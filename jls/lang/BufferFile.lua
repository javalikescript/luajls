local class = require('jls.lang.class')

return class.create('jls.lang.Buffer', function(buffer)

  function buffer:initialize(size, name, preserve)
    self.size = size
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
      return string.sub(s, from, to or #s)
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

  function buffer:serialize(write)
    write(self.size)
    write(self.name)
  end

  function buffer:deserialize(read)
    local size, name = read('number'), read('string')
    assert(string.match(name, '^%.[%w%.]+-%x+%.tmp$'), 'invalid name')
    self:initialize(size, name, true)
  end

end, function(Buffer)

  function Buffer.allocate(size)
    return Buffer:new(size)
  end

end)