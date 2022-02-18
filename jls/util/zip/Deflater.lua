--- Provide compression using the ZLIB library.
-- @module jls.util.zip.Deflater

local zLib = require('zlib')

--- The Deflater class.
-- A Deflater allows to compress data.
-- @type Deflater
return require('jls.lang.class').create(function(deflater)

  --[[
    If no compression_level is provided uses Z_DEFAULT_COMPRESSION (6),
    compression level is a number from 1-9 where zlib.BEST_SPEED is 1 and zlib.BEST_COMPRESSION is 9.
    windowBits Default is 15, MAX_WBITS
  ]]

  --- Creates a new Deflater with the specified compression level and window bits.
  -- @function Deflater:new
  -- @tparam number compressionLevel the compression level from 1-9, from BEST_SPEED to BEST_COMPRESSION
  -- @tparam number windowBits the window bits
  function deflater:initialize(compressionLevel, windowBits)
    self:reset(compressionLevel, windowBits)
  end

  function deflater:reset(compressionLevel, windowBits)
    self.stream = zLib.deflate(compressionLevel, windowBits)
    self.eof = false
    self.bytesIn = 0
    self.bytesOut = 0
  end

  --- Deflates the specified data.
  -- @tparam string buffer the data to deflate
  -- @tparam string flush the flush mode: sync, full or finish
  -- @return the deflated data
  function deflater:deflate(buffer, flush)
    -- nil, sync, full, finish
    local deflated
    deflated, self.eof, self.bytesIn, self.bytesOut = self.stream(buffer, flush)
    return deflated
  end

  function deflater:flushSync(buffer)
    return self:deflate(buffer, 'sync')
  end

  function deflater:flushFull(buffer)
    return self:deflate(buffer, 'full')
  end

  function deflater:finish(buffer)
    return self:deflate(buffer, 'finish')
  end

  function deflater:getBytesRead()
    return self.bytesIn
  end

  function deflater:getBytesWritten()
    return self.bytesOut
  end

  function deflater:finished()
    return self.eof
  end

end, function(Deflater)

  -- for compatibility, deprecated
  require('jls.lang.loader').lazyMethod(Deflater, 'deflateStream', function(deflate)
    return deflate.encodeStream
  end, 'jls.util.codec.deflate')

end)
