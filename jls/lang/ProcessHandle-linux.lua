local linuxLib = require('linux')
local event = require('jls.lang.loader').requireOne('jls.lang.event-')
local Promise = require('jls.lang.Promise')

return require('jls.lang.class').create('jls.lang.ProcessHandleBase', function(processHandle)

  function processHandle:waitExitCode(timeoutMs)
    local id, kind, code = linuxLib.waitpid(self.pid, 0, timeoutMs or -1)
    if id then
      if kind == 'timeout' then
        return true
      elseif kind == 'exit' then
      elseif kind == 'signal' then
        code = code + 128
      end
      self.code = code
    end
    return false
  end

  function processHandle:isAlive()
    return self:waitExitCode(0)
  end

  function processHandle:destroy()
    return linuxLib.kill(self.pid, linuxLib.constants.SIGINT)
  end

  function processHandle:ended()
    if not self.endPromise then
      self.endPromise = Promise:new(function(resolve, reject)
        event:setTask(function(timeoutMs)
          if self:waitExitCode(timeoutMs) then
            return true
          end
          resolve(self.code)
          return false
        end, -1)
      end)
    end
    return self.endPromise
  end

end, function(ProcessHandle)

  ProcessHandle.getCurrentPid = linuxLib.getpid

end)
