--- Provide MessageDigest class.
-- Available algorithms are SHA-1, MD5, CRC32.
-- @module jls.util.MessageDigest
-- @pragma nostrip

local class = require('jls.lang.class')

--- The MessageDigest class.
-- The MessageDigest class provides access to algorithms that compute message digest or hash from any string or message.
-- @type MessageDigest
return class.create(function(messageDigest, _, MessageDigest)

  --- Updates the digest using the specified string.
  -- @tparam string m a message to update the digest.
  -- @treturn MessageDigest this message digest instance.
  -- @function messageDigest:update

  --- Completes and returns the digest.
  -- @treturn string the message digest result.
  -- @function messageDigest:digest

  --- Resets this MessageDigest.
  -- @treturn MessageDigest this message digest instance.
  -- @function messageDigest:reset

  --- Returns the name of the algorithm.
  -- @treturn string the name of the algorithm.
  -- @function messageDigest:getAlgorithm

  -- for compatibility, the methods above should be removed
  function messageDigest:initialize(alg)
    self.alg = alg
    self:reset()
  end

  function messageDigest:update(m)
    self.md:update(m)
    return self
  end

  function messageDigest:digest(m)
    if m then
      self.md:update(m)
    end
    return self.md:digest()
  end

  function messageDigest:reset()
    self.md = MessageDigest.getInstance(self.alg)
    return self
  end

  function messageDigest:getAlgorithm()
    return self.alg or class.getName(self:getClass()) or 'MessageDigest'
  end

  function messageDigest:finish(m)
    if m then
      self:update(m)
    end
    return self:digest()
  end

  function messageDigest:final()
    return self:digest()
  end

end, function(MessageDigest)

  --- Returns the MessageDigest corresponding to the specified algorithm.
  -- @tparam string alg The name of the algorithm.
  -- @return The MessageDigest class
  function MessageDigest.getMessageDigest(alg)
    return require('jls.util.md.'..string.lower(string.gsub(alg, '[%s%-]', '')))
  end

  --- Creates a new MessageDigest.
  -- @tparam string alg The name of the algorithm.
  -- @treturn MessageDigest a new MessageDigest
  -- @usage
  --local md = MessageDigest.getInstance('MD5')
  --md:update('The quick brown fox jumps over the lazy dog'):digest()
  function MessageDigest.getInstance(alg, ...)
    return MessageDigest.getMessageDigest(alg):new(...)
  end

  function MessageDigest.fromOpenssl(alg)
    local opensslLib = require('openssl') -- fail quickly if not available
    return class.create(MessageDigest, function(md)
      function md:initialize()
        self.md = opensslLib.digest.new(alg)
      end
      function md:update(m)
        self.md:update(m)
        return self
      end
      function md:digest()
        return self.md:final(true)
      end
      function md:reset()
        self.md:reset()
        return self
      end
      function md:getAlgorithm()
        return alg
      end
    end)
  end

end)
