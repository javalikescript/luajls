local lu = require('luaunit')

local StringBuffer = require('jls.lang.StringBuffer')

local function assertEquals(value, expected)
  lu.assertEquals(value:clone():toString(), expected)
  lu.assertEquals(value:length(), string.len(expected))
end

function Test_toString()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' world !')
  assertEquals(buffer, 'Hello world !')
end

function Test_intial_value()
  assertEquals(StringBuffer:new(), '')
  assertEquals(StringBuffer:new('Hi'), 'Hi')
  assertEquals(StringBuffer:new('Hello', ' world !'), 'Hello world !')
end

function Test_append()
  assertEquals(StringBuffer:new():append('Hello'):append(' world !'), 'Hello world !')
  assertEquals(StringBuffer:new('Hello'):append(' world !'), 'Hello world !')
  assertEquals(StringBuffer:new():append('Hello', ' world !'), 'Hello world !')
  assertEquals(StringBuffer:new():append('Hello'):append(nil):append(' world !'), 'Hello world !')
  assertEquals(StringBuffer:new():append('Hello', nil, ' world !'), 'Hello world !')
  assertEquals(StringBuffer:new():append(StringBuffer:new('Hello', ' world !')), 'Hello world !')
  assertEquals(StringBuffer:new():append(1, ' ', true), '1 true')
  assertEquals(StringBuffer:new():append({}):sub(1, 5), 'table')
end

function Test_charAt()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  lu.assertEquals(buffer:charAt(0), '')
  lu.assertEquals(buffer:charAt(1), 'H')
  lu.assertEquals(buffer:charAt(7), 't')
  lu.assertEquals(buffer:charAt(11), 'W')
  lu.assertEquals(buffer:charAt(99), '')
end

function Test_byte()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  lu.assertIsNil(buffer:byte(0))
  lu.assertEquals(buffer:byte(1), 72)
  lu.assertEquals(buffer:byte(7), 116)
  lu.assertEquals(buffer:byte(11), 87)
  lu.assertIsNil(buffer:byte(99))
end

function Test_cut()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  lu.assertEquals(buffer:length(), 17)
  lu.assertEquals(table.concat(buffer:getParts(), '-'), 'Hello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(1):getParts(), '-'), 'Hello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(6):getParts(), '-'), 'Hello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(18):getParts(), '-'), 'Hello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(2):getParts(), '-'), 'H-ello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(7):getParts(), '-'), 'Hello- -the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(11):getParts(), '-'), 'Hello- the- -World !')
  lu.assertEquals(table.concat(buffer:clone():cut(17):getParts(), '-'), 'Hello- the- World -!')
  lu.assertEquals(table.concat(buffer:clone():cut(18):getParts(), '-'), 'Hello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(30):getParts(), '-'), 'Hello- the- World !')
end

local function assert_delete(buffer)
  assertEquals(buffer:clone():delete(1, 0), 'Hello the World !')
  assertEquals(buffer:clone():delete(1, 1), 'ello the World !')
  assertEquals(buffer:clone():delete(1, 2), 'llo the World !')
  assertEquals(buffer:clone():delete(7, 7), 'Hello he World !')
  assertEquals(buffer:clone():delete(7, 10), 'Hello World !')
  assertEquals(buffer:clone():delete(2, 9), 'H World !')
  assertEquals(buffer:clone():delete(6, 19), 'Hello')
  assertEquals(buffer:clone():delete(9, 19), 'Hello th')
end

function Test_delete()
  local buffer = StringBuffer:new()
  buffer:append('Hello the World !')
  assert_delete(buffer)
end

function Test_delete_parts()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  assert_delete(buffer)
end

local function assert_replace(buffer)
  assertEquals(buffer:clone():replace(1, 0, '!'), '!')
  assertEquals(buffer:clone():replace(1, 1, 'h'), 'hello the World !')
  assertEquals(buffer:clone():replace(1, 2, '! '), '! llo the World !')
  assertEquals(buffer:clone():replace(7, 7, 'T'), 'Hello The World !')
  assertEquals(buffer:clone():replace(7, 11, 'w'), 'Hello world !')
  assertEquals(buffer:clone():replace(5, 11, ''), 'Hellorld !')
  assertEquals(buffer:clone():replace(2, 9, 'i'), 'Hi World !')
end

function Test_replace()
  local buffer = StringBuffer:new()
  buffer:append('Hello the World !')
  assert_replace(buffer)
end

function Test_replace_parts()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  assert_replace(buffer)
end

function Test_insert()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  assertEquals(buffer:clone():insert(1, 'AB'), 'ABHello the World !')
  assertEquals(buffer:clone():insert(6, 'AB'), 'HelloAB the World !')
  assertEquals(buffer:clone():insert(8, 'x'), 'Hello txhe World !')
  assertEquals(buffer:clone():insert(18, 'OK'), 'Hello the World !OK')
  assertEquals(buffer:clone():insert(30, 'KO'), 'Hello the World !KO')
end

function Test_insert_parts()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  assertEquals(buffer:clone():insert(1, StringBuffer:new('AB')), 'ABHello the World !')
  assertEquals(buffer:clone():insert(1, StringBuffer:new('AB', 'CD')), 'ABCDHello the World !')
  assertEquals(buffer:clone():insert(6, StringBuffer:new('AB', 'CD')), 'HelloABCD the World !')
  assertEquals(buffer:clone():insert(11, StringBuffer:new('AB')), 'Hello the ABWorld !')
  assertEquals(buffer:clone():insert(18, StringBuffer:new('AB')), 'Hello the World !AB')
end

function Test_insert_parts_after()
  -- inserting a part buffer must not duplicate nor lose the parts after the insertion index
  local buffer = StringBuffer:new('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h')
  assertEquals(buffer:clone():insert(3, StringBuffer:new('X', 'Y', 'ZZ')), 'abXYZZcdefgh')
  assertEquals(buffer:clone():insert(1, StringBuffer:new('X', 'Y', 'ZZ')), 'XYZZabcdefgh')
  assertEquals(buffer:clone():insert(9, StringBuffer:new('X', 'Y', 'ZZ')), 'abcdefghXYZZ')
end

function Test_setLength()
  assertEquals(StringBuffer:new('Hello'):setLength(5), 'Hello')
  assertEquals(StringBuffer:new('Hello'):setLength(2), 'He')
  assertEquals(StringBuffer:new('Hello'):setLength(1), 'H')
  assertEquals(StringBuffer:new('Hello'):setLength(0), '')
  assertEquals(StringBuffer:new('Hello'):setLength(8), 'Hello\0\0\0')
end

function Test_setLength_parts()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  assertEquals(buffer:clone():setLength(17), 'Hello the World !')
  assertEquals(buffer:clone():setLength(12), 'Hello the Wo')
  assertEquals(buffer:clone():setLength(6), 'Hello ')
  assertEquals(buffer:clone():setLength(5), 'Hello')
  assertEquals(buffer:clone():setLength(1), 'H')
  assertEquals(buffer:clone():setLength(0), '')
  assertEquals(buffer:clone():setLength(21), 'Hello the World !\0\0\0\0')
end

function Test_setLength_length()
  local buffer = StringBuffer:new('Hello'):append(' the'):append(' World !')
  buffer:setLength(12)
  lu.assertEquals(buffer:length(), 12)
  lu.assertEquals(#buffer:toString(), 12)
  buffer:setLength(4)
  lu.assertEquals(buffer:length(), 4)
  lu.assertEquals(#buffer:toString(), 4)
end

function Test_setLength_then_append()
  assertEquals(StringBuffer:new('Hello'):append(' the'):append(' World !'):setLength(8):append('!'), 'Hello th!')
end

function Test_length()
  local buffer = StringBuffer:new()
  lu.assertEquals(buffer:length(), 0)
  buffer:append('Hello'):append(' world !')
  lu.assertEquals(buffer:length(), 13)
end

os.exit(lu.LuaUnit.run())
