local lu = require('luaunit')

local Crc32 = require('jls.util.md.Crc32')

function assertHexEquals(result, expected)
  lu.assertEquals(result, expected, string.format('expected: 0x%X, actual: 0x%X', expected, result))
end

function test_Crc32_updates()
  local crc = Crc32:new()
  crc:update('The quick brown fox')
  crc:update(' jumps over the lazy dog')
  assertHexEquals(crc:final(), 0x414FA339)
end

function test_Crc32_digest()
  assertHexEquals(Crc32.digest('123456789'), 0xCBF43926)
  assertHexEquals(Crc32.digest('The quick brown fox jumps over the lazy dog'), 0x414FA339)
end

os.exit(lu.LuaUnit.run())
