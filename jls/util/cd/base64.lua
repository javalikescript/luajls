local class = require('jls.lang.class')
local BlockStreamHandler = require('jls.io.streams.BlockStreamHandler')

-- Provide base 64 codec.
-- @module jls.util.cd.base64
-- @pragma nostrip

-- see openssl.base64(msg, true, true)

local function assertLen(alpha)
  if type(alpha) ~= 'string' then
    error('Invalid base64 alphabet type, '..type(alpha))
  end
  local i = #alpha
  if i ~= 64 then
    error('Invalid base64 alphabet length, '..tostring(i))
  end
  return i
end

local function getIndices(alpha)
  local indices = {}
  for i = 1, assertLen(alpha) do
    local letter = string.sub(alpha, i, i)
    indices[letter] = i - 1
  end
  return indices
end

local function getLetters(alpha)
  local letters = {}
  for i = 1, assertLen(alpha) do
    local letter = string.sub(alpha, i, i)
    letters[i - 1] = letter
  end
  return letters
end

local function decode(value, indices)
  if #value % 4 == 1 then
    error('Invalid length')
  end
  return (string.gsub(value, '(.)%s*(.)%s*(.?)%s*(.?)%s*', function(c1, c2, c3, c4)
    local i1 = indices[c1]
    if not i1 then error('Invalid character ('..c1..')') end
    local i2 = indices[c2]
    if not i2 then error('Invalid character ('..c2..')') end
    local b1 = (i1 << 2) | (i2 >> 4)
    if c3 == '' or c3 == '=' then
      return string.char(b1)
    else
      local i3 = indices[c3]
      if not i3 then error('Invalid character ('..c3..')') end
      local b2 = ((i2 & 15) << 4) | (i3 >> 2)
      if c4 == '' or c4 == '=' then
        return string.char(b1, b2)
      else
        local i4 = indices[c4]
        if not i4 then error('Invalid character ('..c4..')') end
        local b3 = ((i3 & 3) << 6) | i4
        return string.char(b1, b2, b3)
      end
    end
  end))
end

local function encode(value, letters, pad)
  return (string.gsub(value, '..?.?', function(ccc)
    local b1, b2, b3 = string.byte(ccc, 1, 3)
    local i1 = b1 >> 2
    local i2, i3, i4
    if b2 then
      i2 = ((b1 & 3) << 4) | (b2 >> 4)
      if b3 then
        i3 = ((b2 & 15) << 2) | (b3 >> 6)
        i4 = b3 & 63
        return letters[i1]..letters[i2]..letters[i3]..letters[i4]
      else
        i3 = ((b2 & 15) << 2)
        if pad then
          return letters[i1]..letters[i2]..letters[i3]..'='
        end
        return letters[i1]..letters[i2]..letters[i3]
      end
    else
      i2 = ((b1 & 3) << 4)
      if pad then
        return letters[i1]..letters[i2]..'=='
      end
      return letters[i1]..letters[i2]
    end
  end))
end

local DEFAULT_ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local DEFAULT_INDICES = getIndices(DEFAULT_ALPHA)
local DEFAULT_LETTERS = getLetters(DEFAULT_ALPHA)

local DecodeStreamHandler = class.create(BlockStreamHandler, function(decodeStreamHandler, super)
  function decodeStreamHandler:initialize(handler)
    super.initialize(self, handler, 4, true)
  end
  function decodeStreamHandler:onData(data)
    return self.handler:onData(data and decode(data))
  end
end)

local EncodeStreamHandler = class.create(BlockStreamHandler, function(encodeStreamHandler, super)
  function encodeStreamHandler:initialize(handler)
    super.initialize(self, handler, 3, true)
  end
  function encodeStreamHandler:onData(data)
    return self.handler:onData(data and encode(data))
  end
end)

return {
  decode = function(value, alpha)
    return decode(value, alpha and getIndices(alpha) or DEFAULT_INDICES)
  end,
  encode = function(value, alpha, pad)
    return encode(value, alpha and getLetters(alpha) or DEFAULT_LETTERS, pad ~= false)
  end,
  decodeStream = function(sh)
    return DecodeStreamHandler:new(sh)
  end,
  encodeStream = function(sh, lc)
    return EncodeStreamHandler:new(sh, lc)
  end,
}
