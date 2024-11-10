local lu = require('luaunit')

local Thread = require('jls.lang.Thread')
local event = require('jls.lang.event')
local BufferStream = require('jls.util.BufferStream')
local Promise = require('jls.lang.Promise')
local loop = require('jls.lang.loopWithTimeout')

local function onError(reason)
  print('Unexpected error: '..tostring(reason))
end

local function waitConnect(bs, delay)
  return Promise:new(function(resolve, reject)
    local function f()
      if bs.outgoingQueue then
        resolve(bs)
      else
        event:setTimeout(f, delay or 100)
      end
    end
    f()
  end)
 end

function Test_thread_stream()
  local result = nil
  local bs = BufferStream:new(4096)
  Thread:new(Thread.resolveUpValues(function(...)
    local ts = BufferStream:new(4096, ...)
    local n = 0
    ts:readStart(function(err, data)
      if err or not data or data == 'close' then
        ts:close()
      else
        n = n + 1
      end
    end)
    ts:write('x'):next(function()
      return ts:write('y')
    end):next(function()
      return ts:write('z')
    end):catch(print)
    event:loop()
    ts:close()
    return n
  end)):start(bs:openAsync()):ended():next(function(res)
    result = res
  end, onError)
  lu.assertNil(result)
  local recvCount = 0
  bs:readStart(function(err, data)
    recvCount = recvCount + 1
  end)
  waitConnect(bs):next(function()
    return bs:write('a')
  end):next(function()
    return bs:write('b')
  end):next(function()
    return bs:write('close')
  end):catch(onError)
  if not loop() then
    lu.fail('Timeout reached')
  end
  bs:close()
  lu.assertNotNil(result)
  lu.assertEquals(result, 2)
  lu.assertEquals(recvCount, 3)
end

os.exit(lu.LuaUnit.run())
