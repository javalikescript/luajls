--- This module provide classes to work with MQTT.
-- see http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html
-- @module jls.net.mqtt

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local net = require('jls.net')
local Promise = require('jls.lang.Promise')
local streams = require('jls.io.streams')
local integers = require('jls.util.integers')
local hex = require('jls.util.hex')

--[[
  mosquitto -v
  mosquitto_pub -t test -m hello
  mosquitto_sub -t test
]]

--local function encodeByte(value) return integers.fromUInt8(value) end
--local function decodeByte(value, offset) return integers.toUInt8(value, offset) end
--local function encodeUInt16(value) return integers.be.fromUInt16(value) end

local encodeByte = integers.fromUInt8
local encodeBytes = string.char
local encodeUInt16 = integers.be.fromUInt16
local encodeUInt32 = integers.be.fromUInt32

local decodeByte = integers.toUInt8
local decodeBytes = string.byte
local decodeUInt16 = integers.be.toUInt16
local decodeUInt32 = integers.be.toUInt32

local function encodeData(data)
  return encodeUInt16(#data)..data
end

local function decodeData(s, offset)
  offset = offset or 1
  local len = decodeUInt16(s, offset)
  if len <= 0 then
    return '', offset + 2
  end
  return string.sub(s, offset + 2, offset + 1 + len), offset + 2 + len
end

local function encodeVariableByteInteger(i)
  if i < 0 then
    return nil
  elseif i < 128 then
    return string.char(i)
  elseif i < 16384  then
    return string.char(0x80 | (i & 0x7f), (i >> 7) & 0x7f)
  elseif i < 2097152  then
    return string.char(0x80 | (i & 0x7f), 0x80 | ((i >> 7) & 0x7f), (i >> 14) & 0x7f)
  elseif i <= 268435455  then
    return string.char(0x80 | (i & 0x7f), 0x80 | ((i >> 7) & 0x7f), 0x80 | ((i >> 14) & 0x7f), (i >> 21) & 0x7f)
  end
  return nil
end

local function decodeVariableByteInteger(s, offset)
  offset = offset or 1
  local i = 0
  for l = 0, 3 do
    local b = decodeByte(s, offset + l)
    i = (i << 7) | (b & 0x7f)
    if (b & 0x80) ~= 0x80 then
      return i, offset + l + 1
    end
  end
  return nil
end

local function encodePacket(packetType, data, packetFlags)
  if not packetFlags then
    packetFlags = 0
  end
  local packetTypeAndFlags = ((packetType & 0xf) << 4) | (packetFlags & 0xf)
  if data then
    return encodeByte(packetTypeAndFlags)..encodeVariableByteInteger(#data)..data
  else
    return encodeByte(packetTypeAndFlags)
  end
end

local CONTROL_PACKET_TYPE = {
  CONNECT = 1, -- Client to Server -- Connection request
  CONNACK = 2, -- Server to Client -- Connect acknowledgment
  PUBLISH = 3, -- Client to Server or Server to Client -- Publish message
  PUBACK = 4, -- Client to Server or Server to Client -- Publish acknowledgment (QoS 1)
  PUBREC = 5, -- Client to Server or Server to Client -- Publish received (QoS 2 delivery part 1)
  PUBREL = 6, -- Client to Server or Server to Client -- Publish release (QoS 2 delivery part 2)
  PUBCOMP = 7, -- Client to Server or Server to Client -- Publish complete (QoS 2 delivery part 3)
  SUBSCRIBE = 8, -- Client to Server -- Subscribe request
  SUBACK = 9, -- Server to Client -- Subscribe acknowledgment
  UNSUBSCRIBE = 10, -- Client to Server -- Unsubscribe request
  UNSUBACK = 11, -- Server to Client -- Unsubscribe acknowledgment
  PINGREQ = 12, -- Client to Server -- PING request
  PINGRESP = 13, -- Server to Client -- PING response
  DISCONNECT = 14, -- Client to Server or Server to Client -- Disconnect notification
  AUTH = 15, -- Client to Server or Server to Client -- Authentication exchange
}

local REASON_CODE = {
  SUCCESS = 0, -- 0x00 -- Success -- CONNACK, PUBACK, PUBREC, PUBREL, PUBCOMP, UNSUBACK, AUTH
  NORMAL_DISCONNECTION = 0, -- 0x00 -- Normal disconnection -- DISCONNECT
  GRANTED_QOS_0 = 0, -- 0x00 -- Granted QoS 0 -- SUBACK
  GRANTED_QOS_1 = 1, -- 0x01 -- Granted QoS 1 -- SUBACK
  GRANTED_QOS_2 = 2, -- 0x02 -- Granted QoS 2 -- SUBACK
  DISCONNECT_WITH_WILL_MESSAGE = 4, -- 0x04 -- Disconnect with Will Message -- DISCONNECT
  NO_MATCHING_SUBSCRIBERS = 16, -- 0x10 -- No matching subscribers -- PUBACK, PUBREC
  NO_SUBSCRIPTION_EXISTED = 17, -- 0x11 -- No subscription existed -- UNSUBACK
  CONTINUE_AUTHENTICATION = 24, -- 0x18 -- Continue authentication -- AUTH
  RE_AUTHENTICATE = 25, -- 0x19 -- Re-authenticate -- AUTH
  UNSPECIFIED_ERROR = 128, -- 0x80 -- Unspecified error -- CONNACK, PUBACK, PUBREC, SUBACK, UNSUBACK, DISCONNECT
  MALFORMED_PACKET = 129, -- 0x81 -- Malformed Packet -- CONNACK, DISCONNECT
  PROTOCOL_ERROR = 130, -- 0x82 -- Protocol Error -- CONNACK, DISCONNECT
  IMPLEMENTATION_SPECIFIC_ERROR = 131, -- 0x83 -- Implementation specific error -- CONNACK, PUBACK, PUBREC, SUBACK, UNSUBACK, DISCONNECT
  UNSUPPORTED_PROTOCOL_VERSION = 132, -- 0x84 -- Unsupported Protocol Version -- CONNACK
  CLIENT_IDENTIFIER_NOT_VALID = 133, -- 0x85 -- Client Identifier not valid -- CONNACK
  BAD_USER_NAME_OR_PASSWORD = 134, -- 0x86 -- Bad User Name or Password -- CONNACK
  NOT_AUTHORIZED = 135, -- 0x87 -- Not authorized -- CONNACK, PUBACK, PUBREC, SUBACK, UNSUBACK, DISCONNECT
  SERVER_UNAVAILABLE = 136, -- 0x88 -- Server unavailable -- CONNACK
  SERVER_BUSY = 137, -- 0x89 -- Server busy -- CONNACK, DISCONNECT
  BANNED = 138, -- 0x8A -- Banned -- CONNACK
  SERVER_SHUTTING_DOWN = 139, -- 0x8B -- Server shutting down -- DISCONNECT
  BAD_AUTHENTICATION_METHOD = 140, -- 0x8C -- Bad authentication method -- CONNACK, DISCONNECT
  KEEP_ALIVE_TIMEOUT = 141, -- 0x8D -- Keep Alive timeout -- DISCONNECT
  SESSION_TAKEN_OVER = 142, -- 0x8E -- Session taken over -- DISCONNECT
  TOPIC_FILTER_INVALID = 143, -- 0x8F -- Topic Filter invalid -- SUBACK, UNSUBACK, DISCONNECT
  TOPIC_NAME_INVALID = 144, -- 0x90 -- Topic Name invalid -- CONNACK, PUBACK, PUBREC, DISCONNECT
  PACKET_IDENTIFIER_IN_USE = 145, -- 0x91 -- Packet Identifier in use -- PUBACK, PUBREC, SUBACK, UNSUBACK
  PACKET_IDENTIFIER_NOT_FOUND = 146, -- 0x92 -- Packet Identifier not found -- PUBREL, PUBCOMP
  RECEIVE_MAXIMUM_EXCEEDED = 147, -- 0x93 -- Receive Maximum exceeded -- DISCONNECT
  TOPIC_ALIAS_INVALID = 148, -- 0x94 -- Topic Alias invalid -- DISCONNECT
  PACKET_TOO_LARGE = 149, -- 0x95 -- Packet too large -- CONNACK, DISCONNECT
  MESSAGE_RATE_TOO_HIGH = 150, -- 0x96 -- Message rate too high -- DISCONNECT
  QUOTA_EXCEEDED = 151, -- 0x97 -- Quota exceeded -- CONNACK, PUBACK, PUBREC, SUBACK, DISCONNECT
  ADMINISTRATIVE_ACTION = 152, -- 0x98 -- Administrative action -- DISCONNECT
  PAYLOAD_FORMAT_INVALID = 153, -- 0x99 -- Payload format invalid -- CONNACK, PUBACK, PUBREC, DISCONNECT
  RETAIN_NOT_SUPPORTED = 154, -- 0x9A -- Retain not supported -- CONNACK, DISCONNECT
  QOS_NOT_SUPPORTED = 155, -- 0x9B -- QoS not supported -- CONNACK, DISCONNECT
  USE_ANOTHER_SERVER = 156, -- 0x9C -- Use another server -- CONNACK, DISCONNECT
  SERVER_MOVED = 157, -- 0x9D -- Server moved -- CONNACK, DISCONNECT
  SHARED_SUBSCRIPTIONS_NOT_SUPPORTED = 158, -- 0x9E -- Shared Subscriptions not supported -- SUBACK, DISCONNECT
  CONNECTION_RATE_EXCEEDED = 159, -- 0x9F -- Connection rate exceeded -- CONNACK, DISCONNECT
  MAXIMUM_CONNECT_TIME = 160, -- 0xA0 -- Maximum connect time -- DISCONNECT
  SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED = 161, -- 0xA1 -- Subscription Identifiers not supported -- SUBACK, DISCONNECT
  WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED = 162, -- 0xA2 -- Wildcard Subscriptions not supported -- SUBACK, DISCONNECT
}

local CONNECT_FLAGS = {
  USER_NAME = 1 << 7,
  PASSWORD = 1 << 6,
  WILL_RETAIN = 1 << 5,
  WILL_QOS_1 = 1 << 4,
  WILL_QOS_2 = 1 << 3,
  WILL_FLAG = 1 << 2,
  CLEAN_START = 1 << 1,
}

--local CLIENT_ID_CHARS = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'

local CLIENT_ID_PREFIX = 'JLS'..hex.encode(encodeUInt32(system.currentTime()))
local CLIENT_ID_UID = 0

local function nextClientId()
  CLIENT_ID_UID = CLIENT_ID_UID + 1
  return CLIENT_ID_PREFIX..hex.encode(encodeUInt32(CLIENT_ID_UID))
end

local PROTOCOL_NAME = 'MQTT'
local PROTOCOL_LEVEL = 4

local MqttClientBase = class.create(function(mqttClientBase)

  function mqttClientBase:initialize(tcp)
    logger:finer('mqttClientBase:initialize(...)')
    self.tcpClient = tcp
  end

  function mqttClientBase:getClientId()
    return self.clientId
  end

  function mqttClientBase:getKeepAlive()
    return self.keepAlive
  end

  function mqttClientBase:onReadError(err)
    if logger:isLoggable(logger.FINE) then
      logger:fine('mqttClientBase:onReadError("'..tostring(err)..'") '..tostring(self.clientId))
    end
  end

  function mqttClientBase:onReadEnded()
    if logger:isLoggable(logger.FINE) then
      logger:fine('mqttClientBase:onReadEnded() '..tostring(self.clientId))
    end
  end

  function mqttClientBase:onPublish(topicName, payload, dup, qos, retain)
    if logger:isLoggable(logger.FINER) then
      logger:finer('mqttClientBase:onPublish("'..tostring(topicName)..'", "'..tostring(payload)..'", dup: '..tostring(dup)..', qos: '..tostring(qos)..', retain: '..tostring(retain)..') '..tostring(self.clientId))
    end
  end

  function mqttClientBase:onReadPacket(packetType, packetFlags, data, offset, len)
    if logger:isLoggable(logger.FINER) then
      logger:finer('mqttClientBase:onReadPacket('..tostring(packetType)..') '..tostring(self.clientId))
    end
    if packetType == CONTROL_PACKET_TYPE.PUBLISH then
      local dup = packetFlags & 8 ~= 0
      local qos = (packetFlags >> 1) & 3
      local retain = packetFlags & 1 ~= 0
      if logger:isLoggable(logger.FINER) then
        logger:finer('publish dup: '..tostring(dup)..', qos: '..tostring(qos)..', retain: '..tostring(retain))
      end
      local topicName, packetIdentifier
      topicName, offset = decodeData(data, offset)
      if qos > 0 then
        packetIdentifier = decodeUInt16(data, offset)
        offset = offset + 2
      end
      local payload = string.sub(data, offset)
      self:onPublish(topicName, payload, dup, qos, retain)
      if qos == 1 then
        self:writePacket(CONTROL_PACKET_TYPE.PUBACK, encodeUInt16(packetIdentifier))
      elseif qos == 2 then
        self:writePacket(CONTROL_PACKET_TYPE.PUBREC, encodeUInt16(packetIdentifier))
      end
    end
  end

  function mqttClientBase:readStart()
    -- stream implementation that buffers and splits packets
    local buffer = ''
    return self.tcpClient:readStart(function(err, data)
      if err then
        self:onReadError(err)
      elseif data then
        buffer = buffer..data
        while true do
          local bufferLength = #buffer
          if bufferLength < 2 then
            break
          end
          local packetTypeAndFlags = decodeByte(buffer, 1)
          local remainingLength, offset = decodeVariableByteInteger(buffer, 2)
          local packetLength = offset - 1 + remainingLength
          if bufferLength < packetLength then
            break
          end
          local remainingBuffer
          if bufferLength == packetLength then
            remainingBuffer = ''
          else
            remainingBuffer = string.sub(buffer, packetLength + 1)
            buffer = string.sub(buffer, 1, packetLength)
          end
          if logger:isLoggable(logger.FINEST) then
            logger:finest('mqttClientBase:read '..tostring(self.clientId)..' "'..hex.encode(buffer)..'"')
          end
          self:onReadPacket(packetTypeAndFlags >> 4, packetTypeAndFlags & 0xf, buffer, offset, remainingLength)
          buffer = remainingBuffer
        end
      else
        self:onReadEnded(err)
      end
    end)
  end

  function mqttClientBase:write(data, callback)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('mqttClientBase:write() "'..hex.encode(data)..'"')
    end
    return self.tcpClient:write(data, callback)
  end

  function mqttClientBase:writePacket(packetType, data, packetFlags, callback)
    local packet = encodePacket(packetType, data, packetFlags)
    return self:write(packet, callback)
  end

  function mqttClientBase:close(callback)
    return self.tcpClient:close(callback)
  end

  function mqttClientBase:publish(topicName, payload)
    if logger:isLoggable(logger.FINER) then
      logger:finer('mqttClientBase:publish("'..tostring(topicName)..'", "'..tostring(payload)..'") '..tostring(self.clientId))
    end
    local qos = 0
    local packetFlags = 0 -- TODO dup, qos and retain
    local data = encodeData(topicName)
    if qos > 0 then
      local packetIdentifier = 0 -- TODO
      data = data..encodeUInt16(packetIdentifier)
    end
    if payload then
      data = data..payload
    end
    return self:writePacket(CONTROL_PACKET_TYPE.PUBLISH, data, packetFlags)
  end

end)

--[[--
The MqttClient class enables to Publish and Subscribe to Application Messages.
@usage
local event = require('jls.lang.event')
local mqtt = require('jls.net.mqtt')

local topicName, payload = 'test', 'Hello world!'
local mqttClient = mqtt.MqttClient:new()
mqttClient:connect():next(function()
  return mqttClient:publish(topicName, payload)
end):next(function()
  mqttClient:close()
end)

event:loop()
event:close()
@type MqttClient
]]
local MqttClient = class.create(MqttClientBase, function(mqttClient, super)

  --- Creates a new MQTT client.
  -- @function MqttClient:new
  -- @return a new MQTT client
  function mqttClient:initialize(options)
    logger:finer('mqttClient:initialize(...)')
    options = options or {}
    self.keepAlive = 30
    if type(options.clientId) == 'string' then
      self.clientId = options.clientId
    else
      self.clientId = nextClientId()
    end
    if type(options.keepAlive) == 'number' then
      self.keepAlive = options.keepAlive
    end
    super.initialize(self, net.TcpClient:new())
  end

  --- Connects this MQTT client.
  -- @tparam[opt] string addr the address to connect to, could be an IP address or a host name.
  -- @tparam[opt] number port the port to connect to, default is 1883.
  -- @return a promise that resolves once the client is connected.
  function mqttClient:connect(addr, port)
    logger:finer('mqttClient:connect()')
    return self.tcpClient:connect(addr or 'localhost', port or 1883):next(function()
      self:readStart()
      local connData = encodeData(PROTOCOL_NAME)..
        encodeBytes(PROTOCOL_LEVEL, CONNECT_FLAGS.CLEAN_START)..
        encodeUInt16(self.keepAlive)..
        encodeData(self.clientId)
      -- TODO handle other payload fields: user, password
      return self:writePacket(CONTROL_PACKET_TYPE.CONNECT, connData)
    end)
  end

  --- Publishes a message payload on a topic.
  -- @tparam string topicName The name of the topic.
  -- @tparam string payload The message payload.
  -- @return a promise that resolves once the message is sent.
  -- @function mqttClient:publish

  --- Connects this MQTT client.
  -- @return a promise that resolves once the client is closed.
  function mqttClient:close()
    return self:writePacket(CONTROL_PACKET_TYPE.DISCONNECT):next(function()
      return super.close(self)
    end)
  end

  function mqttClient:onReadPacket(packetType, packetFlags, data, offset, len)
    logger:finer('mqttClient:onReadPacket()')
    if packetType == CONTROL_PACKET_TYPE.CONNACK then
      self.connected = true
    else
      super.onReadPacket(self, packetType, packetFlags, data, offset, len)
    end
  end

  function mqttClient:onPublish(topicName, payload, dup, qos, retain)
    if logger:isLoggable(logger.FINER) then
      logger:finer('mqttClient:onPublish("'..tostring(topicName)..'", "'..tostring(payload)..'", dup: '..tostring(dup)..', qos: '..tostring(qos)..', retain: '..tostring(retain)..')')
    end
  end

  --- Subscribes to a topic.
  -- @tparam string topicName The name of the topic.
  -- @tparam number qos The QoS.
  -- @return a promise that resolves once the message is sent.
  function mqttClient:subscribe(topicName, qos)
    if logger:isLoggable(logger.FINER) then
      logger:finer('mqttClient:subscribe("'..tostring(topicName)..'", '..tostring(qos)..')')
    end
    local packetIdentifier = 0
    local data = encodeUInt16(packetIdentifier)
    data = data..encodeData(topicName)..encodeByte(qos or 0)
    return self:writePacket(CONTROL_PACKET_TYPE.SUBSCRIBE, data, 2)
  end

end)

local MqttClientServer = class.create(MqttClientBase, function(mqttClientServer, super)

  function mqttClientServer:initialize(tcp, server)
    logger:finer('mqttClientServer:initialize(...)')
    self.server = server
    self.topics = {}
    super.initialize(self, tcp)
  end

  function mqttClientServer:unregisterClient()
    if self.clientId then
      self.server:unregisterClient(self)
      self.clientId = nil
    end
  end

  function mqttClientServer:onReadEnded()
    self:unregisterClient()
    self:close()
  end

  function mqttClientServer:onSubscribe(topicName, qos)
    if logger:isLoggable(logger.FINER) then
      logger:finer('mqttClientServer:onSubscribe("'..tostring(topicName)..'", qos: '..tostring(qos)..')')
    end
    self.topics[topicName] = {
      qos = qos
    }
  end

  function mqttClientServer:onPublish(topicName, payload, dup, qos, retain)
    if logger:isLoggable(logger.FINER) then
      logger:finer('mqttClientServer:onPublish("'..tostring(topicName)..'", "'..tostring(payload)..'", dup: '..tostring(dup)..', qos: '..tostring(qos)..', retain: '..tostring(retain)..')')
    end
    self.server:publish(topicName, payload)
  end

  function mqttClientServer:publish(topicName, payload)
    local topic = self.topics[topicName]
    if topic then
      if logger:isLoggable(logger.FINER) then
        logger:finer('mqttClientServer:publish("'..tostring(topicName)..'", "'..tostring(payload)..'") clientId: "'..tostring(self.clientId)..'"')
      end
      super.publish(self, topicName, payload)
    else
      if logger:isLoggable(logger.FINER) then
        logger:finer('mqttClientServer:publish("'..tostring(topicName)..'") clientId: "'..tostring(self.clientId)..'" topic not registered')
      end
    end
  end

  function mqttClientServer:onReadPacket(packetType, packetFlags, data, offset, len)
    logger:finer('mqttClientServer:onReadPacket()')
    if packetType == CONTROL_PACKET_TYPE.CONNECT then
      local protocolName
      protocolName, offset = decodeData(data, offset)
      local protocolLevel = decodeByte(data, offset)
      local connectFlags = decodeByte(data, offset + 1)
      self.keepAlive = decodeUInt16(data, offset + 2)
      if logger:isLoggable(logger.FINER) then
        logger:finer('connect protocol: "'..tostring(protocolName)..'", level: '..tostring(protocolLevel)..', flags: '..tostring(connectFlags)..', keep alive: '..tostring(self.keepAlive)..'')
      end
      self.clientId, offset = decodeData(data, offset + 4)
      if logger:isLoggable(logger.FINE) then
        logger:fine('New client connected from ? as "'..tostring(self.clientId)..'"')
      end
      self.server:registerClient(self)

      local sessionPresent = false
      local acknowledgeFlags = 0
      if sessionPresent then
        acknowledgeFlags = acknowledgeFlags | 1
      end
      self:writePacket(CONTROL_PACKET_TYPE.CONNACK, encodeBytes(acknowledgeFlags, REASON_CODE.SUCCESS))
    elseif packetType == CONTROL_PACKET_TYPE.SUBSCRIBE then
      local offsetEnd = offset + len
      local packetIdentifier = decodeUInt16(data, offset)
      offset = offset + 2
      local topicName
      local returnCodes = ''
      while offset < offsetEnd do
        topicName, offset = decodeData(data, offset)
        local qos = decodeByte(data, offset)
        offset = offset + 1
        self:onSubscribe(topicName, qos)
        returnCodes = returnCodes..encodeByte(REASON_CODE.SUCCESS)
      end
      self:writePacket(CONTROL_PACKET_TYPE.SUBACK, encodeUInt16(packetIdentifier)..returnCodes)
    elseif packetType == CONTROL_PACKET_TYPE.DISCONNECT then
      self:unregisterClient()
      self:close()
    else
      super.onReadPacket(self, packetType, packetFlags, data, offset, len)
    end
  end

end)

--[[--
The MqttServer class enables clients to exchange Application Messages using publish and subscribe.
@usage
local event = require('jls.lang.event')
local mqtt = require('jls.net.mqtt')

local mqttServer = mqtt.MqttServer:new()
mqttServer:bind()

event:loop()
event:close()
@type MqttServer
]]
local MqttServer = class.create(function(mqttServer)

  --- Creates a new MQTT server.
  -- @function MqttServer:new
  -- @return a new MQTT server
  function mqttServer:initialize()
    logger:finer('mqttServer:initialize(...)')
    self.clients = {}
    self.tcpServer = net.TcpServer:new()
    local server = self
    function self.tcpServer:onAccept(tcpClient)
      local client = MqttClientServer:new(tcpClient, server)
      client:readStart()
    end
  end

  --- Binds this server to the specified address and port number.
  -- @tparam string node the address, the address could be an IP address or a host name.
  -- @tparam number port the port number.
  -- @tparam[opt] number backlog the accept queue size, default is 32.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is bound.
  function mqttServer:bind(node, port, backlog, callback)
    return self.tcpServer:bind(node or '::', port or 1883, backlog, callback)
  end

  --- Closes this server.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is closed.
  function mqttServer:close(callback)
    return self.tcpServer:close(callback)
  end

  function mqttServer:registerClient(client)
    self.clients[client:getClientId()] = client
  end

  function mqttServer:unregisterClient(client)
    self.clients[client:getClientId()] = nil
  end

  function mqttServer:publish(topicName, payload)
    if logger:isLoggable(logger.FINER) then
      logger:finer('mqttServer:publish("'..tostring(topicName)..'", "'..tostring(payload)..'")')
    end
    for _, client in pairs(self.clients) do
      client:publish(topicName, payload)
    end
  end

end)


return {
  MqttClient = MqttClient,
  MqttServer = MqttServer,
}
