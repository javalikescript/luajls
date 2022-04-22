--- This class allows to buffer a stream and to call a sub handler depending on specified limit or pattern.
-- @module jls.io.streams.ChunkedStreamHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')

--- A ChunkedStreamHandler class.
-- This class allows to buffer a stream and to call a sub handler depending on specified limit or pattern.
-- @type ChunkedStreamHandler
return require('jls.lang.class').create('jls.io.streams.WrappedStreamHandler', function(chunkedStreamHandler, super, ChunkedStreamHandler)

  --- Creates a buffered @{StreamHandler} using the pattern and/or limit.
  -- The data will be pass to the wrapped handler depending on the limit and the pattern.
  -- @tparam StreamHandler handler the handler to wrap
  -- @tparam string pattern the pattern to use to split the buffered data to the wrapped handler
  -- @tparam[opt] boolean plain true to use the pattern as a plain string
  -- @tparam[opt] number limit the max size to buffer waiting for a pattern
  -- @tparam[opt] string stop a data on which to stop
  -- @function ChunkedStreamHandler:new
  function chunkedStreamHandler:initialize(handler, pattern, plain, limit, stop)
    super.initialize(self, handler)
    self.limit = limit or -1
    if type(pattern) == 'string' then
      self.findCut = ChunkedStreamHandler.createPatternFinder(pattern, plain)
    elseif type(pattern) == 'function' then
      self.findCut = pattern
    else
      error('Invalid pattern type: '..type(pattern))
    end
    self.stop = stop
    self.length = 0
    if logger:isLoggable(logger.FINEST) then
      logger:finest('chunkedStreamHandler:initialize(?, '..tostring(pattern)..', '..tostring(plain)..', '..tostring(limit)..')')
    end
  end

  function chunkedStreamHandler:crunch(lastIndex, nextIndex)
    if not nextIndex then
      nextIndex = lastIndex + 1
    end
    if nextIndex < 0 then
      self.buffer = nil
      self.length = 0
      self.handler:onData()
      return true
    end
    local buffer = self.buffer
    self.buffer = string.sub(buffer, nextIndex)
    self.length = self.length - nextIndex + 1
    if lastIndex < 0 then
      return false
    end
    buffer = string.sub(buffer, 1, lastIndex)
    if logger:isLoggable(logger.FINER) then
      if logger:isLoggable(logger.FINEST) then
        logger:finest('chunkedStreamHandler:crunch('..tostring(lastIndex)..', '..tostring(nextIndex)..') => "'..tostring(buffer)..'"')
      else
        logger:finer('chunkedStreamHandler:crunch('..tostring(lastIndex)..', '..tostring(nextIndex)..') => #'..tostring(buffer and #buffer))
      end
    end
    self.handler:onData(buffer)
    return buffer == self.stop
  end

  function chunkedStreamHandler:getBuffer()
    return self.buffer
  end

  function chunkedStreamHandler:onData(data)
    if logger:isLoggable(logger.FINER) then
      if logger:isLoggable(logger.FINEST) then
        logger:finest('chunkedStreamHandler:onData("'..tostring(data)..'")')
      else
        logger:finer('chunkedStreamHandler:onData(#'..tostring(data and #data)..')')
      end
    end
    if data then
      local length = string.len(data)
      if self.buffer then
        self.buffer = self.buffer..data
      else
        self.buffer = data
      end
      self.length = self.length + length
      while true do
        local lastIndex, nextIndex = self:findCut(self.buffer, self.length)
        if not lastIndex then
          break
        end
        if self:crunch(lastIndex, nextIndex) then
          return
        end
      end
      if self.limit > 0 and self.length >= self.limit then
        while self.length >= self.limit do
          if self:crunch(self.limit) then
            return
          end
        end
      end
    else
      -- nil data indicates end of stream
      if self.buffer and self.length > 0 then
        local part = self.buffer
        self.buffer = nil
        self.length = 0
        self.handler:onData(part)
      end
      -- propagate end of stream
      self.handler:onData(nil)
    end
  end

  function ChunkedStreamHandler.createPatternFinder(pattern, plain)
    return function(_, buffer, length)
      local ib, ie = string.find(buffer, pattern, 1, plain)
      if ib then
        return ib - 1, ie + 1
      end
      return nil
    end
  end

end)
