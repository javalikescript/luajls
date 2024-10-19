local class = require('jls.lang.class')

return class.create('jls.lang.Buffer', function(buffer)

  function buffer:initialize(value, from, to)
    self.buffer = value
    self.offset = (from or 1) - 1
    self.size = (to or value:length()) - self.offset
  end

  function buffer:length()
    return self.size
  end

  function buffer:get(from, to)
    return self.buffer:get(self.offset + (from or 1), self.offset + (to or self.size))
  end

  function buffer:set(value, offset, from, to)
    self.buffer:set(value, self.offset + (offset or 1), from, to)
  end

  function buffer:getBytes(from, to)
    return self.buffer:getBytes(self.offset + (from or 1), self.offset + (to or from or 1))
  end

  function buffer:setBytes(at, ...)
    self.buffer:setBytes(self.offset + (at or 1), ...)
  end

  function buffer:serialize(write)
    write(self.buffer)
    write(self.offset)
    write(self.size)
  end

  function buffer:deserialize(read)
    self.buffer = read('jls.lang.Buffer')
    self.offset = read('number')
    self.size = read('number')
  end

end)
