--- The System module provides access to data and operations of the underlying OS.
-- Access to environnement variables and default standard file handles.
-- Operation such as the exit method, the garbage collection and the ability to load native library.
-- @module jls.lang.system

local sysLib = require('jls.lang.sys')
local loader = require('jls.lang.loader')
local FileDescriptor = loader.tryRequire('jls.io.FileDescriptor')

local isWindowsOS = string.sub(package.config, 1, 1) == '\\' or string.find(package.cpath, '%.dll')

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

--- Terminates the program and returns a value to the OS.
-- @param code The exit code to return to the OS.
function system.exit(code)
  return os.exit(code, true)
end

--- Gets a specific environnement property.
-- @param name The name of the property to get.
-- @return The environnement property.
-- @function system.getenv
system.getenv = os.getenv

function system.isWindows()
  return isWindowsOS
end

--- Returns the arguments used when calling the Lua standalone executable.
-- @return The environnement property.
function system.getArguments()
  if win32Lib then
    local args = table.pack(win32Lib.GetCommandLineArguments())
    local scriptName = arg[0]
    local scriptIndex = 0
    for i, v in ipairs(args) do
      if v == scriptName then
        scriptIndex = i
        break
      end
    end
    -- Before running any code, lua collects all command-line arguments in a global table called arg.
    -- The script name goes to index 0, the first argument after the script name goes to index 1, and so on.
    local narg = {}
    for i, v in ipairs(args) do
      narg[i - scriptIndex] = v
    end
    return narg
  end
  return arg
end

function system.getLibraryExtension()
  if isWindowsOS then
    return '.dll'
  end
  return '.so'
end

--- Runs the garbage collector.
function system.gc()
  collectgarbage('collect')
end

return system