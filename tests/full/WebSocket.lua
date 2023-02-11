local lu = require('luaunit')

local loop = require('jls.lang.loopWithTimeout')
local Map = require('jls.util.Map')
local WebSocket = require('jls.net.http.WebSocket')
local HttpServer = require('jls.net.http.HttpServer')

local TEST_PORT = 3002

function Test_send_receive()
  local server = HttpServer:new()
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
  server:bind('::', TEST_PORT)
  local webSocket = WebSocket:new('ws://127.0.0.1:'..tostring(TEST_PORT)..'/ws/')
  webSocket:open():next(function()
    function webSocket:onTextMessage(payload)
      reply = payload
      webSocket:close()
    end
    webSocket:readStart()
    webSocket:sendTextMessage('Hello')
  end)
  if not loop(function()
    webSocket:close()
    server:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(reply, 'You said Hello')
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
