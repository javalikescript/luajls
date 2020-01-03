local luvLib = require('luv')

local function listCopy(l)
  local nl = {}
  for _, v in ipairs(l) do
    table.insert(nl, v)
  end
  return nl
end

return {
  execute = function(command, cb)
    -- Windows uses 32-bit unsigned integers as exit codes
    -- windows system function does not return the exit code but the errno
    local async
    async = luvLib.new_async(function(status, kind, code)
      if status then
        cb()
      else
        cb({
          code = math.floor(code),
          kind = kind
        })
      end
      async:close()
    end)
    luvLib.new_thread(function(async, command)
      local status, kind, code = os.execute(command)
      async:send(status, kind, code)
    end, async, command)
  end,
  exePath = luvLib.exepath,
  kill = function(pid, sig)
    return luvLib.kill(pid, sig or 'sigint')
  end,
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
  spawn = function(pb, onexit)
    local options = {}
    options.args = listCopy(pb.cmd)
    local path = table.remove(options.args, 1)
    --print('path', path)
    --for i, v in ipairs(options.args) do print('arg['..tostring(i)..']', v, type(v)) end
    if type(pb.env) == 'table' then
      options.env = pb.env
    end
    if pb.dir then
      options.cwd = pb.dir
    end
    if pb.stdin or pb.stdout or pb.stderr then
      options.stdio = {pb.stdin, pb.stdout, pb.stderr}
    end
    options.verbatim = pb.verbatim == true
    options.detached = pb.detached == true
    options.hide = pb.hide == true
    local handle, pid = luvLib.spawn(path, options, onexit)
    if handle then
      if not (onexit or options.stdio) then
        luvLib.unref(handle)
      end
      return pid
    end
  end
}
