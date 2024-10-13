--- Provides mutual exclusion for the threads in the current process.
-- @module jls.lang.Lock
-- @pragma nostrip

local class = require('jls.lang.class')

local bufferLib = require('buffer')
assert(type(bufferLib.initmutex) == 'function', 'bad buffer lib version '..tostring(bufferLib._VERSION))

--- The Lock class.
-- @type Lock
return class.create(function(lock)

  --- Creates a new Lock.
  -- @function Lock:new
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

  --- Acquires the lock, blocking if necessary.
  function lock:lock()
    bufferLib.lock(self.mutex)
  end

  --- Releases the lock.
  function lock:unlock()
    bufferLib.unlock(self.mutex)
  end

  --- Returns true if the lock has been acquired without blocking.
  -- @treturn boolean true if the lock has been acquired
  function lock:tryLock()
    return bufferLib.trylock(self.mutex)
  end

  function lock:serialize()
    return bufferLib.toreference(self.mutex, nil, 'jls.lang.Lock')
  end

  function lock:deserialize(s)
    local m = bufferLib.fromreference(s, nil, 'jls.lang.Lock')
    if type(m) ~= 'userdata' then
      error('invalid serialization value')
    end
    self.mutex = m
  end

end)