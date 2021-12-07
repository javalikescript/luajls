--- Provide a simple Date class.
-- @module jls.util.Date
-- @pragma nostrip

local system = require('jls.lang.system')
local LocalDateTime = require('jls.util.LocalDateTime')
local logger = require('jls.lang.logger')


local function computeTimezoneOffset(localField, gmField)
  local day -- there could be one day of difference
  if localField.day == gmField.day then
    day = 0
  else
    day = localField.day - gmField.day
    if math.abs(day) ~= 1 then
      if day > 0 then
        day = -1
      else
        day = 1
      end
    end
  end
  return (day * 1440) + (localField.hour * 60 + localField.min) - (gmField.hour * 60 + gmField.min)
end


--- The Date class.
-- The Date provides a way to manipulate date and time.
-- The Date represents the number of milliseconds since epoch, 1970-01-01T00:00:00 UTC.
-- @type Date
return require('jls.lang.class').create(function(date)

  --- Creates a new Date.
  -- @function Date:new
  -- @tparam number yearOrTime the year or the time in milliseconds.
  -- @tparam[opt] number month the month
  -- @tparam[opt] number day the day
  -- @tparam[opt] number hour the hour
  -- @tparam[opt] number min the min
  -- @tparam[opt] number sec the sec
  -- @tparam[opt] number ms the ms
  -- @return a new Date
  -- @usage Date:new(2017, 12, 4, 0, 1, 18) or Date:new(2017, 12)
  -- Date:new() or Date:new(1512345678000)
  function date:initialize(yearOrTime, month, day, hour, min, sec, ms)
    if month then
      -- hour, min, wday, day, month, year, sec, yday, isdst
      self.field = {
        year = yearOrTime,
        month = month,
        day = day or 1,
        hour = hour or 0,
        min = min or 0,
        sec = sec or 0,
        ms = ms or 0
      }
      --self.time = os.time(self.field)
    else
      self:setTime(yearOrTime)
    end
  end

  --- Returns the year of this date.
  -- @treturn number the year.
  function date:getYear()
    return self.field.year
  end

  function date:setYear(value)
    self.field.year = value
    self.time = nil
    return self
  end

  --- Returns the year of this date.
  -- @treturn number the year.
  function date:getMonth() -- 1-12
    return self.field.month
  end

  function date:setMonth(value)
    self.field.month = value
    self.time = nil
    return self
  end

  --- Returns the year of this date.
  -- @treturn number the year.
  function date:getDay() -- 1-31
    return self.field.day
  end

  function date:setDay(value)
    self.field.day = value
    self.time = nil
    return self
  end

  --- Returns the year of this date.
  -- @treturn number the year.
  function date:getWeekDay() -- 1-7, Sunday is 1
    return self.field.wday
  end

  function date:setWeekDay(value)
    self.field.wday = value
    self.time = nil
    return self
  end

  --- Returns the year of this date.
  -- @treturn number the year.
  function date:getHours()
    return self.field.hour
  end

  function date:setHours(value)
    self.field.hour = value
    self.time = nil
    return self
  end

  --- Returns the year of this date.
  -- @treturn number the year.
  function date:getMinutes()
    return self.field.min
  end

  function date:setMinutes(value)
    self.field.min = value
    self.time = nil
    return self
  end

  --- Returns the year of this date.
  -- @treturn number the year.
  function date:getSeconds()
    return self.field.sec
  end

  function date:setSeconds(value)
    self.field.sec = value
    self.time = nil
    return self
  end

  --- Returns the year of this date.
  -- @treturn number the year.
  function date:getMilliseconds()
    return self.field.ms
  end

  function date:setMilliseconds(value)
    self.field.ms = value
    self.time = nil
    return self
  end

  --- Returns the number of milliseconds since epoch, 1970-01-01T00:00:00 UTC, represented by this date.
  -- @treturn number the number of milliseconds since epoch
  function date:getTime()
    if not self.time then
      -- if logger:isLoggable(logger.FINEST) then
      --   --local status, err = pcall(function() os.time(self.field) end)
      --   logger:finest('date:getTime() field')
      --   logger:finest(self.field)
      -- end
      -- os.time() may fail for date that cannot be represented
      --local sec, err = pcall(os.time, self.field)
      self.time = os.time(self.field) * 1000 + self.field.ms
    end
    return self.time
  end

  function date:setTime(value)
    if type(value) ~= 'number' then
      --value = os.time() * 1000
      value = system.currentTimeMillis()
    end
    self.time = value
    self.field = os.date('*t', value // 1000)
    self.field.ms = value % 1000
    return self
  end

  function date:getUTCField()
    if not self.time or not self.utcField then
      self.utcField = os.date('!*t', self:getTime() // 1000)
      self.utcField.ms = self.field.ms
    end
    return self.utcField
  end

  function date:getUTCYear()
    return self:getUTCField().year
  end

  function date:getUTCMonth()
    return self:getUTCField().month
  end

  function date:getUTCDay()
    return self:getUTCField().day
  end

  function date:getUTCWeekDay()
    return self:getUTCField().wday
  end

  function date:getUTCHours()
    return self:getUTCField().hour
  end

  -- Returns the offset in minutes of this local date from UTC
  function date:getTimezoneOffset()
    return computeTimezoneOffset(self.field, os.date('!*t', self:getTime() // 1000))
  end

  function date:getTimezoneOffsetHourMin()
    local offset = self:getTimezoneOffset()
    return offset // 60, math.abs(offset) % 60
  end

  --- Compares the specified date to this date.
  -- @param date the date to compare to
  -- @treturn number 0 if the dates are equals, less than 0 if this date is before the specified date, more than 0 if this date is after the specified date
  function date:compareTo(date)
    return self:getTime() - date:getTime()
  end

  function date:toShortISOString(utc)
    local t = self:getTime() // 1000
    if utc then
      return os.date('!%Y-%m-%dT%H:%M:%S', t)
    end
    return os.date('%Y-%m-%dT%H:%M:%S', t)
  end

  function date:toISOString(utc)
    local t = self:getTime() // 1000
    if utc then
      return os.date('!%Y-%m-%dT%H:%M:%S', t)..string.format('.%03dZ', self.field.ms)
    end
    -- %z does not give the numeric timezone on windows
    local offsetHour, offsetMin = self:getTimezoneOffsetHourMin()
    return os.date('%Y-%m-%dT%H:%M:%S', t)..string.format('.%03d%+03d:%02d', self.field.ms, offsetHour, offsetMin)
  end

  local RFC822_DAYS = {'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'}
  local RFC822_MONTHS = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'}

  function date:toRFC822String(utc)
    -- Sun, 06 Nov 1994 08:49:37 GMT -- os.date('%a, %d %b %y %T %z')
    if utc then
      local utcField = self:getUTCField()
      return string.format('%s, %02d %s %02d %02d:%02d:%02d GMT',
        RFC822_DAYS[utcField.wday], utcField.day, RFC822_MONTHS[utcField.month], utcField.year,
        utcField.hour, utcField.min, utcField.sec)
    end
    local offsetHour, offsetMin = self:getTimezoneOffsetHourMin()
    return string.format('%s, %02d %s %02d %02d:%02d:%02d %+03d%02d',
      RFC822_DAYS[self.field.wday], self.field.day, RFC822_MONTHS[self.field.month], self.field.year,
      self.field.hour, self.field.min, self.field.sec, offsetHour, offsetMin)
  end

  function date:toLocalDateTime()
    return LocalDateTime:new(self.field.year, self.field.month, self.field.day,
      self.field.hour, self.field.min, self.field.sec, self.field.ms)
  end
end, function(Date)

  Date.computeTimezoneOffset = computeTimezoneOffset

  --- Returns the number of milliseconds since epoch, 1970-01-01T00:00:00 UTC.
  -- @treturn number the number of milliseconds since epoch
  function Date.now()
    return system.currentTimeMillis()
  end

  function Date.UTC(...)
    local d = Date:new(...)
    return d:getTime() + (d:getTimezoneOffset() * 60000)
  end

  function Date.fromLocalDateTime(dt, utc)
    if utc then
      return Date:new(Date.UTC(dt:getYear(), dt:getMonth(), dt:getDayOfMonth(),
        dt:getHour(), dt:getMinute(), dt:getSecond(), dt:getMillisecond()))
    end
    return Date:new(dt:getYear(), dt:getMonth(), dt:getDayOfMonth(),
      dt:getHour(), dt:getMinute(), dt:getSecond(), dt:getMillisecond())
  end

  local function formatTime(f, t, utc)
    if t then
      t = t // 1000
    else
      t = os.time()
    end
    if utc then
      f = '!'..f
    end
    return os.date(f, t)
  end

  function Date.iso(t, utc)
    return formatTime('%Y-%m-%dT%H:%M:%S', t, utc)
  end

  function Date.datestamp(t, utc)
    return formatTime('%Y%m%d', t, utc)
  end

  function Date.timestamp(t, utc)
    return formatTime('%Y%m%d%H%M%S', t, utc)
  end

  local function parseISOString(s, lenient)
    local pattern
    if lenient then
      pattern = '^(%d%d%d%d)%D(%d%d)%D(%d%d)%D(%d%d)%D(%d%d)%D(%d%d)(.*)$'
    else
      pattern = '^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d)%:(%d%d)%:(%d%d)(.*)$'
    end
    local year, month, day, hour, min, sec, rs = string.match(s, pattern)
    if not year then
      return nil
    end
    local ms
    if rs then
      ms = string.match(rs, '^%.(%d%d%d)Z?$')
    end
    return tonumber(year), tonumber(month), tonumber(day),
      tonumber(hour), tonumber(min), tonumber(sec), tonumber(ms) or 0
  end

  function Date.fromISOString(s, utc, lenient)
    if utc then
      return Date.UTC(parseISOString(s, lenient))
    end
    return Date:new(parseISOString(s, lenient)):getTime()
  end

  function Date.fromTimestamp(s, utc)
    local year, month, day, hour, min, sec = string.match(s, '^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)$')
    if not year then
      return nil
    end
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    hour = tonumber(hour)
    min = tonumber(min)
    sec = tonumber(sec)
    if utc then
      return Date.UTC(year, month, day, hour, min, sec)
    end
    return Date:new(year, month, day, hour, min, sec):getTime()
  end

end)