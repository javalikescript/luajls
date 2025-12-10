local lu = require('luaunit')

local StreamHandler = require('jls.io.StreamHandler')
local secure = require('jls.net.secure')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpClient = require('jls.net.http.HttpClient')
local HttpServer = require('jls.net.http.HttpServer')

local loader = require('jls.lang.loader')
local loop = require('jls.lang.loopWithTimeout')
local TcpSocketLuv = loader.getRequired('jls.net.TcpSocket-luv')
local TcpSocketSocket = loader.getRequired('jls.net.TcpSocket-socket')
local luaSocketLib = loader.tryRequire('socket')

local File = require('jls.io.File')
local tables = require('jls.util.tables')
local logger = require('jls.lang.logger')

local opensslLib = require('openssl')

local genCertificateAndPKey = loader.load('tests.genCertificateAndPKey')
local CACERT_PEM, PKEY_PEM, CACERT_UNKNOWN_PEM, CACERT_INVALID_PEM = genCertificateAndPKey()

local TEST_HOST, TEST_PORT = '127.0.0.1', 3002

local function createHttpsClient(headers, method, secureContext)
  headers = headers or {}
  logger:fine('createHttpsClient()')
  local client = HttpClient:new({
    url = string.format('https://%s:%d/', TEST_HOST, TEST_PORT),
    method = method or 'GET',
    headers = headers,
    secureContext = secureContext or {
      cafile = CACERT_PEM
    }
  })
  logger:fine('createHttpsClient() done')
  return client
end

local function notFoundHandler(exchange)
  local response = exchange:getResponse()
  response:setStatusCode(404, 'Not Found')
  response:setBody('The resource "'..exchange:getRequest():getTarget()..'" is not available.')
end

local function createHttpsServer(handler, keep, secureContext)
  if not handler then
    handler = notFoundHandler
  end
  local tcp = secure.TcpSocket:new()
  local ctx = secure.Context:new(secureContext or {
    key = PKEY_PEM,
    certificate = CACERT_PEM
  })
  tcp:setSecureContext(ctx)
  local server = HttpServer:new(tcp)
  server:createContext('/.*', function(exchange)
    --print('createHttpsServer() handler')
    server.t_request = exchange:getRequest()
    if not keep then
      exchange:onClose():next(function()
        logger:finer('http exchange closed')
        if exchange:getResponse():getConnection() ~= 'keep-alive' then
          logger:finer('http server closing')
          server:close()
        end
      end)
    end
    return handler(exchange)
  end)
  return server:bind('::', TEST_PORT):next(function()
    return server
  end)
end

local function sendReceiveClose(client, resource, options)
  logger:finer('sendReceiveClose()')
  return client:fetch(resource or '/', tables.merge({
    headers = { connection = 'close' }
  }, options or {})):next(function(response)
    return response:text():next(function()
      logger:finer('sendReceiveClose(), response is %s', response)
      client.t_response = response
    end)
  end):catch(function(err)
    logger:fine('sendReceiveClose error "%s"', err)
    client.t_err = err
  end):finally(function()
    client:close()
  end)
end

function Test_encrypt_decrypt()
  local cacertFile = File:new(CACERT_PEM)
  local pkeyFile = File:new(PKEY_PEM)
  local pkey = opensslLib.pkey.read(pkeyFile:readAll(), true, 'pem')
  local cacert = opensslLib.x509.read(cacertFile:readAll())
  --print('subject', cacert:subject():oneline())
  --print('issuer', cacert:issuer():oneline())
  local text = 'Hello world !'
  local c = cacert:pubkey():encrypt(text)
  local d = pkey:decrypt(c)
  lu.assertEquals(d, text)
end

function Test_HttpsClientServer()
  local body = '<p>Hello.</p>'
  local server, client
  createHttpsServer(function(exchange)
    HttpExchange.ok(exchange, body)
  end):next(function(s)
    server = s
    client = createHttpsClient()
    sendReceiveClose(client):next(function()
      --print('createHttpsServer() closing server')
      server:close()
    end)
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
end

local function checkHttpsClientServer(success, ctxServer, ctxClient)
  local server, client, result
  createHttpsServer(function(exchange)
    HttpExchange.ok(exchange, 'Hi')
  end, nil, ctxServer):next(function(s)
    server = s
    client = createHttpsClient(nil, nil, ctxClient or {
      cafile = ctxServer and ctxServer.certificate or CACERT_PEM
    })
    return sendReceiveClose(client)
  end):finally(function()
    server:close()
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  if success then
    lu.assertIsNil(client.t_err)
    lu.assertEquals(client.t_response:getStatusCode(), 200)
    lu.assertEquals(client.t_response:getBody(), 'Hi')
  else
    lu.assertNotNil(client.t_err)
    --print('error', client.t_err)
  end
  lu.assertIsNil(server.t_err)
end

function Test_HttpsClientServer_verify()
  checkHttpsClientServer(true, {
    key = PKEY_PEM,
    certificate = CACERT_PEM
  })
  checkHttpsClientServer(false, {
    key = PKEY_PEM,
    certificate = CACERT_PEM
  }, {})
  checkHttpsClientServer(false, {
    key = PKEY_PEM,
    certificate = CACERT_UNKNOWN_PEM
  })
  checkHttpsClientServer(false, {
    key = PKEY_PEM,
    certificate = CACERT_INVALID_PEM
  })
end

local function onWriteMessage(message, data)
  if type(data) == 'string' then
    data = {data}
  end
  local l = 0
  for _, d in ipairs(data) do
    l = l + #d
  end
  message:setContentLength(l)
  message:onWriteBodyStreamHandler(function()
    local bsh = message:getBodyStreamHandler()
    for _, d in ipairs(data) do
      bsh:onData(d)
    end
    bsh:onData()
  end)
end

function Test_HttpsClientServer_body_stream()
  local server, client
  createHttpsServer(function(exchange)
    local request = exchange:getRequest()
    local response = exchange:getResponse()
    response:setStatusCode(200, 'Ok')
    onWriteMessage(response, {'<p>Hello ', request:getBody(), '!</p>'})
    logger:fine('http server handler => Ok')
  end):next(function(s)
    server = s
    client = createHttpsClient()
    local request = HttpMessage:new()
    request:setMethod('POST')
    request:setTarget('/')
    onWriteMessage(request, {'John', ', ', 'Smith'})
    logger:fine('http client request')
    sendReceiveClose(client, request)
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getBody(), '<p>Hello John, Smith!</p>')
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_request:getMethod(), 'POST')
end

function Test_HttpsServerClients()
  local server
  local count = 0
  createHttpsServer(function(exchange)
    HttpExchange.ok(exchange, '<p>Hello.</p>')
    count = count + 1
  end, true):next(function(s)
    server = s
    sendReceiveClose(createHttpsClient())
    sendReceiveClose(createHttpsClient()):next(function()
      sendReceiveClose(createHttpsClient()):next(function()
        --print('createHttpsServer() closing server')
        s:close()
      end)
    end)
  end)
  if not loop(function()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(count, 3)
end

function Test_HttpsServerClientsKeepAlive()
  local server, client
  local count = 0
  createHttpsServer(function(exchange)
    HttpExchange.ok(exchange, '<p>Hello.</p>')
    count = count + 1
  end):next(function(s)
    server = s
    client = createHttpsClient({Connection = 'keep-alive'})
    client:fetch('/'):next(function(response)
      return response:text()
    end):next(function()
      logger:fine('send receive completed for first request')
      return client:fetch('/')
    end):next(function(response)
      return response:text()
    end):next(function()
      logger:fine('send receive completed for second request')
    end):finally(function()
      client:close()
      s:close()
    end)
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(count, 2)
end

local function canResetConnection()
  return TcpSocketSocket or TcpSocketLuv and luaSocketLib
end

local function resetConnection(tcp, close, shutdown)
  if TcpSocketLuv and luaSocketLib and TcpSocketLuv:isInstance(tcp) then
    local fd = tcp.tcp:fileno()
    tcp = luaSocketLib.tcp()
    tcp:setfd(fd)
  elseif TcpSocketSocket and TcpSocketSocket:isInstance(tcp) then
    tcp = tcp.tcp
  else
    error('illegal state')
  end
  local lingerOption = tcp:getoption('linger')
  logger:fine('linger: %s, %s', lingerOption.on, lingerOption.timeout)
  tcp:setoption('linger', {on = false, timeout = 0})
  if shutdown then
    tcp:shutdown('both')
  end
  if close then
    tcp:close()
  end
end

local function shutdownConnection(tcp, close)
  if TcpSocketLuv and TcpSocketLuv:isInstance(tcp) then
    tcp.tcp:shutdown()
  elseif TcpSocketSocket and TcpSocketSocket:isInstance(tcp) then
    tcp.tcp:shutdown('both')
  end
  if close then
    tcp:close()
  end
end

local function createSecureTcpClient()
  local secureContext = secure.Context:new({
    peerVerify = false
  })
  local client = secure.TcpSocket:new()
  client:sslInit(false, secureContext)
  return client
end

function Test_HttpsClientServerConnectionCloseAfterHandshake()
  local server, client
  local function cleanup()
    if client then
      client:close()
    end
    if server then
      server:close()
    end
  end
  createHttpsServer():next(function(s)
    server = s
    client = secure.TcpSocket:new()
  end):next(function()
    return client:connect(TEST_HOST, TEST_PORT)
  end):next(function()
    logger:info('client connected')
    return client:close()
  end):next(function()
    server:close()
  end):catch(function(err)
    logger:info('error "%s"', err)
  end):finally(cleanup)
  if not loop(cleanup) then
    lu.fail('Timeout reached')
  end
end

if canResetConnection() then
  function Test_HttpsClientServerConnectionResetAfterHandshake()
    local server, client
    createHttpsServer(function(exchange)
      HttpExchange.ok(exchange, '<p>Hello.</p>')
      logger:info('server replied')
    end):next(function(s)
      server = s
      client = createSecureTcpClient()
      client:connect(TEST_HOST, TEST_PORT):next(function()
        logger:info('client connected')
        resetConnection(client, true, false)
        logger:info('client reset')
        server:close()
        logger:info('server closed')
      end, function(err)
        logger:info('an error occurred, %s', err)
      end)
    end)
    if not loop(function()
      client:close()
      server:close()
    end) then
      lu.fail('Timeout reached')
    end
  end
else
  logger:warn('skip Test_HttpsClientServerConnectionResetAfterHandshake')
end

function No_Test_HttpsClientOnline()
  local client = HttpClient:new('https://openssl.org/')
  logger:finer('connecting client')
  client:fetch('/'):next(function(response)
    local sh = StreamHandler.null
    if logger:isLoggable(logger.FINE) then
      sh = StreamHandler.std
    end
    response:setBodyStreamHandler(sh)
    sh:onData(response:formatLine())
    return client:consume()
  end):next(function()
    logger:finer('closing client')
    client:close()
  end, function(err)
    print('error: ', err)
    client:close()
  end)
  if not loop(function()
    client:close()
  end) then
    lu.fail('Timeout reached')
  end
end

os.exit(lu.LuaUnit.run())
