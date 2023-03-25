--[[--
Provides stream handler class and utility functions.

A stream handler provides a way to deal with an input stream asynchronously.
Basicaly it consists in a function that will be called when data is available.
If the stream ends then the data function is called with no data allowing to execute specific steps.
If the stream has an issue then the error function is called.

Streams classes are mainly used by @{jls.net.TcpSocket|TCP} and @{jls.net.UdpSocket|UDP} protocols.

@module jls.io.StreamHandler
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

local function onDataCallback(self, ...)
  return self.cb(nil, ...)
end

local function onErrorCallback(self, err)
  self.cb(err or 'Unspecified error')
end

--- A StreamHandler class.
-- This class could be inherited to process a data stream.
-- @type StreamHandler
local StreamHandler = class.create(function(streamHandler)

  --- Creates a stream handler.
  -- The optional functions will be called with two parameters, this stream and the data or the error.
  -- The callback function will be called with two parameters, the error or nil and the data.
  -- @tparam[opt] function onData a function to use when receiving data or callback if onError is not specified.
  -- @tparam[opt] function onError a function to use in case of error.
  -- @function StreamHandler:new
  function streamHandler:initialize(onData, onError)
    if type(onData) == 'function' then
      if type(onError) == 'function' then
        self.onData = onData
        self.onError = onError
      else
        self.cb = onData
        self.onData = onDataCallback
        self.onError = onErrorCallback
      end
    end
  end

  --- The specified data is available for this stream.
  -- @param data the new data to process, nil to indicate the end of the stream.
  -- @param ... the optional parameters
  -- @return an optional promise that will resolve when the data has been processed.
  function streamHandler:onData(data, ...)
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
      self.cb = function(err, ...)
        if err then
          self:onError(err)
        else
          return self:onData(...)
        end
      end
    end
    return self.cb
  end
end)


-- This class provides a stream handler that wrap a stream handler.
StreamHandler.WrappedStreamHandler = class.create(StreamHandler, function(wrappedStreamHandler, super)

  -- Creates a wrapped @{StreamHandler}.
  -- @tparam[opt] StreamHandler handler the stream handler to wrap
  -- @function WrappedStreamHandler:new
  function wrappedStreamHandler:initialize(handler)
    super.initialize(self)
    self:setStreamHandler(handler)
  end

  function wrappedStreamHandler:getStreamHandler()
    return self.handler
  end

  function wrappedStreamHandler:setStreamHandler(handler)
    if handler then
      self.handler = StreamHandler.ensureStreamHandler(handler)
    else
      self.handler = StreamHandler.null
    end
    return self
  end

  function wrappedStreamHandler:onData(...)
    return self.handler:onData(...)
  end

  function wrappedStreamHandler:onError(err)
    self.handler:onError(err)
  end

  function wrappedStreamHandler:close()
    self.handler:close()
  end

end)

-- This class allows to stream to two streams.
local BiStreamHandler = class.create(StreamHandler, function(biStreamHandler, super)

  function biStreamHandler:initialize(firstStream, secondStream)
    super.initialize(self)
    self.firstStream = StreamHandler.ensureStreamHandler(firstStream)
    self.secondStream = StreamHandler.ensureStreamHandler(secondStream)
  end

  function biStreamHandler:onData(...)
    local fr = self.firstStream:onData(...)
    local sr = self.secondStream:onData(...)
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

-- Do not propagate the end of stream
local KeepStreamHandler = class.create(StreamHandler.WrappedStreamHandler, function(keepStreamHandler)

  function keepStreamHandler:onData(data, ...)
    if data then
      return self.handler:onData(data, ...)
    else
      self.handler = StreamHandler.null
    end
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
function StreamHandler.fill(sh, data, ...)
  local r
  if data and #data > 0 then
    r = sh:onData(data, ...)
  end
  if Promise:isInstance(r) then
    return r:next(function()
      return sh:onData()
    end)
  end
  return sh:onData() or r
end

--- Creates a stream handler with two handlers.
-- @tparam StreamHandler first The first stream handler.
-- @tparam StreamHandler second The second stream handler.
-- @treturn StreamHandler a StreamHandler.
function StreamHandler.tee(...)
  return BiStreamHandler:new(...)
end
function StreamHandler.keep(...)
  return KeepStreamHandler:new(...)
end
function StreamHandler.wrap(...)
  return StreamHandler.WrappedStreamHandler:new(...)
end

StreamHandler.bi = StreamHandler.tee

--- Creates a BlockStreamHandler that allows to pass fixed size blocks to the wrapped handler.
-- @tparam[opt] StreamHandler handler the handler to wrap
-- @tparam[opt] number size the block size, default to 512
-- @treturn StreamHandler a StreamHandler.
function StreamHandler.block(...)
  return require('jls.io.streams.BlockStreamHandler'):new(...)
end
--- Creates a BufferedStreamHandler that allows to buffer the stream to pass to the wrapped handler.
-- The data will be pass to the wrapped handler once.
-- @tparam[opt] StreamHandler handler the handler to wrap
-- @treturn StreamHandler a StreamHandler.
function StreamHandler.buffer(...)
  return require('jls.io.streams.BufferedStreamHandler'):new(...)
end
--- Reads the specified file using the stream handler.
-- @param file The file to read.
-- @param stream The stream handler to use with the file content.
-- @tparam[opt] number size The read block size.
-- @return a promise that resolves once the file has been fully read.
function StreamHandler.fromFile(...)
  return require('jls.io.streams.FileStreamHandler').readAll(...)
end
--- Creates a FileStreamHandler that allows to write a stream into a file.
-- @tparam jls.io.File file The file to write to
-- @tparam[opt] boolean overwrite true to indicate that existing file must be re created
-- @treturn StreamHandler a StreamHandler.
function StreamHandler.toFile(...)
  return require('jls.io.streams.FileStreamHandler'):new(...)
end
--- Returns a Promise that resolves once the stream ends.
-- @tparam[opt] StreamHandler handler the handler to wrap
-- @treturn jls.lang.Promise a promise that resolves once the stream ends.
-- @treturn StreamHandler a StreamHandler.
function StreamHandler.promise(...)
  local sh = require('jls.io.streams.PromiseStreamHandler'):new(...)
  return sh:getPromise(), sh
end
--- Creates a StreamHandler with a `read()` method.
-- Each call to `read` returns a promise that resolves to the next available data or nil if the stream ended.
-- The promise is rejected if there is an error or the stream ended.
-- @treturn StreamHandler a StreamHandler.
function StreamHandler.promises()
  return require('jls.io.streams.PromisesStreamHandler'):new()
end

--- The standard stream writing data to standard output and error to standard error.
StreamHandler.std = StreamHandler:new(function(err, data)
  if err then
    io.stderr:write(tostring(err))
  elseif data then
    io.stdout:write(data)
  end
end)

--- The null stream.
StreamHandler.null = StreamHandler:new()

return StreamHandler
