--- Represents an array.
-- @module jls.util.TableList
-- @pragma nostrip


--- A TableList class.
-- @type TableList
return require('jls.lang.class').create(function(tableList, _, TableList)

  local function previous(list, index)
    index = index - 1
    if index > 0 then
        return index, list[index]
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

  --- Creates a new TableList.
  -- @function TableList:new
  function tableList:initialize(...)
    if ... then
      self:add(...)
    end
  end

  function tableList:reverseIterator()
    return previous, self, #self + 1
  end

  function tableList:indexOf(value)
    for i, v in ipairs(self) do
      if v == value then
        return i
      end
    end
    return 0
  end

  local irpairs = tableList.reverseIterator

  function tableList:lastIndexOf(value)
    for i, v in irpairs(self) do
      if v == value then
        return i
      end
    end
  end

  --- Adds a new element at the end of this list.
  -- @param value The element to add at the end of this list.
  -- @treturn jls.util.TableList this list.
  function tableList:add(value, ...)
    if value == nil then
      error('Cannot add nil value')
    end
    table.insert(self, value)
    if ... then
      self:addAll({...})
    end
    return self
  end

  function tableList:addAll(values)
    for _, value in ipairs(values) do
      table.insert(self, value)
    end
    return self
  end

  --- Removes the element at the specified index.
  -- @tparam integer index The index of the element to remove.
  -- @return The value of the removed element.
  function tableList:remove(index)
    return table.remove(self, index)
  end

  local indexOf = tableList.indexOf

  --- Removes the first specified value from this list.
  -- The matching values are found using equality (==)
  -- @param value The value to remove from the list.
  -- @treturn boolean true if a value has been removed.
  function tableList:removeFirst(value)
    local index = indexOf(self, value)
    if index > 0 then
      table.remove(self, index)
      return true
    end
    return false
  end

  local lastIndexOf = tableList.lastIndexOf

  --- Removes the last specified value from this list.
  -- @param value The value to remove from the list.
  -- @treturn boolean true if a value has been removed.
  function tableList:removeLast(value)
    local index = lastIndexOf(self, value)
    if index then
      table.remove(self, index)
      return true
    end
    return false
  end

  --- Removes the specified value from this list.
  -- @param value The value to remove from the list.
  function tableList:removeAll(value)
    for i, v in irpairs(self) do
      if v == value then
        table.remove(self, i)
      end
    end
    return self
  end

  function tableList:removeIf(removeFn, removedList)
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
  -- @treturn jls.util.TableList this list.
  function tableList:insert(index, value)
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
  function tableList:size()
    return #self
  end

  function tableList:clear()
    for k in pairs(self) do
      self[k] = nil
    end
    return self
  end

  function tableList:concat(...)
    return concat(TableList:new(), self, ...)
  end

  function tableList:clone()
    return TableList:new():addAll(self)
  end

  function tableList:get(index)
    return self[index]
  end

  function tableList:set(index, value)
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

  function tableList:isEmpty()
    return #self == 0
  end

  function tableList:shift()
    return self:remove(1)
  end

  function tableList:pop()
    return self:remove()
  end

  function tableList:filter(filterFn, unfilteredList)
    local filtered = TableList:new()
    for i, v in ipairs(self) do
      if filterFn(v, i, self) then
        filtered:add(v)
      elseif unfilteredList then
        unfilteredList:add(v)
      end
    end
    return filtered, unfilteredList
  end

  function tableList:contains(value)
    return value ~= nil and indexOf(self, value) > 0
  end

  function tableList:sort(comp)
    -- TODO Should fallback to a comparison function that accept any value, Map.compareKey
    table.sort(self, comp)
    return self
  end

  function tableList:iterator()
    return ipairs(self)
  end

  --- Returns a string by concatenating all the values of the specified list.
  -- tostring() is used to get the string of a value.
  -- @tparam[opt] string sep An optional separator to add between values.
  -- @tparam[opt] integer i The index of the first value, default is 1.
  -- @tparam[opt] integer j The index of the last value, default is #list.
  -- @treturn string a string with all values joined.
  function tableList:join(sep, i, j)
    local l = {}
    for _, value in ipairs(self) do
      table.insert(l, tostring(value))
    end
    return table.concat(l, sep, i, j)
  end


  TableList.indexOf = indexOf

  TableList.lastIndexOf = lastIndexOf

  TableList.irpairs = irpairs

  TableList.filter = TableList.prototype.filter

  TableList.contains = TableList.prototype.contains

  TableList.sort = TableList.prototype.sort

  --- Removes the first specified value from the specified list.
  -- @tparam table list The list from which to remove the value.
  -- @param value The value to remove from the list.
  -- @treturn boolean true if a value has been removed.
  -- @function TableList.removeFirst
  TableList.removeFirst = TableList.prototype.removeFirst

  --- Removes the last specified value from the specified list.
  -- @tparam table list The list from which to remove the value.
  -- @param value The value to remove from the list.
  -- @treturn boolean true if a value has been removed.
  -- @function TableList.removeLast
  TableList.removeLast = TableList.prototype.removeLast

  --- Removes the specified value from the specified list.
  -- @tparam table list The list from which to remove the value.
  -- @param value The value to remove from the list.
  -- @function TableList.removeAll
  TableList.removeAll = TableList.prototype.removeAll

  TableList.removeIf = TableList.prototype.removeIf

  --- Returns a string by concatenating all the values of the specified list.
  -- tostring() is used to get the string of a value.
  -- @tparam table list The list of values to concatenate.
  -- @tparam[opt] string sep An optional separator to add between values.
  -- @tparam[opt] integer i The index of the first value, default is 1.
  -- @tparam[opt] integer j The index of the last value, default is #list.
  -- @treturn string a string with all values joined.
  -- @function TableList.join
  TableList.join = TableList.prototype.join

  function TableList.concat(...)
    return concat({}, ...)
  end

  local RESERVED_NAMES = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}

  --- Returns true when the specified value is a Lua name.
  -- Names in Lua are any string of letters, digits, and underscores, not beginning with a digit and not being a reserved word.
  -- @tparam string value The string value to check.
  -- @treturn boolean true when the specified value is a Lua name.
  function TableList.isName(value)
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
  function TableList.isList(t, withHoles, acceptEmpty)
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