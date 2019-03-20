local lu = require('luaunit')

local event = require('jls.lang.event')
local net = require('jls.net')
local http = require('jls.net.http')
local streams = require('jls.io.streams')

local logger = require('jls.lang.logger')

local TEST_PORT = 3002

local function createTcpServer(onData)
  if type(onData) == 'string' then
    local replyData = onData
    onData = function(server, client)
      client:write(replyData)
    end
  end
  local server = net.TcpServer:new()
  assert(server:bind('0.0.0.0', TEST_PORT))
  function server:onAccept(client)
    local stream = streams.StreamHandler:new()
    function stream:onData(data)
      if type(onData) == 'function' then
        onData(server, client, data)
      end
      if data then
        if server.t_receivedData then
          server.t_receivedData = server.t_receivedData..data
        else
          server.t_receivedData = data
        end
      else
        client:close()
        server:close()
      end
    end
    client:readStart(stream)
  end
  return server
end

local function createTcpClient(requestData)
  local client = net.TcpClient:new()
  client.t_receivedCount = 0
  return client:connect('127.0.0.1', TEST_PORT):next(function()
    local stream = streams.StreamHandler:new()
    function stream:onData(data)
      if data then
        client.t_receivedCount = client.t_receivedCount + 1
        if client.t_receivedData then
          client.t_receivedData = client.t_receivedData..data
        else
          client.t_receivedData = data
        end
      else
        client:close()
      end
    end
    client:readStart(stream)
    if requestData then
      client:write(requestData)
    end
    return client
  end)
end

local function createHttpClient(headers)
  headers = headers or {}
  local client = http.Client:new({
    url = 'http://127.0.0.1:'..tostring(TEST_PORT)..'/',
    method = 'GET',
    headers = headers
  })
  return client
end

local function createHttpServer(handler)
  if not handler then
    handler = http.notFoundHandler
  end
  local server = http.Server:new()
  server.t_requestCount = 0
  server:createContext('(.*)', function(httpExchange)
    --print('createHttpServer() handler')
    local super = httpExchange.close
    function httpExchange.close()
      local keepAlive = httpExchange:getResponse():getHeader('Connection') == 'keep-alive'
      super(httpExchange)
      if not keepAlive then
        --print('createHttpServer() closing server')
        server:close()
      end
    end
    server.t_requestCount = server.t_requestCount + 1
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

local function createRawHeaders(headers)
  local content = ''
  for name, value in pairs(headers) do
    content = content..name..': '..tostring(value)..'\r\n'
  end
  return content
end

local function createHttpRawRequest(target, method, rawHeaders, body, httpVersion)
  target = target or '/'
  method = method or 'GET'
  rawHeaders = rawHeaders or ''
  body = body or ''
  httpVersion = httpVersion or '1.0'
  return method..' '..target..' '..'HTTP/'..httpVersion..'\r\n'..rawHeaders..'\r\n'..body
end

local function createHttpRawRequestCL(target, method, rawHeaders, body, httpVersion)
  body = body or ''
  rawHeaders = createRawHeaders({['Content-Length'] = #body})..(rawHeaders or '')
  return createHttpRawRequest(target, method, rawHeaders, body, httpVersion)
end

local function createHttpRawResponse(body, statusCode, rawHeaders, reasonPhrase, httpVersion)
  body = body or ''
  statusCode = statusCode or 200
  reasonPhrase = reasonPhrase or 'OK'
  rawHeaders = rawHeaders or ''
  httpVersion = httpVersion or '1.0'
  return 'HTTP/'..httpVersion..' '..tostring(statusCode)..' '..reasonPhrase..'\r\n'..rawHeaders..'\r\n'..body
end

local function createHttpRawResponseCC(body, statusCode, rawHeaders, reasonPhrase, httpVersion)
  rawHeaders = createRawHeaders({Connection = 'close'})..(rawHeaders or '')
  return createHttpRawResponse(body, statusCode, rawHeaders, reasonPhrase, httpVersion)
end

local function createHttpRawResponseCL(body, statusCode, rawHeaders, reasonPhrase, httpVersion)
  body = body or ''
  rawHeaders = createRawHeaders({['Content-Length'] = #body})..(rawHeaders or '')
  return createHttpRawResponse(body, statusCode, rawHeaders, reasonPhrase, httpVersion)
end

local function createHttpRawResponseChunked(body, statusCode, rawHeaders, reasonPhrase, httpVersion)
  body = body or ''
  local chunkSize = 10
  local chunkBody = ''
  for p = 1, #body, chunkSize do
    local chunkdata = string.sub(body, p, p + chunkSize - 1)
    chunkBody = chunkBody..string.format('%x', #chunkdata)..'\r\n'..chunkdata..'\r\n'
  end
  chunkBody = chunkBody..'0\r\n'
  rawHeaders = createRawHeaders({['Transfer-Encoding'] = 'chunked'})..(rawHeaders or '')
  return createHttpRawResponse(chunkBody, statusCode, rawHeaders, reasonPhrase, httpVersion)
end

local function createLongBody()
  return [[
    Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc finibus quam nec enim vulputate, vel finibus risus tincidunt. Donec vitae massa sed massa viverra lobortis eu vitae turpis. Nullam non dui rhoncus, fermentum dolor aliquet, interdum nisi. Suspendisse vel purus eget odio ullamcorper fermentum eget vitae diam. Etiam non placerat arcu. Cras varius lectus ac mauris eleifend, sed suscipit erat porta. Nulla eget nisl ac magna iaculis imperdiet. Proin rutrum tincidunt sem, sed sagittis lorem congue et. Aenean interdum lorem a mi finibus, ac egestas mi ullamcorper. Nunc blandit lobortis mi, ac finibus enim varius ut. Integer sit amet malesuada turpis. Nulla viverra massa nisi, sed laoreet nunc gravida sed. Nunc eu tristique dui, sit amet aliquet orci.
    Donec at aliquet libero. Sed a iaculis sapien, quis imperdiet arcu. Cras et ultrices nunc. Fusce tempor ligula at lectus iaculis hendrerit. Morbi feugiat diam ut sagittis efficitur. Cras at metus quis lorem lobortis posuere at eget orci. Praesent feugiat eros id suscipit pretium. Nunc in varius lacus. Mauris tempus tellus erat. Cras a dignissim mi. Aliquam rhoncus rhoncus pellentesque.
    Nunc lectus quam, sollicitudin tempor libero sit amet, laoreet dapibus mauris. Aenean eleifend ante id porta consequat. Quisque mi libero, placerat ut sagittis et, efficitur quis tortor. Sed quis purus vel tortor lacinia egestas ac et ligula. Sed lacinia enim id elementum accumsan. Pellentesque mollis tellus eget orci ornare, quis ultricies lacus elementum. Vestibulum volutpat tellus vel ornare eleifend. Duis sit amet ligula sit amet arcu imperdiet mattis a at est. Donec vel erat id dui aliquet gravida. Duis ac molestie diam. Proin lobortis, erat eu ornare tempor, leo elit auctor justo, ut fermentum velit nulla in nisl. Nullam convallis diam id nisi hendrerit, ac elementum ipsum suscipit. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas.
    Donec aliquam, mauris et gravida varius, sapien erat sodales erat, quis cursus mi ligula eu magna. Proin nisi lectus, tristique eu turpis ut, vehicula commodo eros. Mauris sed efficitur sem. Cras ut felis nibh. Donec massa elit, commodo sed tellus vitae, lobortis tempus ex. Aenean dignissim aliquam neque sit amet consequat. Duis fringilla eget neque sed feugiat. Praesent fringilla leo enim, vitae venenatis tortor vehicula a. Lorem ipsum dolor sit amet, consectetur adipiscing elit.
    Morbi libero libero, lacinia a fringilla eget, dignissim in nunc. Etiam finibus scelerisque ultricies. Sed vel vestibulum nibh, id laoreet velit. Donec interdum eros vel nulla ultrices laoreet. Curabitur facilisis orci et commodo aliquet. Aliquam non justo nulla. Fusce vitae fermentum ligula, eget imperdiet dui. Etiam rutrum nibh sed metus rhoncus consectetur. Donec condimentum quam nulla. Etiam fringilla dictum ullamcorper.
    ]]
end

function test_HttpClient_no_header()
  -- no headers (no connection close) means unknown body size so we expect an error
  local server = createTcpServer(createHttpRawResponse())
  local client = createHttpClient()
  sendReceiveClose(client)
  event:loop()
  lu.assertNotIsNil(client.t_err)
  -- response:getHeaders()
end

function test_HttpClient_content_length_empty_body()
  local server = createTcpServer(createHttpRawResponseCL(''))
  local client = createHttpClient()
  sendReceiveClose(client)
  event:loop()
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
end

function test_HttpClient_content_length_with_body()
  local body = 'Hello world!'
  local server = createTcpServer(createHttpRawResponseCL(body))
  local client = createHttpClient()
  sendReceiveClose(client)
  event:loop()
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
end

function test_HttpClient_connection_close_empty_body()
  local server = createTcpServer(function(s, c)
    c:write(createHttpRawResponseCC('')):next(function()
      c:close()
      s:close()
    end)
  end)
  local client = createHttpClient()
  sendReceiveClose(client)
  event:loop()
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
end

function test_HttpClient_connection_close_with_body()
  local body = 'Hello world!'
  local server = createTcpServer(function(s, c, d)
    c:write(createHttpRawResponseCC(body)):next(function()
      c:close()
      s:close()
    end)
  end)
  local client = createHttpClient()
  sendReceiveClose(client)
  event:loop()
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
end

function test_HttpClient_chunked_empty_body()
  local server = createTcpServer(createHttpRawResponseChunked(''))
  local client = createHttpClient()
  sendReceiveClose(client)
  event:loop()
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
end

function test_HttpClient_chunked_with_body()
  local body = 'Hello       world             !'
  local server = createTcpServer(createHttpRawResponseChunked(body))
  local client = createHttpClient()
  sendReceiveClose(client)
  event:loop()
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
end

function test_HttpClient_long_body()
  local body = createLongBody()
  local server = createTcpServer(createHttpRawResponseCL(body))
  local client = createHttpClient()
  sendReceiveClose(client)
  event:loop()
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
end

function test_HttpServer_simple_get()
  local server
  createHttpServer():next(function(s)
    server = s
    createTcpClient(createHttpRawRequest())
  end)
  event:loop()
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
end

function test_HttpClientServer()
  local body = '<p>Hello.</p>'
  local server, client
  createHttpServer(function(httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(200, 'Ok')
    response:setBody(body)
  end):next(function(s)
    server = s
    client = createHttpClient()
    sendReceiveClose(client)
  end)
  event:loop()
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
end

function test_HttpServer_keep_alive()
  local req = createHttpRawRequest(nil, nil, createRawHeaders({Connection = 'keep-alive'}))
  local server, client
  createHttpServer():next(function(s)
    server = s
    return createTcpClient()
  end):next(function(c)
    client = c
    return client:write(req)
  end):next(function()
    return client:write(createHttpRawRequest())
  end):finally(function()
    --server:close()
  end)
  event:loop()
  lu.assertNotIsNil(client)
  lu.assertNotIsNil(server)
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_requestCount, 2)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
  lu.assertEquals(client.t_receivedCount, 2)
end

function test_HttpClientServer_keep_alive()
  local count = 0
  createHttpServer(function(httpExchange)
    local response = httpExchange:getResponse()
    response:setStatusCode(200, 'Ok')
    response:setBody('<p>Hello.</p>')
    count = count + 1
  end):next(function(s)
    local client = createHttpClient({Connection = 'keep-alive'})
    connectSendReceive(client):next(function()
      logger:fine('send receive completed for first request')
      client:sendReceive():next(function()
        logger:fine('send receive completed for second request')
        client:close()
        s:close()
      end)
    end)
  end)
  event:loop()
  lu.assertEquals(count, 2)
end

--event:close()
os.exit(lu.LuaUnit.run())
