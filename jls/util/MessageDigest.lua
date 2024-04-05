--- Provide message digest algorithm functionality.
-- Available algorithms are `SHA-1`, `MD5`, `CRC32`.
-- @module jls.util.MessageDigest
-- @pragma nostrip

local class = require('jls.lang.class')
local StreamHandler = require('jls.io.StreamHandler')

local DigestStreamHandler = class.create(StreamHandler, function(digestStreamHandler, super)
  function digestStreamHandler:initialize(md)
    super.initialize(self)
    self.md = md
  end
  function digestStreamHandler:digest()
    return self._digest
  end
  function digestStreamHandler:onData(data)
    if data then
      self.md:update(data)
    elseif not self._digest then
      self._digest = self.md:digest()
    end
  end
end)

--- The MessageDigest class.
-- The MessageDigest class provides access to algorithms that compute message digest or hash from any string or message.
-- @type MessageDigest
return class.create(function(messageDigest, _, MessageDigest)

  --- Updates the digest using the specified string.
  -- @tparam string m a message to update the digest
  -- @treturn MessageDigest this message digest instance
  -- @function messageDigest:update

  --- Completes and returns the digest.
  -- @treturn string the message digest result
  -- @function messageDigest:digest

  --- Resets this MessageDigest.
  -- @treturn MessageDigest this message digest instance
  -- @function messageDigest:reset

  --- Returns the name of the algorithm.
  -- @treturn string the name of the algorithm
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
  -- @tparam string alg The name of the algorithm
  -- @return The MessageDigest class
  function MessageDigest.getMessageDigest(alg)
    local a = string.lower(string.gsub(alg, '[%s%-]', ''))
    local status, m
    status, m = pcall(require, 'jls.util.md.'..a)
    if status then
      return m
    end
    status, m = pcall(MessageDigest.fromOpenssl, a)
    if status then
      return m
    end
    error('Algorithm "'..alg..'" not found')
  end

  --- Creates a new MessageDigest.
  -- @tparam string alg The name of the algorithm
  -- @treturn MessageDigest a new MessageDigest
  -- @usage
  --local md = MessageDigest.getInstance('MD5')
  --md:update('The quick brown fox jumps over the lazy dog'):digest()
  function MessageDigest.getInstance(alg, ...)
    return MessageDigest.getMessageDigest(alg):new(...)
  end

  function MessageDigest.decodeStream(alg, ...)
    return DigestStreamHandler:new(MessageDigest.getInstance(alg, ...))
  end

  function MessageDigest.fromOpenssl(alg)
    local mdc = assert(require('openssl').digest.get(alg)) -- fail quickly if not available
    return class.create(MessageDigest, function(md)
      function md:initialize()
        self.md = mdc:new()
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
