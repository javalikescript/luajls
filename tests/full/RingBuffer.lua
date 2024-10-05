local lu = require('luaunit')

local RingBuffer = require('jls.util.RingBuffer')

function Test_enqueue()
  local queue = RingBuffer:new(64)
  queue:enqueue('a')
  lu.assertEquals(queue:dequeue(), 'a')
  queue:enqueue('b')
  queue:enqueue('c')
  lu.assertEquals(queue:dequeue(), 'b')
  lu.assertEquals(queue:dequeue(), 'c')
end

function Test_enqueue_id()
  local queue = RingBuffer:new(64)
  queue:enqueue('a', 123)
  lu.assertEquals({queue:dequeue()}, {'a', 123})
  queue:enqueue('b')
  queue:enqueue('c', 234)
  lu.assertEquals({queue:dequeue()}, {'b', 0})
  lu.assertEquals({queue:dequeue()}, {'c', 234})
end

function Test_enqueue_ring()
  local nextSize = string.packsize('I4I4')
  local headerSize = string.packsize('I1I2')
  local queue = RingBuffer:new(nextSize + 20 + headerSize * 3)
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
  local queue = RingBuffer:new(64)
  local data = 'Hello !'
  queue:enqueue(data)
  for i = 1, 100 do
    queue:enqueue(data)
    lu.assertEquals(queue:dequeue(), data)
  end
  lu.assertEquals(queue:dequeue(), data)
end

function Test_reference()
  local queue = RingBuffer:new(64)
  queue:enqueue('a')
  local ref = queue:toReference()
  local q = RingBuffer.fromReference(ref)
  lu.assertEquals(q:dequeue(), 'a')
end

os.exit(lu.LuaUnit.run())
