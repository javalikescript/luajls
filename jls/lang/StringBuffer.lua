--- Represents a mutable string.
-- @module jls.lang.StringBuffer
-- @pragma nostrip

--- A StringBuffer class.
-- The StringBuffer optimizes the addition of strings in a buffer by avoiding the use of intermediary concatenated string.
-- @type StringBuffer
return require('jls.lang.class').create(function(stringBuffer, _, StringBuffer)

  --- Creates a new StringBuffer.
  -- @tparam[opt] string ... The initial values.
  -- @function StringBuffer:new
  function stringBuffer:initialize(...)
    self:clear()
    if ... then
      self:append(...)
    end
  end

  function stringBuffer:clone()
    return StringBuffer:new(self)
  end

  function stringBuffer:getParts()
    return self.values
  end

  function stringBuffer:addPart(value, index)
    local valueType = type(value)
    local valueString
    if valueType == 'string' then
      valueString = value
    elseif valueType == 'number' or valueType == 'boolean' then
      valueString = tostring(value)
    elseif valueType == 'table' then
      if StringBuffer:isInstance(value) then
        local parts = value:getParts()
        local len = #parts
        if index then
          table.move(self.values, index, index + len, index + len + 1)
        else
          index = #self.values + 1
        end
        table.move(parts, 1, len, index, self.values)
        self.len = self.len + value:length()
        return self
      else
        valueString = tostring(value)
      end
    end
    if valueString ~= nil and valueString ~= '' then
      if index then
        table.insert(self.values, index, valueString)
      else
        table.insert(self.values, valueString)
      end
      self.len = self.len + string.len(valueString)
    end
    return self
  end

  function stringBuffer:addParts(values)
    for _, value in ipairs(values) do
      self:addPart(value)
    end
    return self
  end

  --- Appends the string representation of the value to this buffer.
  -- @param value the value to append.
  -- @param ... more values to append.
  -- @treturn jls.lang.StringBuffer this buffer.
  function stringBuffer:append(value, ...)
    self:addPart(value)
    local l = select('#', ...)
    if l > 0 then
      local values = {...}
      for i = 1, l do
        self:addPart(values[i])
      end
    end
    return self
  end

  function stringBuffer:partAt(i)
    if i >= 1 then
      local ii = 1
      for index, value in ipairs(self.values) do
        local l = string.len(value)
        local jj = ii + l
        if jj > i then
          return value, 1 + i - ii, l, index
        end
        ii = jj
      end
    end
  end

  function stringBuffer:byte(i)
    local value, ii = self:partAt(i)
    if value then
      return string.byte(value, ii)
    end
  end

  function stringBuffer:charAt(i)
    local value, ii = self:partAt(i)
    if value then
      return string.sub(value, ii, ii)
    end
    return ''
  end

  function stringBuffer:cut(i)
    local ii = 1
    for index, value in ipairs(self.values) do
      local jj = ii + #value
      if jj > i then
        if i > ii then
          local k = i - ii
          self.values[index] = string.sub(value, k + 1)
          table.insert(self.values, index, string.sub(value, 1, k))
          return self, index + 1
        end
        return self, index
      end
      ii = jj
    end
    return self
  end

  local function length(values)
    local l = 0
    for _, value in ipairs(values) do
      l = l + #value
    end
    return l
  end

  --- Returns a part of this string buffer.
  -- @tparam number i the index of the first byte to remove.
  -- @tparam[opt] number j the index of the last byte to remove.
  -- @treturn jls.lang.StringBuffer the buffer containing the sub string.
  function stringBuffer:sub(i, j)
    local s = StringBuffer:new()
    if not i then
      return s:append(self)
    end
    if not j or j > self.len then
      j = self.len
    end
    if i > self.len or i > j then
      return s
    end
    local _, ii = self:cut(i)
    local _, jj = self:cut(j + 1)
    if jj then
      jj = jj - 1
    else
      jj = #self.values
    end
    if ii and jj then
      table.move(self.values, ii, jj, 1, s.values)
      s.len = length(s.values)
      local len = #self.values
      table.move(self.values, jj + 1, len + #s.values, ii)
      self.len = self.len - s.len
    end
    return s, ii
  end

  --- Removes a part of this string buffer.
  -- @tparam number i the index of the first byte to remove.
  -- @tparam[opt] number j the index of the last byte to remove.
  -- @treturn jls.lang.StringBuffer this buffer.
  function stringBuffer:delete(i, j)
    local _, ii = self:sub(i, j)
    return self, ii
  end

  --- Inserts a string to this string buffer at the specified position.
  -- @tparam number i the index of the byte where the string will be inserted.
  -- @tparam string s the string to insert.
  -- @treturn jls.lang.StringBuffer this buffer.
  function stringBuffer:insert(i, s)
    local _, ii = self:cut(i)
    self:addPart(s, ii)
    return self
  end

  --- Replaces a part of this string buffer by the specified string.
  -- @tparam number i the index of the byte where the string will be inserted.
  -- @tparam number j the index of the last byte to replace.
  -- @tparam string s the string to use as replacement.
  -- @treturn jls.lang.StringBuffer this buffer.
  function stringBuffer:replace(i, j, s)
    local len = self:length()
    local jj = len
    if not j or j < 1 then
      j = jj
    end
    if i < 0 then
      i = jj + i
    end
    local _, ii = self:delete(i, j)
    if ii and type(s) == 'string' and s ~= '' then
      table.insert(self.values, ii, s)
      self.len = self.len + string.len(s)
    end
    return self
  end

  function stringBuffer:clear()
    self.len = 0
    self.values = {}
    return self
  end

  function stringBuffer:concat()
    local value = table.concat(self.values)
    self.values = {value}
    return value
  end

  --- Returns the length of this buffer.
  -- @treturn number the length of this buffer.
  function stringBuffer:length()
    return self.len
  end

  --- Returns the string representation of this buffer.
  -- @treturn string the string representation of this buffer.
  function stringBuffer:toString()
    return self:concat()
  end

end)