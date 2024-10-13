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
  local module2Name = 'test2__'
  package.preload[moduleName] = function()
    return {
      value = 'test'
    }
  end
  package.preload[module2Name] = function()
    return {
      value = 'test 2'
    }
  end
  local result = nil
  local t = Thread:new(function(name, name2)
    return require(name).value..'+'..require(name2).value
  end):setTransferPreload(true):start(moduleName, module2Name):ended():next(function(res)
    result = res
  end, onThreadError)
  package.preload[moduleName] = nil
  package.preload[module2Name] = nil
  lu.assertNil(result)
  if not loop() then
    lu.fail('Timeout reached')
  end
  --print(result)
  lu.assertEquals(result, 'test+test 2')
end

function Test_resolveUpValues()
  local a, b = 'Hi', 3
  local fn = function(value)
    --print('fn', a, b, value)
    return a, b, value
  end
  local rfn = Thread.resolveUpValues(fn)
  lu.assertEquals({fn(12)}, {'Hi', 3, 12})
  lu.assertEquals({rfn(12)}, {'Hi', 3, 12})
  a, b = 'Oh', 34
  lu.assertEquals({fn(12)}, {'Oh', 34, 12})
  lu.assertEquals({rfn(12)}, {'Hi', 3, 12})
end

function Test_resolveUpValues_with_env()
  local a, b = 'Hi', 3
  local fn = function(value)
    return a, b, math.type(value)
  end
  local rfn = Thread.resolveUpValues(fn)
  a, b = 'Oh', 34
  lu.assertEquals({rfn(12)}, {'Hi', 3, 'integer'})
end

function Test_resolveUpValues_with_require()
  local fn = function()
    return type(Thread)
  end
  local rfn = Thread.resolveUpValues(fn)
  local m = Thread
  lu.assertEquals(fn(), 'table')
  Thread = nil
  lu.assertEquals(fn(), 'nil')
  lu.assertEquals(rfn(), 'table')
  Thread = m
end

function Test_resolveUpValues_identity()
  local fn = function()
    return 1 + 2
  end
  local rfn = Thread.resolveUpValues(fn)
  lu.assertEquals(rfn, fn)

  fn = function()
    return print('Hello')
  end
  rfn = Thread.resolveUpValues(fn)
  lu.assertEquals(rfn, fn)
end

function Test_thread_resolveUpValues()
  local result = nil
  local value = 'Hello !'
  local t = Thread:new(Thread.resolveUpValues(function()
    return tostring(value)..'-'..type(Thread)
  end))
  value = ''
  t:start():ended():next(function(res)
    result = res
  end, onThreadError)
  lu.assertNil(result)
  if not loop() then
    lu.fail('Timeout reached')
  end
  --print(result)
  lu.assertEquals(result, 'Hello !-table')
end

os.exit(lu.LuaUnit.run())
