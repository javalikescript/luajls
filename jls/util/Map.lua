--- Represents a map.
-- @module jls.util.Map
-- @pragma nostrip

-- TODO garantee key insertion order
-- and use metamethod __pairs

local function compareKey(a, b)
  if a == b then
    return false
  elseif a == nil then
    return true
  elseif b == nil then
    return false
  end
  local ta, tb = type(a), type(b)
  if ta == tb then
    if ta == 'string' or ta == 'number' then
      return a < b
    end
    return tostring(a) < tostring(b)
  end
  return ta < tb
end

local function remove(m, k)
  local value = rawget(m, k)
  if value ~= nil then
    rawset(m, k, nil)
  end
  return value
end

local function delete(m, k)
  return remove(m, k) ~= nil
end

local function clear(m)
  for k in pairs(m) do
    rawset(m, k, nil)
  end
  return m
end

local function deleteValues(m, value)
  for k, v in pairs(m) do
    if v == value then
      rawset(m, k, nil)
    end
  end
  return m
end

local function keys(m)
  local list = {}
  for key in pairs(m) do
    table.insert(list, key)
  end
  return list
end

local function values(m)
  local list = {}
  for _, value in pairs(m) do
    table.insert(list, value)
  end
  return list
end

local function size(m)
  local n = 0
  for _ in pairs(m) do
    n = n + 1
  end
  return n
end

local function skeys(m, comp)
  local list = keys(m)
  table.sort(list, comp or compareKey)
  return list
end

local function spairs(m, comp)
  local list = skeys(m, comp)
  local index = 0
  return function(t)
    index = index + 1
    local key = list[index]
    if key then
      return key, t[key]
    end
  end, m
end

local function add(m, ...)
  local args = table.pack(...)
  for i = 1, args.n do
    local v = args[i]
    if v ~= nil then
      rawset(m, v, v)
    end
  end
  return m
end

local function reverse(m)
  local t = {}
  for k, v in pairs(m) do
    if t[v] then
      error('Duplicated value "'..tostring(v)..'"')
    end
    t[v] = k
  end
  return t
end

--- A Map class.
-- @type Map
return require('jls.lang.class').create(function(map, _, Map)

  --- Creates a new Map.
  -- @function Map:new
  function map:initialize(m)
    if type(m) == 'table' then
      self.map = m
    else
      self.map = {}
    end
  end

  --- Adds or updates an entry with a specified key and a value.
  -- @param key The key of the entry to set.
  -- @param value The value of the entry to set.
  -- @treturn jls.util.Map this map.
  function map:set(key, value)
    --if map[key] ~= nil then error('Invalid key '..tostring(key)); end
    rawset(self.map, key, value)
    return self
  end

  --- Deletes the entry with the specified key.
  -- @param key The key of the entry to delete.
  -- @treturn boolean true if an antry has been deleted.
  function map:delete(key)
    return delete(self.map, key)
  end

  --- Removes and returns the entry with the specified key.
  -- @param key The key of the entry to remove.
  -- @return the entry removed or nil.
  function map:remove(key)
    return remove(self.map, key)
  end

  --- Returns the value corresponding to the specified key.
  -- @param key The key of the entry to get.
  -- @return the value or nil.
  function map:get(key)
    return rawget(self.map, key)
  end

  --- Returns true if an entry exists for the specified key.
  -- @param key The key of the entry to test.
  -- @treturn boolean true if an entry exists.
  function map:has(key)
    return rawget(self.map, key) ~= nil
  end

  --- Deletes all entries.
  function map:clear()
    clear(self.map)
    return self
  end

  function map:deleteValues(value)
    deleteValues(self.map, value)
    return self
  end

  --- Returns the keys.
  -- @treturn table the keys.
  function map:keys()
    return keys(self.map)
  end

  --- Returns the values.
  -- @treturn table the values.
  function map:values()
    return values(self.map)
  end

  --- Returns the number of entries.
  -- @treturn number the number of entries.
  function map:size()
    return size(self.map)
  end

  --- Returns the keys, sorted.
  -- @tparam[opt] function comp The comparison function.
  -- @treturn table the keys.
  function map:skeys(comp)
    return skeys(self.map, comp)
  end

  --- Returns an iterator sorted and suitable for the generic "for" loop.
  -- @tparam[opt] function comp The comparison function.
  -- @return an iterator.
  function map:spairs(comp)
    return spairs(self.map, comp)
  end

  --- Adds a new element to this map such as the key is also the value.
  -- This method allows to use this map as a set.
  -- @param ... Additional values to add.
  -- @treturn jls.util.Map this map.
  function map:add(...)
    add(self.map, ...)
    return self
  end

  function map:reverse()
    return Map:new(reverse(self.map))
  end

  --- Sets all key-values of the specified tables to the target table.
  -- @tparam table target The table to update.
  -- @tparam table ... The tables to get key-values from.
  -- @treturn table the target table.
  function Map.assign(target, ...)
    local sources = table.pack(...)
    for i = 1, sources.n do
      local source = sources[i]
      if type(source) == 'table' then
        for key, sourceValue in pairs(source) do
          rawset(target, key, sourceValue)
        end
      end
    end
    return target
  end

  Map.compareKey = compareKey

  Map.delete = delete
  Map.deleteValues = deleteValues
  Map.remove = remove
  Map.size = size
  Map.keys = keys
  Map.values = values
  Map.skeys = skeys
  Map.spairs = spairs
  Map.add = add
  Map.reverse = reverse

end)
