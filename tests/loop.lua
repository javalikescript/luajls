local event = require('jls.lang.event')

return function(onTimeout, timeout)
  local timeoutReached = false
  local timer = event:setTimeout(function()
    timeoutReached = true
    if type(onTimeout) == 'function' then
      if not pcall(onTimeout) then
        event:stop()
      end
    end
  end, timeout or 5000)
  event:daemon(timer, true)
  event:loop()
  if timeoutReached then
    return false
  end
  event:clearTimeout(timer)
  return true
end
