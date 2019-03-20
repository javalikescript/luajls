--- Provide table helper functions.
-- @module jls.util.tables

local tables = {}

function tables.indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end
end

function tables.lastIndexOf(list, value)
  for i = #list, 1, -1 do
    if list[i] == value then
      return i
    end
  end
end

function tables.filter(list, filterFn)
  local filtered = {}
  for i, v in ipairs(list) do
    if filterFn(v, i, list) then
      table.insert(filtered, v)
    end
  end
  return filtered
end

function tables.concat(list, sep)
  sep = sep or ''
  local buffer
  for _, value in ipairs(list) do
    if buffer then
      buffer = buffer..sep..tostring(value)
    else
      buffer = tostring(value)
    end
  end
  return buffer or ''
end

function tables.split(value, pattern, plain)
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

--- Removes the specifed value from the specified table.
-- The matching values are found using equality (==)
-- @tparam table list The table from which to remove the value.
-- @param value The value to remove from the table.
-- @tparam boolean last true to remove only the last value.
-- @treturn table the table to allow method chaining.
function tables.removeTableValue(list, value, last)
  for i = #list, 1, -1 do
    if list[i] == value then
      table.remove(list, i)
      if last then
        break
      end
    end
  end
  return list
end

local function reverseIterator(list, index)
  index = index - 1
  if index > 0 then
      return index, list[index]
  end
end
function tables.irpairs(list) -- reverseIteratorFactory
  return reverseIterator, list, #list - 1
end

function tables.deepCopy(t)
  local c = {}
  for k, v in pairs(t) do
    if type(v) == 'table' then
      v = tables.deepCopy(v)
    end
    c[k] = v
  end
  return c
end

function tables.deepEquals(a, b)
  for k, va in pairs(a) do
    local vb = b[k]
    if not vb then
      return false
    end
    local vat = type(va)
    local vbt = type(vb)
    if vat ~= vbt then
      return false
    end
    if vat == 'table' then
      if not tables.deepEquals(va, vb) then
        return false
      end
    elseif va ~= vb then
      return false
    end
  end
  for k, vb in pairs(b) do
    if not a[k] then
      return false
    end
  end
  return true
end

function tables.merge(baseTable, mergeTable, keep)
  for key, mergeValue in pairs(mergeTable) do
    local baseValue = baseTable[key]
    local baseType = type(baseValue)
    if baseType == 'table' and baseType == type(mergeValue) then
      tables.merge(baseValue, mergeValue, keep)
    elseif baseValue == nil or not keep then
      baseTable[key] = mergeValue
    end
  end
  return baseTable
end


--- Returns a table containing the differences between the two specified tables.
-- The additions or modifications are availables, the same values are discarded
-- and the deleted values are listed in a specific table entry named "_deleted".
-- @tparam table oldTable a base table.
-- @tparam table newTable a modified table.
-- @treturn table the differences or nil if there is no such difference.
function tables.compare(oldTable, newTable)
  -- oldTable and newTable must be of type table
  local diff
  -- TODO we may want to detect renamed keys
  -- TODO we may want to detect moved list entries
  -- TODO we may want to compare long strings
  for key, newValue in pairs(newTable) do
    local oldValue = oldTable[key]
    local oldType = type(oldValue)
    local newType = type(newValue)
    local diffValue
    if oldType ~= newType then -- new type and value cannot be nil
      diffValue = newValue
    else
      if newType == 'table' then
        diffValue = tables.compare(oldValue, newValue)
      else
        if oldValue ~= newValue then
          diffValue = newValue
        end
      end
    end
    if diffValue ~= nil then
      if not diff then
        diff = {}
      end
      diff[key] = diffValue
    end
  end
  local deleted
  for key, oldValue in pairs(oldTable) do
    if newTable[key] == nil then
      if deleted then
        table.insert(deleted, key)
      else
        deleted = {key}
      end
    end
  end
  if deleted then
    if not diff then
      diff = {}
    end
    diff._deleted = deleted
  end
  return diff
end

--- Returns a table patched according to the specified differences.
-- @tparam table oldTable a base table.
-- @tparam table diff the differences to apply to the base table.
-- @treturn table the differences or nil if there is no such difference.
function tables.patch(oldTable, diff)
  local newTable = {}
  local deleted = {}
  if diff._deleted then
    for _, key in ipairs(diff._deleted) do
      deleted[key] = true
    end
  end
  for key, oldValue in pairs(oldTable) do
    if not deleted[key] then
      local newValue
      local oldType = type(oldValue)
      local diffValue = diff[key]
      if diffValue ~= nil then
        local diffType = type(diffValue)
        if oldType == diffType and oldType == 'table' then
          newValue = tables.patch(oldValue, diffValue)
        else
          newValue = diffValue
        end
      else
        newValue = oldValue
      end
      newTable[key] = newValue -- we may want to deep copy the value in case of table
    end
  end
  for key, diffValue in pairs(diff) do
    if oldTable[key] == nil and key ~= '_deleted' then
      newTable[key] = diffValue -- we may want to deep copy the value in case of table
    end
  end
  return newTable
end

--[[
--- Returns the value resulting of the evaluation of the specified path against the specified table.
-- Valid paths are a/b, a[1] ~ a/[1], a[@id='b'] ~ a/*[@id='b']
-- @tparam table t a table.
-- @tparam string path the expression to evaluate against the table.
-- @return the evaluated value, list of values or nil.
function tables.evaluatePath(t, path)
  --local localPath = string.gsub(path, '/.*$', '')
  --local remainingPath = string.gsub(path, '^[^/]*/', '')
  local localPath, remainingPath = string.match(path, '^([^/]*)/(.*)$')
  if not localPath then
    localPath = path
  end
  local key, expression = string.match(localPath, '^([^%[]*)%[(.+)%]$')
  local value
  if expression then
    if #key > 0 then
      if remainingPath then
        remainingPath = '['..expression..']/'..remainingPath
      else
        remainingPath = '['..expression..']'
      end
      value = t[key]
    else
      local index = tonumber(expression)
      if index then
        value = t[index]
      else
        -- TODO

      end
    end
  else
    value = t[localPath]
  end
  if remainingPath then
    if type(value) == 'table' then
      return tables.find(value, remainingPath)
    end
    return nil
  end
  return value
end
]]


--- Returns a table containing an entry for each argument name.
-- An entry contains a string or a list of string.
-- An argument name starts with a comma ('-').
-- The arguments without name are available under the empty name ('').
-- @tparam string arguments the command line containing the arguments.
-- @treturn table the arguments as a table.
function tables.createArgumentTable(arguments)
  local t = {}
  local name = ''
  for _, argument in ipairs(arguments) do
    if string.find(argument, '^-') then
      name = argument
    else
      local value = t[name]
      local et = type(value)
      if et == 'nil' then
        t[name] = argument
      elseif et == 'table' then
        table.insert(value, argument)
      else
        t[name] = {value, argument}
      end
      name = ''
    end
  end
  return t
end

function tables.getArgument(t, name, defaultValue)
  local value = t[name]
  if value == nil then
    return defaultValue
  end
  if type(value) == 'table' then
    return value[1]
  end
  return value
end


local function getPathKey(path)
  local key, remainingPath
  local s = 1
  local p = string.find(path, '/', s, true)
  if p == 1 then
    s = 2
    p = string.find(path, '/', s, true)
  end
  if p then
    key = string.sub(path, s, p - 1)
    remainingPath = string.sub(path, p + 1)
  elseif s ~= 1 then
    key = string.sub(path, s)
  else
    key = path
  end
  -- local key, remainingPath = string.match(path, '^/?([^/]+)/(.*)$')
  -- if not key then
  --   key = path
  -- end
  local index = tonumber(key)
  if index then
    return index, remainingPath
  end
  return key, remainingPath
end

--- Returns the value at the specified path in the specified table.
-- A path consists in table keys separated by slashes.
-- The key are considered as string or number.
-- @tparam table t a table.
-- @tparam string path the path to look in the table.
-- @param defaultValue the default value to return if there is no value for the path.
-- @return the value
function tables.getPath(t, path, defaultValue)
  local key, remainingPath = getPathKey(path)
  local value
  if key == '' then
    value = t
  else
    value = t[key]
  end
  if remainingPath then
    if type(value) == 'table' then
      return tables.getPath(value, remainingPath, defaultValue)
    end
    value = nil
  end
  if value == nil then
    return defaultValue
  end
  return value, t, key
end

--- Sets the specified value at the specified path in the specified table.
-- @tparam table t a table.
-- @tparam string path the path to set in the table.
-- @param value the value to set.
-- @return the previous value.
function tables.setPath(t, path, value)
  local key, remainingPath = getPathKey(path)
  local v = t[key]
  if remainingPath and remainingPath ~= '' then
    if type(v) ~= 'table' then
      -- if the entry does not exist or is not a table then create an intermediary table
      v = {}
      t[key] = v
    end
    return tables.setPath(v, remainingPath, value)
  end
  t[key] = value
  return v
end

function tables.mergePath(t, path, value, keep)
  local key, remainingPath = getPathKey(path)
  local v = t[key]
  if remainingPath and remainingPath ~= '' then
    if type(v) ~= 'table' then
      -- if the entry does not exist or is not a table then create an intermediary table
      v = {}
      t[key] = v
    end
    return tables.mergePath(v, remainingPath, value, keep)
  end
  if type(v) ~= 'table' then
    t[key] = value
  else
    tables.merge(t[key], value, keep)
  end
  return v
end

--- Removes the value at the specified path in the specified table.
-- @tparam table t a table.
-- @tparam string path the path to remove in the table.
-- @return the removed value.
function tables.removePath(t, path)
  local key, remainingPath = getPathKey(path)
  local value = t[key]
  if remainingPath then
    if type(value) == 'table' then
      return tables.removePath(value, remainingPath)
    end
    return nil
  end
  if type(key) == 'number' then
    table.remove(t, key)
  else
    t[key] = nil
  end
  return value
end

local function mapValuesByPath(t, paths, path)
  for k, v in pairs(t) do
    local p = path..'/'..tostring(k)
    if type(v) == 'table' then
      mapValuesByPath(v, paths, p)
    else
      paths[p] = v
    end
  end
  return paths
end

function tables.mapValuesByPath(t, path)
  return mapValuesByPath(t, {}, path or '')
end

function tables.setByPath(baseTable, mergeTable)
  local valuesByPath = mapValuesByPath(mergeTable, {}, '')
  for path, value in pairs(valuesByPath) do
    tables.setPath(baseTable, path, value)
  end
  return baseTable
end

local EMPTY_TABLE = {}

local function mergeValuesByPath(oldTable, newTable, paths, path)
  for k, oldValue in pairs(oldTable) do
    local p = path..'/'..tostring(k)
    local oldType = type(oldValue)
    local newValue = newTable[k]
    if newValue == nil then
      if oldType == 'table' then
        mergeValuesByPath(oldValue, EMPTY_TABLE, paths, p)
      else
        paths[p] = {old = oldValue}
      end
    else
      local newType = type(newValue)
      if oldType == 'table' then
        if newType == 'table' then
          mergeValuesByPath(oldValue, newValue, paths, p)
        else
          mergeValuesByPath(oldValue, EMPTY_TABLE, paths, p)
          paths[p] = {new = newValue}
        end
      elseif newType == 'table' then
        mergeValuesByPath(EMPTY_TABLE, newValue, paths, p)
        paths[p] = {old = oldValue}
      else
        paths[p] = {old = oldValue, new = newValue}
      end
    end
  end
  for k, newValue in pairs(newTable) do
    if oldTable[k] == nil then
      local p = path..'/'..tostring(k)
      if type(newValue) == 'table' then
        mergeValuesByPath(EMPTY_TABLE, newValue, paths, p)
      else
        paths[p] = {new = newValue}
      end
    end
  end
  return paths
end

function tables.mergeValuesByPath(oldTable, newTable, path)
  return mergeValuesByPath(oldTable, newTable, {}, path or '')
end

return tables