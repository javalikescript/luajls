require('jls.lang.protectedCallLog')
local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local File = require('jls.io.File')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local tables = require('jls.util.tables')

-- see https://openjdk.java.net/jeps/408

local CONFIG_SCHEMA = {
  title = 'Web Server',
  type = 'object',
  additionalProperties = false,
  properties = {
    config = {
      title = 'The configuration file',
      type = 'string',
      default = 'webServer.json'
    },
    ['bind-address'] = {
      title = 'The binding address, use :: to bind on any',
      type = 'string',
      default = '127.0.0.1'
    },
    port = {
      type = 'integer',
      default = 8000,
      minimum = 0,
      maximum = 65535,
    },
    dir = {
      title = 'The root directory to serve',
      type = 'string',
      default = '.'
    },
    webdav = {
      title = 'Use the WebDAV protocol',
      type = 'boolean',
      default = false
    },
    permissions = {
      title = 'The file permissions, use rlw to enable file upload',
      type = 'string',
      default = 'rl'
    },
    cipher = {
      type = 'object',
      additionalProperties = false,
      properties = {
        enabled = {
          title = 'Enables file decryption/encryption on the flow',
          type = 'boolean',
          default = false,
        },
        alg = {
          title = 'The cipher algorithm',
          type = 'string',
          default = 'aes-128-ctr',
          -- print("'"..table.concat(require('openssl').cipher.list(), "', '").."'")
        },
        extension = {
          title = 'The cipher extension',
          type = 'string',
          default = 'enc',
        },
        key = {
          title = 'The secret key',
          type = 'string',
        },
        keyFile = {
          title = 'The file containing the secret key',
          type = 'string',
        }
      }
    },
    credentials = {
      title = 'The credentials as name/password pairs for basic authentication',
      type = 'array',
      items = {
        type = 'object',
        properties = {
          name = {
            title = 'The user name',
            type = 'string'
          },
          password = {
            title = 'The user password',
            type = 'string'
          }
        }
      }
    },
    ['log-level'] = {
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
  aliases = {
    h = 'help',
    b = 'bind-address',
    d = 'dir',
    dav = 'webdav',
    p = 'port',
    r = 'permissions',
    c = 'cipher.enabled',
    kf = 'cipher.keyFile',
    k = 'cipher.key',
    ll = 'log-level',
  },
  schema = CONFIG_SCHEMA
})

logger:setLevel(config['log-level'])

local httpServer = HttpServer:new()
httpServer:bind(config['bind-address'], config.port):next(function()
  logger:info('HTTP server bound to "'..config['bind-address']..'" on port '..tostring(config.port))
end, function(err) -- could failed if address is in use or hostname cannot be resolved
  print('Cannot bind HTTP server, '..tostring(err))
  os.exit(1)
end)

if type(config.credentials) == 'table' and next(config.credentials) then
  local BasicAuthenticationHttpFilter = require('jls.net.http.filter.BasicAuthenticationHttpFilter')
  local namePasswordMap = {}
  for _, credential in ipairs(config.credentials) do
    namePasswordMap[credential.name] = credential.password
  end
  httpServer:addFilter(BasicAuthenticationHttpFilter:new(namePasswordMap, 'Web Server'))
end

local handler

if config.webdav then
  local WebDavHttpHandler = require('jls.net.http.handler.WebDavHttpHandler')
  handler = WebDavHttpHandler:new(config.dir, config.permissions)
else
  handler = FileHttpHandler:new(config.dir, config.permissions)
end

if config.cipher and config.cipher.enabled then
  local PromiseStreamHandler = require('jls.io.streams.PromiseStreamHandler')
  local cipher = require('jls.util.cd.cipher')
  local deflate = false -- require('jls.util.cd.deflate')
  local Struct = require('jls.util.Struct')
  local base64 = require('jls.util.cd.base64')
  local alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'

  local struct = Struct:new({
    {name = 'name', type = 's4'},
    {name = 'size', type = 'I8'},
    {name = 'time', type = 'I8'},
  }, '<')
  local mdAlg = 'aes256'
  local alg = config.cipher.alg
  local extension = config.cipher.extension
  local key
  if config.cipher.keyFile then
    local opensslLib = require('openssl')
    local keyFile = File:new(config.cipher.keyFile)
    if keyFile:isFile() then
      key = keyFile:readAll()
    else
      local info = opensslLib.cipher.get(alg):info()
      key = opensslLib.random(info and info.key_length or 512, true)
      keyFile:write(key)
      print('Cipher key generated in '..keyFile:getPath())
    end
  else
    key = config.cipher.key or 'secret'
  end

  httpServer:createContext('/KEY', function(exchange)
    local request = exchange:getRequest()
    if request:getMethod() == 'PUT' then
      key = request:getBody()
      HttpExchange.ok(exchange)
    else
      HttpExchange.methodNotAllowed(exchange)
    end
  end)

  local function generateEncName(md)
    local plain = Struct.encodeVariableByteInteger(md.size)..md.name
    if deflate then
      plain = deflate.encode(plain, nil, -15)
    end
    return base64.encode(cipher.encode(plain, mdAlg, key), alpha, false)..'.'..extension
  end

  local function try(status, ...)
    if status == true then
      return ...
    end
    return nil, ...
  end
  local function readEncFileMetadata(encFile, full)
    local name = string.sub(encFile:getName(), 1, -5)
    local content = try(pcall(base64.decode, name, alpha))
    if content then
      local plain = cipher.decode(content, mdAlg, key)
      if plain then
        if deflate then
          plain = deflate.decode(plain, -15)
        end
        local size, offset = Struct.decodeVariableByteInteger(plain)
        local md = {
          name = string.sub(plain, offset),
          size = size,
          time = encFile:lastModified(),
        }
        if full then
          md.encFile = encFile
        end
        return md
      end
    end
    local file = File:new(encFile:getParentFile(), encFile:getBaseName()..'.emd')
    content = file:readAll()
    if content then
      local plain = cipher.decode(content, 'aes128', key)
      if plain then
        local md = struct:fromString(plain)
        local f = File:new(encFile:getParent(), generateEncName(md))
        if encFile:renameTo(f) then
          logger:warn('The file metadata '..file:getName()..' has been migrated and could be deleted')
          if full then
            md.encFile = f
          end
          return md
        end
      end
    end
  end
  local function getFileMetadata(file, full)
    local dir = file:getParentFile()
    if dir and dir:isDirectory() then
      local name = file:getName()
      for _, f in ipairs(dir:listFiles()) do
        if f:getExtension() == extension then
          local md = readEncFileMetadata(f, full)
          if md and md.name == name then
            return md
          end
        end
      end
    end
  end

  local fs = handler:getFileSystem()
  handler:setFileSystem({
    getFileMetadata = function(file)
      if file:isDirectory() then
        return fs.getFileMetadata(file)
      end
      return getFileMetadata(file, true)
    end,
    listFileMetadata = function(dir)
      local files = {}
      for _, file in ipairs(dir:listFiles()) do
        local md
        if file:isDirectory() then
          md = fs.getFileMetadata(file)
          md.name = file:getName()
        elseif file:getExtension() == extension then
          md = readEncFileMetadata(file)
        end
        if md then
          table.insert(files, md)
        end
      end
      return files
    end,
    createDirectory = fs.createDirectory,
    copyFile = function(file, destFile)
      if file:isDirectory() then
        return fs.copyFile(file, destFile)
      end
      local md = getFileMetadata(file, true)
      if md then
        md.name = destFile:getName()
        local encFile = File:new(destFile:getParent(), generateEncName(md))
        return fs.copyFile(md.encFile, encFile)
      end
    end,
    renameFile = function(file, destFile)
      if file:isDirectory() then
        return fs.renameFile(file, destFile)
      end
      local md = getFileMetadata(file, true)
      if md then
        md.name = destFile:getName()
        return md.encFile:renameTo(File:new(file:getParent(), generateEncName(md)))
      end
    end,
    deleteFile = function(file, recursive)
      if file:isDirectory() then
        return fs.deleteFile(file, recursive)
      end
      local md = getFileMetadata(file, true)
      if md then
        return fs.deleteFile(md.encFile, recursive)
      end
      return true
    end,
    setFileStreamHandler = function(httpExchange, file, sh, md, offset, length)
      logger:fine('setFileStreamHandler('..tostring(offset)..', '..tostring(length)..')')
      if md and md.encFile then
        file = md.encFile
        -- curl -o file -r 0- http://localhost:8000/file
        sh, offset, length = cipher.decodeStreamPart(sh, alg, key, nil, offset, length)
        if logger:isLoggable(logger.FINE) then
          logger:fine('cipher.decodeStreamPart() => '..tostring(offset)..', '..tostring(length))
        end
      end
      fs.setFileStreamHandler(httpExchange, file, sh, md, offset, length)
    end,
    getFileStreamHandler = function(httpExchange, file)
      local time = system.currentTimeMillis()
      local size = httpExchange:getRequest():getContentLength()
      local md = {
        name = file:getName(),
        size = size or 0,
        time = time,
      }
      local encFile = File:new(file:getParent(), generateEncName(md))
      local sh = fs.getFileStreamHandler(httpExchange, encFile)
      if not size then
        sh = PromiseStreamHandler:new(sh)
        sh:getPromise():next(function(s)
          logger:fine('getFileStreamHandler('..file:getName()..') size: '..tostring(size))
          md.size = s
          encFile:renameTo(File:new(file:getParent(), generateEncName(md)))
        end)
      end
      return cipher.encodeStreamPart(sh, alg, key)
    end,
  })
end

httpServer:createContext('/?(.*)', handler)

local scriptDir = File:new(arg[0] or './na.lua'):getAbsoluteFile():getParentFile()
local faviconFile = File:new(scriptDir, 'favicon.ico')
httpServer:createContext('/favicon.ico', function(exchange)
  HttpExchange.ok(exchange, faviconFile:readAll(), FileHttpHandler.guessContentType(faviconFile:getName()))
end)

httpServer:createContext('/STOP', function(exchange)
  event:setTimeout(function()
    logger:info('Closing HTTP server')
    httpServer:close()
  end)
  HttpExchange.ok(exchange)
end)

event:loop()
logger:info('HTTP server closed')
