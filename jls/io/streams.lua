--[[--
Provide stream helper classes and functions.

Streams classes are mainly used by @{jls.net|network} protocols TCP and UDP.

@module jls.io.streams
@pragma nostrip
]]

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
--local Promise = require('jls.lang.Promise')

--- A StreamHandler class.
-- This class could be inherited to process a data stream.
-- @type StreamHandler
local StreamHandler = class.create(function(streamHandler)

  --- Creates a stream handler.
  -- @tparam[opt] function onData the handler to process data
  -- @tparam[opt] function onError the handler to process error
  -- @function StreamHandler:new
  function streamHandler:initialize(onData, onError)
    if type(onData) == 'function' then
      self.onData = onData
    end
    if type(onError) == 'function' then
      self.onError = onError
    end
  end

  --- The specified data is available for this stream.
  -- @param data the new data to process, nil to indicate the end of the stream.
  -- @treturn boolean false or nil to indicate that this handler has finish to process the stream.
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
        sh:onData(data)
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
    self.cb(nil, data)
  end
  function callbackStreamHandler:onError(err)
    self.cb(err or 'Unspecified error')
  end
end)

--- A BufferedStreamHandler class.
-- This class allows to buffer a stream and to call a sub handler depending on specified limit or pattern.
-- @type BufferedStreamHandler
local BufferedStreamHandler = class.create(StreamHandler, function(bufferedStreamHandler, super, BufferedStreamHandler)

  --- Creates a buffered @{StreamHandler} with the limit and/or pattern.
  -- The data will be pass to the wrapped handler depending on the limit and the pattern.
  -- @tparam StreamHandler handler the handler to wrap
  -- @tparam number limit the max size to buffer waiting for a pattern
  -- @tparam[opt] string pattern the pattern to use to split the buffered data to the wrapped handler
  -- @tparam[opt] string buffer the buffer to start with
  -- @function BufferedStreamHandler:new
  function bufferedStreamHandler:initialize(handler, limit, pattern, buffer)
    super.initialize(self)
    self.handler = handler
    self.limit = limit
    if type(pattern) == 'string' then
      self.findCut = BufferedStreamHandler.createPatternFinder(pattern)
    elseif type(pattern) == 'function' then
      self.findCut = pattern
    end
    self.length = 0
    if buffer then
      self.buffer = buffer
      self.length = string.len(buffer)
    end
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('bufferedStreamHandler:initialize(?, '..tostring(limit)..', ?, #'..tostring(self.length)..')')
    end
  end

  function bufferedStreamHandler:crunch(lastIndex, nextIndex)
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

  function bufferedStreamHandler:getBuffer()
    return self.buffer
  end

  function bufferedStreamHandler:onData(data)
    if logger:isLoggable(logger.DEBUG) then
      if logger:isLoggable(logger.FINEST) then
        logger:finest('bufferedStreamHandler:onData("'..tostring(data)..'")')
      else
        logger:debug('bufferedStreamHandler:onData(#'..tostring(data and #data)..')')
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
          if not self:crunch(lastIndex, nextIndex) then
            return false
          end
        end
      end
      if self.limit > 0 and self.length >= self.limit then
        while self.length >= self.limit do
          if not self:crunch(self.limit) then
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

  function bufferedStreamHandler:onError(err)
    self.handler:onError(err)
  end

  function BufferedStreamHandler.createPatternFinder(pattern)
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
  ensureCallback = ensureCallback,
  ensureStreamHandler = ensureStreamHandler
}