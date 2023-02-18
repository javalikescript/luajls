--- Provide a block stream handler.
-- @module jls.io.streams.BlockStreamHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local StreamHandler = require('jls.io.StreamHandler')

--- A BlockStreamHandler class.
-- This class allows to pass fixed size blocks to the wrapped handler.
-- @type BlockStreamHandler
return require('jls.lang.class').create(StreamHandler.WrappedStreamHandler, function(blockStreamHandler, super)

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
    self.buffer = StringBuffer:new()
    self.multiple = multiple and true or false
  end

  function blockStreamHandler:getStringBuffer()
    return self.buffer
  end

  function blockStreamHandler:getBuffer()
    return self.buffer:toString()
  end

  function blockStreamHandler:onData(data)
    if logger:isLoggable(logger.FINER) then
      logger:finer('blockStreamHandler:onData(#'..tostring(data and #data)..')')
    end
    if data then
      self.buffer:append(data)
      local len = self.buffer:length()
      if len == 0 then
        return self.handler:onData('')
      elseif len >= self.size then
        if self.multiple then
          local r = len % self.size
          local q = len - r
          local s = self.buffer:sub(1, q)
          return self.handler:onData(s:toString())
        else
          local l = {}
          while self.buffer:length() >= self.size do
            local s = self.buffer:sub(1, self.size)
            local r = self.handler:onData(s:toString())
            if r then
              table.insert(l, Promise:isInstance(r) and r or Promise.resolve(r))
            end
          end
          if #l > 0 then
            return Promise.all(l)
          end
        end
      end
    else
      local r
      if self.buffer:length() > 0 then
        r = self.handler:onData(self.buffer:toString())
        self.buffer:clear()
      end
      self.handler:onData(nil)
      return r
    end
  end

end)
