local lu = require('luaunit')

local StringBuffer = require("jls.lang.StringBuffer")

function assertEquals(value, expected)
  lu.assertEquals(value:clone():toString(), expected)
  lu.assertEquals(value:length(), string.len(expected))
end

function test_toString()
  local buffer = StringBuffer:new()
  assertEquals(buffer, '')
  buffer:append('Hello world !')
  assertEquals(buffer, 'Hello world !')
end

function test_intial_value()
  local buffer = StringBuffer:new('Hello')
  assertEquals(buffer, 'Hello')
  buffer:append(' world !')
  assertEquals(buffer, 'Hello world !')
end

function test_append()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' world !')
  assertEquals(buffer, 'Hello world !')
end

function test_cut()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  lu.assertEquals(buffer:length(), 17)
  lu.assertEquals(table.concat(buffer.values, '-'), 'Hello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(1).values, '-'), 'Hello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(6).values, '-'), 'Hello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(18).values, '-'), 'Hello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(2).values, '-'), 'H-ello- the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(7).values, '-'), 'Hello- -the- World !')
  lu.assertEquals(table.concat(buffer:clone():cut(11).values, '-'), 'Hello- the- -World !')
end

function test_delete()
  local buffer = StringBuffer:new()
  buffer:append('Hello the World !')
  assertEquals(buffer:clone():delete(1, 1), 'Hello the World !')
  assertEquals(buffer:clone():delete(1, 2), 'ello the World !')
  assertEquals(buffer:clone():delete(7, 8), 'Hello he World !')
  assertEquals(buffer:clone():delete(7, 11), 'Hello World !')
  assertEquals(buffer:clone():delete(2, 10), 'H World !')
end

function test_delete_parts()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  assertEquals(buffer:clone():delete(1, 1), 'Hello the World !')
  assertEquals(buffer:clone():delete(1, 2), 'ello the World !')
  assertEquals(buffer:clone():delete(7, 8), 'Hello he World !')
  assertEquals(buffer:clone():delete(7, 11), 'Hello World !')
  assertEquals(buffer:clone():delete(2, 10), 'H World !')
end

function test_replace()
  local buffer = StringBuffer:new()
  buffer:append('Hello the World !')
  assertEquals(buffer:clone():replace(1, 1, '! '), '! Hello the World !')
  assertEquals(buffer:clone():replace(1, 2, 'h'), 'hello the World !')
  assertEquals(buffer:clone():replace(7, 8, 'T'), 'Hello The World !')
  assertEquals(buffer:clone():replace(7, 12, 'w'), 'Hello world !')
  assertEquals(buffer:clone():replace(5, 12, ''), 'Hellorld !')
  assertEquals(buffer:clone():replace(2, 10, 'i'), 'Hi World !')
end

function test_replace_parts()
  local buffer = StringBuffer:new()
  buffer:append('Hello'):append(' the'):append(' World !')
  assertEquals(buffer:clone():replace(1, 1, '! '), '! Hello the World !')
  assertEquals(buffer:clone():replace(1, 2, 'h'), 'hello the World !')
  assertEquals(buffer:clone():replace(7, 8, 'T'), 'Hello The World !')
  assertEquals(buffer:clone():replace(7, 12, 'w'), 'Hello world !')
  assertEquals(buffer:clone():replace(5, 12, ''), 'Hellorld !')
  assertEquals(buffer:clone():replace(2, 10, 'i'), 'Hi World !')
end

function test_length()
  local buffer = StringBuffer:new()
  lu.assertEquals(buffer:length(), 0)
  buffer:append('Hello'):append(' world !')
  lu.assertEquals(buffer:length(), 13)
end

os.exit(lu.LuaUnit.run())
