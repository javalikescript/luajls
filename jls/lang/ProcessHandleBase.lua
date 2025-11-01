--- Represents a native process.
-- @module jls.lang.ProcessHandle
-- @pragma nostrip

local class = require('jls.lang.class')
local loader = require('jls.lang.loader')
local logger = require('jls.lang.logger'):get(...)

local EXECUTABLE_PATH = 'lua' -- fallback

-- look for the lua path in the arguments
if arg then
  for i = -1, -10, -1 do
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

local isWindowsOS = string.sub(package.config, 1, 1) == '\\'

local DESTROY_COMMAND_LINE, ALIVE_COMMAND_LINE
if isWindowsOS then
  DESTROY_COMMAND_LINE = 'taskkill /f /pid %d >NUL'
  ALIVE_COMMAND_LINE = 'tasklist /fi "PID eq %d" | findstr "PID" >NUL'
else
  DESTROY_COMMAND_LINE = 'kill %d >/dev/null'
  ALIVE_COMMAND_LINE = 'ps -p %d | grep -v defunct | grep -q %d'
end

local function execute(command, pid)
  local cmd = string.gsub(command, '%%d', pid)
  logger:fine('execute(%s)', cmd)
  return os.execute(cmd)
end

--- A ProcessHandle class.
-- @type ProcessHandle
return class.create(function(processHandle)

  function processHandle:initialize(pid)
    self.pid = pid
  end

  --- Returns the Process ID for this process.
  -- @return The Process ID for this process
  function processHandle:getPid()
    return self.pid
  end

  --- Returns true if this process is alive.
  -- @treturn boolean true if this process is alive
  function processHandle:isAlive()
    if self.code ~= nil then
      return false
    end
    if self.pid then
      if execute(ALIVE_COMMAND_LINE, self.pid) then
        return true
      end
      self.code = 128
      return false
    end
    return true
  end

  --- Returns a promise that resolves once this process is terminated.
  -- @treturn jls.lang.Promise A promise that resolves once this process is terminated
  -- @function processHandle:ended
  function processHandle:ended()
    local event = loader.requireOne('jls.lang.event-')
    local Promise = require('jls.lang.Promise')
    if not self.endPromise then
      self.endPromise = Promise:new(function(resolve)
        event:setTask(function()
          if self:isAlive() then
            return true
          end
          resolve(self.code)
          return false
        end)
      end)
    end
    return self.endPromise
  end

  function processHandle:getExitCode()
    return self.code
  end

  --- Destroys this process.
  function processHandle:destroy()
    if self.pid then
      execute(DESTROY_COMMAND_LINE, self.pid)
      self.code = 130
    else
      error('no PID')
    end
  end

  -- processHandle:destroyForcibly

end, function(ProcessHandle)

  --- Returns a new ProcessHandle with the specified Process ID.
  -- @tparam number pid The process identifier
  -- @return A new ProcessHandle with the specified Process ID
  function ProcessHandle.of(pid)
    return ProcessHandle:new(pid)
  end

  --- Returns the Process ID of the current process.
  -- @treturn number The Process ID of the current process
  -- @function ProcessHandle.getCurrentPid
  ProcessHandle.getCurrentPid = class.notImplementedFunction

  ProcessHandle.getPid = ProcessHandle.getCurrentPid

  --- Returns the current executable path.
  -- @treturn string The current executable path
  function ProcessHandle.getExecutablePath()
    return EXECUTABLE_PATH
  end

  loader.lazyMethod(ProcessHandle, 'build', function(formatCommandLine, system)
    return function(processBuilder)
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
      local ph = ProcessHandle:new()
      local line = formatCommandLine(processBuilder.cmd)
      system.execute(line, true, function(e, r)
        if e then
          logger:warn('fail to execute(%s) due to %s', line, e)
          ph.code = 1
        elseif r.kind == 'exit' then
          ph.code = r.code
        else
          ph.code = r.code + 128
        end
      end)
      return ph
    end
  end, true, 'jls.lang.formatCommandLine', 'jls.lang.system')

end)