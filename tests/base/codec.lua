local lu = require('luaunit')

local codec = require('jls.util.codec')

function Test_decode()
  lu.assertEquals(codec.decode('hex', '48656c6c6f20776f726c6421'), 'Hello world!')
  lu.assertEquals(codec.decode('hex', '48656C6C6F20776F726C6421'), 'Hello world!')
  lu.assertEquals(codec.decode('hex', ''), '')
end

function Test_encode()
  lu.assertEquals(codec.encode('hex', 'Hello world!'), '48656c6c6f20776f726c6421')
  lu.assertEquals(codec.encode('hex', 'Hello world!', true), '48656C6C6F20776F726C6421')
  lu.assertEquals(codec.encode('hex', ''), '')
end

function Test_encode_decode()
  local assertEncodeDecode = function(s)
    lu.assertEquals(codec.decode('hex', codec.encode('hex', s)), s)
    lu.assertEquals(codec.decode('hex', codec.encode('hex', s, true)), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode(string.char(0, 1, 2, 3, 4, 126, 127, 128, 129, 254, 255))
end

os.exit(lu.LuaUnit.run())
