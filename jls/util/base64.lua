--- Provide base 64 codec.
-- @module jls.util.base64

local M = {}

local alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local indices = {}
local letters = {}
for i = 1, #alpha do
  local letter = string.sub(alpha, i, i)
  local b = string.byte(alpha, i)
  indices[b] = i - 1
  letters[i - 1] = letter
end

--- Decodes the specified value.
-- @tparam string value the value to decode as a base 64 string.
-- @treturn string the decoded value as a string.
function M.decode(value)
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
    i1 = indices[c1]
    if not i1 then return nil, 'Invalid character ('..tostring(c1)..')' end
    i2 = indices[c2]
    if not i2 then return nil, 'Invalid character ('..tostring(c2)..')' end
    b1 = (i1 << 2) | (i2 >> 4)
    if c3 == 61 then -- 61 => '='
      r = r..string.char(b1)
    else
      i3 = indices[c3]
      if not i3 then return nil, 'Invalid character ('..tostring(c3)..')' end
      b2 = ((i2 & 15) << 4) | (i3 >> 2)
      if c4 == 61 then -- 61 => '='
        r = r..string.char(b1, b2)
      else
        i4 = indices[c4]
        if not i4 then return nil, 'Invalid character ('..tostring(c4)..')' end
        b3 = ((i3 & 3) << 6) | i4
        r = r..string.char(b1, b2, b3)
      end
    end
  end
  return r
end

--- Encodes the specified value.
-- @tparam string value the value to encode as a string.
-- @treturn string the encoded value as a base 64 string.
function M.encode(value)
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

return M