local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpHandler = require('jls.net.http.HttpHandler')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local Url = require('jls.net.Url')
local tables = require('jls.util.tables')
local Map = require('jls.util.Map')
local List = require('jls.util.List')
local strings = require('jls.util.strings')

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
      title = 'Enables stop',
      type = 'boolean',
      default = false,
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
    html = {
      title = 'Use HTML to list directories',
      type = 'boolean',
      default = true
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
          pattern = '^/.+$',
          default = '/WS/'
        },
        uiPath = {
          title = 'The WebSocket UI path',
          type = 'string',
          pattern = '^/.+$',
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
          pattern = '^%w+$',
          default = 'enc',
        },
        filter = {
          title = 'Filters files with the cipher extension',
          type = 'boolean',
          default = true,
        }
      }
    },
    h2 = {
      title = 'Use HTTP/2',
      type = 'boolean',
      default = false
    },
    module = {
      title = 'A Lua module to load',
      pattern = '%.lua$',
      type = 'string',
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
    c = 'cipher.enabled',
    s = 'secure.enabled',
    m = 'module',
    ll = 'log-level',
  },
  schema = CONFIG_SCHEMA
})

logger:setLevel(config['log-level'])

local SCRIPT = [[
function setKey(key) {
  if (typeof key === 'string') {
    fetch(location.pathname + '?key', {
      credentials: "same-origin",
      method: "PUT",
      body: key
    }).then(function() {
      window.location.reload();
    });
  }
}
function askKey(e) {
  setKey(window.prompt('Enter the new cipher key?'));
  stopEvent(e);
}
function createDir(name) {
  if (typeof name === 'string' && name) {
    fetch(name + '/', {
      credentials: "same-origin",
      method: "PUT"
    }).then(function() {
      window.location.reload();
    });
  }
}
function askDir(e) {
  createDir(window.prompt('Enter the folder name?'));
  stopEvent(e);
}
function stopServer(e) {
  if (window.confirm('Stop the server?')) {
    fetch(location.pathname + '?stop', {
      credentials: "same-origin",
      method: "POST"
    }).then(function() {
      document.body.innerHTML = '<p>bye</p>';
    });
  }
  stopEvent(e);
}
]]

local stopPromise, stopCallback = Promise.withCallback()

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
local queryHandler = {}

if config.webdav then
  local WebDavHttpHandler = require('jls.net.http.handler.WebDavHttpHandler')
  handler = WebDavHttpHandler:new(config.dir, config.permissions)
elseif config.html then
  local HtmlFileHttpHandler = require('jls.net.http.handler.HtmlFileHttpHandler')
  handler = HtmlFileHttpHandler:new(config.dir, config.permissions)
else
  local d = File:new(config.dir)
  if d:isFile() and d:getExtension() == 'zip' then
    logger:info('ZIP file detected')
    local ZipFileHttpHandler = require('jls.net.http.handler.ZipFileHttpHandler')
    handler = ZipFileHttpHandler:new(d)
  else
    handler = FileHttpHandler:new(config.dir, config.permissions)
  end
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
  queryHandler['key'] = function(exchange)
    if HttpExchange.methodAllowed(exchange, 'PUT') then
      local session = exchange:getSession()
      local request = exchange:getRequest()
      request:bufferBody()
      return request:consume():next(function()
        local key = exchange:getRequest():getBody()
        if key == '' then
          session:setAttribute('cipher')
          session:setAttribute('mdCipher')
        else
          session:setAttribute('cipher', Codec.getInstance('cipher', config.cipher.alg, key))
          session:setAttribute('mdCipher', Codec.getInstance('cipher', 'aes256', key))
        end
        HttpExchange.ok(exchange)
      end)
    end
    return false
  end
  table.insert(htmlHeaders, '<a href="#" onclick="askKey(event)" class="action" title="Set the cipher key">&#x1F511;</a>')
  local function generateEncName(mdCipher, name)
    -- the same plain name must result to the same encoded name
    return base64:encode(mdCipher:encode('\7'..name))..'.'..extension
  end
  local function getNameExt(name)
    return string.match(name, '^([%w%-_%+/]+)%.(%w+)$')
  end
  local function readEncFileMetadata(mdCipher, encFile)
    local bname, ext = getNameExt(encFile:getName())
    if bname and ext == extension then
      local cname = base64:decodeSafe(bname)
      if cname then
        local name = mdCipher:decodeSafe(cname)
        if name and string.byte(name, 1) == 7 then
          return {
            name = string.sub(name, 2),
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
      local files = fs.listFileMetadata(exchange, dir)
      if config.cipher.filter then
        return List.filter(files, function(md)
          local _, ext = getNameExt(md.name)
          return ext ~= extension
        end)
      end
      return files
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

if config.websocket.enabled then
  local WebSocket = require('jls.net.http.WebSocket')
  local websockets = {}
  local function onWebSocketClose(webSocket)
    logger:fine('WebSocket closed (%s)', webSocket)
    List.removeFirst(websockets, webSocket)
  end
  local wsPath = Url.encodeURI(config.websocket.path)
  httpServer:createContext(strings.escape(wsPath), Map.assign(WebSocket.UpgradeHandler:new(), {
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
  if config.websocket.uiPath then
    local wsUiPath = Url.encodeURI(config.websocket.uiPath)
    httpServer:createContext(strings.escape(wsUiPath), function(exchange)
      local response = exchange:getResponse()
      response:setBody([[<!DOCTYPE html>
<html>
  <body>
    <p>Check the console</p>
    <button onclick="webSocket.send('Hello')" title="Send Hello to others">Send</button>
  </body>
  <script>
  var protocol = location.protocol.replace('http', 'ws');
  var url = protocol + '//' + location.host + ']]..wsPath..[[';
  var webSocket = new WebSocket(url);
  webSocket.onmessage = function(event) {
    console.log('webSocket message', event.data);
  };
  webSocket.onopen = function() {
    console.log('WebSocket opened at ' + url);
  };
  </script>
</html>
]])
    end)
  end
end

if config.module then
  logger:info('Loading module %s', config.module)
  local env = setmetatable({}, { __index = _G })
  local scriptFn = assert(loadfile(config.module, 't', env))
  scriptFn(httpServer, stopPromise)
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
    key = pkeyFile:getPath(),
    alpnSelectProtos = config.h2 and {'h2', 'http/1.1'} or nil,
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

if string.match(config.permissions, '[wc]') then
  table.insert(htmlHeaders, '<a href="#" onclick="askDir(event)" class="action" title="Create a folder">&#x1F4C2;</a>')
end

if config.stop then
  queryHandler['stop'] = function(exchange)
    if HttpExchange.methodAllowed(exchange, 'POST') then
      event:setTimeout(stopCallback)
      --exchange:getResponse():setCookie('jls-session-id', '-', {'expires=Thu, 01 Jan 1970 00:00:00 GMT'})
      HttpExchange.ok(exchange)
    end
    return false
  end
  table.insert(htmlHeaders, '<a href="#" onclick="stopServer(event)" class="action" title="Stop the server">&#x2715;</a>')
end

if #htmlHeaders > 0 then
  local appendDirectoryHtmlBody = handler.appendDirectoryHtmlBody
  function handler:appendDirectoryHtmlBody(exchange, buffer, files)
    buffer:append('<span style="right: 1rem; position: absolute; z-index: +1;">')
    for _, value in ipairs(htmlHeaders) do
      buffer:append(value)
    end
    buffer:append('</span>')
    return appendDirectoryHtmlBody(self, exchange, buffer, files)
  end
end

if handler.getQuery then
  local content = handler:getQuery('script.js')
  if content then
    handler:setQuery('script.js', content..SCRIPT)
  end
end

local rootHandler = handler
if next(queryHandler) then
  rootHandler = HttpHandler:new(function(_, exchange)
    local query = exchange:getRequest():getTargetQuery()
    local filter = queryHandler[query]
    if filter then
      return filter(exchange)
    end
    return handler:handle(exchange)
  end)
end

httpServer:createContext('/?(.*)', rootHandler)

local scriptDir = File:new(system.getArguments()[0] or './na.lua'):getAbsoluteFile():getParentFile()
local faviconFile = File:new(scriptDir, 'favicon.ico')
httpServer:createContext('/favicon.ico', function(exchange)
  HttpExchange.ok(exchange, faviconFile:readAll(), FileHttpHandler.guessContentType(faviconFile:getName()))
end)

do
  local hasLuv, luvLib = pcall(require, 'luv')
  if hasLuv then
    local signal = luvLib.new_signal()
    luvLib.ref(signal)
    stopPromise:next(function()
      logger:fine('Unreference signal')
      luvLib.unref(signal)
    end)
    luvLib.signal_start_oneshot(signal, 'sigint', function()
      stopCallback()
    end)
  end
end

event:loop()
logger:info('HTTP server closed')
