-- This class provides a stream handler that wrap a stream handler.
-- @module jls.io.streams.WrappedStreamHandler
-- @pragma nostrip

local StreamHandler = require('jls.io.streams.StreamHandler')

-- A WrappedStreamHandler class.
-- @type WrappedStreamHandler
return require('jls.lang.class').create(StreamHandler, function(wrappedStreamHandler, super)

  -- Creates a wrapped @{StreamHandler}.
  -- @tparam[opt] StreamHandler handler the stream handler to wrap
  -- @function WrappedStreamHandler:new
  function wrappedStreamHandler:initialize(handler)
    super.initialize(self)
    self.handler = handler or StreamHandler.null
  end

  function wrappedStreamHandler:getStreamHandler()
    return self.handler
  end

  function wrappedStreamHandler:onData(data)
    return self.handler:onData(data)
  end

  function wrappedStreamHandler:onError(err)
    self.handler:onError(err)
  end

  function wrappedStreamHandler:close()
    self.handler:close()
  end

end)

