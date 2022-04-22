local lu = require('luaunit')

local cipher = require('jls.util.codec.cipher')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')

local function randomChars(len, from, to)
  from = from or 0
  to = to or 255
  if len <= 10 then
    local bytes = {}
    for _ = 1, len do
      table.insert(bytes, math.random(from, to))
    end
    return string.char(table.unpack(bytes))
  end
  local parts = {}
  for _ = 1, len // 10 do
    table.insert(parts, randomChars(10, from, to))
  end
  table.insert(parts, randomChars(len % 10, from, to))
  return table.concat(parts)
end

function Test_encode_decode()
  local assertEncodeDecode = function(s, alg, key)
    lu.assertEquals(cipher.decode(cipher.encode(s, alg, key), alg, key), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode('!')
  assertEncodeDecode('Hi')
  assertEncodeDecode('Hello world !')
  assertEncodeDecode(randomChars(2000))
  assertEncodeDecode(randomChars(128, 48, 127), 'aes-128-ctr', 'secret')
end

function Test_encode_decode_stream()
  local assertEncodeDecode = function(s, alg, key)
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
  assertEncodeDecode(randomChars(16))
  assertEncodeDecode(randomChars(128))
  assertEncodeDecode(randomChars(2000))
  assertEncodeDecode(randomChars(128, 48, 127), 'aes-128-ctr', 'secret')
end

os.exit(lu.LuaUnit.run())
