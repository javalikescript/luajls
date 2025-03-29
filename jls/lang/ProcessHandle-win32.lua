local win32Lib = require('win32')
local event = require('jls.lang.loader').requireOne('jls.lang.event-')
local logger = require('jls.lang.logger'):get(...)
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
          logger:fine('waiting process id %d with timeout %s', self.pid, timeoutMs)
          local status, code = win32Lib.WaitProcessId(self.pid, timeoutMs, true)
          logger:fine('wait ended for process id %d => %s, %s', self.pid, status, code)
          if status == win32Lib.constants.WAIT_TIMEOUT then
            return true
          elseif status == win32Lib.constants.WAIT_OBJECT_0 then
            resolve(code)
          elseif status == win32Lib.constants.WAIT_ABANDONED then
            -- the mutex object that was not released before the owning thread terminated
            reject('abandoned')
          elseif status == win32Lib.constants.WAIT_FAILED then
            reject('unable to wait process due to '..(win32Lib.GetMessageFromSystem() or 'n/a'))
          else
            reject('unexpected return status '..tostring(status))
          end
          return false
        end, -1)
      end)
    end
    return self.endPromise
  end

end, function(ProcessHandle)

  ProcessHandle.getCurrentPid = win32Lib.GetCurrentProcessId

end)
