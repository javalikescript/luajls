local luvLib = require('luv')

local function emptyFunction() end

return {
  kill = function(pid)
    luvLib.kill(pid, 'sigint')
  end,
  --[[
  uv.spawn(file, options, onexit) -> process, pid

  options.args - Command line arguments as a list of string. The first string should be the path to the program. On Windows this uses CreateProcess which concatenates the arguments into a string this can cause some strange errors. (See options.verbatim below for Windows.)
  options.stdio - Set the file descriptors that will be made available to the child process. The convention is that the first entries are stdin, stdout, and stderr. (Note On Windows file descriptors after the third are available to the child process only if the child processes uses the MSVCRT runtime.)
  options.env - Set environment variables for the new process.
  options.cwd - Set current working directory for the subprocess.
  options.uid - Set the child process' user id.
  options.gid - Set the child process' group id.
  options.verbatim - If true, do not wrap any arguments in quotes, or perform any other escaping, when converting the argument list into a command line string. This option is only meaningful on Windows systems. On Unix it is silently ignored.
  options.detached - If true, spawn the child process in a detached state - this will make it a process group leader, and will effectively enable the child to keep running after the parent exits. Note that the child process will still keep the parent's event loop alive unless the parent process calls uv.unref() on the child's process handle.
  options.hide - If true, hide the subprocess console window that would normally be created. This option is only meaningful on Windows systems. On Unix it is silently ignored.

  local function onexit(code, signal) end
  ]]
  execute = function(pathOrArgs, env, dir)
    local options = {}
    local path
    if type(pathOrArgs) == 'string' then
      path = pathOrArgs
    elseif type(pathOrArgs) == 'table' then
      path = pathOrArgs[1]
      options.args = pathOrArgs
    end
    if type(env) == 'table' then
      options.env = env
    end
    if dir then
      options.cwd = dir
    end
    local handle, pid = luvLib.spawn(path, options, emptyFunction)
    if handle then
      luvLib.unref(handle)
      return pid
    end
  end
}
