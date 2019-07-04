local lu = require('luaunit')

local strings = require("jls.util.strings")

function test_split()
  lu.assertEquals(strings.split('', ','), {})
  lu.assertEquals(strings.split('a', ','), {'a'})
  lu.assertEquals(strings.split('a,b,c', ','), {'a', 'b', 'c'})
end

os.exit(lu.LuaUnit.run())
