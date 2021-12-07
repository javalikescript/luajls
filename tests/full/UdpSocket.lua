local lu = require('luaunit')

local UdpSocket = require('jls.net.UdpSocket')
local logger = require('jls.lang.logger')

local loop = require('jls.lang.loopWithTimeout')

function Test_UdpSocket()
  local host, port = '225.0.0.37', 12345
  local receivedData
  local receiver = UdpSocket:new()
  local sender = UdpSocket:new()
  receiver:bind('0.0.0.0', port, {reuseaddr = true})
  receiver:joinGroup(host, '0.0.0.0')
  receiver:receiveStart(function(err, data)
    if err then
      logger:warn('receive error: "'..tostring(err)..'"')
    elseif data then
      logger:fine('received data: "'..tostring(data)..'"')
      receivedData = data
    end
    receiver:receiveStop()
    receiver:close()
  end)
  sender:send('Hello', host, port):finally(function(value)
    logger:warn('send value: "'..tostring(value)..'"')
    logger:fine('closing sender')
    sender:close()
  end)
  if not loop(function()
    sender:close()
    receiver:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(receivedData, 'Hello')
end

os.exit(lu.LuaUnit.run())
