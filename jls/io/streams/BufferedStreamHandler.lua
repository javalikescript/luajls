--- Provide a simple buffered stream handler.
-- @module jls.io.streams.BufferedStreamHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local StringBuffer = require('jls.lang.StringBuffer')
local StreamHandler = require('jls.io.StreamHandler')

--- A BufferedStreamHandler class.
-- This class allows to buffer the stream to pass to the wrapped handler.
-- @type BufferedStreamHandler
return require('jls.lang.class').create(StreamHandler.WrappedStreamHandler, function(bufferedStreamHandler, super)

  --- Creates a buffered @{StreamHandler}.
  -- The data will be pass to the wrapped handler once.
  -- @tparam[opt] StreamHandler handler the handler to wrap
  -- @function BufferedStreamHandler:new
  function bufferedStreamHandler:initialize(handler)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('bufferedStreamHandler:initialize()')
    end
    super.initialize(self, handler)
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
      if self.buffer:length() > 0 then
        return StreamHandler.fill(self.handler, self.buffer:toString())
      end
      return self.handler:onData(nil)
    end
  end

end)
