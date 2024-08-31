local class = require('jls.lang.class')

local bufferLib = require('buffer')
assert(bufferLib._VERSION >= '0.3', 'bad buffer lib version '..tostring(bufferLib._VERSION))

return class.create(function(buffer)

  function buffer:initialize(value, size)
    if type(value) ~= 'userdata' then
      error('invalid buffer type '..type(value))
    end
    if size == nil then
      size = bufferLib.len(value)
    end
    if math.type(size) ~= 'integer' or size <= 0 then
      error('invalid size '..tostring(size))
    end
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

  function buffer:toString()
    return bufferLib.sub(self.buffer, 1, self.size)
  end

end, function(Buffer)

  function Buffer.allocate(sizeOrData)
    return Buffer:new(bufferLib.new(sizeOrData))
  end

  function Buffer.fromReference(reference)
    return Buffer:new(bufferLib.fromreference(reference, nil, 'jls.lang.Buffer'))
  end

end)