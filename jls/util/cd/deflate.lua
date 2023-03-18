local class = require('jls.lang.class')
local WrappedStreamHandler = require('jls.io.StreamHandler').WrappedStreamHandler
local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')

local DecodeStreamHandler = class.create(WrappedStreamHandler, function(decodeStreamHandler, super)
  function decodeStreamHandler:initialize(handler, inflater)
    super.initialize(self, handler)
    self.inflater = inflater
  end
  function decodeStreamHandler:onData(data)
    return self.handler:onData(data and self.inflater:inflate(data))
  end
end)

local EncodeStreamHandler = class.create(WrappedStreamHandler, function(encodeStreamHandler, super)
  function encodeStreamHandler:initialize(handler, deflater)
    super.initialize(self, handler)
    self.deflater = deflater
  end
  function encodeStreamHandler:onData(data)
    if data then
      return self.handler:onData(self.deflater:deflate(data))
    end
    self.handler:onData(self.deflater:finish(data))
    self.handler:onData()
  end
end)

return require('jls.lang.class').create('jls.util.Codec', function(deflate)

  function deflate:initialize(windowBits, compressionLevel)
    self.windowBits = windowBits
    self.compressionLevel = compressionLevel
  end

  function deflate:decode(value)
    return Inflater:new(self.windowBits):inflate(value)
  end

  function deflate:encode(value)
    return Deflater:new(self.compressionLevel, self.windowBits):deflate(value, 'finish')
  end

  function deflate:decodeStream(sh)
    return DecodeStreamHandler:new(sh, Inflater:new(self.windowBits))
  end

  function deflate:encodeStream(sh)
    return EncodeStreamHandler:new(sh, Deflater:new(self.compressionLevel, self.windowBits))
  end

  function deflate:getName()
    return 'deflate'
  end

end)
