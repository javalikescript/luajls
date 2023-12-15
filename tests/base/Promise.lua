local lu = require('luaunit')

local Promise = require('jls.lang.Promise')
--require('jls.lang.logger'):setLevel('FINE')

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
      if type(value) == 'function' then
        value(onRejectedCalls[1][1])
      else
        lu.assertEquals(onRejectedCalls[1][1], value)
      end
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
  assertThenResolution(onFulfilledCalls, onRejectedCalls, function(result)
    lu.assertNotNil(string.find(tostring(result), err, 1, true))
    lu.assertEquals(result:getMessage(), err)
  end, true)
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

function Test_any_resolved()
  local deferred1, promise1 = deferPromise()
  local deferred2, promise2 = deferPromise()
  local promise = Promise.any({promise1, promise2})
  local resolution = false
  promise:next(function(value)
    resolution = value
  end)
  lu.assertFalse(resolution)
  deferred2.resolve('Success 2')
  lu.assertEquals('Success 2', resolution)
  deferred1.resolve('Success 1')
  lu.assertEquals('Success 2', resolution)
end

function Test_any_empty()
  local promise = Promise.any({})
  local rejected = false
  promise:next(nil, function()
    rejected = true
  end)
  lu.assertTrue(rejected)
end

function Test_allSettled_resolved()
  local deferred1, promise1 = deferPromise()
  local deferred2, promise2 = deferPromise()
  local promise = Promise.allSettled({promise1, promise2})
  local resolution = false
  promise:next(function(value)
    resolution = value
  end)
  lu.assertFalse(resolution)
  deferred2.resolve('Success 2')
  lu.assertFalse(resolution)
  deferred1.resolve('Success 1')
  lu.assertEquals(resolution, {{status="fulfilled", value="Success 1"}, {status="fulfilled", value="Success 2"}})
end

function Test_allSettled_empty()
  local promise = Promise.allSettled({})
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

function Test_resolution_ordering()
  local index = 0
  local function nextIndex()
    index = index + 1
    return index
  end
  local nextIndex1, nextIndex2, nextIndex3, nextIndex4, nextIndex5
  local deferred, promise = deferPromise()
  promise:next(function()
    nextIndex1 = nextIndex()
    promise:next(function()
      nextIndex3 = nextIndex()
    end)
  end)
  promise:next(function()
    nextIndex2 = nextIndex()
    promise:next(function()
      nextIndex4 = nextIndex()
    end)
  end)
  deferred.resolve()
  promise:next(function()
    nextIndex5 = nextIndex()
  end)
  lu.assertEquals(nextIndex1, 1)
  lu.assertEquals(nextIndex2, 2)
  lu.assertEquals(nextIndex3, 3)
  lu.assertEquals(nextIndex4, 4)
  lu.assertEquals(nextIndex5, 5)
  lu.assertEquals(nextIndex(), 6)
end

function Test_promise_reject()
  local ok, reason
  Promise.reject('Houla'):next(function()
    ok = false
  end, function(r)
    ok = true
    reason = r
  end)
  lu.assertTrue(ok)
  lu.assertEquals(reason, 'Houla')
end

function Test_next_reject_next_catch_chained()
  local ok, reason
  local deferred, promise = deferPromise()
  promise:next(function()
    return Promise.reject('Houla')
  end):next(function()
    ok = false
  end):catch(function(r)
    ok = true
    reason = r
  end)
  deferred.resolve()
  lu.assertEquals(reason, 'Houla')
  lu.assertTrue(ok)
end

function Test_finally()
  local result
  local function return3()
    return 3
  end
  local function captureResult(value)
    result = value
  end
  Promise.resolve(2):next(return3, return3):next(captureResult)
  lu.assertEquals(result, 3)
  Promise.resolve(2):finally(return3):next(captureResult)
  lu.assertEquals(result, 2)
  result = nil
  Promise.reject(2):next(return3, return3):next(captureResult)
  lu.assertEquals(result, 3)
  Promise.reject(2):finally(return3):catch(captureResult)
  lu.assertEquals(result, 2)
  result = nil
  Promise.resolve(2):finally(function()
    return Promise.reject(3)
  end):catch(captureResult)
  lu.assertEquals(result, 3)
  result = nil
  Promise.resolve(2):finally(function()
    error({3}) -- Lua 5.1 turns number message to string
  end):catch(captureResult)
  lu.assertNotNil(result)
  lu.assertEquals(result:getMessage(), {3})
end

function Test_uncaucht()
  if _VERSION == 'Lua 5.1' then
    print('/!\\ skipping test due to Lua version')
    lu.success()
    return
  end
  local unaucht
  Promise.onUncaughtError(function(e)
    unaucht = e
  end)
  do
    Promise.resolve(2):next(function()
      error('Houla', 0)
    end)
  end
  collectgarbage('collect')
  lu.assertNotNil(unaucht)
  lu.assertEquals(unaucht:getMessage(), 'Houla')
  Promise.onUncaughtError()
end

os.exit(lu.LuaUnit.run())
