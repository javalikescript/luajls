local lu = require('luaunit')

local class = require('jls.lang.class')
local Queue = require('jls.util.Queue')
local Buffer = require('jls.lang.Buffer')
local serialization = require('jls.lang.serialization')

local ListQueue = class.create('jls.util.Queue', function(queue)
  function queue:initialize()
    self.list = {}
  end
  function queue:enqueue(data)
    table.insert(self.list, data)
    return true
  end
  function queue:dequeue()
    return table.remove(self.list, 1)
  end
  function queue:serialize(write)
    write(self.list)
  end
  function queue:deserialize(read)
    self.list = read('table')
  end
end)

function Test_abstract()
  local queue = Queue:new()
  lu.assertFalse(pcall(queue.enqueue, queue, 'data'))
  lu.assertFalse(pcall(queue.dequeue, queue))
end

function Test_enqueue_dequeue()
  local queue = ListQueue:new()
  lu.assertTrue(queue:enqueue('a'))
  lu.assertTrue(queue:enqueue('b'))
  lu.assertEquals(queue:dequeue(), 'a')
  lu.assertEquals(queue:dequeue(), 'b')
  lu.assertIsNil(queue:dequeue())
end

function Test_share()
  local ShareableQueue = require('jls.util.ShareableQueue')
  local queue = ListQueue:new()
  local shared = Queue.share(queue)
  lu.assertTrue(ShareableQueue:isInstance(shared))
  lu.assertTrue(shared:enqueue('a'))
  lu.assertEquals(shared:dequeue(), 'a')
  lu.assertIs(Queue.share(shared), shared)
end

function Test_share_error()
  local queue = ListQueue:new()
  local shared = Queue.share(queue)
  queue.enqueue = function()
    error('enqueue error')
  end
  lu.assertFalse(pcall(shared.enqueue, shared, 'a'))
  queue.dequeue = function()
    error('dequeue error')
  end
  lu.assertFalse(pcall(shared.dequeue, shared))
end

function Test_block()
  local BlockingQueue = require('jls.util.BlockingQueue')
  local queue = ListQueue:new()
  local blocking = Queue.block(queue, 1000)
  lu.assertTrue(BlockingQueue:isInstance(blocking))
  lu.assertTrue(blocking:enqueue('a'))
  lu.assertEquals(blocking:dequeue(), 'a')
end

function Test_block_timeout()
  local full = {
    enqueue = function()
      return false
    end,
    dequeue = function()
      return nil
    end
  }
  local blocking = Queue.block(full, 0)
  lu.assertFalse(blocking:enqueue('a'))
end

function Test_ringBuffer()
  local RingBuffer = require('jls.util.RingBuffer')
  local ringBuffer = Queue.ringBuffer(Buffer.allocate(64))
  lu.assertTrue(RingBuffer:isInstance(ringBuffer))
  lu.assertTrue(ringBuffer:enqueue('Hello'))
  lu.assertEquals(ringBuffer:dequeue(), 'Hello')
  lu.assertIsNil(ringBuffer:dequeue())
end

package.loaded['tests.Queue.ListQueue'] = ListQueue

function Test_block_serialization()
  local blocking = Queue.block(ListQueue:new(), 123)
  blocking:enqueue('a')
  blocking:enqueue('b')
  local result = serialization.deserialize(serialization.serialize(blocking))
  lu.assertEquals(result.timeout, 123)
  lu.assertEquals(result:dequeue(), 'a')
  lu.assertEquals(result:dequeue(), 'b')
end

function Test_share_serialization()
  local shared = Queue.share(ListQueue:new())
  shared:enqueue('x')
  local result = serialization.deserialize(serialization.serialize(shared))
  lu.assertEquals(result:dequeue(), 'x')
  lu.assertIsNil(result:dequeue())
end

os.exit(lu.LuaUnit.run())
