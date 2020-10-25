local lu = require('luaunit')

local logger = require('jls.lang.logger')
logger:setLevel(logger.LEVEL.FINEST)

local Promise = require('jls.lang.Promise')

local function createFunction(f)
  local calls = {}
  return calls, function(...)
    table.insert(calls, {...})
    if f and type(f) == 'function' then
      return f(...)
    end
  end
end

local function deferPromise()
  local deferred = {}
  local promise = Promise:new(function(resolve, reject)
    deferred.resolve = resolve
    deferred.reject = reject
  end)
  return deferred, promise
end

local function assertNoResolution(onFulfilledCalls, onRejectedCalls)
  lu.assertEquals(#onFulfilledCalls, 0)
  lu.assertEquals(#onRejectedCalls, 0)
end

local function assertThenResolution(onFulfilledCalls, onRejectedCalls, value, rejected)
  if rejected then
    lu.assertEquals(#onFulfilledCalls, 0)
    lu.assertEquals(#onRejectedCalls, 1)
    if type(value) ~= 'nil' then
      lu.assertEquals(#onRejectedCalls[1], 1)
      lu.assertEquals(onRejectedCalls[1][1], value)
    else
      lu.assertEquals(#onRejectedCalls[1], 0)
    end
  else
    lu.assertEquals(#onFulfilledCalls, 1)
    lu.assertEquals(#onRejectedCalls, 0)
    if type(value) ~= 'nil' then
      lu.assertEquals(#onFulfilledCalls[1], 1)
      lu.assertEquals(onFulfilledCalls[1][1], value)
    else
      lu.assertEquals(#onFulfilledCalls[1], 0)
    end
  end
end

local function nextPromise(promise, ff, rf)
  local onFulfilledCalls, onFulfilled = createFunction(ff)
  local onRejectedCalls, onRejected = createFunction(rf)
  return onFulfilledCalls, onRejectedCalls, promise:next(onFulfilled, onRejected)
end

local function catchPromise(promise, f)
  local onRejectedCalls, onRejected = createFunction(f)
  return onRejectedCalls, promise:next(nil, onRejected)
end

local function donePromise(promise, f)
  local onFulfilledCalls, onFulfilled = createFunction(f)
  return onFulfilledCalls, promise:next(onFulfilled)
end


function Test_executor()
  local resultValue, resultReason
  local deferred, promise = deferPromise()
  lu.assertEquals(type(deferred.resolve), 'function')
  lu.assertEquals(type(deferred.reject), 'function')
end

function Test_resolve()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.resolve(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function Test_resolve_multi_values()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.resolve(result, 'another result')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function Test_resolve_nil()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  deferred.resolve()
  assertThenResolution(onFulfilledCalls, onRejectedCalls, nil)
end

function Test_resolve_resolve()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.resolve(result)
  deferred.resolve('another result')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function Test_resolve_reject()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.resolve(result)
  deferred.reject('an error')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function Test_reject()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.reject(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result, true)
end

function Test_reject_nil()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.reject()
  assertThenResolution(onFulfilledCalls, onRejectedCalls, nil, true)
end

function Test_reject_resolve()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.reject(result)
  deferred.resolve('a result')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result, true)
end

function Test_reject_reject()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.reject(result)
  deferred.reject('another error')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result, true)
end

function Test_then_resolve_no_function()
  local deferred, promise = deferPromise()
  local np = promise:next()
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  local result = {}
  deferred.resolve(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function Test_then_after_resolve_no_function()
  local deferred, promise = deferPromise()
  local result = {}
  deferred.resolve(result)
  local np = promise:next()
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function Test_then_reject_no_function()
  local deferred, promise = deferPromise()
  local np = promise:next()
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  local result = {}
  deferred.reject(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result, true)
end

function Test_then()
  local deferred, promise = deferPromise()
  local np = promise:next(function(value)
    return value + 1
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.resolve(1)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, 2)
end

function Test_done()
  local deferred, promise = deferPromise()
  local np = promise:done(function(value)
    return value + 1
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.resolve(1)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, 2)
end

function Test_then_error()
  local deferred, promise = deferPromise()
  local err = 'An error during onFulfilled'
  local np = promise:next(function(value)
    error(err, 0)
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.resolve()
  assertThenResolution(onFulfilledCalls, onRejectedCalls, err, true)
end

function Test_then_reject()
  local deferred, promise = deferPromise()
  local np = promise:next(nil, function(value)
    return value + 1
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.reject(1)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, 2)
end

function Test_catch_reject()
  local deferred, promise = deferPromise()
  local np = promise:catch(function(value)
    return value + 1
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.reject(1)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, 2)
end

function Test_multiple_then_no_function()
  local deferred, promise = deferPromise()
  local np = promise:next()
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  local onFulfilledCalls2, onRejectedCalls2 = nextPromise(np)
  local result = {}
  deferred.resolve(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
  assertThenResolution(onFulfilledCalls2, onRejectedCalls2, result)
end

function Test_then_chained()
  local deferred, promise = deferPromise()
  local deferred2, promise2 = deferPromise()
  local np = promise:next(function(value)
    return promise2
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.resolve()
  assertNoResolution(onFulfilledCalls, onRejectedCalls)
  local result = {}
  deferred2.resolve(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function Test_all_resolved()
  local deferred1, promise1 = deferPromise()
  local deferred2, promise2 = deferPromise()
  local promise = Promise.all({promise1, promise2})
  local resolution = false
  promise:next(function(value)
    resolution = value
  end)
  lu.assertFalse(resolution)
  deferred2.resolve('Success 2')
  lu.assertFalse(resolution)
  deferred1.resolve('Success 1')
  lu.assertEquals(resolution, {'Success 1', 'Success 2'})
end

function Test_all_rejected()
  local deferred1, promise1 = deferPromise()
  local deferred2, promise2 = deferPromise()
  local deferred3, promise3 = deferPromise()
  local promise = Promise.all({promise1, promise2, promise3})
  local resolution = false
  promise:next(nil, function(value)
    resolution = value
  end)
  lu.assertFalse(resolution)
  deferred2.resolve('Success 2')
  lu.assertFalse(resolution)
  deferred1.reject('Error 1')
  lu.assertEquals(resolution, 'Error 1')
end

function Test_all_empty()
  local promise = Promise.all({})
  local resolution = false
  promise:next(function(value)
    resolution = value
  end)
  lu.assertEquals(resolution, {})
end

function Test_race_resolved()
  local deferred1, promise1 = deferPromise()
  local deferred2, promise2 = deferPromise()
  local promise = Promise.race({promise1, promise2})
  local resolution = false
  promise:next(function(value)
    resolution = value
  end)
  lu.assertFalse(resolution)
  deferred2.resolve('Success 2')
  lu.assertEquals(resolution, 'Success 2')
end

function Test_race_rejected()
  local deferred1, promise1 = deferPromise()
  local deferred2, promise2 = deferPromise()
  local promise = Promise.race({promise1, promise2})
  local resolution = false
  promise:next(nil, function(value)
    resolution = value
  end)
  lu.assertFalse(resolution)
  deferred2.reject('Error 2')
  lu.assertEquals(resolution, 'Error 2')
end

os.exit(lu.LuaUnit.run())
