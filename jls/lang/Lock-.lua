local class = require('jls.lang.class')

return class.create(function(lock)

  function lock:initialize()
    self.name = string.format('.%s-%p.tmp', 'jls.lang.Lock', self)
    self.file = io.open(self.name, 'w+')
    self.initialized = true
  end

  function lock:finalize()
    if self.initialized then
      self.initialized = false
      self.file:close()
      os.remove(self.name)
    end
  end

  function lock:lock()
    local b
    repeat
      self.file:seek('set')
      b = self.file:read(1)
      -- we may want to sleep in case of multiple failures
    until b ~= 'l'
    self.file:seek('set')
    self.file:write('l')
    self.file:flush()
  end

  function lock:unlock()
    self.file:seek('set')
    self.file:write(' ')
    self.file:flush()
  end

  function lock:tryLock()
    self.file:seek('set')
    local b = self.file:read(1)
    if b == 'l' then
      return false
    end
    self.file:seek('set')
    self.file:write('l')
    self.file:flush()
    return true
  end

  function lock:toReference()
    return self.name
  end

end, function(Lock)

  function Lock.fromReference(name)
    local lock = class.makeInstance(Lock)
    lock.name = name
    lock.file = io.open(name, 'r+')
    return lock
  end

end)