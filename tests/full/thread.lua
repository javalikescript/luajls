local lu = require('luaunit')

local Thread = require('jls.lang.Thread')
local loop = require('jls.lang.loader').load('loop', 'tests', false, true)

-- (export JLS_REQUIRES=\!luv; lua tests/full/thread.lua)
--for name, mod in pairs(package.loaded) do if mod == Thread and name ~= 'jls.lang.Thread' then print('Thread library is '..name) end end

local function onThreadError(reason)
  print('Unexpected error: '..tostring(reason))
end

function Test_one_arg_one_result()
  local result = nil
  Thread:new(function(value)
    return 'Hi '..tostring(value)
  end):start('John'):ended():next(function(res)
    result = res
  end, onThreadError)
  lu.assertNil(result)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(result, 'Hi John')
end

function Test_two_args_table_result()
  local result = nil
  Thread:new(function(a, b)
    local sum = a + b
    sum = math.floor(sum) -- integer vs number issue
    return {sum, 'Sum is '..tostring(sum)}
  end):start(1, 2):ended():next(function(res)
    result = res
  end, onThreadError)
  lu.assertNil(result)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(result, {3, 'Sum is 3'})
end

function Test_sleep()
  local called = false
  Thread:new(function()
    local system = require('jls.lang.system')
    system.sleep(100)
  end):start():ended():next(function()
    called = true
  end, onThreadError)
  lu.assertFalse(called)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertTrue(called)
end

os.exit(lu.LuaUnit.run())
