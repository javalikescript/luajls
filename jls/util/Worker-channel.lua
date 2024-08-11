local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event')
local Exception = require('jls.lang.Exception')
local Thread = require('jls.lang.Thread')
local Channel = require('jls.util.Channel')
local json = require('jls.util.json')

local MT_STRING = Channel.MESSAGE_ID_USER
local MT_JSON = Channel.MESSAGE_ID_USER + 1
local MT_ERROR = Channel.MESSAGE_ID_USER + 2

local function postMessage(channel, message)
  if type(message) == 'string' then
    return channel:writeMessage(message, MT_STRING)
  end
  return channel:writeMessage(json.encode(message), MT_JSON)
end

local function newThreadChannel(fn, data, scheme, receive)
  local chunk = string.dump(fn)
  logger:finest('newThreadChannel() code >>%s<<', chunk)
  local jsonData = data and json.encode(data) or nil
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

return class.create(function(worker, _, Worker)

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
    local fn, err = load(chunk, nil, 'b')
    if fn then
      local data = jsonData and json.decode(jsonData) -- TODO protect
      local w = class.makeInstance(Worker)
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

  function worker:initialize(workerFn, workerData, scheme, disableReceive)
    if type(workerFn) == 'function' then
      self.pendingMessages = {}
      newThreadChannel(workerFn, workerData, scheme, not disableReceive):next(function(ch)
        self._channel = ch
        self:resume()
        --ch:onClose():next(function() self:close() end)
      end)
    else
      error('Invalid arguments')
    end
  end

  function worker:initializeChannel(channel, receive)
    self._channel = channel
    if receive then
      channel:receiveStart(function(payload, messageType)
        self:handleMessage(payload, messageType)
      end)
    end
    function self:postMessage(message)
      return postMessage(channel, message)
    end
    --channel:onClose():next(function() wkr:close() end)
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
      logger:fine('Worker error: %s', payload)
      self:close()
    else
      logger:warn('Unexpected message type %s', messageType)
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
    end
    return Promise.reject()
  end

  function worker:onMessage(message)
    logger:finer('onMessage() not overriden')
  end

  function worker:close()
    local channel = self._channel
    if channel then
      self._channel = nil
      channel:close(false)
    end
  end

end)
