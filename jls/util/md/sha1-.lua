local sha1Lib = require('sha1')
local StringBuffer = require('jls.lang.StringBuffer')

return require('jls.lang.class').create('jls.util.MessageDigest', function(sha1)

  function sha1:initialize()
    self.buffer = StringBuffer:new()
  end

  function sha1:update(m)
    self.buffer:append(m)
    return self
  end

  function sha1:digest()
    return (sha1Lib.binary(self.buffer:toString()))
  end

  function sha1:reset()
    self.buffer:clear()
    return self
  end

  function sha1:getAlgorithm()
    return 'sha1'
  end

end)
