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
  local bsh = nil
  local transferEncoding = message:getHeader(HttpMessage.CONST.HEADER_TRANSFER_ENCODING)
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
      logger:fine('readBody() connection is '..tostring(message:getHeader(HttpMessage.CONST.HEADER_CONNECTION)))
    end
    if message:getHeader(HttpMessage.CONST.HEADER_CONNECTION) ~= HttpMessage.CONST.CONNECTION_CLOSE and not bsh then
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
  if buffer and #buffer > 0 then
    partHandler:onData(buffer)
  end
  tcpClient:readStart(partHandler)
  return promise
end

return readBody