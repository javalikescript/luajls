local lu = require('luaunit')

local TcpClient = require('jls.net.TcpClient')
local TcpServer = require('jls.net.TcpServer')
local StreamHandler = require('jls.io.streams.StreamHandler')

local loop = require('jls.lang.loader').load('loop', 'tests', false, true)

local TEST_PORT = 3002

function Test_TcpClient_TcpServer()
  local server = TcpServer:new()
  assert(server:bind('0.0.0.0', TEST_PORT))
  function server:onAccept(client)
    local stream = StreamHandler:new()
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
  local client = TcpClient:new()
  local receivedData
  client:connect('127.0.0.1', TEST_PORT):next(function(err)
    local stream = StreamHandler:new()
    function stream:onData(data)
      if data then
        receivedData = data
      end
      client:close()
    end
    client:readStart(stream)
    client:write('Hello')
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(receivedData, 'Hello')
end

os.exit(lu.LuaUnit.run())
