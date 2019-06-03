local lu = require('luaunit')

local event = require('jls.lang.event')
local http = require('jls.net.http')
local ws = require('jls.net.http.ws')

local TEST_PORT = 3002

function test_send_receive()
  local server = http.Server:new()
  local reply
  server:createContext('/ws/', ws.upgradeHandler, {open = function(webSocket)
    function webSocket:onTextMessage(payload)
      webSocket:sendTextMessage('You said '..payload):next(function()
        webSocket:close()
        server:close()
      end)
    end
    webSocket:readStart()
  end})
  server:bind('::', TEST_PORT)
  local webSocket = ws.WebSocket:new('ws://127.0.0.1:'..tostring(TEST_PORT)..'/ws/')
  webSocket:open():next(function()
    function webSocket:onTextMessage(payload)
      reply = payload
      webSocket:close()
    end
    webSocket:readStart()
    webSocket:sendTextMessage('Hello')
  end)
  event:loop()
  lu.assertEquals(reply, 'You said Hello')
end

os.exit(lu.LuaUnit.run())
