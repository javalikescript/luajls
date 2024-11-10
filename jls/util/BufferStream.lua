local luvLib = require('luv')

local class = require('jls.lang.class')
local serialization = require('jls.lang.serialization')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local Buffer = require('jls.lang.Buffer')
local wrapAsync = require('jls.lang.luv_async')
local Queue = require('jls.util.Queue')
local StreamHandler = require('jls.io.StreamHandler')

return class.create(function(bufferStream)

  function bufferStream:initialize(size, outgoingQueue, outgoingAsync, connectAsync)
    self.outgoingQueue = nil
    self.outgoingAsync = nil
    self.incomingQueue = nil
    self.incomingAsync = nil
    if size and size > 0 then
      self.incomingQueue = Queue.share(Queue.ringBuffer(Buffer.allocate(size, 'global')))
      self.incomingAsync = luvLib.new_async(function()
        logger:finer('async recv')
        while self.cb do
          local data = self.incomingQueue:dequeue()
          if data then
            logger:finer('handling message from queue')
            if data == '' then
              self.cb()
            else
              self.cb(nil, data)
            end
          else
            break
          end
        end
      end)
    end
    if outgoingQueue and outgoingAsync then
      if self.incomingAsync then
        self:openAsync(outgoingQueue, outgoingAsync)
      else
        self:open(outgoingQueue, outgoingAsync)
      end
    end
    if connectAsync then
      self:connectAsync(connectAsync)
    end
  end

  function bufferStream:open(outgoingQueue, outgoingAsync)
    if outgoingQueue then
      logger:finer('open(%s, %s)', outgoingQueue, outgoingAsync)
      self.outgoingQueue = outgoingQueue
      self.outgoingAsync = outgoingAsync
    else
      return self.incomingQueue, self.incomingAsync
    end
  end

  function bufferStream:connectAsync(connectAsync)
    logger:finer('connectAsync()')
    if self.incomingQueue and self.incomingAsync then
      connectAsync:send(serialization.serialize(self.incomingQueue), self.incomingAsync)
    else
      error('not enabled')
    end
  end

  function bufferStream:openAsync(outgoingQueue, outgoingAsync)
    if outgoingQueue then
      logger:finer('openAsync(%s, %s)', outgoingQueue, outgoingAsync)
      self.outgoingQueue = outgoingQueue
      self.outgoingAsync = outgoingAsync
    else
      local connectAsync
      connectAsync = luvLib.new_async(function(s, a)
        logger:finer('openAsync() ...recv')
        connectAsync:close()
        local q = serialization.deserialize(s, 'jls.util.Queue')
        self:openAsync(q, wrapAsync(a))
      end)
      return self.incomingQueue, self.incomingAsync, connectAsync
    end
  end

  function bufferStream:write(data, callback)
    logger:finest('write(%x)', data)
    if self.outgoingQueue and self.outgoingAsync then
      logger:finest('write() enqueueAsync()')
      if self.outgoingQueue:enqueue(data) then
        local status, err = self.outgoingAsync:send()
        if not status then
          logger:fine('write() outgoingAsync:send() %s %s', status, err)
        end
        return Promise.applyCallback(callback)
      end
      return Promise.applyCallback(callback, 'cannot enqueue data')
    end
    return Promise.applyCallback(callback, 'not connected')
  end

  function bufferStream:readStart(sh)
    self.cb = StreamHandler.ensureCallback(sh)
    return true
  end

  function bufferStream:readStop()
    self.cb = nil
    return true
  end

  function bufferStream:isClosed()
    if self.incomingQueue and self.incomingAsync then
      return not self.incomingAsync:is_closing()
    end
    return true
  end

  function bufferStream:shutdown(callback)
    if self.outgoingAsync and not self.outgoingAsync:is_closing() then
      self.outgoingAsync:close()
    end
    self.outgoingQueue = nil
    self.outgoingAsync = nil
    return Promise.applyCallback(callback)
  end

  function bufferStream:close(callback)
    self:readStop()
    if self.incomingAsync and not self.incomingAsync:is_closing() then
      self.incomingAsync:close()
    end
    self.incomingQueue = nil
    self.incomingAsync = nil
    return self:shutdown(callback)
  end

end)
