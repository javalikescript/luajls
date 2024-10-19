local class = require('jls.lang.class')
local Lock = require('jls.lang.Lock')

return class.create('jls.util.Queue', function(queue)

  function queue:initialize(q)
    self.queue = q
    self.lock = Lock:new()
  end

  function queue:enqueue(data, id)
    local q, lock = self.queue, self.lock
    lock:lock()
    local status, result = pcall(q.enqueue, q, data, id)
    lock:unlock()
    if status then
      return result
    end
    error(result)
  end

  function queue:dequeue()
    local q, lock = self.queue, self.lock
    lock:lock()
    local status, data, id = pcall(q.dequeue, q)
    lock:unlock()
    if status then
      return data, id
    end
    error(data)
  end

  function queue:serialize(write)
    write(self.queue)
    write(self.lock)
  end

  function queue:deserialize(read)
    self.queue = read('jls.util.Queue')
    self.lock = read('jls.lang.Lock')
  end

end)
