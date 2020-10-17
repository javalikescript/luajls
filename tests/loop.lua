local event = require('jls.lang.event')

return function(onTimeout, timeout)
  local timeoutReached = false
  if not timeout then
    timeout = 5000
  end
  local timer = event:setTimeout(function()
    timeoutReached = true
    if type(onTimeout) == 'function' then
      if not pcall(onTimeout) then
        event:stop()
      end
    end
  end, timeout)
  event:daemon(timer, true)
  event:loop()
  if timeoutReached then
    --lu.assertFalse(timeoutReached, 'timeout reached ('..tostring(timeout)..')')
    error('timeout reached ('..tostring(timeout)..')')
  else
    event:clearTimeout(timer)
  end
end
