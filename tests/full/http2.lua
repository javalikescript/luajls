local lu = require('luaunit')

local logger = require('jls.lang.logger')
local loader = require('jls.lang.loader')
local Promise = require('jls.lang.Promise')
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local system = require('jls.lang.system')
local loop = require('jls.lang.loopWithTimeout')
local secure = require('jls.net.secure')
local TcpSocket = secure.TcpSocket
local Http2 = require('jls.net.http.Http2')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpClient = require('jls.net.http.HttpClient')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local List = require('jls.util.List')
local Codec = require('jls.util.Codec')
local hex = Codec.getInstance('hex')
local genCertificateAndPKey = loader.load('tests.genCertificateAndPKey')

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
      onHttp2Event = function(_, name, http2, stream, reason)
        if name == 'error' or name == 'stream-error' then
          logger:warn('error', reason)
          client:close()
          server:close()
        end
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

local function helloHandler(exchange)
  local path = exchange:getRequest():getTargetPath()
  HttpExchange.ok(exchange, string.format('<p>Hello %s.</p>', path))
end

local function sum(list)
  local s = 0
  for _, d in ipairs(list) do
    s = s + #d
  end
  return s
end

local function createStreamHandler(list)
  return function(exchange)
    local response = exchange:getResponse()
    response:setContentLength(sum(list))
    response:onWriteBodyStreamHandler(function()
      local sh = response:getBodyStreamHandler()
      for _, d in ipairs(list) do
        sh:onData(d)
      end
      sh:onData()
    end)
  end
end

local function createHttpServer(handler, isSecure)
  local server
  if isSecure then
    server = HttpServer.createSecure({
      key = PKEY_PEM,
      certificate = CACERT_PEM,
      alpnSelectProtos = {'h2'}
    })
  else
    server = HttpServer:new()
  end
  server:createContext('/.*', handler or notFoundHandler)
  return server:bind('::', TEST_PORT):next(function()
    return server
  end)
end

local function runHttpClientServer(onConnect, isSecure, handler)
  local server, client
  createHttpServer(handler or helloHandler, isSecure):next(function(s)
    logger:info('server bound')
    server = s
    client = createHttpClient(isSecure)
    return client:connectV2()
  end):next(function()
    return onConnect(client)
  end):catch(function(reason)
    logger:warn('error in test, due to %s', reason:toString())
  end):finally(function()
    client:close()
    server:close()
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
end

local function assertFetchHttpClientServer(isSecure, options)
  local responseStatus, responseBody, responseVersion
  runHttpClientServer(function(client)
    return client:fetch('/', options):next(function(response)
      logger:info('response fetched')
      responseStatus = response:getStatusCode()
      responseVersion = response:getVersion()
      return response:text()
    end):next(function(content)
      logger:info('response body received')
      responseBody = content
    end)
  end, isSecure)
  lu.assertEquals(responseStatus, 200)
  lu.assertEquals(responseBody, '<p>Hello /.</p>')
  if isSecure then
    lu.assertEquals(responseVersion, 'HTTP/2')
  end
end

function Test_HttpClientServer()
  assertFetchHttpClientServer()
end

function Test_HttpClientServer_close()
  assertFetchHttpClientServer(false, { headers = { connection = 'close'} })
end

function Test_HttpClientServer_secure()
  assertFetchHttpClientServer(true)
end

local function assertFetchsHttpClientServer(isSecure, options)
  local responses, responseVersion
  local function doFetch(client, resource, options)
    return client:fetch(resource, options):next(function(response)
      if response:getStatusCode() ~= 200 then
        return Promise.reject('bad status code')
      end
      responseVersion = response:getVersion()
      return response:text()
    end)
  end
  runHttpClientServer(function(client)
    return Promise.all({
      doFetch(client, '/1', options),
      doFetch(client, '/2', options),
      doFetch(client, '/3', options),
    }):next(function(results)
      responses = results
    end)
  end, isSecure)
  lu.assertEquals(responses, {
    '<p>Hello /1.</p>',
    '<p>Hello /2.</p>',
    '<p>Hello /3.</p>',
  })
  lu.assertEquals(responseVersion, isSecure and 'HTTP/2' or 'HTTP/1.1')
end

function Test_HttpClientServer_concurent()
  assertFetchsHttpClientServer()
end

function Test_HttpClientServer_concurent_secure()
  assertFetchsHttpClientServer(true)
end

local function assertFetchHttpClientServerStream(list, isSecure, options)
  local responseStatus, responseBody, responseVersion
  runHttpClientServer(function(client)
    return client:fetch('/', options):next(function(response)
      logger:info('response fetched')
      responseStatus = response:getStatusCode()
      responseVersion = response:getVersion()
      return response:text()
    end):next(function(content)
      logger:info('response body received')
      responseBody = content
    end)
  end, isSecure, createStreamHandler(list))
  lu.assertEquals(responseStatus, 200)
  lu.assertEquals(responseBody, table.concat(list))
  if isSecure then
    lu.assertEquals(responseVersion, 'HTTP/2')
  end
end

local bodyParts = {
  '<p>',
  'Hello',
  '</p>',
}

function Test_HttpClientServer_stream()
  assertFetchHttpClientServerStream(bodyParts)
end

function Test_HttpClientServer_stream_secure()
  assertFetchHttpClientServerStream(bodyParts, true)
end

os.exit(lu.LuaUnit.run())
