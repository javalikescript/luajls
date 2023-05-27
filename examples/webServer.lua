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
-- https://www.npmjs.com/package/http-server

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
    stop = {
      type = 'object',
      additionalProperties = false,
      properties = {
        enabled = {
          title = 'Enables stop',
          type = 'boolean',
          default = false,
        },
        path = {
          title = 'The HTTP path to stop the server',
          pattern = '^/%w+$',
          type = 'string',
          default = '/STOP'
        },
      }
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
      title = 'The file permissions, use "rlw" to enable file upload',
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
        },
        extension = {
          title = 'The cipher extension',
          type = 'string',
          default = 'enc',
        },
        path = {
          title = "The HTTP path for key modification",
          type = "string",
          pattern = '^/%w+$',
          default = '/KEY',
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
    wsp = 'websocket.path',
    p = 'port',
    r = 'permissions',
    stop = 'stop.enabled',
    c = 'cipher.enabled',
    s = 'secure.enabled',
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

do
  local LogHttpFilter = require('jls.net.http.filter.LogHttpFilter')
  httpServer:addFilter(LogHttpFilter:new())
end

local handler
local htmlHeaders = {}

if config.webdav then
  local WebDavHttpHandler = require('jls.net.http.handler.WebDavHttpHandler')
  handler = WebDavHttpHandler:new(config.dir, config.permissions)
else
  handler = FileHttpHandler:new(config.dir, config.permissions)
end

if config.cipher and config.cipher.enabled then
  local SessionHttpFilter = require('jls.net.http.filter.SessionHttpFilter')
  local FileDescriptor = require('jls.io.FileDescriptor')
  local Codec = require('jls.util.Codec')
  local base64 = Codec.getInstance('base64', 'safe', false)
  local headerFormat = '>c2I8I8'
  local headerSize = string.packsize(headerFormat)
  local extension = config.cipher.extension
  httpServer:addFilter(SessionHttpFilter:new())
  httpServer:createContext(config.cipher.path, function(exchange)
    if HttpExchange.methodAllowed(exchange, 'PUT') then
      local session = exchange:getSession()
      local key = exchange:getRequest():getBody()
      if key == '' then
        session:setAttribute('cipher')
        session:setAttribute('mdCipher')
      else
        session:setAttribute('cipher', Codec.getInstance('cipher', config.cipher.alg, key))
        session:setAttribute('mdCipher', Codec.getInstance('cipher', 'aes256', key))
      end
      HttpExchange.ok(exchange)
    end
  end)
  table.insert(htmlHeaders, [[<script>
function setKey(key) {
  if (typeof key === 'string') {
    fetch(']]..config.cipher.path..[[', {
      method: "PUT",
      body: key
    }).then(function() {
      window.location.reload();
    });
  }
}
</script>
<a href="#" onclick="setKey(window.prompt('Enter the new cipher key?'))" title="Set the cipher key">[&#x1F511;]</a>
]])
  local function generateEncName(mdCipher, name)
    -- the same plain name must result to the same encoded name
    return base64:encode(mdCipher:encode(name))..'.'..extension
  end
  local function readEncFileMetadata(mdCipher, encFile)
    local parts = strings.split(encFile:getName(), '.', true)
    if #parts == 2 and parts[2] == extension then
      local cname = base64:decodeSafe(parts[1])
      if cname then
        local name = mdCipher:decodeSafe(cname)
        if name then
          return {
            name = name,
            size = encFile:length() - headerSize, -- possibly incorrect
            time = encFile:lastModified(),
          } -- we could read the header to check the signature and get the size
        end
      end
    end
  end
  local function getEncFileMetadata(mdCipher, file, full)
    local dir = file:getParentFile()
    if dir then
      local name = file:getName()
      local encFile = File:new(dir, generateEncName(mdCipher, name))
      if encFile:isFile() then
        local md = {
          name = name,
          time = encFile:lastModified(),
          encFile = encFile,
        }
        if not full then
          return md
        end
        local fd = FileDescriptor.openSync(encFile, 'r')
        if fd then
          local header = fd:readSync(headerSize)
          fd:closeSync()
          if header then
            local sig, size, salt = string.unpack(headerFormat, header)
            if sig == 'EC' then
              md.size = size
              md.salt = salt
              return md
            end
          end
        end
      end
    end
  end
  local function getIv(salt, ctr)
    return string.pack('>I8I8', salt, ctr or 0)
  end

  local fs = handler:getFileSystem()
  handler:setFileSystem({
    getFileMetadata = function(exchange, file)
      local mdCipher = exchange:getSession():getAttribute('mdCipher')
      if mdCipher and not file:isDirectory() then
        return getEncFileMetadata(mdCipher, file, true)
      end
      return fs.getFileMetadata(exchange, file)
    end,
    listFileMetadata = function(exchange, dir)
      local mdCipher = exchange:getSession():getAttribute('mdCipher')
      if mdCipher and dir:isDirectory() then
        local files = {}
        for _, file in ipairs(dir:listFiles()) do
          local md
          if file:isDirectory() then
            md = fs.getFileMetadata(exchange, file)
            md.name = file:getName()
          else
            md = readEncFileMetadata(mdCipher, file)
          end
          if md then
            table.insert(files, md)
          end
        end
        return files
      end
      return fs.listFileMetadata(exchange, dir)
    end,
    createDirectory = fs.createDirectory,
    copyFile = function(exchange, file, destFile)
      local mdCipher = exchange:getSession():getAttribute('mdCipher')
      if mdCipher then
        local md = getEncFileMetadata(mdCipher, file)
        if md then
          file = md.encFile
          destFile = File:new(destFile:getParent(), generateEncName(mdCipher, destFile:getName()))
        end
      end
      return fs.copyFile(exchange, file, destFile)
    end,
    renameFile = function(exchange, file, destFile)
      local mdCipher = exchange:getSession():getAttribute('mdCipher')
      if mdCipher then
        local md = getEncFileMetadata(mdCipher, file)
        if md then
          return md.encFile:renameTo(File:new(file:getParent(), generateEncName(mdCipher, destFile:getName())))
        end
      end
      return fs.renameFile(exchange, file, destFile)
    end,
    deleteFile = function(exchange, file, recursive)
      local mdCipher = exchange:getSession():getAttribute('mdCipher')
      if mdCipher then
        local md = getEncFileMetadata(mdCipher, file)
        if md then
          file = md.encFile
        end
      end
      return fs.deleteFile(exchange, file, recursive)
    end,
    setFileStreamHandler = function(exchange, file, sh, md, offset, length)
      local cipher = exchange:getSession():getAttribute('cipher')
      logger:fine('setFileStreamHandler(..., %s, %s)', offset, length)
      if cipher then
        if not (md and md.encFile and md.salt) then
          error('metadata are missing')
        end
        -- curl -o file -r 0- http://localhost:8000/file
        sh, offset, length = cipher:decodeStreamPart(sh, getIv(md.salt), offset, length)
        logger:fine('cipher:decodeStreamPart(0x%x) => %s, %s', md.salt, offset, length)
        offset = headerSize + (offset or 0)
        file = md.encFile
      end
      fs.setFileStreamHandler(exchange, file, sh, md, offset, length)
    end,
    getFileStreamHandler = function(exchange, file, ...)
      local cipher = exchange:getSession():getAttribute('cipher')
      local mdCipher = exchange:getSession():getAttribute('mdCipher')
      if cipher and mdCipher then
        local size = exchange:getRequest():getContentLength()
        if not size then
          error('content length is missing')
        end
        local encFile = File:new(file:getParent(), generateEncName(mdCipher, file:getName()))
        local sh = fs.getFileStreamHandler(exchange, encFile, ...)
        local salt = math.random(0, 0xffffffff)
        sh:onData(string.pack(headerFormat, 'EC', size, salt))
        logger:fine('cipher:encodeStreamPart(%d, 0x%x)', size, salt)
        return cipher:encodeStreamPart(sh, getIv(salt))
      end
      return fs.getFileStreamHandler(exchange, file, ...)
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
    logger:fine('WebSocket closed (%s)', webSocket)
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
    logger:info('Generate certificate %s and associated private key %s', certFile:getPath(), pkeyFile:getPath())
  else
    local cert = secure.readCertificate(certFile:readAll())
    local isValid, notbefore, notafter = cert:validat()
    local notafterDate = Date:new(notafter:get() * 1000)
    local notafterText = notafterDate:toISOString(true)
    logger:info('Using certificate %s valid until %s', certFile:getPath(), notafterText)
    if not isValid then
      logger:warn('The certificate is no more valid since %s', notafterText)
    end
  end

  local httpSecureServer = HttpServer.createSecure({
    certificate = certFile:getPath(),
    key = pkeyFile:getPath()
  })
  httpSecureServer:bind(config['bind-address'], config.secure.port):next(function()
    logger:info('HTTPS bound to "%s" on port %d', config['bind-address'], config.secure.port)
    stopPromise:next(function()
      logger:info('Closing HTTP secure server')
      httpSecureServer:close()
    end)
  end, function(err)
    logger:warn('Cannot bind HTTP to "%s" on port %d due to %s', config['bind-address'], config.secure.port, err)
  end)
  httpSecureServer:setParent(httpServer)
end

if config.stop.enabled then
  httpServer:createContext(config.stop.path, function(exchange)
    if HttpExchange.methodAllowed(exchange, 'POST') then
      event:setTimeout(stopCallback)
      HttpExchange.ok(exchange)
    end
  end)
  table.insert(htmlHeaders, [[<script>
function stopServer() {
  fetch(']]..config.stop.path..[[', {
    method: "POST"
  }).then(function() {
    window.location = 'about:blank';
  });
}
</script>
<a href="#" onclick="stopServer()" title="Stop the server">[&#x2715;]</a>
]])
end

if #htmlHeaders > 0 then
  local appendDirectoryHtmlBody = handler.appendDirectoryHtmlBody
  function handler:appendDirectoryHtmlBody(exchange, buffer, files)
    buffer:append('<div style="right: 2rem; position: absolute;">')
    for _, value in ipairs(htmlHeaders) do
      buffer:append(value)
    end
    buffer:append('</div>')
    return appendDirectoryHtmlBody(self, exchange, buffer, files)
  end
end

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
