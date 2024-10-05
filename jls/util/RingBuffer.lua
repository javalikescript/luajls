--- Represents a circular buffer maintaining a queue of data.
-- @module jls.lang.Buffer
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Buffer = require('jls.lang.Buffer')
local Lock = require('jls.lang.Lock')

--- The RingBuffer class.
-- @type RingBuffer
return class.create(function(ringBuffer)

  local NEXT_FORMAT = 'I4I4'
  local NEXT_SIZE = string.packsize(NEXT_FORMAT)
  local HEADER_FORMAT = 'BI3'
  local HEADER_SIZE = string.packsize(HEADER_FORMAT)

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
    local first, next = string.unpack(NEXT_FORMAT, self.buffer:get(1, NEXT_SIZE))
    --logger:finer('getFirstNext() => %d, %d', first, next)
    return first, next
  end

  local function setFirstNext(self, first, next)
    --logger:finer('setFirstNext(%d, %d)', first, next)
    self.buffer:set(string.pack(NEXT_FORMAT, first, next), 1)
  end

  --- Creates a new RingBuffer.
  -- @param The buffer size
  -- @function RingBuffer:new
  function ringBuffer:initialize(size)
    if type(size) == 'number' then
      self.buffer = Buffer.allocate(size or 1024, 'global')
    elseif Buffer:isInstance(size) then
      assert(size > NEXT_SIZE + HEADER_SIZE)
      self.buffer = size
    else
      error('invalid argument')
    end
    setFirstNext(self, NEXT_SIZE + 1, NEXT_SIZE + 1)
  end

  --- Adds the specified data to the queue.
  -- @tparam string data The start data to add
  -- @tparam[opt] number id An optional byte, defaults to 0
  -- @treturn boolean true if the data has been added
  function ringBuffer:enqueue(data, id)
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
    local header = string.pack(HEADER_FORMAT, id or 0, size)
    next = set(self.buffer, length, next, header, HEADER_SIZE)
    next = set(self.buffer, length, next, data, size)
    setFirstNext(self, first, next)
    return true
  end

  --- Removes and returns the first data of the queue.
  -- @treturn string The first data or nil if there is nothing in the queue
  -- @treturn number The optional byte associated to the data
  function ringBuffer:dequeue()
    local length = self.buffer:length()
    local data, id, size
    local first, next = getFirstNext(self)
    if first ~= next then
      data, first = get(self.buffer, length, first, HEADER_SIZE)
      id, size = string.unpack(HEADER_FORMAT, data)
      assert(size < length, 'corrupted size')
      data, first = get(self.buffer, length, first, size)
      setFirstNext(self, first, next)
    end
    return data, id
  end

  function ringBuffer:toReference()
    return self.buffer:toReference()
  end

end, function(RingBuffer)

  local SyncRingBuffer = class.create(RingBuffer, function(ringBuffer, super)

    function ringBuffer:initialize(size)
      super.initialize(self, size)
      self.lock = Lock:new()
    end

    function ringBuffer:enqueue(data, id)
      local lock = self.lock
      lock:lock()
      local status, result = pcall(super.enqueue, self, data, id)
      lock:unlock()
      if status then
        return result
      end
      error(result)
    end

    function ringBuffer:dequeue()
      local lock = self.lock
      lock:lock()
      local status, data, id = pcall(super.dequeue, self)
      lock:unlock()
      if status then
        return data, id
      end
      error(data)
    end

    function ringBuffer:toReference()
      return string.pack('xs2s2', self.buffer:toReference(), self.lock:toReference())
    end

  end)

  function SyncRingBuffer.fromReference(reference)
    local bufferRef, lockRef = string.unpack('xs2s2', reference)
    local bufferQueue = class.makeInstance(SyncRingBuffer)
    bufferQueue.buffer = Buffer.fromReference(bufferRef)
    bufferQueue.lock = Lock.fromReference(lockRef)
    logger:finer('fromReference(%s) => %s, %s', reference, bufferQueue.buffer, bufferQueue.lock)
    return bufferQueue
  end

  --- A synchronized ring buffer class.
  RingBuffer.SyncRingBuffer = SyncRingBuffer

  --- Returns the ring buffer represented by the specified reference.
  -- @tparam string reference the reference
  -- @return The referenced buffer
  function RingBuffer.fromReference(reference)
    local bufferQueue = class.makeInstance(RingBuffer)
    bufferQueue.buffer = Buffer.fromReference(reference)
    logger:finer('fromReference(%s) => %s', reference, bufferQueue.buffer)
    return bufferQueue
  end

end)
