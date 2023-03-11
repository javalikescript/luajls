local zLib = require('zlib')

return require('jls.lang.class').create('jls.util.MessageDigest', function(crc32)

  function crc32:initialize()
    self:reset()
  end

  function crc32:update(s)
    self.value = self.compute(s)
    return self
  end

  function crc32:digest()
    return self.value >> 0
  end

  function crc32:reset()
    self.value = 0
    self.compute = zLib.crc32()
    return self
  end

  function crc32:getAlgorithm()
    return 'crc32'
  end

end)
