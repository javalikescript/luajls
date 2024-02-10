--- Provide a simple scheduler for coroutines.
-- The coroutines cooperates to allow concurrent programming, coroutines shall not block.
-- @module jls.util.CoroutineScheduler
-- @pragma nostrip

local logger = require('jls.lang.loggerFactory')(...)
local sysLib = require('jls.lang.sys')
local Exception = require('jls.lang.Exception')
local List = require('jls.util.List')

--logger = logger:getClass():new(logger.FINE)

local TWENTY_FIVE_DAYS_MS = 1000*60*60*24*25

--- A CoroutineScheduler class.
-- A CoroutineScheduler provides a way to coordinate mutliple coroutines.
-- @type CoroutineScheduler
return require('jls.lang.class').create(function(coroutineScheduler)

  --- Creates a new CoroutineScheduler.
  -- @function CoroutineScheduler:new
  -- @return a new CoroutineScheduler
  function coroutineScheduler:initialize()
    self.schedules = {}
    self.running = false
    self.maxSleep = 1000*60*60
    self.maxWait = 500
  end

  --- Schedules the specified coroutine.
  -- The cooperation is based on the time.
  -- When yielding the coroutine may indicate the delay or timestamp before this scheduler shall resume it.
  -- When the delay is more than twenty five days, it is considered as a timestamp.
  -- A negative delay indicates the schedule shall receive a timeout argument.
  -- If the yield value is a coroutine then it is scheduled with this scheduler.
  -- When a scheduled coroutine dies it is removed from this scheduler
  -- @param cr The coroutine or function to add to this scheduler.
  -- @param[opt=false] daemon true to indicate that the coroutine will not stop the scheduler from running
  -- @param[opt=0] at An optional time for the first resume
  -- @usage local scheduler = CoroutineScheduler:new()
  -- scheduler:schedule(function ()
  --   while true do
  --     print('Hello')
  --     coroutine.yield(15000) -- will resume in 15 seconds
  --   end
  -- end)
  -- scheduler:run()
  function coroutineScheduler:schedule(cr, daemon, at)
    local crType = type(cr)
    if crType == 'function' then
      cr = coroutine.create(cr)
    elseif crType ~= 'thread' then
      error('Cannot schedule a '..crType)
    end
    if type(at) == 'number' then
      if at >= 0 and at < TWENTY_FIVE_DAYS_MS then
        at = sysLib.timems() + at
      end
    else
      at = sysLib.timems()
    end
    local schedule = {
      at = at,
      cr = cr,
      daemon = daemon or false
    }
    table.insert(self.schedules, schedule)
    return schedule
  end

  function coroutineScheduler:unschedule(schedule)
    List.removeFirst(self.schedules, schedule)
  end

  function coroutineScheduler:countSchedules()
    local count = 0
    for _, schedule in ipairs(self.schedules) do
      if not schedule.daemon then
        count = count + 1
      end
    end
    return count
  end

  function coroutineScheduler:isScheduled(schedule)
    return List.contains(self.schedules, schedule)
  end

  function coroutineScheduler:hasSchedule()
    return self:countSchedules() > 0
  end

  --- Stops this scheduler from running.
  function coroutineScheduler:stop()
    self.running = false
  end

  function coroutineScheduler:onError(e)
    logger:warn('Scheduled coroutine failed due to "%s"', e)
  end

  function coroutineScheduler:runOnce(noWait)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('coroutineScheduler:runOnce(%s) #%d', noWait, #self.schedules)
    end
    local startTime = sysLib.timems()
    local currentTime = startTime
    local nextTime = startTime + self.maxSleep
    local count = 0
    local hasTimeout = false
    local i = 1
    while true do
      local schedule = self.schedules[i]
      if not schedule then
        break
      end
      local crStatus = coroutine.status(schedule.cr)
      local nextAt
      local at = schedule.at
      if crStatus == 'suspended' then
        if at <= currentTime then
          local timeout
          if at < 0 then -- blocking schedule, compute the timeout
            if nextTime < currentTime or noWait then
              timeout = 0
            else
              local nt = nextTime
              local j = i
              while not timeout do
                j = j + 1
                local ns = self.schedules[j]
                if ns then
                  local nat = ns.at
                  if nat < currentTime then
                    timeout = 0
                  elseif nat < nt then
                    nt = nat
                  end
                else
                  timeout = nt - currentTime
                  if hasTimeout and timeout > self.maxWait then
                    timeout = self.maxWait
                  end
                  -- TODO we do not want the last blocking schedule to block
                  logger:finer('Schedule timeout is %d', timeout)
                end
              end
            end
          end
          local resumeStatus, resumeResult = coroutine.resume(schedule.cr, at, currentTime, timeout)
          local ct = sysLib.timems()
          if logger:isLoggable(logger.FINE) then
            local st = ct - currentTime
            if st > 100 then
              logger:fine('Schedule time was %d', st)
            else
              logger:finest('Schedule time was %d', st)
            end
          end
          currentTime = ct
          if resumeStatus then
            if type(resumeResult) == 'thread' then
              self:schedule(resumeResult)
              nextAt = currentTime
            elseif type(resumeResult) == 'number' then
              if resumeResult >= 0 and resumeResult < TWENTY_FIVE_DAYS_MS then
                nextAt = currentTime + resumeResult
              else
                nextAt = resumeResult
              end
            else
              if resumeResult ~= nil then
                logger:finest('Schedule resume result is %s', resumeResult)
              end
              if coroutine.status(schedule.cr) ~= 'dead' then
                nextAt = currentTime
              end
            end
          else
            if Exception:isInstance(resumeResult) then
              self:onError(resumeResult)
            else
              self:onError(Exception:new(resumeResult, nil, debug.traceback(schedule.cr)))
            end
          end
          schedule.at = nextAt
        else
          nextAt = at
        end
      elseif crStatus ~= 'dead' then -- normal or running, not supported
        nextAt = at
        logger:fine('Schedule status is %s', crStatus)
      end
      if nextAt then
        if nextAt < 0 then
          hasTimeout = true
        elseif nextAt < nextTime then
          nextTime = nextAt
        end
        if not schedule.daemon then
          count = count + 1
        end
        i = i + 1
      else
        coroutine.close(schedule.cr)
        table.remove(self.schedules, i)
      end
    end
    if count == 0 then
      return false
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('Schedule count is %s, has timeout: %s, sleep: %d', count, hasTimeout, nextTime - currentTime)
    end
    if nextTime > currentTime and not hasTimeout and not noWait then
      local st = nextTime - currentTime
      if st > 100 then
        logger:fine('Scheduler sleep time was %d', st)
      end
      sysLib.sleep(st)
    end
    return true
  end

  --- Runs this scheduler.
  -- If there are no schedule for some time then this scheduler will sleep.
  -- When there is no more scheduled coroutine then the scheduler stop running.
  function coroutineScheduler:run()
    self.running = true
    while self.running and self:runOnce() do end
    self.running = false
  end
end)
