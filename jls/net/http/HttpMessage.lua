--- This class provides common behavior for HTTP message.
-- @module jls.net.http.HttpMessage
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local strings = require('jls.util.strings')

--- The HttpMessage class represents the base class for request and response.
-- @type HttpMessage
return require('jls.lang.class').create(function(httpMessage, _, HttpMessage)

  --- Creates a new Message.
  -- @function HttpMessage:new
  function httpMessage:initialize()
    self.line = ''
    self.headers = {}
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

  --- Returns the header value for the specified name.
  -- This is the raw value and may contains multiple entries.
  -- @tparam string name the name of the header.
  -- @treturn string the header value corresponding to the name.
  function httpMessage:getHeader(name)
    return self.headers[string.lower(name)]
  end

  function httpMessage:getHeaderValues(name)
    --[[
      see
        https://www.iana.org/assignments/message-headers/message-headers.xhtml
        https://tools.ietf.org/html/rfc7231#section-5.3.4
        https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
    ]]
    local rawValue = self:getHeader(name)
    if rawValue then
      return strings.split(rawValue, '%s*,%s*')
    end
  end

  function httpMessage:setHeaderValues(name, values)
    if type(values) == 'table' then
      self:setHeader(name, table.concat(values, ', '))
    end
  end

  function httpMessage:hasHeaderIgnoreCase(name, value)
    return string.lower(self:getHeader(name)) == string.lower(value)
  end

  function httpMessage:hasHeaderValue(name, value)
    local values = self:getHeaderValues(name)
    if values then
      for _, v in ipairs(values) do
        local pv = HttpMessage.parseHeaderValue(v)
        if pv == value then
          return true
        end
      end
    end
    return false
  end

  function httpMessage:setHeader(name, value)
    local valueType = type(value)
    if valueType == 'string' or valueType == 'number' or valueType == 'boolean' then
      self.headers[string.lower(name)] = tostring(value)
    else
      logger:fine('httpMessage:setHeader('..tostring(name)..', '..tostring(value)..') Invalid value will be ignored')
    end
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

  function httpMessage:appendHeaders(buffer)
    for name, value in pairs(self:getHeaders()) do
      -- TODO Capitalize names
      buffer:append(name, ': ', tostring(value), '\r\n')
    end
    return buffer
  end

  function httpMessage:getRawHeaders()
    return self:appendHeaders(StringBuffer:new()):toString()
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

  --- Returns the header start value and a table containing the header value parameters.
  -- @tparam string value the header value to parse.
  -- @treturn string the header start value.
  -- @treturn table a table containing the header value parameters.
  function HttpMessage.parseHeaderValue(value)
    local params = strings.split(value, '%s*;%s*')
    local value = table.remove(params, 1)
    --return table.unpack(params)
    return value, params
  end

  --- Returns the header start value and a table containing the header value parameters.
  -- @tparam string value the header value to parse.
  -- @treturn string the header start value.
  -- @treturn table a table containing the header parameters as key, value.
  function HttpMessage.parseHeaderValueAsTable(value)
    local startValue, params = HttpMessage.parseHeaderValue(value)
    local t = {}
    for _, param in ipairs(params) do
      local k, v = string.match(param, '^([^=]+)%s*=%s*(.*)$')
      if k then
        t[k] = v
      end
    end
    return startValue, t
  end

  function HttpMessage.equalsIgnoreCase(a, b)
    return a == b or (type(a) == 'string' and type(b) == 'string' and string.lower(a) == string.lower(b))
  end

  HttpMessage.CONST = {

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
    HEADER_TRANSFER_ENCODING = 'Transfer-Encoding'
  }

end)
