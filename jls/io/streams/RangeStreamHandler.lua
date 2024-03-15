--- This class allows to restrict the stream to pass to the wrapped handler to a specified range.
-- @module jls.io.streams.RangeStreamHandler
-- @pragma nostrip
local logger = require('jls.lang.logger'):get(...)
local StreamHandler = require('jls.io.StreamHandler')

--- A RangeStreamHandler class.
-- This class allows to restrict the stream to pass to the wrapped handler to a specified range.
-- @type RangeStreamHandler
return require('jls.lang.class').create(StreamHandler.WrappedStreamHandler, function(rangeStreamHandler, super, RangeStreamHandler)

  --- Creates a @{StreamHandler} with a range.
  -- The data in the range will be pass to the wrapped handler.
  -- @tparam StreamHandler handler the handler to wrap
  -- @tparam[opt] number offset the offset of the range, default is 0
  -- @tparam[opt] number length the length of the range
  -- @function RangeStreamHandler:new
  function rangeStreamHandler:initialize(handler, offset, length)
    logger:finest('initialize(?, %s, %s)', offset, length)
    super.initialize(self, handler)
    self.first = offset or 0
    self.last = self.first + (length or math.maxinteger) - 1
    self.offset = 0
    self.preHandler = RangeStreamHandler.null
    self.postHandler = RangeStreamHandler.null
  end

  function rangeStreamHandler:onData(data)
    if data then
      local size = #data
      local first = self.offset
      self.offset = first + size
      if logger:isLoggable(logger.FINER) then
        logger:finer('onData(#%s) [%s-%s] => [%s-%s]', size, self.first, self.last, first, self.offset)
      end
      if first >= self.first and self.offset < self.last then
        return self.handler:onData(data)
      end
      if self.offset <= self.first then
        return self.preHandler:onData(data)
      end
      if first > self.last then
        return self.postHandler:onData(data)
      end
      local i = 1
      if self.first > first then
        i = self.first - first + 1
      end
      if i > 1 then
        self.preHandler:onData(string.sub(data, 1, i - 1))
      end
      if self.offset <= self.last then
        return self.handler:onData(string.sub(data, i))
      end
      local j = self.last - first + 1
      self.postHandler:onData(string.sub(data, j + 1))
      return RangeStreamHandler.fill(self.handler, string.sub(data, i, j))
    end
    if self.offset < self.last then
      self.offset = self.last
      return self.handler:onData()
    end
    return self.postHandler:onData()
  end

end)
