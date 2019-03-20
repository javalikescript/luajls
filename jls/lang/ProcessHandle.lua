--- Represents a native process.
-- @module jls.lang.ProcessHandle
-- @pragma nostrip

local processLib = require('jls.lang.process')
--local logger = require('jls.lang.logger')

--- A ProcessHandle class.
-- @type ProcessHandle
return require('jls.lang.class').create(function(processHandle)

  function processHandle:initialize(pid)
    self.pid = pid
  end
  
  --- Returns the Process ID for this process.
  -- @return the Process ID for this process.
  function processHandle:getPid()
    return self.pid
  end
  
  --- Destroys this process.
  function processHandle:destroy()
    processLib.kill(self.pid)
  end
  
  --- Destroys this process.
  function processHandle:destroyForcibly()
    processLib.kill(self.pid)
  end
  
end, function(ProcessHandle)
  
  --- Returns a new ProcessHandle with the specified Process ID.
  -- @return a new ProcessHandle with the specified Process ID.
  function ProcessHandle.of(pid)
    return ProcessHandle:new(pid)
  end

end)