local lu = require('luaunit')

local Thread = require('jls.lang.Thread')
local Buffer = require('jls.lang.Buffer')
local Lock = require('jls.lang.Lock')
local system = require('jls.lang.system')
local loop = require('jls.lang.loopWithTimeout')

-- Indicate to a polling thread that it must terminate
function Test_thread_buffer()
  local buffer = Buffer.allocate(1, 'global')
  buffer:setBytes(1, 0)
  lu.assertEquals(buffer:getBytes(), 0)
  local result = nil
  Thread:new(function(buf)
    local sys = require('jls.lang.system')
    local n = 0
    while true do
      local v = buf:getBytes()
      n = n + 1
      if v ~= 0 then
        return n
      end
      sys.sleep(50)
    end
  end):start(buffer):ended():next(function(res)
    result = res
  end)
  lu.assertNil(result)
  system.sleep(200)
  buffer:setBytes(1, 1)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertNotNil(result)
  lu.assertTrue(result > 0)
end

function Test_thread_lock()
  local lock = Lock:new()
  lock:lock()
  local result = nil
  Thread:new(function(lck)
    local sys = require('jls.lang.system')
    local tr = lck:tryLock()
    lck:lock()
    sys.sleep(200)
    lck:unlock()
    return string.format('tryLock=%s', tr)
  end):start(lock):ended():next(function(res)
    result = res
  end)
  lu.assertNil(result)
  local start = system.currentTimeMillis()
  system.sleep(200)
  lock:unlock()
  system.sleep(50)
  lock:lock()
  lock:unlock()
  local ms = system.currentTimeMillis() - start
  if not loop() then
    lu.fail('Timeout reached')
  end
  lock:finalize()
  lu.assertNotNil(result)
  lu.assertEquals(result, 'tryLock=false')
  lu.assertTrue(ms >= 400) -- may fail
end

os.exit(lu.LuaUnit.run())
