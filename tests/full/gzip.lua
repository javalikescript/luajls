local lu = require('luaunit')

local gzip = require('jls.util.zip.gzip')
local StreamHandler = require('jls.io.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')
local base64 = require('jls.util.base64')

local SAMPLE_PLAIN = 'Hello world !'

-- echo -n "Hello world !" | gzip | base64
local SAMPLE_GZIPPED = base64.decode('H4sIAAAAAAAAA/NIzcnJVyjPL8pJUVAEAEAsDgcNAAAA')

local function compress_decompress(data, header)
  local bufferedStream = BufferedStreamHandler:new(StreamHandler.null)
  local resultHeader
  local stream = gzip.compressStream(gzip.decompressStream(bufferedStream, function(header)
    resultHeader = header
  end), header)
  StreamHandler.fill(stream, data)
  return bufferedStream:getBuffer(), resultHeader
end

function Test_decompress()
  local bufferedStream = BufferedStreamHandler:new(StreamHandler.null)
  local stream = gzip.decompressStream(bufferedStream)
  StreamHandler.fill(stream, SAMPLE_GZIPPED)
  local result = bufferedStream:getBuffer()
  lu.assertEquals(result, SAMPLE_PLAIN)
end

function Test_compress()
  local bufferedStream = BufferedStreamHandler:new(StreamHandler.null)
  local stream = gzip.compressStream(bufferedStream)
  StreamHandler.fill(stream, SAMPLE_PLAIN)
  local result = bufferedStream:getBuffer()
  lu.assertEquals(base64.encode(result), base64.encode(SAMPLE_GZIPPED))
end

function Test_compress_decompress()
  local data = 'test'
  lu.assertEquals(compress_decompress(data), data)
end

function Test_compress_decompress_with_header()
  local data = [[
    I find it hard to believe you don't know
    The beauty that you are
    But if you don't let me be your eyes
    A hand in your darkness, so you won't be afraid
  ]]
  local header = {
    name = 'test name',
    comment = 'comment for test',
    modificationTime = 830908800,
    os = 11
  }
  local resultData, resultHeader = compress_decompress(data, header)
  lu.assertEquals(resultData, data)
  lu.assertEquals(resultHeader, header)
end

os.exit(lu.LuaUnit.run())
