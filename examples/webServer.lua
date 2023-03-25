local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local strings = require('jls.util.strings')
local tables = require('jls.util.tables')
local Map = require('jls.util.Map')
local List = require('jls.util.List')

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
    webview = {
      type = 'object',
      additionalProperties = false,
      properties = {
        enabled = {
          title = 'Enables WebView browser',
          type = 'boolean',
          default = false,
        },
        debug = {
          title = 'Enables WebView debug',
          type = 'boolean',
          default = false,
        },
      }
    },
    webdav = {
      title = 'Use the WebDAV protocol',
      type = 'boolean',
      default = false
    },
    websocket = {
      type = 'object',
      additionalProperties = false,
      properties = {
        enabled = {
          title = 'Enables WebSocket echo',
          type = 'boolean',
          default = false,
        },
        path = {
          title = 'The WebSocket path',
          type = 'string',
          default = '/WS/'
        },
      }
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
          title = 'Enables file decryption/encryption on the fly',
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
    secure = {
      type = 'object',
      additionalProperties = false,
      properties = {
        enabled = {
          title = 'Enable HTTPS',
          type = 'boolean',
          default = false
        },
        port = {
          type = 'integer',
          default = 8443,
          minimum = 0,
          maximum = 65535,
        },
        commonName = {
          title = "The server common name",
          type = "string",
          default = "localhost"
        },
        certificate = {
          title = "The certificate file",
          type = "string",
          default = "cer.pem"
        },
        key = {
          title = "The key file",
          type = "string",
          default = "key.pem"
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
    wv = 'webview.enabled',
    wvd = 'webview.debug',
    dav = 'webdav',
    ws = 'websocket.enabled',
    p = 'port',
    r = 'permissions',
    c = 'cipher.enabled',
    s = 'secure.enabled',
    kf = 'cipher.keyFile',
    k = 'cipher.key',
    ll = 'log-level',
  },
  schema = CONFIG_SCHEMA
})

logger:setLevel(config['log-level'])

local stopPromise, stopCallback = Promise.createWithCallback()

local httpServer = HttpServer:new()
httpServer:bind(config['bind-address'], config.port):next(function()
  logger:info('HTTP server bound to "%s" on port %d', config['bind-address'], config.port)
  stopPromise:next(function()
    logger:info('Closing HTTP server')
    httpServer:close()
  end)
  if config.webview.enabled then
    local browserScript = File:new('examples/browser.lua')
    if browserScript:exists() then
      local ProcessBuilder = require('jls.lang.ProcessBuilder')
      local ProcessHandle = require('jls.lang.ProcessHandle')
      local lua = ProcessHandle.getExecutablePath()
      local url = string.format('http://localhost:%d', config.port)
      local args = {lua, browserScript:getPath(), url, '-ll', config['log-level']}
      if config.webview.debug then
        table.insert(args, '-d')
      end
      local pb = ProcessBuilder:new(args)
      pb:setRedirectOutput(system.output)
      pb:setRedirectError(system.error)
      logger:info('Starting WebView on %s', url)
      logger:fine('Command is %s', table.concat(args, ' '))
      local ph = pb:start()
      stopPromise:next(function()
        logger:info('Stopping WebView')
        ph:destroy()
      end)
      ph:ended():next(function(code)
        logger:info('WebView closed (%s)', code)
        stopCallback()
      end)
    else
      print('browser script not found', browserScript:getPath())
    end
  end
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
  local Codec = require('jls.util.Codec')

  local extension = config.cipher.extension
  local key
  if config.cipher.keyFile then
    local opensslLib = require('openssl')
    local keyFile = File:new(config.cipher.keyFile)
    if keyFile:isFile() then
      key = keyFile:readAll()
    else
      local info = opensslLib.cipher.get(config.cipher.alg):info()
      key = opensslLib.random(info and info.key_length or 512, true)
      keyFile:write(key)
      print('Cipher key generated in '..keyFile:getPath())
    end
  else
    key = config.cipher.key or 'secret'
  end

  local cipher = Codec.getInstance('cipher', config.cipher.alg, key)
  local mdCipher = Codec.getInstance('cipher', 'aes256', key)
  local deflate = false --Codec.getInstance('deflate', -15)
  local base64 = Codec.getInstance('base64', 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_', false)

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
    local plain = strings.encodeVariableByteInteger(md.size)..md.name
    if deflate then
      plain = deflate:encode(plain)
    end
    return base64:encode(mdCipher:encode(plain))..'.'..extension
  end

  local function try(status, ...)
    if status == true then
      return ...
    end
    return nil, ...
  end
  local function readEncFileMetadata(encFile, full)
    local name = string.sub(encFile:getName(), 1, -5)
    local content = try(pcall(base64.decode, base64, name))
    if content then
      local plain = mdCipher:decode(content)
      if plain then
        if deflate then
          plain = deflate:decode(plain)
        end
        local size, offset = strings.decodeVariableByteInteger(plain)
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
        sh, offset, length = cipher:decodeStreamPart(sh, nil, offset, length)
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
      return cipher:encodeStreamPart(sh)
    end,
  })
end

httpServer:createContext('/?(.*)', handler)

local scriptDir = File:new(arg[0] or './na.lua'):getAbsoluteFile():getParentFile()
local faviconFile = File:new(scriptDir, 'favicon.ico')
httpServer:createContext('/favicon.ico', function(exchange)
  HttpExchange.ok(exchange, faviconFile:readAll(), FileHttpHandler.guessContentType(faviconFile:getName()))
end)

if config.websocket.enabled then
  local WebSocket = require('jls.net.http.WebSocket')
  local websockets = {}
  local function onWebSocketClose(webSocket)
    logger:fine('WebSocket closed '..tostring(webSocket))
    List.removeFirst(websockets, webSocket)
  end
  httpServer:createContext(config.websocket.path, Map.assign(WebSocket.UpgradeHandler:new(), {
    onOpen = function(_, webSocket, exchange)
      table.insert(websockets, webSocket)
      webSocket.onClose = onWebSocketClose
      function webSocket:onTextMessage(payload)
        for _, ws in ipairs(websockets) do
          if ws ~= webSocket then
            ws:sendTextMessage(payload)
          end
        end
      end
      webSocket:readStart()
    end
  }))
end

if config.secure.enabled then
  local secure = require('jls.net.secure')
  local Date = require('jls.util.Date')

  local certFile = File:new(config.secure.certificate)
  local pkeyFile = File:new(config.secure.key)
  if not certFile:exists() or not pkeyFile:exists() then
    local cacert, pkey = secure.createCertificate({
      commonName = config.secure.commonName
    })
    local cacertPem  = cacert:export('pem')
    local pkeyPem  = pkey:export('pem')
    certFile:write(cacertPem)
    pkeyFile:write(pkeyPem)
    logger:info('Generate certificate '..certFile:getPath()..' and associated private key '..pkeyFile:getPath())
  else
    local cert = secure.readCertificate(certFile:readAll())
    local isValid, notbefore, notafter = cert:validat()
    local notafterDate = Date:new(notafter:get() * 1000)
    local notafterText = notafterDate:toISOString(true)
    logger:info('Using certificate '..certFile:getPath()..' valid until '..notafterText)
    if not isValid then
      logger:warn('The certificate is no more valid since '..notafterText)
    end
  end

  local httpSecureServer = HttpServer.createSecure({
    certificate = certFile:getPath(),
    key = pkeyFile:getPath()
  })
  httpSecureServer:bind(config['bind-address'], config.secure.port):next(function()
    logger:info('HTTPS bound to "'..tostring(config['bind-address'])..'" on port '..tostring(config.secure.port))
    stopPromise:next(function()
      logger:info('Closing HTTP secure server')
      httpSecureServer:close()
    end)
  end, function(err)
    logger:warn('Cannot bind HTTP to "'..tostring(config['bind-address'])..'" on port '..tostring(config.secure.port)..' due to '..tostring(err))
  end)
  httpSecureServer:setParentContextHolder(httpServer)
end

httpServer:createContext('/STOP', function(exchange)
  event:setTimeout(stopCallback)
  HttpExchange.ok(exchange)
end)

do
  local hasLuv, luvLib = pcall(require, 'luv')
  if hasLuv then
    local signal = luvLib.new_signal()
    luvLib.ref(signal)
    stopPromise:next(function()
      logger:info('Unreference signal')
      luvLib.unref(signal)
    end)
    luvLib.signal_start(signal, 'sigint', function()
      stopCallback()
    end)
  end
end

event:loop()
logger:info('HTTP server closed')
