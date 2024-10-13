local lu = require('luaunit')

local RingBuffer = require('jls.util.RingBuffer')
local Buffer = require('jls.lang.Buffer')
local serialization = require('jls.lang.serialization')

local function newRingBuffer(size)
  return RingBuffer:new(Buffer.allocate(size))
end

function Test_enqueue()
  local queue = newRingBuffer(64)
  queue:enqueue('a')
  lu.assertEquals(queue:dequeue(), 'a')
  queue:enqueue('b')
  queue:enqueue('c')
  lu.assertEquals(queue:dequeue(), 'b')
  lu.assertEquals(queue:dequeue(), 'c')
end

function Test_enqueue_ring()
  local nextSize = string.packsize('I4I4')
  local headerSize = string.packsize('I1I2')
  local queue = newRingBuffer(nextSize + 20 + headerSize * 3)
  local data10 = '1234567890'
  local data = '1234'
  lu.assertTrue(queue:enqueue(data))
  lu.assertTrue(queue:enqueue(data10))
  lu.assertFalse(queue:enqueue(data10))
  lu.assertEquals(queue:dequeue(), data)
  lu.assertTrue(queue:enqueue(data10))
  lu.assertEquals(queue:dequeue(), data10)
  lu.assertEquals(queue:dequeue(), data10)
end

function Test_enqueue_ring_multiple()
  local queue = newRingBuffer(64)
  local data = 'Hello !'
  queue:enqueue(data)
  for i = 1, 100 do
    queue:enqueue(data)
    lu.assertEquals(queue:dequeue(), data)
  end
  lu.assertEquals(queue:dequeue(), data)
end

function Test_serialization()
  local queue = newRingBuffer(64)
  queue:enqueue('a')
  local q = serialization.deserialize(serialization.serialize(queue))
  lu.assertEquals(q:dequeue(), 'a')
end

os.exit(lu.LuaUnit.run())
