local lu = require('luaunit')

local Crc32 = require('jls.util.md.Crc32')

function test_Crc32_updates()
  local crc = Crc32:new()
  crc:update('The quick brown fox')
  crc:update(' jumps over the lazy dog')
  --print(string.format('result: 0x%x expected: 0x%x', crc:final(), 1095738169))
  --print('crc', crc:final())
  lu.assertEquals(crc:final(), 1095738169)
end

function test_Crc32_digest()
  lu.assertEquals(Crc32.digest('The quick brown fox jumps over the lazy dog'), 1095738169)
end

os.exit(lu.LuaUnit.run())
