local lu = require('luaunit')

local event = require('jls.lang.event')
local system = require('jls.lang.system')
local Thread = require('jls.lang.Thread')

function test_one_arg_one_result()
  local result = nil
  Thread:new(function(value)
    return 'Hi '..tostring(value)
  end):start('John'):ended():next(function(res)
    result = res
  end)
  lu.assertNil(result)
  event:loop()
  lu.assertEquals(result, 'Hi John')
end

function test_two_args_two_results()
  local c, d
  Thread:new(function(a, b)
    local sum = a + b
    sum = math.floor(sum) -- integer vs number issue
    return sum, 'Sum is '..tostring(sum)
  end):start(1, 2):ended():next(function(res)
    c, d = table.unpack(res)
  end)
  lu.assertNil(c)
  event:loop()
  lu.assertEquals(c, 3)
  lu.assertEquals(d, 'Sum is 3')
end

function test_sleep()
  local called = false
  Thread:new(function()
    local system = require('jls.lang.system')
    system.sleep(100)
  end):start():ended():next(function()
    called = true
  end)
  lu.assertFalse(called)
  event:loop()
  lu.assertTrue(called)
end

os.exit(lu.LuaUnit.run())
