local lu = require('luaunit')

local Date = require('jls.util.Date')

function Test_getTime()
  lu.assertEquals(Date:new(0):getTime(), 0)
  lu.assertEquals(Date:new(1512345678000):getTime(), 1512345678000)
  --lu.assertEquals(Date.UTC(1970, 1, 1, 0, 0, 0), 0)
  lu.assertEquals(Date.UTC(1970, 1, 2, 0, 0, 0), 86400000)
end

function Test_getYear()
  lu.assertEquals(Date:new(0):getYear(), 1970)
  lu.assertEquals(Date:new(1512345678000):getYear(), 2017)
end

function Test_getMonth()
  lu.assertEquals(Date:new(0):getMonth(), 1)
  lu.assertEquals(Date:new(1512345678000):getMonth(), 12)
end

function Test_toISOString()
  lu.assertEquals(Date:new(0):toISOString(true), '1970-01-01T00:00:00.000Z')
  lu.assertEquals(Date:new(1512345678000):toISOString(true), '2017-12-04T00:01:18.000Z')
  lu.assertEquals(Date:new(1512345678020):toISOString(true), '2017-12-04T00:01:18.020Z')
  lu.assertEquals(string.sub(Date:new(2017, 12, 4, 15, 30, 18):toISOString(), 1, 23), '2017-12-04T15:30:18.000')
end

function Test_fromISOString()
  lu.assertEquals(Date.fromISOString('2017-12-04T00:01:18', true), 1512345678000)
end

function Test_toRFC822String()
  lu.assertEquals(Date:new(0):toRFC822String(true), 'Thu, 01 Jan 1970 00:00:00 GMT')
  lu.assertEquals(Date:new(1512345678000):toRFC822String(true), 'Mon, 04 Dec 2017 00:01:18 GMT')
  lu.assertEquals(string.sub(Date:new(2017, 12, 4, 15, 30, 18):toRFC822String(), 1, 25), 'Mon, 04 Dec 2017 15:30:18')
end

function Test_fromRFC822String()
  lu.assertEquals(Date.fromRFC822String('Thu, 02 Jan 1970 00:00:00 GMT'), 86400000)
  lu.assertEquals(Date.fromRFC822String('Mon, 04 Dec 2017 15:30:18 GMT'), Date.UTC(2017, 12, 4, 15, 30, 18))
end

function Test_computeTimezoneOffset()
  lu.assertEquals(Date.computeTimezoneOffset({day = 1, hour = 0, min = 0}, {day = 1, hour = 0, min = 0}), 0)
  lu.assertEquals(Date.computeTimezoneOffset({day = 2, hour = 0, min = 0}, {day = 1, hour = 24, min = 0}), 0)
  lu.assertEquals(Date.computeTimezoneOffset({day = 1, hour = 0, min = 30}, {day = 1, hour = 0, min = 0}), 30)
  lu.assertEquals(Date.computeTimezoneOffset({day = 1, hour = 1, min = 0}, {day = 1, hour = 0, min = 30}), 30)
  lu.assertEquals(Date.computeTimezoneOffset({day = 1, hour = 14, min = 58}, {day = 1, hour = 13, min = 58}), 60)
  lu.assertEquals(Date.computeTimezoneOffset({day = 2, hour = 0, min = 0}, {day = 1, hour = 23, min = 0}), 60)
  lu.assertEquals(Date.computeTimezoneOffset({day = 1, hour = 1, min = 30}, {day = 1, hour = 0, min = 0}), 90)
  lu.assertEquals(Date.computeTimezoneOffset({day = 2, hour = 0, min = 30}, {day = 1, hour = 23, min = 0}), 90)
  lu.assertEquals(Date.computeTimezoneOffset({day = 1, hour = 1, min = 0}, {day = 31, hour = 23, min = 0}), 120)
  lu.assertEquals(Date.computeTimezoneOffset({day = 2, hour = 1, min = 0}, {day = 1, hour = 23, min = 0}), 120)
  lu.assertEquals(Date.computeTimezoneOffset({day = 1, hour = 0, min = 0}, {day = 1, hour = 0, min = 30}), -30)
  lu.assertEquals(Date.computeTimezoneOffset({day = 1, hour = 13, min = 2}, {day = 1, hour = 14, min = 2}), -60)
  lu.assertEquals(Date.computeTimezoneOffset({day = 1, hour = 23, min = 0}, {day = 2, hour = 0, min = 0}), -60)
  lu.assertEquals(Date.computeTimezoneOffset({day = 31, hour = 23, min = 0}, {day = 1, hour = 0, min = 0}), -60)
end

function Test_timestamp()
  lu.assertEquals(Date.timestamp(1512345678000, true), '20171204000118')
  lu.assertEquals(Date.fromTimestamp('20171204000118', true), 1512345678000)
end

function Test_new()
  local ref = Date:new()
  local d = Date:new(ref:getTime())
  lu.assertEquals(d:getTime(), ref:getTime())
end

function Test_new()
  local ref = Date:new()
  local d = Date:new(ref:getTime())
  lu.assertEquals(d:getTime(), ref:getTime())
end

function Test_compareTo_equality()
  local d1 = Date:new(2017, 12, 4, 0, 1, 18)
  local d2 = Date:new(2017, 12, 4, 0, 1, 18)
  lu.assertEquals(d1:compareTo(d2), 0)
end

function Test_compareTo()
  local d1 = Date:new(2017, 12, 4, 0, 1, 18)
  local d2 = Date:new(2017, 12, 4, 10, 1, 18)
  lu.assertTrue(d1:compareTo(d2) < 0)
  lu.assertTrue(d2:compareTo(d1) > 0)
end

function Test_time_ms_add()
  local ref = Date:new()
  local d1 = Date:new(ref:getTime() + 1)
  local d2 = Date:new(ref:getTime())
  d2:setMilliseconds(d2:getMilliseconds() + 1)
  lu.assertEquals(d1:getTime(), d2:getTime())
end

-- the following tests depends on the current locale

function No_Test_new()
  local d = Date:new(2017, 12, 4, 0, 1, 18)
  local offset = d:getTimezoneOffset() * 60000
  lu.assertEquals(d:getTime(), 1512345678000)
end

os.exit(lu.LuaUnit.run())
