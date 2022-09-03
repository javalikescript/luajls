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

local RFC822_DAYS = {'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'}
local RFC822_MONTHS = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'}
local RFC822_OFFSET_BY_TZ = {GMT = 0, UTC = 0, UT = 0, Z = 0, EST = -5, EDT = -4, CST = -6, CDT = -5, MST = -7,  MDT = -6, PST = -8, PDT = -7}

local ISO_FORMAT = '%Y-%m-%dT%H:%M:%S'
local ISO_FORMAT_UTC = '!%Y-%m-%dT%H:%M:%S'


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

  function date:getTimeInSeconds()
    return self:getTime() // 1000
  end

  function date:setTime(value)
    if type(value) ~= 'number' then
      value = system.currentTimeMillis()
    end
    self.time = value
    self.field = os.date('*t', value // 1000)
    self.field.ms = value % 1000
    return self
  end

  function date:getUTCField()
    if not self.time or not self.utcField then
      self.utcField = os.date('!*t', self:getTimeInSeconds())
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
    return computeTimezoneOffset(self.field, self:getUTCField())
  end

  function date:getTimezoneOffsetHourMin()
    local offset = self:getTimezoneOffset()
    return offset // 60, math.abs(offset) % 60
  end

  --- Compares the specified date to this date.
  -- @param date the date to compare to
  -- @treturn number 0 if the dates are equals, less than 0 if this date is before the specified date, more than 0 if this date is after the specified date
  function date:compareTo(d)
    return self:getTime() - d:getTime()
  end

  function date:toISOString(utc, short)
    local t = self:getTimeInSeconds()
    local mss
    local ms = self.field.ms
    if short and ms == 0 then
      mss = ''
    else
      mss = string.format('.%03d', ms)
    end
    if utc then
      return os.date(ISO_FORMAT_UTC, t)..mss..'Z'
    end
    -- %z does not give the numeric timezone on windows
    local offsetHour, offsetMin = self:getTimezoneOffsetHourMin()
    return os.date(ISO_FORMAT, t)..mss..string.format('%+03d:%02d', offsetHour, offsetMin)
  end

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

  --- Returns the number of milliseconds since epoch for the specified date time.
  -- @tparam number year the year
  -- @tparam[opt] number month the month
  -- @tparam[opt] number day the day
  -- @tparam[opt] number hour the hour
  -- @tparam[opt] number min the min
  -- @tparam[opt] number sec the sec
  -- @tparam[opt] number ms the ms
  -- @treturn number the number of milliseconds since epoch
  function Date.UTC(year, month, day, hour, min, sec, ms)
    -- daylight saving time is around midnigth, so we use noon to compute the UTC time
    local d = Date:new(year, month or 1, day or 1, 12)
    -- we apply the time zone offset
    local t = d:getTime() + d:getTimezoneOffset() * 60000
    -- we apply the time
    t = t + ((((hour or 0) - 12) * 60 + (min or 0)) * 60 + (sec or 0)) * 1000 + (ms or 0)
    return t
  end

  function Date.fromLocalDateTime(dt, utcOrOffsetMinutes)
    if utcOrOffsetMinutes then
      local utcTime = Date.UTC(dt:getYear(), dt:getMonth(), dt:getDayOfMonth(),
        dt:getHour(), dt:getMinute(), dt:getSecond(), dt:getMillisecond())
        if type(utcOrOffsetMinutes) == 'number' then
          utcTime = utcTime - utcOrOffsetMinutes * 60000
        end
        return Date:new(utcTime)
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
    return formatTime(ISO_FORMAT, t, utc)
  end

  function Date.datestamp(t, utc)
    return formatTime('%Y%m%d', t, utc)
  end

  function Date.timestamp(t, utc)
    return formatTime('%Y%m%d%H%M%S', t, utc)
  end

  local function parseISOTimeZone(s)
    if string.find(s, 'Z$') then
      return string.sub(s, 1, -2), 0, 0
    end
    local rs, hour, min = string.match(s, '^(.*)([%+%-]%d%d):?(%d%d)$')
    if rs then
      return rs, tonumber(hour), tonumber(min)
    end
    return s
  end

  function Date.fromISOString(s, utc)
    local rs, hour, min = parseISOTimeZone(s)
    local offsetMin = hour and (hour * 60 + min) or utc
    local ld, err = LocalDateTime.fromISOString(rs)
    if ld then
      return Date.fromLocalDateTime(ld, offsetMin):getTime()
    end
    return nil, err
  end

  local function parseRFC822Month(month)
    month = string.upper(string.sub(month, 1, 1))..string.lower(string.sub(month, 2, 3))
    for i, m in ipairs(RFC822_MONTHS) do
      if m == month then
        return i
      end
    end
  end

  function Date.fromRFC822String(s)
    -- Thu, 01 Jan 1970 00:00:00 GMT
    local wday, mday, month, year, hour, min, sec, tz = string.match(s, '(%a+),%s+(%d+)%s+(%a+)%s+(%d+)%s+(%d+):(%d+):(%d+)%s+([^%s]+)')
    if not wday then
      return nil, 'Bad date format'
    end
    month = parseRFC822Month(month)
    if not month then
      return nil, 'Bad month value'
    end
    local utcTime = Date.UTC(tonumber(year), month, tonumber(mday), tonumber(hour), tonumber(min), tonumber(sec))
    local offsetHour = RFC822_OFFSET_BY_TZ[tz]
    if offsetHour then
      utcTime = utcTime - offsetHour * 60 * 60000
      return utcTime
    end
    local oh, om = string.match(s, '^(.*)([%+%-]%d%d):?(%d%d)$')
    if oh then
      local offsetMin = tonumber(oh) * 60 + tonumber(om)
      utcTime = utcTime - offsetMin * 60000
      return utcTime
    end
    return nil, 'Unsupported time zone format, '..tz
  end

  function Date.fromTimestamp(s, utc)
    local year, month, day, hour, min, sec = string.match(s, '^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)$')
    if not year then
      return nil
    end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, min, sec = tonumber(hour), tonumber(min), tonumber(sec)
    if utc then
      return Date.UTC(year, month, day, hour, min, sec)
    end
    return Date:new(year, month, day, hour, min, sec):getTime()
  end

end)