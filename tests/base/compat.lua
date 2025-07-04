local lu = require('luaunit')

local compat = require('jls.util.compat')

local function assertEqualsHex(r, e)
  if r ~= e and type(r) == 'string' and type(e) == 'string' then
    local rh, eh = compat.hex(r), compat.hex(e)
    lu.assertEquals(rh, eh)
  end
  lu.assertEquals(r, e)
end

local function assertAlmostEquals(r, e, d)
  lu.assertEquals(type(r), 'number')
  lu.assertEquals(type(e), 'number')
  lu.assertEquals(r < 0, e < 0)
  local re = math.floor(compat.log10(math.abs(r)))
  local ee = math.floor(compat.log10(math.abs(e)))
  lu.assertAlmostEquals(re, ee, d)
  local m = 10 ^ math.min(re, ee)
  local rd = r / m
  local ed = e / m
  lu.assertAlmostEquals(rd, ed, d)
end

function Test_len()
  lu.assertEquals(compat.len('a'), 1)
  lu.assertEquals(compat.len({'a'}), 1)
  local o = setmetatable({}, {
    __len = function()
      return 123
    end
  })
  lu.assertEquals(compat.len(o), 123)
end

function Test_band()
  lu.assertEquals(compat.band(0, 1), 0)
  lu.assertEquals(compat.band(1, 1), 1)
  lu.assertEquals(compat.band(2, 1), 0)
  lu.assertEquals(compat.band(3, 1), 1)
end

function Test_bor()
  lu.assertEquals(compat.bor(0, 1), 1)
  lu.assertEquals(compat.bor(1, 1), 1)
  lu.assertEquals(compat.bor(2, 1), 3)
  lu.assertEquals(compat.bor(3, 1), 3)
  lu.assertEquals(compat.bor(0x40000000, 1), 0x40000001)
  lu.assertEquals(compat.bor(0x200000000, 1), 0x200000001)
end

function Test_bxor()
  lu.assertEquals(compat.bxor(0, 1), 1)
  lu.assertEquals(compat.bxor(1, 1), 0)
  lu.assertEquals(compat.bxor(2, 1), 3)
  lu.assertEquals(compat.bxor(3, 1), 2)
end

function Test_bnot()
  lu.assertEquals(compat.bnot(1), -2)
end

function Test_lshift()
  lu.assertEquals(compat.lshift(1, 1), 2)
  lu.assertEquals(compat.lshift(1, 30), 0x40000000)
  lu.assertEquals(compat.lshift(8, 30), 0x200000000)
end

function Test_rshift()
  lu.assertEquals(compat.rshift(2, 1), 1)
end

function Test_pack()
  lu.assertEquals(compat.pack(1, 2), {n = 2, 1, 2})
  lu.assertEquals(compat.pack(1, nil, 3), {n = 3, 1, [3] = 3})
end

function Test_itos()
  if _VERSION == 'Lua 5.1' then
    print('/!\\ skipping test due to Lua version')
    lu.success()
    return
  end
  for _, i in ipairs({0, 1, -1, 123456, -123456}) do
    lu.assertEquals(compat.itos(i, 4, false), string.pack('<i4', i))
    lu.assertEquals(compat.itos(i, 4, true), string.pack('>i4', i))
  end
end

function Test_sign()
  lu.assertEquals(compat.sign(255, 1), -1)
  lu.assertEquals(compat.sign(255, 2), 255)
end

function Test_unsign()
  lu.assertEquals(compat.unsign(-1, 1), 255)
  lu.assertEquals(compat.unsign(-1, 2), 65535)
  lu.assertEquals(compat.unsign(255, 2), 255)
end

function Test_itos_stoi()
  for _, i in ipairs({0, 1, -1, 123456, -123456}) do
    lu.assertEquals(compat.sign(compat.stoi(compat.itos(i, 4, false), 4, false), 4), i)
  end
end

local DOUBLE_VALUES = {
  ['0000000000000000'] = 0,
  ['3FF0000000000000'] = 1,
  ['C000000000000000'] = -2,
  ['4000000000000000'] = 2,
  ['7FF0000000000000'] = math.huge,
  ['FFF0000000000000'] = -math.huge,
  ['7FF0000000000001'] = 0/0,
}
local NUMBER_VALUES = {0, 1, -1, 2, 4097, math.pi, 1/3, math.huge, -math.huge}

function Test_rtos()
  for h, n in ipairs(DOUBLE_VALUES) do
    assertEqualsHex(compat.rtos(n, 11, 52, true), compat.byt(h))
  end
  if _VERSION == 'Lua 5.1' then
    print('/!\\ skipping test due to Lua version')
    lu.success()
    return
  end
  for _, n in ipairs(NUMBER_VALUES) do
    assertEqualsHex(compat.rtos(n, 11, 52), string.pack('<d', n))
    --assertEqualsHex(compat.rtos(n, 8, 23), string.pack('<f', n))
    assertEqualsHex(compat.rtos(n, 11, 52, true), string.pack('>d', n))
  end
end

function Test_stor()
  for h, n in ipairs(DOUBLE_VALUES) do
    lu.assertEquals(compat.stor(compat.byt(h), 11, 52, true), n)
  end
  if _VERSION == 'Lua 5.1' then
    print('/!\\ skipping test due to Lua version')
    lu.success()
    return
  end
  for _, n in ipairs(NUMBER_VALUES) do
    lu.assertEquals(compat.stor(string.pack('<d', n), 11, 52), n)
    --lu.assertEquals(compat.stor(string.pack('<f', n), 8, 23), n)
    lu.assertEquals(compat.stor(string.pack('>d', n), 11, 52, true), n)
  end
end

function Test_rtos_stor()
  for _, n in ipairs({0.0, 1.0, -1.0, 1/3, 1.23e20, 1.23e-20, -1.23e20, -1.23e-20}) do
    lu.assertEquals(compat.stor(compat.rtos(n, 11, 52), 11, 52), n)
  end
  for _, n in ipairs({0.0, 1.0, -1.0}) do
    lu.assertEquals(compat.stor(compat.rtos(n, 8, 23), 8, 23), n)
  end
  for _, n in ipairs({1/3, -1/3}) do
    assertAlmostEquals(compat.stor(compat.rtos(n, 8, 23), 8, 23), n, 0.01)
  end
end

function Test_spack()
  --print('\n'..compat.hex('\1\0\1\0\0\0\1a\0')..'\n'..compat.hex(compat.spack('>BI2I4c2', 1, 1, 1, 'a')))
  lu.assertEquals(compat.spack('>BI2I4c2', 1, 1, 1, 'ab'), '\1\0\1\0\0\0\1ab')
end

function Test_sunpack()
  --print('sunpack', compat.sunpack('>BI2I4c2', '\1\0\1\0\0\0\1a\0'))
  lu.assertEquals(compat.pack(compat.sunpack('>BI2I4c2', '\1\0\1\0\0\0\1ab')), {n = 5, 1, 1, 1, 'ab', 10})
end

function Test_spacksize()
  lu.assertEquals(compat.spacksize('>BI2I4c2fdn'), 29)
end

function Test_uchar()
  lu.assertEquals(compat.uchar(65, 0xef, 66), 'AïB')
end

function Test_ucodepoint()
  local s = 'AïB'
  lu.assertEquals(compat.ucodepoint(s), 65)
  lu.assertEquals(compat.pack(compat.ucodepoint(s, 1, #s)), {n = 3, 65, 0xef, 66})
end

function Test_ucodes()
  local t = {}
  for _, cp in compat.ucodes('AïB') do
    table.insert(t, cp)
  end
  lu.assertEquals(t, {65, 0xef, 66})
end

function Test_ulen()
  local s = 'AïB'
  lu.assertEquals(#s, 4)
  lu.assertEquals(compat.ulen(s), 3)
end

function Test_uoffset()
  local s = 'AïB'
  lu.assertEquals(#s, 4)
  lu.assertEquals(compat.uoffset(s, 3), 4)
end

function Test_random()
  local r = compat.random()
  lu.assertTrue(r >= 0)
  lu.assertTrue(r < 1)
  local n = 2 ^ 60
  r = compat.random(n)
  lu.assertTrue(r >= 1)
  lu.assertTrue(r < n)
  local m = 2 ^ 59
  r = compat.random(m, n)
  lu.assertTrue(r >= m)
  lu.assertTrue(r < n)
end

os.exit(lu.LuaUnit.run())
