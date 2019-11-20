local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local streams = require('jls.io.streams')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpRequest = require('jls.net.http.HttpRequest')

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
  local chunkFinder = nil
  local transferEncoding = message:getHeader(HttpMessage.CONST.HEADER_TRANSFER_ENCODING)
  if transferEncoding then
    if transferEncoding == 'chunked' then
      chunkFinder = createChunkFinder()
    else
      cb('Unsupported transfer encoding "'..transferEncoding..'"')
      return promise
    end
  end
  local length = message:getContentLength()
  if logger:isLoggable(logger.FINE) then
    logger:fine('readBody() content length is '..tostring(length))
  end
  if length and length <= 0 then
    message:setBody('')
    cb(nil, buffer) -- empty body
    return promise
  end
  -- TODO Overwrite HttpMessage:writeBody() to pipe body
  if length and buffer then
    local bufferLength = #buffer
    if logger:isLoggable(logger.FINE) then
      logger:fine('readBody() remaining buffer #'..tostring(bufferLength))
    end
    if bufferLength >= length then
      local remainingBuffer = nil
      if bufferLength > length then
        logger:warn('readBody() remaining buffer too big '..tostring(bufferLength)..' > '..tostring(length))
        remainingBuffer = string.sub(buffer, length + 1)
        buffer = string.sub(buffer, 1, length)
      end
      message:setBody(buffer)
      cb(nil, remainingBuffer)
      return promise
    end
  end
  if not length then
    -- request without content length nor transfer encoding does not have a body
    local connection = message:getHeader(HttpMessage.CONST.HEADER_CONNECTION)
    if HttpRequest:isInstance(message) or HttpMessage.equalsIgnoreCase(connection, HttpMessage.CONST.HEADER_UPGRADE) then
      cb(nil, buffer) -- no body
      return promise
    end
    length = -1
    if logger:isLoggable(logger.FINE) then
      logger:fine('readBody() connection is '..tostring(connection))
    end
    if not HttpMessage.equalsIgnoreCase(connection, HttpMessage.CONST.CONNECTION_CLOSE) and not chunkFinder then
      cb('Content length value, chunked transfer encoding or connection close expected')
      return promise
    end
  end
  local readState = 0
  -- after that we know that we have something to read from the client
  local readStream = streams.CallbackStreamHandler:new(function(err, data)
    if readState == 1 then
      tcpClient:readStop()
    end
    readState = 3
    if err then
      if logger:isLoggable(logger.FINE) then
        logger:fine('readBody() stream error is "'..tostring(err)..'"')
      end
    else
      if logger:isLoggable(logger.FINEST) then
        logger:finest('readBody() stream data is "'..tostring(data)..'"')
      end
      if data then
        if logger:isLoggable(logger.FINE) then
          logger:fine('readBody() stream data length is '..tostring(#data))
        end
        message:setBody(data)
      end
    end
    cb(err) -- TODO is there a remaining buffer
  end)
  local stream = streams.CallbackStreamHandler:new(function(err, data)
    if err then
      readStream:onError(err)
    else
      message:readBody(data)
      if not data then
        return readStream:onData(data)
      end
    end
  end)
  if chunkFinder then
    stream = streams.ChunkedStreamHandler:new(stream, chunkFinder)
  elseif length > 0 then
    stream = streams.LimitedStreamHandler:new(stream, length)
  end
  if buffer and #buffer > 0 then
    stream:onData(buffer)
  end
  if readState == 0 then
    readState = 1
    tcpClient:readStart(stream)
  end
  return promise
end

return readBody