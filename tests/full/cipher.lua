local lu = require('luaunit')

local cipher = require('jls.util.cd.cipher')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')

local function chars(l)
  local ten = '123456789 '
  return string.rep(ten, l // 10)..string.sub(ten, 1, l % 10)
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
    lu.assertEquals(cipher.decode(cipher.encode(s, alg, key), alg, key), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode('!')
  assertEncodeDecode('Hi')
  assertEncodeDecode('Hello world !')
  assertEncodeDecode(chars(2000))
  assertEncodeDecode(chars(128), 'aes-128-ctr', 'secret')
end

function Test_encode_decode_stream()
  local function assertEncodeDecode(s, alg, key)
    local bsh = BufferedStreamHandler:new()
    local esh = cipher.encodeStream(bsh, alg, key)
    BufferedStreamHandler.fill(esh, s)
    local es = bsh:getBuffer()
    bsh:getStringBuffer():clear()
    local dsh = cipher.decodeStream(bsh, alg, key)
    BufferedStreamHandler.fill(dsh, es)
    local ds = bsh:getBuffer()
    --print('encoded size is '..tostring(#es)..'/'..tostring(#s))
    lu.assertEquals(ds, s)
  end
  assertEncodeDecode('')
  assertEncodeDecode('!')
  assertEncodeDecode('Hi')
  assertEncodeDecode('Hello world !')
  assertEncodeDecode(chars(16))
  assertEncodeDecode(chars(128))
  assertEncodeDecode(chars(2000))
  assertEncodeDecode(chars(128), 'aes-128-ctr', 'secret')
end

function Test_encode_decode_stream_part()
  local s = chars(2 ^ 20) -- 7
  local alg, key = 'aes-128-ctr', 'secret'
  local bsh = BufferedStreamHandler:new()
  local esh = cipher.encodeStreamPart(bsh, alg, key)
  BufferedStreamHandler.fill(esh, s)
  local es = bsh:getBuffer()
  local function assertDecodePart(offset, length)
    length = length or (#s - offset)
    bsh:getStringBuffer():clear()
    local dsh, o, l = cipher.decodeStreamPart(bsh, alg, key, nil, offset, length)
    --print('assertDecode('..tostring(offset)..', '..tostring(length)..') => '..tostring(o)..', '..tostring(l))
    BufferedStreamHandler.fill(dsh, sub(es, o, l))
    local ds = bsh:getBuffer()
    lu.assertEquals(ds, sub(s, offset, length))
  end
  assertDecodePart(0)
  assertDecodePart(6)
  assertDecodePart(16)
  assertDecodePart(20)
  local m = (#s // 32) * 2
  assertDecodePart(m)
  assertDecodePart(m + 10)
end

os.exit(lu.LuaUnit.run())
