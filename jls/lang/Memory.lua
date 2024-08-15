local class = require('jls.lang.class')

local bufferLib = require('buffer')
assert(bufferLib._VERSION >= '0.3', 'bad buffer lib version '..tostring(bufferLib._VERSION))

return class.create(function(memory)

  function memory:initialize(buffer, size)
    if type(buffer) ~= 'userdata' then
      error('invalid buffer type '..type(buffer))
    end
    if size == nil then
      size = bufferLib.len(buffer)
    end
    if math.type(size) ~= 'integer' or size <= 0 then
      error('invalid size '..tostring(size))
    end
    self.buffer = buffer
    self.size = size
  end

  function memory:length()
    return self.size
  end

  function memory:get(from, to)
    return bufferLib.sub(self.buffer, from, to or self.size)
  end

  function memory:set(value, offset, from, to)
    offset = offset or 1
    from = from or 1
    to = to or #value
    assert(offset > 0 and from > 0 and to > 0 and to <= #value, 'invalid argument')
    local l = 1 + to - from
    assert(offset - 1 + l <= self.size, 'not enough space')
    if l > 0 then
      bufferLib.memcpy(self.buffer, value, offset, from, to)
    end
  end

  function memory:getBytes(from, to)
    return bufferLib.byte(self.buffer, from, to)
  end

  function memory:setBytes(at, ...)
    bufferLib.byteset(self.buffer, at, ...)
  end

  function memory:toPointer()
    return bufferLib.topointer(self.buffer), self.size
  end

  function memory:toString()
    return bufferLib.sub(self.buffer, 1, self.size)
  end

end, function(Memory)

  function Memory.allocate(size)
    return Memory:new(bufferLib.new(size))
  end

  function Memory.fromPointer(pointer, size)
    return Memory:new(bufferLib.frompointer(pointer), size)
  end

end)