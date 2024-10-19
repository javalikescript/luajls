local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)

return class.create('jls.util.Queue', function(ringBuffer)

  local NEXT_SIZE = string.packsize('I4I4')
  local HEADER_SIZE = string.packsize('I3')

  local function get(buffer, length, pos, size)
    local to = pos + size - 1
    local cut = to - length
    if cut > 0 then
      local first = NEXT_SIZE + 1 + cut
      local a = buffer:get(pos, length)
      local b = buffer:get(NEXT_SIZE + 1, first - 1)
      --logger:finer('get(%d, %d) cut=%d => "%s"-"%s" %d', pos, size, cut, a, b, first)
      return a..b, first
    end
    local data = buffer:get(pos, to)
    if cut == 0 then
      return data, NEXT_SIZE + 1
    end
    return data, pos + size
  end

  local function set(buffer, length, pos, data, size)
    local cut = length - pos + 1
    if size > cut then
      local a, b = string.sub(data, 1, cut), string.sub(data, cut + 1)
      local next = NEXT_SIZE + 1 + size - cut
      --logger:finer('set(%d "%s", %d) cut=%d => "%s""%s" %d', pos, data, size, cut, a, b, next)
      buffer:set(a, pos)
      buffer:set(b, NEXT_SIZE + 1)
      return next
    end
    buffer:set(data, pos)
    if size == cut then
      return NEXT_SIZE + 1
    end
    return pos + size
  end

  local function getFirstNext(self)
    local first, next = string.unpack('I4I4', self.buffer:get(1, NEXT_SIZE))
    --logger:finer('getFirstNext() => %d, %d', first, next)
    return first, next
  end

  local function setFirstNext(self, first, next)
    --logger:finer('setFirstNext(%d, %d)', first, next)
    self.buffer:set(string.pack('I4I4', first, next), 1)
  end

  function ringBuffer:initialize(buffer)
    self.buffer = buffer
    setFirstNext(self, NEXT_SIZE + 1, NEXT_SIZE + 1)
  end

  function ringBuffer:enqueue(data)
    assert(type(data) == 'string', 'invalid data type')
    local length = self.buffer:length()
    local size = #data
    local first, next = getFirstNext(self)
    local remaining
    if first > next then
      remaining = first - next
    else
      remaining = length - next + first - 1 - NEXT_SIZE
    end
    if HEADER_SIZE + size > remaining then
      assert(NEXT_SIZE + HEADER_SIZE + size < length, 'data too large')
      return false
    end
    local header = string.pack('I3', size)
    next = set(self.buffer, length, next, header, HEADER_SIZE)
    next = set(self.buffer, length, next, data, size)
    setFirstNext(self, first, next)
    return true
  end

  function ringBuffer:dequeue()
    local length = self.buffer:length()
    local data, size
    local first, next = getFirstNext(self)
    if first ~= next then
      data, first = get(self.buffer, length, first, HEADER_SIZE)
      size = string.unpack('I3', data)
      assert(size < length, 'corrupted size')
      data, first = get(self.buffer, length, first, size)
      setFirstNext(self, first, next)
    end
    return data
  end

  function ringBuffer:serialize(write)
    write(self.buffer)
  end

  function ringBuffer:deserialize(read)
    self.buffer = read('jls.lang.Buffer')
  end

end)
