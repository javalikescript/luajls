--[[--
Base stream handler class.

A stream handler provides a way to deal with an input stream asynchronously.
Basicaly it consists in a function that will be called when data is available.
If the stream ends then the data function is called with no data allowing to execute specific steps.
If the stream has an issue then the error function is called.

Streams classes are mainly used by @{jls.net.TcpClient|TCP} @{jls.net.UdpSocket|UDP} protocols.

@module jls.io.streams.StreamHandler
@pragma nostrip

@usage
local std = StreamHandler:new(function(self, data)
  if data then
    io.stdout:write(data)
  end
end, function(self, err)
  io.stderr:write(err or 'Stream error')
end)

-- or
local std = StreamHandler:new(function(err, data)
  if err then
    io.stderr:write(tostring(err))
  elseif data then
    io.stdout:write(data)
  end
end)
]]

local class = require('jls.lang.class')

local function onDataCallback(self, data)
  return self.cb(nil, data)
end

local function onErrorCallback(self, err)
  self.cb(err or 'Unspecified error')
end

--- A StreamHandler class.
-- This class could be inherited to process a data stream.
-- @type StreamHandler
local StreamHandler = class.create(function(streamHandler)

  --- Creates a stream handler.
  -- The optional functions take two parameters, the stream and the data or the error
  -- @tparam[opt] function onDataOrCallback a function to use when receiving data or callback if onError is not specified.
  -- @tparam[opt] function onError a function to use in case of error.
  -- @function StreamHandler:new
  function streamHandler:initialize(onDataOrCallback, onError)
    if type(onDataOrCallback) == 'function' then
      if type(onError) == 'function' then
        self.onData = onDataOrCallback
        self.onError = onError
      else
        self.cb = onDataOrCallback
        self.onData = onDataCallback
        self.onError = onErrorCallback
      end
    end
  end

  --- The specified data is available for this stream.
  -- @param data the new data to process, nil to indicate the end of the stream.
  -- @treturn boolean false to indicate that this handler has finish to process the stream.
  function streamHandler:onData(data)
  end

  --- The specified error occured on this stream.
  -- @param err the error that occured on this stream.
  function streamHandler:onError(err)
  end

  --- Closes this stream handler.
  -- Do nothing by default. Must support to be called multiple times.
  function streamHandler:close()
  end

  --- Returns this stream handler as a callback function.
  -- The callback function has two arguments: the error and the data.
  -- The data could be nil indicating the end of the stream.
  -- @treturn function the callback function
  function streamHandler:toCallback()
    if not self.cb then
      self.cb = function(err, data)
        if err then
          self:onError(err)
        else
          return self:onData(data)
        end
      end
    end
    return self.cb
  end
end)

-- This class allows to stream to two streams.
-- @type BiStreamHandler
local BiStreamHandler = class.create(StreamHandler, function(biStreamHandler, super)

  -- Creates a @{StreamHandler} with two streams.
  -- @function BiStreamHandler:new
  function biStreamHandler:initialize(firstStream, secondStream)
    super.initialize(self)
    self.firstStream = StreamHandler.ensureStreamHandler(firstStream)
    self.secondStream = StreamHandler.ensureStreamHandler(secondStream)
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

  function biStreamHandler:close()
    self.firstStream:close()
    self.secondStream:close()
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

  function multipleStreamHandler:close()
    for _, stream in ipairs(self.streams) do
      stream:close()
    end
  end

end)

--- Returns a callback function.
-- @param cb a callback function or a StreamHandler.
-- @tparam[opt] lazy true to indicate that nil values are valid.
-- @treturn function a callback function.
function StreamHandler.ensureCallback(cb, lazy)
  if type(cb) == 'function' then
    return cb
  elseif StreamHandler:isInstance(cb) then
    return cb:toCallback()
  elseif not lazy or cb ~= nil then
    error('Invalid argument')
  end
end

-- This class allows to wrap a callback function into a stream.
local CallbackStreamHandler = class.create(StreamHandler, function(callbackStreamHandler)

  -- Creates a @{StreamHandler} based on a callback.
  -- @tparam function cb the callback
  -- @function CallbackStreamHandler:new
  function callbackStreamHandler:initialize(cb)
    --super.initialize(self, cb)
    self.cb = cb
  end

  callbackStreamHandler.onData = onDataCallback
  callbackStreamHandler.onError = onErrorCallback

  function callbackStreamHandler:toCallback()
    return self.cb
  end

end)

StreamHandler.CallbackStreamHandler = CallbackStreamHandler

--- Returns a StreamHandler.
-- @param sh a callback function or a StreamHandler.
-- @return a StreamHandler.
function StreamHandler.ensureStreamHandler(sh)
  if type(sh) == 'function' then
    return CallbackStreamHandler:new(sh)
  elseif StreamHandler:isInstance(sh) then
    return sh
  else
    error('Invalid argument (type is '..type(sh)..')')
  end
end

--- Fills the specified StreamHandler with the specified data.
-- This is shortcut for sh:onData(data); sh:onData(nil)
-- @tparam StreamHandler sh the StreamHandler to fill.
-- @tparam string data the data to process.
function StreamHandler.fill(sh, data)
  if data then
    sh:onData(data)
  end
  sh:onData(nil)
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
StreamHandler.std = StreamHandler:new(function(err, data)
  if err then
    io.stderr:write(tostring(err))
  elseif data then
    io.stdout:write(data)
  end
end)

--- A null stream.
StreamHandler.null = StreamHandler:new()

return StreamHandler
