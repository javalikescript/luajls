-- TODO Remove this class as it can be replaced by string.pack, string.packsize, and string.unpack

local integers = {}

local UINT8_MAX = 255
local UINT8_MIN = 0
local INT8_MAX = 127
local INT8_MIN = -128
local UINT16_MAX = 65535
local UINT16_MIN = 0
local INT16_MAX = 32767
local INT16_MIN = -32768
local UINT32_MAX = 4294967295
local UINT32_MIN = 0
local INT32_MAX = 2147483647
local INT32_MIN = -2147483648

-- two's complement signing
function integers.sign(i, bitCount)
  if ((i >> (bitCount - 1)) & 1) == 1 then
    -- example: -2 = 1111 1110 = 254, 254 - 256 = -2
    return i - (1 << bitCount)
  end
  return i
end

function integers.unsign(i, bitCount)
  if i < 0 then
    -- example: -2 = 1111 1110 = 254, 256 - 2 = 254
    return (1 << bitCount) + i
  end
  return i
end

function integers.fromUInt8(i)
  if (i < UINT8_MIN) or (i > UINT8_MAX) then
    return nil
  end
  return string.char(i)
end

function integers.fromInt8(i)
  if (i < INT8_MIN) or (i > INT8_MAX) then
    return nil
  end
  return string.char(integers.unsign(i, 8))
end

function integers.toUInt8(s, o)
  return string.byte(s, o)
end

function integers.toInt8(s, o)
  return integers.sign(integers.toUInt8(s, o), 8)
end

local bigEndian = {
  fromUInt8 = integers.fromUInt8,
  fromInt8 = integers.fromInt8,
  toUInt8 = integers.toUInt8,
  toInt8 = integers.toInt8
}

function bigEndian.fromUInt16(i)
  if (i < UINT16_MIN) or (i > UINT16_MAX) then
    return nil
  end
  return string.char((i >> 8) & 0xff, i & 0xff)
end

function bigEndian.fromInt16(i)
  if (i < INT16_MIN) or (i > INT16_MAX) then
    return nil
  end
  return bigEndian.fromUInt16(integers.unsign(i, 16))
end

function bigEndian.toUInt16(s, o)
  o = o or 1
  local b1, b2 = string.byte(s, o, o + 1)
  return (b1 << 8) | b2
end

function bigEndian.toInt16(s, o)
  return integers.sign(bigEndian.toUInt16(s, o), 16)
end

function bigEndian.fromUInt32(i)
  if (i < UINT32_MIN) or (i > UINT32_MAX) then
    return nil
  end
  return string.char((i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff)
end

function bigEndian.fromInt32(i)
  if (i < INT32_MIN) or (i > INT32_MAX) then
    return nil
  end
  return bigEndian.fromUInt32(integers.unsign(i, 32))
end

function bigEndian.toUInt32(s, o)
  o = o or 1
  local b1, b2, b3, b4 = string.byte(s, o, o + 3)
  return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
end

function bigEndian.toInt32(s, o)
  return integers.sign(bigEndian.toUInt32(s, o), 32)
end

integers.be = bigEndian

local littleEndian = {
  fromUInt8 = integers.fromUInt8,
  fromInt8 = integers.fromInt8,
  toUInt8 = integers.toUInt8,
  toInt8 = integers.toInt8
}

function littleEndian.fromUInt16(i)
  if (i < UINT16_MIN) or (i > UINT16_MAX) then
    return nil
  end
  return string.char(i & 0xff, (i >> 8) & 0xff)
end

function littleEndian.fromInt16(i)
  if (i < INT16_MIN) or (i > INT16_MAX) then
    return nil
  end
  return littleEndian.fromUInt16(integers.unsign(i, 16))
end

function littleEndian.toUInt16(s, o)
  o = o or 1
  local b1, b2 = string.byte(s, o, o + 1)
  return (b2 << 8) | b1
end

function littleEndian.toInt16(s)
  return integers.sign(littleEndian.toUInt16(s, o), 16)
end

function littleEndian.fromUInt32(i)
  if (i < UINT32_MIN) or (i > UINT32_MAX) then
    return nil
  end
  return string.char(i & 0xff, (i >> 8) & 0xff, (i >> 16) & 0xff, (i >> 24) & 0xff)
end

function littleEndian.fromInt32(i)
  if (i < INT32_MIN) or (i > INT32_MAX) then
    return nil
  end
  return littleEndian.fromUInt32(integers.unsign(i, 32))
end

function littleEndian.toUInt32(s, o)
  o = o or 1
  local b1, b2, b3, b4 = string.byte(s, o, o + 3)
  return (b4 << 24) | (b3 << 16) | (b2 << 8) | b1
end

function littleEndian.toInt32(s, o)
  return integers.sign(littleEndian.toUInt32(s, o), 32)
end

integers.le = littleEndian

return integers