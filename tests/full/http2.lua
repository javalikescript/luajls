local lu = require('luaunit')

local secure = require('jls.net.secure')
local logger = require('jls.lang.logger')
local TcpSocket = secure.TcpSocket
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local system = require('jls.lang.system')
local loop = require('jls.lang.loopWithTimeout')
local Http2 = require('jls.net.http.Http2')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpClient = require('jls.net.http.HttpClient')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local List = require('jls.util.List')
local Codec = require('jls.util.Codec')
local hex = Codec.getInstance('hex')
local genCertificateAndPKey = require('tests.genCertificateAndPKey')

--logger = logger:getClass():new(); logger:setLevel('finer')
--logger:setLevel('finer')

-- make -f ../luaclibs/lua-openssl.mk OPENSSL_STATIC=1 OPENSSLDIR=../luaclibs/openssl LUADIR=../luaclibs/lua/src && cp openssl.dll ..\luaclibs\dist

local CACERT_PEM, PKEY_PEM = genCertificateAndPKey()
local TEST_HOST, TEST_PORT = '127.0.0.1', 3002

local TOOL
if os.getenv('USE_OPENSSL') then
  TOOL = system.findExecutablePath('openssl')
else
  TOOL = system.findExecutablePath('curl')
end


local function newSecureTcpServer()
  local server = TcpSocket:new()
  -- reuse previous context
  local secureContext = secure.Context:new({
    key = PKEY_PEM,
    certificate = CACERT_PEM,
    alpnSelectProtos = {'h2', 'http/1.1'},
  })
  server:setSecureContext(secureContext)
  return server
end

function No_Test_TcpClient_TcpServer()
  if not TOOL then
    print('/!\\ skipping test, tool not found')
    lu.success()
    return
  end
  local alpnSelected
  local server = newSecureTcpServer()
  function server:onAccept(client)
    alpnSelected = client:sslGetAlpnSelected()
    if alpnSelected ~= 'h2' then -- HTTP/2
      client:close()
      server:close()
      return
    end
    local http2 = Http2:new(client, true, {
      onHttp2EndHeaders = function(_, stream)
        logger:info('end headers: %s', stream.message:getRawHeaders())
      end,
      onHttp2Data = function(_, stream, data)
        logger:info('data: %s', hex:encode(data))
      end,
      onHttp2EndStream = function(_, stream)
        logger:info('end stream')
        local response = HttpMessage:new()
        response:setStatusCode(200)
        response:setHeader(HttpMessage.CONST.HEADER_SERVER, HttpMessage.CONST.DEFAULT_SERVER)
        stream:sendHeaders(response, true):next(function()
          return stream.http2:goAway()
        end):next(function()
          client:close()
          server:close()
        end)
      end,
      onHttp2Error = function(_, stream, reason)
        logger:info('error', reason)
        client:close()
        server:close()
      end,
    })
    http2:readStart()
  end
  assert(server:bind(TEST_HOST, TEST_PORT))
  logger:info('server boud %s:%s', TEST_HOST, TEST_PORT)

  local null = system.isWindows() and 'NUL' or '/dev/null'
  local pb
  if string.find(TOOL, 'curl') then
    local args = {TOOL, '--insecure'}
    List.concat(args, '-I') -- head
    --List.concat(args, '-v') -- verbose
    List.concat(args, '-s') -- silent
    List.concat(args, '-o'..null)
    List.concat(args, '-H', 'X-custom: A value with $#')
    --List.concat(args, '-w', 'HTTP version is %{http_version}\\n')
    List.concat(args, string.format('https://%s:%d', TEST_HOST, TEST_PORT))
    pb = ProcessBuilder:new(args)
  else
    local hostport = string.format('%s:%d', TEST_HOST, TEST_PORT)
    pb = ProcessBuilder:new(TOOL, 's_client', '-partial_chain', '-alpn', 'h2', '-connect', hostport, '-status')
  end
  pb:setRedirectOutput(system.output)
  pb:setRedirectError(system.error)
  local ph, err = pb:start()
  lu.assertNil(err)
  lu.assertNotNil(ph)

  local exitCode
  ph:ended():next(function(c)
    exitCode = c
    server:close()
  end)

  if not loop() then
    ph:destroy()
    server:close()
    lu.fail('Timeout reached')
  end
  lu.assertEquals(alpnSelected, 'h2')
  lu.assertEquals(exitCode, 0)
end

local function createHttpClient(isSecure)
  local client = HttpClient:new({
    url = string.format('%s://%s:%d', isSecure and 'https' or 'http', TEST_HOST, TEST_PORT),
    secureContext = {
      alpnProtos = {'h2'}
    },
  })
  return client
end

local function notFoundHandler(exchange)
  local response = exchange:getResponse()
  response:setStatusCode(404, 'Not Found')
  response:setBody('The resource "'..exchange:getRequest():getTarget()..'" is not available.')
end

local function createHttpServer(handler, isSecure)
  if not handler then
    handler = notFoundHandler
  end
  local tcp
  if isSecure then
    tcp = secure.TcpServer:new()
    tcp:setSecureContext({
      key = PKEY_PEM,
      certificate = CACERT_PEM,
      alpnSelectProtos = {'h2'}
    })
  end
  local server = HttpServer:new(tcp)
  server:createContext('/.*', function(exchange)
    logger:info('createHttpServer() handler')
    server.t_request = exchange:getRequest()
    return handler(exchange)
  end)
  return server:bind('::', TEST_PORT):next(function()
    return server
  end)
end

local function assertFetchHttpClientServer(isServer)
  local body = '<p>Hello.</p>'
  local receivedStatus, receivedBody
  local server, client
  createHttpServer(function(exchange)
    HttpExchange.ok(exchange, body)
  end, isServer):next(function(s)
    logger:info('server bound')
    server = s
    client = createHttpClient(isServer)
    return client:fetch('/')
  end):next(function(response)
    logger:info('response fetched')
    receivedStatus = response:getStatusCode()
    return response:readBody()
  end):next(function(body)
    receivedBody = body
    client:close()
    server:close()
  end):catch(function(reason)
    logger:warn('ouch', reason)
    client:close()
    server:close()
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(receivedStatus, 200)
  lu.assertEquals(receivedBody, body)
end

function Test_HttpClientServer()
  assertFetchHttpClientServer()
end

function Test_Http2ClientServer()
  assertFetchHttpClientServer(true)
end

os.exit(lu.LuaUnit.run())
