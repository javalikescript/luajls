--- This class allows to limit the stream to pass to the wrapped handler to a specified size.
-- @module jls.io.streams.LimitedStreamHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')

--- A LimitedStreamHandler class.
-- This class allows to limit the stream to pass to the wrapped handler to a specified size.
-- @type LimitedStreamHandler
return require('jls.lang.class').create(require('jls.io.streams.StreamHandler'), function(limitedStreamHandler, super)

  --- Creates a @{StreamHandler} with a limited size.
  -- The data will be pass to the wrapped handler up to the limit.
  -- @tparam StreamHandler handler the handler to wrap
  -- @tparam[opt] number limit the max size to handle
  -- @function LimitedStreamHandler:new
  function limitedStreamHandler:initialize(handler, limit)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('limitedStreamHandler:initialize(?, '..tostring(limit)..')')
    end
    super.initialize(self)
    self.handler = handler
    self.limit = limit
    self.length = 0
  end

  function limitedStreamHandler:getBuffer()
    return self.buffer
  end

  function limitedStreamHandler:onData(data)
    if logger:isLoggable(logger.FINER) then
      logger:finer('limitedStreamHandler:onData(#'..tostring(data and #data)..') '..tostring(self.length)..'/'..tostring(self.limit))
    end
    if data then
      local length = string.len(data)
      self.length = self.length + length
      if self.length < self.limit then
        return self.handler:onData(data)
      end
      local part = data
      if self.length > self.limit then
        local partLength = length - (self.length - self.limit)
        self.buffer = string.sub(data, partLength + 1)
        part = string.sub(data, 1, partLength)
      end
      self.handler:onData(part)
      self.handler:onData(nil)
      return false
    end
    -- propagate EOF
    self.handler:onData(nil)
    return false
  end

  function limitedStreamHandler:onError(err)
    self.handler:onError(err)
  end

end)

