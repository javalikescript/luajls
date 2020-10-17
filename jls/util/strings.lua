--- Provide string helper functions.
-- @module jls.util.strings

local strings = {}


--- Returns a list of strings split at each pattern.
-- @tparam string value The string to split.
-- @tparam string pattern The pattern used to split the string.
-- @tparam boolean plain true to find the pattern as a plain string.
-- @treturn table a list of strings split at each pattern.
function strings.split(value, pattern, plain)
  local list = {}
  local s = #value
  local p = 1
  while p <= s do
    local pStart, pEnd = string.find(value, pattern, p, plain)
    if pStart then
      table.insert(list, string.sub(value, p, pStart - 1))
      p = pEnd + 1
    else
      table.insert(list, string.sub(value, p))
      break
    end
  end
  return list
end

--- Returns a list of strings cut at each length.
-- @tparam string value The string to split.
-- @treturn table a list of strings cut at each pattern.
function strings.cuts(value, ...)
  local lengthList = {...}
  local list = {}
  local index = 1
  for _, length in ipairs(lengthList) do
    table.insert(list, string.sub(value, index, index + length - 1))
    index = index + length
  end
  return list
end

--[[
function strings.compareToIgnoreCase(s1, s2) end
function strings.equalsIgnoreCase(s1, s2) end
function strings.endsWith(s1, s2) end
function strings.startsWith(s1, s2) end
function strings.trim(s) end
function strings.format(s) end
]]

--- Returns an integer for the specified string.
-- If two strings are equals then each string produce the same integer.
-- The result integer uses all the integer possible values from math.mininteger to math.maxinteger.
-- The result integer for a specific string may change in futur versions.
-- @tparam string value The string to hash.
-- @treturn integer a hash integer value.
function strings.hash(value)
  local h = 0
  for i = 1, #value do
    local b = string.byte(value, i)
    h = 31 * h + b
  end
  return h
end

function strings.padLeft(s, l, c)
  local sl = #s
  if sl < l then
    return string.rep(c or ' ', l - sl)..s
  elseif sl > l then
    return string.sub(s, -l)
  end
  return s
end

-- The character order is respected to allow comparison
-- The starting characters respect the hexadecimal notation
-- The characters length is a power of two, convenient for binary data
-- The characters are usable as file name or URL path
-- URI Unreserved Characters = ALPHA / DIGIT / "-" / "." / "_" / "~"
-- see https://tools.ietf.org/html/rfc3986#page-13
local FORMAT_CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~'

--- Returns a string representing the specified integer in the specified radix.
-- @tparam integer value The integer to format.
-- @tparam[opt] integer radix The radix to use from 2 to 64, default is 10.
-- @tparam[opt] integer len The minimal length of the resulting string padded with zero.
-- @tparam[opt] string chars A string containing the characters used to format.
-- @treturn string a string representing the integer.
function strings.formatInteger(value, radix, len, chars)
  if not chars then
    chars = FORMAT_CHARS
  end
  if not radix or radix < 2 or radix > #chars then
    radix = 10
  end
  local m
  local i = math.abs(value)
  local s = ''
  while i > 0 do
    m = (i % radix) + 1
    i = i // radix
    s = string.sub(chars, m, m)..s
  end
  if len then
    if value < 0 then
      return '-'..strings.padLeft(s, len - 1, '0')
    end
    return strings.padLeft(s, len, '0')
  end
  if value < 0 then
    return '-'..s
  end
  return s
end

return strings
