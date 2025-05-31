--- Provides value serialization to string and deserialization from.
-- Serialization allows to share objects, class instances, between Lua states.
-- Some serialization implementation could bring restriction such as the same Lua state, process or OS.
-- @module jls.lang.serialization
-- @pragma nostrip

local class = require('jls.lang.class')

-- We use a magic byte to avoid serializing almost all single string values
local MARK = '\026'

-- Encodes a variable length unsigned integer.
local function packv(i)
  assert(i >= 0, 'unsigned integer out of bound')
  if i <= 127 then
    return string.char(i)
  end
  local l = {}
  repeat
    local b = 128 | (i & 127)
    table.insert(l, b)
    i = i >> 7
  until i <= 127
  table.insert(l, i)
  return string.char(table.unpack(l))
end

-- Decodes a variable length unsigned integer.
local function unpackv(s, pos)
  local p = pos or 1
  local d = 0
  local i = 0
  repeat
    assert(d < 63, 'unsigned integer out of bound')
    local b = string.byte(s, p)
    assert(b, 'end of string')
    p = p + 1
    i = i | ((b & 127) << d)
    d = d + 7
  until b & 128 == 0
  return i, p
end

-- Returns the significant and power of 2 for a positive number.
local function n2sp(n)
  local s = string.format('%a', n) -- [-]0xh.hhhhp±d
  local op = string.find(s, 'p', 1, true)
  local p
  if op then
    p = math.tointeger(string.sub(s, op + 1))
  else
    p = 0
    op = #s + 1
  end
  local od = string.find(s, '.', 4, true)
  if od then
    p = p - (op - 1 - od) * 4
    s = string.sub(s, 3, od - 1)..string.sub(s, od + 1, op - 1)
  else
    s = string.sub(s, 3, op - 1)
  end
  return tonumber(s, 16), p
end

-- Encodes a positive number.
local function packn(n)
  local i, e = n2sp(n)
  if e < 0 then
    e = (-e) << 1 | 1
  else
    e = e << 1
  end
  return packv(i)..packv(e)
end

-- Decodes a positive number.
local function unpackn(s, pos)
  local p, i, e
  i, p = unpackv(s, pos)
  e, p = unpackv(s, p)
  local neg = e & 1 == 1
  e = e >> 1
  if neg then
    e = -e
  end
  return i * 2 ^ e, p
end

if string['pack'..''] then
  packn = function(n)
    return string.pack('n', n)
  end
  unpackn = function(s, pos)
    return string.unpack('n', s, pos)
  end
end

-- Returns true when the value is serializable.
-- This is not a deep check, table or object could contain not serializable values.
local function isSerializable(value)
  local t = type(value)
  if t == 'string' or t == 'number' or t == 'boolean' or t == 'nil' then
    return true
  end
  if t == 'table' then
    local Class = class.getClass(value)
    if Class then
      if Class:getName() and type(value.serialize) == 'function' then
        return true
      end
    elseif type(value.serialize) == 'function' or not getmetatable(value) then
      return true
    end
  end
  return false
end

--[[--
Returns the serialized string corresponding to the specified values.  
The primitive types, boolean, number, string and nil can be serialized.
The objects implementing a serialize method can be serialized.
The tables containg serializable values can be serialized.
@param ... the value to serialize
@treturn string the serialized string
@function serialize
]]
local function serialize(...)
  local values = table.pack(...)
  local n = values.n
  if n == 0 then
    return ''
  elseif n == 1 then
    local value = values[1]
    if type(value) == 'string' and string.sub(value, 1, 1) ~= MARK then
      return value
    end
  end
  local list = {MARK}
  local index = 2
  local function write(value, protected, asType)
    local t = type(value)
    if protected then
      local i = index
      local status, reason = pcall(write, value, false, asType)
      if status then
        return true
      end
      index = i
      for ii in pairs(list) do
        if ii >= i then
          list[ii] = nil
        end
      end
      return false, reason
    end
    if asType then
      if asType == 'error' or asType == 'string' or asType == t then
        t = asType
      else
        error('invalid value type "'..tostring(asType)..'"')
      end
    end
    if t == 'nil' then
      list[index] = 'N'
      index = index + 1
    elseif t == 'boolean' then
      list[index] = value and 'T' or 'F'
      index = index + 1
    elseif t == 'number' then
      local neg = value < 0
      local v = neg and -value or value
      if math.type(v) == 'integer' then
        list[index] = neg and 'i' or 'I'
        index = index + 1
        list[index] = packv(v)
      elseif v ~= v then -- NaN
        list[index] = 'n'
      elseif v == math.huge then -- inf
        list[index] = neg and 'h' or 'H'
      else
        list[index] = neg and 'd' or 'D'
        index = index + 1
        list[index] = packn(v)
      end
      index = index + 1
    else
      local st
      local typeIndex = index
      index = index + 2 -- reserve 2 slots for short type and size
      if t == 'string' then
        st = 's'
        list[index] = tostring(value)
        index = index + 1
      elseif t == 'error' then
        st = 'e'
        write(value)
      elseif t == 'table' then
        -- TODO detect cycle
        local Class = class.getClass(value)
        if Class then
          local classname = assert(Class:getName(), 'no class name')
          if type(value.serialize) ~= 'function' then
            error('class "'..classname..'" not serializable')
          end
          st = 'o'
          list[index] = packv(#classname)
          index = index + 1
          list[index] = classname
          index = index + 1
          value:serialize(write)
        elseif type(value.serialize) == 'function' then
          index = typeIndex -- discard reserved slots
          value:serialize(write)
          return
        else
          assert(not getmetatable(value), 'table has metadata')
          local s
          if value[1] ~= nil then
            s = 0
            for _ in pairs(value) do
              s = s + 1
            end
          end
          if s and s == #value then
            st = 'l'
            for _, v in ipairs(value) do
              write(v)
            end
          else
            st = 't'
            for k, v in pairs(value) do
              write(k)
              write(v)
            end
          end
        end
      else
        error('invalid value type "'..t..'"')
      end
      local size = 0
      for i = typeIndex + 2, index - 1 do
        local v = list[i]
        size = size + #v
      end
      list[typeIndex] = st
      list[typeIndex + 1] = packv(size)
    end
  end
  for i = 1, n do
    write(values[i])
  end
  return table.concat(list)
end

--[[--
Returns the serialized string corresponding to an error.  
The deserialization will raise the specified error message.
@param message the error message to serialize
@treturn string the serialized string
@function serializeError
]]
local function serializeError(message, protected)
  return serialize({
    serialize = function(_, write)
      write(message, protected, 'error')
    end
  })
end

local TYPE_MAP = {
  N = 'nil',
  T = 'boolean', -- true
  F = 'boolean', -- false
  I = 'number', -- +integer
  i = 'number', -- -integer
  D = 'number', -- +float
  d = 'number', -- -float
  H = 'number', -- +inf
  h = 'number', -- -inf
  n = 'number', -- nan
  s = 'string',
  t = 'table', -- map
  l = 'table', -- list
  e = 'error',
  o = 'object',
}

local function typeMatch(types, value)
  if types == '?' then
    return true
  end
  for t in string.gmatch(types, '[^|]*') do
    if t == value then
      return true
    end
  end
  return false
end

local function classMatch(types, Class)
  if not types or types == '?' then
    return true
  end
  for t in string.gmatch(types, '[^|]*') do
    if t ~= 'nil' and t ~= 'string' and t ~= 'number' and t ~= 'boolean' and t ~= 'error' then
      local SuperClass = class.byName(t)
      if SuperClass and SuperClass:isAssignableFrom(Class) then
        return true
      end
    end
  end
  return false
end

-- Trims a string, returns nil for empty string.
local function trim(value)
  if value == nil then
    return nil
  end
  local s = string.gsub(string.gsub(value, '^%s+', ''), '%s+$', '')
  if #s == 0 then
    return nil
  end
  return s
end

--[[--
Returns the values read from the specified serialized string.
The expected types could be enclosed with brackets `{}` to indicate the expected types in a table,
optionally the table key types could be passed followed by the equal sign `=`.
The object constructor is not called, the `deserialize` method is in charge to initialize the object including its inheritance.
@tparam[opt] number pos the optional position in the string value, default to 1
@tparam string s the string value to deserialize
@tparam string ... the expected types or class names, defaults to any type, `?` and any count
@return the deserialized values
@function deserialize
]]
local function deserialize(pos, ...)
  local s, types
  if type(pos) == 'number' then
    s = (...)
    types = table.pack(select(2, ...))
  else
    s = pos
    pos = 1
    types = table.pack(...)
  end
  local typesn = types.n
  if string.sub(s, pos, pos) ~= MARK then
    if typesn > 0 then
      if typesn ~= 1 then
        error('invalid values count 1, expected '..typesn)
      elseif not typeMatch(types[1], 'string') then
        error('invalid type string, expected '..tostring(types[1]))
      end
    end
    return s
  end
  local len = #s
  pos = pos + 1
  local function read(exectedTypes)
    local valueType, keyType
    if exectedTypes then
      valueType = string.match(exectedTypes, '^{(.*)}$')
      if valueType then
        exectedTypes = 'table'
        local k, v = string.match(valueType, '^([^=]*)=(.*)$')
        if k then
          keyType, valueType = trim(k), trim(v)
        else
          valueType = trim(valueType)
        end
      end
    end
    if pos > len then
      error('end of string')
    end
    local st = string.sub(s, pos, pos)
    pos = pos + 1
    local v
    if st == 'N' then
      v = nil
    elseif st == 'T' then
      v = true
    elseif st == 'F' then
      v = false
    elseif st == 'I' then
      v, pos = unpackv(s, pos)
    elseif st == 'i' then
      v, pos = unpackv(s, pos)
      v = -v
    elseif st == 'D' then
      v, pos = unpackn(s, pos)
    elseif st == 'd' then
      v, pos = unpackn(s, pos)
      v = -v
    elseif st == 'n' then
      v = 0/0 -- nan
    elseif st == 'H' then
      v = math.huge -- +inf
    elseif st == 'h' then
      v = -math.huge -- -inf
    else
      local size
      size, pos = unpackv(s, pos)
      local next = pos + size
      local lend = next - 1
      if lend > len then
        error('end of string')
      end
      if st == 's' then
        v = string.sub(s, pos, lend)
      elseif st == 'e' then
        error(read())
      elseif st == 't' then
        v = {}
        while pos < next do
          local k = read(keyType)
          v[k] = read(valueType)
        end
      elseif st == 'l' then
        if keyType and not typeMatch(keyType, 'integer') then
          error('invalid type '..keyType..' for table key, expected integer')
        end
        v = {}
        local i = 0
        while pos < next do
          i = i + 1
          v[i] = read(valueType)
        end
      elseif st == 'o' then
        local osize
        osize, pos = unpackv(s, pos)
        local classname = string.sub(s, pos, pos + osize - 1)
        pos = pos + osize
        if pos > len then
          error('end of string')
        end
        local Class = assert(class.byName(classname), 'class not found')
        v = class.makeInstance(Class)
        if type(v.deserialize) ~= 'function' then
          error('class "'..classname..'" not deserializable')
        end
        v:deserialize(read)
        if classMatch(exectedTypes, Class) then
          exectedTypes = nil
        else
          error('invalid type '..classname..', expected '..tostring(exectedTypes))
        end
      else
        error('invalid short type '..st)
      end
      pos = next
    end
    if exectedTypes then
      local t = TYPE_MAP[st]
      if not typeMatch(exectedTypes, t) then
        error('invalid type '..tostring(t)..', expected '..tostring(exectedTypes))
      end
    end
    return v
  end
  local list = {}
  local n = 0
  while pos <= len do
    n = n + 1
    local exectedType
    if typesn > 0 then
      if n > typesn then
        break
      end
      exectedType = types[n]
    end
    list[n] = read(exectedType)
  end
  if typesn > 0 and n ~= typesn then
    error('invalid values count '..n..', expected '..typesn)
  end
  return table.unpack(list, 1, n)
end

return {
  isSerializable = isSerializable,
  serialize = serialize,
  serializeError = serializeError,
  deserialize = deserialize,
  typeMatch = typeMatch,
  classMatch = classMatch,
  packv = packv,
  unpackv = unpackv,
  packn = packn,
  unpackn = unpackn,
  n2sp = n2sp,
  MARK = MARK,
}
