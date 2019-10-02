local lu = require('luaunit')

local event = require('jls.lang.event')
local net = require('jls.net')
local http = require('jls.net.http')
local streams = require('jls.io.streams')
local secure = require('jls.net.secure')
local Promise = require('jls.lang.Promise')

local loader = require('jls.lang.loader')
local netLuv = loader.tryRequire('jls.net-luv')
local netSocket = loader.tryRequire('jls.net-socket')
local luaSocketLib = loader.tryRequire('socket')

local File = require('jls.io.File')
local logger = require('jls.lang.logger')

local opensslLib = require('openssl')

local TEST_PORT = 3002

function loop(onTimeout, timeout)
  local timeoutReached = false
  if not timeout then
    timeout = 5000
  end
  local timer = event:setTimeout(function()
    timeoutReached = true
    if type(onTimeout) == 'function' then
      onTimeout()
    end
    --event:stop()
  end, timeout)
  event:daemon(timer, true)
  event:loop()
  if timeoutReached then
    lu.assertFalse(timeoutReached, 'timeout reached ('..tostring(timeout)..')')
  else
    event:clearTimeout(timer)
  end
end

local function createHttpsClient(headers)
  headers = headers or {}
  local client = http.Client:new({
    url = 'https://127.0.0.1:'..tostring(TEST_PORT)..'/',
    method = 'GET',
    checkHost = false,
    headers = headers
  })
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

local function createHttpsServer(handler)
  if not handler then
    handler = http.notFoundHandler
  end
  local tcp = secure.TcpServer:new()
  local secureContext = secure.Context:new({
    key = PKEY_PEM,
    certificate = CACERT_PEM
  })
  tcp:setSecureContext(secureContext)
  local server = http.Server:new(tcp)
  server:createContext('(.*)', function(httpExchange)
    --print('createHttpsServer() handler')
    server.t_request = httpExchange:getRequest()
    return handler(httpExchange)
  end)
  return server:bind('::', TEST_PORT):next(function()
    return server
  end)
end

local function sendReceiveClose(client)
  return client:connect():next(function()
    return client:sendReceive()
  end):next(function(response)
    client.t_response = response
    client:close()
  end, function(err)
    --print('client error', err)
    client.t_err = err
    client:close()
  end)
end

local function connectSendReceive(client)
  return client:connect():next(function()
    return client:sendReceive()
  end)
end

function test_encrypt_decrypt()
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

function test_HttpsClientServer()
  local body = '<p>Hello.</p>'
  local server, client
  createHttpsServer(function(httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(200, 'Ok')
    response:setBody(body)
  end):next(function(s)
    server = s
    client = createHttpsClient()
    sendReceiveClose(client):next(function()
      --print('createHttpsServer() closing server')
      server:close()
    end)
  end)
  loop(function()
    client:close()
    server:close()
  end)
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
end

function test_HttpsServerClients()
  local server
  local count = 0
  createHttpsServer(function(httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(200, 'Ok')
    response:setBody('<p>Hello.</p>')
    count = count + 1
  end):next(function(s)
    server = s
    sendReceiveClose(createHttpsClient())
    sendReceiveClose(createHttpsClient()):next(function()
      sendReceiveClose(createHttpsClient()):next(function()
        --print('createHttpsServer() closing server')
        s:close()
      end)
    end)
  end)
  loop(function()
    server:close()
  end)
  lu.assertEquals(count, 3)
end

function test_HttpsServerClientsKeepAlive()
  local server, client
  local count = 0
  createHttpsServer(function(httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(200, 'Ok')
    response:setBody('<p>Hello.</p>')
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
  loop(function()
    client:close()
    server:close()
  end)
  lu.assertEquals(count, 2)
end

local function resetConnection(tcp, close, shutdown)
  if netLuv.TcpClient:isInstance(tcp) then
    local fd = tcp.tcp:fileno()
    tcp = luaSocketLib.tcp()  
    tcp:setfd(fd)
  elseif netSocket.TcpClient:isInstance(tcp) then
    tcp = tcp.tcp
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
  if netLuv.TcpClient:isInstance(tcp) then
    tcp.tcp:shutdown()
  elseif netSocket.TcpClient:isInstance(tcp) then
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

function test_HttpsClientServerConnectionCloseAfterHandshake()
  local server, client
  createHttpsServer(function(httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(200, 'Ok')
    response:setBody('<p>Hello.</p>')
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
  loop(function()
    client:close()
    server:close()
  end)
end

function test_HttpsClientServerConnectionResetAfterHandshake()
  local server, client
  createHttpsServer(function(httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(200, 'Ok')
    response:setBody('<p>Hello.</p>')
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
  loop(function()
    client:close()
    server:close()
  end)
end

checkCertificateAndPrivateKey()

os.exit(lu.LuaUnit.run())
