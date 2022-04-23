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
local std = StreamHandler:new(function(_, data)
  if data then
    io.stdout:write(data)
  end
end, function(_, err)
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

-- see https://streams.spec.whatwg.org/

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')

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
  -- @return an optional promise that will resolve when the data has been processed.
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
local BiStreamHandler = class.create(StreamHandler, function(biStreamHandler, super)

  function biStreamHandler:initialize(firstStream, secondStream)
    super.initialize(self)
    self.firstStream = StreamHandler.ensureStreamHandler(firstStream)
    self.secondStream = StreamHandler.ensureStreamHandler(secondStream)
  end

  function biStreamHandler:onData(data)
    local fr = self.firstStream:onData(data)
    local sr = self.secondStream:onData(data)
    if fr or sr then
      local fp = Promise:isInstance(fr) and fr or nil
      local sp = Promise:isInstance(sr) and sr or nil
      if fp or sp then
        if fp and sp then
          return Promise.all({fp, sp})
        end
        return fp or sp
      end
    end
    if fr ~= nil then
      return fr
    end
    return sr
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

--- Returns a callback function.
-- @param cb a callback function or a StreamHandler.
-- @tparam[opt] boolean lazy true to indicate that nil values are valid.
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

--- Returns a StreamHandler.
-- @param sh a callback function or a StreamHandler.
-- @treturn StreamHandler a StreamHandler.
function StreamHandler.ensureStreamHandler(sh)
  if StreamHandler:isInstance(sh) then
    return sh
  elseif type(sh) == 'function' then
    return StreamHandler:new(sh)
  else
    error('Invalid argument (type is '..type(sh)..')')
  end
end

--- Fills the specified stream handler with the specified data.
-- This is shortcut for sh:onData(data); sh:onData(nil)
-- @tparam StreamHandler sh the StreamHandler to fill.
-- @tparam string data the data to process.
-- @return an optional promise that will resolve when the data has been processed.
function StreamHandler.fill(sh, data)
  local r
  if data and #data > 0 then
    r = sh:onData(data)
  end
  if Promise:isInstance(r) then
    return r:next(function()
      return sh:onData()
    end)
  end
  return sh:onData() or r
end

--- Creates a stream handler with two handlers.
-- @tparam StreamHandler firstStream The first stream handlers.
-- @tparam StreamHandler secondStream The second stream handlers.
-- @treturn StreamHandler a StreamHandler.
function StreamHandler.tee(...)
  return BiStreamHandler:new(...)
end

StreamHandler.bi = StreamHandler.tee

function StreamHandler.block(...)
  return require('jls.io.streams.BlockStreamHandler'):new(...)
end
function StreamHandler.buffer(...)
  return require('jls.io.streams.BufferedStreamHandler'):new(...)
end
function StreamHandler.chunk(...)
  return require('jls.io.streams.ChunkedStreamHandler'):new(...)
end
function StreamHandler.delay(...)
  return require('jls.io.streams.DelayedStreamHandler'):new(...)
end
function StreamHandler.file(...)
  return require('jls.io.streams.FileStreamHandler'):new(...)
end
function StreamHandler.promise(...)
  return require('jls.io.streams.PromiseStreamHandler'):new(...)
end
function StreamHandler.range(...)
  return require('jls.io.streams.RangeStreamHandler'):new(...)
end
function StreamHandler.wrap(...)
  return require('jls.io.streams.WrappedStreamHandler'):new(...)
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
