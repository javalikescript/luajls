--- Returns the default event instance to execute asynchronous operations.
-- The Event class coordinates distinct asynchronous operations using a single event loop.
-- @module jls.lang.event
-- @pragma nostrip

local logger = require('jls.lang.logger')
local CoroutineScheduler = require('jls.util.CoroutineScheduler')
local Exception = require('jls.lang.Exception')

local TASK_DELAY_MS = os.getenv('JLS_EVENT_TASK_DELAY_MS')
TASK_DELAY_MS = TASK_DELAY_MS and tonumber(TASK_DELAY_MS) or 500

--- An Event class.
-- @type Event
return require('jls.lang.class').create(function(event)

  --- Creates an Event.
  -- @function Event:new
  function event:initialize()
    self.scheduler = CoroutineScheduler:new()
    self.scheduler.maxWait = TASK_DELAY_MS
  end

  --[[--
  Registers a timer which executes a function once after the timer expires.
  @tparam function callback A function that is executed once after the timer expires.
  @tparam[opt=0] number delayMs The time, in milliseconds, the timer should wait before the specified function is executed.
  @param[opt] ... the parameters to pass when calling the function.
  @return An opaque value identifying the timer that can be used to cancel it.
  @usage
  event:setTimeout(function()
    -- something that have to be done once in 1 second
  end, 1000)
  ]]
  function event:setTimeout(callback, delayMs, ...)
    local args = table.pack(...)
    return self.scheduler:schedule(function()
      local status, err = Exception.pcall(callback, table.unpack(args, 1, args.n))
      if not status then
        logger:warn('event:setTimeout() callback in error "%s"', err)
      end
    end, false, delayMs or 0) -- as opaque timer id
  end

  --- Unregisters a timer.
  -- @param timer the timer as returned by the setTimeout or setInterval method.
  function event:clearTimeout(timer)
    self.scheduler:unschedule(timer)
  end

  --[[--
  Registers a timer which executes a function repeatedly with a fixed time delay between each execution.
  @tparam function callback A function that is executed repeatedly.
  @tparam number delayMs The time, in milliseconds, the timer should wait between to execution.
  @return An opaque value identifying the timer that can be used to cancel it.
  @usage
  local intervalId
  intervalId = event:setInterval(function()
    -- something that have to be done every 1 second
    intervalId:clearInterval(intervalId)
  end, 1000)
  ]]
  function event:setInterval(callback, delayMs, ...)
    local args = table.pack(...)
    return self.scheduler:schedule(function(at)
      while true do
        local status, err = Exception.pcall(callback, table.unpack(args, 1, args.n))
        if not status then
          logger:warn('event:setInterval() callback in error "%s"', err)
        end
        at = coroutine.yield(at + delayMs)
      end
    end, false, delayMs) -- as opaque timer id
  end

  --- Unregisters a timer.
  -- @param timer the timer as returned by the setTimeout or setInterval method.
  -- @function event:clearInterval
  event.clearInterval = event.clearTimeout

  -- Returns true if the specified timer id is still registered.
  -- @param timer the timer as returned by the setTimeout or setInterval method.
  -- @treturn boolean true if the specified timer id is still registered.
  function event:hasTimer(timer)
    return self.scheduler:isScheduled(timer)
  end

  -- Registers a timer which executes a function until completion.
  -- A negative delay indicate that the task is able to wait, the callback will receive the maximum delay,
  -- the maximum delay could be 0 when the task should not wait.
  -- @tparam function callback A function that is executed repeatedly.
  -- @tparam[opt] number delayMs The time, in milliseconds, the timer should wait between two executions.
  -- @return An opaque value identifying the timer that can be used to cancel it.
  function event:setTask(callback, delayMs)
    logger:debug('event:setTask(%s, %s)', callback, delayMs)
    if type(delayMs) ~= 'number' then
      delayMs = TASK_DELAY_MS
    end
    return self.scheduler:schedule(function(_, _, timeout)
      while true do
        local status, result = Exception.pcall(callback, timeout)
        if status then
          if not result then
            logger:debug('event:setTask() callback ends')
            break
          end
        else
          logger:warn('event:setTask() callback in error "%s"', result)
          break
        end
        _, _, timeout = coroutine.yield(delayMs)
      end
    end, false, math.min(delayMs, 0)) -- as opaque timer id
  end

  -- Sets the timer daemon flag.
  -- @param timer the timer as returned by the setTimeout or setInterval method.
  -- @tparam[opt=false] boolean daemon true to indicate this timer is a daemon.
  function event:daemon(timer, daemon)
    if type(timer) == 'table' and type(timer.daemon) == 'boolean' then
      timer.daemon = daemon
    end
  end

  --- Runs the event loop until there is no more registered event.
  function event:loop()
    self.scheduler:run()
  end

  --- Stops the event loop.
  function event:stop()
    self.scheduler:stop()
  end

  --- Indicates whether or not this event has at least one registered event.
  -- @treturn boolean true when this event has something to do.
  function event:loopAlive()
    return self.scheduler:hasSchedule()
  end

  --- Runs the event loop once.
  function event:runOnce()
    self.scheduler:runOnce()
  end

  --- Closes this event.
  function event:close()
  end

end):new()
