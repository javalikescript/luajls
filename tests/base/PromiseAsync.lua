local lu = require('luaunit')

local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')

local function future(value, millis)
  return Promise:new(function(resolve, reject)
    event:setTimeout(function()
      if Promise.isPromise(value) then
        value:next(resolve, reject)
      else
        resolve(value)
      end
    end, millis or 0)
  end)
end

function Test_async_await()
  local v
  Promise.async(function(await, w)
    return await(future(w + 1))
  end, 1):next(function(r)
    v = r
  end)
  lu.assertNil(v)
  event:loop()
  lu.assertEquals(v, 2)
end

function Test_async_await_n()
  local v
  Promise.async(function(await, n)
    local w = 0
    for i = 1, n do
      w = await(future(w + 1))
    end
    return w
  end, 3):next(function(r)
    v = r
  end)
  lu.assertNil(v)
  event:loop()
  lu.assertEquals(v, 3)
end

function Test_async_await_error()
  --[[
    local cr = coroutine.create(function()
      local function r()
        error('ouch')
        --void()
      end
      r()
    end)
    print('resume:', coroutine.resume(cr))
    print('traceback:', debug.traceback(cr, nil, 1))
  ]]
  local v
  Promise.async(function(await)
    await(future())
    local function aFunction()
      error('ouch', 0)
      --void()
    end
    aFunction()
  end):catch(function(e)
    v = e
  end)
  lu.assertNil(v)
  event:loop()
  print(v)
  lu.assertEquals(Exception.getMessage(v), 'ouch')
end

function Test_async_await_reject()
  local v
  Promise.async(function(await)
    await(future(Promise.reject('ouch')))
  end):catch(function(e)
    v = e
  end)
  lu.assertNil(v)
  event:loop()
  lu.assertEquals(Exception.getMessage(v), 'ouch')
end

function Test_async_n_await()
  local function asyncInc(n)
    return Promise.async(function(await, m)
      return await(future(m + 1))
    end, n)
  end
  local v
  Promise.async(function(await, n)
    return await(asyncInc(n)) * await(asyncInc(n))
  end, 1):next(function(r)
    v = r
  end)
  lu.assertNil(v)
  event:loop()
  lu.assertEquals(v, 4)
end

os.exit(lu.LuaUnit.run())
