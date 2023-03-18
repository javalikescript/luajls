local StreamHandler = require('jls.io.StreamHandler')
local BufferedStreamHandler = require('jls.io.streams.BufferedStreamHandler')
local gzip = require('jls.util.zip.gzip')

return require('jls.lang.class').create('jls.util.Codec', function(codec)

  function codec:decode(value)
    local bufferedStream = BufferedStreamHandler:new()
    StreamHandler.fill(self:decodeStream(bufferedStream), value)
    return bufferedStream:getBuffer()
  end

  function codec:encode(value)
    local bufferedStream = BufferedStreamHandler:new()
    StreamHandler.fill(self:encodeStream(bufferedStream), value)
    return bufferedStream:getBuffer()
  end

  function codec:decodeStream(sh)
    return gzip.decompressStream(sh)
  end

  function codec:encodeStream(sh)
    return gzip.compressStream(sh)
  end

  function codec:getName()
    return 'gzip'
  end

end)
