local lu = require('luaunit')

local Codec = require('jls.util.Codec')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')

local function chars(l)
  local ten = '123456789 '
  return string.rep(ten, math.floor(l / 10))..string.sub(ten, 1, l % 10)
end

local function sub(value, offset, length)
  return string.sub(value, offset + 1, offset + length)
end

function Test_test()
  lu.assertEquals('34', sub('123456789', 2, 2))
  lu.assertEquals('12', chars(2))
  lu.assertEquals('123456789 12', chars(12))
end

function Test_encode_decode()
  local function assertEncodeDecode(s, alg, key)
    local cipher = Codec.getInstance('cipher', alg, key)
    lu.assertEquals(cipher:decode(cipher:encode(s)), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode('!')
  assertEncodeDecode('Hi')
  assertEncodeDecode('Hello world !')
  assertEncodeDecode(chars(2000))
  assertEncodeDecode(chars(128), 'aes-128-ctr', 'secret')
end

function Test_decode_stream_error()
  local cipher = Codec.getInstance('cipher', 'aes128', 'secret')
  local bsh = BufferedStreamHandler:new()
  local esh = cipher:encodeStream(bsh)
  BufferedStreamHandler.fill(esh, 'Hi')
  local es = assert(bsh:getBuffer())

  bsh:getStringBuffer():clear()
  cipher = Codec.getInstance('cipher', 'aes128', 'secret2')
  local dsh = cipher:decodeStream(bsh)
  BufferedStreamHandler.fill(dsh, es)
  local ds, err = bsh:getBuffer()
  lu.assertNil(ds)
  lu.assertEquals(err, 'bad decrypt')
end

function Test_encode_decode_stream()
  local function assertEncodeDecode(s, alg, key)
    local cipher = Codec.getInstance('cipher', alg, key)
    local bsh = BufferedStreamHandler:new()
    local esh = cipher:encodeStream(bsh)
    BufferedStreamHandler.fill(esh, s)
    local es = assert(bsh:getBuffer())
    bsh:getStringBuffer():clear()
    local dsh = cipher:decodeStream(bsh)
    BufferedStreamHandler.fill(dsh, es)
    local ds = bsh:getBuffer()
    --print('encoded size is '..tostring(#es)..'/'..tostring(#s))
    lu.assertEquals(ds, s)
  end
  local values = {
    '',
    '!',
    'Hi',
    'Hello world !',
    chars(16),
    chars(128),
    chars(2000),
  }
  for _, value in ipairs(values) do
    assertEncodeDecode(value)
  end
  for _, value in ipairs(values) do
    assertEncodeDecode(value, 'aes-128-ctr', 'secret')
  end
end

function Test_encode_decode_stream_part()
  local s = chars(2 ^ 20) -- 7
  local alg, key = 'aes-128-ctr', 'secret'
  local bsh = BufferedStreamHandler:new()
  local cipher = Codec.getInstance('cipher', alg, key)
  local esh = cipher:encodeStreamPart(bsh)
  BufferedStreamHandler.fill(esh, s)
  local es = bsh:getBuffer()
  local function assertDecodePart(offset, length)
    length = length or (#s - offset)
    bsh:getStringBuffer():clear()
    local dsh, o, l = cipher:decodeStreamPart(bsh, nil, offset, length)
    --print('assertDecode('..tostring(offset)..', '..tostring(length)..') => '..tostring(o)..', '..tostring(l))
    BufferedStreamHandler.fill(dsh, sub(es, o, l))
    local ds = bsh:getBuffer()
    lu.assertEquals(ds, sub(s, offset, length))
  end
  assertDecodePart(0)
  assertDecodePart(6)
  assertDecodePart(16)
  assertDecodePart(20)
  local m = math.floor(#s / 32) * 2
  assertDecodePart(m)
  assertDecodePart(m + 10)
end

if false then
  local opensslLib = require('openssl')
  print('Digest algorithms:')
  for _, v in pairs(opensslLib.digest.list()) do
    print('', v)
  end
  print('Cipher algorithms:')
  for _, v in pairs(opensslLib.cipher.list()) do
    print('', v)
  end
  os.exit(0)
end

os.exit(lu.LuaUnit.run())
