--- Represents a mutable string.
-- @module jls.lang.StringBuffer
-- @pragma nostrip

--- A StringBuffer class.
-- The StringBuffer optimizes the addition of strings in a buffer by avoiding the use of intermediary concatenated string.
-- @type StringBuffer
return require('jls.lang.class').create(function(stringBuffer, _, StringBuffer)

  --- Creates a new StringBuffer.
  -- @tparam[opt] string value the initial value.
  -- @function StringBuffer:new
  function stringBuffer:initialize(value)
    self:clear()
    self:append(value)
  end

  function stringBuffer:clone()
    return StringBuffer:new(self)
  end

  --- Appends the string representation of the value to this buffer.
  -- @param value the value to append.
  -- @treturn jls.lang.StringBuffer this buffer.
  function stringBuffer:append(value)
    local valueType = type(value)
    local valueString
    if valueType == 'string' then
      valueString = value
    elseif valueType == 'number' or valueType == 'boolean' then
      valueString = tostring(value)
    elseif valueType == 'table' then
      if StringBuffer:isInstance(value) then
        for _, s in ipairs(value.values) do
          table.insert(self.values, s)
        end
        self.len = self.len + value.len
        return self
      elseif type(value.toString) == 'function' then
        valueString = value:toString()
      end
    end
    if valueString ~= nil then
      table.insert(self.values, valueString)
      self.len = self.len + string.len(valueString)
    end
    return self
  end

  function stringBuffer:cut(i)
    local ii = 1
    for index, value in ipairs(self.values) do
      local l = string.len(value)
      local jj = ii + l
      if jj > i then
        if i > ii then
          self.values[index] = string.sub(value, 1 + i - ii)
          table.insert(self.values, index, string.sub(value, 1, i - ii))
          return self, index + 1
        end
        return self, index
      end
      ii = jj
    end
    return self
  end

  --- Removes a part of this string buffer.
  -- @tparam number i the index of the first byte to remove, inclusive.
  -- @tparam[opt] number j the index of the last byte to remove, exclusive.
  -- @treturn jls.lang.StringBuffer this buffer.
  function stringBuffer:delete(i, j)
    local _, ii = self:cut(i)
    local jj
    if j then
      _, jj = self:cut(j)
    else
      jj = #self.values
    end
    if ii and jj then
      if ii > jj then
        ii, jj = jj, ii
      end
      local l = 0
      for k = jj - 1, ii, -1 do
        local s = table.remove(self.values, k)
        l = l + string.len(s)
      end
      self.len = self.len - l
    end
    return self, ii
  end

  --- Inserts a string to this string buffer at the specified position.
  -- @tparam number i the index of the byte where the string will be inserted.
  -- @tparam string s the string to insert.
  -- @treturn jls.lang.StringBuffer this buffer.
  function stringBuffer:insert(i, s)
    if type(s) == 'string' and s ~= '' then
      local _, ii = self:cut(i)
      if ii then
        table.insert(self.values, ii, s)
        self.len = self.len + string.len(s)
      end
    end
    return self
  end

  --- Replaces a part of this string buffer by the specified string.
  -- @tparam number i the index of the byte where the string will be inserted.
  -- @tparam number j the index of the last byte to replace, exclusive.
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