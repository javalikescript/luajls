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

--- Returns the specified Lua module if already loaded.
-- @tparam string name the name of the module to load
-- @return the already loaded module or nil if none
local function getRequired(name)
  return package.loaded[name]
end

local NOT_LOADED = {}

--- Returns a funtion that will try to require the specified Lua module only once.
-- @tparam string name the name of the module to load
-- @treturn funtion a function that will return the specified module or nil if an error occured
local function singleRequirer(name)
  local module = NOT_LOADED
  return function()
    if module == NOT_LOADED then
      module = tryRequire(name)
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('singleRequirer() fails to load module "'..name..'"')
      end
    end
    return module
  end
end

local BASE_REQUIRE = require

-- The JLS_REQUIRES environment variable enables to pre load native/non jls modules
-- that can be used in case of multiple implementations
local jlsRequires = os.getenv('JLS_REQUIRES')
if jlsRequires then
  local jlsObviates = {}
  local isDebugLoggable = logger:isLoggable(logger.DEBUG)
  require = function(name)
    if isDebugLoggable then
      logger:debug('require("'..tostring(name)..'")')
    end
    if jlsObviates[name] then
      error('The module "'..tostring(name)..'" is deactivated via JLS_REQUIRES')
    end
    return BASE_REQUIRE(name)
  end
  local reentrancyKey = '__JLS_LOADER_REENTRANCY'
  if package.loaded[reentrancyKey] then
    error('Reentrancy detected')
  end
  package.loaded[reentrancyKey] = true
  if isDebugLoggable then
    logger:debug('loads modules from JLS_REQUIRES: "'..jlsRequires..'"')
  end
  for name in string.gmatch(jlsRequires, '[^,%s]+') do
    local nname = string.match(name, '!(.+)$')
    if nname then
      jlsObviates[nname] = true
      if isDebugLoggable then
        logger:debug('obviated module "'..nname..'"')
      end
    else
      if isDebugLoggable then
        logger:debug('preload required module "'..name..'"')
      end
      local mod = tryRequire(name)
      if not mod then
        logger:warn('Fail to load required module "'..name..'"')
      end
    end
  end
  if next(jlsObviates) == nil then
    require = BASE_REQUIRE
  end
  package.loaded[reentrancyKey] = nil
  jlsRequires = nil
  reentrancyKey = nil
  isDebugLoggable = nil
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
  local names = {}
  for _, name in ipairs(arg) do
    local sname = string.match(name, '%-([^%-]+)$')
    if sname and package.loaded[sname] then
      local mod = tryRequire(name)
      if mod then
        if logger:isLoggable(logger.DEBUG) then
          logger:debug('requireOne() loads module "'..name..'" because "'..sname..'" is already loaded')
        end
        return mod
      end
    else
      table.insert(names, name)
    end
  end
  -- look for the first module that loads
  for _, name in ipairs(names) do
    local mod = tryRequire(name)
    if mod then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('requireOne() loads module "'..name..'"')
      end
      return mod
    end
  end
  error('No suitable module found in "'..table.concat(arg, '", "')..'"')
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
  BASE_REQUIRE = BASE_REQUIRE,
  requireOne = requireOne,
  tryRequire = tryRequire,
  getRequired = getRequired,
  singleRequirer = singleRequirer,
  unload = unload,
  unloadAll = unloadAll
}