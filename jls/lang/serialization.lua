--- Provides value serialization to string and deserialization from.
-- Serialization allows to share class instances between Lua states.
-- Some serialization implementation could bring restriction such as the same Lua state, process or OS.
-- @module jls.lang.serialization
-- @pragma nostrip

local class = require('jls.lang.class')

-- We use a magic byte to avoid serializing 99% of string values
local MARK = 26

local TYPE_MAP = {
  ['nil'] = '0',
  number = 'n',
  string = 's',
  boolean = 'b',
  table = 't',
}
local T_MAP = {}
for k, v in pairs(TYPE_MAP) do
  T_MAP[v] = k
end

--[[--
Returns the serialized string corressponding to the specified values.  
The class instances implementing a serialize method can be serialized.
The primitive types, boolean, number, string and nil can be serialized.
The tables containg serializable values can be serialized.
@param ... the value to serialize
@treturn string the serialized string
@function serialize
]]
local function serialize(...)
  local n = select('#', ...)
  if n == 0 then
    return ''
  elseif n == 1 then
    local value = ...
    if type(value) == 'string' and string.byte(value) ~= MARK then
      return value
    end
  end
  local values = table.pack(...)
  local list = {string.char(MARK)}
  for i = 1, values.n do
    local value = values[i]
    local name = type(value)
    local rawValue
    if name == 'table' then
      local Class = class.getClass(value)
      if Class then
        name = assert(Class:getName(), 'no class name')
        if type(value.serialize) ~= 'function' then
          error('class "'..name..'" not serializable')
        end
        rawValue = value:serialize()
      else
        assert(not getmetatable(value), 'table has metadata')
        -- TODO optimize list
        -- TODO detect cycle
        local entries = {}
        for k, v in pairs(value) do
          table.insert(entries, string.pack('<s3s3', serialize(k), serialize(v)))
        end
        rawValue = table.concat(entries)
      end
    elseif name == 'nil' then
      rawValue = ''
    elseif name == 'number' or name == 'boolean' then
      -- Lua uses 64-bit integers so 8 bytes, using string value is interesting up to 7 digits
      rawValue = tostring(value)
    elseif name == 'string' then
      rawValue = value
    else
      error('invalid value type "'..name..'"')
    end
    -- TODO use variable length unsigned integer
    table.insert(list, string.pack('<s1s3', TYPE_MAP[name] or name, rawValue))
  end
  return table.concat(list)
end

local function serializeError(message)
  return string.pack('<Bs1s3', MARK, 'error', serialize(message))
end

local function typeMatch(types, current)
  if not types or types == '?' then
    return true
  end
  for t in string.gmatch(types, '[^|]*') do
    if current == t then
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

local function getType(pos, s)
  if type(pos) ~= 'number' then
    s = pos
    pos = 1
  end
  if string.byte(s, pos) ~= MARK then
    return 'string'
  end
  return (string.unpack('<s1', s, pos))
end

--[[--
Returns the values corressponding to the specified serialized string.
@tparam[opt] number pos the optional position in the string value, default to 1
@tparam string s the value to deserialize
@tparam string .. the expected types or class names, defaults to any type, `?`, and any count
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
  local len = #s
  local typesn = types.n
  if string.byte(s, pos) ~= MARK then
    if typesn > 0 then
      if typesn ~= 1 then
        error('invalid values count 1, expected '..typesn)
      elseif not typeMatch(types[1], 'string') then
        error('invalid single string, expected '..tostring(types[1]))
      end
    end
    return s
  end
  pos = pos + 1
  local name, rawValue
  local list = {}
  local n = 0
  while pos < len do
    name, rawValue, pos = string.unpack('<s1s3', s, pos)
    name = T_MAP[name] or name
    n = n + 1
    local checkType
    if typesn > 0 then
      if n > typesn then
        break
      end
      checkType = types[n]
    end
    local value
    if name == 'nil' then
      assert(rawValue == '', 'invalid value')
      value = nil
    elseif name == 'string' then
      value = rawValue
    elseif name == 'number' then
      value = tonumber(rawValue)
    elseif name == 'boolean' then
      if rawValue == 'true' then
        value = true
      elseif rawValue == 'false' then
        value = false
      else
        error('invalid value')
      end
    elseif name == 'error' then
      local message = deserialize(pos, rawValue, '?')
      error(message)
    elseif name == 'table' then
      value = {}
      local p, l = 1, #rawValue
      local rk, rv
      while p < l do
        rk, rv, p = string.unpack('<s3s3', rawValue, p)
        local k, v = deserialize(rk, 'number|string|boolean'), deserialize(rv, '?')
        value[k] = v
      end
    else
      local Class = assert(class.byName(name), 'class not found')
      value = class.makeInstance(Class)
      if type(value.deserialize) ~= 'function' then
        error('class "'..name..'" not deserializable')
      end
      value:deserialize(rawValue)
      if classMatch(checkType, Class) then
        checkType = nil
      else
        error('invalid type '..name..', expected '..tostring(checkType))
      end
    end
    if typeMatch(checkType, name) then
      list[n] = value
    else
      error('invalid type '..name..', expected '..tostring(checkType))
    end
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
  getType = getType,
  typeMatch = typeMatch,
  classMatch = classMatch,
  MARK = MARK,
}