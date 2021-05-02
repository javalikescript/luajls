-- This class provides a promise that resolves once the stream is closed.
-- @module jls.io.streams.PromiseStreamHandler
-- @pragma nostrip

local Promise = require('jls.lang.Promise')

-- A PromiseStreamHandler class.
-- This class provides a promise that resolves once the stream is closed.
-- @type PromiseStreamHandler
return require('jls.lang.class').create('jls.io.streams.WrappedStreamHandler', function(promiseStreamHandler, super)

  -- Creates a @{StreamHandler} with a promise.
  -- @tparam[opt] StreamHandler handler the handler to wrap
  -- @function PromiseStreamHandler:new
  function promiseStreamHandler:initialize(handler)
    super.initialize(self, handler)
    self:reset()
  end

  function promiseStreamHandler:reset()
    self.promise, self.promiseCallback = Promise.createWithCallback()
  end

  -- Returns a Promise that resolves once the stream is closed.
  -- @treturn jls.lang.Promise a promise that resolves once the stream is closed.
  function promiseStreamHandler:getPromise()
    return self.promise
  end

  function promiseStreamHandler:onData(data)
    local result = self.handler:onData(data)
    if not data then
      self.promiseCallback()
    end
    return result
  end

  function promiseStreamHandler:onError(err)
    self.handler:onError(err)
    self.promiseCallback(err)
  end

  function promiseStreamHandler:close()
    self.promiseCallback('Closed') -- if not already resolved
  end

end)

