--- This module provide classes to work with HTTP.
-- @module jls.net.http

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local net = require('jls.net')
local URL = require('jls.net.URL')
local Promise = require('jls.lang.Promise')
local streams = require('jls.io.streams')
local loader = require('jls.lang.loader')

local secure = false

local socketToString = net.socketToString

local HTTP_CONST = {

  HTTP_CONTINUE = 100,
  HTTP_SWITCHING_PROTOCOLS = 101,

  HTTP_OK = 200,

  HTTP_BAD_REQUEST = 400,
  HTTP_UNAUTHORIZED = 401,
  HTTP_FORBIDDEN = 403,
  HTTP_NOT_FOUND = 404,
  HTTP_METHOD_NOT_ALLOWED = 405,
  HTTP_NOT_ACCEPTABLE = 406,
  HTTP_LENGTH_REQUIRED = 411,
  
  HTTP_INTERNAL_SERVER_ERROR = 500,

  METHOD_GET = 'GET',
  METHOD_HEAD = 'HEAD',
  METHOD_POST = 'POST',
  METHOD_PUT = 'PUT',
  METHOD_DELETE = 'DELETE',
  METHOD_OPTIONS = 'OPTIONS',
  METHOD_CONNECT = 'CONNECT',
  METHOD_PATCH = 'PATCH',
  METHOD_TRACE = 'TRACE',

  VERSION_1_0 = 'HTTP/1.0',
  VERSION_1_1 = 'HTTP/1.1',

  DEFAULT_SERVER = 'Lua jls',
  DEFAULT_USER_AGENT = 'Lua jls',

  TRANSFER_ENCODING_CHUNKED = 'chunked',
  TRANSFER_ENCODING_COMPRESS = 'compress',
  TRANSFER_ENCODING_DEFLATE = 'deflate',
  TRANSFER_ENCODING_GZIP = 'gzip',

  CONNECTION_CLOSE = 'close',
  CONNECTION_KEEP_ALIVE = 'keep-alive',

  HEADER_HOST = 'Host',
  HEADER_USER_AGENT = 'User-Agent',
  HEADER_ACCEPT = 'Accept',
  HEADER_ACCEPT_LANGUAGE = 'Accept-Language',
  HEADER_ACCEPT_ENCODING = 'Accept-Encoding',
  HEADER_ACCEPT_CHARSET = 'Accept-Charset',
  HEADER_AUTHORIZATION = 'Authorization',
  HEADER_WWW_AUTHENTICATE = 'WWW-Authenticate',
  HEADER_KEEP_ALIVE = 'Keep-Alive',
  HEADER_PROXY_CONNECTION = 'Proxy-Connection',
  HEADER_CONNECTION = 'Connection',
  HEADER_UPGRADE = 'Upgrade',
  HEADER_COOKIE = 'Cookie',
  HEADER_SERVER = 'Server',
  HEADER_CACHE_CONTROL = 'Cache-Control',
  HEADER_CONTENT_LENGTH = 'Content-Length',
  HEADER_CONTENT_TYPE = 'Content-Type',
  HEADER_TRANSFER_ENCODING = 'Transfer-Encoding'
}


local function hasSecure()
  if secure == false then
    secure = loader.tryRequire('jls.net.secure')
    if not secure then
      logger:warn('Unable to require jls.net.secure')
    end
  end
  return secure
end


--- The HttpMessage class represents the base class for request and response.
-- @type HttpMessage
local HttpMessage = class.create(function(httpMessage)

  --- Creates a new Message.
  -- @function HttpMessage:new
  function httpMessage:initialize()
    self.line = ''
    self.headers = {}
    self.version = HTTP_CONST.VERSION_1_1
  end

  function httpMessage:getLine()
    return self.line
  end

  function httpMessage:setLine(value)
    self.line = value
  end

  function httpMessage:getVersion()
    return self.version or HTTP_CONST.VERSION_1_0
  end

  --- Returns the header value for the specified name.
  -- @tparam string name the name of the header.
  -- @treturn string the header value corresponding to the name.
  function httpMessage:getHeader(name)
    return self.headers[string.lower(name)]
  end

  function httpMessage:setHeader(name, value)
    self.headers[string.lower(name)] = value
  end

  function httpMessage:parseHeaderLine(line)
    local index, _, name, value = string.find(line, '^([^:]+):%s*(.*)%s*$')
    if index then
      self:setHeader(name, value)
      return true
    end
    return false
  end

  function httpMessage:getHeaders()
    return self.headers
  end

  function httpMessage:setHeaders(headers)
    for name, value in pairs(headers) do
      self:setHeader(name, value)
    end
  end

  function httpMessage:getRawHeaders()
    local content = ''
    for name, value in pairs(self:getHeaders()) do
      -- TODO Capitalize names
      content = content..name..': '..tostring(value)..'\r\n'
    end
    return content
  end

  function httpMessage:getContentLength()
    local value = self:getHeader(HTTP_CONST.HEADER_CONTENT_LENGTH)
    if type(value) == 'string' then
      return tonumber(value)
    end
    return value
  end

  function httpMessage:setContentLength(value)
    self:setHeader(HTTP_CONST.HEADER_CONTENT_LENGTH, value)
  end

  function httpMessage:getBody()
    return self.body
  end

  function httpMessage:setBody(value)
    if value == nil or type(value) == 'string' then
      self.body = value
    elseif logger:isLoggable(logger.FINER) then
      logger:finer('httpMessage:setBody('..tostring(value)..') Invalid value')
    end
  end

  function httpMessage:writeHeaders(stream, callback)
    local buffer = self:getLine()..'\r\n'..self:getRawHeaders()..'\r\n'
    if logger:isLoggable(logger.FINEST) then
      logger:finest('httpMessage:writeHeaders() "'..buffer..'"')
    end
    return stream:write(buffer, callback)
  end

  function httpMessage:writeBody(stream, callback)
    if self.body then
      if logger:isLoggable(logger.FINER) then
        if logger:isLoggable(logger.FINEST) then
          logger:finest('httpMessage:writeBody() "'..tostring(self.body)..'"')
        else
          logger:finer('httpMessage:writeBody() #'..tostring(#self.body))
        end
      end
      return stream:write(self.body, callback)
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpMessage:writeBody() empty body')
    end
    local cb, promise = Promise.ensureCallback(callback)
    cb()
    return promise
  end

  function httpMessage:close()
  end
end)


--- The HttpRequest class represents an HTTP request.
-- The HttpRequest class inherits from @{HttpMessage}.
-- @type HttpRequest
local HttpRequest = class.create(HttpMessage, function(httpRequest, super)

  --- Creates a new Request.
  -- @function HttpRequest:new
  function httpRequest:initialize()
    super.initialize(self)
    self.method = 'GET'
    self.target = '/'
  end

  function httpRequest:getMethod()
    return self.method
  end

  function httpRequest:setMethod(value)
    self.method = value
    self.line = ''
  end

  function httpRequest:getTarget()
    return self.target
  end

  function httpRequest:setTarget(value)
    self.target = value
    self.line = ''
  end

  function httpRequest:getLine()
    if self.line == '' then
      self.line = self:getMethod()..' '..self:getTarget()..' '..self:getVersion()
    end
    return self.line
  end

  function httpRequest:setLine(line)
    self.line = line
    -- see https://tools.ietf.org/html/rfc7230#section-3.1.1
    local index, _, method, target, version = string.find(line, "(%S+)%s(%S+)%s(%S+)")
    if index then
      self.method = method
      self.target = target
      self.version = version
    else
      self.method = ''
      self.target = ''
      self.version = ''
    end
  end

  function httpRequest:getTargetPath()
    return string.gsub(self.target, '%?.*$', '')
  end

  function httpRequest:getTargetQuery()
    return string.gsub(self.target, '^[^%?]*%??', '')
  end
end)

--- The HttpResponse class represents an HTTP response.
-- The HttpResponse class inherits from @{HttpMessage}.
-- @type HttpResponse
local HttpResponse = class.create(HttpMessage, function(httpResponse, super)

  --- Creates a new Response.
  -- @function HttpResponse:new
  function httpResponse:initialize()
    super.initialize(self)
    self:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    --self:setBody('')
    --self:setHeader(HTTP_CONST.HEADER_CONNECTION, HTTP_CONST.CONNECTION_CLOSE)
    --self:setHeader(HTTP_CONST.HEADER_SERVER, HTTP_CONST.DEFAULT_SERVER)
    --self:setHeader(HTTP_CONST.HEADER_CONTENT_TYPE, 'text/html; charset=utf-8')
    --self:setHeader(HTTP_CONST.HEADER_CONTENT_LENGTH], '0')
  end

  function httpResponse:getStatusCode()
    return self.statusCode, self.reasonPhrase
  end

  function httpResponse:setStatusCode(statusCode, reasonPhrase)
    self.statusCode = tonumber(statusCode)
    if type(reasonPhrase) == 'string' then
      self.reasonPhrase = reasonPhrase
    end
    self.line = ''
  end

  function httpResponse:getReasonPhrase()
    return self.reasonPhrase
  end

  function httpResponse:setReasonPhrase(value)
    self.reasonPhrase = value
    self.line = ''
  end

  function httpResponse:setVersion(value)
    self.version = value
    self.line = ''
  end

  function httpResponse:getLine()
    if self.line == '' then
      self.line = self:getVersion()..' '..tostring(self:getStatusCode())..' '..self:getReasonPhrase()
    end
    return self.line
  end

  function httpResponse:setLine(line)
    self.line = line
    -- see https://tools.ietf.org/html/rfc7230#section-3.1.1
    local index, _, version, statusCode, reasonPhrase = string.find(line, "(%S+)%s(%S+)%s(%S+)")
    if index then
      self.version = version
      self.statusCode = tonumber(statusCode)
      self.reasonPhrase = reasonPhrase
    end
  end

  function httpResponse:setContentType(value)
    self:setHeader(HTTP_CONST.HEADER_CONTENT_TYPE, value)
  end

  function httpResponse:setCacheControl(value)
    if type(value) == 'boolean' then
      if value then
        value = 'public, max-age=31536000'
      else
        value = 'no-cache, no-store, must-revalidate'
      end
    elseif type(value) == 'number' then
      value = 'public, max-age='..tostring(value)
    end
    self:setHeader(HTTP_CONST.HEADER_CACHE_CONTROL, value)
  end
end)

local function createChunkFinder()
  local needChunkSize = true
  local chunkSize
  return function(self, buffer, length)
    if logger:isLoggable(logger.FINER) then
      logger:finer('chunkFinder('..tostring(buffer and #buffer)..', '..tostring(length)..') chunk size: '..tostring(chunkSize))
    end
    if needChunkSize then
      local ib, ie = string.find(buffer, '\r\n', 1, true)
      if ib and ib > 1 and ib < 32 then
        local chunkLine = string.sub(buffer, 1, ib - 1)
        if logger:isLoggable(logger.FINEST) then
          logger:finest('chunkFinder() chunk line: "'..chunkLine..'"')
        end
        local ic = string.find(chunkLine, ';', 1, true)
        if ic then
          chunkLine = string.sub(buffer, 1, ic - 1)
        end
        chunkSize = tonumber(chunkLine, 16)
        if chunkSize then
          needChunkSize = false
        else
          self:onError('Invalid chunk size, line length is '..tostring(chunkLine and #chunkLine))
        end
        return -1, ie + 1
      elseif #buffer > 2 then
        self:onError('Chunk size not found, buffer length is '..tostring(#buffer))
      end
    else
      if chunkSize == 0 then
        if logger:isLoggable(logger.FINER) then
          logger:finer('chunkFinder() chunk ended')
        end
        -- TODO consume trailer-part
        return -1, -1
      elseif length >= chunkSize then
        needChunkSize = true
        return chunkSize, chunkSize + 2
      end
    end
    return nil
  end
end

-- Reads a message body
local function readBody(message, tcpClient, buffer, callback)
  local cb, promise = Promise.ensureCallback(callback)
  logger:fine('readBody()')
  local bsh = nil
  local transferEncoding = message:getHeader(HTTP_CONST.HEADER_TRANSFER_ENCODING)
  if transferEncoding then
    if transferEncoding == 'chunked' then
      bsh = createChunkFinder()
    else
      cb('Unsupported transfer encoding "'..transferEncoding..'"')
      return promise
    end
  end
  local l = message:getContentLength()
  if logger:isLoggable(logger.FINE) then
    logger:fine('readBody() content length is '..tostring(l))
  end
  if l and l <= 0 then
    message:setBody('')
    cb(nil, buffer) -- empty body
    return promise
  end
  -- TODO Overwrite HttpMessage:writeBody() to pipe body
  if l and buffer then
    local bufferLength = #buffer
    if logger:isLoggable(logger.FINE) then
      logger:fine('readBody() remaining buffer #'..tostring(bufferLength))
    end
    if bufferLength >= l then
      local remainingBuffer = nil
      if bufferLength > l then
        logger:warn('readBody() remaining buffer too big '..tostring(bufferLength)..' > '..tostring(l))
        remainingBuffer = string.sub(buffer, l + 1)
        buffer = string.sub(buffer, 1, l)
      end
      message:setBody(buffer)
      cb(nil, remainingBuffer)
      return promise
    end
  end
  if not l then
    -- request without content length nor transfer encoding does not have a body
    if HttpRequest:isInstance(message) then
      cb(nil, buffer) -- no body
      return promise
    end
    l = -1
    if logger:isLoggable(logger.FINE) then
      logger:fine('readBody() connection is '..tostring(message:getHeader(HTTP_CONST.HEADER_CONNECTION)))
    end
    if message:getHeader(HTTP_CONST.HEADER_CONNECTION) ~= HTTP_CONST.CONNECTION_CLOSE and not bsh then
      cb('Content length value, chunked transfer encoding or connection close expected')
      return promise
    end
  end
  -- after that we know that we have something to read from the client
  local stream = streams.StreamHandler:new()
  function stream:onData(data)
    tcpClient:readStop()
    if logger:isLoggable(logger.FINEST) then
      logger:finest('readBody() stream:onData('..tostring(data)..')')
    end
    if data then
      if logger:isLoggable(logger.FINE) then
        logger:fine('readBody() stream:onData(#'..tostring(#data)..')')
      end
      message:setBody(data)
    end
    cb() -- TODO is there a remaining buffer
  end
  function stream:onError(err)
    tcpClient:readStop()
    if logger:isLoggable(logger.FINE) then
      logger:fine('readBody() stream:onError('..tostring(err)..')')
    end
    cb(err or 'Unknown error')
  end
  if bsh then
    stream = streams.BufferedStreamHandler:new(stream, -1)
  end
  local partHandler = streams.BufferedStreamHandler:new(stream, l, bsh)
  if buffer then
    partHandler:onData(buffer)
  end
  tcpClient:readStart(partHandler)
  return promise
end


local HeaderStreamHandler = class.create(streams.StreamHandler, function(headerStreamHandler, super)

  function headerStreamHandler:initialize(message, size)
    super.initialize(self)
    self.message = message
    self.maxLineLength = size or 2048
    self.firstLine = true
  end

  function headerStreamHandler:onData(line)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('headerStreamHandler:onData("'..tostring(line)..'")')
    end
    if not line then
      if self.firstLine then
        self:onError('No header')
      else
        self:onError('Unexpected end of header')
      end
      return false
    end
    -- decode header
    local l = string.len(line)
    if l >= self.maxLineLength then
      self:onError('Too long header line (max is '..tostring(self.maxLineLength)..')')
    elseif l == 0 then
      if self.onCompleted then
        self:onCompleted()
      end
    else
      if self.firstLine then
        self.message:setLine(line)
        if string.find(self.message:getVersion(), '^HTTP/') then
          self.firstLine = false
          return true
        else
          self:onError('Bad HTTP request line (Invalid version in "'..line..'")')
        end
      else
        if self.message:parseHeaderLine(line) then
          return true
        else
          self:onError('Bad HTTP request header ("'..line..'")')
        end
      end
    end
    return false -- stop
  end

  function headerStreamHandler:onError(err)
    if self.onCompleted then
      self:onCompleted(err or 'Unknown error')
    else
      logger:warn('HeaderStreamHandler completed in error, due to '..tostring(err))
    end
  end

  function headerStreamHandler:read(tcpClient, buffer)
    if logger:isLoggable(logger.FINE) then
      logger:fine('headerStreamHandler:read(?, #'..tostring(buffer and #buffer)..')')
    end
    if self.onCompleted then
      error('read in progress')
    end
    return Promise:new(function(resolve, reject)
      local c
      local partHandler = streams.BufferedStreamHandler:new(self, self.maxLineLength, '\r\n')
      function self:onCompleted(err)
        if logger:isLoggable(logger.FINE) then
          logger:fine('headerStreamHandler:read() onCompleted('..tostring(err)..')')
        end
        if c then
          c:readStop()
        end
        self.onCompleted = nil
        if err then
          reject(err)
        else
          resolve(partHandler:getBuffer())
        end
      end
      if buffer then
        partHandler:onData(buffer)
      end
      if self.onCompleted then
        c = tcpClient
        c:readStart(partHandler)
      end
    end)
  end
end)

--[[--
The HttpClient class enables to send an HTTP request.
@usage
local event = require('jls.lang.event')
local http = require('jls.net.http')
local httpClient = http.Client:new({
  url = 'https://www.openssl.org/',
  method = 'GET',
  headers = {}
})
httpClient:connect():next(function()
  return httpClient:sendReceive()
end):next(function(response)
  print('status code is', response:getStatusCode())
  print(response:getBody())
  httpClient:close()
end)
event:loop()
@type HttpClient
]]
local HttpClient = class.create(function(httpClient)

  --- Creates a new HTTP client.
  -- @function HttpClient:new
  -- @tparam table options A table describing the client options.
  -- @return a new HTTP client
  function httpClient:initialize(options)
    logger:finer('httpClient:initialize(...)')
    options = options or {}
    local method = options.method or 'GET'
    local request = HttpRequest:new()
    self.isSecure = false
    self.request = request
    if type(options.headers) == 'table' then
      request:setHeaders(options.headers)
    end
    request:setMethod(method)
    if type(options.url) == 'string' then
      self:setUrl(options.url)
    end
    if type(options.target) == 'string' then
      request:setTarget(options.target)
    end
    if type(options.host) == 'string' then
      self.host = options.host
    end
    if type(options.port) == 'number' then
      self.port = options.port
    end
    if type(options.body) == 'string' then
      request:setContentLength(#options.body)
      request:setBody(options.body)
    end
    if self.host then
      request:setHeader(HTTP_CONST.HEADER_HOST, self.host)
    end
    -- add accept headers
    if options.tcpClient then
      self.tcpClient = options.tcpClient
    elseif self.isSecure and hasSecure() then
      self.tcpClient = secure.TcpClient:new()
      --self.tcpClient.sslCheckHost = options.checkHost == true
    else
      self.tcpClient = net.TcpClient:new()
    end
  end

  function httpClient:setUrl(url)
    logger:finer('httpClient:setUrl('..tostring(url)..')')
    local u = URL:new(url)
    local target = u:getFile()
    self.isSecure = u:getProtocol() == 'https' or u:getProtocol() == 'wss'
    self.host = u:getHost()
    self.port = u:getPort()
    self.request:setTarget(target or '/')
  end

  --- Connects this HTTP client.
  -- @return true in case of success
  function httpClient:connect(callback)
    logger:finer('httpClient:connect()')
    return self.tcpClient:connect(self.host or 'localhost', self.port or 80, callback)
  end

  --- Closes this HTTP client.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the client is closed.
  function httpClient:close(callback)
    return self.tcpClient:close(callback)
  end

  --- Returns the HTTP message request.
  -- @return the HTTP message request.
  function httpClient:getRequest()
    return self.request
  end

  --- Returns the HTTP message response.
  -- @return the HTTP message response.
  function httpClient:getResponse()
    return self.response
  end

  --[[
  The presence of a message body in a response depends on both the
  request method to which it is responding and the response status code.
  Responses to the HEAD request method never include a message body
  because the associated response header fields (e.g., Transfer-Encoding,
  Content-Length, etc.), if present, indicate only what their values
  would have been if the request method had been GET.

  3.  If a Transfer-Encoding header field is present and the chunked
    transfer coding is the final encoding, the message body length
    is determined by reading and decoding the chunked data until the
    transfer coding indicates the data is complete.
    If a message is received with both a Transfer-Encoding and a
    Content-Length header field, the Transfer-Encoding overrides the
    Content-Length.
  5.  If a valid Content-Length header field is present without
    Transfer-Encoding, its decimal value defines the expected message
    body length in octets.
  6.  If this is a request message and none of the above are true, then
    the message body length is zero (no message body is present).
  7.  Otherwise, this is a response message without a declared message
    body length, so the message body length is determined by the
    number of octets received prior to the server closing the
    connection.
  ]]--

  --- Sends the request then receives the response.
  -- @return a promise that resolves once the response is received.
  function httpClient:sendReceive()
    logger:finer('httpClient:sendReceive()')
    local promise, resolve, reject = Promise.createWithCallbacks()
    local client = self
    local response = HttpResponse:new()
    self.request:writeHeaders(client.tcpClient):next(function()
      logger:finer('httpClient:sendReceive() writeHeaders() done')
      return client.request:writeBody(client.tcpClient)
    end):next(function()
      logger:finer('httpClient:sendReceive() writeBody() done')
      local hsh = HeaderStreamHandler:new(response)
      return hsh:read(client.tcpClient)
    end):next(function(buffer)
      logger:fine('httpClient:sendReceive() header done')
      return readBody(response, client.tcpClient, buffer)
    end):next(function()
      logger:fine('httpClient:sendReceive() body done')
      -- TODO We may want to handle redirections, status code 3xx
      resolve(response)
    end, function(err)
      if logger:isLoggable(logger.FINE) then
        logger:fine('httpClient:sendReceive() error "'..tostring(err)..'"')
      end
      reject(err or 'Unknown error')
    end)
    return promise
  end
end)

--- A class that holds attributes.
-- @type Attributes
local Attributes = class.create(function(attributes)

  --- Creates a new Attributes.
  -- @function Attributes:new
  function attributes:initialize(attributes)
    self.attributes = {}
    if attributes and type(attributes) == 'table' then
      self:setAttributes(attributes)
    end
  end

  --- Sets the specified value for the specified name.
  -- @tparam string name the attribute name
  -- @param value the attribute value
  function attributes:setAttribute(name, value)
    self.attributes[name] = value
    return self
  end

  --- Returns the value for the specified name.
  -- @tparam string name the attribute name
  -- @return the attribute value
  function attributes:getAttribute(name)
    return self.attributes[name]
  end

  function attributes:getAttributes()
    return self.attributes
  end

  function attributes:setAttributes(attributes)
    for name, value in pairs(attributes) do
      self:setAttribute(name, value)
    end
    return self
  end
end)


--- The HttpContext class maps a path to a handler.
-- The HttpContext is used by the @{HttpServer} through the @{HttpContextHolder}.
-- @type HttpContext
local HttpContext = class.create(Attributes, function(httpContext, super, HttpContext)

  --- Creates a new Context.
  -- @tparam function handler the context handler
  --   the function takes one argument which is an @{HttpExchange}.
  -- @tparam string path the context path
  -- @tparam[opt] table attributes the optional context attributes
  -- @function HttpContext:new
  function httpContext:initialize(handler, path, attributes)
    super.initialize(self, attributes)
    self.handler = handler
    self.path = path or ''
  end

  function httpContext:getHandler()
    return self.handler
  end

  function httpContext:setHandler(handler)
    self.handler = handler
    return self
  end

  function httpContext:getPath()
    return self.path
  end

  function httpContext:chainContext(context)
    return HttpContext:new(function(httpExchange)
      httpExchange:handleRequest(self):next(function()
        return httpExchange:handleRequest(context)
      end)
    return result
    end)
  end

  function httpContext:copyContext()
    return HttpContext:new(self:getHandler(), self:getPath(), self:getAttributes())
  end
end)


--- The HttpExchange class wraps the request and the response.
-- @type HttpExchange
local HttpExchange = class.create(Attributes, function(httpExchange)

  --- Creates a new Exchange.
  -- @function HttpExchange:new
  function httpExchange:initialize(server, client)
    self.attributes = {}
    self.server = server
    self.client = client
  end

  --- Returns the HTTP context.
  -- @treturn HttpContext the HTTP context.
  function httpExchange:getContext()
    return self.context
  end

  function httpExchange:setContext(value)
    self.context = value
  end

  --- Returns the HTTP request.
  -- @treturn HttpRequest the HTTP request.
  function httpExchange:getRequest()
    return self.request
  end

  function httpExchange:setRequest(value)
    self.request = value
  end

  --- Returns the HTTP response.
  -- @treturn HttpResponse the HTTP response.
  function httpExchange:getResponse()
    return self.response
  end

  function httpExchange:setResponse(value)
    self.response = value
  end

  --- Returns the captured values of the request target path using the context path.
  -- @treturn string the first captured value, nil if there is no captured value.
  function httpExchange:getRequestArguments()
    return select(3, string.find(self:getRequest():getTargetPath(), '^'..self:getContext():getPath()..'$'))
  end

  --- Returns a new HTTP response.
  -- @treturn HttpResponse a new HTTP response.
  function httpExchange:createResponse()
    local response = HttpResponse:new()
    response:setHeader(HTTP_CONST.HEADER_CONNECTION, HTTP_CONST.CONNECTION_CLOSE)
    response:setHeader(HTTP_CONST.HEADER_SERVER, HTTP_CONST.DEFAULT_SERVER)
    return response
  end

  function httpExchange:prepareResponse(response)
    local body = response:getBody()
    if not response:getContentLength() then
      if type(body) == 'string' then
        response:setContentLength(string.len(body))
      else
        response:setContentLength(0)
      end
    end
  end

  function httpExchange:handleRequest(context)
    if logger:isLoggable(logger.FINER) then
      logger:finer('HttpServer:handleRequest() "'..self:getRequest():getTarget()..'"')
    end
    self:setContext(context)
    local status, result = pcall(function ()
      local handler = context:getHandler()
      return handler(self)
    end)
    if status then
      -- always return a promise
      if Promise:isInstance(result) then
        return result
      end
      return Promise.resolve()
    end
    if logger:isLoggable(logger.WARN) then
      logger:warn('HttpServer error while handling "'..self:getRequest():getTarget()..'", due to "'..tostring(result)..'"')
    end
    local response = self:getResponse()
    response:close()
    response = self:createResponse()
    response:setStatusCode(HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
    self:setResponse(response)
    return Promise.reject(result or 'Unkown error')
  end

  function httpExchange:processResponse()
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpExchange:processResponse()')
    end
    local response = self:getResponse()
    if not response then
      return Promise.reject('No response to process')
    end
    self:prepareResponse(response)
    return response:writeHeaders(self.client):next(function()
      return response:writeBody(self.client)
    end)
  end

  function httpExchange:processRequest()
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpExchange:processRequest()')
    end
    local request = self:getRequest()
    local path = request:getTargetPath()
    local context = self.server:getHttpContext(path)
    self:setResponse(self:createResponse())
    return self:handleRequest(context)
  end

  function httpExchange:removeClient()
    local client = self.client
    self.client = nil
    return client
  end

  function httpExchange:close()
    logger:finest('httpExchange:close()')
    if self.request then
      self.request:close()
      self.request = nil
    end
    if self.response then
      self.response:close()
      self.response = nil
    end
    if self.client then
      --self.client:readStop()
      self.client:close()
      self.client = nil
    end
  end
end)

local function notFoundHandler(httpExchange)
  local response = httpExchange:getResponse()
  response:setStatusCode(HTTP_CONST.HTTP_NOT_FOUND, 'Not Found')
  response:setBody('<p>The resource "'..httpExchange:getRequest():getTarget()..'" is not available.</p>')
end


--- A class that holds HTTP contexts.
-- @type HttpContextHolder
local HttpContextHolder = class.create(function(httpContextHolder)

  --- Creates a new ContextHolder.
  -- @function HttpContextHolder:new
  function httpContextHolder:initialize()
    self.contexts = {}
    self.notFoundContext = HttpContext:new(notFoundHandler)
  end

  --- Creates a context in this server with the specified path and using the specified handler.
  -- @tparam string path The path of the context.
  -- @tparam function handler The handler function
  --   the function takes one argument which is an @{HttpExchange}.
  -- @param[opt] attributes The context attributes.
  -- @return the new context
  function httpContextHolder:createContext(path, handler, attributes)
    if type(path) ~= 'string' or path == '' then
      error('Invalid context path')
    end
    if type(handler) ~= 'function' then
      error('Invalid context handler type '..type(handler))
    end
    local context = HttpContext:new(handler, path, attributes)
    self.contexts[context:getPath()] = context
    return context
  end

  function httpContextHolder:removeContext(pathOrContext)
    if type(pathOrContext) == 'string' then
      self.contexts[pathOrContext] = nil
    elseif HttpContext:isInstance(pathOrContext) then
      for p, c in pairs(self.contexts) do
        if c == pathOrContext then
          self.contexts[p] = nil
        end
      end
    end
  end

  function httpContextHolder:removeAllContexts()
    self.contexts = {}
  end

  --[[
  function httpContextHolder:getHttpContexts()
    return self.contexts
  end

  function httpContextHolder:setHttpContexts(contexts)
    self.contexts = contexts
    return self
  end

  function httpContextHolder:addHttpContexts(contexts)
    for p, c in pairs(contexts) do
      self.contexts[p] = c
    end
    return self
  end
  ]]

  function httpContextHolder:getHttpContext(path)
    local context, maxLen = self.notFoundContext, 0
    for p, c in pairs(self.contexts) do
      local pLen = string.len(p)
      if pLen > maxLen and string.find(path, '^'..p..'$') then
        maxLen = pLen
        context = c
      end
    end
    return context
  end

  function httpContextHolder:toHandler()
    return function(httpExchange)
      local request = httpExchange:getRequest()
      local context = self:getHttpContext(request:getTargetPath())
      return httpExchange:handleRequest(context)
    end
  end
end)


--[[-- An HTTP server.
The HttpServer inherits from @{HttpContextHolder}.
@usage
local event = require('jls.lang.event')
local http = require('jls.net.http')
local hostname, port = '::', 3001
local httpServer = http.Server:new()
httpServer:bind(hostname, port):next(function()
  print('Server bound to "'..hostname..'" on port '..tostring(port))
end, function(err) -- could failed if address is in use or hostname cannot be resolved
  print('Cannot bind HTTP server, '..tostring(err))
end)
httpServer:createContext('/', function(httpExchange)
  local response = httpExchange:getResponse()
  response:setStatusCode(http.CONST.HTTP_OK)
  response:setReasonPhrase('OK')
  response:setBody('It works !')
end)
event:loop()
@type HttpServer
]]
local HttpServer = class.create(HttpContextHolder, function(httpServer, super)

  --- Creates a new HTTP server.
  -- @function HttpServer:new
  -- @return a new HTTP server
  function httpServer:initialize(tcp)
    super.initialize(self)
    self.tcpServer = tcp or net.TcpServer:new()
    local server = self
    function self.tcpServer:onAccept(client)
      server:onAccept(client)
    end
  end

  --[[
    The presence of a message body in a request is signaled by a
  Content-Length or Transfer-Encoding header field.  Request message
  framing is independent of method semantics, even if the method does
  not define any use for a message body
  ]]
  function httpServer:onAccept(client, buffer)
    logger:finer('httpServer:onAccept()')
    local server = self
    local exchange = HttpExchange:new(server, client)
    local request = HttpRequest:new()
    local keepAlive = false
    local remainingBuffer = nil
    local hsh = HeaderStreamHandler:new(request)
    -- TODO limit headers
    hsh:read(client, buffer):next(function(remainingHeaderBuffer)
      logger:finer('httpServer:onAccept() header read')
      exchange:setRequest(request)
      if request then
        keepAlive = request:getHeader(HTTP_CONST.HEADER_CONNECTION) == HTTP_CONST.CONNECTION_KEEP_ALIVE
      end
      -- TODO limit request body
      return readBody(request, client, remainingHeaderBuffer)
    end):next(function(remainingBodyBuffer)
      logger:fine('httpServer:onAccept() body done')
      remainingBuffer = remainingBodyBuffer
      return exchange:processRequest()
    end):next(function()
      logger:fine('httpServer:onAccept() request processed')
      if keepAlive and exchange:getResponse() then
        exchange:getResponse():setHeader(HTTP_CONST.HEADER_CONNECTION, HTTP_CONST.CONNECTION_KEEP_ALIVE)
      end
      local status, res = pcall(function ()
        return exchange:processResponse()
      end)
      if not status then
        logger:warn('HttpExchange:processResponse() in error due to "'..tostring(res)..'"')
        return Promise.reject(res)
      end
      return res
    end):next(function()
      logger:fine('httpServer:onAccept() response processed')
      --local response = exchange:getResponse()
      if keepAlive then
        local c = exchange:removeClient()
        if c then
          logger:fine('httpServer:onAccept() keeping client alive')
          server:onAccept(c, remainingBuffer)
        end
      end
      exchange:close()
    end, function(err)
      if logger:isLoggable(logger.FINE) then
        logger:fine('httpServer:onAccept() read header error "'..tostring(err)..'"')
      end
      exchange:close()
    end)
  end

  --- Binds this server to the specified address and port number.
  -- @tparam string node the address, the address could be an IP address or a host name.
  -- @tparam number port the port number.
  -- @tparam[opt] number backlog the accept queue size, default is 32.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is bound.
  -- @usage
  --local s = HttpServer:new()
  --s:bind('127.0.0.1', 80)
  function httpServer:bind(node, port, backlog, callback)
    return self.tcpServer:bind(node or '::', port or 80, backlog, callback)
  end

  --- Closes this server.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is closed.
  function httpServer:close(callback)
    return self.tcpServer:close(callback)
  end
end)

function HttpServer.createSecure(secureContext)
  if hasSecure() then
    local tcp = secure.TcpServer:new()
    if type(secureContext) == 'table' then
      tcp:setSecureContext(secure.Context:new(secureContext))
    end
    return HttpServer:new(tcp), tcp
  end
end


return {
  CONST = HTTP_CONST,
  Context = HttpContext,
  ContextHolder = HttpContextHolder,
  notFoundHandler = notFoundHandler,
  HeaderStreamHandler = HeaderStreamHandler,
  Message = HttpMessage,
  Request = HttpRequest,
  Response = HttpResponse,
  Client = HttpClient,
  getSecure = hasSecure,
  Server = HttpServer
}