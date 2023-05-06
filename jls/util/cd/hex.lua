local class = require('jls.lang.class')

-- see openssl.hex(msg, true)

local string_char = string.char
local string_byte = string.byte

-- character to nibble
local function c2n(c)
  if c >= 48 and c <= 57 then
    return c - 48
  elseif c >= 65 and c <= 70 then
    return c - 55
  elseif c >= 97 and c <= 102 then
    return c - 87
  else
    error('invalid hexa character '..tostring(c))
  end
end

-- nibble to character
local function n2c(n, lc)
  if n >= 0 and n < 10 then
    return 48 + n
  elseif n >= 10 and n < 16 then
    if lc then
      return 55 + n
    end
    return 87 + n
  end
end

local function decode(value)
  return (string.gsub(value, '..', function(cc)
    local c1, c2 = string_byte(cc, 1, 2)
    local hn, ln = c2n(c1), c2n(c2)
    return string_char((hn << 4) + ln)
  end))
end

local function encode(value, lc)
  return (string.gsub(value, '.', function(c)
    local b = string_byte(c)
    return string_char(n2c((b >> 4) & 0x0f, lc), n2c(b & 0x0f, lc))
  end))
end

local DecodeStreamHandler = class.create('jls.io.streams.BlockStreamHandler', function(decodeStreamHandler, super)
  function decodeStreamHandler:initialize(handler)
    super.initialize(self, handler, 2, true)
  end
  function decodeStreamHandler:onData(data)
    return self.handler:onData(data and decode(data))
  end
end)

local EncodeStreamHandler = class.create(require('jls.io.StreamHandler').WrappedStreamHandler, function(encodeStreamHandler, super)
  function encodeStreamHandler:initialize(handler, lowerCase)
    super.initialize(self, handler)
    self.lowerCase = lowerCase
  end
  function encodeStreamHandler:onData(data)
    return self.handler:onData(data and encode(data, self.lowerCase))
  end
end)

return require('jls.lang.class').create('jls.util.Codec', function(hex)

  function hex:initialize(lowerCase)
    self.lowerCase = lowerCase
  end

  function hex:decode(value)
    return decode(value)
  end

  function hex:encode(value)
    return encode(value, self.lowerCase)
  end

  function hex:decodeStream(sh)
    return DecodeStreamHandler:new(sh)
  end

  function hex:encodeStream(sh)
    return EncodeStreamHandler:new(sh, self.lowerCase)
  end

  function hex:getName()
    return 'hex'
  end

end)
