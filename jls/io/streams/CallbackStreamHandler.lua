--- Provide a simple stream handler using a callback function.
-- @module jls.io.streams.CallbackStreamHandler
-- @pragma nostrip

local StreamHandler = require('jls.io.streams.StreamHandler')

--- This class allows to wrap a callback function into a stream.
-- @type CallbackStreamHandler
return require('jls.lang.class').create(StreamHandler, function(callbackStreamHandler)

  --- Creates a @{StreamHandler} based on a callback.
  -- @tparam function cb the callback
  -- @function CallbackStreamHandler:new
  function callbackStreamHandler:initialize(cb)
    self.cb = cb
  end

  function callbackStreamHandler:onData(data)
    return self.cb(nil, data)
  end

  function callbackStreamHandler:onError(err)
    self.cb(err or 'Unspecified error')
  end

  function callbackStreamHandler:toCallback()
    return self.cb
  end

end, function(CallbackStreamHandler)

  --- Returns a StreamHandler.
  -- @param sh a callback function or a StreamHandler.
  -- @return a StreamHandler.
  function CallbackStreamHandler.ensureStreamHandler(sh)
    if type(sh) == 'function' then
      return CallbackStreamHandler:new(sh)
    elseif StreamHandler:isInstance(sh) then
      return sh
    else
      error('Invalid argument (type is '..type(sh)..')')
    end
  end

end)

