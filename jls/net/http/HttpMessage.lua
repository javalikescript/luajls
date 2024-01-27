--- Represents an HTTP request or response.
-- @module jls.net.http.HttpMessage
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local StreamHandler = require('jls.io.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')
local Date = require('jls.util.Date')
local strings = require('jls.util.strings')

--- The HttpMessage class represents the base class for HTTP request and HTTP response.
-- This class inherits from @{HttpHeaders}.
-- @type HttpMessage
return class.create('jls.net.http.HttpHeaders', function(httpMessage, super, HttpMessage)

  --- Creates a new Message.
  -- @function HttpMessage:new
  function httpMessage:initialize()
    super.initialize(self)
    self.body = ''
    self.bodyStreamHandler = StreamHandler.null
    self.line = ''
    self.version = HttpMessage.CONST.VERSION_1_1
  end

  function httpMessage:isRequest()
    return type(self.method) == 'string' and self.method ~= '' and type(self.target) == 'string' and self.target ~= ''
  end

  function httpMessage:isResponse()
    return type(self.statusCode) == 'number'
  end

  function httpMessage:getLine()
    if self.line == '' then
      if self:isRequest() then
        self.line = self.method..' '..self.target..' '..self:getVersion()
      elseif self:isResponse() then
        self.line = self:getVersion()..' '..tostring(self.statusCode)..' '..(self.reasonPhrase or '')
      else
        error('invalid message')
      end
    end
    return self.line
  end

  function httpMessage:setLine(line)
    -- see https://tools.ietf.org/html/rfc7230#section-3.1.1
    self.line = tostring(line)
    -- clean request and response fields
    self.method = nil
    self.target = nil
    self.statusCode = nil
    self.reasonPhrase = nil
    self.version = nil
    local method, target, version = string.match(line, "^(%S+)%s(%S+)%s(HTTP/%d+%.%d+)$")
    if method then
      self.method = string.upper(method)
      self.target = target
      self.version = string.upper(version)
      return true
    end
    local statusCode, reasonPhrase
    version, statusCode, reasonPhrase = string.match(line, "^(HTTP/%d+%.%d+)%s(%d+)%s(.*)$")
    if version then
      self.version = string.upper(version)
      self.statusCode = tonumber(statusCode)
      self.reasonPhrase = reasonPhrase
      return true
    end
    return false -- TODO Do we need to enforce line check?
  end

  --- Returns the version of this HTTP message, default to `HTTP/1.1`.
  -- @treturn string the version of this HTTP message.
  function httpMessage:getVersion()
    return self.version or HttpMessage.CONST.VERSION_1_0
  end

  --- Sets the first line of this HTTP message.
  -- @tparam string version the first line.
  function httpMessage:setVersion(version)
    if not string.find(version, 'HTTP/%d+%.?%d*') then
      error('Invalid HTTP version, '..version)
    end
    self.version = version
    self.line = ''
    return self
  end

  --- Returns this HTTP response status code.
  -- @treturn number the HTTP response status code.
  -- @treturn string the HTTP response reason phrase.
  function httpMessage:getStatusCode()
    return self.statusCode or 0, self.reasonPhrase or ''
  end

  --- Returns this HTTP response reason phrase.
  -- @treturn string the HTTP response reason phrase.
  function httpMessage:getReasonPhrase()
    return self.reasonPhrase or ''
  end

  --- Sets the status code for the response.
  -- @tparam number status the status code.
  -- @tparam[opt] string reason the reason phrase.
  -- @treturn HttpMessage this message.
  function httpMessage:setStatusCode(status, reason)
    self.statusCode = tonumber(status)
    if type(reason) == 'string' then
      self.reasonPhrase = reason
    end
    self.line = ''
    return self
  end

  function httpMessage:setReasonPhrase(reason)
    if type(reason) == 'string' then
      self.reasonPhrase = reason
    end
    self.line = ''
  end

  function httpMessage:setContentType(value)
    self:setHeader(HttpMessage.CONST.HEADER_CONTENT_TYPE, value)
  end

  function httpMessage:setCacheControl(value)
    if type(value) == 'boolean' then
      value = value and 604800 or -1 -- one week
    end
    if type(value) == 'number' then
      if value >= 0 then
        value = 'public, max-age='..tostring(value)..', must-revalidate'
      else
        value = 'no-store, no-cache, must-revalidate'
      end
    elseif type(value) ~= 'string' then
      error('Invalid cache control value')
    end
    self:setHeader(HttpMessage.CONST.HEADER_CACHE_CONTROL, value)
  end

  function httpMessage:getLastModified()
    local value = self:getHeader(HttpMessage.CONST.HEADER_LAST_MODIFIED)
    if value then
      return Date.fromRFC822String(value)
    end
  end

  function httpMessage:setLastModified(value)
    -- All HTTP date/time stamps MUST be represented in Greenwich Mean Time (GMT)
    if type(value) == 'number' then
      value = Date:new(value):toRFC822String(true)
    elseif Date:isInstance(value) then
      value = value:toRFC822String(true)
    elseif type(value) ~= 'string' then
      error('Invalid last modified value')
    end
    self:setHeader(HttpMessage.CONST.HEADER_LAST_MODIFIED, value)
  end

  --- Returns this HTTP request method, GET, POST.
  -- @treturn string the HTTP request method.
  function httpMessage:getMethod()
    return self.method
  end

  --- Sets this HTTP request method.
  -- @tparam string value the method.
  function httpMessage:setMethod(value)
    self.method = string.upper(value)
    self.line = ''
  end

  --- Returns this HTTP request target.
  -- @treturn string the HTTP request target.
  function httpMessage:getTarget()
    return self.target
  end

  --- Sets this HTTP request target.
  -- @tparam string value the target.
  function httpMessage:setTarget(value)
    self.target = value
    self.line = ''
  end

  function httpMessage:getTargetPath()
    return string.gsub(self.target, '%?.*$', '')
  end

  function httpMessage:getTargetQuery()
    return string.gsub(self.target, '^[^%?]*%??', '')
  end

  function httpMessage:getIfModifiedSince()
    local value = self:getHeader('If-Modified-Since')
    if type(value) == 'string' then
      return Date.fromRFC822String(value) + 999
    end
    return nil
  end

  function httpMessage:getContentLength()
    local value = self:getHeader(HttpMessage.CONST.HEADER_CONTENT_LENGTH)
    if type(value) == 'string' then
      return tonumber(value)
    end
    return value
  end

  function httpMessage:setContentLength(value)
    self:setHeader(HttpMessage.CONST.HEADER_CONTENT_LENGTH, value)
  end

  function httpMessage:getContentType()
    return self:getHeader(HttpMessage.CONST.HEADER_CONTENT_TYPE)
  end

  --- Returns the stream handler associated to the body.
  -- The default value is the null stream handler.
  -- @treturn StreamHandler the body stream handler.
  function httpMessage:getBodyStreamHandler()
    return self.bodyStreamHandler
  end

  --- Sets the stream handler associated to the body.
  -- @tparam StreamHandler sh the body stream handler.
  function httpMessage:setBodyStreamHandler(sh)
    if StreamHandler:isInstance(sh) then
      self.bodyStreamHandler = sh
    elseif sh == nil then
      self.bodyStreamHandler = StreamHandler.null
    else
      error('invalid argument')
    end
  end

  function httpMessage:bufferBody()
    self.bodyStreamHandler = BufferedStreamHandler:new(StreamHandler:new(function(err, data)
      if err then
        logger:warn('httpMessage:bufferBody() error "%s"', err)
        -- TODO Throw an error on getBody()?
      elseif data then
        self.body = data
      end
    end))
    return self
  end

  function httpMessage:getBodyLength()
    return #self.body
  end

  --- Returns the body of this HTTP message.
  -- @treturn string the body of this HTTP message.
  function httpMessage:getBody()
    return self.body
  end

  function httpMessage:applyBodyLength()
    -- If there no length and using body string
    if not self:getContentLength() and self.writeBodyCallback == httpMessage.writeBodyCallback then
      -- We may check the connection header
      self:setContentLength(self:getBodyLength())
    end
  end

  --- Sets the body of this HTTP message.
  -- @tparam string value the body.
  function httpMessage:setBody(value)
    if type(value) == 'string' then
      self.body = value
    elseif value == nil then
      self.body = ''
    elseif StringBuffer:isInstance(value) then
      self.body = value:toString()
    else
      error('Invalid body value, type is '..type(value))
    end
    self.writeBodyCallback = nil
  end

  --- Sets a function that will be called when the body stream handler is available to receive data.
  -- The default callback will emit the string body value.
  -- It is the caller's responsability to ensure that the content length or message headers are correctly set.
  -- @tparam[opt] function callback the function to call when the body stream handler is available.
  -- @return a promise that resolves once the body stream handler is available.
  function httpMessage:onWriteBodyStreamHandler(callback)
    local cb, pr = Promise.ensureCallback(callback)
    self.writeBodyCallback = cb
    return pr
  end

  function httpMessage:isBodyEmpty()
    if self.writeBodyCallback == httpMessage.writeBodyCallback then
      return self:getBodyLength() == 0
    end
    return false -- don't know
  end

  function httpMessage:writeBodyCallback(blockSize)
    local data = self:getBody()
    local sh = self:getBodyStreamHandler()
    -- Avoid writing huge body
    if blockSize and #data > blockSize then
      for value, ends in strings.parts(data, blockSize) do
        sh:onData(value, ends)
      end
    elseif #data > 0 then
      sh:onData(data, true)
    end
    sh:onData()
  end

  --- Consumes the body.
  -- @return a promise that resolves once the body has been received.
  function httpMessage:consume()
    return Promise.reject('not available')
  end

  --- Reads the message body as text.
  -- @return a promise that resolves to the body content as text.
  function httpMessage:text()
    self:bufferBody()
    return self:consume():next(function()
      return self.body
    end)
  end

  --- Reads the message body as JSON.
  -- @return a promise that resolves to the body content as JSON.
  function httpMessage:json()
    local json = require('jls.util.json')
    return self:text():next(function(text)
      return json.parse(text)
    end)
  end

  function httpMessage:close()
    self.bodyStreamHandler:close()
  end

  HttpMessage.CONST = {

    HTTP_CONTINUE = 100,
    HTTP_SWITCHING_PROTOCOLS = 101,

    HTTP_OK = 200,
    HTTP_CREATED = 201,
    HTTP_NO_CONTENT = 204,
    HTTP_PARTIAL_CONTENT = 206,

    HTTP_MOVED_PERMANENTLY = 301,
    HTTP_FOUND = 302,
    HTTP_NOT_MODIFIED = 304,

    HTTP_BAD_REQUEST = 400,
    HTTP_UNAUTHORIZED = 401,
    HTTP_FORBIDDEN = 403,
    HTTP_NOT_FOUND = 404,
    HTTP_METHOD_NOT_ALLOWED = 405,
    HTTP_NOT_ACCEPTABLE = 406,
    HTTP_CONFLICT = 409,
    HTTP_LENGTH_REQUIRED = 411,
    HTTP_PRECONDITION_FAILED = 412,
    HTTP_PAYLOAD_TOO_LARGE = 413,
    HTTP_UNSUPPORTED_MEDIA_TYPE = 415,
    HTTP_RANGE_NOT_SATISFIABLE = 416,

    HTTP_INTERNAL_SERVER_ERROR = 500,

    -- method names are case sensitive
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

    HEADER_HOST = 'host',
    HEADER_USER_AGENT = 'user-agent',
    HEADER_ACCEPT = 'accept',
    HEADER_ACCEPT_LANGUAGE = 'accept-language',
    HEADER_ACCEPT_ENCODING = 'accept-encoding',
    HEADER_ACCEPT_CHARSET = 'accept-charset',
    HEADER_AUTHORIZATION = 'authorization',
    HEADER_WWW_AUTHENTICATE = 'www-authenticate',
    HEADER_KEEP_ALIVE = 'keep-alive',
    HEADER_PROXY_CONNECTION = 'proxy-connection',
    HEADER_CONNECTION = 'connection',
    HEADER_LOCATION = 'location',
    HEADER_UPGRADE = 'upgrade',
    HEADER_COOKIE = 'cookie',
    HEADER_SET_COOKIE = 'set-cookie',
    HEADER_SERVER = 'server',
    HEADER_CACHE_CONTROL = 'cache-control',
    HEADER_CONTENT_DISPOSITION = 'content-disposition',
    HEADER_CONTENT_LENGTH = 'content-length',
    HEADER_CONTENT_TYPE = 'content-type',
    HEADER_TRANSFER_ENCODING = 'transfer-encoding',
    HEADER_LAST_MODIFIED = 'last-modified',
    HEADER_RANGE = 'range',
    HEADER_CONTENT_RANGE = 'content-range',
  }

end)
