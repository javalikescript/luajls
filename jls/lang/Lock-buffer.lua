local class = require('jls.lang.class')

local bufferLib = require('buffer')

return class.create(function(lock)

  function lock:initialize()
    self.mutex = bufferLib.newmutex()
    bufferLib.initmutex(self.mutex)
    self.initialized = true
  end

  function lock:finalize()
    -- type(self.mutex) == 'userdata' and bufferLib.len(self.mutex) == bufferLib.MUTEX_SIZE
    if self.initialized then
      self.initialized = false
      bufferLib.destroymutex(self.mutex)
    end
  end

  function lock:lock()
    bufferLib.lock(self.mutex)
  end

  function lock:unlock()
    bufferLib.unlock(self.mutex)
  end

  function lock:tryLock()
    return bufferLib.trylock(self.mutex)
  end

  function lock:toReference()
    return bufferLib.toreference(self.mutex, nil, 'jls.lang.Lock')
  end

end, function(Lock)

  function Lock.fromReference(reference)
    local m = bufferLib.fromreference(reference, nil, 'jls.lang.Lock')
    if type(m) ~= 'userdata' then
      error('invalid reference type '..type(reference))
    end
    local lock = class.makeInstance(Lock)
    lock.mutex = m
    return lock
  end

end)