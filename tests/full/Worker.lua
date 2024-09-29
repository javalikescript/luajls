local lu = require('luaunit')

local logger = require('jls.lang.logger')
local Worker = require('jls.util.Worker')
local loop = require('jls.lang.loopWithTimeout')

local function assertPostReceive(withData, scheme, disableReceive)
  local received = nil
  local f
  if disableReceive and not scheme then
    f = function(w, d)
      local logr = require('jls.lang.logger')
      local sys = require('jls.lang.system')
      logr:info('initializing worker %s receive disabled', withData)
      local suffix = d and tostring(d) or '-'
      local message = 'Hi '..suffix
      if w:isConnected() then
        logr:info('worker is connected')
        w:postMessage(message)
        logr:info('posted in worker "%s"', message)
        while w:isConnected() and not w._remote do
          sys.sleep(100)
        end
      else
        logr:info('not connected')
      end
      logr:info('ending worker')
    end
  else
    f = function(w, d)
      local logr = require('jls.lang.logger')
      logr:info('initializing worker %s, %s, %s', withData, scheme, disableReceive)
      local suffix = d and (', '..tostring(d)) or ''
      function w:onMessage(message)
        logr:info('received in worker "%s"', message)
        local reply = 'Hi '..tostring(message)..suffix
        w:postMessage(reply)
        logr:info('posted in worker "%s"', reply)
      end
    end
  end
  local w = Worker:new(f, withData and 'cheers' or nil, function(self, message)
    logger:info('received from worker "%s"', message)
    received = message
    self:close()
  end, {scheme = scheme, disableReceive = disableReceive})
  if not disableReceive then
    logger:info('posting')
    w:postMessage('John')
  end
  logger:info('looping')
  if not loop(function()
    w:close()
  end) then
    lu.fail('Timeout reached')
  end
  if disableReceive then
    lu.assertEquals(received, withData and 'Hi cheers' or 'Hi -')
  else
    lu.assertEquals(received, withData and 'Hi John, cheers' or 'Hi John')
  end
end

function Test_default()
  assertPostReceive()
end

function Test_default_with_data()
  assertPostReceive(true)
end

function Test_TCP()
  assertPostReceive(false, 'tcp')
end

function Test_disable_receive()
  assertPostReceive(false, nil, true)
end

function Test_disable_receive_with_data()
  assertPostReceive(true, nil, true)
end

os.exit(lu.LuaUnit.run())
