local win32Lib = require('win32')
local event = require('jls.lang.loader').requireOne('jls.lang.event-')
local Promise = require('jls.lang.Promise')

return require('jls.lang.class').create('jls.lang.ProcessHandleBase', function(processHandle)

  function processHandle:isAlive()
    local code = win32Lib.GetExitCodeProcess(self.pid)
    return code == win32Lib.constants.STILL_ACTIVE
  end

  function processHandle:destroy()
    return win32Lib.TerminateProcessId(self.pid)
  end

  function processHandle:ended()
    if not self.endPromise then
      self.endPromise = Promise:new(function(resolve, reject)
        event:setTask(function(timeoutMs)
          local status, code = win32Lib.WaitProcessId(self.pid, timeoutMs, true)
          if status == win32Lib.constants.WAIT_OBJECT_0 then
            resolve(code)
            return false
          end
          return true
        end, -1)
      end)
    end
    return self.endPromise
  end

end, function(ProcessHandle)

  ProcessHandle.getCurrentPid = win32Lib.GetCurrentProcessId

end)
