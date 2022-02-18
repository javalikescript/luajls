local StreamHandler = require('jls.io.streams.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')
local gzip = require('jls.util.zip.gzip')

return {
  decode = function(data, ...)
    local bufferedStream = BufferedStreamHandler:new()
    StreamHandler.fill(gzip.decompressStream(bufferedStream, ...), data)
    return bufferedStream:getBuffer()
  end,
  encode = function(data, ...)
    local bufferedStream = BufferedStreamHandler:new()
    StreamHandler.fill(gzip.compressStream(bufferedStream, ...), data)
    return bufferedStream:getBuffer()
  end,
  decodeStream = gzip.decompressStream,
  encodeStream = gzip.compressStream,
}
