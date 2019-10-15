--- This class allows to buffer a stream and to call a sub handler depending on specified limit or pattern.
-- @module jls.io.streams.ChunkedStreamHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')

--- A ChunkedStreamHandler class.
-- This class allows to buffer a stream and to call a sub handler depending on specified limit or pattern.
-- @type ChunkedStreamHandler
return require('jls.lang.class').create(require('jls.io.streams.StreamHandler'), function(chunkedStreamHandler, super, ChunkedStreamHandler)

  --- Creates a buffered @{StreamHandler} using the pattern and/or limit.
  -- The data will be pass to the wrapped handler depending on the limit and the pattern.
  -- @tparam StreamHandler handler the handler to wrap
  -- @tparam[opt] string pattern the pattern to use to split the buffered data to the wrapped handler
  -- @tparam[opt] number limit the max size to buffer waiting for a pattern
  -- @function ChunkedStreamHandler:new
  function chunkedStreamHandler:initialize(handler, pattern, limit)
    super.initialize(self)
    self.handler = handler
    self.limit = limit or -1
    if type(pattern) == 'string' then
      self.findCut = ChunkedStreamHandler.createPatternFinder(pattern)
    elseif type(pattern) == 'function' then
      self.findCut = pattern
    end
    self.length = 0
    if logger:isLoggable(logger.FINEST) then
      logger:finest('chunkedStreamHandler:initialize(?, '..tostring(limit)..', ?)')
    end
  end

  function chunkedStreamHandler:crunch(lastIndex, nextIndex)
    if not nextIndex then
      nextIndex = lastIndex + 1
    end
    if nextIndex < 0 then
      self.buffer = nil
      self.length = 0
      self.handler:onData(nil)
      return false
    end
    local buffer = self.buffer
    self.buffer = string.sub(buffer, nextIndex)
    self.length = self.length - nextIndex + 1
    if lastIndex < 0 then
      return true
    end
    buffer = string.sub(buffer, 1, lastIndex)
    return self.handler:onData(buffer)
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
      if self.findCut then
        while true do
          local lastIndex, nextIndex = self:findCut(self.buffer, self.length)
          if not lastIndex then
            break
          end
          if self:crunch(lastIndex, nextIndex) == false then
            return false
          end
        end
      end
      if self.limit > 0 and self.length >= self.limit then
        while self.length >= self.limit do
          if self:crunch(self.limit) == false then
            return false
          end
        end
      end
    else
      -- nil data indicates EOF
      if self.buffer and self.length > 0 then
        local part = self.buffer
        self.buffer = nil
        self.length = 0
        self.handler:onData(part)
      end
      -- propagate EOF
      self.handler:onData(nil)
      return false
    end
    return true
  end

  function chunkedStreamHandler:onError(err)
    self.handler:onError(err)
  end

  function ChunkedStreamHandler.createPatternFinder(pattern)
    return function(self, buffer)
      local ib, ie = string.find(buffer, pattern, 1, true)
      if ib then
        return ib - 1, ie + 1
      end
      return nil
    end
  end
end)
