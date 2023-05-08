local lu = require('luaunit')

local secure = require('jls.net.secure')
local HttpExchange = require('jls.net.http.HttpExchange')
local StreamHandler = require('jls.io.StreamHandler')
local HttpClient = require('jls.net.http.HttpClient')
local HttpServer = require('jls.net.http.HttpServer')

local loader = require('jls.lang.loader')
local loop = require('jls.lang.loopWithTimeout')
local TcpClientLuv = loader.getRequired('jls.net.TcpClient-luv')
local TcpClientSocket = loader.getRequired('jls.net.TcpClient-socket')
local luaSocketLib = loader.tryRequire('socket')

local File = require('jls.io.File')
local logger = require('jls.lang.logger')

local opensslLib = require('openssl')

local TEST_PORT = 3002

local function createHttpsClient(headers, method)
  headers = headers or {}
  logger:fine('createHttpsClient()')
  local client = HttpClient:new({
    url = 'https://127.0.0.1:'..tostring(TEST_PORT)..'/',
    method = method or 'GET',
    checkHost = false,
    headers = headers
  })
  logger:fine('createHttpsClient() done')
  return client
end

local function createCertificateAndPrivateKey()
  local cadn = opensslLib.x509.name.new({{commonName='CA'}, {C='CN'}})
  local pkey = opensslLib.pkey.new()
  local req = opensslLib.x509.req.new(cadn, pkey)
  local cacert = opensslLib.x509.new(1, req)
  cacert:validat(os.time(), os.time() + 3600*24*365)
  cacert:sign(pkey, cacert) --self sign
  return cacert, pkey
end

local function writeCertificateAndPrivateKey(cacertFile, pkeyFile)
  local cacert, pkey = createCertificateAndPrivateKey()
  local cacertPem  = cacert:export('pem')
  -- pkey:export('pem', true, 'secret') -- format='pem' raw=true,  passphrase='secret'
  local pkeyPem  = pkey:export('pem')
  cacertFile:write(cacertPem)
  pkeyFile:write(pkeyPem)
end

local CACERT_PEM = 'tests/cacert.pem'
local PKEY_PEM = 'tests/pkey.pem'

local function checkCertificateAndPrivateKey()
  local cacertFile = File:new(CACERT_PEM)
  local pkeyFile = File:new(PKEY_PEM)
  if not cacertFile:isFile() or not pkeyFile:isFile() then
    writeCertificateAndPrivateKey(cacertFile, pkeyFile)
  end
end

local function notFoundHandler(exchange)
  local response = exchange:getResponse()
  response:setStatusCode(404, 'Not Found')
  response:setBody('The resource "'..exchange:getRequest():getTarget()..'" is not available.')
end

local function createHttpsServer(handler, keep)
  if not handler then
    handler = notFoundHandler
  end
  local tcp = secure.TcpServer:new()
  local secureContext = secure.Context:new({
    key = PKEY_PEM,
    certificate = CACERT_PEM
  })
  tcp:setSecureContext(secureContext)
  local server = HttpServer:new(tcp)
  server:createContext('/.*', function(exchange)
    --print('createHttpsServer() handler')
    server.t_request = exchange:getRequest()
    if not keep then
      exchange:onClose():next(function()
        logger:finer('http exchange closed')
        local keepAlive = exchange:getResponse():getHeader('connection') == 'keep-alive'
        if not keepAlive then
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

local function sendReceiveClose(client)
  return client:connect():next(function()
    return client:sendReceive()
  end):next(function(response)
    logger:fine('http client response received')
    client.t_response = response
    client:close()
  end, function(err)
    logger:fine('http client error: %s', err)
    client.t_err = err
    client:close()
  end)
end

local function connectSendReceive(client)
  return client:connect():next(function()
    return client:sendReceive()
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
    local request = client:getRequest()
    request:setMethod('POST')
    onWriteMessage(request, {'John', ', ', 'Smith'})
    logger:fine('http client request')
    sendReceiveClose(client)
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
    connectSendReceive(client):next(function()
      logger:fine('send receive completed for first request')
      client:sendReceive():next(function()
        logger:fine('send receive completed for second request')
        client:close()
        s:close()
      end)
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
  return TcpClientSocket or TcpClientLuv and luaSocketLib
end

local function resetConnection(tcp, close, shutdown)
  if TcpClientLuv and luaSocketLib and TcpClientLuv:isInstance(tcp) then
    local fd = tcp.tcp:fileno()
    tcp = luaSocketLib.tcp()
    tcp:setfd(fd)
  elseif TcpClientSocket and TcpClientSocket:isInstance(tcp) then
    tcp = tcp.tcp
  else
    error('illegal state')
  end
  local lingerOption = tcp:getoption('linger')
  logger:fine('linger: '..tostring(lingerOption.on)..', '..tostring(lingerOption.timeout))
  tcp:setoption('linger', {on = false, timeout = 0})
  if shutdown then
    tcp:shutdown('both')
  end
  if close then
    tcp:close()
  end
end

local function shutdownConnection(tcp, close)
  if TcpClientLuv and TcpClientLuv:isInstance(tcp) then
    tcp.tcp:shutdown()
  elseif TcpClientSocket and TcpClientSocket:isInstance(tcp) then
    tcp.tcp:shutdown('both')
  end
  if close then
    tcp:close()
  end
end

local function createSecureTcpClient()
  local secureContext = secure.Context:new()
  secureContext.sslContext:set_cert_verify(function(arg)
    logger:info('ssl cert verify => false')
    return false
  end)
  local client = secure.TcpClient:new()
  client:sslInit(false, secureContext)
  return client
end

function Test_HttpsClientServerConnectionCloseAfterHandshake()
  local server, client
  createHttpsServer(function(exchange)
    HttpExchange.ok(exchange, '<p>Hello.</p>')
    logger:info('server replied')
  end):next(function(s)
    server = s
    client = secure.TcpClient:new()
    client:connect('localhost', TEST_PORT):next(function()
      logger:info('client connected')
      return client:close()
    end):next(function()
      logger:info('client closed')
      server:close()
      logger:info('server closed')
    end)
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
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
      client:connect('localhost', TEST_PORT):next(function()
        logger:info('client connected')
        resetConnection(client, true, false)
        logger:info('client reset')
        server:close()
        logger:info('server closed')
      end, function(err)
        logger:info('an error occurred, '..tostring(err))
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
  local client = HttpClient:new({
    url = 'https://openssl.org/',
    method = 'GET',
    headers = {},
  })
  logger:finer('connecting client')
  client:connect():next(function()
    logger:finer('client connected')
    return client:sendRequest()
  end):next(function()
    return client:receiveResponseHeaders()
  end):next(function(remainingBuffer)
    local response = client:getResponse()
    local sh = StreamHandler.null
    if logger:isLoggable(logger.FINE) then
      sh = StreamHandler.std
    end
    response:setBodyStreamHandler(sh)
    sh:onData(response:getLine())
    return client:receiveResponseBody(remainingBuffer)
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

checkCertificateAndPrivateKey()

os.exit(lu.LuaUnit.run())
