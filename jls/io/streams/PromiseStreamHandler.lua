-- This class provides a promise that resolves once the stream is closed.
-- @module jls.io.streams.PromiseStreamHandler
-- @pragma nostrip

local Promise = require('jls.lang.Promise')

-- A PromiseStreamHandler class.
-- This class provides a promise that resolves once the stream is closed.
-- @type PromiseStreamHandler
return require('jls.lang.class').create(require('jls.io.streams.StreamHandler'), function(promiseStreamHandler, super)

  -- Creates a @{StreamHandler} with a promise.
  -- @function PromiseStreamHandler:new
  function promiseStreamHandler:initialize()
    super.initialize(self)
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
    if not data then
      self.promiseCallback()
    end
  end

  function promiseStreamHandler:onError(err)
    self.promiseCallback(err)
  end

end)

