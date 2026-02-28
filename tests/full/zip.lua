local lu = require('luaunit')

local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')

local HELLO_WORLD_INFLATED = 'Hello world!'
local HELLO_WORLD_DEFLATED = '\x78\x9C\xF3\x48\xCD\xC9\xC9\x57\x28\xCF\x2F\xCA\x49\x51\x04\x00\x1D\x09\x04\x5E'

local VALUES = {'', 'a', 'ab', 'abc', HELLO_WORLD_INFLATED}

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
