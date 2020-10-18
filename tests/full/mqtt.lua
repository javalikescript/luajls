local lu = require('luaunit')

local logger = require('jls.lang.logger')
local loop = require('jls.lang.loader').load('loop', 'tests', false, true)
local mqtt = require('jls.net.mqtt')

function Test_pubsub()
  local hostname, port = 'localhost', 1883
  local topicName, payload = 'test', 'Hello world!'
  local topicNameReceived, payloadReceived

  local mqttServer = mqtt.MqttServer:new()
  local mqttClientSub = mqtt.MqttClient:new()
  function mqttClientSub:onPublish(topicName, payload, dup, qos, retain)
    logger:info('mqttClientSub:onPublish('..tostring(topicName)..')')
    topicNameReceived = topicName
    payloadReceived = payload
    self:close()
    mqttServer:close()
  end
  local mqttClientPub = mqtt.MqttClient:new()
  logger:info('mqttServer:bind()')
  mqttServer:bind():next(function()
    logger:info('mqttClientSub:connect()')
    return mqttClientSub:connect()
  end):next(function()
    logger:info('mqttClientSub:subscribe()')
    mqttClientSub:subscribe(topicName, 0)
    logger:info('mqttClientPub:connect()')
    return mqttClientPub:connect()
  end):next(function()
    logger:info('mqttClientPub:publish()')
    return mqttClientPub:publish(topicName, payload)
  end):next(function()
    logger:info('mqttClientPub:close()')
    mqttClientPub:close()
  end)
  if not loop(function()
    mqttServer:close()
    mqttClientPub:close()
  end) then
    lu.fail('Timeout reached')
  end
  lu.assertEquals(payloadReceived, payload)
end

os.exit(lu.LuaUnit.run())
