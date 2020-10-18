local lu = require('luaunit')

local loader = require('jls.lang.loader')
local logger = require('jls.lang.logger')
local Worker = require('jls.util.Worker')
local loop = loader.load('loop', 'tests', false, true)

local function assertPostReceive()
  local received = nil
  local w = Worker:new(function(w)
    local logger = require('jls.lang.logger')
    logger:info('initializing worker')
    function w:onMessage(message)
      logger:info('received in worker "'..tostring(message)..'"')
      w:postMessage('Hi '..tostring(message))
    end
  end)
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
  lu.assertEquals(received, 'Hi John')
end

function Test_default()
  assertPostReceive()
end

function _Test_TCP()
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
