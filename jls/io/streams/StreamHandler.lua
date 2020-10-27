--- Base stream handler class.
-- @module jls.io.streams.StreamHandler
-- @pragma nostrip

local class = require('jls.lang.class')

--- A StreamHandler class.
-- This class could be inherited to process a data stream.
-- @type StreamHandler
local StreamHandler = class.create(function(streamHandler)

  --- Creates a stream handler.
  -- The optional functions take two parameters, the stream and the data or the error
  -- @tparam[opt] function onData a function to use when receiving data.
  -- @tparam[opt] function onError a function to use in case of error.
  -- @function StreamHandler:new
  function streamHandler:initialize(onData, onError, callback)
    if type(callback) == 'function' then
      function self:onData(data)
        callback(nil, data)
      end
      function self:onError(err)
        callback(err or '')
      end
    else
      if type(onData) == 'function' then
        self.onData = onData
      end
      if type(onError) == 'function' then
        self.onError = onError
      end
    end
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

-- This class allows to stream to two streams.
-- @type BiStreamHandler
local BiStreamHandler = class.create(StreamHandler, function(biStreamHandler, super)

  -- Creates a @{StreamHandler} with two streams.
  -- @function BiStreamHandler:new
  function biStreamHandler:initialize(firstStream, secondStream)
    super.initialize(self)
    self.firstStream = firstStream
    self.secondStream = secondStream
  end

  function biStreamHandler:onData(data)
    local r
    if self.firstStream:onData(data) == false then
      r = false
    end
    if self.secondStream:onData(data) == false then
      r = false
    end
    return r
  end

  function biStreamHandler:onError(err)
    self.firstStream:onError(err)
    self.secondStream:onError(err)
  end

end)

-- This class allows to stream to multiple streams.
-- @type MultipleStreamHandler
local MultipleStreamHandler = class.create(StreamHandler, function(multipleStreamHandler, super)

  -- Creates a @{StreamHandler} with multiple streams.
  -- @function MultipleStreamHandler:new
  function multipleStreamHandler:initialize(...)
    super.initialize(self)
    self.streams = {...}
  end

  function multipleStreamHandler:onData(data)
    local r
    for _, stream in ipairs(self.streams) do
      if stream:onData(data) == false then
        r = false
      end
    end
    return r
  end

  function multipleStreamHandler:onError(err)
    for _, stream in ipairs(self.streams) do
      stream:onError(err)
    end
  end

end)

--- Returns a callback function.
-- @param cb a callback function or a StreamHandler.
-- @treturn function a callback function.
function StreamHandler.ensureCallback(cb)
  if type(cb) == 'function' then
    return cb
  elseif StreamHandler:isInstance(cb) then
    return cb:toCallback()
  else
    error('Invalid argument')
  end
end

function StreamHandler.bi(...)
  return BiStreamHandler:new(...)
end

function StreamHandler.multiple(...)
  local firstStream, secondStream, thirdStream = ...
  if thirdStream then
    return MultipleStreamHandler:new(...)
  elseif secondStream then
    return BiStreamHandler:new(firstStream, secondStream)
  end
  return firstStream
end

--- The standard stream writing data to standard output and error to standard error.
StreamHandler.std = StreamHandler:new(function(_, data)
  if data then
    io.stdout:write(data)
  end
end, function(_, err)
  io.stderr:write(err or 'Stream error')
end)

--- The null stream.
StreamHandler.null = StreamHandler:new()

return StreamHandler
