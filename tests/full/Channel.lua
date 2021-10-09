local lu = require('luaunit')

local logger = require('jls.lang.logger')
local loop = require('jls.lang.loader').load('loop', 'tests', false, true)
local Channel = require('jls.util.Channel')

function Test_channel()
  local receivedMessage
  local channelServer = Channel:new()
  local channel = Channel:new()
  local acceptedChannel
  local function closeAll(reason)
    print('Close all '..(reason or ''))
    channelServer:close(false)
    channel:close(false)
    if acceptedChannel then
      acceptedChannel:close(false)
    end
    if reason then
      lu.fail(reason)
    end
  end
  channelServer:acceptAndClose():next(function(c)
    acceptedChannel = c
    acceptedChannel:receiveStart(function(message)
      receivedMessage = message
      acceptedChannel:receiveStop()
      acceptedChannel:close(false)
    end)
  end)
  channelServer:bind():next(function()
    local name = channelServer:getName()
    return channel:connect(name)
  end):next(function()
    channel:sendMessage('Hello')
  end):catch(function(r)
    closeAll('Listen or connect error: '..tostring(r))
  end)
  if not loop(closeAll) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(receivedMessage, 'Hello')
end

os.exit(lu.LuaUnit.run())
