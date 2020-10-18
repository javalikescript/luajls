local lu = require('luaunit')

local logger = require('jls.lang.logger')
local loop = require('jls.lang.loader').load('loop', 'tests', false, true)
local smt = require('jls.util.smt')

local function postReceive(payload, smtServer, smtClient, useTcp)
  logger:info('postReceive()')
  local resultClient, resultServer
  function smtServer:onMessage(payload)
    logger:info('server received message: "'..tostring(payload)..'"')
    resultServer = payload
  end
  function smtClient:onMessage(payload)
    logger:info('client received message: "'..tostring(payload)..'"')
    resultClient = payload
    self:close()
    smtServer:close()
  end
  local onClientRegistered = smtServer:onNextRegisteredClient()
  smtServer:bind(nil, 0):next(function ()
    logger:info('smtClient:connect()')
    if useTcp then
      return smtClient:connect(nil, smtServer:getTcpPort())
    end
    return smtClient:connect(smtServer:getPipeName())
  end):next(function()
    logger:info('client sending message')
    return smtClient:postMessage(payload)
  end):next(function()
    return onClientRegistered
  end):next(function(client)
    logger:info('server sending message')
    return client:postMessage(payload)
  end):catch(function(err)
    logger:warn(err)
  end)
  if not loop(function()
    smtClient:close()
    smtServer:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(resultClient, payload)
  lu.assertEquals(resultServer, payload)
end

function Test_smt_pipe()
  if not smt.SmtPipeServer then
    lu.success()
    return
  end
  postReceive('Hello Pipe!', smt.SmtPipeServer:new(), smt.SmtPipeClient:new(), false)
end

function Test_smt_tcp()
  if not smt.SmtTcpServer then
    lu.success()
    return
  end
  postReceive('Hello TCP!', smt.SmtTcpServer:new(), smt.SmtTcpClient:new(), true)
end

os.exit(lu.LuaUnit.run())
