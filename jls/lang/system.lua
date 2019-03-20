--- The System module provides access to data and operations of the underlying OS.
-- Access to environnement variables and default standard file handles.
-- Operation such as the exit method, the garbage collection and the ability to load native library. 
-- @module jls.lang.system

local loader = require('jls.lang.loader')
local logger = require('jls.lang.logger')
local runtime = require('jls.lang.runtime')

local luaSocketLib = loader.tryRequire('socket.core')

local system = {}

--- The standard input file handle.
-- @field input
system.input = io.input()

--- The standard output file handle.
-- @field output
system.output = io.output()


--- Returns the current time in seconds.
-- The time is given as the number of seconds since the Epoch, 1970-01-01 00:00:00 +0000 (UTC). 
-- @return the current time in seconds.
function system.currentTime()
  return os.time()
end

--- Returns the current time in milliseconds.
-- @return The current time in milliseconds.
-- @function system.currentTimeMillis
if luaSocketLib then
  system.currentTimeMillis = function ()
    return math.floor(luaSocketLib.gettime() * 1000)
  end
else
  system.currentTimeMillis = function ()
    return os.time() * 1000
  end
end

--- Causes the program to sleep.
-- @param millis The length of time to sleep in milliseconds.
function system.sleep(millis)
  if logger:isLoggable(logger.DEBUG) then
    logger:debug('system.sleep('..tostring(millis)..')')
  end
  luaSocketLib.sleep(millis / 1000)
  -- luvLib.sleep(millis)
end

--- Terminates the program and returns a value to the OS.
-- @function system.exit
-- @param code The exit code to return to the OS.
system.exit = runtime.exit

--- Gets a specific environnement property.
-- @param name The name of the property to get.
-- @return The environnement property.
function system.getenv(name)
  return os.getenv(name)
end

local isWindowsOS = false
if string.sub(package.config, 1, 1) == '\\' or string.find(package.cpath, '%.dll') then
  isWindowsOS = true
end
function system.isWindows()
  return isWindowsOS
end

function system.getLibraryExtension()
  if isWindowsOS then
    return '.dll'
  end
  return '.so'
end

--- Runs the garbage collector. 
-- @function system.gc
system.gc = runtime.gc

return system