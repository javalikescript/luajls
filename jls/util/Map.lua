--- Represents a map.
-- @module jls.util.Map
-- @pragma nostrip

-- TODO An OrderedMap that garantee key insertion order
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

--- A Map class.
-- @type Map
return require('jls.lang.class').create(function(map)

  --- Creates a new Map.
  -- @function Map:new

  --- Adds or updates an entry with a specified key and a value.
  -- @param key The key of the entry to set.
  -- @param value The value of the entry to set.
  -- @treturn jls.util.Map this map.
  function map:set(key, value)
    self[key] = value
    return self
  end

  --- Deletes the entry with the specified key.
  -- @param key The key of the entry to delete.
  -- @treturn boolean true if an antry has been deleted.
  function map:delete(key)
    if self[key] == nil then
      return false
    end
    self[key] = nil
    return true
  end

  --- Removes and returns the entry with the specified key.
  -- @param key The key of the entry to remove.
  -- @return the entry removed or nil.
  function map:remove(key)
    local value = self[key]
    if value == nil then
      return false
    end
    self[key] = nil
    return value
  end

  --- Returns the value corresponding to the specified key.
  -- @param key The key of the entry to get.
  -- @return the value or nil.
  function map:get(key)
    return self[key]
  end

  --- Returns true if an entry exists for the specified key.
  -- @param key The key of the entry to test.
  -- @treturn boolean true if an entry exists.
  function map:has(key)
    return self[key] ~= nil
  end

  --- Deletes all entries.
  function map:clear()
    for k in pairs(self) do
      self[k] = nil
    end
    return self
  end

  --- Returns the keys.
  -- @treturn table the keys.
  function map:keys()
    local keys = {}
    for key in pairs(self) do
      table.insert(keys, key)
    end
    return keys
  end

  --- Returns the values.
  -- @treturn table the values.
  function map:values()
    local values = {}
    for _, value in pairs(self) do
      table.insert(values, value)
    end
    return values
  end

  --- Returns the number of entries.
  -- @treturn number the number of entries.
  function map:size()
    local size = 0
    for _ in pairs(self) do
      size = size + 1
    end
    return size
  end

  --- Returns the keys, sorted.
  -- @tparam[opt] function comp The comparison function.
  -- @treturn table the keys.
  function map:skeys(comp)
    local keys = map.keys(self)
    table.sort(keys, comp or compareKey)
    return keys
  end

  --- Returns an iterator sorted and suitable for the generic "for" loop.
  -- @tparam[opt] function comp The comparison function.
  -- @return an iterator.
  function map:spairs(comp)
    local keys = map.skeys(self, comp)
    local index = 0
    return function(m)
      index = index + 1
      local key = keys[index]
      if key then
        return key, m[key]
      end
    end, self
  end

end, function(Map)

  --- Sets all key-values of the specified tables to the target table.
  -- @tparam table target The table to update.
  -- @tparam table ... The tables to get key-values from.
  -- @treturn table the target table.
  function Map.assign(target, ...)
    local sources = {...}
    for _, source in ipairs(sources) do
      for key, sourceValue in pairs(source) do
        target[key] = sourceValue
      end
    end
    return target
  end

  Map.compareKey = compareKey

  Map.delete = Map.prototype.delete
  Map.remove = Map.prototype.remove
  Map.size = Map.prototype.size
  Map.keys = Map.prototype.keys
  Map.values = Map.prototype.values
  Map.skeys = Map.prototype.skeys
  Map.spairs = Map.prototype.spairs

end)
