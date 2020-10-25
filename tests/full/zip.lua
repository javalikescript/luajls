local lu = require('luaunit')

local base64 = require('jls.util.base64')
local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')

local EMPTY_DEFLATED = base64.decode('eJwDAAAAAAE=')
local SPACES_INFLATED = '                                                                                '
local SPACES_DEFLATED = base64.decode('eJxTUKAuAACVXwoB')
local SPACES_DEFLATED_100 = base64.decode('eJztwYEAAAAAgCCV/SkXqQoAAAAAAAAAGKcS6C4=')
local HELLO_WORLD_INFLATED = 'Hello world!'
local HELLO_WORLD_DEFLATED = base64.decode('eJzzSM3JyVcozy/KSVEEAB0JBF4=')

local VALUES = {'', 'a', 'ab', 'abc', HELLO_WORLD_INFLATED}

local function print_base64_deflated(s)
  print('"'..s..'" => '..base64.encode(Deflater:new():deflate(s, 'finish')))
end

local function print_base64_deflated_n(s, n)
  local deflater = Deflater:new()
  local deflated = ''
  for i = 1, n do
    deflated = deflated..deflater:deflate(s)
  end
  deflated = deflated..deflater:finish()
  print('"'..s..'" x '..tostring(n)..' => '..base64.encode(deflated))
end

local function print_base64_deflated_l(l)
  local deflater = Deflater:new()
  local deflated = ''
  for i, s in ipairs(l) do
    deflated = deflated..deflater:deflate(s)
    print('['..tostring(i)..'] => '..base64.encode(deflated))
  end
  deflated = deflated..deflater:finish()
  print('['..tostring(#l)..'] => '..base64.encode(deflated))
end

--[[]
print_base64_deflated('')
print_base64_deflated(SPACES_INFLATED)
print_base64_deflated(HELLO_WORLD_INFLATED)
print_base64_deflated_n(SPACES_INFLATED, 100)
]]

function Test_deflate()
  lu.assertEquals(Deflater:new():deflate(HELLO_WORLD_INFLATED, 'finish'), HELLO_WORLD_DEFLATED)
end

function Test_inflate()
  lu.assertEquals(Inflater:new():inflate(HELLO_WORLD_DEFLATED), HELLO_WORLD_INFLATED)
end

local function assertDeflateInflate(value, compressionLevel, windowBits)
  local deflated = Deflater:new(compressionLevel, windowBits):deflate(value, 'finish')
  local inflated = Inflater:new(windowBits):inflate(deflated)
  lu.assertEquals(inflated, value)
end

local function assertDeflateInflateAll(values, compressionLevel, windowBits)
  for _, value in ipairs(values) do
    assertDeflateInflate(value, compressionLevel, windowBits)
  end
end

function Test_deflate_inflate()
  assertDeflateInflateAll(VALUES)
end

function Test_deflate_inflate_compressionLevel()
  assertDeflateInflateAll(VALUES, 1)
  assertDeflateInflateAll(VALUES, 9)
end

function Test_deflate_inflate_windowBits()
  assertDeflateInflateAll(VALUES, nil, -15)
end

os.exit(lu.LuaUnit.run())
