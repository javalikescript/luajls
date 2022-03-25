local zLib = require('zlib')

return require('jls.lang.class').create(function(crc32)

  function crc32:initialize()
    self.value = 0
    self.compute = zLib.crc32()
  end

  function crc32:update(s)
    self.value = self.compute(s)
    return self
  end

  function crc32:final()
    return self.value >> 0
  end

  function crc32:digest(m)
    return zLib.crc32()(m)
  end

end, function(Crc32)

  function Crc32:digest(m)
    return zLib.crc32()(m)
  end

end)
