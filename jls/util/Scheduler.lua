--- Provide a simple scheduler.
-- @module jls.util.Scheduler
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local TableList = require('jls.util.TableList')
local Date = require('jls.util.Date')


--- The Schedule class.
-- @type Schedule
local Schedule = class.create(function(schedule)

  --- Creates a new Schedule.
  -- @function Schedule:new
  -- @tparam table minute a list of range for the minutes, 0-59
  -- @tparam table hour a list of range for the hours, 0-23
  -- @tparam table day a list of range for the days, 1-31
  -- @tparam table month a list of range for the months, 1-12
  -- @tparam table weekDay a list of range for the weekDays, 0-6 Sunday to Saturday
  -- @return a new Schedule
  function schedule:initialize(minute, hour, day, month, weekDay)
    self.minute = minute     -- 0-59
    self.hour = hour         -- 0-23
    self.day = day           -- 1-31
    self.month = month       -- 1-12
    self.weekDay = weekDay   -- 0-6 Sunday to Saturday
  end

  local function formatScheduleField(list)
    local n = #list
    if n == 0 then
      return '*'
    end
    local field, from, to, value, fieldPart
    for i = 1, n + 1 do
      value = list[i]
      if not to or not value or value ~= to + 1 then
        if from then
          if from == to then
            fieldPart = tostring(from)
          else
            fieldPart = tostring(from)..'-'..tostring(to)
          end
          if field then
            field = field..','..fieldPart
          else
            field = fieldPart
          end
        end
        from = value
      end
      to = value
    end
    return field
  end

  --- Returns a string representation of this schedule.
  -- @treturn string a representation of this schedule.
  function schedule:format()
    local minute = formatScheduleField(self.minute)
    local hour = formatScheduleField(self.hour)
    local day = formatScheduleField(self.day)
    local month = formatScheduleField(self.month)
    local weekDay = formatScheduleField(self.weekDay)
    if minute and hour and day and month and weekDay then
      return minute..' '..hour..' '..day..' '..month..' '..weekDay
    end
    return nil
  end

  local function fieldNext(list, value)
    local n = #list
    if n == 0 then
      return value -- accept any value
    end
    for _, v in ipairs(list) do
      if v >= value then
        return v
      end
    end
    return list[1] -- take the first available value
  end

  function schedule:slotMonth(date)
    local value = date:getMonth()
    local nextValue = fieldNext(self.month, value)
    if nextValue ~= value then
      date:setMonth(nextValue)
      date:setDayOfMonth(fieldNext(self.day, 1))
      date:setHour(fieldNext(self.hour, 0))
      date:setMinute(fieldNext(self.minute, 0))
      if nextValue < value then
        date:plusYears(1)
      end
    end
    --logger:finest('schedule:slotMonth() => '..date:toISOString())
    return date
  end

  function schedule:slotDay(date)
    --[[
      The specification of days can be made by two fields (day of the month and day of the week).
      If month, day of month, and day of week are all asterisks, every day shall be matched.
      If either the month or day of month is specified as an element or list, but the day of week is an asterisk,
      the month and day of month fields shall specify the days that match.
      If both month and day of month are specified as an asterisk, but day of week is an element or list,
      then only the specified days of the week match.
      Finally, if either the month or day of month is specified as an element or list, and the day of week is also specified as an element or list,
      then any day matching either the month and day of month, or the day of week, shall be matched.
      See http://pubs.opengroup.org/onlinepubs/007904975/utilities/crontab.html
    ]]
    local hasWeekDay = #self.weekDay > 0
    local hasDay = #self.day > 0
    local value = date:getDayOfMonth()
    -- Check week day
    local nextValue, nextWeekDay, weekDay
    if hasDay then
      nextValue = fieldNext(self.day, value)
      if hasWeekDay then
        weekDay = date:getDayOfWeek()
        nextWeekDay = fieldNext(self.weekDay, weekDay)
        local nextWeekDayValue = value + (nextWeekDay - weekDay + 7) % 7
        if nextWeekDayValue < nextValue then
          nextValue = nextWeekDayValue
        end
      end
    elseif hasWeekDay then
      weekDay = date:getDayOfWeek()
      nextWeekDay = fieldNext(self.weekDay, weekDay)
      if weekDay ~= nextWeekDay then
        nextValue = value + (nextWeekDay - weekDay + 7) % 7
      else
        nextValue = value
      end
    else
      nextValue = value
    end
    if nextValue ~= value then
      local monthLength = date:getMonthLength()
      -- TODO Check month length
      date:setDayOfMonth(nextValue)
      date:setHour(fieldNext(self.hour, 0))
      date:setMinute(fieldNext(self.minute, 0))
      if nextValue < value then
        date:plusMonths(1)
        --logger:finest('schedule:slotDay() ... '..date:toISOString())
        return self:slotMonth(date)
      end
    end
    return date
  end

  function schedule:slotHour(date)
    local value = date:getHour()
    local nextValue = fieldNext(self.hour, value)
    if nextValue ~= value then
      date:setHour(nextValue)
      date:setMinute(fieldNext(self.minute, 0))
      if nextValue < value then
        date:plusDays(1)
        --logger:finest('schedule:slotHour() ... '..date:toISOString())
        return self:slotDay(date)
      end
    end
    return date
  end

  function schedule:slotMinute(date)
    local value = date:getMinute()
    local nextValue = fieldNext(self.minute, value)
    if nextValue ~= value then
      date:setMinute(nextValue)
      if nextValue < value then
        date:plusHours(1)
        --logger:finest('schedule:slotMinute() ... '..date:toISOString())
        return self:slotHour(date)
      end
    end
    --logger:finest('schedule:slotMinute() => '..date:toISOString())
    return date
  end

  function schedule:slotDate(date)
    if date:getSecond() ~= 0 or date:getMillisecond() ~= 0 then
      date:setMillisecond(0)
      date:setSecond(0)
      date:plusMinutes(1)
    end
    if logger:isLoggable(logger.FINEST) then
      logger:finest('schedule:slotDate('..date:toISOString()..')')
    end
    return self:slotMinute(self:slotHour(self:slotDay(self:slotMonth(date))))
  end

  function schedule:ofDate(date)
    if not date then
      date = Date:new()
    end
    return Date.fromLocalDateTime(self:slotDate(date:toLocalDateTime()))
  end

end)

local function parseScheduleField(field, min, max)
  local list = {}
  if field == '*' then
    return list
  end
  local range, step = string.match(field, '^([%*0-9%-]+)/([0-9]+)$')
  if step then
    local from, to
    if range == '*' then
      from, to = min, max
    else
      from, to = string.match(range, '^([0-9]+)-([0-9]+)$')
      if from and to then
        from = tonumber(from)
        to = tonumber(to)
        if from < min then
          from = min
        end
        if to > max then
          to = max
        end
      end
    end
    step = tonumber(step)
    if step and from and to and step > 0 and from < to then
      for i = from, to, step do
        table.insert(list, i)
      end
      return list
    else
      return nil
    end
  end
  for range in string.gmatch(field, '[^,]+') do
    local from, to = string.match(range, '^([0-9]+)-([0-9]+)$')
    if from then
      from = tonumber(from)
      to = tonumber(to)
    else
      to = tonumber(range)
      from = to
    end
    if from and to then
      if from == to then
        table.insert(list, from)
      elseif from < to then
        for i = from, to do
          table.insert(list, i)
        end
      else
        return nil
      end
    else
      return nil
    end
  end
  table.sort(list)
  return list
end

--- Returns a new schedule from the specified string.
-- The string representation is similar of the cron syntax, see https://en.wikipedia.org/wiki/Cron
-- The value is a space separated list of definition for the minute, hour, day, month, weekDay fields.
-- Each field could be a comma separated list of numerical value, numerical range, the star symbol.
-- A range can be followed by a slash and a numerical value indicating the step to use in the range.
-- @tparam string value the string representation of the schedule
-- @treturn Schedule the new schedule
function Schedule.parse(value)
  local minute, hour, day, month, weekDay = string.match(value,
    '^([0-9%*,%-/]+) +([0-9%*,%-/]+) +([0-9%*,%-/]+) +([0-9%*,%-/]+) +([0-9%*,%-/]+)') -- ignore remainings
  if not minute then
    return nil
  end
  minute = parseScheduleField(minute, 0, 59)
  hour = parseScheduleField(hour, 0, 23)
  day = parseScheduleField(day, 1, 31)
  month = parseScheduleField(month, 1, 12)
  weekDay = parseScheduleField(weekDay, 0, 6)
  if minute and hour and day and month and weekDay then
    return Schedule:new(minute, hour, day, month, weekDay)
  end
  return nil
end

local function currentDate()
  local now = Date:new()
  now:setSeconds(0)
  now:setMilliseconds(0)
  return now
end

local function plusMilliseconds(date, value)
  if type(value) ~= 'number' then
    value = 1
  end
  return Date:new(date:getTime() + value)
end

--- A Scheduler class.
-- @type Scheduler
local Scheduler = class.create(function(scheduler)

  --- Creates a new Scheduler.
  -- @function Scheduler:new
  -- @return a new Scheduler
  function scheduler:initialize()
    self.schedules = {}
    self.running = false
    self.previous = nil
    self.next = nil
  end

  --- Schedules the specified function using the specified schedule.
  -- @param schedule the schedule as a string or a @{Schedule}
  -- @tparam function fn the function to call depending on the schedule
  -- @return an opaque schedule id that can be used to remove the schedule from this scheduler
  -- @usage
  --local scheduler = Scheduler:new()
  --local fn = function()
  --  print(os.date())
  --end
  --scheduler:schedule('0 * * * *', fn) -- every hour
  --scheduler:schedule('*/5 * * * *', fn) -- every five minutes
  --scheduler:schedule('0 0 * * *', fn) -- every day at midnight
  --scheduler:schedule('0 0 * * 1-5', fn) -- every weekday at midnight
  --scheduler:schedule('0 0 1 * *', fn) -- every first day of the month at midnight
  --scheduler:schedule('0 0 1 1 *', fn) -- every year the 1st January at midnight
  function scheduler:schedule(schedule, fn)
    if type(schedule) == 'string' then
      schedule = Schedule.parse(schedule)
    end
    if not schedule then
      return nil, 'Invalid or missing schedule'
    end
    if logger:isLoggable(logger.FINEST) then
      logger:finest('scheduler:schedule('..schedule:format()..')')
    end
    local t = {
      schedule = schedule,
      fn = fn
    }
    table.insert(self.schedules, t)
    self.next = nil
    return t -- scheduleId
  end

  function scheduler:removeSchedule(scheduleId)
    TableList.removeFirst(self.schedules, scheduleId)
  end

  function scheduler:removeAllSchedules()
    self.schedules = {}
  end

  function scheduler:hasSchedule()
    return #self.schedules > 0
  end

  --- Stops this scheduler from running.
  function scheduler:stop()
    self.running = false
  end

  function scheduler:onError(err)
    logger:warn('Scheduled failed due to "'..tostring(err)..'"')
  end

  function scheduler:runScheduleAt(t, date)
    local status, err = pcall(function ()
      t.fn(date:getTime())
    end)
    if not status then
      self:onError(err)
    end
  end

  -- ]from, to]
  function scheduler:runBetween(from, to, all)
    if not from then
      from = plusMilliseconds(to, -1)
    end
    if logger:isLoggable(logger.FINEST) then
      logger:finest('scheduler:runBetween('..from:toISOString(true)..', '..to:toISOString(true)..') #'..tostring(#self.schedules))
    end
    local nearest
    for _, t in ipairs(self.schedules) do
      local date = from
      local latestDate = nil
      while true do
        date = t.schedule:ofDate(plusMilliseconds(date))
        if date:compareTo(to) > 0 then
          if logger:isLoggable(logger.FINEST) then
            logger:finest('scheduler:runBetween() => '..t.schedule:format()..' next '..date:toISOString(true))
          end
          if not nearest or date:compareTo(nearest) < 0 then
            nearest = date
          end
          break
        end
        if all then
          self:runScheduleAt(t, date)
        end
        latestDate = date
      end
      if not all and latestDate then
        self:runScheduleAt(t, latestDate)
      end
    end
    return nearest
  end

  function scheduler:runTo(date, all)
    if not date then
      date = currentDate()
    end
    if self.previous and date:compareTo(self.previous) <= 0 then
      if logger:isLoggable(logger.FINE) then
        logger:fine('scheduler:runTo('..date:toISOString(true)..') => already run')
      end
      return nil, "already run"
    end
    if self.next and date:compareTo(self.next) < 0 then
      if logger:isLoggable(logger.FINE) then
        logger:fine('scheduler:runTo('..date:toISOString(true)..') => before next '..self.next:toISOString(true))
      end
      return self.next:getTime() - date:getTime()
    end
    self.next = self:runBetween(self.previous, date, all)
    self.previous = date
    if not self.next then
      if logger:isLoggable(logger.FINE) then
        logger:fine('scheduler:runTo('..date:toISOString(true)..') => no schedule')
      end
      return nil, "no schedule"
    end
    return self.next:getTime() - date:getTime()
  end

  function scheduler:clearRunTo()
    self.previous = nil
  end

  --- Runs this scheduler.
  -- If there are no schedule for some time then this scheduler will sleep.
  function scheduler:run()
    self.running = true
    while self.running do
      local delay = self:runTo()
      system.sleep(math.min(math.max(60000, delay or 0), 300000))
    end
    self.running = false
  end

end)

Scheduler.currentDate = currentDate
Scheduler.Schedule = Schedule

return Scheduler