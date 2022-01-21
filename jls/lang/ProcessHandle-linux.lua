local linuxLib = require('linux')
local event = require('jls.lang.loader').requireOne('jls.lang.event-')
local Promise = require('jls.lang.Promise')

return require('jls.lang.class').create('jls.lang.ProcessHandleBase', function(processHandle)

  function processHandle:isAlive()
    local id, status, code = linuxLib.waitpid(self.pid)
    if id == self.pid then
      if status then
        self.code = code
      else
        return true
      end
    end
    return false
  end

  function processHandle:destroy()
    return linuxLib.kill(self.pid, linuxLib.constants.SIGINT)
  end

  function processHandle:ended()
    if not self.endPromise then
      self.endPromise = Promise:new(function(resolve, reject)
        event:setTask(function()
          local id, status, code = linuxLib.waitpid(self.pid)
          if id == self.pid then
            if status then
              self.code = code
              resolve(code)
              return false
            else
              return true
            end
          end
          reject('unable to retrieve exit code')
          return false
        end, 500)
      end)
    end
    return self.endPromise
  end

end, function(ProcessHandle)

  ProcessHandle.getCurrentPid = linuxLib.getpid

end)
