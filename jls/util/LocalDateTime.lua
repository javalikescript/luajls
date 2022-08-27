--- Provide a simple LocalDateTime class.
-- @module jls.util.LocalDateTime

local function isLeapYear(year)
  -- there is a leap year every 4 years except every 100 years but still every 400 years
  return ((year % 4) == 0) and (((year % 100) ~= 0) or ((year % 400) == 0))
end

local function getMonthLength(year, month)
  if month == 2 then
    if isLeapYear(year) then
      return 29
    end
    return 28
  end
  if month > 7 then
    if month % 2 == 0 then
      return 31
    end
    return 30
  end
  if month % 2 == 1 then
    return 31
  end
  return 30
end

local function computeTotalDays(year, month, day)
  local totalDays = (year - 1) * 365 + (year // 4) - (year // 100) + (year // 400)
  for m = 1, month - 1 do
    totalDays = totalDays + getMonthLength(year, m)
  end
  return totalDays + day
end

local WEEK_DAYS = {
  SUNDAY = 1,
  MONDAY = 2,
  TUESDAY = 3,
  WEDNESDAY = 4,
  THURSDAY = 5,
  FRIDAY = 6,
  SATURDAY = 7
}

--- The LocalDateTime class.
-- The LocalDateTime provides a way to manipulate local date and time with milli seconds precision.
-- @type LocalDateTime
return require('jls.lang.class').create(function(localDateTime, _, LocalDateTime)

  --- Creates a new LocalDateTime.
  -- @function LocalDateTime:new
  -- @tparam number year the year
  -- @tparam number month the month
  -- @tparam number day the day
  -- @tparam number hour the hour
  -- @tparam number min the min
  -- @tparam number sec the sec
  -- @tparam number ms the ms
  -- @return a new LocalDateTime
  function localDateTime:initialize(year, month, day, hour, min, sec, ms)
    self.year = year or 0
    self.month = month or 1
    self.day = day or 1
    self.hour = hour or 0
    self.min = min or 0
    self.sec = sec or 0
    self.ms = ms or 0
  end

  --- Returns the year of this date.
  -- @treturn number the year.
  function localDateTime:getYear()
    return self.year
  end

  --- Sets the year of this date.
  -- @tparam number value the year.
  -- @return this date.
  function localDateTime:setYear(value)
    self.year = value
    return self
  end

  --- Returns true is this date is in a leap year.
  -- @treturn boolean true is this date is in a leap year.
  function localDateTime:isLeapYear()
    return isLeapYear(self.year)
  end

  --- Returns the month of this date.
  -- @treturn number the month from 1 to 12.
  function localDateTime:getMonth()
    return self.month
  end

  --- Sets the month of this date.
  -- @tparam number value the month.
  -- @return this date.
  function localDateTime:setMonth(value)
    self.month = value
    return self
  end

  --- Returns the day of month of this date.
  -- @treturn number the day of month from 1 to 31.
  function localDateTime:getDayOfMonth()
    return self.day
  end

  --- Sets the day of month of this date.
  -- @tparam number value the day of month.
  -- @return this date.
  function localDateTime:setDayOfMonth(value)
    self.day = value
    return self
  end

  --- Returns the day of week of this date.
  -- @treturn number the day of week from 1 to 7, 1 for Sunday.
  function localDateTime:getDayOfWeek()
    return computeTotalDays(self.year, self.month, self.day) % 7 + 1
  end

  --- Returns the hour of this date.
  -- @treturn number the hour.
  function localDateTime:getHour()
    return self.hour
  end

  --- Sets the hour of this date.
  -- @tparam number value the hour.
  -- @return this date.
  function localDateTime:setHour(value)
    self.hour = value
    return self
  end

  --- Returns the minute of this date.
  -- @treturn number the minute.
  function localDateTime:getMinute()
    return self.min
  end

  --- Sets the minute of this date.
  -- @tparam number value the minute.
  -- @return this date.
  function localDateTime:setMinute(value)
    self.min = value
    return self
  end

  --- Returns the second of this date.
  -- @treturn number the second.
  function localDateTime:getSecond()
    return self.sec
  end

  --- Sets the second of this date.
  -- @tparam number value the second.
  -- @return this date.
  function localDateTime:setSecond(value)
    self.sec = value
    return self
  end

  --- Returns the milli-second of this date.
  -- @treturn number the milli-second.
  function localDateTime:getMillisecond()
    return self.ms
  end

  --- Sets the milli-second of this date.
  -- @tparam number value the milli-second.
  -- @return this date.
  function localDateTime:setMillisecond(value)
    self.ms = value
    return self
  end

  --- Adds year to this date.
  -- @tparam number value the number of year to add.
  -- @return this date.
  function localDateTime:plusYears(value)
    self.year = self.year + value
    return self
  end

  function localDateTime:plusMonths(value)
    local newValue = self.month + value
    if newValue > 12 then
      self:plusYears((newValue - 1) // 12)
      self.month = (newValue - 1) % 12 + 1
    else
      self.month = newValue
    end
    return self
  end

  function localDateTime:getMonthLength()
    return getMonthLength(self.year, self.month)
  end

  function localDateTime:plusDays(value)
    local newValue = self.day + value
    while true do
      local monthLength = self:getMonthLength()
      if newValue <= monthLength then
        self.day = newValue
        break
      end
      newValue = newValue - monthLength
      self:plusMonths(1)
    end
    return self
  end

  function localDateTime:plusHours(value)
    local newValue = self.hour + value
    if newValue >= 24 then
      self:plusDays(newValue // 24)
      self.hour = newValue % 24
    else
      self.hour = newValue
    end
    return self
  end

  function localDateTime:plusMinutes(value)
    local newValue = self.min + value
    if newValue >= 60 then
      self:plusHours(newValue // 60)
      self.min = newValue % 60
    else
      self.min = newValue
    end
    return self
  end

  function localDateTime:plusSeconds(value)
    local mt = math.type(value)
    if mt == 'integer' then
      local newValue = self.sec + math.floor(value)
      if newValue >= 60 then
        self:plusMinutes(newValue // 60)
        self.sec = newValue % 60
      else
        self.sec = newValue
      end
    elseif mt == 'float' then
      self:plusMillis(math.floor(value * 1000))
    end
    return self
  end

  function localDateTime:plusMillis(value)
    local newValue = self.ms + math.floor(value)
    if newValue >= 1000 then
      self:plusSeconds(newValue // 1000)
      self.ms = newValue % 1000
    else
      self.ms = newValue
    end
    return self
  end

  --- Returns a negative, zero or positive value depending if this date
  -- is before, equal or after the specified date.
  -- @tparam LocalDateTime date the local date to compare to.
  -- @treturn number a negative, zero or positive value depending if this date
  -- is before, equal or after the specified date.
  function localDateTime:compareTo(date)
    local delta
    delta = self.year - date.year
    if delta == 0 then
      delta = self.month - date.month
      if delta == 0 then
        delta = self.day - date.day
        if delta == 0 then
          delta = self.hour - date.hour
          if delta == 0 then
            delta = self.min - date.min
            if delta == 0 then
              delta = self.sec - date.sec
              if delta == 0 then
                delta = self.ms - date.ms
              end
            end
          end
        end
      end
    end
    return delta
  end

  function localDateTime:toDateString()
    return string.format('%04d-%02d-%02d', self.year, self.month, self.day)
  end

  function localDateTime:toTimeString(withMillis)
    if self.ms > 0 or withMillis then
      return string.format('%02d:%02d:%02d.%03d', self.hour, self.min, self.sec, self.ms)
    end
    return string.format('%02d:%02d:%02d', self.hour, self.min, self.sec)
  end

  function localDateTime:toString(withMillis)
    if self.ms > 0 or withMillis then
      return string.format('%04d-%02d-%02dT%02d:%02d:%02d.%03d', self.year, self.month, self.day, self.hour, self.min, self.sec, self.ms)
    end
    return string.format('%04d-%02d-%02dT%02d:%02d:%02d', self.year, self.month, self.day, self.hour, self.min, self.sec)
  end

  function localDateTime:toISOString()
    return string.format('%04d-%02d-%02dT%02d:%02d:%02d.%03d', self.year, self.month, self.day, self.hour, self.min, self.sec, self.ms)
  end

end, function(LocalDateTime)

  LocalDateTime.isLeapYear = isLeapYear
  LocalDateTime.getMonthLength = getMonthLength
  LocalDateTime.computeTotalDays = computeTotalDays
  for k, v in pairs(WEEK_DAYS) do
    LocalDateTime[k] = v
  end

  local function nmatch(s, ...)
    local patterns = {...}
    for _, pattern in ipairs(patterns) do
      local t = table.pack(string.match(s, pattern))
      --print('nmatch("'..s..'") "'..pattern..'": ', table.unpack(t, 1, t.n))
      if t[1] then
        return table.unpack(t, 1, t.n)
      end
    end
  end

  local function parseISOTime(s)
    local hour, min, sec, ms, rs, ts
    rs, hour, ts = string.match(s, '^([^T]*)T(%d%d)(.*)$')
    if not rs then
      return s, 0, 0, 0, 0
    end
    min, sec, ms = nmatch(ts, '^:?(%d%d):?(%d%d)(%.%d+)$', '^:?(%d%d):?(%d%d)$', '^:?(%d%d)$', '^$')
    if not min then
      return s, 0, 0, 0, 0
    end
    ms = math.floor((tonumber(ms) or 0) * 1000)
    return rs, tonumber(hour), tonumber(min) or 0, tonumber(sec) or 0, ms
  end

  local function parseISODate(s)
    local year, month, day = nmatch(s, '^(%d%d%d%d)%-?(%d%d)%-?(%d%d)$', '^(%d%d%d%d)%-?(%d%d)$', '^(%d%d%d%d)$')
    if year then
      return tonumber(year), tonumber(month) or 1, tonumber(day) or 1
    end
  end

  function LocalDateTime.fromISOString(s)
    local ds, hour, min, sec, ms = parseISOTime(s)
    local year, month, day = parseISODate(ds)
    if year then
      return LocalDateTime:new(year, month, day, hour, min, sec, ms)
    end
    return nil, 'Invalid date format, '..tostring(s)
  end

end)
