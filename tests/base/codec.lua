local lu = require('luaunit')

local Codec = require('jls.util.Codec')

function Test_decode()
  lu.assertEquals(Codec.decode('hex', '48656c6c6f20776f726c6421'), 'Hello world!')
  lu.assertEquals(Codec.decode('hex', '48656C6C6F20776F726C6421'), 'Hello world!')
  lu.assertEquals(Codec.decode('hex', ''), '')
  lu.assertEquals(Codec.getInstance('hex'):decode('48656C6C6F20776F726C6421'), 'Hello world!')
end

function Test_encode()
  lu.assertEquals(Codec.encode('hex', 'Hello world!'), '48656c6c6f20776f726c6421')
  lu.assertEquals(Codec.encode('hex', 'Hello world!', true), '48656C6C6F20776F726C6421')
  lu.assertEquals(Codec.encode('hex', ''), '')
  lu.assertEquals(Codec.getInstance('hex'):encode('Hello world!'), '48656c6c6f20776f726c6421')
end

function Test_encode_decode()
  local assertEncodeDecode = function(s)
    lu.assertEquals(Codec.decode('hex', Codec.encode('hex', s)), s)
    lu.assertEquals(Codec.decode('hex', Codec.encode('hex', s, true)), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode(string.char(0, 1, 2, 3, 4, 126, 127, 128, 129, 254, 255))
end

os.exit(lu.LuaUnit.run())
