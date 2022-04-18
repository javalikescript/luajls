local logger = require('jls.lang.logger')

return require('jls.lang.class').create('jls.io.streams.WrappedStreamHandler', function(rangeStreamHandler, super, RangeStreamHandler)

  function rangeStreamHandler:initialize(handler, offset, length)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('rangeStreamHandler:initialize(?, '..tostring(offset)..', '..tostring(length)..')')
    end
    super.initialize(self, handler)
    self.first = offset or 0
    self.last = offset + length - 1
    self.offset = 0
  end

  function rangeStreamHandler:onData(data)
    if data then
      local size = #data
      local first = self.offset
      local nextOffset = first + size
      self.offset = nextOffset
      --print('range ['..tostring(self.first)..'-'..tostring(self.last)..'] onData(#'..tostring(size)..') ['..tostring(first)..'-'..tostring(nextOffset)..']')
      if first >= self.first and nextOffset < self.last then
        return self.handler:onData(data)
      end
      if nextOffset <= self.first then
        return -- skipped
      end
      if first > self.last then
        return false
      end
      local i = 1
      if self.first > first then
        i = self.first - first + 1
      end
      if nextOffset <= self.last then
        return self.handler:onData(string.sub(data, i))
      end
      local handler = self.handler
      self.handler = RangeStreamHandler.null
      return RangeStreamHandler.fill(handler, string.sub(data, i, self.last - first + 1))
    end
    local handler = self.handler
    self.handler = RangeStreamHandler.null
    return handler:onData()
  end

end)
