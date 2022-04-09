local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local File = require('jls.io.File')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpHandler = require('jls.net.http.HttpHandler')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local ZipFileHttpHandler = require('jls.net.http.handler.ZipFileHttpHandler')
local ProxyHttpHandler = require('jls.net.http.handler.ProxyHttpHandler')
local WebDavHttpHandler = require('jls.net.http.handler.WebDavHttpHandler')
local URL = require('jls.net.URL')
local tables = require('jls.util.tables')
local base64 = require('jls.util.base64')
local Scheduler = require('jls.util.Scheduler')
local EventPublisher = require("jls.util.EventPublisher")

-- see https://openjdk.java.net/jeps/408

local function cipherFileHttpHandler(handler, endpoint)
  local PromiseStreamHandler = require('jls.io.streams.PromiseStreamHandler')
  local cipher = require('jls.util.codec.cipher')
  local strings = require('jls.util.strings')
  local Struct = require('jls.util.Struct')
  local struct = Struct:new({
    {name = 'name', type = 's4'},
    {name = 'size', type = 'I8'},
    {name = 'time', type = 'I8'},
  }, '<')
  local function generateEncName(name, time)
    return strings.formatInteger(math.abs(strings.hash(name)), 64)..strings.formatInteger(time, 64)..strings.formatInteger(math.random(0, math.maxinteger), 64)..'.enc'
  end
  class.modifyInstance(handler, function(fileHttpHandler, super)
    function fileHttpHandler:getEncFileMetadata(encFile)
      return File:new(encFile:getParentFile(), encFile:getBaseName()..'.emd')
    end
    function fileHttpHandler:readEncFileMetadata(encFile)
      local file = self:getEncFileMetadata(encFile)
      local content = file:readAll()
      if content then
        local md = struct:fromString(cipher.decode(content, endpoint.cipher.alg, endpoint.cipher.key))
        logger:fine('readEncFileMetadata('..file:getName()..') '..tables.stringify(md, 2))
        return md
      end
    end
    function fileHttpHandler:writeEncFileMetadata(encFile, md)
      local file = self:getEncFileMetadata(encFile)
      logger:fine('writeEncFileMetadata('..file:getName()..') md: '..tables.stringify(md, 2))
      file:write(cipher.encode(struct:toString(md), endpoint.cipher.alg, endpoint.cipher.key))
    end
    function fileHttpHandler:getFileMetadata(file)
      if file:isDirectory() then
        return super.getFileMetadata(self, file)
      end
      local dir = file:getParentFile()
      if dir and dir:isDirectory() then
        local name = file:getName()
        for _, f in ipairs(dir:listFiles()) do
          if f:getExtension() == 'enc' then
            local md = self:readEncFileMetadata(f)
            if md and md.name == name then
              md.encFile = f
              return md
            end
          end
        end
      end
    end
    function fileHttpHandler:listFiles(dir)
      local files = {}
      for _, file in ipairs(dir:listFiles()) do
        local md
        if file:isDirectory() then
          md = super.getFileMetadata(self, file)
        elseif file:getExtension() == 'enc' then
          md = self:readEncFileMetadata(file)
        end
        if md then
          table.insert(files, md)
        end
      end
      return files
    end
    function fileHttpHandler:deleteFile(file)
      local md = self:getFileMetadata(file)
      if md and md.encFile then
        local mdFile = self:getEncFileMetadata(md.encFile)
        return md.encFile:delete() and mdFile:delete()
      end
      return true
    end
    function fileHttpHandler:setFileStreamHandler(httpExchange, file, sh, md)
      if md and md.encFile then
        file = md.encFile
        sh = cipher.decodeStream(sh, endpoint.cipher.alg, endpoint.cipher.key)
      end
      super.setFileStreamHandler(self, httpExchange, file, sh)
    end
    function fileHttpHandler:getFileStreamHandler(httpExchange, file)
      local time = system.currentTimeMillis()
      local name = generateEncName(file:getName(), time)
      local encFile = File:new(file:getParent(), name)
      local sh = super.getFileStreamHandler(self, httpExchange, encFile)
      local size = httpExchange:getRequest():getContentLength()
      local md = {
        name = file:getName(),
        size = size or 0,
        time = time,
      }
      if size then
        self:writeEncFileMetadata(encFile, md)
      else
        sh = PromiseStreamHandler:new(sh)
        sh:getPromise():next(function(s)
          logger:fine('getFileStreamHandler('..file:getName()..') size: '..tostring(size))
          md.size = s
          self:writeEncFileMetadata(encFile, md)
        end)
      end
      return cipher.encodeStream(sh, endpoint.cipher.alg, endpoint.cipher.key)
    end
  end)
end

local CIPHER_SCHEMA = {
  type = 'object',
  additionalProperties = false,
  properties = {
    enabled = {
      type = 'boolean',
      default = false,
    },
    alg = {
      title = 'The cipher algorithm',
      type = 'string',
      default = 'aes128',
    },
    key = {
      title = 'The secret key',
      type = 'string',
    }
  }
}

local CONFIG_SCHEMA = {
  title = 'HTTP server',
  type = 'object',
  additionalProperties = false,
  properties = {
    config = {
      title = 'The configuration file',
      type = 'string',
      default = 'httpServer.json'
    },
    server = {
      type = 'object',
      additionalProperties = false,
      properties = {
        address = {
          title = 'The binding address',
          type = 'string',
          default = '::'
        },
        port = {
          type = 'integer',
          default = 8080,
          minimum = 0,
          maximum = 65535,
        },
        secure = {
          type = 'object',
          additionalProperties = false,
          properties = {
            enabled = {
              type = 'boolean',
              default = false
            },
          },
        },
      },
    },
    dir = {
      title = 'The root directory to serve',
      type = 'string',
      default = '.'
    },
    scheme = {
      title = 'The scheme',
      type = 'string',
      default = 'file',
      enum = {'file', 'webdav'},
    },
    permissions = {
      title = 'The root directory permissions, use rlw to enable file upload',
      type = 'string',
      default = 'rl'
    },
    cipher = CIPHER_SCHEMA,
    endpoints = {
      type = 'array',
      items = {
        type = 'object',
        required = {'path', 'target'},
        additionalProperties = false,
        properties = {
          path = {
            title = 'The path where the endpoint is available',
            type = 'string',
          },
          target = {
            title = 'The endpoint URI target',
            description = 'The URI with a supported scheme: file, zip, webdav, http, https, data, lua',
            type = 'string',
          },
          permissions = {
            title = 'The endpoint permissions',
            type = 'string',
          },
          cipher = CIPHER_SCHEMA
        }
      },
    },
    scheduler = {
      type = 'object',
      additionalProperties = false,
      properties = {
        enabled = {
          type = 'boolean',
          default = true,
        },
        heartbeat = {
          type = 'number',
          default = 15,
          multipleOf = 0.1,
          minimum = 0.5,
          maximum = 3600,
        },
        refresh = {
          title = 'The refresh scheduler recurrence',
          type = 'string',
          default = '*/15 * * * *',
        },
      },
    },
    loglevel = {
      title = 'The log level',
      type = 'string',
      default = 'warn',
      enum = {'error', 'warn', 'info', 'config', 'fine', 'finer', 'finest', 'debug', 'all'}
    }
  }
}

local config = tables.createArgumentTable(system.getArguments(), {
  configPath = 'config',
  emptyPath = 'dir',
  helpPath = 'help',
  schema = CONFIG_SCHEMA
})

logger:setLevel(config.loglevel)

local scriptDir = File:new(arg[0] or './na.lua'):getParentFile()
local faviconFile = File:new(scriptDir, 'favicon.ico')

local endpoints = config.endpoints
if not endpoints or #endpoints == 0 then
  endpoints = {
    {path = '/admin/stop', target = 'lua:event:publishEvent("terminate")'},
    {path = '/favicon.ico', target = 'file:'..faviconFile:getPath()},
    {path = '/files/?', target = config.scheme..':'..config.dir, permissions = config.permissions, cipher = config.cipher},
    {path = '/', target = [[data:text/html;charset=utf-8,<!DOCTYPE html>
<html><head><title>Welcome</title></head><body>
<p>Welcome !</p>
<p><a href="#" onclick="fetch('admin/stop', {method: 'POST'})">Stop the server</a></p>
<p><a href="files/">Explore files</a></p>
</body></html>]]},
  }
end

local eventPublisher = EventPublisher:new()

local httpServer = HttpServer:new()
httpServer:bind(config.server.address, config.server.port):next(function()
  logger:info('HTTP server bound to "'..config.server.address..'" on port '..tostring(config.server.port))
end, function(err) -- could failed if address is in use or hostname cannot be resolved
  print('Cannot bind HTTP server, '..tostring(err))
  os.exit(1)
end)

eventPublisher:subscribeEvent('terminate', function()
  logger:info('Closing HTTP server')
  httpServer:close()
end)

if config.scheduler and config.scheduler.enabled then
  local scheduler = Scheduler:new()
  if config.scheduler.refresh then
    scheduler:schedule(config.scheduler.refresh, function(t)
      logger:info('Refreshing')
      eventPublisher:publishEvent('refresh')
    end)
  end
  local schedulerIntervalId = event:setInterval(function()
    scheduler:runTo()
  end, math.floor(config.scheduler.heartbeat * 1000))
  eventPublisher:subscribeEvent('terminate', function()
    logger:info('Closing event publisher')
    event:clearInterval(schedulerIntervalId)
  end)
end

for _, endpoint in ipairs(endpoints) do
  local scheme, specificPart = string.match(endpoint.target, '^([%w][%w%+%.%-]*):(.*)$')
  --local targetUri = URL.fromString(endpoint.target)
  if scheme then
    if scheme == 'file' or scheme == 'zip' or scheme == 'webdav' then
      local targetFile = File:new(specificPart)
      if targetFile:exists() then
        local handler, path
        if scheme == 'zip' and targetFile:isFile() then
          handler = ZipFileHttpHandler:new(targetFile)
        elseif scheme == 'webdav' and targetFile:isDirectory() then
          handler = WebDavHttpHandler:new(targetFile, endpoint.permissions)
        elseif scheme == 'file' and targetFile:isDirectory() then
          handler = FileHttpHandler:new(targetFile, endpoint.permissions)
        elseif scheme == 'file' and targetFile:isFile() then
          handler = HttpHandler:new(function(_, exchange)
            HttpExchange.ok(exchange, targetFile:readAll(), FileHttpHandler.guessContentType(targetFile:getName()))
          end)
          path = endpoint.path
        end
        if not path then
          path = endpoint.path..'(.*)'
        end
        if handler then
          if endpoint.cipher and endpoint.cipher.enabled then
            if FileHttpHandler:isInstance(handler) then
              cipherFileHttpHandler(handler, endpoint)
            else
              logger:warn('cannot cipher endpoint target "'..tostring(endpoint.path)..'"')
            end
          end
          logger:fine('create context "'..tostring(path)..'" using '..tostring(class.getName(handler:getClass())))
          httpServer:createContext(path, handler)
        else
          logger:warn('invalid endpoint target "'..tostring(endpoint.target)..'"')
        end
      else
        logger:warn('target endpoint not found "'..targetFile:getPath()..'"')
      end
    elseif scheme == 'http' or scheme == 'https' then
      httpServer:createContext(endpoint.path..'(.*)', ProxyHttpHandler:new():configureReverse(endpoint.target))
    elseif scheme == 'data' then
      -- data:[<media type>[;attribute=value]][;base64],<data>
      local mediaType, body = string.match(specificPart, '^([^,]*),(.*)$')
      if body then
        if mediaType and string.match(mediaType, ';base64$') then
          mediaType = string.gsub(mediaType, ';base64$', '')
          body = base64.decode(body)
        else
          body = URL.decodePercent(body)
        end
        httpServer:createContext(endpoint.path, HttpHandler:new(function(_, exchange)
          HttpExchange.ok(exchange, body, mediaType or 'text/plain;charset=US-ASCII')
        end))
      else
        logger:warn('unsupported data endpoint "'..tostring(specificPart)..'"')
      end
    elseif scheme == 'lua' then
      local handler, err = load('local exchange, event = ...; '..specificPart)
      if handler then
        httpServer:createContext(endpoint.path, HttpHandler:new(function(_, exchange)
          return handler(exchange, eventPublisher)
        end))
      else
        logger:warn('Error "'..tostring(err)..'" while loading: '..tostring(specificPart))
      end
    else
      logger:warn('unsupported endpoint scheme "'..tostring(scheme)..'"')
    end
  else
    logger:warn('unsupported endpoint target "'..tostring(endpoint.target)..'"')
  end
end

event:loop()
logger:info('HTTP server closed')
