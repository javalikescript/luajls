local lu = require('luaunit')

local TcpSocket = require('jls.net.TcpSocket')
local StreamHandler = require('jls.io.StreamHandler')

local loop = require('jls.lang.loopWithTimeout')

local TEST_HOST, TEST_PORT = '127.0.0.1', 3002

function Test_TcpClient_TcpServer()
  local server = TcpSocket:new()
  assert(server:bind(TEST_HOST, TEST_PORT))
  function server:onAccept(client)
    client:readStart(StreamHandler:new(function(_, data)
      if data then
        client:write(data)
      else
        client:close()
        server:close()
      end
    end))
  end
  local client = TcpSocket:new()
  local receivedData
  client:connect(TEST_HOST, TEST_PORT):next(function(err)
    client:readStart(StreamHandler:new(function(_, data)
      if data then
        receivedData = data
      end
      client:close()
    end))
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

function Test_TcpClient_TcpServer_table()
  local t = {'Received: '}
  local server = TcpSocket:new()
  assert(server:bind(TEST_HOST, TEST_PORT))
  function server:onAccept(client)
    client:readStart(StreamHandler:new(function(_, data)
      if data then
        table.insert(t, data)
        if string.find(data, '\n$') then
          client:write(t)
        end
      else
        client:close()
        server:close()
      end
    end))
  end
  local client = TcpSocket:new()
  local u = {}
  client:connect(TEST_HOST, TEST_PORT):next(function(err)
    client:readStart(StreamHandler:new(function(_, data)
      if data then
        table.insert(u, data)
      end
      client:close()
    end))
    client:write({'Hello, ', 'My name is ', 'John\n'})
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(table.concat(u), 'Received: Hello, My name is John\n')
end

os.exit(lu.LuaUnit.run())
