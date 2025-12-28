local MessageDigest = require('jls.util.MessageDigest')

return require('jls.lang.class').create(MessageDigest, function(md)

  function md:initialize(alg, key)
    alg = alg or 'SHA-256'
    local mdc = MessageDigest.getMessageDigest(alg)
    local algSize = tonumber(string.match(alg, '(%d+)$'))
    local blockSize = 64
    if algSize == 512 or algSize == 384 then
      blockSize = 128
    end
    local k = tostring(key or '')
    if #k > blockSize then
      local kd = mdc:new()
      kd:update(k)
      k = kd:digest()
    end
    if #k < blockSize then
      k = k..string.rep('\0', blockSize - #k)
    end
    local ipad = {}
    local opad = {}
    for i = 1, blockSize do
      local b = string.byte(k, i) or 0
      ipad[i] = string.char(b ~ 0x36)
      opad[i] = string.char(b ~ 0x5c)
    end
    self.ipad = table.concat(ipad)
    self.opad = table.concat(opad)
    self.mdc = mdc
    self:reset()
  end

  function md:update(m)
    self.inner:update(m)
    return self
  end

  function md:digest()
    local innerDigest = self.inner:digest()
    self.outer:update(innerDigest)
    local res = self.outer:digest()
    self:reset()
    return res
  end

  function md:reset()
    self.inner = self.mdc:new()
    self.outer = self.mdc:new()
    self.inner:update(self.ipad)
    self.outer:update(self.opad)
    return self
  end

  function md:getAlgorithm()
    return 'HMAC'
  end
end)
