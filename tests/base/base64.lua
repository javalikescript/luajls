local lu = require('luaunit')

local base64 = require('jls.util.cd.base64')

local function unpcall(status, ...)
  if status then
    return ...
  end
  return nil, ...
end

local function safe(fn, ...)
  unpcall(xpcall(fn, debug.traceback, ...))
end

local function chars(l)
  local ten = '123456789 '
  return string.rep(ten, math.floor(l / 10))..string.sub(ten, 1, l % 10)
end

---@diagnostic disable-next-line: deprecated
local table_unpack = table.unpack or _G.unpack

local function randomChars(len, from, to)
  from = from or 0
  to = to or 255
  if len <= 10 then
    local bytes = {}
    for _ = 1, len do
      table.insert(bytes, math.random(from, to))
    end
    return string.char(table_unpack(bytes))
  end
  local parts = {}
  for _ = 1, len / 10 do
    table.insert(parts, randomChars(10, from, to))
  end
  table.insert(parts, randomChars(len % 10, from, to))
  return table.concat(parts)
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

local function time(fn, ...)
  local system = require('jls.lang.system')
  local startMillis = system.currentTimeMillis()
  collectgarbage('collect')
  collectgarbage('stop')
  local gcCountBefore = math.floor(collectgarbage('count') * 1024)
  fn(...)
  local endMillis = system.currentTimeMillis()
  local gcCountAfter = math.floor(collectgarbage('count') * 1024)
  collectgarbage('restart')
  return endMillis - startMillis, gcCountAfter - gcCountBefore
end

function _Test_encode_decode_perf()
  local samples = {}
  for _ = 1, 10000 do
    table.insert(samples, randomChars(math.random(5, 500)))
  end
  print(time(function()
    for _, s in ipairs(samples) do
      lu.assertEquals(base64.decode(base64.encode(s)), s)
    end
  end))
end

os.exit(lu.LuaUnit.run())
