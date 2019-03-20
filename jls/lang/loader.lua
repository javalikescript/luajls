--- This module contains helper functions to load Lua modules.
-- @module jls.lang.loader

local logger = require('jls.lang.logger')

--- Requires the specified Lua module.
-- @tparam string name the name of the module to load
-- @return the loaded module or nil if an error occured
local function tryRequire(name)
  local status, mod = pcall(function() return require(name) end)
  if status then
    return mod
  end
  if logger:isLoggable(logger.DEBUG) then
    logger:debug('tryRequire() fails to load module "'..name..'" due to "'..mod..'"')
  end
  return nil
end

-- The JLS_REQUIRES environment variable enables to pre load native/non jls modules
-- that can be used in case of multiple implementations
local jlsRequires = os.getenv('JLS_REQUIRES')
if jlsRequires then
  if logger:isLoggable(logger.DEBUG) then
    logger:debug('loads modules from JLS_REQUIRES: "'..jlsRequires..'"')
  end
  for name in string.gmatch(jlsRequires, '[^,%s]+') do
    tryRequire(name)
  end
end

--[[--
Requires one of the specified Lua modules.
The order is: the first already loaded module then
the first module whose name ends by an already loaded module.
If no module could be loaded then an error is raised.
@param ... the ordered names of the module eligible to load
@return the loaded module
@usage
return require('jls.lang.loader').requireOne('jls.net-luv', 'jls.net-socket')
]]
local function requireOne(...)
  local arg = {...}
  -- look for the first already loaded module
  for _, name in ipairs(arg) do
    local mod = package.loaded[name]
    if mod then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('requireOne() found loaded module "'..name..'"')
      end
      return mod
    end
  end
  -- try to load the first module whose name ends by an already loaded module
  for i, name in ipairs(arg) do
    local sname = string.match(name, '%-([^%-]+)$')
    if sname and package.loaded[sname] then
      local mod = tryRequire(name)
      if mod then
        if logger:isLoggable(logger.DEBUG) then
          logger:debug('requireOne() loads module "'..name..'" because "'..sname..'" is already loaded')
        end
        return mod
      else
        --table.remove(arg, i) -- we already know that this one cannot be loaded
      end
    end
  end
  -- look for the first loaded module
  for _, name in ipairs(arg) do
    local mod = tryRequire(name)
    if mod then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('requireOne() loads module "'..name..'"')
      end
      return mod
    end
  end
  error('No suitable module found')
end

--- Unloads the specified Lua module.
-- @tparam string name the name of the module to unload
local function unload(name)
  if logger:isLoggable(logger.DEBUG) then
    logger:debug('unload("'..name..'")')
  end
  package.loaded[name] = nil
end

--[[-- Unloads all the specified Lua modules.
@tparam string pattern the pattern of the module names to unload
@usage
require('jls.lang.loader').unloadAll('^jls%.')
]]
local function unloadAll(pattern)
  for name in pairs(package.loaded) do
    if not pattern or string.find(name, pattern) then
      unload(name)
    end
  end
end

return {
  requireOne = requireOne,
  tryRequire = tryRequire,
  unload = unload,
  unloadAll = unloadAll
}