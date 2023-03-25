local lu = require('luaunit')

local TcpSocket = require('jls.net.TcpSocket')
local StreamHandler = require('jls.io.StreamHandler')
local Promise = require('jls.lang.Promise')

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

function Test_Async()
  local server = TcpSocket:new()
  local client = TcpSocket:new()
  Promise.async(function(await)
    local aClient
    local csh = StreamHandler.promises()
    local ssh = StreamHandler.promises()
    await(server:bind(TEST_HOST, TEST_PORT))
    function server:onAccept(c)
      c:readStart(ssh)
      aClient = c
    end
    await(client:connect(TEST_HOST, TEST_PORT))
    client:readStart(csh)
    client:write('Hi')
    lu.assertEquals(await(ssh:read()), 'Hi')
    aClient:write('Hello')
    lu.assertEquals(await(csh:read()), 'Hello')
    await(aClient:close())
    await(client:close())
    await(server:close())
    lu.assertNil(await(csh:read()))
    lu.assertNil(await(ssh:read()))
  end):catch(function(reason)
    print(reason)
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
end

os.exit(lu.LuaUnit.run())
