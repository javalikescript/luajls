local event = require('jls.lang.event')

--- Runs the event loop until there is no more registered event or the timeout occurs.
-- This function allows to use asynchronous functions in a blocking way.
-- When called with a function, the event loop is not stopped on timeout,
-- it is the responsability of the function to close pending events.
-- The function fails if the timeout has been reached.
-- @function jls.lang.loopWithTimeout
-- @tparam[opt] number timeout The timeout in milliseconds, default is 5000.
-- @tparam[opt] function onTimeout A function that will be called when the timeout occurs.
-- @treturn boolean false if the timeout has been reached.
return function(timeout, onTimeout)
  local timer
  if type(timeout) == 'function' then
    onTimeout = timeout
    timeout = nil
  end
  timer = event:setTimeout(function()
    timer = nil
    if type(onTimeout) == 'function' and pcall(onTimeout) then
      return
    end
    event:stop()
  end, timeout or 5000)
  event:daemon(timer, true)
  event:loop()
  if timer then
    event:clearTimeout(timer)
    return true
  end
  return false
end
