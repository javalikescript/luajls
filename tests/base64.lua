local lu = require('luaunit')

local base64 = require('jls.util.base64')

function test_decode()
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQh'), 'Hello world!')
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQgIQ=='), 'Hello world !')
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQgICE='), 'Hello world  !')
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQgIQ'), 'Hello world !')
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQgICE'), 'Hello world  !')
  lu.assertEquals(base64.decode(''), '')
end

function test_decode_error()
  lu.assertIsNil(base64.decode('SGVsbG8gd29ybGQh='))
  lu.assertIsNil(base64.decode('SGVs-G8gd29ybGQh='))
  lu.assertIsNil(base64.decode('='))
end

function test_encode()
  lu.assertEquals(base64.encode('Hello world!'), 'SGVsbG8gd29ybGQh')
  lu.assertEquals(base64.encode('Hello world !'), 'SGVsbG8gd29ybGQgIQ==')
  lu.assertEquals(base64.encode('Hello world  !'), 'SGVsbG8gd29ybGQgICE=')
  lu.assertEquals(base64.encode(''), '')
end

function test_decode_encode()
  local assertDecodeEncode = function(s)
    lu.assertEquals(base64.encode(base64.decode(s)), s)
  end
  assertDecodeEncode('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/')
end

function test_encode_decode()
  local assertEncodeDecode = function(s)
    lu.assertEquals(base64.decode(base64.encode(s)), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode('a')
  assertEncodeDecode('ab')
  assertEncodeDecode('abc')
  assertEncodeDecode('Hello world !')
end

os.exit(lu.LuaUnit.run())
