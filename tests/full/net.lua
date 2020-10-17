local lu = require('luaunit')

local net = require('jls.net')
local streams = require('jls.io.streams')

local loop = require('tests.loop')

local logger = require('jls.lang.logger')

local TEST_PORT = 3002

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
  receiver:receiveStart(streams.CallbackStreamHandler:new(function(err, data)
    if err then
      logger:warn('receive error: "'..tostring(err)..'"')
    elseif data then
      logger:fine('received data: "'..tostring(data)..'"')
      receivedData = data
    end
    receiver:receiveStop()
    receiver:close()
  end))
  sender:send('Hello', host, port):finally(function(value)
    logger:warn('send value: "'..tostring(value)..'"')
    logger:fine('closing sender')
    sender:close()
  end)
  loop(function()
    sender:close()
    receiver:close()
  end)
  lu.assertEquals(receivedData, 'Hello')
end

os.exit(lu.LuaUnit.run())
