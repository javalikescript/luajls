--[[--
Provide a delayed stream handler.

This class allows to buffer a stream while the sub handler is not available.

@module jls.io.streams.DelayedStreamHandler
@pragma nostrip
]]

local logger = require('jls.lang.logger')
local StringBuffer = require('jls.lang.StringBuffer')

--- A DelayedStreamHandler class.
-- @type DelayedStreamHandler
return require('jls.lang.class').create('jls.io.streams.WrappedStreamHandler', function(delayedStreamHandler, super)

  --- Creates a delayed @{StreamHandler}.
  -- @function DelayedStreamHandler:new
  function delayedStreamHandler:initialize()
    if logger:isLoggable(logger.FINEST) then
      logger:finest('delayedStreamHandler:initialize()')
    end
    super.initialize(self)
    self.handler = nil
    self.buffer = StringBuffer:new()
    self.error = nil
    self.ended = false
    self.closed = false
  end

  --- Sets the sub handler.
  -- The buffered and future data will be passed to the sub handler.
  -- @tparam StreamHandler handler the handler to use
  function delayedStreamHandler:setStreamHandler(handler)
    if not self.handler then
      if self.error then
        handler:onError(self.error)
      else
        if self.buffer:length() > 0 then
          for _, part in ipairs(self.buffer:getParts()) do
            handler:onData(part)
          end
        end
        if self.ended then
          handler:onData()
        end
      end
      if self.closed then
        handler:close()
      end
      self.buffer = nil
      self.error = nil
    end
    self.handler = handler
  end

  function delayedStreamHandler:isEnded()
    return self.ended
  end

  function delayedStreamHandler:isClosed()
    return self.closed
  end

  function delayedStreamHandler:getError()
    return self.error
  end

  function delayedStreamHandler:getStringBuffer()
    return self.buffer
  end

  function delayedStreamHandler:getBuffer()
    return self.buffer:toString()
  end

  function delayedStreamHandler:onData(data)
    if self.handler then
      return self.handler:onData(data)
    end
    if logger:isLoggable(logger.FINEST) then
      logger:finest('delayedStreamHandler:onData(#'..tostring(data and #data)..')')
    end
    if data then
      self.buffer:append(data)
    else
      self.ended = true
    end
  end

  function delayedStreamHandler:onError(err)
    if self.handler then
      self.handler:onError(err)
    else
      self.ended = true
      if not self.error then
        self.error = err
      end
    end
  end

  function delayedStreamHandler:close()
    if self.handler then
      self.handler:close()
    else
      self.closed = true
    end
  end

end)
