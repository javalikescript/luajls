-- This class provides a promise that resolves once the stream is closed.
-- @module jls.io.streams.PromiseStreamHandler
-- @pragma nostrip

local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.StreamHandler')

-- A PromiseStreamHandler class.
-- This class provides a promise that resolves once the stream ended.
-- @type PromiseStreamHandler
return require('jls.lang.class').create(StreamHandler.WrappedStreamHandler, function(promiseStreamHandler, super)

  -- Creates a @{StreamHandler} with a promise.
  -- @tparam[opt] StreamHandler handler the handler to wrap
  -- @function PromiseStreamHandler:new
  function promiseStreamHandler:initialize(handler)
    super.initialize(self, handler)
    self:reset()
  end

  function promiseStreamHandler:reset()
    self.promise, self.promiseCallback = Promise.createWithCallback()
    self.size = 0
  end

  -- Returns a Promise that resolves once the stream ends.
  -- @treturn jls.lang.Promise a promise that resolves once the stream ends.
  function promiseStreamHandler:getPromise()
    return self.promise
  end

  function promiseStreamHandler:onData(data)
    local result = self.handler:onData(data)
    if data then
      self.size = self.size + #data
    else
      if Promise:isInstance(result) then
        result:next(function()
          self.promiseCallback(nil, self.size)
        end)
      else
        self.promiseCallback(nil, self.size)
      end
    end
    return result
  end

  function promiseStreamHandler:onError(err)
    self.handler:onError(err)
    self.promiseCallback(err or 'Error')
  end

  function promiseStreamHandler:close()
    self.promiseCallback('Closed') -- if not already resolved
  end

end)

