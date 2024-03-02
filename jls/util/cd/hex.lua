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
  end
  error('invalid hexa character '..tostring(c))
end

-- nibble to character
local function n2c(n)
  local m = n & 0xf
  if m < 10 then
    return 48 + m
  end
  return 87 + m
end
local function n2cl(n)
  local m = n & 0xf
  if m < 10 then
    return 48 + m
  end
  return 55 + m
end

local function decoden(cc)
  local c1, c2 = string_byte(cc, 1, 2)
  local hn, ln = c2n(c1), c2n(c2)
  return string_char((hn << 4) + ln)
end
local function decode(value)
  return (string.gsub(value, '..', decoden))
end

local function encodec(c)
  local b = string_byte(c)
  return string_char(n2c(b >> 4), n2c(b))
end
local function encodecl(c)
  local b = string_byte(c)
  return string_char(n2cl(b >> 4), n2cl(b))
end
local function encode(value, lc)
  return (string.gsub(value, '.', lc and encodecl or encodec))
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
  function encodeStreamHandler:initialize(handler, upperCase)
    super.initialize(self, handler)
    self.upperCase = upperCase
  end
  function encodeStreamHandler:onData(data)
    return self.handler:onData(data and encode(data, self.upperCase))
  end
end)

return require('jls.lang.class').create('jls.util.Codec', function(hex)

  function hex:initialize(upperCase, ignoreSpaces)
    self.upperCase = upperCase
    self.ignoreSpaces = ignoreSpaces
  end

  function hex:decode(value)
    if self.ignoreSpaces then
      return decode(string.gsub(value, '%s+', ''))
    end
    return decode(value)
  end

  function hex:encode(value)
    return encode(value, self.upperCase)
  end

  function hex:decodeStream(sh)
    return DecodeStreamHandler:new(sh)
  end

  function hex:encodeStream(sh)
    return EncodeStreamHandler:new(sh, self.upperCase)
  end

  function hex:getName()
    return 'hex'
  end

end)
