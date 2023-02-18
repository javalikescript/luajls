--- Represents the eventual result of an asynchronous operation.
-- **Note**: The _then_ method is replaced by _next_, because _then_ is a reserved word in Lua.
-- see [Promises/A+](https://promisesaplus.com/)
--
-- @module jls.lang.Promise
-- @pragma nostrip

local PENDING = 0
local FULFILLED = 1
local REJECTED = 2
local ERROR = 3

local NO_VALUE = {}

local protectedCall = pcall
local onUncaughtError = print

local ERROR_METATABLE = {
  __gc = function(e)
    if type(e) == 'table' and e.uncaught == true then
      onUncaughtError(e.message)
    end
  end
}

local function wrapError(message)
  return setmetatable({
    message = message,
    uncaught = true
  }, ERROR_METATABLE)
end

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

local function isPromise(promise)
  return type(promise) == 'table' and type(promise.next) == 'function'
end

applyPromiseHandler = function(promise, handler)
  local status, result = true, NO_VALUE
  local state = promise._state
  if state == FULFILLED then
    if type(handler.onFulfilled) == 'function' then
      status, result = protectedCall(handler.onFulfilled, promise._result)
    end
  elseif state == REJECTED then
    if type(handler.onRejected) == 'function' then
      status, result = protectedCall(handler.onRejected, promise._result)
    end
  elseif state == ERROR then
    if type(handler.onRejected) == 'function' then
      promise._result.uncaught = false
      status, result = protectedCall(handler.onRejected, promise._result.message)
    end
  else
    error('Invalid promise state ('..tostring(state)..')')
  end
  if status then
    if result == NO_VALUE then
      -- If onFulfilled is not a function and promise1 is fulfilled, promise2 must be fulfilled with the same value as promise1
      -- If onRejected is not a function and promise1 is rejected, promise2 must be rejected with the same reason as promise1
      applyPromise(handler.promise, promise._result, state)
    elseif result == promise then
      applyPromise(handler.promise, 'Invalid promise result', REJECTED)
    elseif isPromise(result) then
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
    applyPromise(handler.promise, wrapError(result), ERROR)
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
@tparam function executor A function that is passed with the arguments resolve and reject.
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
@tparam function onFulfilled A Function called when the Promise is fulfilled.
 This function has one argument, the fulfillment value.
@tparam[opt] function onRejected A Function called when the Promise is rejected.
 This function has one argument, the rejection reason.
@return A new promise.
]]
function promise:next(onFulfilled, onRejected)
  local p = Promise:new()
  local handler = {
    promise = p,
    onFulfilled = onFulfilled,
    onRejected = onRejected
  }
  --if self._state == PENDING then
  if self._handlers ~= nil then
    table.insert(self._handlers, handler)
  else
    -- onFulfilled and onRejected must be called asynchronously;
    -- TODO defer
    applyPromiseHandler(self, handler)
  end
  return p
end

--- Appends a rejection handler callback to the promise, and returns a new
-- promise resolving to the return value of the callback if it is called,
-- or to its original fulfillment value if the promise is instead fulfilled.
--
-- @tparam function onRejected A Function called when the Promise is rejected.
-- @return A new promise.
function promise:catch(onRejected)
  return self:next(nil, onRejected)
end

function promise:done(onFulfilled)
  return self:next(onFulfilled, nil)
end

--- Appends a handler callback to the promise for both fulfillment and rejection,
-- and returns an equivalent of the original promise.
-- In case of error or returning a rejected promise in the finally callback will reject the returned promise.
--
-- @tparam function onFinally A Function called when the Promise is either fulfilled or rejected.
-- @return A new promise.
function promise:finally(onFinally)
  -- finally call will usually chain through an equivalent to the original promise
  -- onFinally shall not receive any argument
  -- throw (or returning a rejected promise) in the finally callback will reject the returned promise
  return self:next(function(value)
    local result = onFinally()
    if isPromise(result) then
      return result:next(function()
        return value
      end)
    end
    return value
  end, function(reason)
    local result = onFinally()
    if isPromise(result) then
      return result:next(function()
        return Promise.reject(reason)
      end)
    end
    return Promise.reject(reason)
  end)
end


--[[--
Returns a new promise and its associated callback.
@usage
local promise, cb = Promise.createWithCallback()
--]]
function Promise.createWithCallback()
  local p = Promise:new()
  return p, asCallback(p)
end

function Promise.createWeakWithCallback(prepare)
  local p = Promise:new()
  function p:next(onFulfilled, onRejected)
    self.next = nil -- remove overrided next function to only call prepare once
    if type(prepare) == 'function' then
      prepare(asCallback(self))
    end
    return self:next(onFulfilled, onRejected)
  end
  return p
end

function Promise.createWithCallbacks()
  local p = Promise:new()
  return p, asCallbacks(p)
end

function Promise.newCallback(executor)
  local p = Promise:new()
  executor(asCallback(p))
  return p
end

function Promise.newCallbacks(executor)
  local p = Promise:new()
  executor(asCallbacks(p))
  return p
end

--- Returns a promise that either fulfills when all of the promises in the
-- iterable argument have fulfilled or rejects as soon as one of the
-- promises in the iterable argument rejects.
--
-- @tparam table promises The promises list.
-- @return A promise.
function Promise.all(promises)
  local count = #promises
  local values = {}
  local ps, resolve, reject = Promise.createWithCallbacks()
  if count > 0 then
    local function resolveAt(index)
      return function(value)
        values[index] = value
        count = count - 1
        if count == 0 then
          resolve(values)
        end
      end
    end
    for i, p in ipairs(promises) do
      p:next(resolveAt(i), reject)
    end
  else
    resolve(values)
  end
  return ps
end

function Promise.allSettled(promises)
  local count = #promises
  local values = {}
  local ps, resolve, reject = Promise.createWithCallbacks()
  if count > 0 then
    local function callbackAt(index, rejected)
      return function(value)
        local outcome
        if rejected then
          outcome = {
            status = 'rejected',
            reason = value
          }
        else
          outcome = {
            status = 'fulfilled',
            value = value
          }
        end
        values[index] = outcome
        count = count - 1
        if count == 0 then
          resolve(values)
        end
      end
    end
    for i, p in ipairs(promises) do
      p:next(callbackAt(i), callbackAt(i, true))
    end
  else
    resolve(values)
  end
  return ps
end

function Promise.any(promises)
  local count = #promises
  local reasons = {}
  local ps, resolve, reject = Promise.createWithCallbacks()
  if count > 0 then
    local function rejectAt(index)
      return function(value)
        reasons[index] = value
        count = count - 1
        if count == 0 then
          reject(reasons)
        end
      end
    end
    for i, p in ipairs(promises) do
      p:next(resolve, rejectAt(i))
    end
  else
    reject()
  end
  return ps
end

--- Returns a promise that fulfills or rejects as soon as one of the
-- promises in the iterable fulfills or rejects, with the value or reason
-- from that promise.
--
-- @tparam table promises The promises list.
-- @return A promise.
function Promise.race(promises)
  local ps, resolve, reject = Promise.createWithCallbacks()
  for _, p in ipairs(promises) do
    p:next(resolve, reject)
  end
  return ps
end

--- Returns a Promise object that is rejected with the given reason.
--
-- @param reason The reason for the rejection.
-- @return A rejected promise.
function Promise.reject(reason)
  local p = Promise:new()
  applyPromise(p, reason, REJECTED)
  return p
end

--- Returns a Promise object that is resolved with the given value.
-- If the value is a thenable (i.e. has a next method), the returned
-- promise will "follow" that thenable, adopting its eventual state;
-- otherwise the returned promise will be fulfilled with the value.
--
-- @param value The resolving value.
-- @return A resolved promise.
function Promise.resolve(value)
  local p = Promise:new()
  applyPromise(p, value, FULFILLED)
  return p
end

--- Returns the specified callback if any or a callback and its associated promise.
-- This function helps to create asynchronous functions with an optional ending callback parameter.
-- @param callback An optional existing callback or false to indicate that no promise is expected.
-- @return a callback and an associated promise if necessary.
-- @usage function readAsync(callback)
--   local cb, promise = Promise.ensureCallback(callback)
--   -- call cb(nil, value) on success or cb(reason) on error
--   return promise
-- end
function Promise.ensureCallback(callback)
  if type(callback) == 'function' then
    return callback, nil
  elseif callback == false then
    return nil, nil
  elseif callback ~= nil then
    error('Invalid callback')
  end
  local p, resolutionCallback = Promise.createWithCallback()
  return resolutionCallback, p
end

function Promise.callbackToNext(callback)
  if callback == nil then
    return nil, nil
  end
  return function(value)
    return callback(nil, value)
  end, function(reason)
    return callback(reason or 'Unknown error')
  end
end

--- Return true if the specified value is a promise.
-- @param promise The value to test.
-- @treturn boolean true if the specified value is a promise.
-- @function Promise.isPromise
Promise.isPromise = isPromise

function Promise.setProtectedCall(value)
  protectedCall = value or pcall
end

function Promise.onUncaughtError(value)
  onUncaughtError = value or print
end

do
  local status, Exception = pcall(require, 'jls.lang.Exception')
  if status then
    Promise.setProtectedCall(Exception.pcall)
  end
end
do
  local status, logger = pcall(require, 'jls.lang.logger')
  if status then
    Promise.onUncaughtError(function(e)
      logger:warn('Uncaught promise error: %s', e)
    end)
  end
end

end)
