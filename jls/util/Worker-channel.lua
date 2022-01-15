local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event')
local Thread = require('jls.lang.Thread')
local Channel = require('jls.util.Channel')
local json = require('jls.util.json')

local MT_STRING = Channel.MESSAGE_TYPE_USER
local MT_JSON = Channel.MESSAGE_TYPE_USER + 1
local MT_ERROR = Channel.MESSAGE_TYPE_USER + 2

local function postMessage(channel, message)
  if type(message) == 'string' then
    return channel:writeMessage(message, MT_STRING)
  end
  return channel:writeMessage(json.encode(message), MT_JSON)
end

local function newThreadChannel(fn, data, scheme)
  local chunk = string.dump(fn)
  if logger:isLoggable(logger.FINEST) then
    logger:finest('newThreadChannel() code >>'..tostring(chunk)..'<<')
  end
  local jsonData = data and json.encode(data) or nil
  local thread = Thread:new(function(...)
    require('jls.util.Worker-channel').initializeWorkerThread(...)
    require('jls.lang.event'):loop()
  end)
  if logger:isLoggable(logger.FINER) then
    logger:finer('workerServer:newThreadChannel()')
  end
  local channelServer = Channel:new()
  local acceptPromise = channelServer:acceptAndClose()
  return channelServer:bind(nil, scheme):next(function()
    local channelName = channelServer:getName()
    thread:start(channelName, chunk, jsonData):ended():next(function()
      if logger:isLoggable(logger.FINER) then
        logger:finer('workerServer thread ended')
      end
    end)
    return acceptPromise
  end)
end

return class.create(function(worker, _, Worker)

  function Worker.initializeWorkerThread(channelName, chunk, jsonData)
    local channel = Channel:new()
    channel:connect(channelName):catch(function(reason)
      logger:fine('Unable to connect thread channel due to '..tostring(reason))
      channel = nil
    end)
    event:loop() -- wait for connection
    if not channel then
      error('Unable to connect thread channel "'..tostring(channelName)..'"')
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('Thread channel "'..tostring(channelName)..'" connected')
    end
    local fn, err = load(chunk, nil, 'b')
    if fn then
      local status, reason = pcall(fn, Worker:new(nil, nil, nil, channel), jsonData and json.decode(jsonData))
      if status then
        logger:finer('Worker initialized')
      else
        local message = 'Worker initialization failure, "'..tostring(reason)..'"'
        logger:fine(message)
        channel:writeMessage(message, MT_ERROR)
      end
    else
      channel:writeMessage('Unable to load chunk due to "'..tostring(err)..'"', MT_ERROR)
    end
  end

  function worker:initialize(workerFn, workerData, scheme, channel)
    if type(workerFn) == 'function' then
      self.pendingMessages = {}
      newThreadChannel(workerFn, workerData, scheme):next(function(ch)
        self._channel = ch
        self:resume()
        --ch:onClose():next(function() self:close() end)
      end)
    elseif channel then
      self._channel = channel
      channel:receiveStart(function(payload, messageType)
        self:handleMessage(payload, messageType)
      end)
      function self:postMessage(message)
        return postMessage(channel, message)
      end
      --channel:onClose():next(function() wkr:close() end)
    else
      error('Invalid arguments')
    end
  end

  function worker:handleMessage(payload, messageType)
    if messageType == MT_STRING then
      self:onMessage(payload)
    elseif messageType == MT_JSON then
      local value = json.decode(payload)
      if value == json.null then
        value = nil
      end
      self:onMessage(value)
    elseif messageType == MT_ERROR then
      logger:fine('Worker error: '..tostring(payload))
      self:close()
    else
      logger:warn('Unexpected message type '..tostring(messageType))
    end
  end

  function worker:pause()
    if not self.pendingMessages then
      self.pendingMessages = {}
      self._channel:receiveStop()
      self.postMessage = nil
    end
  end

  function worker:resume()
    if self.pendingMessages then
      self._channel:receiveStart(function(payload, messageType)
        self:handleMessage(payload, messageType)
      end)
      function self:postMessage(message)
        return postMessage(self._channel, message)
      end
      self:postPendingMessages()
    end
  end

  function worker:postPendingMessages(reason)
    local messages = self.pendingMessages
    if not messages then
      return Promise.resolve()
    end
    self.pendingMessages = nil
    if logger:isLoggable(logger.FINER) then
      logger:finer('worker post '..tostring(#messages)..' pending messages')
    end
    local cb = self.postMessageCallback
    self.postMessagePromise = nil
    self.postMessageCallback = nil
    if reason then
      cb(reason)
      return Promise.resolve()
    end
    local promises = {}
    for _, message in ipairs(messages) do
      table.insert(promises, self:postMessage(message))
    end
    Promise.all(promises):next(function()
      if cb then
        cb()
      end
    end)
  end

  function worker:postMessage(message)
    if self.pendingMessages then
      logger:finer('worker:postMessage() add to pending messages')
      table.insert(self.pendingMessages, message)
      if not self.postMessagePromise then
        self.postMessagePromise, self.postMessageCallback = Promise.createWithCallback()
      end
      return self.postMessagePromise
    end
    return Promise.reject()
  end

  function worker:onMessage(message)
    logger:finer('worker:onMessage() not overriden')
  end

  function worker:close()
    local channel = self._channel
    if channel then
      self._channel = nil
      channel:close(false)
    end
  end

end)
