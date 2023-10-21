local lu = require('luaunit')

local logger = require('jls.lang.logger')
local loop = require('jls.lang.loopWithTimeout')
local mqtt = require('jls.net.mqtt')

function Test_pubsub()
  local hostname, port = 'localhost', 0
  local topicName, payload = 'test', 'Hello world!'
  local topicNameReceived, payloadReceived

  local mqttServer = mqtt.MqttServer:new()
  local mqttClientSub = mqtt.MqttClient:new()
  function mqttClientSub:onMessage(tn, pl)
    logger:info('mqttClientSub:onMessage(%s)', tn)
    topicNameReceived = tn
    payloadReceived = pl
    self:close()
    mqttServer:close()
  end
  local mqttClientPub = mqtt.MqttClient:new()
  logger:info('mqttServer:bind()')
  mqttServer:bind(nil, port):next(function()
    if port == 0 then
      port = select(2, mqttServer:getAddress())
      logger:info('mqttServer bound on %s', port)
    end
    logger:info('mqttClientSub:connect()')
    return mqttClientSub:connect(hostname, port)
  end):next(function()
    logger:info('mqttClientSub:subscribe()')
    mqttClientSub:subscribe(topicName, 0)
    logger:info('mqttClientPub:connect()')
    return mqttClientPub:connect(hostname, port)
  end):next(function()
    logger:info('mqttClientPub:publish()')
    return mqttClientPub:publish(topicName, payload)
  end):next(function()
    logger:info('mqttClientPub:close()')
    mqttClientPub:close()
  end):catch(function(reason)
    logger:warn('something goes wrong %s', reason)
    mqttServer:close()
    mqttClientPub:close()
    mqttClientSub:close()
  end)
  if not loop(function()
    mqttServer:close()
    mqttClientPub:close()
    mqttClientSub:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(payloadReceived, payload)
end

os.exit(lu.LuaUnit.run())
