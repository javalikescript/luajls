local class = require('jls.lang.class')
local system = require('jls.lang.system')

local function read(file, offset)
  file:seek('set', offset)
  local s = file:read(1)
  if s then
    return (string.byte(s))
  end
  return 0
end

local function write(file, offset, value)
  file:seek('set', offset)
  file:write(string.char(value))
  file:flush()
end

local MAX_ID = 2

local function getId(self)
  return self.initialized and 0 or 1
end

local function softUnlock(file, id)
  write(file, MAX_ID + id, 0)
end

-- From Lamport's bakery algorithm
local function softLock(file, id, try)
  local max = 0
  write(file, id, 1)
  for j = MAX_ID, MAX_ID * 2 - 1 do
    max = math.max(max, read(file, j))
  end
  local tic = 1 + max;
  write(file, MAX_ID + id, tic)
  write(file, id, 0)
  --print(string.format("mutex_soft_init(%s, %s) max: %d", id, try, max));
  if try and max ~= 0 then
    softUnlock(file, id)
    return false
  end
  for i = 0, MAX_ID - 1 do
    if i ~= id then
      while read(file, i) == 1 do
        system.sleep(0)
      end
      local j = MAX_ID + i
      while true do
        local cur = read(file, j)
        if cur ~= 0 and (cur < tic or (cur == tic and i < id)) then
          system.sleep(0)
        else
          break
        end
      end
    end
  end
  return true
end

return class.create(function(lock)

  function lock:initialize()
    self.name = string.format('.%s-%p.tmp', 'jls.lang.Lock', self)
    self.file = io.open(self.name, 'w+')
    self.initialized = true
    self.file:write(string.rep('\0', MAX_ID * 2))
    self.file:flush()
  end

  function lock:finalize()
    if self.initialized then
      self.initialized = false
      self.file:close()
      os.remove(self.name)
    end
  end

  function lock:lock()
    softLock(self.file, getId(self), false)
  end

  function lock:unlock()
    softUnlock(self.file, getId(self))
  end

  function lock:tryLock()
    return softLock(self.file, getId(self), true)
  end

  function lock:serialize(w)
    w(self.name)
  end

  function lock:deserialize(r)
    self.name = r('string')
    self.file = io.open(self.name, 'r+')
  end

end)