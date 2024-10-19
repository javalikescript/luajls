local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local system = require('jls.lang.system')

return class.create('jls.util.Queue', function(queue)

  function queue:initialize(q, timeout)
    self.queue = q
    self.timeout = timeout or 15000
  end

  function queue:enqueue(data)
    local endTime, delay
    while true do
      if self.queue:enqueue(data) then
        return true
      end
      local t = system.currentTimeMillis()
      if endTime == nil then
        endTime = t + self.timeout
        delay = 100
      end
      if t >= endTime then
        break
      end
      logger:finer('no space on queue, sleeping %d ms', delay)
      system.sleep(delay)
      if delay < 3000 then
        delay = delay * 2
      end
    end
    return false
  end

  function queue:dequeue()
    return self.queue:dequeue()
  end

  function queue:serialize(write)
    write(self.queue)
    write(self.timeout)
  end

  function queue:deserialize(read)
    self.queue = read('jls.util.Queue')
    self.timeout = read('number')
  end

end)
