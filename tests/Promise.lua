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


function test_executor()
  local resultValue, resultReason
  local deferred, promise = deferPromise()
  lu.assertEquals(type(deferred.resolve), 'function')
  lu.assertEquals(type(deferred.reject), 'function')
end

function test_resolve()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.resolve(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function test_resolve_multi_values()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.resolve(result, 'another result')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function test_resolve_nil()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  deferred.resolve()
  assertThenResolution(onFulfilledCalls, onRejectedCalls, nil)
end

function test_resolve_resolve()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.resolve(result)
  deferred.resolve('another result')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function test_resolve_reject()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.resolve(result)
  deferred.reject('an error')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function test_reject()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.reject(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result, true)
end

function test_reject_nil()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.reject()
  assertThenResolution(onFulfilledCalls, onRejectedCalls, nil, true)
end

function test_reject_resolve()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.reject(result)
  deferred.resolve('a result')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result, true)
end

function test_reject_reject()
  local deferred, promise = deferPromise()
  local onFulfilledCalls, onRejectedCalls = nextPromise(promise)
  local result = {}
  deferred.reject(result)
  deferred.reject('another error')
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result, true)
end

function test_then_resolve_no_function()
  local deferred, promise = deferPromise()
  local np = promise:next()
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  local result = {}
  deferred.resolve(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function test_then_after_resolve_no_function()
  local deferred, promise = deferPromise()
  local result = {}
  deferred.resolve(result)
  local np = promise:next()
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
end

function test_then_reject_no_function()
  local deferred, promise = deferPromise()
  local np = promise:next()
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  local result = {}
  deferred.reject(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result, true)
end

function test_then()
  local deferred, promise = deferPromise()
  local np = promise:next(function(value)
    return value + 1
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.resolve(1)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, 2)
end

function test_done()
  local deferred, promise = deferPromise()
  local np = promise:done(function(value)
    return value + 1
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.resolve(1)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, 2)
end

function test_then_error()
  local deferred, promise = deferPromise()
  local err = 'An error during onFulfilled'
  local np = promise:next(function(value)
    error(err, 0)
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.resolve()
  assertThenResolution(onFulfilledCalls, onRejectedCalls, err, true)
end

function test_then_reject()
  local deferred, promise = deferPromise()
  local np = promise:next(nil, function(value)
    return value + 1
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.reject(1)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, 2)
end

function test_catch_reject()
  local deferred, promise = deferPromise()
  local np = promise:catch(function(value)
    return value + 1
  end)
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  deferred.reject(1)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, 2)
end

function test_multiple_then_no_function()
  local deferred, promise = deferPromise()
  local np = promise:next()
  local onFulfilledCalls, onRejectedCalls = nextPromise(np)
  local onFulfilledCalls2, onRejectedCalls2 = nextPromise(np)
  local result = {}
  deferred.resolve(result)
  assertThenResolution(onFulfilledCalls, onRejectedCalls, result)
  assertThenResolution(onFulfilledCalls2, onRejectedCalls2, result)
end

function test_then_chained()
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

os.exit(lu.LuaUnit.run())
