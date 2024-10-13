--- Represents a list of data in first-in first-out order.
-- @module jls.util.Queue
-- @pragma nostrip

local class = require('jls.lang.class')

--- The Queue class.
-- @type Queue
return class.create(function(queue)

  --- Adds the specified data to the queue.
  -- @tparam string data The data to add at the end of the queue
  -- @treturn boolean true if the data has been added
  -- @function queue:enqueue
  queue.enqueue = class.notImplementedFunction

  --- Removes and returns the first data of the queue.
  -- @treturn string The first data or nil if there is nothing in the queue
  -- @function queue:dequeue
  queue.dequeue = class.notImplementedFunction

end, function(Queue)

  --- Returns a queue that is thread safe.
  -- @tparam jls.util.Queue queue The queue
  -- @treturn jls.util.Queue the thread safe queue
  function Queue.share(queue)
    local ShareableQueue = require('jls.util.ShareableQueue')
    if ShareableQueue:isInstance(queue) then
      return queue
    end
    return ShareableQueue:new(queue)
  end

  --- Returns a queue that blocks while data could be queued.
  -- @tparam jls.util.Queue queue The queue
  -- @tparam number timeout The max duration in milliseconds to wait for enqueue
  -- @treturn jls.util.Queue the blocking queue
  function Queue.block(queue, timeout)
    return require('jls.util.BlockingQueue'):new(queue, timeout)
  end

  --- Returns a queue using a circular buffer.
  -- @tparam jls.lang.Buffer buffer The buffer
  -- @treturn jls.util.Queue the ring buffer
  function Queue.ringBuffer(buffer)
    return require('jls.util.RingBuffer'):new(buffer)
  end

end)
