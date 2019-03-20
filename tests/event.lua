local lu = require('luaunit')

local event = require('jls.lang.event')

function loop(sec)
  local endTime = os.time() + sec
  while event:loopAlive() and os.time() < endTime do
    event:runOnce()
  end
end

function test_setTimeout()
  local called = false
  event:setTimeout(function()
    called = true
  end, 100)
  event:loop()
  lu.assertEquals(called, true)
end

function test_setTimeout_order()
  local value = 1
  event:setTimeout(function()
    value = value * 2
  end, 300)
  event:setTimeout(function()
    value = value + 1
  end, 100)
  event:loop()
  lu.assertEquals(value, 4)
end

function test_setInterval()
  local count = 0
  local eventId = event:setInterval(function()
    count = count + 1
  end, 100)
  event:setTimeout(function()
    event:clearInterval(eventId)
  end, 500)
  event:loop()
  lu.assertAlmostEquals(count, 5, 2)
end

os.exit(lu.LuaUnit.run())
