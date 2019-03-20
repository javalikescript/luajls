--- Provide MessageDigest class.
-- @module jls.util.MessageDigest

--- The MessageDigest class.
-- @type MessageDigest
return require('jls.lang.class').create(function(messageDigest)

  function messageDigest:initialize(alg)
    if type(alg) == 'string' then
      self.md = require('jls.util.md.'..alg)
    elseif type(alg) == 'table' and type(alg.digest) == 'function' then
      self.md = alg
    else
      error('Bad algorithm type')
    end
  end

  function messageDigest:reset()
    self.mdc = self.md:new()
  end

  function messageDigest:update(m)
    if not self.mdc then
      self:reset()
    end
    self.mdc:update(m)
  end

  function messageDigest:finish(m)
    if m then
      self:update(m)
    end
    return self.mdc:final(true)
  end

  function messageDigest:digest(m)
    return self.md:digest(m)
  end

end)