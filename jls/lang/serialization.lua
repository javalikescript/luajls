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
  local function write(value, asType)
    local t = asType or type(value)
    if t == 'nil' then
      list[index] = 'N'
      index = index + 1
    elseif t == 'boolean' then
      list[index] = value and 'T' or 'F'
      index = index + 1
    elseif t == 'number' and math.type(value) == 'integer' then
      if value >= 0 then
        list[index] = 'I'
        index = index + 1
        list[index] = packv(value)
      else
        list[index] = 'i'
        index = index + 1
        list[index] = packv(-value)
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
      elseif t == 'number' then
        -- TODO using string pack 'n' is problematic as unsupported in Lua 5.1
        st = 'n'
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
          local s = 0
          for _ in pairs(value) do
            s = s + 1
          end
          if s == #value then
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
local function serializeError(message)
  return serialize({
    serialize = function(_, write)
      write(message, 'error')
    end
  })
end

local TYPE_MAP = {
  N = 'nil',
  T = 'boolean',
  F = 'boolean',
  n = 'number',
  I = 'number',
  i = 'number',
  s = 'string',
  t = 'table',
  l = 'table',
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

--[[--
Returns the values read from the specified serialized string.
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
      elseif st == 'n' then
        v = tonumber(string.sub(s, pos, lend))
      elseif st == 'e' then
        error(read())
      elseif st == 't' then
        v = {}
        while pos < next do
          local k = read()
          v[k] = read()
        end
      elseif st == 'l' then
        v = {}
        local i = 0
        while pos < next do
          i = i + 1
          v[i] = read()
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
  serialize = serialize,
  serializeError = serializeError,
  deserialize = deserialize,
  typeMatch = typeMatch,
  classMatch = classMatch,
  packv = packv,
  unpackv = unpackv,
  MARK = MARK,
}
