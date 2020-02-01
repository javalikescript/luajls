--- A promise represents the eventual result of an asynchronous operation.
-- see https://promisesaplus.com/
-- @module jls.lang.Promise
-- @pragma nostrip

local PENDING = 0
local FULFILLED = 1
local REJECTED = 2

local NO_VALUE = {}

local applyPromiseHandler

local function applyPromise(promise, result, state)
  if promise._state == PENDING then -- only one resolution is allowed
    promise._state = state
    promise._result = result
    for _, handler in ipairs(promise._handlers) do
      applyPromiseHandler(promise, handler)
    end
    promise._handlers = nil -- cleaning handlers
  end
end

applyPromiseHandler = function(promise, handler)
  local status, result = true, NO_VALUE
  if promise._state == FULFILLED then
    if type(handler.onFulfilled) == 'function' then
      status, result = pcall(handler.onFulfilled, promise._result)
    end
  elseif promise._state == REJECTED then
    if type(handler.onRejected) == 'function' then
      status, result = pcall(handler.onRejected, promise._result)
    end
  else
    error('Invalid promise state ('..tostring(promise._state)..')')
  end
  if status then
    if result == NO_VALUE then
      -- If onFulfilled is not a function and promise1 is fulfilled, promise2 must be fulfilled with the same value as promise1
      -- If onRejected is not a function and promise1 is rejected, promise2 must be rejected with the same reason as promise1
      applyPromise(handler.promise, promise._result, promise._state)
    elseif result == promise then
      applyPromise(handler.promise, 'Invalid promise result', REJECTED)
    elseif type(result) == 'table' and type(result.next) == 'function' then
      -- we may want to detect cycle in the thenable chain
      -- TODO: If calling then throws an exception e,
      -- If resolvePromise or rejectPromise have been called, ignore it.
      -- Otherwise, reject promise with e as the reason.
      result:next(function(value)
        applyPromise(handler.promise, value, FULFILLED)
      end, function(reason)
        applyPromise(handler.promise, reason, REJECTED)
      end)
    else
      -- If either onFulfilled or onRejected returns a value then run the Promise Resolution Procedure
      -- Note: the value could be nil even if it is not specified
      applyPromise(handler.promise, result, FULFILLED)
    end
  else
    -- If either onFulfilled or onRejected throws an exception e, promise2 must be rejected with e as the reason.
    applyPromise(handler.promise, result, REJECTED)
  end
end

local function asCallback(promise)
  return function(reason, value)
    if reason then
      applyPromise(promise, reason, REJECTED)
    else
      applyPromise(promise, value, FULFILLED)
    end
  end
end

local function asCallbacks(promise)
  return function(value)
    applyPromise(promise, value, FULFILLED)
  end, function(reason)
    applyPromise(promise, reason, REJECTED)
  end
end

--- A promise represents the completion (or failure) of an asynchronous operation, and its resulting value (or error).
-- @type Promise
return require('jls.lang.class').create(function(promise, _, Promise)
--[[--
Creates a promise.
@function Promise:new
@param executor A function that is passed with the arguments resolve and reject.
@usage
Promise:new(function(resolve, reject)
  -- call resolve(value) or reject(reason)
end)
--]]
function promise:initialize(executor)
  self._handlers = {}
  self._state = PENDING
  self._result = NO_VALUE
  if type(executor) == 'function' then
    executor(asCallbacks(self))
  end
end

--[[--
Appends fulfillment and rejection handlers to the promise, and returns
a new promise resolving to the return value of the called handler,
or to its original settled value if the promise was not handled.

If onFulfilled or onRejected throws an error, or returns a Promise which
rejects, then returns a rejected Promise.
If onFulfilled or onRejected returns a Promise which resolves,
or returns any other value, then returns a resolved Promise.
@param onFulfilled A Function called when the Promise is fulfilled.
 This function has one argument, the fulfillment value.
@param onRejected A Function called when the Promise is rejected.
 This function has one argument, the rejection reason.
@return A new promise.
]]
function promise:next(onFulfilled, onRejected)
  local promise = Promise:new()
  local handler = {
    promise = promise,
    onFulfilled = onFulfilled,
    onRejected = onRejected
  }
  if self._state == PENDING then
    table.insert(self._handlers, handler)
  else
    -- onFulfilled and onRejected must be called asynchronously;
    -- TODO defer
    applyPromiseHandler(self, handler)
  end
  return promise
end

--- Appends a rejection handler callback to the promise, and returns a new
-- promise resolving to the return value of the callback if it is called,
-- or to its original fulfillment value if the promise is instead fulfilled.
--
-- @param onRejected A Function called when the Promise is rejected.
-- @return A new promise.
function promise:catch(onRejected)
  return self:next(nil, onRejected)
end

function promise:done(onFulfilled)
  return self:next(onFulfilled, nil)
end

function promise:finally(onFinally)
  return self:next(onFinally, onFinally)
end


--[[--
Returns a new promise and its associated callback.
@usage
local promise, cb = Promise.createWithCallback()
--]]
function Promise.createWithCallback()
  local promise = Promise:new()
  return promise, asCallback(promise)
end

function Promise.createWithCallbacks()
  local promise = Promise:new()
  return promise, asCallbacks(promise)
end

function Promise.newCallback(executor)
  local promise = Promise:new()
  executor(asCallback(promise))
  return promise
end

function Promise.newCallbacks(executor)
  local promise = Promise:new()
  executor(asCallbacks(promise))
  return promise
end

--- Returns a promise that either fulfills when all of the promises in the
-- iterable argument have fulfilled or rejects as soon as one of the
-- promises in the iterable argument rejects.
-- 
-- @param promises The promises.
-- @return A promise.
function Promise.all(promises) end

--- Returns a promise that fulfills or rejects as soon as one of the
-- promises in the iterable fulfills or rejects, with the value or reason
-- from that promise.
-- 
-- @param promises The promises.
-- @return A promise.
function Promise.race(promises) end

--- Returns a Promise object that is rejected with the given reason.
-- 
-- @param reason The reason for the rejection.
-- @return A rejected promise.
function Promise.reject(reason)
  return Promise:new(function(resolve, reject)
    reject(reason)
  end)
end

--- Returns a Promise object that is resolved with the given value.
-- If the value is a thenable (i.e. has a next method), the returned
-- promise will "follow" that thenable, adopting its eventual state;
-- otherwise the returned promise will be fulfilled with the value.
-- 
-- @param value The resolving value.
-- @return A resolved promise.
function Promise.resolve(value)
  return Promise:new(function(resolve, reject)
    resolve(value)
  end)
end

--- Returns the specified callback if any or a callback and its associated promise.
-- This function helps to create asynchronous functions with an optional ending callback parameter.
-- @param callback An optional existing callback.
-- @return a callback and an associated promise if necessary.
-- @usage function readAsync(callback)
--   local cb, promise = Promise.ensureCallback(callback)
--   -- call cb(nil, value) on success or cb(reason) on error
--   return promise
-- end
function Promise.ensureCallback(callback)
  if type(callback) == 'function' then
    return callback
  end
  local promise, resolutionCallback = Promise.createWithCallback()
  return resolutionCallback, promise
end

end)
