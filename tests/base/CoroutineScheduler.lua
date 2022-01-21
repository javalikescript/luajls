local lu = require('luaunit')

local CoroutineScheduler = require("jls.util.CoroutineScheduler")

function Test_schedule()
    local v = 0
    local scheduler = CoroutineScheduler:new()
    scheduler:schedule(function ()
      for i = 1, 3 do
        v = v + 1
        coroutine.yield(-1)
      end
    end, false)
    scheduler:run()
    lu.assertEquals(v, 3)
end

function Test_schedule_daemon()
    local v = 0
    local vd = 0
    local scheduler = CoroutineScheduler:new()
    scheduler:schedule(function ()
      for i = 1, 3 do
        v = v + 1
        coroutine.yield(-1)
      end
    end, false)
    scheduler:schedule(function ()
      while true do
        vd = vd + 1
        coroutine.yield(-1)
      end
    end, true)
    scheduler:run()
    lu.assertEquals(v, 3)
    lu.assertEquals(vd, 4)
    scheduler:run()
    lu.assertEquals(v, 3)
    lu.assertEquals(vd, 5)
end

os.exit(lu.LuaUnit.run())
