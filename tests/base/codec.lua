local lu = require('luaunit')

local Codec = require('jls.util.Codec')

local Base64 = Codec.getCodec('base64')
local base64 = Codec.getInstance('base64')
local Hex = Codec.getCodec('hex')
local hex = Codec.getInstance('hex')

function Test_hex_decode()
  lu.assertEquals(hex:decode('48656c6c6f20776f726c6421'), 'Hello world!')
  lu.assertEquals(hex:decode('48656C6C6F20776F726C6421'), 'Hello world!')
  lu.assertEquals(hex:decode(''), '')
  lu.assertEquals(Hex:compat().decode('48656C6C6F20776F726C6421'), 'Hello world!')
  lu.assertEquals(Codec.decode('hex', '48656C6C6F20776F726C6421'), 'Hello world!')
end

function Test_hex_encode()
  local hexUppercase = Hex:new(true)
  lu.assertEquals(hex:encode('Hello world!'), '48656c6c6f20776f726c6421')
  lu.assertEquals(hexUppercase:encode('Hello world!'), '48656C6C6F20776F726C6421')
  lu.assertEquals(hex:encode(''), '')
  lu.assertEquals(hex:encode('Hello world!'), '48656c6c6f20776f726c6421')
end

function Test_hex_encode_decode()
  local assertEncodeDecode = function(s)
    lu.assertEquals(hex:decode(hex:encode(s)), s)
    lu.assertEquals(hex:decode(hex:encode(s, true)), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode(string.char(0, 1, 2, 3, 4, 126, 127, 128, 129, 254, 255))
end

function Test_base64_decode()
  lu.assertEquals(base64:decode('SGVsbG8gd29ybGQh'), 'Hello world!')
  lu.assertEquals(base64:decode('SGVsbG8gd29ybGQgIQ=='), 'Hello world !')
  lu.assertEquals(base64:decode('SGVsbG8gd29ybGQgICE='), 'Hello world  !')
  lu.assertEquals(base64:decode('SGVsbG8gd29ybGQgIQ'), 'Hello world !')
  lu.assertEquals(base64:decode('SGVsbG8gd29ybGQgICE'), 'Hello world  !')
  lu.assertEquals(base64:decode(''), '')
  lu.assertEquals(base64:decode('SGVsbG8 gd29\nybG\r\nQgIQ=='), 'Hello world !')
  lu.assertEquals(Base64:compat().decode('SGVsbG8gd29ybGQh'), 'Hello world!')
  lu.assertEquals(Codec.decode('base64', 'SGVsbG8gd29ybGQh'), 'Hello world!')
end

function Test_base64_decode_error()
  lu.assertFalse(pcall(base64.decode, base64, 'SGVsbG8gd29ybGQh='))
  lu.assertFalse(pcall(base64.decode, base64, 'SGVs-G8gd29ybGQh='))
  lu.assertFalse(pcall(base64.decode, base64, '='))
end

function Test_base64_encode()
  lu.assertEquals(base64:encode('Hello world!'), 'SGVsbG8gd29ybGQh')
  lu.assertEquals(base64:encode('Hello world !'), 'SGVsbG8gd29ybGQgIQ==')
  lu.assertEquals(base64:encode('Hello world  !'), 'SGVsbG8gd29ybGQgICE=')
  lu.assertEquals(base64:encode(''), '')
end

function Test_base64_decode_encode_alpha()
  local alpha = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~'
  local b64alpha = Base64:new(alpha)
  local b64alphaNoPadding = Base64:new(alpha, false)
  lu.assertEquals(b64alpha:encode('Hello world!'), 'I6LhR6xWTrynR6GX')
  lu.assertEquals(b64alpha:decode('I6LhR6xWTrynR6GX'), 'Hello world!')
  lu.assertEquals(b64alpha:encode('Hello world !'), 'I6LhR6xWTrynR6GW8G==')
  lu.assertEquals(b64alphaNoPadding:encode('Hello world !'), 'I6LhR6xWTrynR6GW8G')
  lu.assertEquals(b64alpha:decode('I6LhR6xWTrynR6GW8G'), 'Hello world !')
end

function Test_base64_decode_encode()
  local assertDecodeEncode = function(s)
    lu.assertEquals(base64:encode(base64:decode(s)), s)
  end
  assertDecodeEncode('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/')
end

function Test_base64_encode_decode()
  local assertEncodeDecode = function(s)
    lu.assertEquals(base64:decode(base64:encode(s)), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode('a')
  assertEncodeDecode('ab')
  assertEncodeDecode('abc')
  assertEncodeDecode('Hello world !')
end

function _Test_hex_encode_decode_perf()
  local randomChars = require('tests.randomChars')
  local time = require('tests.time')
  local samples = {}
  for _ = 1, 10000 do
    table.insert(samples, randomChars(math.random(5, 500)))
  end
  print('time', 'user', 'mem')
  print(time(function()
    for _, s in ipairs(samples) do
      lu.assertEquals(base64:decode(base64:encode(s)), s)
    end
  end))
  print(time(function()
    for _, s in ipairs(samples) do
      lu.assertEquals(hex:decode(hex:encode(s)), s)
    end
  end))
end

os.exit(lu.LuaUnit.run())
