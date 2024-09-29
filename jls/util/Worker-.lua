--[[--
Provides a way to process tasks in background.

The worker thread interacts with the current thread via message passing.

By default the worker thread has an event loop and will be triggered when receiving message.
You could disable the event loop and incoming messages by using the option `disableReceive`.

@module jls.util.Worker
@pragma nostrip
--]]

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')

--- The Worker class.
-- The Worker provides a way to process task in background.
-- @type Worker
return class.create(function(worker, _, Worker)

  --[[-- Creates a new Worker.
  @function Worker:new
  @tparam function fn the function that the worker will execute
  @param[opt] data the data to pass to the worker function
  @tparam[opt] function onMessage the function that will handle messages
  @tparam[opt] table options the worker options
  @return a new Worker
  @usage
local w = Worker:new(function(w)
  function w:onMessage(message)
    print('received in worker', message)
    w:postMessage('Hi '..tostring(message))
  end
end, nil, function(self, message)
  print('received from worker', message)
  self:close()
end)
w:postMessage('John')
  ]]
  function worker:initialize(fn, data, onMessage)
    if type(fn) ~= 'function' then
      error('Invalid arguments')
    end
    if type(onMessage) == 'function' then
      self.onMessage = onMessage
    end
    local w = class.makeInstance(Worker)
    self._remote = w
    w._remote = self
    fn(w, data) -- posted messages will be lost
  end

  --- Sends a message to the worker.
  -- @param message the message to send
  -- @treturn jls.lang.Promise a promise that resolves once the message is sent
  function worker:postMessage(message)
    self._remote:onMessage(message)
    return Promise.resolve()
  end

  --- Receives a message from the worker.
  -- @param message the message to handle
  function worker:onMessage(message)
    logger:finer('onMessage() not overriden')
  end

  --- Returns true if this worker is connected.
  -- @treturn boolean true if this worker is connected
  function worker:isConnected()
    return self._remote ~= nil
  end

  --- Closes the worker.
  function worker:close()
    if self._remote then
      self._remote._remote = nil
      self._remote = nil
    end
  end

end)
