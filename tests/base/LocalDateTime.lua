local lu = require('luaunit')

local LocalDateTime = require('jls.util.LocalDateTime')

function test_new()
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 18):toString(), '2017-12-04T14:01:18')
end

function test_computeTotalDays()
  lu.assertEquals(LocalDateTime.computeTotalDays(1, 1, 1), 1)
  lu.assertEquals(LocalDateTime.computeTotalDays(2009, 8, 13), 733632)
end

function test_getDayOfWeek() -- 1-7, Sunday is 1
  lu.assertEquals(LocalDateTime:new(1929, 10, 29):getDayOfWeek(), LocalDateTime.TUESDAY)
  lu.assertEquals(LocalDateTime:new(2009, 8, 13):getDayOfWeek(), LocalDateTime.THURSDAY)
  lu.assertEquals(LocalDateTime:new(2017, 12, 2):getDayOfWeek(), 7)
  lu.assertEquals(LocalDateTime:new(2017, 12, 3):getDayOfWeek(), 1)
  lu.assertEquals(LocalDateTime:new(2017, 12, 4):getDayOfWeek(), 2)
  lu.assertEquals(LocalDateTime:new(2017, 12, 5):getDayOfWeek(), 3)
end

function test_isLeapYear()
  lu.assertEquals(LocalDateTime:new(1900):isLeapYear(), false)
  lu.assertEquals(LocalDateTime:new(2000):isLeapYear(), true)
  lu.assertEquals(LocalDateTime:new(2004):isLeapYear(), true)
  lu.assertEquals(LocalDateTime:new(2017):isLeapYear(), false)
end

function test_plusYears()
  lu.assertEquals(LocalDateTime:new(2016, 12, 4, 14, 1, 18):plusYears(1):toString(), '2017-12-04T14:01:18')
end

function test_plusMonths()
  lu.assertEquals(LocalDateTime:new(2017, 11, 4, 14, 1, 18):plusMonths(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 18):plusMonths(1):toString(), '2018-01-04T14:01:18')
end

function test_plusDays()
  lu.assertEquals(LocalDateTime:new(2017, 12, 3, 14, 1, 18):plusDays(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 3, 14, 1, 18):plusDays(29):toString(), '2018-01-01T14:01:18')
end

function test_plusHours()
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 13, 1, 18):plusHours(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 13, 1, 18):plusHours(25):toString(), '2017-12-05T14:01:18')
end

function test_plusMinutes()
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 0, 18):plusMinutes(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 32, 18):plusMinutes(30):toString(), '2017-12-04T15:02:18')
end

function test_plusSeconds()
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 17):plusSeconds(1):toString(), '2017-12-04T14:01:18')
  lu.assertEquals(LocalDateTime:new(2017, 12, 4, 14, 1, 17):plusSeconds(70):toString(), '2017-12-04T14:02:27')
end

os.exit(lu.LuaUnit.run())
