local lu = require('luaunit')

local Date = require('jls.util.Date')
local Scheduler = require('jls.util.Scheduler')
local Schedule = Scheduler.Schedule
local LocalDateTime = require('jls.util.LocalDateTime')

function assertScheduleParseFormat(r)
  lu.assertEquals(Schedule.parse(r):format(), r)
end

function test_Schedule_parse_format()
  assertScheduleParseFormat('* * * * *')
  assertScheduleParseFormat('0 0 1 1 *')
  assertScheduleParseFormat('59 23 31 12 *')
  assertScheduleParseFormat('0 1 2 3 4')
  assertScheduleParseFormat('0 * * * *')
  assertScheduleParseFormat('* 0 * * *')
  assertScheduleParseFormat('* * 0 * *')
  assertScheduleParseFormat('* * * 0 *')
  assertScheduleParseFormat('* * * * 0')
end

function test_Schedule_parse_format_with_list()
  assertScheduleParseFormat('0,5,10,15,20,25,30,35,40,45,50,55 * * * *')
  lu.assertEquals(Schedule.parse('1,2,3,4,5 * * * *'):format(), '1-5 * * * *')
end

function test_Schedule_parse_format_with_range()
  assertScheduleParseFormat('15-45 * * * *')
  lu.assertIsNil(Schedule.parse('45-15 * * * *'))
end

function test_Schedule_parse_format_with_step()
  lu.assertEquals(Schedule.parse('*/5 * * * *'):format(), '0,5,10,15,20,25,30,35,40,45,50,55 * * * *')
  lu.assertEquals(Schedule.parse('1-30/5 * * * *'):format(), '1,6,11,16,21,26 * * * *')
end

function assertScheduleSlot(r, d, nd)
  lu.assertEquals(Schedule.parse(r):slotDate(d:clone()):toString(), nd:toString())
end

function test_Schedule_slot_hour()
  local ref = LocalDateTime:new(2017, 12, 5, 15, 5)
  assertScheduleSlot('0 * * * *', ref, LocalDateTime:new(2017, 12, 5, 16, 0))
  assertScheduleSlot('11 * * * *', ref, LocalDateTime:new(2017, 12, 5, 15, 11))
  assertScheduleSlot('*/3 * * * *', ref, LocalDateTime:new(2017, 12, 5, 15, 6))
  assertScheduleSlot('*/5 * * * *', ref, LocalDateTime:new(2017, 12, 5, 15, 5))
  assertScheduleSlot('*/15 * * * *', ref, LocalDateTime:new(2017, 12, 5, 15, 15))
  assertScheduleSlot('*/30 * * * *', ref, LocalDateTime:new(2017, 12, 5, 15, 30))
end

function test_Schedule_slot_midnight()
  assertScheduleSlot('0 0 * * *', LocalDateTime:new(2017, 12, 5, 15, 0, 0), LocalDateTime:new(2017, 12, 6, 0, 0, 0))
  assertScheduleSlot('0 0 * * *', LocalDateTime:new(2017, 12, 5, 0, 0, 1), LocalDateTime:new(2017, 12, 6, 0, 0, 0))
  assertScheduleSlot('0 0 * * *', LocalDateTime:new(2017, 12, 5, 0, 0, 0), LocalDateTime:new(2017, 12, 5, 0, 0, 0))
end

function test_Schedule_slot_first_month_day()
  assertScheduleSlot('0 0 1 * *', LocalDateTime:new(2017, 12, 5, 15, 0, 0), LocalDateTime:new(2018, 1, 1, 0, 0, 0))
  assertScheduleSlot('0 0 1 * *', LocalDateTime:new(2017, 12, 1, 0, 0, 0), LocalDateTime:new(2017, 12, 1, 0, 0, 0))
end

function test_Schedule_slot_first_year_day()
  assertScheduleSlot('0 0 1 1 *', LocalDateTime:new(2017, 1, 5, 15, 0, 0), LocalDateTime:new(2018, 1, 1, 0, 0, 0))
  assertScheduleSlot('0 0 1 1 *', LocalDateTime:new(2017, 1, 1, 0, 0, 0), LocalDateTime:new(2017, 1, 1, 0, 0, 0))
end

function test_Scheduler_every_hour()
  local scheduler = Scheduler:new()
  lu.assertEquals(scheduler:hasSchedule(), false)
  local count = 0
  local s = scheduler:schedule('0 * * * *', function(t)
    count = count + 1
  end)
  lu.assertEquals(scheduler:hasSchedule(), true)
  lu.assertEquals(count, 0)
  scheduler:runBetween(Date:new(2017, 1, 5, 15, 5), Date:new(2017, 1, 5, 15, 55))
  lu.assertEquals(count, 0)
  scheduler:runBetween(Date:new(2017, 1, 5, 15, 5), Date:new(2017, 1, 5, 16, 5))
  lu.assertEquals(count, 1)
  count = 0
  scheduler:runBetween(Date:new(2017, 1, 5, 15, 5), Date:new(2017, 1, 5, 18, 55))
  lu.assertEquals(count, 1)
  count = 0
  scheduler:runBetween(Date:new(2017, 1, 5, 15, 5), Date:new(2017, 1, 5, 18, 55), true)
  lu.assertEquals(count, 3)
end

function test_Scheduler_every_day()
  local scheduler = Scheduler:new()
  lu.assertEquals(scheduler:hasSchedule(), false)
  local count = 0
  local s = scheduler:schedule('0 0 * * *', function(t)
    count = count + 1
  end)
  lu.assertEquals(scheduler:hasSchedule(), true)
  lu.assertEquals(count, 0)
  scheduler:runBetween(Date:new(2017, 1, 5, 15, 5), Date:new(2018, 1, 5, 15, 55))
  lu.assertEquals(count, 1)
  count = 0
  scheduler:runBetween(Date:new(2017, 1, 5, 15, 5), Date:new(2018, 1, 5, 15, 55), true)
  lu.assertEquals(count, 365)
end

function test_Scheduler_multiple()
  local scheduler = Scheduler:new()
  local halfCount
  local quarterCount
  local threeCount
  halfCount, quarterCount, threeCount = 0, 0, 0
  scheduler:schedule('*/30 * * * *', function(t)
    halfCount = halfCount + 1
  end)
  scheduler:schedule('*/15 * * * *', function(t)
    quarterCount = quarterCount + 1
  end)
  scheduler:schedule('*/3 * * * *', function(t)
    threeCount = threeCount + 1
  end)
  lu.assertEquals(halfCount, 0)
  lu.assertEquals(quarterCount, 0)
  lu.assertEquals(threeCount, 0)
  scheduler:runBetween(Date:new(2017, 1, 5, 15, 4), Date:new(2017, 1, 5, 15, 5))
  lu.assertEquals(halfCount, 0)
  lu.assertEquals(quarterCount, 0)
  lu.assertEquals(threeCount, 0)
  scheduler:runBetween(Date:new(2017, 1, 5, 15, 29), Date:new(2017, 1, 5, 15, 31))
  lu.assertEquals(halfCount, 1)
  lu.assertEquals(quarterCount, 1)
  lu.assertEquals(threeCount, 1)
end

os.exit(lu.LuaUnit.run())
