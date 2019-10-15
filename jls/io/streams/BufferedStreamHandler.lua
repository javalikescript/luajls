--- Provide a simple buffered stream.
-- @module jls.io.streams.BufferedStreamHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local StringBuffer = require('jls.lang.StringBuffer')

--- A BufferedStreamHandler class.
-- This class allows to buffer the stream to pass to the wrapped handler.
-- @type BufferedStreamHandler
return require('jls.lang.class').create(require('jls.io.streams.StreamHandler'), function(bufferedStreamHandler, super)

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
