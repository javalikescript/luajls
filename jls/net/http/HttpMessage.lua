--- This class provides common behavior for HTTP message.
-- @module jls.net.http.HttpMessage
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local StreamHandler = require('jls.io.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')
local RangeStreamHandler = require('jls.io.streams.RangeStreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local strings = require('jls.util.strings')

--- The HttpMessage class represents the base class for @{HttpRequest|request}
-- and @{HttpResponse|response}.
-- The HttpMessage class inherits from @{HttpHeaders}.
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

  --- Returns the first line of this HTTP message.
  -- @treturn string the first line of this HTTP message.
  function httpMessage:getLine()
    return self.line
  end

  function httpMessage:clearLine()
    self.line = ''
  end

  --- Sets the first line of this HTTP message.
  -- @tparam string line the first line.
  function httpMessage:setLine(line)
    self.line = line
    return true
  end

  --- Returns the version of this HTTP message, default to `HTTP/1.0`.
  -- @treturn string the version of this HTTP message.
  function httpMessage:getVersion()
    return self.version or HttpMessage.CONST.VERSION_1_0
  end

  --- Sets the first line of this HTTP message.
  -- @tparam string version the first line.
  function httpMessage:setVersion(version)
    self.version = version
    return self
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
    self.bodyStreamHandler = sh
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

  function httpMessage:writeHeaders(stream, callback)
    local buffer = StringBuffer:new(self:getLine(), '\r\n')
    self:appendHeaders(buffer):append('\r\n')
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpMessage:writeHeaders() "'..buffer:toString()..'"')
    end
    -- TODO write StringBuffer
    return stream:write(buffer:toString(), callback)
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
    if not self:getContentLength() then
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
    self.writeBodyCallback = httpMessage.writeBodyCallback
  end

  function httpMessage:isResponse()
    return type(self.getStatusCode) == 'function'
  end

  --- Sets a function that will be called when the body stream handler is available to receive data.
  -- The default callback will emit the string body value.
  -- It is the caller's responsability to ensure that the content length or message headers are correctly set.
  -- @tparam function callback the function to call when the body stream handler is available.
  function httpMessage:onWriteBodyStreamHandler(callback)
    local cb, pr = Promise.ensureCallback(callback)
    self.writeBodyCallback = cb
    return pr
  end

  function httpMessage:writeBodyCallback()
    local data = self:getBody()
    local sh = self:getBodyStreamHandler()
    if #data > 0 then
      sh:onData(data)
    end
    --[[
      -- Avoid writing huge body
      local BODY_BLOCK_SIZE = 1024*16
      while #data > 0 do
        local block = string.sub(data, 1, BODY_BLOCK_SIZE)
        data = string.sub(data, BODY_BLOCK_SIZE + 1)
        sh:onData(block)
      end
    ]]
    sh:onData()
  end

  local function createChunkFinder()
    local needChunkSize = true
    local chunkSize
    return function(self, buffer, length)
      if logger:isLoggable(logger.FINER) then
        logger:finer('chunkFinder(#%s, %s) chunk size: %s, needChunkSize: %s', buffer and #buffer, length, chunkSize, needChunkSize)
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
            logger:fine('line is "%s"', chunkLine)
            self:onError('Invalid chunk size, line length is '..tostring(chunkLine and #chunkLine))
          end
          return -1, ie + 1
        elseif #buffer > 2 then
          logger:fine('buffer is "%s"', buffer)
          self:onError('Chunk size not found, buffer length is '..tostring(#buffer))
        end
      else
        if chunkSize == 0 then
          if logger:isLoggable(logger.FINER) then
            logger:finer('chunkFinder() chunk ended')
          end
          -- TODO consume trailer-part
          return -1, -1
        elseif length >= chunkSize + 2 then
          needChunkSize = true
          return chunkSize, chunkSize + 2
        end
      end
      return nil
    end
  end

  local function isRequest(message)
    return message and type(message.getMethod) == 'function'
  end

  function httpMessage:readHeader(client, buffer)
    local hsh = HeaderStreamHandler:new(self)
    return hsh:read(client, buffer)
  end

  function httpMessage:readBody(stream, buffer, callback)
    local cb, promise = Promise.ensureCallback(callback)
    logger:finest('httpMessage:readBody()')
    local chunkFinder = nil
    local transferEncoding = self:getHeader(HttpMessage.CONST.HEADER_TRANSFER_ENCODING)
    if transferEncoding then
      if transferEncoding == 'chunked' then
        chunkFinder = createChunkFinder()
      else
        cb('Unsupported transfer encoding "'..transferEncoding..'"')
        return promise
      end
    end
    local length = self:getContentLength()
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpMessage:readBody() content length is '..tostring(length))
    end
    if length and length <= 0 then
      self.bodyStreamHandler:onData(nil)
      cb(nil, buffer) -- empty body
      return promise
    end
    if length and buffer then
      local bufferLength = #buffer
      if logger:isLoggable(logger.FINER) then
        logger:finer('httpMessage:readBody() remaining buffer #'..tostring(bufferLength))
      end
      if bufferLength >= length then
        local remainingBuffer = nil
        if bufferLength > length then
          logger:warn('httpMessage:readBody() remaining buffer too big '..tostring(bufferLength)..' > '..tostring(length))
          remainingBuffer = string.sub(buffer, length + 1)
          buffer = string.sub(buffer, 1, length)
        end
        StreamHandler.fill(self.bodyStreamHandler, buffer)
        cb(nil, remainingBuffer)
        return promise
      end
    end
    if not length then
      -- request without content length nor transfer encoding does not have a body
      local connection = self:getHeader(HttpMessage.CONST.HEADER_CONNECTION)
      if isRequest(self) or strings.equalsIgnoreCase(connection, HttpMessage.CONST.HEADER_UPGRADE) then
        self.bodyStreamHandler:onData(nil)
        cb(nil, buffer) -- no body
        return promise
      end
      length = -1
      if logger:isLoggable(logger.FINER) then
        logger:finer('httpMessage:readBody() connection: '..tostring(connection))
      end
      if not strings.equalsIgnoreCase(connection, HttpMessage.CONST.CONNECTION_CLOSE) and not chunkFinder then
        cb('Content length value, chunked transfer encoding or connection close expected')
        return promise
      end
    end
    local readState = 0
    -- after that we know that we have something to read from the client
    local sh = StreamHandler:new(function(err, data)
      if not err then
        local r = self.bodyStreamHandler:onData(data)
        -- we may need to wait for promise resolution prior calling the callback
        -- or we may want to stop/start in case of promise
        if data then
          return r
        end
      elseif logger:isLoggable(logger.FINE) then
        logger:fine('httpMessage:readBody() stream error is "'..tostring(err)..'"')
      end
      -- data ended or error
      if readState == 1 then
        stream:readStop()
      end
      readState = 3
      cb(err) -- TODO is there a remaining buffer
    end)
    if chunkFinder then
      sh = ChunkedStreamHandler:new(sh, chunkFinder)
    elseif length > 0 then
      sh = RangeStreamHandler:new(sh, 0, length)
    end
    if buffer and #buffer > 0 then
      sh:onData(buffer)
    end
    if readState == 0 then
      readState = 1
      stream:readStart(sh)
    end
    return promise
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
        if logger:isLoggable(logger.FINEST) then
          local message = 'httpMessage:writeBody() write #'..tostring(len)..'+'..tostring(#data)
          if logger:isLoggable(logger.DEBUG) then
            logger:debug(message..' "'..tostring(data)..'"')
          else
            logger:finest(message)
          end
        end
        return stream:write(data)
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

  local WritableBuffer = class.create(function(writableBuffer)
    function writableBuffer:initialize()
      self.buffer = StringBuffer:new()
    end
    function writableBuffer:write(data, callback)
      local cb, d = Promise.ensureCallback(callback)
      self.buffer:append(data)
      if cb then
        cb()
      end
      return d
    end
    function writableBuffer:getStringBuffer()
      return self.buffer
    end
    function writableBuffer:getBuffer()
      return self.buffer:toString()
    end
  end)

  function HttpMessage.fromString(data, message)
    if not message then
      message = HttpMessage:new()
    end
    return message, message:readHeader(nil, data):next(function(remainingHeaderBuffer)
      return message:readBody(nil, remainingHeaderBuffer)
    end)
  end

  function HttpMessage.toString(message)
    local stream = WritableBuffer:new()
    message:writeHeaders(stream)
    message:writeBody(stream)
    return stream:getBuffer()
  end

  HttpMessage.WritableBuffer = WritableBuffer

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
