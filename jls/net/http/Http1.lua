local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local StreamHandler = require('jls.io.StreamHandler')
local RangeStreamHandler = require('jls.io.streams.RangeStreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local HttpMessage = require('jls.net.http.HttpMessage')
local strings = require('jls.util.strings')

local Http1 = {}

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

function Http1.readHeader(tcp, message, buffer)
  local hsh = HeaderStreamHandler:new(message)
  return hsh:read(tcp, buffer)
end

function Http1.writeHeaders(tcp, message, callback)
  local buffer = StringBuffer:new(message:getLine(), '\r\n')
  message:appendHeaders(buffer):append('\r\n')
  if logger:isLoggable(logger.FINER) then
    logger:finer('Http1.writeHeaders() "'..buffer:toString()..'"')
  end
  -- TODO write StringBuffer
  return tcp:write(buffer:toString(), callback)
end

function Http1.readBody(tcp, message, buffer, callback)
  logger:finest('Http1.readBody()')
  local bsh = message:getBodyStreamHandler()
  local cb, promise = Promise.ensureCallback(callback)
  local chunkFinder = nil
  local transferEncoding = message:getHeader(HttpMessage.CONST.HEADER_TRANSFER_ENCODING)
  if transferEncoding then
    if strings.equalsIgnoreCase(transferEncoding, 'chunked') then
      chunkFinder = createChunkFinder()
    else
      cb('Unsupported transfer encoding "'..transferEncoding..'"')
      return promise
    end
  end
  local length = message:getContentLength()
  if logger:isLoggable(logger.FINER) then
    logger:finer('Http1.readBody() content length is '..tostring(length))
  end
  if length and length <= 0 then
    bsh:onData(nil)
    cb(nil, buffer) -- empty body
    return promise
  end
  if length and buffer then
    local bufferLength = #buffer
    if logger:isLoggable(logger.FINER) then
      logger:finer('Http1.readBody() remaining buffer #'..tostring(bufferLength))
    end
    if bufferLength >= length then
      local remainingBuffer = nil
      if bufferLength > length then
        logger:warn('Http1.readBody() remaining buffer too big '..tostring(bufferLength)..' > '..tostring(length))
        remainingBuffer = string.sub(buffer, length + 1)
        buffer = string.sub(buffer, 1, length)
      end
      StreamHandler.fill(bsh, buffer)
      cb(nil, remainingBuffer)
      return promise
    end
  end
  if not length then
    -- request without content length nor transfer encoding does not have a body
    local connection = message:getHeader(HttpMessage.CONST.HEADER_CONNECTION)
    if message:isRequest() or strings.equalsIgnoreCase(connection, HttpMessage.CONST.HEADER_UPGRADE) then
      bsh:onData(nil)
      cb(nil, buffer) -- no body
      return promise
    end
    length = -1
    if logger:isLoggable(logger.FINER) then
      logger:finer('Http1.readBody() connection: '..tostring(connection))
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
      local r = bsh:onData(data)
      -- we may need to wait for promise resolution prior calling the callback
      -- or we may want to stop/start in case of promise
      if data then
        return r
      end
    elseif logger:isLoggable(logger.FINE) then
      logger:fine('Http1.readBody() stream error is "'..tostring(err)..'"')
    end
    -- data ended or error
    if readState == 1 then
      tcp:readStop()
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
    tcp:readStart(sh)
  end
  return promise
end

Http1.BODY_BLOCK_SIZE = 2 << 14

function Http1.writeBody(tcp, message)
  if logger:isLoggable(logger.FINER) then
    logger:finer('Http1.writeBody()')
  end
  local pr, cb = Promise.createWithCallback()
  local len = 0
  message:setBodyStreamHandler(StreamHandler:new(function(err, data)
    if err then
      if logger:isLoggable(logger.FINE) then
        logger:fine('Http1.writeBody() stream error "'..tostring(err)..'"')
      end
      cb(err)
    elseif data then
      len = len + #data
      if logger:isLoggable(logger.FINEST) then
        local message = 'Http1.writeBody() write #'..tostring(len)..'+'..tostring(#data)
        if logger:isLoggable(logger.DEBUG) then
          logger:debug(message..' "'..tostring(data)..'"')
        else
          logger:finest(message)
        end
      end
      return tcp:write(data)
    else
      if logger:isLoggable(logger.FINER) then
        logger:finer('Http1.writeBody() done #'..tostring(len))
      end
      cb()
    end
  end))
  message:writeBodyCallback(Http1.BODY_BLOCK_SIZE)
  return pr
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

function Http1.fromString(data, message)
  if not message then
    message = HttpMessage:new()
  end
  return message, Http1.readHeader(nil, message, data):next(function(remainingHeaderBuffer)
    return Http1.readBody(nil, message, remainingHeaderBuffer)
  end)
end

function Http1.toString(message)
  local stream = WritableBuffer:new()
  Http1.writeHeaders(stream, message)
  Http1.writeBody(stream, message)
  return stream:getBuffer()
end

Http1.WritableBuffer = WritableBuffer

return Http1
