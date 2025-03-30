local event = require('jls.lang.event')
local system = require('jls.lang.system')
local tables = require('jls.util.tables')
local Url = require('jls.net.Url')
local mqtt = require('jls.net.mqtt')

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  emptyPath = 'url',
  logPath = 'log-level',
  aliases = {
    h = 'help',
    ll = 'log-level',
  },
  schema = {
    title = 'MQTT client and server',
    description = [[Allows to publish or subscribe to a MQTT broker.
Allows to start a MQTT broker.]],
    type = 'object',
    additionalProperties = false,
    properties = {
      url = {
        title = 'The broker URL, used for both client and server',
        type = 'string',
        pattern = '^tcp://.+:%d+$',
        default = 'tcp://localhost:1883'
      },
      topic = {
        title = 'The topic used to publish',
        type = 'string',
        default = 'default'
      },
      publish = {
        title = 'The message to publish, disable the subscribe',
        type = 'string'
      },
      pub = {
        title = 'The message to publish after subscribed',
        type = 'string'
      },
      subscribe = {
        title = 'The topic to subscribe to, the topic and message are print to stdout',
        type = 'string',
        default = '#'
      },
      mode = {
        title = 'The mode to use',
        type = 'string',
        default = 'client',
        enum = {'client', 'server', 'both'},
      },
      bindOnAny = {
        title = 'true to indicate that the server will be bound on all interfaces',
        type = 'boolean',
        default = true
      },
      qos = {
        type = 'integer',
        default = 0,
        minimum = 0,
        maximum = 3
      },
      retain = {
        title = 'retain the message for future subscribers',
        type = 'boolean',
        default = false
      },
      ping = {
        title = 'sends a ping, disable publish/subscribe',
        type = 'boolean',
        default = false
      },
      connect = {
        title = 'connects and close, disable publish/subscribe',
        type = 'boolean',
        default = false
      },
    }
  }
})

local tUrl = Url.parse(options.url)
local mqttClient, mqttServer

local function client()
  if options.mode == 'client' or options.mode == 'both' then
    mqttClient = mqtt.MqttClient:new()
    function mqttClient:onMessage(topicName, payload)
      print(topicName, payload)
    end
    mqttClient:connect(tUrl.host, tUrl.port):next(function()
      if options.connect then
        print('connected')
        mqttClient:close()
      elseif options.ping then
        mqttClient:ping():next(function()
          print('pong')
          mqttClient:close()
        end)
      elseif options.publish then
        mqttClient:publish(options.topic, options.publish, options):next(function()
          print('published', options.topic)
          mqttClient:close()
        end)
      else
        mqttClient:subscribe(options.subscribe, options.qos):next(function()
          print('subscribed', options.subscribe)
          if options.pub then
            mqttClient:publish(options.topic, options.pub, options):next(function()
              print('pub', options.topic)
            end)
          end
        end)
      end
    end)
  end
end

if options.mode == 'server' or options.mode == 'both' then
  mqttServer = mqtt.MqttServer:new()
  mqttServer:bind(not options.bindOnAny and tUrl.host or nil, tUrl.port):next(function()
    print('bound', tUrl.port)
    client()
  end)
else
  client()
end

event:loop()
