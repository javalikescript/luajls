--- This class provides common behavior for HTTP message.
-- @module jls.net.http.HttpMessage
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local strings = require('jls.util.strings')

--- The HttpMessage class represents the base class for request and response.
-- @type HttpMessage
return require('jls.lang.class').create('jls.net.http.HttpHeaders', function(httpMessage, super, HttpMessage)

  --- Creates a new Message.
  -- @function HttpMessage:new
  function httpMessage:initialize()
    super.initialize(self)
    self.line = ''
    self.version = HttpMessage.CONST.VERSION_1_1
    self.bodyBuffer = StringBuffer:new()
  end

  function httpMessage:getLine()
    return self.line
  end

  function httpMessage:setLine(value)
    self.line = value
  end

  function httpMessage:getVersion()
    return self.version or HttpMessage.CONST.VERSION_1_0
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

  function httpMessage:hasBody()
    return self.bodyBuffer:length() > 0
  end

  function httpMessage:getBodyLength()
    return self.bodyBuffer:length()
  end

  function httpMessage:getBody()
    return self.bodyBuffer:toString()
  end

  function httpMessage:setBody(value)
    if value == nil or type(value) == 'string' then
      self.bodyBuffer:clear()
      self.bodyBuffer:append(value)
    elseif StringBuffer:isInstance(value) then
      self.bodyBuffer = value
    elseif logger:isLoggable(logger.FINER) then
      logger:finer('httpMessage:setBody('..tostring(value)..') Invalid value')
    end
  end

  function httpMessage:setBodyStreamHandler(sh)
    self.bodyBuffer = {
      len = 0,
      length = function(self)
        return self.len
      end,
      append = function(self, value)
        if value then
          self.len = self.len + #value
        end
        sh:onData(value)
      end,
      clear = function(self)
        error('Cannot clear a stream body')
      end,
      toString = function(self)
        error('Cannot return string from a stream body')
      end,
    }
  end

  -- Could be overriden to read the body, for example to store the content in a file
  function httpMessage:readBody(value)
    self.bodyBuffer:append(value)
  end

  function httpMessage:writeHeaders(stream, callback)
    local buffer = StringBuffer:new(self:getLine(), '\r\n')
    self:appendHeaders(buffer):append('\r\n')
    if logger:isLoggable(logger.FINEST) then
      logger:finest('httpMessage:writeHeaders() "'..buffer:toString()..'"')
    end
    -- TODO write StringBuffer
    return stream:write(buffer:toString(), callback)
  end

  -- Could be overriden to write the body, for example to get the content from a file
  function httpMessage:writeBody(stream, callback)
    if self:hasBody() then
      local body = self:getBody()
      if logger:isLoggable(logger.FINER) then
        if logger:isLoggable(logger.FINEST) then
          logger:finest('httpMessage:writeBody() "'..tostring(body)..'"')
        else
          logger:finer('httpMessage:writeBody() #'..tostring(#body))
        end
      end
      return stream:write(body, callback)
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

  HttpMessage.CONST = {

    HTTP_CONTINUE = 100,
    HTTP_SWITCHING_PROTOCOLS = 101,

    HTTP_OK = 200,
    HTTP_CREATED = 201,
    HTTP_NO_CONTENT= 204,

    HTTP_MOVED_PERMANENTLY = 301,
    HTTP_FOUND = 302,

    HTTP_BAD_REQUEST = 400,
    HTTP_UNAUTHORIZED = 401,
    HTTP_FORBIDDEN = 403,
    HTTP_NOT_FOUND = 404,
    HTTP_METHOD_NOT_ALLOWED = 405,
    HTTP_NOT_ACCEPTABLE = 406,
    HTTP_CONFLICT = 409,
    HTTP_LENGTH_REQUIRED = 411,
    HTTP_PRECONDITION_FAILED = 412,
    HTTP_UNSUPPORTED_MEDIA_TYPE = 415,

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
    HEADER_LOCATION = 'Location',
    HEADER_UPGRADE = 'Upgrade',
    HEADER_COOKIE = 'Cookie',
    HEADER_SERVER = 'Server',
    HEADER_CACHE_CONTROL = 'Cache-Control',
    HEADER_CONTENT_DISPOSITION = 'Content-Disposition',
    HEADER_CONTENT_LENGTH = 'Content-Length',
    HEADER_CONTENT_TYPE = 'Content-Type',
    HEADER_TRANSFER_ENCODING = 'Transfer-Encoding',
    HEADER_LAST_MODIFIED = 'Last-Modified',
  }

end)
