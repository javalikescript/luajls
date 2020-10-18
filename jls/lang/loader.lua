--- This module contains helper functions to load Lua modules.
-- @module jls.lang.loader

local logger = require('jls.lang.logger')

--- Requires the specified Lua module.
-- @tparam string name the name of the module to load
-- @return the loaded module or nil if an error occured
local function tryRequire(name)
  local status, mod = pcall(require, name)
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

--- Requires the Lua object specified by its path.
-- @tparam string path the pathname of the module to load
-- @tparam[opt] boolean try true to return nil in place of raising an error
-- @return the loaded module
local function requireByPath(path, try)
  local status, modOrErr = pcall(require, path)
  if status then
    return modOrErr
  end
  local names = {}
  local mod
  while true do
    table.insert(names, 1, (string.gsub(path, '^.*%.', '', 1)))
    path = string.match(path, '^(.+)%.[^%.]+$')
    if not path then
      break
    end
    status, mod = pcall(require, path)
    if status then
      for _, name in ipairs(names) do
        if type(mod) == 'table' then
          mod = mod[name]
        else
          break
        end
      end
      if mod then
        return mod
      end
      break
    end
  end
  if try then
    return nil
  end
  error(modOrErr)
end

--- Unloads the specified Lua module.
-- The module is removed from the loaded modules and will be loaded again on a require.
-- This is not the opposite of the require and bad things could happen.
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

-- Loads a module using a specific path.
-- @tparam string name the name of the module to load
local function load(name, path, try, asRequire)
  if asRequire then
    local m = package.loaded[name]
    if m then
      return m
    end
  end
  local directorySeparator = string.sub(package.config, 1, 1)
  local fullname = name
  if path then
    fullname = path..directorySeparator..name
  end
  local filename = string.gsub(fullname, '%.', directorySeparator)..'.lua'
  local fn, err = loadfile(filename, 't')
  if fn then
    local status, modOrErr = pcall(fn)
    if status and modOrErr ~= nil then
      if asRequire then
        package.loaded[name] = modOrErr
      end
      return modOrErr
    end
    err = modOrErr
  end
  if try then
    return nil, err
  end
  error(err)
end

local function appendLuaPath(name)
  if not string.find(package.path, name) then
    package.path = package.path..';'..name
  end
end

local BASE_LUA_PATH = package.path

local function resetLuaPath()
  package.path = BASE_LUA_PATH
end


return {
  getBaseRequire = function()
    return BASE_REQUIRE
  end,
  getBaseLuaPath = function()
    return BASE_LUA_PATH
  end,
  requireOne = requireOne,
  tryRequire = tryRequire,
  getRequired = getRequired,
  singleRequirer = singleRequirer,
  requireByPath = requireByPath,
  unload = unload,
  unloadAll = unloadAll,
  load = load,
  appendLuaPath = appendLuaPath,
  resetLuaPath = resetLuaPath,
}