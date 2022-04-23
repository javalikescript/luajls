local logger = require('jls.lang.logger')
local loader = require('jls.lang.loader')
local system = require('jls.lang.system')
local StringBuffer = require('jls.lang.StringBuffer')
local Path = require('jls.io.Path')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local tables = require('jls.util.tables')
local Map = require('jls.util.Map')
local List = require('jls.util.List')

local function getModuleName(d, f)
  local path = Path.relativizePath(d, f)
  local name = string.gsub(Path.extractBaseName(path), '[/\\]+', '.')
  return name, path
end

local function isDashModule(name)
  return string.find(name, '-[^.]*$')
end

local function uniq(list)
  local ul = {}
  for i, v in ipairs(list) do
    for j = i + 1, #list do
      if list[j] == v then
        v = nil
        break
      end
    end
    if v then
      table.insert(ul, v)
    end
  end
  return ul
end

local function getRequiredFromFile(filename, name, requireOne)
  local names = {}
  local fn = assert(loadfile(filename, 't'))
  local baseRequireOne = loader.requireOne
  local baseRequire = require
  local function namedRequire(moduleName)
    table.insert(names, moduleName)
    require = baseRequire
    local status, module = pcall(require, moduleName)
    require = namedRequire
    if status then
      return module
    end
    error(module)
  end
  local function requireAll(...)
    local args = {...}
    if #args == 1 then
      return require(args[1])
    end
    for _, name in ipairs(args) do
      pcall(require, name)
    end
    return baseRequireOne(...)
  end
  if not requireOne then
    loader.requireOne = requireAll
  end
  require = namedRequire
  local status, err = pcall(fn, name, filename)
  require = baseRequire
  loader.requireOne = baseRequireOne
  if not status then
    return nil, err
  end
  return names
end

local function getRequired(name, path, requireOne)
  local filename = assert(package.searchpath(name, path))
  local names = getRequiredFromFile(filename, name, requireOne)
  return names, filename
end

local function getOrderedNames(modules)
  local names = {}
  local moduleMap = Map.assign({}, modules)
  while next(moduleMap) ~= nil do
    local required = {}
    for name, module in pairs(moduleMap) do
      if #module.requires == 0 then
        table.insert(required, name)
      end
    end
    if #required == 0 then
      -- TODO find the cyclic dependencies
      for name, module in Map.spairs(moduleMap) do
        print(name, table.concat(module.requires, ', '))
      end
      error('Cannot compute dependencies')
    end
    for _, name in ipairs(required) do
      local module = moduleMap[name]
      if module then
        moduleMap[name] = nil
      else
        error('Cannot find module '..name)
      end
    end
    for _, module in pairs(moduleMap) do
      for _, name in ipairs(required) do
        List.removeFirst(module.requires, name)
      end
    end
    table.sort(required)
    --print('required', table.concat(required, ', '))
    List.concat(names, required)
  end
  return names
end


local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  emptyPath = 'dir',
  aliases = {
    h = 'help',
    ll = 'loglevel',
  },
  schema = {
    title = 'Lua package utility',
    description = 'Bundles several Lua modules into a single file',
    type = 'object',
    additionalProperties = false,
    properties = {
      help = {
        title = 'Show the help',
        type = 'boolean',
        default = false
      },
      dir = {
        title = 'The directory containing the modules',
        type = 'string'
      },
      name = {
        title = 'The module to require',
        type = 'string'
      },
      includeDir = {
        title = 'Includes the directory in the module name',
        type = 'boolean',
        default = true
      },
      addPath = {
        title = 'Includes the directory in the package path',
        type = 'boolean',
        default = true
      },
      binary = {
        title = 'Uses binary chunks',
        type = 'boolean',
        default = false
      },
      strip = {
        title = 'Strips binary chunks or Lua code',
        type = 'boolean',
        default = false
      },
      action = {
        title = 'Modules processing',
        type = 'string',
        default = 'preload',
        enum = {'preload', 'require', 'inline', 'dependencies', 'list', 'sort', 'none'},
      },
      dependency = {
        title = 'Dependencies processing',
        type = 'string',
        default = 'require',
        enum = {'require', 'pattern'},
      },
      requireOne = {
        title = 'Selects only one module',
        type = 'boolean',
        default = false
      },
      noDash = {
        title = 'Filters module with dash',
        type = 'boolean',
        default = false
      },
      file = {
        title = 'The file to generate',
        type = 'string'
      },
      module = {
        title = 'The main module to require',
        type = 'string'
      },
      overwrite = {
        title = 'Replace existing file',
        type = 'boolean',
        default = false
      },
      loglevel = {
        title = 'The log level',
        type = 'string',
        default = 'warn',
        enum = {'error', 'warn', 'info', 'config', 'fine', 'finer', 'finest', 'debug', 'all'},
      },
    }
  }
})

logger:setLevel(options.loglevel)

local eol = system.lineSeparator
local out = system.output

if options.file then
  local f = File:new(options.file)
  if f:exists() and not options.overwrite then
    print('The file exists')
    os.exit(1)
  end
  out = FileDescriptor.openSync(options.file, 'w')
  if f:getExtension() == 'bin' then
    options.binary = true
  end
elseif options.name then
  local required, filename = getRequired(options.name, package.path, options.requireOne)
  -- todo recurse
end

if options.binary then
  local wo = out
  out = {
    sb = StringBuffer:new(),
    writeSync = function(self, data)
      self.sb:append(data)
    end,
    closeSync = function(self)
      local fn = load(self.sb:toString(), nil, 't')
      local bin = string.dump(fn, options.strip)
      wo:writeSync(bin)
      wo:closeSync()
      print('The binary chunk can be loaded using:')
      print('loadfile('..string.format('%q', options.file or 'out.bin')..', nil, "b")()')
    end
  }
end

local modules = {}
local base

if options.dir then
  local dir = File:new(options.dir)
  base = dir
  if options.includedir then
    base = dir:getParentFile()
  end
  if options.addPath then
    package.path = package.path..';'..File:new(base, '?.lua'):getPathName()
  end
  dir:forEachFile(function(_, file)
    if file:getExtension() == 'lua' then
      local name, path = getModuleName(base, file)
      modules[name] = {
        content = file:readAll(), -- we may want to fix end of line in content
        file = file
      }
    end
  end, true)
end

-- compute dependencies
if options.dependency == 'pattern' then
  for moduleName, module in pairs(modules) do
    local set = {}
    for name in string.gmatch(module.content, 'require%(%s*["\']([%a%d_%.%-]+)["\']%s*%)') do
      if name ~= moduleName then
        set[name] = true
      end
    end
    module.allRequires = Map.keys(set)
  end
elseif options.dependency == 'require' then
  for name, module in pairs(modules) do
    --print('compute dependencies for '..name..' with path '..path)
    local names, err = getRequiredFromFile(module.file:getPathName(), name, options.requireOne)
    if names then
      module.allRequires = uniq(names)
    else
      print('Unable to get required for "'..name..'"')
      module.allRequires = {}
    end
  end
end

-- filter required modules
local allRequired = {}
for moduleName, module in pairs(modules) do
  local requires = {}
  local addRequired = not isDashModule(moduleName)
  for _, name in ipairs(module.allRequires) do
    if addRequired then
      allRequired[name] = true
    end
    if modules[name] then
      table.insert(requires, name)
    else
      --print('drop require', name, 'for', moduleName)
    end
  end
  module.requires = requires
end

-- filter dash modules not required
if options.requireOne then
  for name in pairs(modules) do
    if isDashModule(name) and not allRequired[name] then
      modules[name] = nil
    end
  end
end

if options.noDash then
  for name in pairs(modules) do
    if isDashModule(name) then
      modules[name] = nil
    end
  end
end

if options.action == 'list' then
  for name in Map.spairs(modules) do
    out:writeSync('require("'..name..'")'..eol)
  end
elseif options.action == 'dependencies' then
  for name, module in Map.spairs(modules) do
    print(name, table.concat(module.requires, ', '))
  end
elseif options.action == 'preload' then
  for name, module in Map.spairs(modules) do
    out:writeSync('package.preload["'..name..'"] = function()'..eol)
    --out:writeSync('package.preload["'..name..'"] = nil'..eol)
    if options.strip then
      local parser = require('parser')
      --parser()
    else
      out:writeSync(module.content)
    end
    out:writeSync(eol..'end'..eol)
  end
elseif options.action == 'sort' then
  local names = getOrderedNames(modules)
  for _, name in ipairs(names) do
    local module = modules[name]
    out:writeSync('require("'..name..'") -- '..table.concat(module.allRequires, ', ')..eol)
  end
elseif options.action == 'require' then
  local names = getOrderedNames(modules)
  out:writeSync('local PRELOAD_ENV = _ENV'..eol)
  if options.module and modules[options.module] then
    out:writeSync('local PRELOAD_PACKAGES = {}'..eol)
    for _, name in ipairs(names) do
      out:writeSync('PRELOAD_PACKAGES["'..name..'"] = package.loaded["'..name..'"]'..eol)
    end
  end
  for _, name in ipairs(names) do
    local module = modules[name]
    out:writeSync('_ENV = PRELOAD_ENV'..eol)
    out:writeSync('package.loaded["'..name..'"] = (function(...)'..eol)
    out:writeSync(module.content)
    out:writeSync(eol..'end)("'..name..'")'..eol..eol)
  end
  if options.module and modules[options.module] then
    local vname = string.gsub(options.module, '[.]', '_')
    out:writeSync('local '..vname..' = require("'..options.module..'")'..eol)
    for _, name in ipairs(names) do
      out:writeSync('package.loaded["'..name..'"] = PRELOAD_PACKAGES["'..name..'"]'..eol)
    end
    out:writeSync('return '..vname..eol)
  end
end

if out ~= system.output then
  out:closeSync()
end
