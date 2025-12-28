local lu = require('luaunit')

local MessageDigest = require('jls.util.MessageDigest')
local hex = require('jls.util.Codec').getInstance('hex')

--[[
MessageDigest.getInstance('MD5')
print('loaded modules:')
for name in pairs(package.loaded) do
  print('  '..name)
end
]]

local function assertHexEquals(result, expected)
  lu.assertEquals(result, expected, string.format('expected: 0x%X, actual: 0x%X', expected, result))
end

local function onAlgAndMod(alg, mod, fn, ...)
  local Md = MessageDigest.getMessageDigest(alg)
  fn(Md:new(...))
  local Mdp = require(mod)
  if Md ~= Mdp then
    --print('also testing pure Lua module '..mod)
    fn(Mdp:new(...))
  end
end

local function assertAlgAndMod(alg, mod, value, result, ...)
  onAlgAndMod(alg, mod, function(md)
    md:update(value)
    lu.assertEquals(hex:encode(md:digest()), result)
    local s = #value // 2
    md:reset():update(string.sub(value, 1, s - 1)):update(string.sub(value, s))
    lu.assertEquals(hex:encode(md:digest()), result)
  end, ...)
end

function Test_md5()
  assertAlgAndMod('MD5', 'jls.util.md.md5-', 'The quick brown fox jumps over the lazy dog', '9e107d9d372bb6826bd81d3542a419d6')
  onAlgAndMod('MD5', 'jls.util.md.md5-', function(md)
    lu.assertEquals(hex:encode(md:update(''):digest()), 'd41d8cd98f00b204e9800998ecf8427e')
    md:reset():update('The quick brown fox jumps over the lazy dog.')
    lu.assertEquals(hex:encode(md:digest()), 'e4d909c290d0fb1ca068ffaddf22cbd0')
  end)
end

function Test_md5_updates()
  local md = MessageDigest.getInstance('MD5')
  md:update('The quick brown fox'):update(' jumps over the lazy dog')
  md:update('.')
  lu.assertEquals(hex:encode(md:digest()), 'e4d909c290d0fb1ca068ffaddf22cbd0')
end

function Test_sha1()
  assertAlgAndMod('SHA-1', 'jls.util.md.sha1-', 'The quick brown fox jumps over the lazy dog', '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12')
end

function Test_hmac()
  assertAlgAndMod('HMAC', 'jls.util.md.hmac-', 'The quick brown fox jumps over the lazy dog', 'de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9', 'sha1', 'key')
  assertAlgAndMod('HMAC', 'jls.util.md.hmac-', 'The quick brown fox jumps over the lazy dog', 'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8', 'sha256', 'key')
end

function Test_Crc32_updates()
  onAlgAndMod('CRC32', 'jls.util.md.crc32-', function(md)
    md:update('The quick brown fox')
    md:update(' jumps over the lazy dog')
    assertHexEquals(md:digest(), 0x414FA339)
  end)
end

function Test_Crc32_digest()
  local md = MessageDigest.getInstance('CRC32')
  md:update('123456789')
  assertHexEquals(md:digest(), 0xCBF43926)
  md:reset():update('The quick brown fox jumps over the lazy dog')
  assertHexEquals(md:digest(), 0x414FA339)
end

os.exit(lu.LuaUnit.run())
