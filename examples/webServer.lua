require('jls.lang.protectedCallLog')
local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local Path = require('jls.io.Path')
local File = require('jls.io.File')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local tables = require('jls.util.tables')
local Map = require('jls.util.Map')

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
      title = 'The binding address',
      type = 'string',
      default = '::'
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

local VIEW_SCRIPT = [[<script>
function viewFile(e) {
  var href = e.target.previousElementSibling.getAttribute('href');
  window.location = '/view' + window.location.pathname + href;
}
</script>
]]

local function getExtension(name)
  local extension = Path.extractExtension(name)
  return extension and string.lower(extension) or ''
end

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
  local cipher = require('jls.util.codec.cipher')
  local strings = require('jls.util.strings')
  local Struct = require('jls.util.Struct')

  local struct = Struct:new({
    {name = 'name', type = 's4'},
    {name = 'size', type = 'I8'},
    {name = 'time', type = 'I8'},
  }, '<')
  local ivf = '>I16'
  local mdAlg = 'aes128'
  local alg = config.cipher.alg
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

  local function formatInt(i, s)
    return strings.formatInteger(math.abs(i), s or 64)
  end
  local function generateEncName(name, time)
    return formatInt(strings.hash(name))..formatInt(time)..formatInt(math.random(0, 64^4))..'.enc'
  end
  local function getEncFileMetadata(encFile)
    return File:new(encFile:getParentFile(), encFile:getBaseName()..'.emd')
  end
  local function readEncFileMetadata(encFile, full)
    local file = getEncFileMetadata(encFile)
    local content = file:readAll()
    if content then
      local plain = cipher.decode(content, mdAlg, key)
      if plain then
        local md = struct:fromString(plain)
        if full then
          md.encFile = encFile
          md.file = file
        end
        return md
      end
    end
  end
  local function writeEncFileMetadata(encFile, md)
    local file = getEncFileMetadata(encFile)
    file:write(cipher.encode(struct:toString(md), mdAlg, key))
  end
  local function getFileMetadata(file, full)
    local dir = file:getParentFile()
    if dir and dir:isDirectory() then
      local name = file:getName()
      for _, f in ipairs(dir:listFiles()) do
        if f:getExtension() == 'enc' then
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
        elseif file:getExtension() == 'enc' then
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
        local name = generateEncName(destFile:getName(), md.time)
        local encFile = File:new(destFile:getParent(), name)
        md.name = destFile:getName()
        writeEncFileMetadata(encFile, md)
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
        writeEncFileMetadata(md.encFile, md)
        return true
      end
    end,
    deleteFile = function(file, recursive)
      if file:isDirectory() then
        return fs.deleteFile(file, recursive)
      end
      local md = getFileMetadata(file, true)
      if md then
        return fs.deleteFile(md.encFile, recursive) and fs.deleteFile(md.file, recursive)
      end
      return true
    end,
    setFileStreamHandler = function(httpExchange, file, sh, md, offset, length)
      logger:fine('setFileStreamHandler('..tostring(offset)..', '..tostring(length)..')')
      if md and md.encFile then
        file = md.encFile
        sh, offset, length = cipher.decodeStreamPart(sh, alg, key, nil, offset, length)
        if logger:isLoggable(logger.FINE) then
          logger:fine('ciipher.decodeStreamPart() => '..tostring(offset)..', '..tostring(length))
        end
      end
      fs.setFileStreamHandler(httpExchange, file, sh, md, offset, length)
    end,
    getFileStreamHandler = function(httpExchange, file)
      local time = system.currentTimeMillis()
      local name = generateEncName(file:getName(), time)
      local encFile = File:new(file:getParent(), name)
      local sh = fs.getFileStreamHandler(httpExchange, encFile)
      local size = httpExchange:getRequest():getContentLength()
      local md = {
        name = file:getName(),
        size = size or 0,
        time = time,
      }
      if size then
        writeEncFileMetadata(encFile, md)
      else
        sh = PromiseStreamHandler:new(sh)
        sh:getPromise():next(function(s)
          logger:fine('getFileStreamHandler('..file:getName()..') size: '..tostring(size))
          md.size = s
          writeEncFileMetadata(encFile, md)
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
