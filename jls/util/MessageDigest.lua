--- Provide MessageDigest class.
-- @module jls.util.MessageDigest

--- The MessageDigest class.
-- The MessageDigest class provides access to algorithms that compute message digest or hash from any string or message.
-- @type MessageDigest
return require('jls.lang.class').create(function(messageDigest)

  --- Creates a new MessageDigest.
  -- @function MessageDigest:new
  -- @tparam string alg The name of the algorithm.
  -- @return a new MessageDigest
  -- @usage
  --local md = MessageDigest:new('md5')
  --md:digest('The quick brown fox jumps over the lazy dog')
  function messageDigest:initialize(alg)
    if type(alg) == 'string' then
      self.md = require('jls.util.md.'..alg)
    elseif type(alg) == 'table' and type(alg.digest) == 'function' then
      self.md = alg
    else
      error('Bad algorithm type')
    end
  end

  --- Resets this MessageDigest.
  function messageDigest:reset()
    self.mdc = self.md:new()
  end

  --- Updates the digest using the specified string.
  -- @tparam string m a message to update the digest.
  function messageDigest:update(m)
    if not self.mdc then
      self:reset()
    end
    self.mdc:update(m)
  end

  --- Completes and returns the digest.
  -- @tparam[opt] string m a message to update the digest.
  -- @treturn string the message digest result.
  function messageDigest:finish(m)
    if m then
      self:update(m)
    end
    return self.mdc:final(true)
  end

  --- Returns the digest using the specified string.
  -- @tparam string m a message to compute the digest.
  -- @treturn string the message digest result.
  function messageDigest:digest(m)
    return self.md:digest(m)
  end

end)