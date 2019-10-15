local lu = require('luaunit')

local strings = require("jls.util.strings")

function test_split()
  lu.assertEquals(strings.split('', ','), {})
  lu.assertEquals(strings.split('a', ','), {'a'})
  lu.assertEquals(strings.split('a,b,c', ','), {'a', 'b', 'c'})
end

function test_cuts()
  lu.assertEquals(strings.cuts('abcdefghijklmnopqrstuvwxyz', 2, 2, 3), {'ab', 'cd', 'efg'})
  lu.assertEquals(strings.cuts('abcdefghijklmnopqrstuvwxyz', 2, 2, 99), {'ab', 'cd', 'efghijklmnopqrstuvwxyz'})
  lu.assertEquals(strings.cuts('abc', 2, 2, 3), {'ab', 'c', ''})
end

os.exit(lu.LuaUnit.run())
