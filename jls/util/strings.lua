--- Provide string helper functions.
-- @module jls.util.strings
-- @pragma nostrip

local strings = {}


--- Returns a list of strings split at each pattern.
-- @tparam string value The string to split.
-- @tparam string pattern The pattern used to split the string.
-- @tparam boolean plain true to find the pattern as a plain string.
-- @treturn table a list of strings split at each pattern.
function strings.split(value, pattern, plain)
  local list = {}
  local p = 1
  while p <= #value do
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

-- deprecated, to remove
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

--- Returns an iterator function and the string value.
-- When used in a for loop it will iterate over all values.
-- If the pattern is a number it will be used to cut the string in values of the same size.
-- @tparam string value The string to split.
-- @param pattern The pattern used to split the string.
-- @tparam[opt] boolean plain true to find the pattern as a plain string.
-- @treturn function an iterator function
-- @treturn string value The string to split
function strings.parts(value, pattern, plain)
  if type(pattern) == 'string' then
    local p = 1
    return function(s)
      if p > #s then
        return nil
      end
      local i = p
      local pStart, pEnd = string.find(s, pattern, i, plain)
      if pStart then
        p = pEnd + 1
        return string.sub(s, i, pStart - 1), false, i
      end
      p = #s + 1
      return string.sub(s, i), true, i
    end, value
  elseif type(pattern) == 'number' and pattern > 0 then
    local index = 1
    return function(s)
      if index > #s then
        return nil
      end
      local i = index
      index = index + pattern
      return string.sub(s, i, index - 1), index > #s, i
    end, value
  end
  error('invalid argument')
end

--- Returns a list of strings cut with the same size.
-- @tparam number size The size to cut.
-- @tparam string value The string to split.
-- @treturn table a list of strings cut at each pattern.
function strings.cut(size, value) -- TODO value should come first
  local list = {}
  local index = 1
  while index < #value do
    table.insert(list, string.sub(value, index, index + size - 1))
    index = index + size
  end
  return list
end

--[[
function strings.compareToIgnoreCase(s1, s2) end
function strings.endsWith(s1, s2) end
function strings.startsWith(s1, s2) end
function strings.trim(s) end
function strings.format(s) end
]]

function strings.startsWith(value, prefix)
  return prefix == '' or string.sub(value, 1, #prefix) == prefix
end

function strings.endsWith(value, suffix)
  return suffix == '' or string.sub(value, -#suffix) == suffix
end

--- Returns true if the specified strings are equals case insensitive or both nil.
-- @tparam string a the first string.
-- @tparam string b the second string.
-- @treturn boolean true if the specified strings are equals.
function strings.equalsIgnoreCase(a, b)
  return (type(a) == 'string' and type(b) == 'string' and string.lower(a) == string.lower(b)) or (a == nil and b == nil)
end

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

--- Returns the string representing the specified integer
-- The most significant bit is set to 1 to indicate that another byte is used.
-- @tparam number i the integer to encode
-- @treturn string the encoded value as a string.
function strings.encodeVariableByteInteger(i)
  if i < 0 then
    return nil
  elseif i < 128 then
    return string.char(i)
  elseif i < 16384  then
    return string.char(0x80 | (i & 0x7f), (i >> 7) & 0x7f)
  elseif i < 2097152  then
    return string.char(0x80 | (i & 0x7f), 0x80 | ((i >> 7) & 0x7f), (i >> 14) & 0x7f)
  elseif i <= 268435455  then
    return string.char(0x80 | (i & 0x7f), 0x80 | ((i >> 7) & 0x7f), 0x80 | ((i >> 14) & 0x7f), (i >> 21) & 0x7f)
  end
  return nil
end

--- Returns the integer represented by the specified string
-- @tparam string s the encoded integer
-- @tparam[opt] number offset the starting offset, default is 1
-- @treturn number the decoded integer or nil.
-- @treturn number the end offset
function strings.decodeVariableByteInteger(s, offset)
  offset = offset or 1
  local i = 0
  for l = 0, 3 do
    local b = string.byte(s, offset + l)
    i = ((b & 0x7f) << (7 * l)) | i
    if (b & 0x80) ~= 0x80 then
      return i, offset + l + 1
    end
  end
  return nil, 'unexpected end of string'
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
-- @tparam[opt] string pad The character used to pad.
-- @treturn string a string representing the integer.
function strings.formatInteger(value, radix, len, chars, pad)
  if not chars then
    chars = FORMAT_CHARS
  end
  if not radix or radix < 2 or radix > #chars then
    radix = 10
  end
  if not pad then
    pad = string.sub(chars, 1, 1)
  end
  local m
  local i = math.abs(value)
  local s = ''
  while i > 0 do
    m = (i % radix) + 1
    i = math.floor(i / radix)
    s = string.sub(chars, m, m)..s
  end
  if len then
    if value < 0 then
      return '-'..strings.padLeft(s, len - 1, pad)
    end
    return strings.padLeft(s, len, pad)
  end
  if s == '' then
    s = pad
  end
  if value < 0 then
    return '-'..s
  end
  return s
end

--- Returns the pattern corresponding to the specified string with the magic characters ^$()%.[]*+-? escaped.
-- @tparam string value The string to escape.
-- @treturn string The corresponding pattern.
function strings.escape(value)
  if value == nil then
    return nil
  end
  return (string.gsub(value, '[%^%$%(%)%%%.%[%]%*%+%-%?]', function(c)
    return '%'..c
  end))
end

function strings.capitalize(value)
  if value == nil then
    return nil
  end
  return string.upper(string.sub(value, 1, 1))..string.sub(value, 2)
end

function strings.strip(value)
  if value == nil then
    return nil
  end
  return (string.gsub(string.gsub(value, '^%s+', ''), '%s+$', ''))
end

return strings
