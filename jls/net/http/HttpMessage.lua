--- This class provides common behavior for HTTP message.
-- @module jls.net.http.HttpMessage
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local StreamHandler = require('jls.io.streams.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')

--- The HttpMessage class represents the base class for request and response.
-- @type HttpMessage
return class.create('jls.net.http.HttpHeaders', function(httpMessage, super, HttpMessage)

  --- Creates a new Message.
  -- @function HttpMessage:new
  function httpMessage:initialize()
    super.initialize(self)
    self:clearLine()
    self.version = HttpMessage.CONST.VERSION_1_1
    self.body = ''
    self.bodyStreamHandler = StreamHandler.null
    --self.willRead = willRead -- indicates this message direction
  end

  function httpMessage:getLine()
    return self.line
  end

  function httpMessage:clearLine()
    self.line = ''
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

  function httpMessage:setBodyStreamHandler(sh)
    self.bodyStreamHandler = sh
  end

  function httpMessage:getBodyStreamHandler()
    return self.bodyStreamHandler
  end

  function httpMessage:bufferBody()
    self.bodyStreamHandler = BufferedStreamHandler:new(StreamHandler:new(function(err, data)
      if err then
        if logger:isLoggable(logger.FINER) then
          logger:finer('httpMessage:bufferBody() error "'..tostring(err)..'"')
        end
        self.body = ''
      elseif data then
        self.body = data
      end
    end))
  end

  -- Could be overriden to read the body, for example to store the content in a file
  function httpMessage:readBody(value)
    self.bodyStreamHandler:onData(value)
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

  function httpMessage:getBodyLength()
    return #self.body
  end

  function httpMessage:getBody()
    return self.body
  end

  function httpMessage:applyBodyLength()
    if not self:getContentLength() then
      self:setContentLength(self:getBodyLength())
    end
  end

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
    self.writeBodyCallback = httpMessage.writeBodyCallback
  end

  function httpMessage:isResponse()
    return type(self.getStatusCode) == 'function'
  end

  -- It is the caller's responsability to ensure that the content length or message headers are correctly set.
  function httpMessage:onWriteBodyStreamHandler(callback)
    local cb, pr = Promise.ensureCallback(callback)
    self.writeBodyCallback = cb
    return pr
  end

  function httpMessage:writeBodyCallback()
    local body = self:getBody()
    local sh = self:getBodyStreamHandler()
    if #body > 0 then
      sh:onData(body)
    end
    sh:onData()
  end

  function httpMessage:writeBody(stream)
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpMessage:writeBody()')
    end
    local pr, cb = Promise.createWithCallback()
    local len = 0
    self.bodyStreamHandler = StreamHandler:new(function(err, data)
      if err then
        if logger:isLoggable(logger.FINE) then
          logger:fine('httpMessage:writeBody() stream error "'..tostring(err)..'"')
        end
        cb(err)
      elseif data then
        len = len + #data
        if logger:isLoggable(logger.FINER) then
          local message = 'httpMessage:writeBody() write #'..tostring(len)..'+'..tostring(#data)
          if logger:isLoggable(logger.FINEST) then
            logger:finest(message..' "'..tostring(data)..'"')
          else
            logger:finer(message)
          end
        end
        stream:write(data)
      else
        if logger:isLoggable(logger.FINER) then
          logger:finer('httpMessage:writeBody() done #'..tostring(len))
        end
        cb()
      end
    end)
    self:writeBodyCallback()
    return pr
  end

  function httpMessage:close()
    self.bodyStreamHandler:close()
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
