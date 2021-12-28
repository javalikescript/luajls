--- Provide the Channel class.
-- @module jls.util.Channel

local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local loader = require('jls.lang.loader')
local Promise = require('jls.lang.Promise')
local URL = require('jls.net.URL')
local strings = require('jls.util.strings')
local event = require('jls.lang.event')

local DEFAULT_SCHEME = os.getenv('JLS_CHANNEL_DEFAULT_SCHEME')
if not DEFAULT_SCHEME then
  if loader.tryRequire('jls.io.Pipe') then
    DEFAULT_SCHEME = 'pipe'
  else
    DEFAULT_SCHEME = 'tcp'
  end
end

local SCHEMES = {
  pipe = {
    bind = function(self, userinfo)
      local Pipe = require('jls.io.Pipe')
      local pipeName = Pipe.generateUniqueName('JLS')
      self.name = URL.format({
        scheme = 'pipe',
        userinfo = userinfo,
        host = 'local',
        path = '/'..pipeName,
      })
      self.stream = Pipe:new()
      return self.stream:bind(Pipe.normalizePipeName(pipeName))
    end,
    connect = function(self, urlTable)
      local Pipe = require('jls.io.Pipe')
      self.stream = Pipe:new()
      local pipeName = Pipe.normalizePipeName(string.sub(urlTable.path, 2))
      return self.stream:connect(pipeName)
    end,
  },
  tcp = {
    bind = function(self, userinfo)
      local TcpServer = require('jls.net.TcpServer')
      self.stream = TcpServer:new()
      return self.stream:bind(nil, 0):next(function()
        local host, port = self.stream:getLocalName()
        self.name = URL.format({
          scheme = 'tcp',
          userinfo = userinfo,
          host = host,
          port = port,
        })
      end)
    end,
    connect = function(self, urlTable)
      local TcpClient = require('jls.net.TcpClient')
      self.stream = TcpClient:new()
      return self.stream:connect(nil, urlTable.port)
    end,
  },
}

--- The Channel class.
-- Provides a local message passing interface suitable for process and thread event based message passing.
-- The messages are sent and received as string on a channel.
-- The goal is to abstract the message transport implementation, that can internally be a queue, a pipe or a socket.
-- The channel resource is represented by an opaque string and can be generated automatically.
-- Internally using URI with authentication keys, pipe://pub.priv@local/p12345 or tcp://pub.priv@localhost:12345.
-- This interface is used for worker that abstract the thread.
-- @type Channel
return class.create(function(channel, _, Channel)

  --- Creates a new Channel.
  -- A channel can be a server using the bind method or a client using the connect method but not both.
  -- @function Channel:new
  function channel:initialize()
    if logger:isLoggable(logger.FINEST) then
      logger:finest('channel['..tostring(self)..']:initialize()')
    end
  end

  --- Closes this channel.
  -- @tparam function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the channel is closed.
  function channel:close(callback)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('channel['..tostring(self)..']:close()')
    end
    local p
    if self.stream then
      p = self.stream:close(callback)
      self.stream = nil
    else
      p = Promise.reject('The channel is not open')
    end
    local closeCallback = self.closeCallback
    if closeCallback then
      self.closeCallback = nil
      closeCallback()
      self.closePromise = nil
    end
    return p
  end

  --- Returns a promise that resolves once the channel is closed.
  -- @treturn jls.lang.Promise a promise that resolves once the channel is closed.
  function channel:onClose()
    if not self.closePromise then
      self.closePromise, self.closeCallback = Promise.createWithCallback()
    end
    return self.closePromise
  end

  --- Returns the name of this channel.
  -- @treturn string the name of this channel.
  function channel:getName()
    return self.name
  end

  function channel:checkStream(closed)
    if closed then
      if self.stream then
        error('The channel is already open')
      end
    elseif not self.stream then
      error('The channel is not open')
    end
  end

  --- Binds this channel.
  -- When bound, the channel name can be used for connection.
  -- @tparam[opt] boolean closeWithAccepted true to indicate this channel shall be closed after all the accepted channels are closed.
  -- @tparam[opt] string scheme the scheme to use.
  -- @treturn jls.lang.Promise a promise that resolves once the server channel is bound.
  function channel:bind(closeWithAccepted, scheme)
    scheme = scheme or DEFAULT_SCHEME
    if logger:isLoggable(logger.FINER) then
      logger:finer('channel['..tostring(self)..']:bind('..tostring(closeWithAccepted)..', '..tostring(scheme)..')')
    end
    self:checkStream(true)
    self.name = ''
    local acceptedCount = 0
    local privateKey = strings.formatInteger(math.random(0, math.maxinteger), 64)
    local publicKey = strings.formatInteger(math.random(0, math.maxinteger), 64)
    local userinfo = publicKey..'.'..privateKey
    if not SCHEMES[scheme] then
      error('Invalid channel server scheme "'..tostring(scheme)..'"')
    end
    local bindPromise = SCHEMES[scheme].bind(self, userinfo)
    function self.stream.onAccept(_, st)
      local ch = Channel:new()
      ch.stream = st
      ch.privateKey = privateKey
      ch.publicKey = publicKey
      if logger:isLoggable(logger.FINEST) then
        logger:finest('channel['..tostring(self)..']:bind() on accept '..tostring(ch))
      end
      if closeWithAccepted then
        acceptedCount = acceptedCount + 1
        ch:onClose():next(function()
          acceptedCount = acceptedCount - 1
          if acceptedCount == 0 then
            self:close(false)
          end
        end)
      end
      self:onAccept(ch)
    end
    return bindPromise
  end

  --- Accepts a new channel.
  -- This method should be overriden, the default implementation closes the channel.
  -- @param ch the channel to accept.
  function channel:onAccept(ch)
    logger:fine('channel:onAccept() => closing')
    ch:close(false)
  end

  function channel:acceptAndClose(timeout)
    return Promise:new(function(resolve, reject)
      local timer = event:setTimeout(function()
        self:close(false)
        reject('Timeout')
      end, timeout or 5000)
      function self:onAccept(ch)
        event:clearTimeout(timer)
        self:close(false)
        resolve(ch)
      end
    end)
  end

  function channel:isOpen()
    return self.stream and not self.stream:isClosed()
  end

  --- Connects this channel to the specified name.
  -- @tparam string name the name of the channel.
  -- @treturn jls.lang.Promise a promise that resolves once the channel is connected.
  function channel:connect(name)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('channel['..tostring(self)..']:connect("'..tostring(name)..'")')
    end
    self:checkStream(true)
    local t = URL.parse(name)
    if t and t.userinfo then
      local privateKey, publicKey = string.match(t.userinfo, '^([^%.]+)%.([^%.]+)$')
      if privateKey and publicKey then
        self.name = name
        self.privateKey = privateKey
        self.publicKey = publicKey
        if SCHEMES[t.scheme] then
          return SCHEMES[t.scheme].connect(self, t)
        end
      end
    end
    logger:finest('channel:connect() => reject')
    return Promise.reject('Invalid channel name "'..tostring(name)..'"')
  end

  local MT_CLOSE = 0
  local MT_CONNECT = 1
  local MT_USER = 2
  Channel.MESSAGE_TYPE_USER = MT_USER

  --- Starts receiving messages on this channel.
  -- The handler will be called with the payload and the message type.
  -- @tparam function handleMessage a function that will be called when a message is received.
  function channel:receiveStart(handleMessage)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('channel['..tostring(self)..']:receiveStart()')
    end
    self:checkStream()
    if type(handleMessage) ~= 'function' then
      error('Invalid message handling function')
    end
    local buffer = ''
    return self.stream:readStart(function(err, data)
      if logger:isLoggable(logger.FINEST) then
        logger:finest('channel['..tostring(self)..'] read "'..tostring(err)..'", #'..tostring(data and #data))
      end
      if err then
      elseif data then
        buffer = buffer..data
        while true do
          local bufferLength = #buffer
          if bufferLength < 5 then
            break
          end
          local messageType, remainingLength, offset = string.unpack('>BI4', buffer)
          local messageLength = offset - 1 + remainingLength
          if bufferLength < messageLength then
            break
          end
          local remainingBuffer
          if bufferLength == messageLength then
            remainingBuffer = ''
          else
            remainingBuffer = string.sub(buffer, messageLength + 1)
            buffer = string.sub(buffer, 1, messageLength)
          end
          local payload = string.sub(buffer, offset)
          if logger:isLoggable(logger.FINEST) then
            logger:finest('channel received message type '..tostring(messageType)..', payload "'..tostring(payload)..'"')
          end
          if messageType >= MT_USER and self.authorized then
            handleMessage(payload, messageType)
          elseif messageType == MT_CONNECT and payload == self.privateKey then
            self.authorized = true
          else
            self:close(false)
            return
          end
          buffer = remainingBuffer
        end
        return
      end
      self:close(false)
    end)
  end

  --- Stops receiving messages on this channel.
  -- This server channel shall not be used anymore.
  function channel:receiveStop()
    logger:finest('channel:receiveStop()')
    self:checkStream()
    return self.stream:readStop()
  end

  --- Writes a message on this channel.
  -- @tparam string payload the message to send
  -- @tparam[opt] number messageType the message type, default is Channel.MESSAGE_TYPE_USER.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the message has been sent.
  function channel:writeMessage(payload, messageType, callback)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('channel['..tostring(self)..']:writeMessage('..tostring(messageType)..', "'..tostring(payload)..'")')
    end
    local cb, p = Promise.ensureCallback(callback)
    local wcb = cb or false
    if logger:isLoggable(logger.FINE) then
      wcb = function(reason)
        if reason then
          logger:fine('channel write error "'..tostring(reason)..'"')
        elseif logger:isLoggable(logger.FINEST) then
          logger:finest('channel message sent '..tostring(messageType))
        end
        if cb then
          cb(reason)
        end
      end
    end
    local data = string.pack('>Bs4', messageType or MT_USER, payload or '')
    if self.publicKey then
      data = string.pack('>Bs4', MT_CONNECT, self.publicKey)..data
      self.publicKey = nil
    end
    local _, req, err = self.stream:write(data, wcb)
    if not req and err then
      if not wcb and logger:isLoggable(logger.FINE) then
        logger:fine('channel write error, '..tostring(err))
      end
      self:close(false)
    end
    return p, req, err
  end

  function channel:writeCloseMessage(callback)
    return self:writeMessage(nil, MT_CLOSE, callback)
  end

end)