local class = require('jls.lang.class')
local WrappedStreamHandler = require('jls.io.StreamHandler').WrappedStreamHandler
local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')

local DecodeStreamHandler = class.create(WrappedStreamHandler, function(decodeStreamHandler, super)
  function decodeStreamHandler:initialize(handler, ...)
    super.initialize(self, handler)
    self.inflater = Inflater:new(...)
  end
  function decodeStreamHandler:onData(data)
    return self.handler:onData(data and self.inflater:inflate(data))
  end
end)

local EncodeStreamHandler = class.create(WrappedStreamHandler, function(encodeStreamHandler, super)
  function encodeStreamHandler:initialize(handler, ...)
    super.initialize(self, handler)
    self.deflater = Deflater:new(...)
  end
  function encodeStreamHandler:onData(data)
    if data then
      return self.handler:onData(self.deflater:deflate(data))
    end
    self.handler:onData(self.deflater:finish(data))
    self.handler:onData()
  end
end)

return {
  decode = function(data, ...)
    return Inflater:new(...):inflate(data)
  end,
  encode = function(data, ...)
    return Deflater:new(...):deflate(data, 'finish')
  end,
  decodeStream = function(handler, ...)
    return DecodeStreamHandler:new(handler, ...)
  end,
  encodeStream = function(handler, ...)
    return EncodeStreamHandler:new(handler, ...)
  end,
}
