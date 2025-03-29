local luvLib = require('luv')
local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Exception = require('jls.lang.Exception')

return class.create(function(event)

  function event:onError(err)
    logger:warn('Event failed due to "%s"', err)
  end

  local function newTimer(callback, timeoutMs, repeatMs, ...)
    local args = table.pack(...)
    local timer = luvLib.new_timer()
    timer:start(timeoutMs, repeatMs, function()
      if repeatMs <= 0 then
        timer:close()
      end
      local status, err = Exception.pcall(callback, table.unpack(args, 1, args.n))
      if not status then
        logger:warn('event timer callback on error "%s"', err)
      end
    end)
    return timer -- as opaque id
  end

  function event:setTimeout(callback, delayMs, ...)
    return newTimer(callback, delayMs or 0, 0, ...)
  end

  function event:clearTimeout(timer)
    if timer then
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
    end
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

  function event:loop()
    -- returns true if uv_stop() was called and there are still active handles or requests, false otherwise
    -- may returns nil then an error message in case of libuv returning <0
    local ret, err = luvLib.run()
    if ret then
      logger:fine('loop() return %s', ret)
    elseif ret == nil then
      logger:fine('loop() in error %s', err)
    end
  end

  function event:stop()
    logger:fine('stop()')
    luvLib.stop()
  end

  function event:loopAlive()
    return luvLib.loop_alive()
  end

  function event:runOnce()
    luvLib.run('once')
  end

  function event:runNoWait()
    luvLib.run('nowait')
  end

  function event:close()
    --luvLib.loop_close() -- the loop will automatically be closed when it is garbage collected by Lua
  end

  function event:print()
    luvLib.print_all_handles()
  end

end):new()
