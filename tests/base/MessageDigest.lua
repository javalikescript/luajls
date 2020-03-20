local lu = require('luaunit')

local MessageDigest = require('jls.util.MessageDigest')
local hex = require('jls.util.hex')

--[[
MessageDigest:new('md5')
print('loaded modules:')
for name in pairs(package.loaded) do
  print('  '..name)
end
]]

function test_md5_digest()
  local md = MessageDigest:new('md5')
  lu.assertEquals(hex.encode(md:digest('')), 'd41d8cd98f00b204e9800998ecf8427e')
  lu.assertEquals(hex.encode(md:digest('The quick brown fox jumps over the lazy dog')), '9e107d9d372bb6826bd81d3542a419d6')
  lu.assertEquals(hex.encode(md:digest('The quick brown fox jumps over the lazy dog.')), 'e4d909c290d0fb1ca068ffaddf22cbd0')
end

function test_md5_finish()
  local md = MessageDigest:new('md5')
  lu.assertEquals(hex.encode(md:finish('The quick brown fox jumps over the lazy dog.')), 'e4d909c290d0fb1ca068ffaddf22cbd0')
end

function test_md5_updates()
  local md = MessageDigest:new('md5')
  md:update('The quick brown fox')
  md:update(' jumps over the lazy dog')
  md:update('.')
  lu.assertEquals(hex.encode(md:finish()), 'e4d909c290d0fb1ca068ffaddf22cbd0')
end

function test_sha1_digest()
  local md = MessageDigest:new('sha1')
  lu.assertEquals(hex.encode(md:digest('The quick brown fox jumps over the lazy dog')), '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12')
end

os.exit(lu.LuaUnit.run())
