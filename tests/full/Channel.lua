local lu = require('luaunit')

local loader = require('jls.lang.loader')
local event = require('jls.lang.event')
local loop = require('jls.lang.loopWithTimeout')
local Channel = require('jls.util.Channel')

local function test_channel(scheme)
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
  channelServer:bind(false, scheme):next(function()
    local name = channelServer:getName()
    return channel:connect(name)
  end):next(function()
    channel:writeMessage('Hello')
  end):catch(function(r)
    closeAll('Listen or connect error: '..tostring(r))
  end)
  if not loop(closeAll) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(receivedMessage, 'Hello')
end

function Test_channel_pipe()
  if event ~= loader.getRequired('jls.lang.event-luv') then
    print('/!\\ skipping pipe test')
    lu.success()
  end
  test_channel('pipe')
end

function Test_channel_tcp()
  test_channel('tcp')
end

os.exit(lu.LuaUnit.run())
