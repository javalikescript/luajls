--- Provide hexadecimal codec.
-- @module jls.util.hex

local hex = {}

-- character to nibble
local function c2n(c)
  if c >= 48 and c <= 57 then
    return c - 48
  elseif c >= 65 and c <= 70 then
    return c - 55
  elseif c >= 97 and c <= 102 then
    return c - 87
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

-- nibble to string
local function n2s(n, lc)
  return string.char(n2c(n, lc))
end

--- Decodes the specified value.
-- @tparam string value the value to decode as an hexadecimal string.
-- @treturn string the decoded value as a string.
function hex.decode(value)
  local r = ''
  for i = 1, #value, 2 do
    local c1, c2 = string.byte(value, i, i + 1)
    local hn, ln = c2n(c1), c2n(c2)
    r = r..string.char((hn << 4) + ln)
  end
  return r
end

--- Encodes the specified value.
-- @tparam string value the value to encode as a string.
-- @tparam[opt=false] boolean lc true to encode using lowercases.
-- @treturn string the encoded value as an hexadecimal string.
function hex.encode(value, lc)
  local r = ''
  for i = 1, #value do
    local b = string.byte(value, i)
    r = r..string.char(n2c((b >> 4) & 0x0f, lc), n2c(b & 0x0f, lc))
  end
  return r
end

return hex