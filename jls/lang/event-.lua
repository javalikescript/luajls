--- Returns the default event instance to execute asynchronous operations.
-- The Event class coordinates distinct asynchronous operations using a single event loop.
-- @module jls.lang.event
-- @pragma nostrip

local logger = require('jls.lang.logger')
local CoroutineScheduler = require('jls.util.CoroutineScheduler')

--- An Event class.
-- @type Event
return require('jls.lang.class').create(function(event)

  --- Creates an Event.
  -- @function Event:new
  function event:initialize()
    self.scheduler = CoroutineScheduler:new()
  end

  --[[--
  Registers a timer which executes a function once after the timer expires.
  @tparam function callback A function that is executed once after the timer expires.
  @tparam[opt=0] number delayMs The time, in milliseconds, the timer should wait before the specified function is executed.
  @return An opaque value identifying the timer that can be used to cancel it.
  @usage
  event:setTimeout(function()
    -- something that have to be done once in 1 second
  end, 1000)
  ]]
  function event:setTimeout(callback, delayMs) -- TODO Use extra arguments as function arguments
    return self.scheduler:schedule(callback, false, delayMs or 0) -- as opaque timer id
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
  function event:setInterval(callback, delayMs) -- TODO Use extra arguments as function arguments
    return self.scheduler:schedule(function()
      while true do
        local status, err = pcall(callback)
        if not status then
          if logger:isLoggable(logger.WARN) then
            logger:warn('event:setInterval() callback on error "'..err..'"')
          end
        end
        coroutine.yield(delayMs)
      end
    end, false, delayMs) -- as opaque timer id
  end

  --- Unregisters a timer.
  -- @param timer the timer as returned by the setTimeout or setInterval method.
  function event:clearInterval(timer)
    self.scheduler:unschedule(timer)
  end

  -- Returns true if the specified timer id is still registered.
  -- @param timer the timer as returned by the setTimeout or setInterval method.
  -- @treturn boolean true if the specified timer id is still registered.
  function event:hasTimer(timer)
    return self.scheduler:isScheduled(timer)
  end

  -- Registers a timer which executes a function until completion.
  -- @tparam function callback A function that is executed repeatedly.
  -- @tparam[opt=0] number delayMs The time, in milliseconds, the timer should wait between to execution.
  -- @return An opaque value identifying the timer that can be used to cancel it.
  function event:setTask(callback, delayMs)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('event:setTask('..tostring(callback)..', '..tostring(delayMs)..')')
    end
    local taskSchedule
    taskSchedule = self.scheduler:schedule(function()
      while true do
        local status, err = pcall(callback, delayMs and delayMs < 0 and self.scheduler:getWaitTime(taskSchedule) or nil)
        if status then
          if not err then
            if logger:isLoggable(logger.DEBUG) then
              logger:debug('event:setTask() callback ends')
            end
            break
          end
        else
          if logger:isLoggable(logger.WARN) then
            logger:warn('event:setTask() callback on error "'..err..'"')
          end
        end
        coroutine.yield(delayMs or 0)
      end
    end, false)
    return taskSchedule -- as opaque timer id
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
