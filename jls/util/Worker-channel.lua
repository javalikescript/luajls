local class = require('jls.lang.class')
local serialization = require('jls.lang.serialization')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event')
local Exception = require('jls.lang.Exception')
local Thread = require('jls.lang.Thread')
local Channel = require('jls.util.Channel')
local Buffer = require('jls.lang.Buffer')
local Queue = require('jls.util.Queue')

local loader = require('jls.lang.loader')
local luvLib = loader.tryRequire('luv')

local EINPROGRESS = 115

-- TODO Move in a dedicated module
local AsyncChannel = class.create(function(channel)

  function channel:initialize(async, buffer, thread, queue)
    logger:fine('AsyncChannel:new(%s, %s, %s, %s)', async, buffer, thread, queue)
    self.async = async
    self.buffer = buffer
    self.thread = thread
    self.queue = queue
  end

  function channel:close(callback)
    logger:fine('asyncChannel:close()')
    local async, buffer, thread = self.async, self.buffer, self.thread
    self.async, self.thread = nil, nil
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

  function channel:writeMessage(payload, _, callback)
    local status, err
    if self.async and self.queue then
      if self.async:is_closing() then
        err = 'closed'
      else
        if self.queue:enqueue(payload) then
          status, err = self.async:send()
          if status then
            return Promise.applyCallback(callback)
          end
        else
          err = 'not enough space in queue'
        end
      end
    end
    logger:fine('asyncChannel:writeMessage() fails due to %s', err)
    return Promise.applyCallback(callback, err or 'cannot write message')
  end

end)

local function newThreadChannel(chunk, data, options)
  local thread = Thread:new(function(...)
    require('jls.util.Worker-channel').initializeWorkerThread(...)
    require('jls.lang.event'):loop()
  end)
  logger:finer('newThreadChannel()')
  local channelServer = Channel:new()
  local acceptPromise = channelServer:acceptAndClose()
  return channelServer:bind(nil, options.scheme):next(function()
    local channelName = channelServer:getName()
    thread:start(channelName, chunk, data, not options.disableReceive):ended():next(function()
      logger:finer('thread ended')
    end)
    return acceptPromise
  end)
end

local function newThreadAsyncChannel(chunk, data, options)
  local queue = Queue.block(Queue.share(Queue.ringBuffer(Buffer.allocate(options.ringSize or 4096, 'global'))))
  local channel
  ---@diagnostic disable-next-line: need-check-nil
  local async = luvLib.new_async(function()
    logger:finer('async received')
    local handleMessageFn = channel and channel.handleMessageFn
    if handleMessageFn then
      while true do
        local payload = queue:dequeue()
        if payload then
          logger:finer('handling message from queue')
          handleMessageFn(payload)
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
  thread:start(async, chunk, data, buffer, queue)
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
    local p
    if options.disableReceive and options.ringSize and not options.scheme and luvLib then
      p = newThreadAsyncChannel(chunk, workerData, options)
    else
      p = newThreadChannel(chunk, workerData, options)
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
      channel:receiveStart(function(payload)
        self:handleMessage(payload)
      end)
    end
    --channel:onClose():next(function() wkr:close() end)
  end

  function worker:handleMessage(payload)
    local status, message = pcall(serialization.deserialize, payload, '?')
    if status then
      self:onMessage(message)
    else
      logger:warn('Worker error: %s', message)
      self:close()
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
        self._channel:receiveStart(function(payload)
          self:handleMessage(payload)
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
      return self._channel:writeMessage(serialization.serialize(message))
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

  local function setupWorkerThread(channel, chunk, data, receive)
    logger:fine('setupWorkerThread()')
    local fn, err = load(chunk, nil, 'b')
    if fn then
      local w = class.makeInstance(Worker)
      w:initializeChannel(channel, receive)
      local status, e = Exception.pcall(fn, w, data)
      if status then
        logger:finer('initialized')
      else
        logger:fine('initialization failure, %s', e)
        --e = Exception:new('Initialization failure', err)
        channel:writeMessage(serialization.serializeError(e))
      end
    else
      logger:fine('fail to load chunk, %s', err)
      --err = Exception:new('Unable to load chunk', err)
      channel:writeMessage(serialization.serializeError(err))
    end
  end

  function Worker.initializeAsyncWorkerThread(async, chunk, data, buffer, queue)
    local channel = AsyncChannel:new(async, buffer, nil, queue)
    setupWorkerThread(channel, chunk, data, false)
  end

  function Worker.initializeWorkerThread(channelName, chunk, data, receive)
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
    setupWorkerThread(channel, chunk, data, receive)
  end

end)
