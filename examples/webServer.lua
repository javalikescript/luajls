local class = require('jls.lang.class')
local event = require('jls.lang.event')
local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local signal = require('jls.lang.signal')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local Path = require('jls.io.Path')
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
      default = 'localhost'
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
  }
}

local config = tables.createArgumentTable(system.getArguments(), {
  configPath = 'config',
  emptyPath = 'dir',
  helpPath = 'help',
  logPath = 'log-level',
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
  local CipherHttpFile = require('jls.net.http.handler.CipherHttpFile')
  local extension = config.cipher.extension
  httpServer:addFilter(SessionHttpFilter:new())
  queryHandler['key'] = function(exchange)
    if HttpExchange.methodAllowed(exchange, 'PUT') then
      local request = exchange:getRequest()
      request:bufferBody()
      return request:consume():next(function()
        local key = exchange:getRequest():getBody()
        local session = exchange:getSession()
        if session then
          session:setAttribute('jls-cipher-key', key ~= '' and key or nil)
        end
        HttpExchange.ok(exchange)
      end)
    end
    return false
  end
  local createCipherHttpFile = CipherHttpFile.getCreateHttpFilefromSession()
  class.modifyInstance(handler, function(fileHttpHandler, super)
    function fileHttpHandler:createHttpFile(exchange, file, isDir)
      local hf = createCipherHttpFile(self, exchange, file, isDir)
      if hf then
        return hf
      end
      return super.createHttpFile(self, exchange, file, isDir)
    end
    if config.cipher.filter then
      function fileHttpHandler:listFileMetadata(exchange, dir)
        return List.filter(super.listFileMetadata(self, exchange, dir), function(md)
          return Path.extractExtension(md.name) ~= extension
        end)
      end
    end
  end)
  table.insert(htmlHeaders, '<a href="#" onclick="askKey(event)" class="action" title="Set the cipher key">&#x1F511;</a>')
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
  local appendDirectoryHtmlActions = handler.appendDirectoryHtmlActions
  function handler:appendDirectoryHtmlActions(exchange, buffer)
    appendDirectoryHtmlActions(self, exchange, buffer)
    for _, value in ipairs(htmlHeaders) do
      buffer:append(value)
    end
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

stopPromise:next(signal('?!sigint', function() stopCallback() end))

event:loop()
logger:info('HTTP server closed')
