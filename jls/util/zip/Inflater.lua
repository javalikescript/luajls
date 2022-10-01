--- Provide decompression using the ZLIB library.
-- @module jls.util.zip.Inflater

local zLib = require('zlib')

--- The Inflater class.
-- A Inflater allows to decompress data.
-- @type Inflater
return require('jls.lang.class').create(function(inflater)

  --[[
    The windowBits parameter is the base two logarithm of the maximum window size.
    windowBits can also be -8..-15 for raw inflate.
    In this case, -windowBits determines the window size.
    inflate() will then process raw deflate data, not looking for a zlib or gzip header,
    not generating a check value, and not looking for any check values for comparison at the end of the stream.

    windowBits can also be greater than 15 for optional gzip decoding.
    Add 32 to windowBits to enable zlib and gzip decoding with automatic headerdetection,
    or add 16 to decode only the gzip format (the zlib format will return a Z_DATA_ERROR).
    If a gzip stream is being decoded, strm->adler is a CRC-32 instead of an Adler-32. 

    By default, we will do gzip header detection w/ max window size */

    Default is 15+32, MAX_WBITS+32
  ]]
  --- Creates a new Inflater with the specified window bits.
  -- @function Inflater:new
  -- @tparam[opt] number windowBits the window bits
  function inflater:initialize(windowBits)
    self:reset(windowBits)
  end

  function inflater:reset(windowBits)
    self.stream = zLib.inflate(windowBits)
    self.eof = false
    self.bytesIn = 0
    self.bytesOut = 0
  end

  --- Inflates the specified data.
  -- @tparam string buffer the data to inflate
  -- @return the inflated data
  function inflater:inflate(buffer)
    local inflated
    inflated, self.eof, self.bytesIn, self.bytesOut = self.stream(buffer)
    return inflated
  end

  function inflater:getBytesRead()
    return self.bytesIn
  end

  function inflater:getBytesWritten()
    return self.bytesOut
  end

  function inflater:finished()
    return self.eof
  end

end, function(Inflater)

  -- for compatibility, deprecated
  require('jls.lang.loader').lazyMethod(Inflater, 'inflateStream', function(deflate)
    return deflate.decodeStream
  end, 'jls.util.cd.deflate')

end)
