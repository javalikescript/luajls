--[[--
Provide stream helper classes and functions.

Streams classes are mainly used by @{jls.net|network} protocols TCP and UDP.

@module jls.io.streams
@pragma nostrip
]]

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')

--- A StreamHandler class.
-- This class could be inherited to process a data stream.
-- @type StreamHandler
local StreamHandler = class.create(function(streamHandler)

  --- Creates a stream handler.
  -- @function StreamHandler:new
  function streamHandler:initialize()
  end

  --- The specified data is available for this stream.
  -- @param data the new data to process, nil to indicate the end of the stream.
  -- @treturn boolean false to indicate that this handler has finish to process the stream.
  function streamHandler:onData(data)
  end

  --- The specified error occured for this stream.
  -- @param err the error that occured on this stream.
  function streamHandler:onError(err)
  end

  --- Translate this stream handler to a callback function.
  -- The callback function has two arguments: the error and the data.
  -- The data could be nil indicating the end of the stream.
  -- @treturn function the callback function
  function streamHandler:toCallback()
    local sh = self
    return function(err, data)
      if err then
        sh:onError(err)
      else
        return sh:onData(data)
      end
    end
  end
end)


--- This class allows to wrap a callback function into a stream.
-- @type CallbackStreamHandler
local CallbackStreamHandler = class.create(StreamHandler, function(callbackStreamHandler)
  --- Creates a @{StreamHandler} based on a callback.
  -- @tparam function cb the callback
  -- @function CallbackStreamHandler:new
  function callbackStreamHandler:initialize(cb)
    self.cb = cb
  end
  function callbackStreamHandler:onData(data)
    return self.cb(nil, data)
  end
  function callbackStreamHandler:onError(err)
    self.cb(err or 'Unspecified error')
  end
  function callbackStreamHandler:toCallback()
    return self.cb
  end
end)


--- A BufferedStreamHandler class.
-- This class allows to buffer the stream to pass to the wrapped handler.
-- @type BufferedStreamHandler
local BufferedStreamHandler = class.create(StreamHandler, function(bufferedStreamHandler, super)

  local StringBuffer = require('jls.lang.StringBuffer')

  --- Creates a buffered @{StreamHandler}.
  -- The data will be pass to the wrapped handler once.
  -- @tparam StreamHandler handler the handler to wrap
  -- @tparam[opt] boolean noData true to indicate that the wrapped handler does not need the buffered data
  -- @function BufferedStreamHandler:new
  function bufferedStreamHandler:initialize(handler, noData)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('bufferedStreamHandler:initialize()')
    end
    super.initialize(self)
    self.handler = handler
    self.noData = noData or false
    self.buffer = StringBuffer:new()
  end

  function bufferedStreamHandler:getStringBuffer()
    return self.buffer
  end

  function bufferedStreamHandler:getBuffer()
    return self.buffer:toString()
  end

  function bufferedStreamHandler:onData(data)
    if logger:isLoggable(logger.FINER) then
      logger:finer('bufferedStreamHandler:onData(#'..tostring(data and #data)..')')
    end
    if data then
      self.buffer:append(data)
    else
      if not self.noData and self.buffer:length() > 0 then
        self.handler:onData(self.buffer:toString())
      end
      self.handler:onData(nil)
      return false
    end
    return true
  end

  function bufferedStreamHandler:onError(err)
    self.handler:onError(err)
  end

end)

--- A LimitedStreamHandler class.
-- This class allows to limit the stream to pass to the wrapped handler to a specified size.
-- @type LimitedStreamHandler
local LimitedStreamHandler = class.create(StreamHandler, function(limitedStreamHandler, super)

  --- Creates a @{StreamHandler} with a limited size.
  -- The data will be pass to the wrapped handler up to the limit.
  -- @tparam StreamHandler handler the handler to wrap
  -- @tparam[opt] number limit the max size to handle
  -- @function LimitedStreamHandler:new
  function limitedStreamHandler:initialize(handler, limit)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('limitedStreamHandler:initialize(?, '..tostring(limit)..')')
    end
    super.initialize(self)
    self.handler = handler
    self.limit = limit
    self.length = 0
  end

  function limitedStreamHandler:getBuffer()
    return self.buffer
  end

  function limitedStreamHandler:onData(data)
    if logger:isLoggable(logger.FINER) then
      logger:finer('limitedStreamHandler:onData(#'..tostring(data and #data)..') '..tostring(self.length)..'/'..tostring(self.limit))
    end
    if data then
      local length = string.len(data)
      self.length = self.length + length
      if self.length < self.limit then
        return self.handler:onData(data)
      end
      local part = data
      if self.length > self.limit then
        local partLength = length - (self.length - self.limit)
        self.buffer = string.sub(data, partLength + 1)
        part = string.sub(data, 1, partLength)
      end
      self.handler:onData(part)
      self.handler:onData(nil)
      return false
    end
    -- propagate EOF
    self.handler:onData(nil)
    return false
  end

  function limitedStreamHandler:onError(err)
    self.handler:onError(err)
  end

end)

--- A ChunkedStreamHandler class.
-- This class allows to buffer a stream and to call a sub handler depending on specified limit or pattern.
-- @type ChunkedStreamHandler
local ChunkedStreamHandler = class.create(StreamHandler, function(chunkedStreamHandler, super, ChunkedStreamHandler)

  --- Creates a buffered @{StreamHandler} using the pattern and/or limit.
  -- The data will be pass to the wrapped handler depending on the limit and the pattern.
  -- @tparam StreamHandler handler the handler to wrap
  -- @tparam[opt] string pattern the pattern to use to split the buffered data to the wrapped handler
  -- @tparam[opt] number limit the max size to buffer waiting for a pattern
  -- @function ChunkedStreamHandler:new
  function chunkedStreamHandler:initialize(handler, pattern, limit)
    super.initialize(self)
    self.handler = handler
    self.limit = limit or -1
    if type(pattern) == 'string' then
      self.findCut = ChunkedStreamHandler.createPatternFinder(pattern)
    elseif type(pattern) == 'function' then
      self.findCut = pattern
    end
    self.length = 0
    if logger:isLoggable(logger.FINEST) then
      logger:finest('chunkedStreamHandler:initialize(?, '..tostring(limit)..', ?)')
    end
  end

  function chunkedStreamHandler:crunch(lastIndex, nextIndex)
    if not nextIndex then
      nextIndex = lastIndex + 1
    end
    if nextIndex < 0 then
      self.buffer = nil
      self.length = 0
      self.handler:onData(nil)
      return false
    end
    local buffer = self.buffer
    self.buffer = string.sub(buffer, nextIndex)
    self.length = self.length - nextIndex + 1
    if lastIndex < 0 then
      return true
    end
    buffer = string.sub(buffer, 1, lastIndex)
    return self.handler:onData(buffer)
  end

  function chunkedStreamHandler:getBuffer()
    return self.buffer
  end

  function chunkedStreamHandler:onData(data)
    if logger:isLoggable(logger.FINER) then
      if logger:isLoggable(logger.FINEST) then
        logger:finest('chunkedStreamHandler:onData("'..tostring(data)..'")')
      else
        logger:finer('chunkedStreamHandler:onData(#'..tostring(data and #data)..')')
      end
    end
    if data then
      local length = string.len(data)
      if self.buffer then
        self.buffer = self.buffer..data
      else
        self.buffer = data
      end
      self.length = self.length + length
      if self.findCut then
        while true do
          local lastIndex, nextIndex = self:findCut(self.buffer, self.length)
          if not lastIndex then
            break
          end
          if self:crunch(lastIndex, nextIndex) == false then
            return false
          end
        end
      end
      if self.limit > 0 and self.length >= self.limit then
        while self.length >= self.limit do
          if self:crunch(self.limit) == false then
            return false
          end
        end
      end
    else
      -- nil data indicates EOF
      if self.buffer and self.length > 0 then
        local part = self.buffer
        self.buffer = nil
        self.length = 0
        self.handler:onData(part)
      end
      -- propagate EOF
      self.handler:onData(nil)
      return false
    end
    return true
  end

  function chunkedStreamHandler:onError(err)
    self.handler:onError(err)
  end

  function ChunkedStreamHandler.createPatternFinder(pattern)
    return function(self, buffer)
      local ib, ie = string.find(buffer, pattern, 1, true)
      if ib then
        return ib - 1, ie + 1
      end
      return nil
    end
  end
end)

--- @section end

--- Returns a callback function.
-- @param cb a callback function or a StreamHandler.
-- @return a callback function.
local function ensureCallback(cb)
  if type(cb) == 'function' then
    return cb
  end
  return cb:toCallback()
end

--- Returns a StreamHandler.
-- @param sh a callback function or a StreamHandler.
-- @return a StreamHandler.
local function ensureStreamHandler(sh)
  if type(sh) == 'function' then
    return CallbackStreamHandler:new(sh)
  end
  return sh
end


return {
  StreamHandler = StreamHandler,
  CallbackStreamHandler = CallbackStreamHandler,
  BufferedStreamHandler = BufferedStreamHandler,
  LimitedStreamHandler = LimitedStreamHandler,
  ChunkedStreamHandler = ChunkedStreamHandler,
  ensureCallback = ensureCallback,
  ensureStreamHandler = ensureStreamHandler
}