--- This module provides classes to work with MQTT.
-- Message Queuing Telemetry Transport
--
-- see [MQTT Version 3.1.1](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html)

-- @module jls.net.mqtt
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local system = require('jls.lang.system')
local Promise = require('jls.lang.Promise')
local TcpSocket = require('jls.net.TcpSocket')
local List = require('jls.util.List')
local strings = require('jls.util.strings')
local Codec = require('jls.util.Codec')

--[[
  mosquitto -v
  mosquitto_pub -t test -m hello
  mosquitto_sub -t test
]]

local function encodeUInt16(i)
  if i < 0 then
    return 0
  end
  return string.char((i >> 8) & 0xff, i & 0xff)
end

local function encodeUInt32(i)
  if i < 0 then
    return 0
  end
  return string.char((i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff)
end

local function decodeUInt16(s, o)
  o = o or 1
  local b1, b2 = string.byte(s, o, o + 1)
  return (b1 << 8) | b2
end

local function decodeUInt32(s, o)
  o = o or 1
  local b1, b2, b3, b4 = string.byte(s, o, o + 3)
  return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
end

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

local CONNECT_CODE = {
  ACCEPTED = 0,
  BAD_PROTOCOL_VERSION = 1,
  IDENTIFIER_REJECTED = 2,
  SERVER_UNAVAILABLE = 3,
  BAD_USER_NAME_OR_PASSWORD = 4,
  NOT_AUTHORIZED = 5,
}

local SUBSCRIBE_CODE = {
  SUCCESS_QOS_0 = 0,
  SUCCESS_QOS_1 = 1,
  SUCCESS_QOS_2 = 2,
  FAILURE = 0x80,
}

local CLIENT_ID_PREFIX = 'JLS'..strings.formatInteger(system.currentTimeMillis(), 64)..'-'
local CLIENT_ID_UID = 0

local function nextClientId()
  CLIENT_ID_UID = CLIENT_ID_UID + 1
  return CLIENT_ID_PREFIX..strings.formatInteger(CLIENT_ID_UID, 64)
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

  function mqttClientBase:onError(err)
    logger:fine('mqttClientBase:onError("%s") %s', err, self.clientId)
  end

  function mqttClientBase:raiseError(reason)
    self:close(false)
    self:onError(reason)
  end

  function mqttClientBase:onPublish(topicName, payload, qos, retain, dup, packetId)
    logger:finer('mqttClientBase:onPublish("%s", "%s", dup: %s, qos: %s, retain: %s, packetId: %s) %s', topicName, payload, dup, qos, retain, packetId, self.clientId)
  end

  function mqttClientBase:onReadPacket(packetType, packetFlags, data, offset, len)
    logger:finer('mqttClientBase:onReadPacket(%s) %s', packetType, self.clientId)
    if packetType == CONTROL_PACKET_TYPE.PUBLISH then
      local dup = packetFlags & 8 ~= 0
      local qos = (packetFlags >> 1) & 3
      local retain = packetFlags & 1 ~= 0
      logger:finer('publish dup: %s, qos: %s, retain: %s', dup, qos, retain)
      local topicName, packetId
      topicName, offset = decodeData(data, offset)
      if qos > 0 then
        packetId = decodeUInt16(data, offset)
        offset = offset + 2
      else
        packetId = 0
      end
      local payload = string.sub(data, offset)
      self:onPublish(topicName, payload, qos, retain, dup, packetId)
      if qos == 1 then
        self:writePacket(CONTROL_PACKET_TYPE.PUBACK, encodeUInt16(packetId))
      elseif qos == 2 then
        self:writePacket(CONTROL_PACKET_TYPE.PUBREC, encodeUInt16(packetId))
      end
    elseif packetType == CONTROL_PACKET_TYPE.PUBREC then
      local packetId = decodeUInt16(data, offset)
      self:writePacket(CONTROL_PACKET_TYPE.PUBREL, encodeUInt16(packetId))
    elseif packetType == CONTROL_PACKET_TYPE.PUBREL then
      local packetId = decodeUInt16(data, offset)
      self:writePacket(CONTROL_PACKET_TYPE.PUBCOMP, encodeUInt16(packetId))
    end
  end

  function mqttClientBase:readStart()
    -- stream implementation that buffers and splits packets
    local buffer = ''
    return self.tcpClient:readStart(function(err, data)
      if err then
        self:raiseError(err)
      elseif data then
        buffer = buffer..data
        while true do
          local bufferLength = #buffer
          if bufferLength < 2 then
            break
          end
          local packetTypeAndFlags = string.byte(buffer, 1)
          local remainingLength, offset = strings.decodeVariableByteInteger(buffer, 2)
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
            logger:finest('mqttClientBase:read %s "%s"', self.clientId, Codec.encode('hex', buffer))
          end
          self:onReadPacket(packetTypeAndFlags >> 4, packetTypeAndFlags & 0xf, buffer, offset, remainingLength)
          buffer = remainingBuffer
        end
      else
        self:raiseError('end of stream')
      end
    end)
  end

  function mqttClientBase:write(data, callback)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('mqttClientBase:write() "%s"', Codec.encode('hex', data))
    end
    local cb, d = Promise.ensureCallback(callback)
    self.tcpClient:write(data, function(err)
      if err then
        self:raiseError(err)
      end
      if cb then
        cb(err)
      end
    end)
    return d
  end

  function mqttClientBase:writePacket(packetType, data, packetFlags, callback)
    local packetTypeAndFlags = ((packetType & 0xf) << 4) | ((packetFlags or 0) & 0xf)
    local packet
    if data then
      packet = string.char(packetTypeAndFlags)..strings.encodeVariableByteInteger(#data)..data
    else
      packet = string.char(packetTypeAndFlags, 0)
    end
    return self:write(packet, callback)
  end

  function mqttClientBase:close(callback)
    return self.tcpClient:close(callback)
  end

  -- Duplicate delivery of a PUBLISH Control Packet, false to indicate this is the first delivery attempt
  -- Quality of Service, 0: At most once delivery, 1: At least once delivery, 2: Exactly once delivery
  -- Retain flag, will be delivered to future subscribers
  function mqttClientBase:publish(topicName, payload, qos, retain, dup, packetId, callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('mqttClientBase:publish("%s", "%s") %s', topicName, payload, self.clientId)
      logger:finer('publish dup: %s, qos: %s, retain: %s, packetId: %s', dup, qos, retain, packetId)
    end
    qos = (qos or 0) & 3
    local packetFlags = (qos << 1)
    if dup then
      packetFlags = packetFlags | 8
    end
    if retain then
      packetFlags = packetFlags | 1
    end
    local data = encodeData(topicName)
    if qos > 0 then
      if type(packetId) ~= 'number' or packetId <= 0 then
        error('Invalid packet identifier, '..tostring(packetId))
      end
      data = data..encodeUInt16(packetId)
    end
    if payload then
      data = data..payload
    end
    return self:writePacket(CONTROL_PACKET_TYPE.PUBLISH, data, packetFlags, callback)
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
    self.packetId = 0
    self.regPacketIds = {}
    if type(options.clientId) == 'string' then
      self.clientId = options.clientId
    else
      self.clientId = nextClientId()
    end
    if type(options.keepAlive) == 'number' then
      self.keepAlive = options.keepAlive
    end
    super.initialize(self, TcpSocket:new())
  end

  function mqttClient:nextPacketId()
    self.packetId = (self.packetId + 1) % 0xffff
    return self.packetId
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
        string.char(PROTOCOL_LEVEL, CONNECT_FLAGS.CLEAN_START)..
        encodeUInt16(self.keepAlive)..
        encodeData(self.clientId)
      -- TODO handle other payload fields: user, password
      return self:writePacket(CONTROL_PACKET_TYPE.CONNECT, connData)
    end)
  end

  --- Closes this MQTT client.
  -- @return a promise that resolves once the client is closed.
  function mqttClient:close()
    return self:writePacket(CONTROL_PACKET_TYPE.DISCONNECT):next(function()
      return super.close(self)
    end)
  end

  function mqttClient:onReadPacket(packetType, packetFlags, data, offset, len)
    logger:finer('mqttClient:onReadPacket()')
    if packetType == CONTROL_PACKET_TYPE.CONNACK then
      local ackFlags = string.byte(data, offset)
      local code = string.byte(data, offset + 1)
      local sessionPresent = ackFlags & 1
      self.connected = code == 0 -- Is this used?
      self:onConnected(code, sessionPresent)
    elseif packetType == CONTROL_PACKET_TYPE.PUBACK then
      local packetId = decodeUInt16(data, offset)
      self:onPacketId(packetId)
    elseif packetType == CONTROL_PACKET_TYPE.PUBCOMP then
      local packetId = decodeUInt16(data, offset)
      self:onPacketId(packetId)
    elseif packetType == CONTROL_PACKET_TYPE.PINGRESP then
      self:onPong()
    elseif packetType == CONTROL_PACKET_TYPE.SUBACK then
      local packetId = decodeUInt16(data, offset)
      local returnCodes = table.pack(string.byte(data, offset + 2, len))
      logger:finer('subscribed(%s, #%s)', packetId, #returnCodes)
      self:onPacketId(packetId, nil, returnCodes)
    elseif packetType == CONTROL_PACKET_TYPE.UNSUBACK then
      local packetId = decodeUInt16(data, offset)
      logger:finer('unsubscribed(%s)', packetId)
      self:onPacketId(packetId)
    else
      super.onReadPacket(self, packetType, packetFlags, data, offset, len)
    end
  end

  function mqttClient:onConnected(code, sessionPresent)
    logger:fine('mqttClient:onConnected(%s, %s)', code, sessionPresent)
  end

  function mqttClient:onPong()
    logger:fine('mqttClient:onPong()')
  end

  function mqttClient:onPacketId(packetId, reason, value)
    local reg = self.regPacketIds[packetId]
    if reg then
      self.regPacketIds[packetId] = nil
      reg.cb(reason, value)
    end
  end

  function mqttClient:waitPacketId(packetId)
    local reg = self.regPacketIds[packetId]
    if reg then
      return reg.promise
    end
    local promise, cb = Promise.createWithCallback()
    self.regPacketIds[packetId] = {
      cb = cb,
      promise = promise,
    }
    return promise
  end

  --- Called when a message has been published on a subscribed topic.
  -- @tparam string topicName The name of the topic.
  -- @tparam string payload The message payload.
  function mqttClient:onMessage(topicName, payload)
    logger:info('mqttClient:onMessage("%s", "%s")', topicName, payload)
  end

  function mqttClient:onPublish(topicName, payload, qos, retain, dup, packetId)
    logger:finer('mqttClient:onPublish("%s", "%s")', topicName, payload)
    self:onMessage(topicName, payload)
  end

  function mqttClient:ping()
    return self:writePacket(CONTROL_PACKET_TYPE.PINGREQ)
  end

  --- Publishes a message payload on a topic.
  -- @tparam string topicName The name of the topic.
  -- @tparam string payload The message payload.
  -- @tparam[opt] table options the options.
  -- @tparam[opt] number options.qos Quality of Service, 0: At most once delivery, 1: At least once delivery, 2: Exactly once delivery
  -- @tparam[opt] boolean options.retain Retain flag, will be delivered to future subscribers
  -- @return a promise that resolves once the message is sent.
  function mqttClient:publish(topicName, payload, options)
    local qos = options and options.qos or 0
    local retain = options and options.retain or false
    local packetId = self:nextPacketId()
    return super.publish(self, topicName, payload, qos, retain, false, packetId):next(function()
      if options and options.wait and qos ~= 0 then
        return self:waitPacketId(packetId)
      end
      return packetId
    end)
  end

  --- Subscribes to a topic.
  -- @tparam string topicName The name of the topic.
  -- @tparam number qos The QoS.
  -- @return a promise that resolves once the message is sent.
  function mqttClient:subscribe(topicName, qos)
    logger:finer('mqttClient:subscribe("%s", %s)', topicName, qos)
    local packetId = self:nextPacketId()
    local data = encodeUInt16(packetId)
    if type(topicName) == 'table' then
      for _, tn in ipairs(topicName) do
        data = data..encodeData(tn)..string.char(qos or 0)
      end
    else
      data = data..encodeData(topicName)..string.char(qos or 0)
    end
    return self:writePacket(CONTROL_PACKET_TYPE.SUBSCRIBE, data, 2):next(function()
      return packetId
    end)
  end

  --- Unubscribes from a topic.
  -- @tparam string topicName The name of the topic.
  -- @return a promise that resolves once the message is sent.
  function mqttClient:unsubscribe(topicName)
    logger:finer('mqttClient:subscribe("%s")', topicName)
    local packetId = self:nextPacketId()
    local data = encodeUInt16(packetId)
    if type(topicName) == 'table' then
      for _, tn in ipairs(topicName) do
        data = data..encodeData(tn)
      end
    else
      data = data..encodeData(topicName)
    end
    return self:writePacket(CONTROL_PACKET_TYPE.UNSUBSCRIBE, data, 2):next(function()
      return packetId
    end)
  end

end)

--[[
  The topic level separator is used to introduce structure into the Topic Name. If present, it divides the Topic Name into multiple “topic levels”.
  A subscription’s Topic Filter can contain special wildcard characters, which allow you to subscribe to multiple topics at once.
  The forward slash (‘/’ U+002F) is used to separate each level within a topic tree and provide a hierarchical structure to the Topic Names.
  The number sign (‘#’ U+0023) is a wildcard character that matches any number of levels within a topic.
  The plus sign (‘+’ U+002B) is a wildcard character that matches only one topic level.
  The Server MUST NOT match Topic Filters starting with a wildcard character (# or +) with Topic Names beginning with a $ character
]]
local function topicFilterToPattern(filter)
  if filter == '#' then
    return '^[^%$].*$'
  end
  -- escape magic characters except +
  filter = string.gsub(filter, '[%^%$%(%)%%%.%[%]%*%-%?]', function(c)
    return '%'..c
  end)
  -- TODO check for + or # used outside a / level
  return '^'..string.gsub(string.gsub(string.gsub(filter, '^%+', '[^%$/][^/]*'), '%+', '[^/]+'), '/%#$', '.*')..'$'
end

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

  function mqttClientServer:findTopic(topicName)
    for index, topic in ipairs(self.topics) do
      if string.match(topicName, topic.pattern) then
        return topic, index
      end
    end
    return nil
  end

  function mqttClientServer:onSubscribe(topicFilter, qos)
    local pattern = topicFilterToPattern(topicFilter)
    logger:finer('mqttClientServer:onSubscribe("%s", qos: %s) "%s"', topicFilter, qos, pattern)
    table.insert(self.topics, {
      pattern = pattern,
      qos = qos
    })
  end

  function mqttClientServer:onUnsubscribe(topicFilter)
    local pattern = topicFilterToPattern(topicFilter)
    logger:finer('mqttClientServer:onUnsubscribe("%s") "%s"', topicFilter, pattern)
    List.removeIf(self.topics, function(topic)
      return topic.pattern == pattern
    end)
  end

  function mqttClientServer:onPublish(topicName, payload, qos, retain, dup, packetId)
    logger:finer('mqttClientServer:onPublish("%s", "%s", dup: %s, qos: %s, retain: %s)', topicName, payload, dup, qos, retain)
    self.server:publish(topicName, payload, qos, retain, dup, packetId)
  end

  function mqttClientServer:publish(topicName, payload, qos, retain, dup, packetId)
    local topic = self:findTopic(topicName)
    if topic then
      logger:finer('mqttClientServer:publish("%s", "%s") clientId: "%s"', topicName, payload, self.clientId)
      super.publish(self, topicName, payload, qos, retain, dup, packetId)
    else
      logger:finer('mqttClientServer:publish("%s") clientId: "%s" topic not registered', topicName, self.clientId)
    end
  end

  function mqttClientServer:onReadPacket(packetType, packetFlags, data, offset, len)
    logger:finer('mqttClientServer:onReadPacket()')
    if packetType == CONTROL_PACKET_TYPE.CONNECT then
      local protocolName
      protocolName, offset = decodeData(data, offset)
      local protocolLevel = string.byte(data, offset)
      local connectFlags = string.byte(data, offset + 1)
      self.keepAlive = decodeUInt16(data, offset + 2)
      logger:finer('connect protocol: "%s", level: %s, flags: %s, keep alive: %s', protocolName, protocolLevel, connectFlags, self.keepAlive)
      self.clientId, offset = decodeData(data, offset + 4)
      if logger:isLoggable(logger.FINE) then
        local addr, port = self.tcpClient:getRemoteName()
        logger:fine('New client connected from %s:%s as "%s"', addr, port, self.clientId)
      end
      self.server:registerClient(self)
      local sessionPresent = false
      local acknowledgeFlags = 0
      if sessionPresent then
        acknowledgeFlags = acknowledgeFlags | 1
      end
      self:writePacket(CONTROL_PACKET_TYPE.CONNACK, string.char(acknowledgeFlags, CONNECT_CODE.ACCEPTED))
    elseif packetType == CONTROL_PACKET_TYPE.SUBSCRIBE then
      local offsetEnd = offset + len
      local packetId = decodeUInt16(data, offset)
      offset = offset + 2
      local topicFilter
      local returnCodes = ''
      while offset < offsetEnd do
        topicFilter, offset = decodeData(data, offset)
        local qos = string.byte(data, offset)
        offset = offset + 1
        self:onSubscribe(topicFilter, qos)
        returnCodes = returnCodes..string.char(SUBSCRIBE_CODE.SUCCESS_QOS_0)
      end
      self:writePacket(CONTROL_PACKET_TYPE.SUBACK, encodeUInt16(packetId)..returnCodes)
    elseif packetType == CONTROL_PACKET_TYPE.UNSUBSCRIBE then
      local offsetEnd = offset + len
      local packetId = decodeUInt16(data, offset)
      offset = offset + 2
      local topicFilter
      while offset < offsetEnd do
        topicFilter, offset = decodeData(data, offset)
        self:onUnsubscribe(topicFilter)
      end
      self:writePacket(CONTROL_PACKET_TYPE.UNSUBACK, encodeUInt16(packetId))
    elseif packetType == CONTROL_PACKET_TYPE.DISCONNECT then
      self:unregisterClient()
      self:close()
    elseif packetType == CONTROL_PACKET_TYPE.PINGREQ then
      logger:fine('Ping from client "%s"', self.clientId)
      self:writePacket(CONTROL_PACKET_TYPE.PINGRESP)
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
@type MqttServer
]]
local MqttServer = class.create(function(mqttServer)

  --- Creates a new MQTT server.
  -- @function MqttServer:new
  -- @return a new MQTT server
  function mqttServer:initialize()
    logger:finer('mqttServer:initialize(...)')
    self.clients = {}
    self.tcpServer = TcpSocket:new()
    local server = self
    function self.tcpServer:onAccept(tcpClient)
      local client = MqttClientServer:new(tcpClient, server)
      client:readStart()
    end
  end

  --- Binds this server to the specified address and port number.
  -- @tparam string node the address, the address could be an IP address or a host name.
  -- @tparam[opt] number port the port number, 0 to let the system automatically choose a port, default is 1883.
  -- @tparam[opt] number backlog the accept queue size, default is 32.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is bound.
  function mqttServer:bind(node, port, backlog, callback)
    return self.tcpServer:bind(node or '::', port or 1883, backlog, callback)
  end

  function mqttServer:getAddress()
    return self.tcpServer:getLocalName()
  end

  --- Closes this server.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is closed.
  function mqttServer:close(callback)
    return self.tcpServer:close(callback)
  end

  function mqttServer:getTcpServer()
    return self.tcpServer
  end

  function mqttServer:registerClient(client)
    self.clients[client:getClientId()] = client
    -- TODO publish retained packets
  end

  function mqttServer:unregisterClient(client)
    self.clients[client:getClientId()] = nil
  end

  function mqttServer:publish(topicName, payload, qos, retain, dup, packetId)
    logger:finer('mqttServer:publish("%s", "%s")', topicName, payload)
    for _, client in pairs(self.clients) do
      client:publish(topicName, payload, qos, retain, dup, packetId)
    end
  end

end)


return {
  MqttClient = MqttClient,
  MqttServer = MqttServer,
}
