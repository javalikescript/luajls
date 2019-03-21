
local luvLib = require('luv')

local Promise = require('jls.lang.Promise')
local streams = require('jls.io.streams')

return require('jls.lang.class').create(function(pipe)

  function pipe:initialize(fd)
    self.fd = fd or luvLib.new_pipe(false)
  end

  function pipe:close(callback)
    local cb, d = Promise.ensureCallback(callback)
    luvLib.close(self.fd, cb)
    return d
  end

  function pipe:shutdown(callback)
    local cb, d = Promise.ensureCallback(callback)
    luvLib.shutdown(self.fd, cb)
    return d
  end

  function pipe:write(data, callback)
    local cb, d = Promise.ensureCallback(callback)
    luvLib.write(self.fd, data, cb)
    return d
  end

  function pipe:readStart(stream)
    local cb = streams.ensureCallback(stream)
    return luvLib.read_start(self.fd, cb) -- TODO handle error
  end

  function pipe:readStop()
    luvLib.read_stop(self.fd)
  end

end, function(Pipe)

  function Pipe.create(ipc)
    return Pipe:new(luvLib.new_pipe(ipc == true))
  end

end)
