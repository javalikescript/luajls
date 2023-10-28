local lu = require('luaunit')

local loader = require('jls.lang.loader')
local loop = require('jls.lang.loopWithTimeout')
local Map = require('jls.util.Map')
local WebSocket = require('jls.net.http.WebSocket')
local HttpServer = require('jls.net.http.HttpServer')

local genCertificateAndPKey = loader.load('tests.genCertificateAndPKey')

local CACERT_PEM, PKEY_PEM = genCertificateAndPKey()
local TEST_PORT = 3002

local function assert_send_receive(withH2)
  local scheme = 'ws'
  local server
  if withH2 then
    scheme = scheme..'s'
    server = HttpServer.createSecure({
      key = PKEY_PEM,
      certificate = CACERT_PEM,
      alpnSelectProtos = {'h2'}
    })
  else
    server = HttpServer:new()
  end
  local reply
  server:createContext('/ws/', Map.assign(WebSocket.UpgradeHandler:new(), {
    onOpen = function(_, webSocket, exchange)
      function webSocket:onTextMessage(payload)
        webSocket:sendTextMessage('You said '..payload):next(function()
          webSocket:close()
          server:close()
        end)
      end
      webSocket:readStart()
    end
  }))
  local webSocket = WebSocket:new(scheme..'://127.0.0.1:'..tostring(TEST_PORT)..'/ws/')
  server:bind('::', TEST_PORT):next(function()
    webSocket:open():next(function()
      function webSocket:onTextMessage(payload)
        reply = payload
        webSocket:close()
      end
      webSocket:readStart()
      webSocket:sendTextMessage('Hello')
    end)
  end)
  if not loop(function()
    webSocket:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(reply, 'You said Hello')
end

function Test_send_receive()
  assert_send_receive()
end

function Test_send_receive_h2()
  assert_send_receive(true)
end

function Test_applyMask()
  local values = {'', 'a', 'ab', 'abc', 'abcd', 'abcde'}
  local mask = WebSocket.generateMask()
  for _, value in ipairs(values) do
    local maskedValue = WebSocket.applyMask(mask, value)
    lu.assertEquals(#maskedValue, #value)
    if value ~= '' then
      lu.assertNotEquals(maskedValue, value)
    end
    lu.assertEquals(WebSocket.applyMask(mask, maskedValue), value)
  end
end

function _Test_applyMask_perf()
  local value = WebSocket.randomChars(8195)
  local mask = WebSocket.generateMask()
  for _ = 1, 1000 do
    WebSocket.applyMask(mask, value)
  end
end

os.exit(lu.LuaUnit.run())
