local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event')
local Exception = require('jls.lang.Exception')
local Thread = require('jls.lang.Thread')
local Channel = require('jls.util.Channel')
local json = require('jls.util.json')
local Buffer = require('jls.lang.Buffer')

local loader = require('jls.lang.loader')
local luvLib = loader.tryRequire('luv')

local MT_STRING = Channel.MESSAGE_ID_USER
local MT_JSON = Channel.MESSAGE_ID_USER + 1
local MT_ERROR = Channel.MESSAGE_ID_USER + 2

local EINPROGRESS = 115

local function postMessage(channel, message)
  if type(message) == 'string' then
    return channel:writeMessage(message, MT_STRING)
  end
  return channel:writeMessage(json.encode(message), MT_JSON)
end

local function newThreadChannel(chunk, jsonData, scheme, receive)
  local thread = Thread:new(function(...)
    require('jls.util.Worker-channel').initializeWorkerThread(...)
    require('jls.lang.event'):loop()
  end)
  logger:finer('newThreadChannel()')
  local channelServer = Channel:new()
  local acceptPromise = channelServer:acceptAndClose()
  return channelServer:bind(nil, scheme):next(function()
    local channelName = channelServer:getName()
    thread:start(channelName, chunk, jsonData, receive):ended():next(function()
      logger:finer('thread ended')
    end)
    return acceptPromise
  end)
end

local AsyncChannel = class.create(function(channel)

  function channel:initialize(async, buffer, thread)
    self.async = async
    self.buffer = buffer
    self.thread = thread
  end

  function channel:close(callback)
    local async, buffer, thread = self.async, self.buffer, self.thread
    self:initialize()
    if async then
      async:close()
    end
    if buffer then
      buffer:setBytes(1, 0)
    end
    if thread then
      thread:join()
    end
    return Promise.applyCallback(callback)
  end

  function channel:isOpen()
    if self.buffer then
      return self.buffer:getBytes() == EINPROGRESS
    end
    return false
  end

  function channel:receiveStart(handleMessage)
    self.handleMessageFn = handleMessage
  end

  function channel:receiveStop()
    self.handleMessageFn = nil
  end

  function channel:writeMessage(payload, id, callback)
    local status, err
    if self.async and not self.thread then
      status, err = self.async:send(payload, id)
      if status then
        return Promise.applyCallback(callback)
      end
    end
    return Promise.applyCallback(callback, err or 'cannot write message')
  end

end)

return class.create(function(worker, _, Worker)

  local function setupWorkerThread(channel, chunk, jsonData, receive)
    logger:fine('setupWorkerThread()')
    local fn, err = load(chunk, nil, 'b')
    if fn then
      local w = class.makeInstance(Worker)
      local data = jsonData and json.decode(jsonData) -- TODO protect
      w:initializeChannel(channel, receive)
      local status, e = Exception.pcall(fn, w, data)
      if status then
        logger:finer('initialized')
      else
        logger:fine('initialization failure, %s', e)
        channel:writeMessage('Initialization failure, "'..tostring(e)..'"', MT_ERROR)
      end
    else
      logger:fine('fail to load chunk, %s', err)
      channel:writeMessage('Unable to load chunk due to "'..tostring(err)..'"', MT_ERROR)
    end
  end

  function Worker.initializeAsyncWorkerThread(async, chunk, jsonData, ref)
    local buffer
    if ref then
      buffer = Buffer.fromReference(ref, 'global')
    end
    local channel = AsyncChannel:new(async, buffer)
    setupWorkerThread(channel, chunk, jsonData, false)
  end

  function Worker.initializeWorkerThread(channelName, chunk, jsonData, receive)
    local channel = Channel:new()
    channel:connect(channelName):catch(function(reason)
      logger:fine('Unable to connect thread channel due to %s', reason)
      channel = nil
    end)
    event:loop() -- wait for connection
    if not channel then
      error('Unable to connect thread channel "'..tostring(channelName)..'"')
    end
    logger:finer('Thread channel "%s" connected', channelName)
    setupWorkerThread(channel, chunk, jsonData, receive)
  end

  function worker:initialize(workerFn, workerData, onMessage, options)
    if type(workerFn) ~= 'function' then
      error('Invalid arguments')
    end
    if type(onMessage) == 'function' then
      self.onMessage = onMessage
    end
    if type(options) ~= 'table' then
      options = {}
    end
    self:pause()
    local chunk = string.dump(workerFn)
    logger:finest('Worker:new() code >>%s<<', chunk)
    local jsonData = workerData and json.encode(workerData) or nil
    local p
    if options.disableReceive and luvLib and not options.scheme then
      local async = luvLib.new_async(function(...)
        logger:fine('async received')
        local ch = self._channel
        local handleMessageFn = ch and ch.handleMessageFn
        if handleMessageFn then
          handleMessageFn(...)
        end
      end)
      local buffer = Buffer.allocate(1, 'global')
      buffer:setBytes(1, EINPROGRESS)
      local thread = Thread:new(function(...)
        require('jls.util.Worker-channel').initializeAsyncWorkerThread(...)
        require('jls.lang.event'):loop()
      end):start(async, chunk, jsonData, buffer:toReference())
      p = Promise.resolve(AsyncChannel:new(async, buffer, thread))
    else
      p = newThreadChannel(chunk, jsonData, options.scheme, not options.disableReceive)
    end
    p:next(function(ch)
      self._channel = ch
      self:resume()
      --ch:onClose():next(function() self:close() end)
    end)
  end

  function worker:initializeChannel(channel, receive)
    self._channel = channel
    if receive then
      channel:receiveStart(function(payload, messageType)
        self:handleMessage(payload, messageType)
      end)
    end
    --channel:onClose():next(function() wkr:close() end)
  end

  function worker:handleMessage(payload, messageType)
    if messageType == MT_STRING then
      self:onMessage(payload)
    elseif messageType == MT_JSON then
      local status, value = pcall(json.decode, payload)
      if status then
        if value == json.null then
          value = nil
        end
        self:onMessage(value)
      else
        logger:warn('Invalid JSON message %s', payload)
        self:close()
      end
    elseif messageType == MT_ERROR then
      logger:warn('Worker error: %s', payload)
      self:close()
    else
      logger:warn('Unexpected message type %s', messageType)
    end
  end

  function worker:pause()
    if not self.pendingMessages then
      self.pendingMessages = {}
      if self._channel then
        self._channel:receiveStop()
      end
    end
  end

  function worker:resume()
    if self.pendingMessages then
      if self._channel then
        self._channel:receiveStart(function(payload, messageType)
          self:handleMessage(payload, messageType)
        end)
      end
      self:postPendingMessages()
    end
  end

  function worker:postPendingMessages()
    local messages = self.pendingMessages
    local cb = self.postMessageCallback
    self.pendingMessages = nil
    self.postMessagePromise = nil
    self.postMessageCallback = nil
    if not messages then
      return
    end
    logger:finer('worker post %l pending messages', messages)
    local promises = {}
    for _, message in ipairs(messages) do
      local p = self:postMessage(message)
      if p then
        table.insert(promises, p)
      end
    end
    Promise.all(promises):next(Promise.callbackToNext(cb))
  end

  function worker:postMessage(message)
    if self.pendingMessages then
      logger:finer('postMessage() add to pending messages')
      table.insert(self.pendingMessages, message)
      if not self.postMessagePromise then
        self.postMessagePromise, self.postMessageCallback = Promise.withCallback()
      end
      return self.postMessagePromise
    elseif self._channel then
      return postMessage(self._channel, message)
    end
    return Promise.reject()
  end

  function worker:onMessage(message)
    logger:finer('onMessage() not overriden')
  end

  function worker:isConnected()
    if self._channel then
      return self._channel:isOpen()
    end
    return false
  end

  function worker:close()
    local channel = self._channel
    if channel then
      self._channel = nil
      channel:close(false)
    end
  end

end)
