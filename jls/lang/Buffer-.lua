local class = require('jls.lang.class')

return class.create(function(buffer)

  function buffer:initialize(size, name, preserve)
    if math.type(size) ~= 'integer' or size <= 0 then
      error('invalid size '..tostring(size))
    end
    self.size = size or 0
    self.name = name or string.format('.%s-%p.tmp', 'jls.lang.Buffer', self)
    self.file = assert(io.open(self.name, preserve and 'r+b' or 'w+b'))
    if not preserve then
      self.file:write(string.rep('\0', self.size))
      self.file:flush()
      self.initialized = true
    end
  end

  function buffer:finalize()
    if self.initialized then
      self.initialized = nil
      self.file:close()
      os.remove(self.name)
    end
  end

  function buffer:length()
    return self.size
  end

  function buffer:get(from, to)
    self.file:seek('set')
    local s = self.file:read(self.size)
    if from then
      return string.sub(s, from, to)
    end
    return s
  end

  function buffer:set(value, offset, from, to)
    self.file:seek('set', (offset or 1) - 1)
    if from then
      self.file:write(string.sub(value, from, to))
    else
      self.file:write(value)
    end
    self.file:flush()
  end

  function buffer:getBytes(from, to)
    self.file:seek('set')
    local s = self.file:read(self.size)
    return string.byte(s, from, to)
  end

  function buffer:setBytes(at, ...)
    self.file:seek('set', (at or 1) - 1)
    self.file:write(string.char(...))
    self.file:flush()
  end

  function buffer:toReference()
    return self.name..'#'..tostring(self.size)
  end

  function buffer:toString()
    return self:get()
  end

end, function(Buffer)

  function Buffer.allocate(sizeOrData)
    if type(sizeOrData) == 'string' then
      local buffer = Buffer:new(#sizeOrData)
      buffer:set(sizeOrData)
      return buffer
    end
    return Buffer:new(sizeOrData)
  end

  function Buffer.fromReference(reference)
    local name, id, size = string.match(reference, '^%.([%w%.]+)(-%x+%.tmp)#(%d+)$')
    local sz = tonumber(size)
    if name ~= 'jls.lang.Buffer' or not sz then
      error('invalid reference '..reference)
    end
    return Buffer:new(sz, '.'..name..id, true)
  end

end)