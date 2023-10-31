local lu = require('luaunit')

local Thread = require('jls.lang.Thread')
local Exception = require('jls.lang.Exception')
local loop = require('jls.lang.loopWithTimeout')

--[[
JLS_LOGGER_LEVEL=finest JLS_REQUIRES=\!luv lua tests/full/thread.lua Test_one_arg_one_result
(export JLS_REQUIRES=\!luv; lua tests/full/thread.lua)
for name, mod in pairs(package.loaded) do if mod == Thread and name ~= 'jls.lang.Thread' then print('Thread library is '..name) end end
]]

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
  local result = nil
  Thread:new(function()
    local system = require('jls.lang.system')
    system.sleep(100)
  end):start():ended():next(function(res)
    result = res
    called = true
  end, onThreadError)
  lu.assertFalse(called)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertTrue(called)
  lu.assertNil(result)
end

function Test_promise()
  local result = nil
  Thread:new(function(value)
    local event = require('jls.lang.event')
    local Promise = require('jls.lang.Promise')
    return Promise:new(function(resolve)
      event:setTimeout(resolve, 100, value)
    end)
  end):start('after'):ended():next(function(res)
    result = res
  end, onThreadError)
  lu.assertNil(result)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(result, 'after')
end

function Test_failure()
  local result = nil
  Thread:new(function(value)
    return nil, 'Ouch '..tostring(value)
  end):start('John'):ended():next(onThreadError, function(res)
    result = res
  end)
  lu.assertNil(result)
  if not loop() then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(result, 'Ouch John')
end

function Test_error()
  local result = nil
  Thread:new(function(value)
    error('Ouch '..tostring(value))
  end):start('John'):ended():next(onThreadError, function(res)
    result = res
  end)
  lu.assertNil(result)
  if not loop() then
    lu.fail('Timeout reached')
  end
  --print(result)
  lu.assertEquals(Exception.getMessage(result), 'Ouch John')
end

function Test_preload()
  local moduleName = 'test__'
  package.preload[moduleName] = function()
    return {
      value = 'test'
    }
  end
  local result = nil
  local t = Thread:new(function(name)
    return require(name).value
  end):setTransferPreload(true):start(moduleName):ended():next(function(res)
    result = res
  end, onThreadError)
  lu.assertNil(result)
  if not loop() then
    lu.fail('Timeout reached')
  end
  package.preload[moduleName] = nil
  --print(result)
  lu.assertEquals(result, 'test')
end

os.exit(lu.LuaUnit.run())
