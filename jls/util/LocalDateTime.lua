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
-- The LocalDateTime provides a way to manipulate local date and time.
-- @type LocalDateTime
local LocalDateTime = require('jls.lang.class').create(function(localDateTime)

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

  function localDateTime:getYear()
    return self.year
  end

  function localDateTime:setYear(value)
    self.year = value
    return self
  end

  function localDateTime:isLeapYear()
    return isLeapYear(self.year)
  end

  function localDateTime:getMonth() -- 1-12
    return self.month
  end

  function localDateTime:setMonth(value)
    self.month = value
    return self
  end

  function localDateTime:getDayOfMonth() -- 1-31
    return self.day
  end

  function localDateTime:setDayOfMonth(value)
    self.day = value
    return self
  end

  function localDateTime:getDayOfWeek() -- 1-7, Sunday is 1
    return computeTotalDays(self.year, self.month, self.day) % 7 + 1
  end

  function localDateTime:getHour()
    return self.hour
  end

  function localDateTime:setHour(value)
    self.hour = value
    return self
  end

  function localDateTime:getMinute()
    return self.min
  end

  function localDateTime:setMinute(value)
    self.min = value
    return self
  end

  function localDateTime:getSecond()
    return self.sec
  end

  function localDateTime:setSecond(value)
    self.sec = value
    return self
  end

  function localDateTime:getMillisecond()
    return self.ms
  end

  function localDateTime:setMillisecond(value)
    self.ms = value
    return self
  end

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
    local newValue = self.sec + value
    if newValue >= 60 then
      self:plusMinutes(newValue // 60)
      self.sec = newValue % 60
    else
      self.sec = newValue
    end
    return self
  end

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
    return string.format('%04d-%02d-%02dT%02d:%02d:%02d', self.year, self.month, self.day)
  end

  function localDateTime:toTimeString()
    return string.format('%02d:%02d:%02d', self.hour, self.min, self.sec)
  end

  function localDateTime:toString()
    return string.format('%04d-%02d-%02dT%02d:%02d:%02d', self.year, self.month, self.day, self.hour, self.min, self.sec)
  end

  function localDateTime:toISOString()
    return string.format('%04d-%02d-%02dT%02d:%02d:%02d.%03d', self.year, self.month, self.day, self.hour, self.min, self.sec, self.ms)
  end

end)

LocalDateTime.isLeapYear = isLeapYear
LocalDateTime.getMonthLength = getMonthLength
LocalDateTime.computeTotalDays = computeTotalDays
for k, v in pairs(WEEK_DAYS) do
  LocalDateTime[k] = v
end

return LocalDateTime
