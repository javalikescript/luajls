--- Provide a Worker class.
-- @module jls.util.Worker

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')

--- The Worker class.
-- The Worker provides a way to process task in background.
-- @type Worker
return class.create(function(worker, _, Worker)

  --[[-- Creates a new Worker.
  @function Worker:new
  @tparam function workerFn the function that the worker will execute
  @return a new Worker
  @usage
local w = Worker:new(function(w)
  function w:onMessage(message)
    print('received in worker', message)
    w:postMessage('Hi '..tostring(message))
  end
end)
function w:onMessage(message)
  print('received from worker', message)
  self:close()
end
w:postMessage('John')
  ]]
  function worker:initialize(workerFn, workerData)
    if type(workerFn) == 'function' then
      local w = Worker:new()
      function w.postMessage(_, message)
        self:onMessage(message)
        return Promise.resolve()
      end
      function self.postMessage(_, message)
        w:onMessage(message)
        return Promise.resolve()
      end
      workerFn(w, workerData)
    end
  end

  --- Sends a message to the worker.
  -- @param message the message to send
  -- @treturn jls.lang.Promise a promise that resolves once the message is sent.
  function worker:postMessage(message)
  end

  --- Receives a message from the worker.
  -- @param message the message to handle
  function worker:onMessage(message)
  end

  --- Closes the worker.
  function worker:close()
  end

  --- Terminates the worker.
  function worker:terminate()
    self:close()
  end

  function Worker.shutdown()
  end

end)
