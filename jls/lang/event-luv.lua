local luvLib = require('luv')
local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local protectedCall = require('jls.lang.protectedCall')

return class.create(function(event)

  function event:onError(err)
    logger:warn('Event failed due to "'..tostring(err)..'"')
  end

  local function newTimer(callback, timeoutMs, repeatMs, ...)
    local args = table.pack(...)
    local timer = luvLib.new_timer()
    timer:start(timeoutMs, repeatMs, function()
      if not repeatMs or repeatMs <= 0 then
        timer:close()
      end
      local status, err = protectedCall(callback, table.unpack(args, 1, args.n))
      if not status then
        if logger:isLoggable(logger.WARN) then
          logger:warn('event timer callback on error "'..tostring(err)..'"')
        end
      end
    end)
    return timer -- as opaque id
  end

  function event:setTimeout(callback, delayMs, ...)
    return newTimer(callback, delayMs or 0, 0, ...)
  end

  function event:clearTimeout(timer)
    timer:stop()
    timer:close()
  end

  function event:setInterval(callback, delayMs, ...)
    return newTimer(callback, delayMs, delayMs, ...)
  end

  event.setTask = class.notImplementedFunction

  event.clearInterval = event.clearTimeout

  function event:daemon(timer, daemon)
    if daemon then
      luvLib.unref(timer)
    else
      luvLib.ref(timer)
    end
  end

  function event:loop(mode)
    -- returns true if uv_stop() was called and there are still active handles or requests, false otherwise
    -- may returns nil then an error message in case of libuv returning <0
    local ret, err = luvLib.run(mode)
    if ret then
      if logger:isLoggable(logger.FINE) then
        logger:fine('event:loop('..tostring(mode)..') return '..tostring(ret))
      end
    elseif ret == nil then
      if logger:isLoggable(logger.WARN) then
        logger:warn('event:loop('..tostring(mode)..') in error "'..tostring(err)..'"')
      end
    end
  end

  function event:stop()
    luvLib.stop()
  end

  function event:loopAlive()
    return luvLib.loop_alive()
  end

  function event:runOnce()
    self:loop('once')
  end

  function event:close()
    --luvLib.loop_close() -- the loop will automatically be closed when it is garbage collected by Lua
  end

end):new()
