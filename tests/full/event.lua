local lu = require('luaunit')

local event = require('jls.lang.event')

function Test_setTimeout()
  local called = false
  event:setTimeout(function()
    called = true
  end, 100)
  event:loop()
  lu.assertEquals(called, true)
end

function Test_setTimeout_order()
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

function Test_setTimeout_no_delay()
  local value = 1
  event:setTimeout(function()
    value = value * 2
  end, 300)
  event:setTimeout(function()
    value = value + 1
  end)
  event:setTimeout(function()
    value = value + 1
  end)
  event:loop()
  lu.assertEquals(value, 6)
end

function Test_setInterval()
  local count = 0
  local eventId = event:setInterval(function()
    count = count + 1
  end, 100)
  event:setTimeout(function()
    event:clearInterval(eventId)
  end, 500)
  event:loop()
  -- this test will fail on pure Lua depending on time resolution
  lu.assertAlmostEquals(count, 5, 2)
end

function Test_setTask()
  if event ~= package.loaded['jls.lang.event-'] then
    print('/!\\ skipping setTask test')
    lu.success()
  end
  local count = 0
  event:setTask(function()
    count = count + 1
    if count >= 4 then
      return false
    end
    return true
  end, 100)
  event:loop()
  lu.assertEquals(count, 4)
end

os.exit(lu.LuaUnit.run())
