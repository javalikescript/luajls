local hmac = require('openssl').hmac

return require('jls.lang.class').create('jls.util.MessageDigest', function(md)
  function md:initialize(alg, key)
    self.hashAlg = alg
    self.key = key
    self:reset()
  end
  function md:update(m)
    self.md:update(m)
    return self
  end
  function md:digest()
    return self.md:final(true)
  end
  function md:reset()
    self.md = hmac.new(self.hashAlg, self.key)
    return self
  end
  function md:getAlgorithm()
    return 'HMAC'
  end
end)
