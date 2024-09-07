local class = require('jls.lang.class')

local bufferLib = require('buffer')
assert(type(bufferLib.toreference) == 'function', 'bad buffer lib version '..tostring(bufferLib._VERSION))

return class.create('jls.lang.Buffer', function(buffer)

  function buffer:initialize(value, size)
    self.buffer = value
    self.size = size
  end

  function buffer:length()
    return self.size
  end

  function buffer:get(from, to)
    return bufferLib.sub(self.buffer, from, to or self.size)
  end

  function buffer:set(value, offset, from, to)
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

  function buffer:getBytes(from, to)
    return bufferLib.byte(self.buffer, from, to)
  end

  function buffer:setBytes(at, ...)
    bufferLib.byteset(self.buffer, at, ...)
  end

  function buffer:toReference()
    return bufferLib.toreference(self.buffer, nil, 'jls.lang.Buffer')
  end

end, function(Buffer)

  function Buffer.allocate(size)
    return Buffer:new(bufferLib.new(size), size)
  end

  function Buffer.fromReference(reference)
    local buffer, size = bufferLib.fromreference(reference, nil, 'jls.lang.Buffer')
    return Buffer:new(buffer, size)
  end

end)