local lu = require('luaunit')

local base64 = require('jls.util.base64')

local function unpcall(status, ...)
  if status then
    return ...
  end
  return nil, ...
end

local function safe(fn, ...)
  unpcall(xpcall(fn, debug.traceback, ...))
end

function Test_decode()
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQh'), 'Hello world!')
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQgIQ=='), 'Hello world !')
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQgICE='), 'Hello world  !')
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQgIQ'), 'Hello world !')
  lu.assertEquals(base64.decode('SGVsbG8gd29ybGQgICE'), 'Hello world  !')
  lu.assertEquals(base64.decode(''), '')
  lu.assertEquals(base64.decode('SGVsbG8 gd29\nybG\r\nQgIQ=='), 'Hello world !')
end

function Test_decode_error()
  lu.assertIsNil(safe(base64.decode, 'SGVsbG8gd29ybGQh='))
  lu.assertIsNil(safe(base64.decode, 'SGVs-G8gd29ybGQh='))
  lu.assertIsNil(safe(base64.decode, '='))
end

function Test_encode()
  lu.assertEquals(base64.encode('Hello world!'), 'SGVsbG8gd29ybGQh')
  lu.assertEquals(base64.encode('Hello world !'), 'SGVsbG8gd29ybGQgIQ==')
  lu.assertEquals(base64.encode('Hello world  !'), 'SGVsbG8gd29ybGQgICE=')
  lu.assertEquals(base64.encode(''), '')
end

function Test_decode_encode_alpha()
  local alpha = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~'
  lu.assertEquals(base64.encode('Hello world!', alpha), 'I6LhR6xWTrynR6GX')
  lu.assertEquals(base64.decode('I6LhR6xWTrynR6GX', alpha), 'Hello world!')
  lu.assertEquals(base64.encode('Hello world !', alpha), 'I6LhR6xWTrynR6GW8G==')
  lu.assertEquals(base64.encode('Hello world !', alpha, false), 'I6LhR6xWTrynR6GW8G')
  lu.assertEquals(base64.decode('I6LhR6xWTrynR6GW8G', alpha), 'Hello world !')
end

function Test_decode_encode()
  local assertDecodeEncode = function(s)
    lu.assertEquals(base64.encode(base64.decode(s)), s)
  end
  assertDecodeEncode('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/')
end

function Test_encode_decode()
  local assertEncodeDecode = function(s)
    lu.assertEquals(base64.decode(base64.encode(s)), s)
  end
  assertEncodeDecode('')
  assertEncodeDecode('a')
  assertEncodeDecode('ab')
  assertEncodeDecode('abc')
  assertEncodeDecode('Hello world !')
end

function _Test_encode_decode_perf()
  local randomChars = require('tests.randomChars')
  local time = require('tests.time')
  local samples = {}
  for _ = 1, 10000 do
    table.insert(samples, randomChars(math.random(5, 500)))
  end
  print('time', 'user', 'mem')
  print(time(function()
    for _, s in ipairs(samples) do
      lu.assertEquals(base64.decode(base64.encode(s)), s)
    end
  end))
end

os.exit(lu.LuaUnit.run())
