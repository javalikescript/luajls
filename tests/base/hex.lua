local lu = require('luaunit')

local hex = require('jls.util.hex')

function Test_decode()
  lu.assertEquals(hex.decode('48656c6c6f20776f726c6421'), 'Hello world!')
  lu.assertEquals(hex.decode('48656C6C6F20776F726C6421'), 'Hello world!')
  lu.assertEquals(hex.decode(''), '')
end

function Test_encode()
  lu.assertEquals(hex.encode('Hello world!'), '48656c6c6f20776f726c6421')
  lu.assertEquals(hex.encode('Hello world!', true), '48656C6C6F20776F726C6421')
  lu.assertEquals(hex.encode(''), '')
end

function Test_encode_decode()
  local assertEncodeDecode = function(s)
    lu.assertEquals(hex.decode(hex.encode(s)), s)
    lu.assertEquals(hex.decode(hex.encode(s, true)), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode(string.char(0, 1, 2, 3, 4, 126, 127, 128, 129, 254, 255))
end

os.exit(lu.LuaUnit.run())
