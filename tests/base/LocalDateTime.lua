local lu = require('luaunit')

local LocalDateTime = require('jls.util.LocalDateTime')

function Test_new()
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 18):toString(), '2017-12-04T14:01:18')
end

function Test_computeTotalDays()
  lu.assertEquals(LocalDateTime.computeTotalDays(1, 1, 1), 1)
  lu.assertEquals(LocalDateTime.computeTotalDays(2009, 8, 13), 733632)
end

function Test_getDayOfWeek() -- 1-7, Sunday is 1
  lu.assertEquals(LocalDateTime:new(1929, 10, 29):getDayOfWeek(), LocalDateTime.TUESDAY)
  lu.assertEquals(LocalDateTime:new(2009, 8, 13):getDayOfWeek(), LocalDateTime.THURSDAY)
  lu.assertEquals(LocalDateTime:new(2017, 12, 2):getDayOfWeek(), 7)
  lu.assertEquals(LocalDateTime:new(2017, 12, 3):getDayOfWeek(), 1)
  lu.assertEquals(LocalDateTime:new(2017, 12, 4):getDayOfWeek(), 2)
  lu.assertEquals(LocalDateTime:new(2017, 12, 5):getDayOfWeek(), 3)
end

function Test_isLeapYear()
  lu.assertEquals(LocalDateTime:new(1900):isLeapYear(), false)
  lu.assertEquals(LocalDateTime:new(2000):isLeapYear(), true)
  lu.assertEquals(LocalDateTime:new(2004):isLeapYear(), true)
  lu.assertEquals(LocalDateTime:new(2017):isLeapYear(), false)
end

function Test_plusYears()
  lu.assertEquals(LocalDateTime:new(2016, 12, 4, 14, 1, 18):plusYears(1):toString(), '2017-12-04T14:01:18')
end

function Test_plusMonths()
  lu.assertEquals(LocalDateTime:new(2017, 11, 4, 14, 1, 18):plusMonths(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 18):plusMonths(1):toString(), '2018-01-04T14:01:18')
end

function Test_plusDays()
  lu.assertEquals(LocalDateTime:new(2017, 12, 3, 14, 1, 18):plusDays(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 3, 14, 1, 18):plusDays(29):toString(), '2018-01-01T14:01:18')
end

function Test_plusHours()
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 13, 1, 18):plusHours(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 13, 1, 18):plusHours(25):toString(), '2017-12-05T14:01:18')
end

function Test_plusMinutes()
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 0, 18):plusMinutes(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 32, 18):plusMinutes(30):toString(), '2017-12-04T15:02:18')
end

function Test_plusSeconds()
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 17):plusSeconds(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 17):plusSeconds(70):toString(), '2017-12-04T14:02:27')
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 17):plusSeconds(111.11):toString(), '2017-12-04T14:03:08.110')
  lu.assertEquals(LocalDateTime:new():plusSeconds(111.11):toTimeString(), '00:01:51.110')
end

function Test_plusMillis()
  lu.assertEquals(LocalDateTime:new():plusMillis(60000):toTimeString(), '00:01:00')
  lu.assertEquals(LocalDateTime:new():plusMillis(111111):toTimeString(), '00:01:51.111')
end

function Test_toDateString()
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 17):toDateString(), '2017-12-04')
end

local function assertFromToISO(s, e)
  lu.assertEquals(LocalDateTime.fromISOString(s):toString(), e)
  lu.assertEquals(LocalDateTime.fromISOString(string.gsub(s, '[%-:]', '')):toString(), e)
end

function Test_fromISOString()
  assertFromToISO('2017-12-04T14:03:08.110', '2017-12-04T14:03:08.110')
  assertFromToISO('2017-12-04T14:03:08.1109', '2017-12-04T14:03:08.110')
  assertFromToISO('2017-12-04T14:03:08', '2017-12-04T14:03:08')
  assertFromToISO('2017-12-04T14:03', '2017-12-04T14:03:00')
  assertFromToISO('2017-12-04T14', '2017-12-04T14:00:00')
  assertFromToISO('2017-12-04', '2017-12-04T00:00:00')
  assertFromToISO('2017-12', '2017-12-01T00:00:00')
  assertFromToISO('2017', '2017-01-01T00:00:00')
  lu.assertIsNil(LocalDateTime.fromISOString(''))
  lu.assertIsNil(LocalDateTime.fromISOString('17'))
  lu.assertIsNil(LocalDateTime.fromISOString('2017T1'))
  lu.assertIsNil(LocalDateTime.fromISOString('2017-12-04T14:03:082'))
end

os.exit(lu.LuaUnit.run())
