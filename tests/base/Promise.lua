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

function Test_any_rejected()
  local result
  Promise.any({Promise.reject(3), Promise.resolve(5)}):next(function(value)
    result = value
  end)
  lu.assertEquals(result, 5)
  local rejected = false
  Promise.any({Promise.reject(3), Promise.reject(5)}):catch(function(value)
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
  lu.assertEquals(resolution, {{status='fulfilled', value='Success 1'}, {status='fulfilled', value='Success 2'}})
end

function Test_allSettled_empty()
  local promise = Promise.allSettled({})
  local resolution = false
  promise:next(function(value)
    resolution = value
  end)
  lu.assertEquals(resolution, {})
end

function Test_allSettled_rejected()
  local resolution = false
  Promise.allSettled({Promise.reject(3), Promise.resolve(5)}):next(function(value)
    resolution = value
  end)
  lu.assertEquals(resolution, {{status='rejected', reason=3}, {status='fulfilled', value=5}})
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
  local function returnPromised3()
    return Promise.resolve(3)
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

  Promise.resolve(2):finally(returnPromised3):next(captureResult)
  lu.assertEquals(result, 2)
  Promise.reject(2):finally(returnPromised3):next(captureResult)
  lu.assertEquals(result, 2)
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

function Test_Promise_resolve()
  local result
  Promise.resolve({
    next = function(_, fn)
      fn(3)
    end
  }):next(function(value)
    result = value
  end)
  lu.assertEquals(result, 3)
  Promise.resolve({
    next = function(_, _, fn)
      fn(5)
    end
  }):next(nil, function(value)
    result = value
  end)
  lu.assertEquals(result, 5)
end

function Test_withResolvers()
  local p, resolve, reject = Promise.withResolvers()
  local result
  p:next(function(value)
    result = value
  end)
  resolve(3)
  lu.assertEquals(result, 3)
end

function Test_ensureCallback()
  local cb, p
  local fn = function() end

  cb, p = Promise.ensureCallback(fn)
  lu.assertIs(cb, fn)
  lu.assertNil(p)

  cb, p = Promise.ensureCallback(false)
  lu.assertNil(cb)
  lu.assertNil(p)

  cb, p = Promise.ensureCallback(false, true)
  lu.assertNotNil(cb)
  lu.assertNil(p)

  cb, p = Promise.ensureCallback()
  lu.assertEquals(type(cb), 'function')
  lu.assertTrue(Promise:isInstance(p))
end

function Test_applyCallback()
  local reason, value, p
  local cb = function(r, v)
    reason, value = r, v
  end
  local captureValue = function(v)
    value = v
  end
  local captureReason = function(r)
    reason = r
  end

  reason, value = nil, nil
  p = Promise.applyCallback(nil, nil, 'success')
  lu.assertTrue(Promise:isInstance(p))
  p:next(captureValue, captureReason)
  lu.assertNil(reason)
  lu.assertEquals(value, 'success')

  reason, value = nil, nil
  p = Promise.applyCallback(nil, 'ouch')
  lu.assertTrue(Promise:isInstance(p))
  p:next(captureValue, captureReason)
  lu.assertEquals(reason, 'ouch')
  lu.assertNil(value)

  reason, value = nil, nil
  p = Promise.applyCallback(cb, nil, 'success')
  lu.assertNil(p)
  lu.assertNil(reason)
  lu.assertEquals(value, 'success')

  reason, value = nil, nil
  p = Promise.applyCallback(cb, 'ouch')
  lu.assertNil(p)
  lu.assertEquals(reason, 'ouch')
  lu.assertNil(value)
end

function Test_new_executor_resolve()
  local result
  local p = Promise:new(function(resolve, reject)
    resolve('done')
  end)
  p:next(function(value)
    result = value
  end)
  lu.assertEquals(result, 'done')
end

function Test_new_executor_reject()
  local reason
  local p = Promise:new(function(resolve, reject)
    reject('fail')
  end)
  p:next(nil, function(value)
    reason = value
  end)
  lu.assertEquals(reason, 'fail')
end

function Test_resolve_instance()
  local p = Promise:new()
  lu.assertIs(Promise.resolve(p), p)
  lu.assertTrue(Promise.isPromise(p))
  lu.assertFalse(Promise.isPromise({}))
  lu.assertFalse(Promise.isPromise(1))
  lu.assertFalse(Promise.isPromise(nil))
end

function Test_withCallback()
  local p, cb = Promise.withCallback()
  local result
  p:next(function(value)
    result = value
  end)
  cb(nil, 5)
  lu.assertEquals(result, 5)

  local p2, cb2 = Promise.withCallback()
  local reason
  p2:catch(function(value)
    reason = value
  end)
  cb2('bad')
  lu.assertEquals(reason, 'bad')
end

function Test_newCallback()
  local result
  local p = Promise.newCallback(function(cb)
    cb(nil, 7)
  end)
  p:next(function(value)
    result = value
  end)
  lu.assertEquals(result, 7)
end

function Test_callbackToNext()
  lu.assertNil((Promise.callbackToNext(nil)))
  local calls = {}
  local onFulfilled, onRejected = Promise.callbackToNext(function(reason, value)
    calls[#calls + 1] = {reason, value}
  end)
  onFulfilled(3)
  onRejected('err')
  onRejected(nil)
  lu.assertEquals(calls[1], {nil, 3})
  lu.assertEquals(calls[2][1], 'err')
  lu.assertEquals(calls[3][1], 'unknown reason')
end

function Test_chainCallback()
  local p = Promise.resolve(3)
  lu.assertIs(Promise.chainCallback(p, nil), p)
  lu.assertNil(Promise.chainCallback(p, false))
  local calls = {}
  Promise.chainCallback(Promise.resolve(5), function(reason, value)
    calls[#calls + 1] = {reason, value}
  end)
  lu.assertEquals(calls[1], {nil, 5})
  local ok, err = pcall(Promise.chainCallback, p, 3)
  lu.assertFalse(ok)
  lu.assertStrContains(err, 'invalid callback')
end

function Test_invalidCallback()
  lu.assertFalse(pcall(Promise.ensureCallback, 3))
  lu.assertFalse(pcall(Promise.applyCallback, 3))
end

function Test_setProtectedCall()
  local count = 0
  Promise.setProtectedCall(function(f, ...)
    count = count + 1
    return pcall(f, ...)
  end)
  local result
  Promise.resolve(1):next(function(value)
    return value + 1
  end):next(function(value)
    result = value
  end)
  lu.assertEquals(result, 2)
  lu.assertTrue(count > 0)
  local ok, Exception = pcall(require, 'jls.lang.Exception')
  Promise.setProtectedCall(ok and Exception.pcall or nil)
end

function Test_createWeakWithCallback()
  local prepared
  local p = Promise.createWeakWithCallback(function(cb)
    prepared = cb
  end)
  local result
  p:next(function(value)
    result = value
  end)
  lu.assertNotNil(prepared)
  prepared(nil, 9)
  lu.assertEquals(result, 9)
  local first = prepared
  p:next(function() end)
  lu.assertIs(first, prepared)
end

function Test_async_return()
  local result
  local p = Promise.async(function()
    return 5
  end)
  lu.assertTrue(Promise.isPromise(p))
  p:next(function(value)
    result = value
  end)
  lu.assertEquals(result, 5)
end

function Test_async_args()
  local result
  Promise.async(function(await, a, b)
    return a + b
  end, 2, 3):next(function(value)
    result = value
  end)
  lu.assertEquals(result, 5)
end

function Test_async_await_resolved()
  local result
  Promise.async(function(await)
    local value = await(Promise.resolve(3))
    return value + 1
  end):next(function(value)
    result = value
  end)
  lu.assertEquals(result, 4)
end

function Test_async_await_pending()
  local deferred, pending = deferPromise()
  local result
  Promise.async(function(await)
    local value = await(pending)
    return value..'!'
  end):next(function(value)
    result = value
  end)
  lu.assertNil(result)
  deferred.resolve('hi')
  lu.assertEquals(result, 'hi!')
end

function Test_async_await_multiple()
  local deferred1, pending1 = deferPromise()
  local deferred2, pending2 = deferPromise()
  local result
  Promise.async(function(await)
    local a = await(pending1)
    local b = await(pending2)
    return a + b
  end):next(function(value)
    result = value
  end)
  deferred1.resolve(2)
  lu.assertNil(result)
  deferred2.resolve(3)
  lu.assertEquals(result, 5)
end

function Test_async_await_rejected()
  local reason
  Promise.async(function(await)
    return await(Promise.reject('boom'))
  end):catch(function(value)
    reason = value
  end)
  lu.assertEquals(reason:getMessage(), 'boom')
end

function Test_async_await_pending_reject()
  local deferred, pending = deferPromise()
  local reason
  Promise.async(function(await)
    return await(pending)
  end):catch(function(value)
    reason = value
  end)
  lu.assertNil(reason)
  deferred.reject('nope')
  lu.assertEquals(reason:getMessage(), 'nope')
end

function Test_async_throw()
  local reason
  Promise.async(function()
    error('kaboom', 0)
  end):catch(function(value)
    reason = value
  end)
  lu.assertEquals(reason:getMessage(), 'kaboom')
end

function Test_async_await_error_state()
  local inner = Promise.resolve(1):next(function()
    error('oops', 0)
  end)
  local reason
  Promise.async(function(await)
    return await(inner)
  end):catch(function(value)
    reason = value
  end)
  lu.assertEquals(reason:getMessage(), 'oops')
end

os.exit(lu.LuaUnit.run())
