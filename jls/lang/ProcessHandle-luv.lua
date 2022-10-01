local luvLib = require('luv')
local Promise = require('jls.lang.Promise')

--[[
uv.spawn(file, options, onexit) -> process, pid

options.args - Command line arguments as a list of string. The first string should be the path to the program.
  On Windows this uses CreateProcess which concatenates the arguments into a string this can cause some strange errors. (See options.verbatim below for Windows.)
options.stdio - Set the file descriptors that will be made available to the child process.
  The convention is that the first entries are stdin, stdout, and stderr. (Note On Windows file descriptors after the third are available to the child process only if the child processes uses the MSVCRT runtime.)
options.env - Set environment variables for the new process, as an array of key=value string.
options.cwd - Set current working directory for the subprocess.
options.uid - Set the child process' user id.
options.gid - Set the child process' group id.
options.verbatim - If true, do not wrap any arguments in quotes, or perform any other escaping, when converting the argument list into a command line string.
    This option is only meaningful on Windows systems. On Unix it is silently ignored.
options.detached - If true, spawn the child process in a detached state - this will make it a process group leader,
  and will effectively enable the child to keep running after the parent exits. Note that the child process will still keep the parent's event loop alive unless the parent process calls uv.unref() on the child's process handle.
options.hide - If true, hide the subprocess console window that would normally be created.
  This option is only meaningful on Windows systems. On Unix it is silently ignored.

local function onexit(code, signal) end
]]

local function getPipeFd(pipe)
  if type(pipe) == 'table' and pipe.fd then
    return pipe.fd
  end
  return nil
end

return require('jls.lang.class').create('jls.lang.ProcessHandleBase', function(processHandle)

  function processHandle:isAlive()
    return luvLib.kill(self.pid, 0) == 0
  end

  function processHandle:destroy()
    return luvLib.kill(self.pid, 'sigint') -- TODO return true on success
  end

  function processHandle:ended()
    return self.endPromise or Promise.reject()
  end

end, function(ProcessHandle)

  ProcessHandle.getCurrentPid = luvLib.os_getpid

  ProcessHandle.getExecutablePath = luvLib.exepath

  ProcessHandle.build = function(processBuilder)
    local args = {}
    for _, v in ipairs(processBuilder.cmd) do
      table.insert(args, v)
    end
    local path = table.remove(args, 1)
    local options = {}
    if #args > 0 then
      options.args = args
    end
    if type(processBuilder.env) == 'table' then
      local env = {}
      for k, v in pairs(processBuilder.env) do
        table.insert(env, k..'='..v)
      end
      options.env = env
    end
    if processBuilder.dir then
      options.cwd = processBuilder.dir
    end
    if processBuilder.stdin or processBuilder.stdout or processBuilder.stderr then
      options.stdio = {
        getPipeFd(processBuilder.stdin),
        getPipeFd(processBuilder.stdout),
        getPipeFd(processBuilder.stderr)
      }
    end
    options.verbatim = processBuilder.verbatim == true
    options.detached = processBuilder.detached == true
    options.hide = processBuilder.hide == true
    local onExitCallback
    local ph = ProcessHandle:new()
    if not options.detached then
      ph.endPromise = Promise:new(function(resolve, reject)
        onExitCallback = function(code, signal)
          ph.code = code
          ph.signal = signal
          resolve(code)
        end
      end)
    end
    local handle, pid = luvLib.spawn(path, options, onExitCallback)
    if handle then
      ph.pid = pid
      ph.handle = handle
      if not (onExitCallback or options.stdio) then
        luvLib.unref(handle)
      end
      return ph
    end
    return nil, pid
  end

end)
