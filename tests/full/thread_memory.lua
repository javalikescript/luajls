local lu = require('luaunit')

local Thread = require('jls.lang.Thread')
local Memory = require('jls.lang.Memory')
local system = require('jls.lang.system')
local loop = require('jls.lang.loopWithTimeout')

-- Indicate to a polling thread that it must terminate
function Test_thread_memory()
  local memory = Memory.allocate(1)
  memory:setBytes(1, 0)
  lu.assertEquals(memory:getBytes(), 0)
  local result = nil
  Thread:new(function(l)
    local Mem = require('jls.lang.Memory')
    local sys = require('jls.lang.system')
    local mem = Mem.fromPointer(l, 1)
    local n = 0
    while true do
      local v = mem:getBytes()
      n = n + 1
      if v ~= 0 then
        return n
      end
      sys.sleep(50)
    end
  end):start(memory:toPointer()):ended():next(function(res)
    result = res
  end)
  lu.assertNil(result)
  system.sleep(200)
  memory:setBytes(1, 1)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertNotNil(result)
  lu.assertTrue(result > 0)
end

os.exit(lu.LuaUnit.run())
