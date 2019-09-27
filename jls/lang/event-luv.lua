local luvLib = require('luv')
local logger = require('jls.lang.logger')

return require('jls.lang.class').create(function(event)

  function event:onError(err)
    logger:warn('Event failed due to "'..tostring(err)..'"')
  end
  
  function event:setTimeout(callback, delayMs) -- TODO Use extra arguments as function arguments
    local timer = luvLib.new_timer()
    timer:start(delayMs, 0, function ()
      timer:close()
      --local status, err = pcall(callback)
      local status, err = xpcall(callback, debug.traceback)
      if not status then
        if logger:isLoggable(logger.WARN) then
          logger:warn('event:setTimeout() callback on error "'..err..'"')
        end
      end
    end)
    return timer -- as opaque id
  end
  
  function event:clearTimeout(timer)
    timer:stop()
    timer:close()
  end
  
  function event:setInterval(callback, delayMs) -- TODO Use extra arguments as function arguments
    local timer = luvLib.new_timer()
    timer:start(delayMs, delayMs, function ()
      --local status, err = pcall(callback)
      local status, err = xpcall(callback, debug.traceback)
      if not status then
        if logger:isLoggable(logger.WARN) then
          logger:warn('event:setInterval() callback on error "'..err..'"')
        end
      end
    end)
    return timer -- as opaque id
  end
  
  function event:clearInterval(timer)
    timer:stop()
    timer:close()
  end
  
  function event:loop()
    luvLib.run()
  end
  
  function event:stop()
    luvLib.stop()
  end
  
  function event:loopAlive()
    return luvLib.loop_alive()
  end
  
  function event:runOnce()
    luvLib.run('once')
  end
  
  function event:close()
    --luvLib.loop_close() -- the loop will automatically be closed when it is garbage collected by Lua
  end
end):new()
