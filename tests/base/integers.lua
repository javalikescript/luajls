local lu = require('luaunit')

local integers = require('jls.util.integers')

function assert_int8_from_to(e, i)
  lu.assertEquals(e.toInt8(e.fromInt8(i)), i)
end
function assert_uint8_from_to(e, i)
  lu.assertEquals(e.toUInt8(e.fromUInt8(i)), i)
end

function assert_int16_from_to(e, i)
  lu.assertEquals(e.toInt16(e.fromInt16(i)), i)
end
function assert_uint16_from_to(e, i)
  lu.assertEquals(e.toUInt16(e.fromUInt16(i)), i)
end

function assert_int32_from_to(e, i)
  lu.assertEquals(e.toInt32(e.fromInt32(i)), i)
end
function assert_uint32_from_to(e, i)
  lu.assertEquals(e.toUInt32(e.fromUInt32(i)), i)
end

function assert_int8(e)
  lu.assertIsNil(e.fromInt8(-256))
  lu.assertIsNil(e.fromInt8(-129))
  assert_int8_from_to(e, -128)
  assert_int8_from_to(e, -123)
  assert_int8_from_to(e, 0)
  assert_int8_from_to(e, 123)
  assert_int8_from_to(e, 127)
  lu.assertIsNil(e.fromInt8(128))
  lu.assertIsNil(e.fromInt8(256))
end

function assert_uint8(e)
  lu.assertIsNil(e.fromUInt8(-256))
  lu.assertIsNil(e.fromUInt8(-123))
  assert_uint8_from_to(e, 0)
  assert_uint8_from_to(e, 123)
  assert_uint8_from_to(e, 255)
  lu.assertIsNil(e.fromUInt8(256))
end

function assert_int16(e)
  assert_int16_from_to(e, -123)
  assert_int16_from_to(e, 0)
  assert_int16_from_to(e, 123)
end

function assert_uint16(e)
  assert_uint16_from_to(e, 123)
  assert_uint16_from_to(e, 255)
  assert_uint16_from_to(e, 256)
  assert_uint16_from_to(e, 1234)
  assert_uint16_from_to(e, 45678)
  assert_uint16_from_to(e, 65535)
end

function assert_uint32(e)
  assert_uint32_from_to(e, 123)
  assert_uint32_from_to(e, 255)
  assert_uint32_from_to(e, 256)
  assert_uint32_from_to(e, 45678)
  assert_uint32_from_to(e, 65535)
  assert_uint32_from_to(e, 2147483647)
  assert_uint32_from_to(e, 2147483648)
  assert_uint32_from_to(e, 4294967295)
end

function test_int8()
  assert_int8(integers)
  assert_int8(integers.be)
  assert_int8(integers.le)
end

function test_uint8()
  assert_uint8(integers)
  assert_uint8(integers.be)
  assert_uint8(integers.le)
end

function test_be_int16()
  assert_int16(integers.be)
end
function test_le_int16()
  assert_int16(integers.le)
end

function test_be_uint16()
  lu.assertEquals(integers.be.fromUInt16(65), '\0A')
  lu.assertEquals(integers.be.toUInt16('\0A'), 65)
  lu.assertIsNil(integers.be.fromUInt16(-1))
  lu.assertIsNil(integers.be.fromUInt16(65536))
  assert_uint16(integers.be)
end
function test_le_uint16()
  assert_uint16(integers.le)
end

function test_be_uint32()
  lu.assertEquals(integers.be.fromUInt32(65), '\0\0\0A')
  lu.assertEquals(integers.be.toUInt32('\0\0\0A'), 65)
  lu.assertIsNil(integers.be.fromUInt32(-1))
  lu.assertIsNil(integers.be.fromUInt32(4294967296))
  assert_uint32(integers.be)
end
function test_le_uint32()
  assert_uint32(integers.le)
end

os.exit(lu.LuaUnit.run())
