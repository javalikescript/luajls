local sha1Lib = require('sha1')
local StringBuffer = require('jls.lang.StringBuffer')

return require('jls.lang.class').create(function(sha1)

  function sha1:initialize()
    self.buffer = StringBuffer:new()
  end

  function sha1:update(s)
    self.buffer:append(s)
    return self
  end

  function sha1:final()
    return sha1Lib.binary(self.buffer:toString())
  end

end, function(Sha1)

  function Sha1:digest(s)
    --return Sha1:new():update(s):final()
    return sha1Lib.binary(s)
  end
end)
