local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event')
local Exception = require('jls.lang.Exception')
local Thread = require('jls.lang.Thread')
local Channel = require('jls.util.Channel')
local json = require('jls.util.json')
local Buffer = require('jls.lang.Buffer')
local system = require('jls.lang.system')
local RingBuffer = require('jls.util.RingBuffer')

local loader = require('jls.lang.loader')
local luvLib = loader.tryRequire('luv')

local MT_STRING = Channel.MESSAGE_ID_USER
local MT_JSON = Channel.MESSAGE_ID_USER + 1
local MT_ERROR = Channel.MESSAGE_ID_USER + 2

local EINPROGRESS = 115

local AsyncChannel = class.create(function(channel)

  function channel:initialize(async, buffer, thread, ring, timeout)
    logger:fine('AsyncChannel:new(%s, %s, %s, %s)', async, buffer, thread, ring)
    self.async = async
    self.buffer = buffer
    self.thread = thread
    self.ring = ring
    self.timeout = timeout or 15000
  end

  function channel:close(callback)
    local async, buffer, thread = self.async, self.buffer, self.thread
    self:initialize()
    if async and not async:is_closing() then
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
    if self.async and self.ring then
      if self.async:is_closing() then
        return Promise.applyCallback(callback, 'closed')
      end
      local endTime, delay
      while true do
        status = self.ring:enqueue(payload, id)
        if status then
          logger:finer('message queued to buffer ring')
          break
        end
        local t = system.currentTimeMillis()
        if endTime == nil then
          endTime = t + self.timeout
          delay = 100
        end
        if t >= endTime then
          break
        end
        logger:finer('no space on buffer ring, sleeping %d ms', delay)
        system.sleep(delay)
        if delay < 3000 then
          delay = delay * 2
        end
      end
      if status then
        status, err = self.async:send()
        if status then
          return Promise.applyCallback(callback)
        end
      else
        err = 'not enough space in ring buffer'
      end
    end
    logger:fine('asyncChannel:writeMessage() fails due to %s', err)
    return Promise.applyCallback(callback, err or 'cannot write message')
  end

end)

local function postMessage(channel, message)
  if type(message) == 'string' then
    return channel:writeMessage(message, MT_STRING)
  end
  return channel:writeMessage(json.encode(message), MT_JSON)
end

local function newThreadChannel(chunk, jsonData, options)
  local thread = Thread:new(function(...)
    require('jls.util.Worker-channel').initializeWorkerThread(...)
    require('jls.lang.event'):loop()
  end)
  logger:finer('newThreadChannel()')
  local channelServer = Channel:new()
  local acceptPromise = channelServer:acceptAndClose()
  return channelServer:bind(nil, options.scheme):next(function()
    local channelName = channelServer:getName()
    thread:start(channelName, chunk, jsonData, not options.disableReceive):ended():next(function()
      logger:finer('thread ended')
    end)
    return acceptPromise
  end)
end

local function newThreadAsyncChannel(chunk, jsonData, options)
  local ring = RingBuffer.SyncRingBuffer:new(options.size or 4096)
  local channel
  ---@diagnostic disable-next-line: need-check-nil
  local async = luvLib.new_async(function()
    logger:finer('async received')
    local handleMessageFn = channel and channel.handleMessageFn
    if handleMessageFn then
      while true do
        local payload, id = ring:dequeue()
        if payload then
          logger:finer('handling message from queue')
          handleMessageFn(payload, id)
        else
          break
        end
      end
    end
  end)
  local buffer = Buffer.allocate(1, 'global')
  buffer:setBytes(1, EINPROGRESS)
  local thread = Thread:new(function(...)
    require('jls.util.Worker-channel').initializeAsyncWorkerThread(...)
    require('jls.lang.event'):loop()
  end)
  channel = AsyncChannel:new(async, buffer, thread)
  thread:start(async, chunk, jsonData, buffer:toReference(), ring:toReference())
  return Promise.resolve(channel)
end


return class.create(function(worker)

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
    if options.disableReceive and options.scheme == 'ring' and luvLib then
      p = newThreadAsyncChannel(chunk, jsonData, options)
    else
      p = newThreadChannel(chunk, jsonData, options)
    end
    p:next(function(ch)
      self._channel = ch
      self:resume()
      --ch:onClose():next(function() self:close() end)
    end)
  end

  function worker:initializeChannel(channel, receive)
    logger:finer('initializeChannel() receive: %s', receive)
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

end, function(Worker)

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

  function Worker.initializeAsyncWorkerThread(async, chunk, jsonData, bufferRef, ringRef)
    local buffer, ring
    if bufferRef then
      buffer = Buffer.fromReference(bufferRef, 'global')
    end
    if ringRef then
      ring = RingBuffer.SyncRingBuffer.fromReference(ringRef)
    else
      logger:warn('no ring reference provided')
    end
    local channel = AsyncChannel:new(async, buffer, nil, ring)
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

end)
