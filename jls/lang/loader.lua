--- Contains helper functions to load Lua modules.
-- The loader module is fully compatible with the Lua require function.
-- @module jls.lang.loader
-- @pragma nostrip

local logger = require('jls.lang.logger'):get(...)

--- Requires the specified Lua module.
-- @tparam string name the name of the module to load
-- @return the loaded module or nil if an error occured
-- @function tryRequire
local function tryRequire(name)
  local status, mod = pcall(require, name)
  if status then
    return mod
  end
  logger:fine('tryRequire() fails to load module "%s" due to "%s"', name, mod)
  return nil
end

--- Requires the specified Lua modules.
-- You could pass the module names as arguments with the optional try mode as first argument.
-- @tparam table names the list of the modules to load
-- @tparam[opt] boolean try true to return nil in place of raising an error
-- @return the loaded modules or nil values
-- @function requireList
local function requireList(names, try, ...)
  local modules = {}
  local t = type(names)
  if t ~= 'table' then
    if t == 'string' then
      names, try = {names, try, ...}, false
    elseif t == 'boolean' then
      names, try = try, names
      t = type(names)
      if t == 'string' then
        names = {names, ...}
      elseif t ~= 'table' then
        error('Invalid arguments')
      end
    end
  end
  for i, name in ipairs(names) do
    if try then
      modules[i] = tryRequire(name)
    else
      modules[i] = require(name)
    end
  end
  return table.unpack(modules, 1, #names)
end

--- Returns the specified Lua module if already loaded.
-- @tparam string name the name of the module to load
-- @return the already loaded module or nil if none
-- @function getRequired
local function getRequired(name)
  return package.loaded[name]
end

local NOT_LOADED = {}

-- Returns a funtion that will try to require the specified Lua module only once.
-- @tparam string name the name of the module to load
-- @treturn funtion a function that will return the specified module or nil if an error occured
-- @function singleRequirer
local function singleRequirer(name)
  local module = NOT_LOADED
  return function()
    if module == NOT_LOADED then
      module = tryRequire(name)
      logger:fine('singleRequirer() fails to load module "%s"', name)
    end
    return module
  end
end

-- Builds a function by requiring its dependencies on first call.
-- @tparam function providerFn A function which will be called only once with the loaded modules
-- @treturn funtion the function returned by the providerFn parameter
-- @function lazyFunction
local function lazyFunction(providerFn, ...)
  local fn, rargs
  rargs = table.pack(...)
  return function(...)
    if not fn then
      fn = providerFn(requireList(table.unpack(rargs, 1, rargs.n)))
      rargs = nil
    end
    return fn(...)
  end
end

--- Adds a method by requiring its dependencies on first call.
-- Lazy method allows cycling dependencies between modules.
-- The module method will be replaced on the first call, caching the boot method works but is not recommended.
-- @tparam table mod the module owning the method
-- @tparam string name the method name
-- @tparam function providerFn A function which will be called only once with the loaded modules
-- @param[opt] ... a list of module names to require and pass to the provider function
-- @treturn funtion the function returned by the providerFn parameter
-- @function lazyMethod
local function lazyMethod(mod, name, providerFn, ...)
  if type(mod) ~= 'table' or type(name) ~= 'string' or type(providerFn) ~= 'function' then
    error('invalid arguments')
  end
  local fn, rargs
  rargs = table.pack(...)
  mod[name] = function(...)
    if not fn then
      fn = providerFn(requireList(table.unpack(rargs, 1, rargs.n)))
      mod[name] = fn
      -- cleanup
      rargs, mod, name, providerFn = nil, nil, nil, nil
    end
    return fn(...)
  end
end

local BASE_REQUIRE = require

-- The JLS_REQUIRES environment variable enables to pre load native/non jls modules
-- that can be used in case of multiple implementations
local jlsRequires = os.getenv('JLS_REQUIRES')
if jlsRequires and jlsRequires ~= '' then
  local jlsObviates = {}
  local isDebugLoggable = logger:isLoggable(logger.FINE)
  local function restrictedRequire(name)
    if isDebugLoggable then
      logger:fine('require("%s")', name)
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
    logger:fine('loads modules from JLS_REQUIRES: "%s"', jlsRequires)
  end
  for name in string.gmatch(jlsRequires, '[^,%s]+') do
    local nname = string.match(name, '!(.+)$')
    if nname then
      jlsObviates[nname] = true
      if isDebugLoggable then
        logger:fine('obviated module "%s"', nname)
      end
    else
      if isDebugLoggable then
        logger:fine('preload required module "%s"', name)
      end
      local mod = tryRequire(name)
      if not mod then
        logger:warn('Fail to load required module "%s"', name)
      end
    end
  end
  if next(jlsObviates) ~= nil then
    require = restrictedRequire
  end
  package.loaded[reentrancyKey] = nil
  jlsRequires = nil
end

--[[--
Requires one of the specified Lua modules.
The order is: the first already loaded module then
the first module whose name ends by an already loaded module.
If no module could be loaded then an error is raised.
If there is only one module then the base module shall be the same.
@tparam string ... the ordered names of the module eligible to load
@return the loaded module
@function requireOne
@usage
return require('jls.lang.loader').requireOne('jls.io.fs-luv', 'jls.io.fs-lfs')
]]
local function requireOne(...)
  local args = {...}
  if #args == 1 then
    local name = args[1]
    local bname = string.match(name, '^(.+)%-[^%-]*$')
    if not bname then
      error('Invalid module name "'..tostring(name)..'"')
    end
    local mod = require(bname)
    if mod ~= package.loaded[name] then
      error('Bad module loaded, "'..bname..'" is not "'..name..'"')
    end
    return mod
  end
  -- look for the first already loaded module
  for _, name in ipairs(args) do
    local mod = package.loaded[name]
    if mod then
      logger:fine('requireOne() found loaded module "%s"', name)
      return mod
    end
  end
  -- try to load the first module whose name ends by an already loaded module
  local names = {}
  for _, name in ipairs(args) do
    local sname = string.match(name, '%-([^%-]+)$')
    if sname and package.loaded[sname] then
      local mod = tryRequire(name)
      if mod then
        logger:fine('requireOne() loads module "%s" because "%s" is already loaded', name, sname)
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
      logger:fine('requireOne() loads module "%s"', name)
      return mod
    end
  end
  error('No suitable module found in "'..table.concat(args, '", "')..'"')
end

--- Requires the Lua object specified by its path.
-- If the full path cannot be required then each part of the path, separated by a dot '.',
-- is required and the remaining part of the path are accessed in the module table.
-- @tparam string path the pathname of the module to load
-- @tparam[opt] boolean try true to return nil in place of raising an error
-- @return the loaded module
-- @function requireByPath
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

-- Unloads the specified Lua module.
-- The module is removed from the loaded modules and will be loaded again on a require.
-- This is not the opposite of the require and bad things could happen.
-- @tparam string name the name of the module to unload
-- @function unload
local function unload(name)
  logger:fine('unload("%s")', name)
  package.loaded[name] = nil
end

--[[ Unloads all the specified Lua modules.
@tparam string pattern the pattern of the module names to unload
@function unloadAll
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

--- Loads a module using a specific path.
-- @tparam string name the name of the module to load
-- @tparam[opt] string path the path of the module to load, could be `package.path`
-- @tparam[opt] boolean try true to return nil in place of raising an error
-- @tparam[opt] boolean asRequire true to be compatible with require by using `package.loaded`
-- @return the loaded module or nil if an error occured
-- @function load
local function load(name, path, try, asRequire)
  if asRequire then
    local m = package.loaded[name]
    if m ~= nil then
      return m
    end
  end
  local filename
  if path and string.find(path, '%?') then
    filename = package.searchpath(name, path)
  else
    local directorySeparator = string.sub(package.config, 1, 1)
    filename = string.gsub(name, '%.', directorySeparator)..'.lua'
    if path then
      filename = path..directorySeparator..filename
    end
  end
  local fn, err = loadfile(filename, 't')
  if fn then
    local status, modOrErr = pcall(fn, name, filename)
    if status then
      if asRequire then
        if package.loaded[name] ~= nil then
          modOrErr = package.loaded[name]
        else
          if modOrErr == nil then
            modOrErr = true
          end
          package.loaded[name] = modOrErr
        end
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

--- Loads a resource.
-- A resource is data accessible in the Lua path or in the table `package.resource`.
-- If no resource is found, or if there is any error loading the resource, then an error is raised.
-- If `package.resource[name]` returns a function, then it is called to get the resource with the name as parameter.
-- @tparam string name the name of the resource to load using slash as separator, for example "`a/b.json`"
-- @tparam[opt] boolean try true to return nil in place of raising an error
-- @treturn string the resource
-- @function loadResource
local function loadResource(name, try)
  logger:fine('loadResource("%s")', name)
  if type(package.resource) == 'table' then
    local r = package.resource[name]
    if type(r) == 'function' then
      r = r(name)
    end
    if type(r) == 'string' then
      return r
    end
  end
  local n, e = string.match(name, '^/?(.+)(%.[^/%.]*)$')
  if not n then
    n, e = name, ''
  end
  local ep = string.gsub(package.path, '%.lua', e)
  local p, err = package.searchpath(n, ep, '/')
  if p then
    local fd
    fd, err = io.open(p, 'rb')
    if fd then
      local r = fd:read('*a')
      fd:close()
      return r
    end
  end
  if try then
    return nil, err
  end
  error(err)
end

local function findPath(name, path, sep)
  path = path or package.path
  sep = sep or string.sub(package.config, 3, 3)
  local i, j
  i = 0
  while true do
    i, j = string.find(path, name, i + 1, true)
    if i then
      if (i == 1 or string.sub(path, i - 1, i - 1) == sep) and (j == #path or string.sub(path, j + 1, j + 1) == sep) then
        return i, j
      end
    else
      break
    end
  end
end

local function addLuaPath(name)
  if not findPath(name) then
    package.path = package.path..';'..name
    return true
  end
  return false
end

local function removeLuaPath(name)
  local i, j = findPath(name)
  if i then
    if i > 2 then
      package.path = string.sub(package.path, 1, i - 2)..string.sub(package.path, j + 1)
    else
      package.path = string.sub(package.path, j + 2)
    end
    return true
  end
  return false
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
  requireList = requireList,
  lazyFunction = lazyFunction,
  lazyMethod = lazyMethod,
  requireByPath = requireByPath,
  unload = unload,
  unloadAll = unloadAll,
  load = load,
  loadResource = loadResource,
  findPath = findPath,
  addLuaPath = addLuaPath,
  removeLuaPath = removeLuaPath,
  resetLuaPath = resetLuaPath,
}