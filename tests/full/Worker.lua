local lu = require('luaunit')

local loader = require('jls.lang.loader')
local logger = require('jls.lang.logger')
local Worker = require('jls.util.Worker')
local loop = loader.load('loop', 'tests', false, true)

Tests = {}

--function Tests:tearDown()
--  Worker.shutdown()
--end

local function assertPostReceive(withData)
  local received = nil
  local w = Worker:new(function(w, d)
    local logr = require('jls.lang.logger')
    logr:info('initializing worker')
    local suffix = d and (', '..tostring(d)) or ''
    function w:onMessage(message)
      logr:info('received in worker "'..tostring(message)..'"')
      w:postMessage('Hi '..tostring(message)..suffix)
    end
  end, withData and 'cheers' or nil)
  function w:onMessage(message)
    logger:info('received from worker "'..tostring(message)..'"')
    received = message
    self:close()
    Worker.shutdown()
  end
  lu.assertNil(received)
  logger:info('posting')
  w:postMessage('John')
  logger:info('looping')
  if not loop(function()
    w:close()
    Worker.shutdown()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(received, withData and 'Hi John, cheers' or 'Hi John')
end

function Tests:test_default()
  assertPostReceive()
end

function Tests:test_default_with_data()
  assertPostReceive(true)
end

function Tests:_test_TCP()
  if not Worker.WorkerServer then
    lu.success()
    return
  end
  loader.unload('jls.util.Worker')
  local smt = require('jls.util.smt')
  smt.SmtPipeServer = nil
  Worker = require('jls.util.Worker')
  assertPostReceive()
  loader.unload('jls.util.smt')
  loader.unload('jls.util.Worker')
  Worker = require('jls.util.Worker')
end

os.exit(lu.LuaUnit.run())
