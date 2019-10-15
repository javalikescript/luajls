--- Base stream handler class.
-- @module jls.io.streams.StreamHandler
-- @pragma nostrip

--- A StreamHandler class.
-- This class could be inherited to process a data stream.
-- @type StreamHandler
return require('jls.lang.class').create(function(streamHandler)

  --- Creates a stream handler.
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
end, function(StreamHandler)

  --- Returns a callback function.
  -- @param cb a callback function or a StreamHandler.
  -- @return a callback function.
  function StreamHandler.ensureCallback(cb)
    if type(cb) == 'function' then
      return cb
    elseif StreamHandler:isInstance(cb) then
      return cb:toCallback()
    else
      error('Invalid argument')
    end
  end

  StreamHandler.std = StreamHandler:new(function(_, data)
    if data then
      io.stdout:write(data)
    end
  end, function(_, err)
    io.stderr:write(err)
  end)

  StreamHandler.null = StreamHandler:new()

end)
