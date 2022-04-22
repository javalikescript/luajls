--- Provide a block stream handler.
-- @module jls.io.streams.BlockStreamHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')

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
      local s = #buffer
      if s == 0 then
        return self.handler:onData(buffer)
      end
      if self.multiple then
        local r = s % self.size
        local bl = s - r
        if r == 0 then
          self.remaining = ''
        else
          self.remaining = string.sub(buffer, bl + 1, s)
          buffer = string.sub(buffer, 1, bl)
        end
        if bl > 0 then
          return self.handler:onData(buffer)
        end
      else
        local i, j = 1, self.size
        local l = {}
        while j <= s do
          local r = self.handler:onData(string.sub(buffer, i, j))
          i, j = j + 1, j + self.size
          if r then
            table.insert(l, Promise:isInstance(r) and r or Promise.resolve(r))
          end
        end
        self.remaining = string.sub(buffer, i)
        if #l > 0 then
          return Promise.all(l)
        end
      end
    else
      local r
      if #self.remaining > 0 then
        r = self.handler:onData(self.remaining)
        self.remaining = ''
      end
      self.handler:onData(nil)
      return r
    end
  end

end)
