local lu = require('luaunit')

local TcpSocket = require('jls.net.TcpSocket')
local dns = require('jls.net.dns')
local StreamHandler = require('jls.io.StreamHandler')
local Promise = require('jls.lang.Promise')

local loop = require('jls.lang.loopWithTimeout')

local TEST_HOST, TEST_PORT = '127.0.0.1', 3002

function Test_TcpClient_TcpServer()
  local server = TcpSocket:new()
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
  server:bind(TEST_HOST, TEST_PORT):next(function()
    client:connect(TEST_HOST, TEST_PORT):next(function(err)
      client:readStart(StreamHandler:new(function(_, data)
        if data then
          receivedData = data
        end
        client:close()
      end))
      client:write('Hello')
    end)
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
  server:bind(TEST_HOST, TEST_PORT):next(function()
    client:connect(TEST_HOST, TEST_PORT):next(function(err)
      client:readStart(StreamHandler:new(function(_, data)
        if data then
          table.insert(u, data)
        end
        client:close()
      end))
      client:write({'Hello, ', 'My name is ', 'John\n'})
    end)
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(table.concat(u), 'Received: Hello, My name is John\n')
end

function Test_TcpClient_TcpServer_dual()
  local function send(data, host, port)
    --print('send', data, 'on', host, port)
    local client = TcpSocket:new()
    return client:connect(host, port):next(function(client)
      return client:write(data)
    end):finally(function()
      client:close()
    end)
  end
  local host = 'localhost'
  local t = {}
  local server = TcpSocket:new()
  local port, infos
  dns.getAddressInfo(host):next(function(l)
    infos = l
    if #infos == 2 then
      function server:onAccept(client)
        client:readStart(StreamHandler:new(function(_, data)
          if data then
            table.insert(t, data)
          else
            client:close()
          end
        end))
      end
      return server:bind(host, 0)
    end
    t = nil
  end):next(function()
    port = select(2, server:getLocalName())
    return send('1\n', infos[1].addr, port)
  end):next(function()
    return send('2\n', infos[2].addr, port)
  end):catch(function(reason)
    print('error', reason)
  end):finally(function()
    server:close()
  end)
  if not loop(function()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  if t then
    lu.assertEquals(t, {'1\n', '2\n'})
  else
    print('/!\\ skipping test as '..host..' resolves to '..tostring(#infos)..' addresses')
    for i, info in ipairs(infos) do
      print('', i, info.addr, info.family)
    end
    lu.success()
  end
end

function Test_Async()
  if _VERSION == 'Lua 5.1' then
    print('/!\\ skipping test due to Lua version')
    lu.success()
    return
  end
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
