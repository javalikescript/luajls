local lu = require('luaunit')

local event = require('jls.lang.event')
local net = require('jls.net')
local streams = require('jls.io.streams')

local TEST_PORT = 3002

function loop(onTimeout, timeout)
  local timeoutReached = false
  if not timeout then
    timeout = 5000
  end
  local timer = event:setTimeout(function()
    timeoutReached = true
    if type(onTimeout) == 'function' then
      if not pcall(onTimeout) then
        event:stop()
      end
    end
  end, timeout)
  event:daemon(timer, true)
  event:loop()
  if timeoutReached then
    lu.assertFalse(timeoutReached, 'timeout reached ('..tostring(timeout)..')')
  else
    event:clearTimeout(timer)
  end
end

function test_TcpClient_TcpServer()
  local server = net.TcpServer:new()
  assert(server:bind('0.0.0.0', TEST_PORT))
  function server:onAccept(client)
    local stream = streams.StreamHandler:new()
    function stream:onData(data)
      if data then
        client:write(data)
      else
        client:close()
        server:close()
      end
    end
    client:readStart(stream)
  end
  local client = net.TcpClient:new()
  local receivedData
  client:connect('127.0.0.1', TEST_PORT):next(function(err)
    local stream = streams.StreamHandler:new()
    function stream:onData(data)
      if data then
        receivedData = data
      end
      client:close()
    end
    client:readStart(stream)
    client:write('Hello')
  end)
  loop(function()
    client:close()
    server:close()
  end)
  lu.assertEquals(receivedData, 'Hello')
end

function test_UdpSocket()
  local host, port = '225.0.0.37', 12345
  local receivedData
  local receiver = net.UdpSocket:new()
  local sender = net.UdpSocket:new()
  receiver:bind('0.0.0.0', port, {reuseaddr = true})
  receiver:joinGroup(host, '0.0.0.0')
  local stream = streams.StreamHandler:new()
  function stream:onData(data)
    if data then
      receivedData = data
    end
    receiver:receiveStop()
    receiver:close()
  end
  receiver:receiveStart(stream)
  sender:send('Hello', host, port):next(function(err)
    sender:close()
  end)
  loop(function()
    sender:close()
    receiver:close()
  end)
  lu.assertEquals(receivedData, 'Hello')
end

os.exit(lu.LuaUnit.run())
