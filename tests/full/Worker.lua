local lu = require('luaunit')

local logger = require('jls.lang.logger')
local Worker = require('jls.util.Worker')
local loop = require('jls.lang.loopWithTimeout')

local function assertPostReceive(withData, scheme)
  local received = nil
  local w = Worker:new(function(w, d)
    local logr = require('jls.lang.logger')
    logr:info('initializing worker')
    local suffix = d and (', '..tostring(d)) or ''
    function w:onMessage(message)
      logr:info('received in worker "'..tostring(message)..'"')
      local reply = 'Hi '..tostring(message)..suffix
      w:postMessage(reply)
      logr:info('posted in worker "'..tostring(reply)..'"')
    end
  end, withData and 'cheers' or nil, scheme)
  function w:onMessage(message)
    logger:info('received from worker "'..tostring(message)..'"')
    received = message
    self:close()
  end
  lu.assertNil(received)
  logger:info('posting')
  w:postMessage('John')
  logger:info('looping')
  if not loop(function()
    w:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(received, withData and 'Hi John, cheers' or 'Hi John')
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

os.exit(lu.LuaUnit.run())
