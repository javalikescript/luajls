--- Represents a native process.
-- @module jls.lang.ProcessHandle
-- @pragma nostrip

local Promise = require('jls.lang.Promise')
local formatCommandLine = require('jls.lang.formatCommandLine')

local EXECUTABLE_PATH = 'lua' -- fallback

-- look for the lua path in the arguments
if arg then
  for i = 0, -10, -1 do
    if arg[i] then
      EXECUTABLE_PATH = arg[i]
    else
      break
    end
  end
end
-- TODO compute absolute path
--local lfsLib = require('lfs')
--lfsLib.currentdir()

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

  --- Returns true if this process is alive.
  function processHandle:isAlive()
    return false
  end

  --- Returns a promise that resolves once this process is terminated.
  -- @treturn jls.lang.Promise a promise that resolves once this process is terminated.
  function processHandle:ended()
    if self.code then
      Promise.resolve(self.code)
    end
    return Promise.reject()
  end

  function processHandle:getExitCode()
    return self.code
  end

  --- Destroys this process.
  function processHandle:destroy()
  end

  -- processHandle:destroyForcibly

end, function(ProcessHandle)

  --- Returns a new ProcessHandle with the specified Process ID.
  -- @return a new ProcessHandle with the specified Process ID.
  function ProcessHandle.of(pid)
    return ProcessHandle:new(pid)
  end

  --- Returns the Process ID of the current process.
  -- @treturn number the Process ID of the current process.
  function ProcessHandle.getCurrentPid()
    error('not available')
  end

  ProcessHandle.getPid = ProcessHandle.getCurrentPid

  --- Returns the current executable path.
  -- @treturn string the current executable path.
  function ProcessHandle.getExecutablePath()
    return EXECUTABLE_PATH
  end

  function ProcessHandle.build(processBuilder)
    if processBuilder.stdin or processBuilder.stdout or processBuilder.stderr then
      -- TODO use popen
      error('cannot redirect')
    end
    if type(processBuilder.env) == 'table' then
      error('cannot set env')
    end
    if processBuilder.dir then
      error('cannot set dir')
    end
    local line = formatCommandLine(processBuilder.cmd)
    local status, kind, num = os.execute(line) -- will block
    local ph = ProcessHandle:new()
    if kind == 'exit' then
      ph.code = num
    elseif kind == 'signal' then
      ph.code = num + 128
    end
    return nil
  end

end)