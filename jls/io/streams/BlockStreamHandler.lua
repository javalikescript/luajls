--- Provide a block stream handler.
-- @module jls.io.streams.BlockStreamHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')

--- A BlockStreamHandler class.
-- This class allows to pass fixed size blocks to the wrapped handler.
-- @type BlockStreamHandler
return require('jls.lang.class').create('jls.io.streams.WrappedStreamHandler', function(blockStreamHandler, super)

  --- Creates a block @{StreamHandler}.
  -- @tparam[opt] StreamHandler handler the handler to wrap
  -- @tparam[opt] number size the block size, default to 512
  -- @tparam[opt] boolean multiple true to indicate that the resulting size must be a multiple
  -- @function BlockStreamHandler:new
  function blockStreamHandler:initialize(handler, size, multiple)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('blockStreamHandler:initialize()')
    end
    super.initialize(self, handler)
    self.size = size or 512
    self.multiple = multiple and true or false
    self.remaining = ''
  end

  function blockStreamHandler:onData(data)
    if logger:isLoggable(logger.FINER) then
      logger:finer('blockStreamHandler:onData(#'..tostring(data and #data)..')')
    end
    if data then
      local buffer = self.remaining..data
      local l = #buffer
      if l == 0 then
        return self.handler:onData(buffer)
      end
      if self.multiple then
        local r = l % self.size
        local bl = l - r
        if r == 0 then
          self.remaining = ''
        else
          self.remaining = string.sub(buffer, bl + 1, l)
          buffer = string.sub(buffer, 1, bl)
        end
        if bl > 0 then
          return self.handler:onData(buffer)
        end
      else
        local i, j = 1, self.size
        while j <= l do
          self.handler:onData(string.sub(buffer, i, j))
          i, j = j + 1, j + self.size
        end
        self.remaining = string.sub(buffer, i)
      end
    else
      if #self.remaining > 0 then
        self.handler:onData(self.remaining)
        self.remaining = ''
      end
      self.handler:onData(nil)
    end
  end

end)
