--[[--
Provides access to data and operations of the underlying OS.

Access to environnement variables and default standard file handles.
Operation such as the exit method and the garbage collection.

@module jls.lang.system
@pragma nostrip
]]

local sysLib = require('jls.lang.sys')
local loader = require('jls.lang.loader')
local FileDescriptor = loader.tryRequire('jls.io.FileDescriptor')

local isWindowsOS = string.sub(package.config, 1, 1) == '\\'

local win32Lib = isWindowsOS and loader.tryRequire('win32')

local system = {}

--- The Operating System (OS) line separator, '\\n' on Unix and '\\r\\n' on Windows.
-- @field system.lineSeparator
system.lineSeparator = isWindowsOS and '\r\n' or '\n'

if FileDescriptor then
  --- The standard input stream file descriptor.
  system.input = FileDescriptor:new(0)
  --- The standard output stream file descriptor.
  system.output = FileDescriptor:new(1)
  --- The standard error stream file descriptor.
  system.error = FileDescriptor:new(2)
else
  -- fallback to standard Lua files that provide a write function
  system.input = io.stdin
  system.output = io.stdout
  system.error = io.stderr
end

--- Returns the current time in seconds.
-- The time is given as the number of seconds since the Epoch, 1970-01-01 00:00:00 +0000 (UTC).
-- @return the current time in seconds.
-- @function system.currentTime
system.currentTime = os.time

--- Returns the current time in milliseconds.
-- @return The current time in milliseconds.
-- @function system.currentTimeMillis
system.currentTimeMillis = sysLib.timems

--- Causes the program to sleep.
-- @param millis The length of time to sleep in milliseconds.
-- @function system.sleep
system.sleep = sysLib.sleep

--- Gets a specific environnement property.
-- @param name The name of the property to get.
-- @return The environnement property.
-- @function system.getenv
system.getenv = os.getenv

system.setenv = sysLib.setenv

function system.isWindows()
  return isWindowsOS
end

--- Returns the arguments used when calling the Lua standalone executable.
-- @treturn table The arguments.
function system.getArguments()
  if not system.arguments then
    local shiftArguments = require('jls.lang.shiftArguments')
    if win32Lib then
      system.arguments = shiftArguments({win32Lib.GetCommandLineArguments()})
    elseif not arg and process and type(process.argv) == 'table' then
      system.arguments = shiftArguments(process.argv, 1)
    else
      system.arguments = arg or {} -- arg is nil in a thread
    end
  end
  return system.arguments
end

function system.getLibraryExtension()
  if isWindowsOS then
    return '.dll'
  end
  return '.so'
end

-- Returns the command line corresponding to the specified arguments.
-- @tparam table args Array of strings specifying the command-line arguments.
-- @treturn string the command line
-- @function system.currentTime
system.formatCommandLine = require('jls.lang.formatCommandLine')

--- Executes the specified command and arguments in a separate process with the specified environment and working directory.
-- @param command Array of strings specifying the command-line arguments.
-- The first argument is the name of the executable file.
-- @param env Array of key=values specifying the environment strings.
-- If undefined, the new process inherits the environment of the parent process.
-- @param dir The working directory of the subprocess, or undefined
-- if the subprocess should inherit the working directory of the current process.
-- @treturn jls.lang.ProcessHandle a handle of the new process
-- @function system.exec
loader.lazyMethod(system, 'exec', function(ProcessBuilder, Path)
  return function(command, env, dir)
    if type(command) == 'string' then
      command = {command}
    elseif type(command) ~= 'table' or #command < 1 then
      error('Missing command arguments')
    end
    local pb = ProcessBuilder:new(command)
    if env then
      pb:setEnvironment(env)
    end
    if dir then
      pb:setDirectory(Path.asNormalizedPath(dir))
    end
    return pb:start()
  end
end, 'jls.lang.ProcessBuilder', 'jls.io.Path')

--- Executes the specified command line in a separate thread.
-- The promise will be rejected if the process exit code is not zero.
-- The error is a table with a code and a kind fields.
-- @tparam string command The command-line to execute.
-- @tparam[opt] boolean anyCode true to resolve the promise with any exit code.
-- @tparam[opt] function callback an optional callback function to use in place of promise.
-- @treturn jls.lang.Promise a promise that resolves once the command has been executed.
-- @function system.execute
loader.lazyMethod(system, 'execute', function(Promise, Thread)
  local function applyExecuteCallback(cb, anyCode, status, kind, code)
    if anyCode then
      cb(nil, {
        code = math.floor(code),
        kind = kind
      })
    elseif status then
      cb()
    else
      cb('Execute fails with '..tostring(kind)..' code '..tostring(code))
    end
  end
  return function(command, anyCode, callback)
    if type(anyCode) == 'function' then
      callback = anyCode
      anyCode = false
    end
    -- TODO We may use a serial worker to avoid creating a thread for each execution
    local cb, d = Promise.ensureCallback(callback)
    if Thread then
      Thread:new(function(cmd)
        -- Windows uses 32-bit unsigned integers as exit codes
        -- windows system function does not return the exit code but the errno
        local osm = os -- avoid Lua compatibility as it is handled
        local status, kind, code = osm.execute(cmd)
        if type(status) == 'number' then
          return tostring(status == 0)..' exit '..tostring(status)
        end
        -- status is a shorter for kind == 'exit' and code == 0
        return tostring(status)..' '..kind..' '..tostring(code)
      end):start(command):ended():next(function(result)
        local status, kind, code = string.match(result, '^(%a+) (%a+) %-?(%d+)$')
        applyExecuteCallback(cb, anyCode, status == 'true', kind, tonumber(code))
      end, function(reason)
        cb(reason or 'Unknown error')
      end)
    else
      applyExecuteCallback(cb, anyCode, os.execute(command))
    end
    return d
  end
end, 'jls.lang.Promise', 'jls.lang.Thread')

loader.lazyMethod(system, 'findExecutablePath', function(File, strings)
  return function(name)
    if isWindowsOS then
      name = name..'.exe'
    end
    local path = os.getenv('PATH')
    --print('locate', name, 'sep', File.pathSeparator, 'path', path)
    if path then
      for _, p in ipairs(strings.split(path, File.pathSeparator, true)) do
        local f = File:new(p, name)
        if f:exists() then
          --print(f:getPath())
          return f:getPath()
        end
      end
    end
  end
end, 'jls.io.File', 'jls.util.strings')

local shutdownHooks = {}

local function runShutdownHooks()
  local list = shutdownHooks
  shutdownHooks = {}
  for _, fn in ipairs(list) do
    fn()
  end
end

-- Registers a function that will be called prior Lua termination.
function system.addShutdownHook(fn)
  if type(JLS_RUNTIME_GLOBAL_OBJECT) == 'nil' then
    -- registering a global object to check if the event loop has been called and processed all the events.
    JLS_RUNTIME_GLOBAL_OBJECT = setmetatable({}, {
      __gc = runShutdownHooks
    })
  end
  table.insert(shutdownHooks, fn)
end

--- Terminates the program and returns a value to the OS.
-- @param code The exit code to return to the OS.
function system.exit(code)
  runShutdownHooks()
  return os.exit(code, true)
end

--- Runs the garbage collector.
function system.gc()
  collectgarbage('collect')
end

--- Forcibly terminates the program and returns a value to the OS.
-- @param code The exit code to return to the OS.
function system.halt(code)
  runShutdownHooks()
  return os.exit(code, false)
end

return system