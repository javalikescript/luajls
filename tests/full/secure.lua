local lu = require('luaunit')

local loader = require('jls.lang.loader')
local secure = require('jls.net.secure')
local TcpSocket = secure.TcpSocket
local StreamHandler = require('jls.io.StreamHandler')

local loop = require('jls.lang.loopWithTimeout')

local genCertificateAndPKey = loader.load('tests.genCertificateAndPKey')
local CACERT_PEM, PKEY_PEM = genCertificateAndPKey()

local TEST_HOST, TEST_PORT = '127.0.0.1', 3002

local function prepareServer(server)
  -- reuse previous context
  local secureContext = secure.Context:new({
    key = PKEY_PEM,
    certificate = CACERT_PEM
  })
  server:setSecureContext(secureContext)
end

function Test_TcpClient_TcpServer()
  local payload = 'Hello'
  --payload = string.rep('1234567890', 10000)
  local server = TcpSocket:new()
  prepareServer(server)
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
  client:setSecureContext({peerVerify = false})
  local u = {}
  server:bind(TEST_HOST, TEST_PORT):next(function()
    client:connect(TEST_HOST, TEST_PORT):next(function(err)
      client:readStart(StreamHandler:new(function(_, data)
        if data then
          table.insert(u, (string.gsub(data, '%c', '')))
          if string.find(data, '\n') then
            client:close()
          end
        else
          client:close()
        end
      end))
      client:write(payload)
      client:write('\n')
    end)
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(table.concat(u), payload)
end

function Test_TcpClient_TcpServer_table()
  local t = {'Received: '}
  local server = TcpSocket:new()
  prepareServer(server)
  function server:onAccept(client)
    client:readStart(StreamHandler:new(function(_, data)
      if data then
        table.insert(t, data)
        if string.find(data, '\n') then
          client:write(t)
        end
      else
        client:close()
        server:close()
      end
    end))
  end
  local client = TcpSocket:new()
  client:setSecureContext({peerVerify = false})
  local u = {}
  server:bind(TEST_HOST, TEST_PORT):next(function()
    client:connect(TEST_HOST, TEST_PORT):next(function(err)
      client:readStart(StreamHandler:new(function(_, data)
        if data then
          table.insert(u, (string.gsub(data, '%c', '')))
          if string.find(data, '\n') then
            client:close()
          end
        else
          client:close()
        end
      end))
      client:write({'Hello, ', 'My name is ', 'John', '\n'})
    end)
  end)
  if not loop(function()
    client:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(table.concat(u), 'Received: Hello, My name is John')
end

os.exit(lu.LuaUnit.run())
