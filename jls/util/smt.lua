-- SMT is a simple Star Message Transport
-- It is composed on a single server and one or more clients.
-- A client can post message to the server and
-- the server can post message to any client.

local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local loader = require('jls.lang.loader')
local Promise = require('jls.lang.Promise')
local strings = require('jls.util.strings')
local TableList = require('jls.util.TableList')

local MESSAGE_TYPE = {
  CONNECT = 1, -- Client to Server -- Connection request
  CONNACK = 2, -- Server to Client -- Connect acknowledgment
  POST = 3, -- Client to Server or Server to Client -- Post message
  DISCONNECT = 14, -- Client to Server or Server to Client -- Disconnect notification
}

local PROTOCOL_NAME = 'SMT'
local PROTOCOL_LEVEL = 1

local SmtClientBase = class.create(function(smtClientBase)

  function smtClientBase:initialize(stream)
    logger:finer('smtClientBase:initialize(...)')
    self.stream = stream
  end

  function smtClientBase:getClientId()
    return self.clientId
  end

  function smtClientBase:onReadError(err)
    if logger:isLoggable(logger.FINE) then
      logger:fine('smtClientBase:onReadError("'..tostring(err)..'") '..tostring(self.clientId))
    end
  end

  function smtClientBase:onReadEnded()
    if logger:isLoggable(logger.FINE) then
      logger:fine('smtClientBase:onReadEnded() '..tostring(self.clientId))
    end
  end

  function smtClientBase:onMessage(payload)
    if logger:isLoggable(logger.FINER) then
      logger:finer('smtClientBase:onMessage("'..tostring(payload)..'") '..tostring(self.clientId))
    end
  end

  function smtClientBase:onReadMessage(messageType, data, offset)
    if logger:isLoggable(logger.FINER) then
      logger:finer('smtClientBase:onReadMessage('..tostring(messageType)..') '..tostring(self.clientId))
    end
    if messageType == MESSAGE_TYPE.POST then
      local payload = string.sub(data, offset)
      self:onMessage(payload)
    end
  end

  function smtClientBase:readStart()
    if logger:isLoggable(logger.FINER) then
      logger:finer('smtClientBase:readStart()')
    end
    -- stream implementation that buffers and splits messages
    local buffer = ''
    return self.stream:readStart(function(err, data)
      if err then
        self:onReadError(err)
      elseif data then
        if logger:isLoggable(logger.FINEST) then
          logger:finest('smtClientBase:read '..tostring(self.clientId)..' #'..tostring(#data))
        end
        buffer = buffer..data
        while true do
          local bufferLength = #buffer
          if bufferLength < 5 then
            if logger:isLoggable(logger.FINEST) then
              logger:finest('smtClientBase:read buffer too small ('..tostring(bufferLength)..'<2)')
            end
            break
          end
          local messageType, remainingLength, offset = string.unpack('>BI4', buffer)
          local messageLength = offset - 1 + remainingLength
          if bufferLength < messageLength then
            if logger:isLoggable(logger.FINEST) then
              logger:finest('smtClientBase:read buffer too small ('..tostring(bufferLength)..'<'..tostring(messageLength)..')')
            end
            break
          end
          local remainingBuffer
          if bufferLength == messageLength then
            remainingBuffer = ''
          else
            remainingBuffer = string.sub(buffer, messageLength + 1)
            buffer = string.sub(buffer, 1, messageLength)
          end
          if logger:isLoggable(logger.FINEST) then
            logger:finest('smtClientBase:read '..tostring(self.clientId)..' "'..tostring(buffer)..'"')
          end
          self:onReadMessage(messageType, buffer, offset)
          buffer = remainingBuffer
        end
      else
        self:onReadEnded()
      end
    end)
  end

  function smtClientBase:writeMessage(messageType, payload, callback)
    return self.stream:write(string.pack('>Bs4', messageType, payload or ''), callback)
  end

  function smtClientBase:postMessage(payload)
    if logger:isLoggable(logger.FINER) then
      logger:finer('smtClientBase:postMessage("'..tostring(payload)..'") '..tostring(self.clientId))
    end
    return self:writeMessage(MESSAGE_TYPE.POST, payload)
  end

  function smtClientBase:close(callback)
    local stream = self.stream
    if stream then
      self.stream = nil
      return stream:close(callback)
    end
    return Promise.resolve()
  end

end)

local SmtClient = class.create(SmtClientBase, function(smtClient, super)

  local CLIENT_ID_PREFIX = 'JLS'..strings.formatInteger(require('jls.lang.system').currentTimeMillis(), 64)..'-'
  local CLIENT_ID_UID = 0

  local function nextClientId()
    CLIENT_ID_UID = CLIENT_ID_UID + 1
    return CLIENT_ID_PREFIX..strings.formatInteger(CLIENT_ID_UID, 64)
  end

  function smtClient:initialize(stream, options)
    logger:finer('smtClient:initialize(...)')
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
    super.initialize(self, stream)
  end

  function smtClient:connect(...)
    logger:finer('smtClient:connect()')
    return self.stream:connect(...):next(function()
      return self:initializeConnection()
    end)
  end

  function smtClient:initializeConnection()
    self:readStart() -- TODO Check errors
    local connData = string.pack('>s1BI2s2', PROTOCOL_NAME, PROTOCOL_LEVEL, self.keepAlive, self.clientId)
    return self:writeMessage(MESSAGE_TYPE.CONNECT, connData)
  end

  function smtClient:close()
    return self:writeMessage(MESSAGE_TYPE.DISCONNECT):next(function()
      return super.close(self)
    end)
  end

  function smtClient:onReadMessage(messageType, data, offset)
    logger:finer('smtClient:onReadMessage()')
    if messageType == MESSAGE_TYPE.CONNACK then
      self.connected = true
    else
      super.onReadMessage(self, messageType, data, offset)
    end
  end

end)

local SmtClientServer = class.create(SmtClientBase, function(smtClientServer, super)

  function smtClientServer:initialize(tcp, server)
    logger:finer('smtClientServer:initialize(...)')
    self.server = server
    super.initialize(self, tcp)
  end

  function smtClientServer:unregisterClient()
    if self.clientId then
      self.server:unregisterClient(self)
      self.clientId = nil
    end
  end

  function smtClientServer:onReadEnded()
    self:unregisterClient()
    self:close()
  end

  function smtClientServer:onMessage(payload)
    if logger:isLoggable(logger.FINER) then
      logger:finer('smtClientServer:onMessage("'..tostring(payload)..'") '..tostring(self.clientId))
    end
    self.server:onMessage(payload, self)
  end

  function smtClientServer:onReadMessage(messageType, data, offset)
    if logger:isLoggable(logger.FINER) then
      logger:finer('smtClientServer:onReadMessage('..tostring(messageType)..', #'..tostring(data and #data or 'nil')..')')
    end
    if messageType == MESSAGE_TYPE.CONNECT then
      local protocolName, protocolLevel
      protocolName, protocolLevel, self.keepAlive, self.clientId, offset = string.unpack('>s1BI2s2', data, offset)
      if logger:isLoggable(logger.FINER) then
        logger:finer('connect protocol: "'..tostring(protocolName)..'", level: '..tostring(protocolLevel)..', keep alive: '..tostring(self.keepAlive)..'')
      end
      if logger:isLoggable(logger.FINE) then
        logger:fine('New client connected from ? as "'..tostring(self.clientId)..'"')
      end
      self.server:registerClient(self)
      self:writeMessage(MESSAGE_TYPE.CONNACK)
    elseif messageType == MESSAGE_TYPE.DISCONNECT then
      self:unregisterClient()
      self:close()
    else
      super.onReadMessage(self, messageType, data, offset)
    end
  end

end)

local SmtServer = class.create(function(smtServer)

  function smtServer:initialize(streamServer, options)
    logger:finer('smtServer:initialize(...)')
    options = options or {}
    self.clients = TableList:new()
    self.streamServer = streamServer
    function self.streamServer.onAccept(_, stream)
      local client = SmtClientServer:new(stream, self)
      client:readStart()
    end
  end

  function smtServer:bind(...)
    return self.streamServer:bind(...)
  end

  function smtServer:close(callback)
    return self.streamServer:close(callback)
  end

  function smtServer:onNextRegisteredClient()
    if not self.nextRegisteredClientPromise then
      self.nextRegisteredClientPromise, self.nextRegisteredClientCallback = Promise.createWithCallback()
    end
    return self.nextRegisteredClientPromise
  end

  function smtServer:registerClient(client)
    self.clients:add(client)
    if self.nextRegisteredClientPromise then
      local cb = self.nextRegisteredClientCallback
      self.nextRegisteredClientPromise = nil
      self.nextRegisteredClientCallback = nil
      cb(nil, client)
    end
  end

  function smtServer:unregisterClient(client)
    self.clients:removeAll(client)
  end

  function smtServer:getClients()
    return self.clients
  end

  function smtServer:onMessage(payload, client)
    if logger:isLoggable(logger.FINER) then
      logger:finer('smtServer:onMessage("'..tostring(payload)..'", '..tostring(client.clientId)..')')
    end
  end

  function smtServer:broadcastMessage(payload)
    if logger:isLoggable(logger.FINER) then
      logger:finer('smtServer:broadcastMessage("'..tostring(payload)..'")')
    end
    local promises = {}
    for _, client in ipairs(self.clients) do
      table.insert(promises, client:postMessage(payload))
    end
    return Promise.all(promises)
  end

end)

local smt = {
  SmtClient = SmtClient,
  SmtServer = SmtServer,
}


local TcpClient = loader.tryRequire('jls.net.TcpClient')
local TcpServer = loader.tryRequire('jls.net.TcpServer')
if TcpClient and TcpServer then
  local DEFAULT_TCP_PORT = 3881

  smt.SmtTcpClient = class.create(SmtClient, function(smtTcpClient, super)
    function smtTcpClient:initialize(options)
      if options and type(options.tcpPort) == 'number' then
        self.tcpPort = options.tcpPort
      end
      super.initialize(self, TcpClient:new(), options)
    end
    function smtTcpClient:connect(addr, port)
      return self.stream:connect(addr, port or self.tcpPort or DEFAULT_TCP_PORT):next(function()
        return self:initializeConnection()
      end)
    end
  end)

  smt.SmtTcpServer = class.create(SmtServer, function(smtTcpServer, super)
    function smtTcpServer:initialize(options)
      if options and type(options.tcpPort) == 'number' then
        self.tcpPort = options.tcpPort
      end
      super.initialize(self, TcpServer:new(), options)
    end
    function smtTcpServer:bind(addr, port)
      self.tcpPort = port or self.tcpPort or DEFAULT_TCP_PORT
      return self.streamServer:bind(addr, port):next(function()
        if self.tcpPort == 0 then
          self.tcpPort = select(2, self.streamServer:getLocalName())
        end
      end)
    end
    function smtTcpServer:getTcpPort()
      return self.tcpPort
    end
  end)
end

local Pipe = loader.tryRequire('jls.io.Pipe')
if Pipe then
  local DEFAULT_PIPE_NAME = 'smt'

  smt.SmtPipeClient = class.create(SmtClient, function(smtPipeClient, super)
    function smtPipeClient:initialize(options)
      -- TODO remove self port and pipe name options
      if options and type(options.pipeName) == 'string' then
        self.pipeName = options.pipeName
      end
      super.initialize(self, Pipe:new(), options)
    end
    function smtPipeClient:connect(pipeName)
      return self.stream:connect(pipeName or self.pipeName or Pipe.normalizePipeName(DEFAULT_PIPE_NAME)):next(function()
        return self:initializeConnection()
      end)
    end
  end)

  smt.SmtPipeServer = class.create(SmtServer, function(smtPipeServer, super)
    function smtPipeServer:initialize(options)
      if options and type(options.pipeName) == 'string' then
        self.pipeName = options.pipeName
      end
      super.initialize(self, Pipe:new(), options)
    end
    function smtPipeServer:bind(pipeName)
      self.pipeName = pipeName or self.pipeName or Pipe.normalizePipeName(DEFAULT_PIPE_NAME)
      if self.pipeName == '' then
        self.pipeName = Pipe.normalizePipeName(DEFAULT_PIPE_NAME, true)
      end
      return self.streamServer:bind(self.pipeName)
    end
    function smtPipeServer:getPipeName()
      return self.pipeName
    end
  end)
end

return smt
