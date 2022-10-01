local lcLib = require('luachild')

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')
local loader = require('jls.lang.loader')
local StreamHandler = require('jls.io.StreamHandler')
local event = loader.requireOne('jls.lang.event-')
local linuxLib = loader.tryRequire('linux')

local function deferCallback(cb, err, res)
  if cb then
    event:setTimeout(function()
      cb(err, res)
    end)
  end
end


return class.create(function(pipe, _, Pipe)

  function pipe:initialize()
    local r, w = lcLib.pipe()
    if not r then
      error(w or 'fail to create pipe')
    end
    if linuxLib then
      local flags = linuxLib.fcntl(r, linuxLib.constants.F_GETFL)
      linuxLib.fcntl(r, linuxLib.constants.F_SETFL, flags | linuxLib.constants.O_NONBLOCK)
    end
    self.readFd = r
    self.writeFd = w
    if logger:isLoggable(logger.FINEST) then
      logger:finest('Pipe:new() r: '..tostring(self.readFd)..', w: '..tostring(self.writeFd))
    end
  end

  function pipe:bind(name, backlog)
    error('Not supported')
  end

  function pipe:connect(name, callback)
    error('Not supported')
  end

  function pipe:open(f) -- f as integer
  end

  function pipe:readSync(size)
    return self.readFd:read(size)
  end

  function pipe:writeSync(data)
    return self.writeFd:write(data)
  end

  function pipe:readStart(callback)
    if self.readTaskId then
      error('already started')
    end
    local cb = StreamHandler.ensureCallback(callback)
    local size = 1024
    self.readTaskId = event:setTask(function()
      if self.readFd then
        local data, err, errnum = self.readFd:read(size) -- will block on Windows
        if data then
          cb(nil, data)
          return true
        elseif linuxLib and errnum == linuxLib.constants.EAGAIN then
          return true
        end
      end
      self.readTaskId = nil
      cb()
      return false
    end)
  end

  function pipe:readStop()
    if self.readTaskId then
      event:clearInterval(self.readTaskId)
      self.readTaskId = nil
    end
  end

  function pipe:write(data, callback)
    local cb, d = Promise.ensureCallback(callback)
    self.writeFd:write(data)
    deferCallback(cb)
    return d
  end

  function pipe:chmod(mode)
  end

  function pipe:close(callback)
    local cb, d = Promise.ensureCallback(callback)
    if self.readFd then
      self.readFd:close()
      self.readFd = nil
    end
    if self.writeFd then
      self.writeFd:close()
      self.writeFd = nil
    end
    deferCallback(cb)
    return d
  end

  function pipe:isClosed()
    return not (self.readFd or self.readFd)
  end

  function pipe:shutdown(callback)
    logger:finest('pipe:shutdown()')
    local cb, d = Promise.ensureCallback(callback)
    self.writeFd:close()
    self.writeFd = nil
    deferCallback(cb)
    return d
  end

end)
