--- Represents a list.
-- The class functions could be used for Lua tables.
-- @module jls.util.List
-- @pragma nostrip


--- A List class.
-- @type List
return require('jls.lang.class').create(function(list, _, List)

  local function previous(l, index)
    index = index - 1
    if index > 0 then
        return index, l[index]
    end
  end

  local function concat(l, ...)
    local size = select('#', ...)
    if size > 0 then
      local values = {...}
      for i = 1, size do
        local e = values[i]
        if type(e) == 'table' then
          for _, v in ipairs(e) do
            table.insert(l, v)
          end
        elseif e ~= nil then
          table.insert(l, e)
        end
      end
    end
    return l
  end

  local function map(d, s, f)
    if f == nil and type(s) == 'function' then
      d, s, f = {}, d, s
    end
    for i, v in ipairs(s) do
      d[i] = f(v, i, s)
    end
    return d
  end

  local function filter(l, f, lf, lu)
    for i, v in ipairs(l) do
      if f(v, i, l) then
        table.insert(lf, v)
      elseif lu then
        table.insert(lu, v)
      end
    end
    return lf, lu
  end

  --- Creates a new List.
  -- @param[opt] ... The values to add to the list.
  -- @function List:new
  function list:initialize(...)
    if ... then
      self:add(...)
    end
  end

  function list:reverseIterator()
    return previous, self, #self + 1
  end

  --- Returns the index where the value is found or 0 if not present.
  -- @param value The element to look for.
  -- @treturn number the index or 0 if not present.
  function list:indexOf(value)
    for i, v in ipairs(self) do
      if v == value then
        return i
      end
    end
    return 0
  end

  local irpairs = list.reverseIterator

  function list:lastIndexOf(value)
    for i, v in irpairs(self) do
      if v == value then
        return i
      end
    end
  end

  --- Adds a new element at the end of this list.
  -- @param value The element to add at the end of this list.
  -- @param[opt] ... Additional values to add.
  -- @treturn jls.util.List this list.
  function list:add(value, ...)
    if value == nil then
      error('Cannot add nil value')
    end
    table.insert(self, value)
    local size = select('#', ...)
    if size > 0 then
      local values = {...}
      for i = 1, size do
        local v = values[i]
        if v == nil then
          error('Cannot add nil value')
        end
        table.insert(self, v)
      end
    end
    return self
  end

  function list:addAll(values)
    for _, value in ipairs(values) do
      table.insert(self, value)
    end
    return self
  end

  --- Removes the element at the specified index.
  -- @tparam integer index The index of the element to remove.
  -- @return The value of the removed element.
  function list:remove(index)
    return table.remove(self, index)
  end

  local indexOf = list.indexOf

  --- Removes the first specified value from this list.
  -- The matching values are found using equality (==)
  -- @param value The value to remove from the list.
  -- @treturn boolean true if a value has been removed.
  function list:removeFirst(value)
    local index = indexOf(self, value)
    if index > 0 then
      table.remove(self, index)
      return true
    end
    return false
  end

  local lastIndexOf = list.lastIndexOf

  --- Removes the last specified value from this list.
  -- @param value The value to remove from the list.
  -- @treturn boolean true if a value has been removed.
  function list:removeLast(value)
    local index = lastIndexOf(self, value)
    if index then
      table.remove(self, index)
      return true
    end
    return false
  end

  --- Removes the specified value from this list.
  -- @param value The value to remove from the list.
  function list:removeAll(value)
    for i, v in irpairs(self) do
      if v == value then
        table.remove(self, i)
      end
    end
    return self
  end

  function list:removeIf(removeFn, removedList)
    for i, v in irpairs(self) do
      if removeFn(v, i, self) then
        table.remove(self, i)
        if removedList then
          table.insert(removedList, v)
        end
      end
    end
    return self
  end

  --- Inserts a new element to this list at the specified index.
  -- @tparam integer index The index where to insert the element.
  -- @param value The element to insert to this list.
  -- @treturn jls.util.List this list.
  function list:insert(index, value)
    if value == nil then
      error('Cannot add nil value')
    end
    if index < 1 or index > #self then
      error('Index out of bounds')
    end
    table.insert(self, index, value)
    return self
  end

  --- Returns the size of this list.
  -- @treturn integer the size of this list.
  function list:size()
    return #self
  end

  function list:clear()
    for k in pairs(self) do
      self[k] = nil
    end
    return self
  end

  function list:concat(...)
    return concat(List:new(), self, ...)
  end

  --- Returns a list containing the result of the function called on each element.
  -- @tparam function f The function to call on each element.
  -- @treturn jls.util.List the new list.
  function list:map(f)
    return map(List:new(), self, f)
  end

  --- Returns the last result of the function called on each element.
  -- @tparam function f The function to call on each element.
  -- The function is called with the last result, element, index and the list.
  -- @param[opt] value The initial value.
  -- @return the last result of the function.
  function list:reduce(f, value)
    local a = value
    for i, v in ipairs(self) do
      if i == 1 and a == nil then
        a = v
      else
        a = f(a, v, i, self)
      end
    end
    return a
  end


  function list:clone()
    return List:new():addAll(self)
  end

  function list:get(index)
    return self[index]
  end

  function list:set(index, value)
    if value == nil then
      error('Cannot add nil value')
    end
    if index < 1 or index > #self then
      error('Index out of bounds')
    end
    local previousValue = self[index]
    self[index] = value
    return previousValue
  end

  function list:isEmpty()
    return #self == 0
  end

  function list:shift()
    return self:remove(1)
  end

  function list:pop()
    return self:remove()
  end

  function list:filter(f, l)
    return filter(self, f, List:new(), l)
  end

  function list:contains(value)
    return value ~= nil and indexOf(self, value) > 0
  end

  function list:sort(comp)
    -- TODO Should fallback to a comparison function that accept any value, Map.compareKey
    table.sort(self, comp)
    return self
  end

  function list:iterator()
    return ipairs(self)
  end

  --- Returns a string by concatenating all the values of the specified list.
  -- tostring() is used to get the string of a value.
  -- @tparam[opt] string sep An optional separator to add between values.
  -- @tparam[opt] integer i The index of the first value, default is 1.
  -- @tparam[opt] integer j The index of the last value, default is #list.
  -- @treturn string a string with all values joined.
  function list:join(sep, i, j)
    local l = {}
    for _, value in ipairs(self) do
      table.insert(l, tostring(value))
    end
    return table.concat(l, sep, i, j)
  end


  List.indexOf = indexOf

  List.lastIndexOf = lastIndexOf

  List.irpairs = irpairs

  function List.filter(l, f, lu)
    return filter(l, f, {}, lu)
  end

  List.contains = List.prototype.contains

  List.sort = List.prototype.sort

  --- Removes the first specified value from the specified list.
  -- @tparam table list The list from which to remove the value.
  -- @param value The value to remove from the list.
  -- @treturn boolean true if a value has been removed.
  -- @function List.removeFirst
  List.removeFirst = List.prototype.removeFirst

  --- Removes the last specified value from the specified list.
  -- @tparam table list The list from which to remove the value.
  -- @param value The value to remove from the list.
  -- @treturn boolean true if a value has been removed.
  -- @function List.removeLast
  List.removeLast = List.prototype.removeLast

  --- Removes the specified value from the specified list.
  -- @tparam table list The list from which to remove the value.
  -- @param value The value to remove from the list.
  -- @function List.removeAll
  List.removeAll = List.prototype.removeAll

  List.removeIf = List.prototype.removeIf

  --- Returns a string by concatenating all the values of the specified list.
  -- tostring() is used to get the string of a value.
  -- @tparam table list The list of values to concatenate.
  -- @tparam[opt] string sep An optional separator to add between values.
  -- @tparam[opt] integer i The index of the first value, default is 1.
  -- @tparam[opt] integer j The index of the last value, default is #list.
  -- @treturn string a string with all values joined.
  -- @function List.join
  List.join = List.prototype.join

  List.shift = List.prototype.shift

  List.pop = List.prototype.pop

  List.addAll = List.prototype.addAll

  List.reduce = List.prototype.reduce

  List.concat = concat

  --- Returns a table containing the result of the function called on each element of the source table.
  -- @tparam[opt] table d the destination table, if missing then a new table will be returned.
  -- @tparam table t the table containing the elements to map.
  -- @tparam function f the function to call on each element.
  -- @treturn table the destination table.
  -- @function List.map
  List.map = map

  local function isInteger(v)
    return type(v) == 'number' and v % 1 == 0
  end

  --- Returns the number of elements in the list or -1 if the specified table is not a list.
  -- A list has continuous integer keys starting at 1.
  -- @tparam table t The table to get the size from.
  -- @tparam[opt] boolean withHoles true to indicate that the list may have holes.
  -- @tparam[opt] boolean useN true to accept the field "n" as the number of elements.
  -- @treturn number the number of elements in the list or -1.
  function List.size(t, withHoles, useN)
    if type(t) ~= 'table' then
      return -1
    end
    if List:isInstance(t) then
      return t:size()
    end
    local size = 0
    local max = 0
    local n
    for k, v in pairs(t) do
      if isInteger(k) then
        if k > max then
          max = k
        elseif k < 1 then
          return -1
        end
        size = size + 1
      elseif useN and k == 'n' and isInteger(v) then
        n = v
      else
        return -1
      end
    end
    if n then
      if n < max then
        return -1
      end
      max = n
    end
    if max == size or withHoles then
      return max
    end
    return -1
  end

  --- Returns true when the specified table is a list.
  -- A list has continuous integer keys starting at 1.
  -- A list may have a field "n" giving the size of the list as an integer.
  -- @tparam table t The table to check.
  -- @tparam[opt] boolean withHoles true to indicate that the list may have holes.
  -- @tparam[opt] boolean acceptEmpty true to indicate that the list could be empty.
  -- @treturn boolean true when the specified table is a list.
  -- @treturn number the number of elements in the list or -1.
  function List.isList(t, withHoles, acceptEmpty)
    local size = List.size(t, withHoles, true)
    if size > 0 or size == 0 and acceptEmpty then
      return true, size
    end
    return false, size
  end

end)