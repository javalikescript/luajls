local ASYNC_MT = {
  __index = function(self, key)
    if not self._cleanmt and self._metatable and not debug.getmetatable(self._data) then
      self._cleanmt = true
      debug.setmetatable(self._data, self._metatable)
    end
    local value = self._data[key]
    if type(value) == 'function' then
      local fn = function(w, ...)
        return value(w._data, ...)
      end
      self[key] = fn
      return fn
    end
    return value
  end,
  __gc = function(self)
    if self._cleanmt then
      debug.setmetatable(self._data, nil)
    end
  end
}
-- luv removes the metatable from the userdata async arguments, to disable the GC.
-- This function captures the metatable then restores it until GC.
return function(value)
  if type(value) == 'userdata' then
    local mt = debug.getmetatable(value)
    if mt then
      return setmetatable({
        _cleanmt = false,
        _metatable = mt,
        _data = value
      }, ASYNC_MT)
    end
  end
  return value
end
