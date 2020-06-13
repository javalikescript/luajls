--- Provide a simple scheduler for coroutines.
-- @module jls.util.CoroutineScheduler

local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local TableList = require('jls.util.TableList')

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
    self.minDelay = 3000
  end

  --- Schedules the specified coroutine.
  -- When yielding the coroutine may indicate the delay or timestamp before this scheduler shall resume it.
  -- Using a negative delay indicates that the coroutine shall be resumed at soon at possible.
  -- If the yield value is a coroutine then it is scheduled with this scheduler.
  -- When a scheduled coroutine dies it is removed from this scheduler
  -- @param cr The coroutine or function to add to this scheduler.
  -- @param daemon true to indicate that the coroutine will not stop the scheduler from running
  -- @param at An optional time for the first resume
  -- @usage local scheduler = CoroutineScheduler:new()
  -- scheduler:schedule(function ()
  --   while true do
  --     print('Hello')
  --     coroutine.yield(15000) -- resume in 15 seconds
  --   end
  -- end, true)
  -- scheduler:run()
  function coroutineScheduler:schedule(cr, daemon, at)
    daemon = daemon or false
    local crType = type(cr)
    if crType == 'function' then
      cr = coroutine.create(cr)
    elseif crType ~= 'thread' then
      error('Cannot schedule a '..crType)
    end
    if type(at) == 'number' then
      local currentTime = system.currentTimeMillis()
      if at < 86400000 then -- one day
        at = currentTime + at
      elseif at < currentTime then
        at = 0
      end
    else
      at = 0
    end
    local schedule = {
      at = at,
      cr = cr,
      daemon = daemon
    }
    table.insert(self.schedules, schedule)
    return schedule
  end

  function coroutineScheduler:unschedule(schedule)
    TableList.removeFirst(self.schedules, schedule)
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
    TableList.contains(self.schedules, schedule)
  end

  function coroutineScheduler:hasSchedule()
    return self:countSchedules() > 0
  end

  --- Stops this scheduler from running.
  function coroutineScheduler:stop()
    self.running = false
  end

  function coroutineScheduler:onError(resumeResult)
    logger:warn('Scheduled coroutine failed due to "'..tostring(resumeResult)..'"')
  end

  function coroutineScheduler:getWaitTime(excludedSchedule)
    local nextTime = math.maxinteger
    for _, schedule in ipairs(self.schedules) do
      if schedule ~= excludedSchedule then
        if schedule.at < nextTime then
          nextTime = schedule.at
        end
      end
    end
    local waitTimeMillis = 0
    if nextTime >= 0 then
      if nextTime == math.maxinteger then
        waitTimeMillis = math.maxinteger
      else
        local currentTime = system.currentTimeMillis()
        waitTimeMillis = nextTime - currentTime
        if waitTimeMillis < 0 then
          waitTimeMillis = 0
        end
      end
    end
    return waitTimeMillis
  end

  function coroutineScheduler:runOnce()
    if logger:isLoggable(logger.FINEST) then
      logger:finest('coroutineScheduler:runOnce() #'..tostring(#self.schedules))
    end
    local startTime = system.currentTimeMillis()
    local currentTime = startTime
    local nextTime = startTime + 3600000 -- one hour
    local count = 0
    for i, schedule in ipairs(self.schedules) do
      local crStatus = coroutine.status(schedule.cr)
      if crStatus == 'dead' then
        schedule = nil
      elseif crStatus == 'suspended' then
        if schedule.at <= currentTime then
          local resumeStatus, resumeResult = coroutine.resume(schedule.cr)
          currentTime = system.currentTimeMillis()
          if resumeStatus then
            if type(resumeResult) == 'thread' then
              self:schedule(resumeResult) -- will processed in this loop
              schedule.at = 0
            elseif type(resumeResult) == 'number' then
              if resumeResult < 0 then
                schedule.at = 0
              elseif resumeResult > startTime then
                schedule.at = resumeResult
              else
                schedule.at = currentTime + resumeResult
              end
            else
              if logger:isLoggable(logger.DEBUG) then
                logger:debug('Schedule resumeResult is '..tostring(resumeResult))
              end
              if coroutine.status(schedule.cr) == 'dead' then
                schedule = nil
              else
                schedule.at = currentTime
              end
            end
          else
            self:onError(resumeResult)
            schedule = nil
          end
        end
      end
      if schedule then
        if schedule.at < nextTime then
          nextTime = schedule.at
        end
        if not schedule.daemon then
          count = count + 1
        end
      else
        -- FIXME The next schedule will be skipped
        table.remove(self.schedules, i)
      end
    end
    if count == 0 then
      return false
    end
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('Schedule count is '..tostring(count))
    end
    local endTime = currentTime -- system.currentTimeMillis()
    local elaspedTime = endTime - startTime
    local sleepTime = 0
    if nextTime > endTime then
      sleepTime = math.floor(nextTime - endTime)
    elseif nextTime > 0 and elaspedTime < self.minDelay then
      sleepTime = math.floor(self.minDelay - elaspedTime)
    end
    if sleepTime > 0 then
      system.sleep(sleepTime)
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
