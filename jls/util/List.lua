--- Represents a list.
-- The functions could be used for Lua tables.
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
    for _, e in ipairs({...}) do
      if type(e) == 'table' then
        for _, v in ipairs(e) do
          table.insert(l, v)
        end
      else
        table.insert(l, e)
      end
    end
    return l
  end

  local function map(d, s, f)
    if f == nil and type(s) == 'function' then
      d, s, f = {}, d, s
    end
    for i, v in ipairs(s) do
      table.insert(d, f(v, i, s))
    end
    return d
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
    if ... then
      self:addAll({...})
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

  function list:map(f)
    return map(List:new(), self, f)
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

  function list:filter(filterFn, unfilteredList)
    local filtered = List:new()
    for i, v in ipairs(self) do
      if filterFn(v, i, self) then
        filtered:add(v)
      elseif unfilteredList then
        unfilteredList:add(v)
      end
    end
    return filtered, unfilteredList
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

  function List.filter(l, filterFn, unfilteredList)
    local filtered = {}
    for i, v in ipairs(l) do
      if filterFn(v, i, l) then
        table.insert(filtered, v)
      elseif unfilteredList then
        table.insert(unfilteredList, v)
      end
    end
    return filtered, unfilteredList
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

  List.concat = concat

  List.map = map

  local RESERVED_NAMES = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}

  --- Returns true when the specified value is a Lua name.
  -- Names in Lua are any string of letters, digits, and underscores, not beginning with a digit and not being a reserved word.
  -- @tparam string value The string value to check.
  -- @treturn boolean true when the specified value is a Lua name.
  function List.isName(value)
    if string.find(value, '^[%a_][%a%d_]*$') and indexOf(RESERVED_NAMES, value) == 0 then
      return true
    end
    return false
  end

  --- Returns true when the specified table is a list.
  -- A list has continuous integer keys starting at 1.
  -- @tparam table t The table to check.
  -- @tparam[opt] boolean withHoles true to indicate that the list may have holes.
  -- @tparam[opt] boolean acceptEmpty true to indicate that the list could be empty.
  -- @treturn boolean true when the specified table is a list.
  -- @treturn number the number of fields of the table.
  function List.isList(t, withHoles, acceptEmpty)
    if type(t) ~= 'table' then
      return false
    end
    local count = 0
    local size = 0
    local min, max
    for k in pairs(t) do
      if math.type(k) == 'integer' then
        if not min or k < min then
          min = k
        end
        if not max or k > max then
          max = k
        end
        size = size + 1
      else
        count = count + 1
      end
    end
    if acceptEmpty and count == 0 and size == 0 then
      return true, 0
    end
    local result = count == 0 and min == 1 and (max == size or withHoles)
    return result, count + size
  end

end)