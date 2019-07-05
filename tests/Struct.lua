local lu = require('luaunit')

local Struct = require('jls.util.Struct')

function test_to_from()
  --lu.assertEquals(res, exp)
  --lu.assertIsNil(res)
  local struct = Struct:new({
    {name = 'aUInt8', type = 'UnsignedByte'},
    {name = 'aInt8', type = 'SignedByte'},
    {name = 'aUInt16', type = 'UnsignedShort'},
    {name = 'aInt16', type = 'SignedShort'},
    {name = 'aUInt32', type = 'UnsignedInt'},
    {name = 'aInt32', type = 'SignedInt'}
  })
  local t = {
    aUInt8 = 1,
    aInt8 = 2,
    aUInt16 = 3,
    aInt16 = 4,
    aUInt32 = 5,
    aInt32 = 6
  }
  lu.assertEquals(struct:fromString(struct:toString(t)), t)
end

os.exit(lu.LuaUnit.run())
