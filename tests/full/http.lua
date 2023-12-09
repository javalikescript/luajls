local lu = require('luaunit')

local loop = require('jls.lang.loopWithTimeout')
local TcpClient = require('jls.net.TcpClient')
local TcpServer = require('jls.net.TcpServer')
local strings = require('jls.util.strings')
local List = require('jls.util.List')
local HttpHandler = require('jls.net.http.HttpHandler')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpClient = require('jls.net.http.HttpClient')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')

local logger = require('jls.lang.logger')

local TEST_PORT = 3002

local function createTcpServer(onData)
  if type(onData) == 'string' then
    local replyData = onData
    onData = function(server, client, data)
      client:write(replyData)
      onData = nil
    end
  end
  local server = TcpServer:new()
  assert(server:bind('127.0.0.1', TEST_PORT))
  function server:onAccept(client)
    client:readStart(function(err, data)
      if type(onData) == 'function' then
        onData(server, client, data)
      end
      if err then
        logger:warn('tcp server error "'..tostring(err)..'" => closing')
        server.t_error = err
        server:close()
        client:close()
      elseif data then
        logger:finer('tcp server receives data')
        if server.t_receivedData then
          server.t_receivedData = server.t_receivedData..data
        else
          server.t_receivedData = data
        end
      else
        logger:finer('tcp server receives no data => closing')
        client:close()
        server:close()
      end
    end)
  end
  return server
end

local function createTcpClient(requestData)
  local client = TcpClient:new()
  local receivedCount = 0
  return client:connect('127.0.0.1', TEST_PORT):next(function()
    logger:finer('tcp client connected')
    client:readStart(function(err, data)
      if err then
        logger:warn('tcp client stream error '..tostring(err))
        client.t_error = err
        client:close()
      elseif data then
        receivedCount = receivedCount + 1
        logger:finer('tcp client receives #'..tostring(receivedCount)..' data #'..tostring(#data))
        logger:finest('tcp client receives data '..tostring(data))
        if client.t_receivedData then
          client.t_receivedData = client.t_receivedData..data
        else
          client.t_receivedData = data
        end
      else
        logger:finer('tcp client receives no data')
        client:close()
      end
    end)
    if requestData then
      client:write(requestData)
    end
    return client
  end, function(err)
    logger:warn('tcp client connect error '..tostring(err))
  end)
end

local function createHttpClient()
  return HttpClient:new('http://127.0.0.1:'..tostring(TEST_PORT)..'/')
end

local function notFoundHandler(exchange)
  local response = exchange:getResponse()
  response:setStatusCode(404, 'Not Found')
  response:setBody('The resource "'..exchange:getRequest():getTarget()..'" is not available.')
end

local function createHttpServer(handler, keep)
  if not handler then
    handler = notFoundHandler
  end
  local server = HttpServer:new()
  server.t_requestCount = 0
  local wh = handler
  local ch = function(exchange)
    server.t_requestCount = server.t_requestCount + 1
    server.t_request = exchange:getRequest()
    logger:finer('http server handle #'..tostring(server.t_requestCount))
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
    return wh(exchange)
  end
  if HttpHandler:isInstance(handler) then
    local chf = ch
    ch = HttpHandler:new(function(_, exchange)
      return chf(exchange)
    end)
    wh = function(exchange)
      return handler:handle(exchange)
    end
  end
  server:createContext('/.*', ch)
  return server:bind('::', TEST_PORT):next(function()
    return server
  end)
end

local function setConnectionClose(message)
  message:setHeader(HttpMessage.CONST.HEADER_CONNECTION, HttpMessage.CONST.CONNECTION_CLOSE)
end

local function sendReceiveClose(client, resource, options)
  logger:finer('sendReceiveClose()')
  return client:fetch(resource or '/', options or resource == nil and {
    headers = { connection = 'close' }
  }):next(function(response)
    return response:text():next(function()
      logger:finer('sendReceiveClose(), response is '..tostring(response))
      client.t_response = response
    end)
  end):catch(function(err)
    logger:fine('sendReceiveClose error "'..tostring(err)..'"')
    client.t_err = err
  end):finally(function()
    client:close()
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

function Test_HttpClient_no_header()
  -- no headers (no connection close) means unknown body size so we expect an error
  local server = createTcpServer(createHttpRawResponse())
  local client = createHttpClient()
  sendReceiveClose(client)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertNotIsNil(client.t_err)
end

function Test_HttpClient_content_length_empty_body()
  local server = createTcpServer(createHttpRawResponseCL(''))
  local client = createHttpClient()
  sendReceiveClose(client)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
end

function Test_HttpClient_content_length_with_body()
  local body = 'Hello world!'
  local server = createTcpServer(createHttpRawResponseCL(body))
  local client = createHttpClient()
  sendReceiveClose(client)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
end

function Test_HttpClient_connection_close_empty_body()
  local server = createTcpServer(function(s, c)
    c:write(createHttpRawResponseCC('')):next(function()
      c:close()
      s:close()
    end)
  end)
  local client = createHttpClient()
  sendReceiveClose(client)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
end

function Test_HttpClient_connection_close_with_body()
  local body = 'Hello world!'
  local server = createTcpServer(function(s, c, d)
    c:write(createHttpRawResponseCC(body)):next(function()
      c:close()
      s:close()
    end)
  end)
  local client = createHttpClient()
  sendReceiveClose(client)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
end

function Test_HttpClient_chunked_empty_body()
  local server = createTcpServer(createHttpRawResponseChunked(''))
  local client = createHttpClient()
  sendReceiveClose(client)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
end

function Test_HttpClient_chunked_with_body()
  local body = 'Hello-------world-------------!'
  local server = createTcpServer(createHttpRawResponseChunked(body))
  local client = createHttpClient()
  sendReceiveClose(client)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
end

function Test_HttpClient_long_body()
  local body = createLongBody()
  local server = createTcpServer(createHttpRawResponseCL(body))
  local client = createHttpClient()
  sendReceiveClose(client)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getStatusCode(), 200)
  lu.assertEquals(client.t_response:getBody(), body)
end

function Test_HttpServer_simple_get()
  local server, client
  createHttpServer():next(function(s)
    logger:fine('http server created')
    server = s
    client = createTcpClient(createHttpRawRequest())
    logger:fine('tcp client created')
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
end

function Test_HttpClientServer()
  local body = '<p>Hello.</p>'
  local server, client
  createHttpServer(function(exchange)
    local response = exchange:getResponse()
    response:setStatusCode(200, 'Ok')
    response:setBody(body)
    logger:fine('http server handler => Ok')
  end):next(function(s)
    server = s
    client = createHttpClient()
    sendReceiveClose(client)
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

function Test_HttpClientServer_body()
  local server, client
  createHttpServer(function(exchange)
    local request = exchange:getRequest()
    local response = exchange:getResponse()
    response:setStatusCode(200, 'Ok')
    setConnectionClose(response)
    response:setBody('<p>Hello '..request:getBody()..'!</p>')
    logger:fine('http server handler => Ok')
  end):next(function(s)
    server = s
    client = createHttpClient()
    sendReceiveClose(client, '/', { method = 'POST', body = 'Tim' })
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getBody(), '<p>Hello Tim!</p>')
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_request:getMethod(), 'POST')
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

local function createRequest(method, target)
  local request = HttpMessage:new()
  request:setMethod(method or 'GET')
  request:setTarget(target or '/')
  setConnectionClose(request)
  return request
end

function Test_HttpClientServer_body_stream()
  local server, client
  createHttpServer(function(exchange)
    local request = exchange:getRequest()
    local response = exchange:getResponse()
    response:setStatusCode(200, 'Ok')
    setConnectionClose(response)
    onWriteMessage(response, '<p>Hello '..request:getBody()..'!</p>')
    logger:fine('http server handler => Ok')
  end):next(function(s)
    server = s
    client = createHttpClient()
    local request = createRequest('POST')
    onWriteMessage(request, 'Tim')
    sendReceiveClose(client, request)
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertIsNil(client.t_err)
  lu.assertEquals(client.t_response:getBody(), '<p>Hello Tim!</p>')
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_request:getMethod(), 'POST')
end

function Test_HttpsClientServer_body_stream_multiple()
  local server, client
  createHttpServer(function(exchange)
    local request = exchange:getRequest()
    local response = exchange:getResponse()
    response:setStatusCode(200, 'Ok')
    setConnectionClose(response)
    onWriteMessage(response, {'<p>Hello ', request:getBody(), '!</p>'})
    logger:fine('http server handler => Ok')
  end):next(function(s)
    server = s
    client = createHttpClient()
    local request = createRequest('POST')
    onWriteMessage(request, {'John, ', 'Smith'})
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

local function createHttpServerRedirect(body, ...)
  local paths = {...}
  return createHttpServer(function(exchange)
    local target = exchange:getRequest():getTarget()
    local response = exchange:getResponse()
    local index = List.indexOf(paths, target)
    if index == 1 then
      response:setStatusCode(200, 'Ok')
      response:setBody(body)
    elseif index > 1 then
      response:setHeader('Location', 'http://127.0.0.1:'..tostring(TEST_PORT)..paths[index - 1])
      response:setStatusCode(302, 'Found')
    else
      response:setStatusCode(404, 'Not Found')
      response:setBody('<p>The resource "'..target..'" is not available.</p>')
    end
  end, true)
end

function Test_HttpClientServer_redirect_none()
  local body = '<p>Hello.</p>'
  local server, client
  createHttpServerRedirect(body, '/newLocation', '/'):next(function(s)
    server = s
    client = createHttpClient()
    sendReceiveClose(client, '/', { redirect = 'manual' }):next(function()
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
  lu.assertEquals(client.t_response:getStatusCode(), 302)
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_requestCount, 1)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
end

function Test_HttpClientServer_redirect()
  local body = '<p>Hello.</p>'
  local server, client
  createHttpServerRedirect(body, '/newLocation', '/'):next(function(s)
    server = s
    client = createHttpClient()
    sendReceiveClose(client):next(function()
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
  lu.assertEquals(server.t_requestCount, 2)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
end

function Test_HttpClientServer_redirect_2()
  local body = '<p>Hello.</p>'
  local server, client
  createHttpServerRedirect(body, '/newerLocation', '/newLocation', '/'):next(function(s)
    server = s
    client = createHttpClient()
    client.maxRedirectCount = 5
    sendReceiveClose(client):next(function()
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
  lu.assertEquals(server.t_requestCount, 3)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
end

function Test_HttpClientServer_redirect_too_much()
  local body = '<p>Hello.</p>'
  local server, client
  local paths = {}
  for i = 1, 20 do
    table.insert(paths, '/location-'..i)
  end
  table.insert(paths, '/')
  createHttpServerRedirect(body, table.unpack(paths)):next(function(s)
    server = s
    client = createHttpClient()
    sendReceiveClose(client):next(function()
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
  lu.assertEquals(client.t_response:getStatusCode(), 302)
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_requestCount, 20)
end

function Test_HttpServer_keep_alive()
  local req = createHttpRawRequest(nil, nil, createRawHeaders({Connection = 'keep-alive'}))
  local server, client
  createHttpServer():next(function(s)
    logger:fine('http server created')
    server = s
    return createTcpClient()
  end):next(function(c)
    logger:fine('http client created')
    client = c
    return client:write(req)
  end):next(function()
    logger:fine('http first request write completed')
    return client:write(createHttpRawRequest())
  end):finally(function()
    logger:fine('http second request write completed')
    --server:close()
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertNotIsNil(client)
  lu.assertNotIsNil(server)
  lu.assertIsNil(server.t_err)
  lu.assertEquals(server.t_requestCount, 2)
  lu.assertEquals(server.t_request:getMethod(), 'GET')
  local bodies = strings.split(client.t_receivedData, 'HTTP/1%.')
  logger:finest('http client received '..List.join(bodies, '+'))
  lu.assertEquals(#bodies, 3)
end

function Test_HttpClientServer_keep_alive()
  local server, client
  local count = 0
  createHttpServer(function(exchange)
    logger:fine('http server created')
    local response = exchange:getResponse()
    response:setStatusCode(200, 'Ok')
    response:setBody('<p>Hello.</p>')
    count = count + 1
  end):next(function(s)
    server = s
    client = HttpClient:new('http://127.0.0.1:'..tostring(TEST_PORT)..'/')
    client:fetch('/'):next(function(response)
      return response:consume()
    end):next(function()
      logger:fine('send receive completed for first request')
      return client:fetch('/')
    end):next(function(response)
      return response:consume()
    end):next(function()
      logger:fine('send receive completed for second request')
    end):catch(function(err)
      logger:warn('send receive error: "'..tostring(err)..'"')
    end):finally(function()
      logger:fine('closing client and server')
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

local function getSearchParams(resource)
  local exchange = HttpExchange:new()
  exchange:getRequest():setLine('GET '..resource..' HTTP/1.1')
  return exchange:getSearchParams()
end

function Test_HttpMessage_getSearchParams()
  lu.assertEquals(getSearchParams('/search?a=b&c=a+name'), { a = 'b', c = 'a name' })
  lu.assertEquals(getSearchParams('/search?q=a%2Bname'), { q = 'a+name' })
end

os.exit(lu.LuaUnit.run())
