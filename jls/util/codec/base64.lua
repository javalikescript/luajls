local class = require('jls.lang.class')
local BlockStreamHandler = require('jls.io.streams.BlockStreamHandler')

--- Provide base 64 codec.
-- @module jls.util.base64

local alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local bindices = {}
local indices = {}
local letters = {}
for i = 1, #alpha do
  local letter = string.sub(alpha, i, i)
  local b = string.byte(alpha, i)
  bindices[b] = i - 1
  indices[letter] = i - 1
  letters[i - 1] = letter
end

local function decode_concat(value)
  local l = #value
  local m = l % 4
  if m ~= 0 then
    if m == 1 then
      return nil, 'Invalid length'
    end
    value = value..'=='
  end
  local r = ''
  local c1, c2, c3, c4
  local i1, i2, i3, i4
  local b1, b2, b3
  for i = 1, l, 4 do
    c1, c2, c3, c4 = string.byte(value, i, i + 3)
    --print('letters', c1, c2, c3, c4)
    i1 = bindices[c1]
    if not i1 then return nil, 'Invalid character ('..tostring(c1)..')' end
    i2 = bindices[c2]
    if not i2 then return nil, 'Invalid character ('..tostring(c2)..')' end
    b1 = (i1 << 2) | (i2 >> 4)
    if c3 == 61 then -- 61 => '='
      r = r..string.char(b1)
    else
      i3 = bindices[c3]
      if not i3 then return nil, 'Invalid character ('..tostring(c3)..')' end
      b2 = ((i2 & 15) << 4) | (i3 >> 2)
      if c4 == 61 then -- 61 => '='
        r = r..string.char(b1, b2)
      else
        i4 = bindices[c4]
        if not i4 then return nil, 'Invalid character ('..tostring(c4)..')' end
        b3 = ((i3 & 3) << 6) | i4
        r = r..string.char(b1, b2, b3)
      end
    end
  end
  return r
end

local function encode_concat(value)
  local r = ''
  local b1, b2, b3
  local i1, i2, i3, i4
  for i = 1, #value, 3 do
    b1, b2, b3 = string.byte(value, i, i + 2)
    --print('letters', b1, b2, b3)
    i1 = b1 >> 2
    if b2 then
      i2 = ((b1 & 3) << 4) | (b2 >> 4)
      if b3 then
        i3 = ((b2 & 15) << 2) | (b3 >> 6)
        i4 = b3 & 63
        r = r..letters[i1]..letters[i2]..letters[i3]..letters[i4]
      else
        i3 = ((b2 & 15) << 2)
        r = r..letters[i1]..letters[i2]..letters[i3]..'='
      end
    else
      i2 = ((b1 & 3) << 4)
      r = r..letters[i1]..letters[i2]..'=='
    end
  end
  return r
end

local function decode_gsub(value)
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

local function encode_gsub(value)
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
        return letters[i1]..letters[i2]..letters[i3]..'='
      end
    else
      i2 = ((b1 & 3) << 4)
      return letters[i1]..letters[i2]..'=='
    end
  end))
end

--local decode, encode = decode_concat, encode_concat
local decode, encode = decode_gsub, encode_gsub

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
  decode = decode,
  encode = encode,
  decodeStream = function(sh)
    return DecodeStreamHandler:new(sh)
  end,
  encodeStream = function(sh, lc)
    return EncodeStreamHandler:new(sh, lc)
  end,
}
