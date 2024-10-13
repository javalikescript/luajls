--[[--
Provides class creation with inheritance and constructor.

This module provides helper functions to create and work with classes.
A class can implement prototype methods shared among all its instances.
A class can implement an initialize method that will be called for new instances.
A class can inherit from another class, prototype methods are inherited by the subclasses.

@module jls.lang.class
@pragma nostrip

@usage
local class = require('jls.lang.class')
local Person = class.create(function(person)
  function person:initialize(name)
    self.name = name
  end
  function person:getName()
    return self.name
  end
end)
local luke = Person:new('Luke')

local User = class.create(Person, function(user, super)
  function user:initialize(name, registrationYear)
    super.initialize(self, name)
    self.registrationYear = registrationYear
  end
end)
local dave = User:new('Dave', 2012)
]]

-- see https://en.wikipedia.org/wiki/Class_(computer_programming)
-- and https://en.wikipedia.org/wiki/Naming_convention_(programming)

local function emptyFunction(...) end

local function notImplementedFunction()
  error('This function is not implemented')
end

local function changeClass(instance, class)
  local mt = getmetatable(instance)
  setmetatable(instance, class.metatable)
  return mt
end

local function makeInstance(class, instance)
  if instance == nil then
    instance = {}
  end
  setmetatable(instance, class.metatable)
  return instance
end

--[[--
Returns the class of the specified instance.
@param instance The instance to get the class from
@return The class of the specified class or nil if there is no such class
@function getClass
@usage
local Vehicle = require('jls.lang.class').create()
local car = Vehicle:new()
car:getClass() -- Returns Vehicle
]]
local function getClass(instance)
  if type(instance) == 'table' then
    local mt = getmetatable(instance)
    if mt and mt.class then
      -- we may check that the class prototype is the same than the instance __index metatable field
      return mt.class
    end
  end
end

--[[--
Returns a copy of the specified instance.
This method performs a shallow copy, field-by-field copy, not a deep copy.
@param instance The instance to clone
@return A copy of the specified instance, or nil if the instance has no class
@function cloneInstance
@usage
local Vehicle = require('jls.lang.class').create()
local car = Vehicle:new()
local carCopy = car:clone()
]]
local function cloneInstance(instance)
  local class = getClass(instance)
  if class then
    local newInstance = makeInstance(class)
    -- TODO use serialization
    for k, v in pairs(instance) do
      newInstance[k] = v
    end
    return newInstance
  end
end

--local function toString(instance)
--  return string.format('%s: %p', getName(getClass(instance)) or 'table', instance)
--end

--[[--
Creates a new instance of the specified class.
@param class The class to instantiate
@param ... The parameters passed to the initialize method
@return A new instance
@function newInstance
@usage
local Vehicle = require('jls.lang.class').create(function(vehicle)
  function vehicle:initialize(color)
    self.color = color
  end
  function vehicle:getColor()
    return self.color
  end
end)
local car = Vehicle:new('blue')
car:getColor() -- Returns 'blue'
]]
local function newInstance(class, ...)
  local instance = makeInstance(class)
  instance:initialize(...)
  return instance
end

--[[--
Returns the name of the specified class.
This is a default and best effort implementation, edge case should override it at class level.
@param class The class to look for
@treturn string The class name or nil if the class is not found in `package.loaded`
@function getName
]]
local function getName(class)
  -- some class are loaded twice under different names
  for name, c in pairs(package.loaded) do
    if c == class and not string.find(name, '-', 1, true) then
      return name
    end
  end
  for name, m in pairs(package.loaded) do
    if m == class and string.find(name, '-', 1, true) then
      return name
    end
    if type(m) == 'table' then
      for field, c in pairs(m) do
        if c == class then
          return name..'$'..field
        end
      end
    end
  end
  return nil
end

--[[--
Returns the class for the specified name.
A class defined in a module field uses a dollar sign `$` to separate the package name and the field name.
@tparam string name The class name to look for
@return The class or nil if the class cannot be found
@function byName
]]
local function byName(name)
  local modname, path = string.match(name, '^([^%$]+)%$(.+)$')
  if modname then
    local m = require(modname)
    for field in string.gmatch(path, '[^%.]*') do
      m = type(m) == 'table' and m[field]
      if not m then
        break
      end
    end
    if m then
      return m
    end
    error('class '..name..' not found')
  end
  return require(name)
end

--[[--
Indicates whether or not the specified subclass is the same or a sub class of the specified class.
@param class The class to check with
@param subclass The class to be checked
@return true if the subclass is the same or a sub class of the class, false otherwise
@function isAssignableFrom
@usage
local class = require('jls.lang.class')
local Vehicle = class.create()
local Bus = class.create(Vehicle)
Vehicle:isAssignableFrom(Bus) -- Returns true
]]
local function isAssignableFrom(class, subclass)
  while type(subclass) == 'table' do
    if subclass == class then
      return true
    end
    subclass = subclass.super
  end
  return false
end

--[[--
Returns true if the specified value is a class.
@param value The class to check
@return true if the specified value is a class, false otherwise
@function isClass
]]
local function isClass(value)
  if type(value) == 'table' then
    local mt = getmetatable(value)
    if mt and type(value.new) == 'function' and value.prototype then
      return true
    end
  end
  return false
end

--[[--
Indicates whether or not the specified instance is an instance of the specified class.
@param class The class to check with
@param instance The instance to be checked
@return true if the instance is an instance of the class, false otherwise
@function isInstance
@usage
local Vehicle = require('jls.lang.class').create()
local car = Vehicle:new()
Vehicle:isInstance(car) -- Returns true
]]
local function isInstance(class, instance)
  return isAssignableFrom(class, getClass(instance))
end

--[[--
Returns an instance of the specified class.
@param class The class from which an instance is expected
@param ... The instance to be checked or the creation parameters
@return An instance
@function asInstance
]]
local function asInstance(class, ...)
  local value = ...
  if isAssignableFrom(class, getClass(value)) then
    return value
  end
  local instance = makeInstance(class)
  instance:initialize(...)
  return instance
end

-- The __len metamethod is available since Lua 5.2
local MetatableKeys = {
  __close = 'cease',
  __eq = 'equals',
  __gc = 'finalize',
  __len = 'length',
  __pairs = 'pairs',
  __tostring = 'toString'
}

local ClassIndex = {
  new = newInstance,
  -- Could be named getClassName to avoid collision
  getName = getName,
  isAssignableFrom = isAssignableFrom,
  --as = asInstance,
  isInstance = isInstance
}

local ClassMetaTable = {
  __call = newInstance,
  __index = ClassIndex
}

local function decorate(metatable, prototype)
  for key, name in pairs(MetatableKeys) do
    local value = prototype[name]
    if type(value) == 'function' then
      metatable[key] = value
    end
  end
end

--[[--
Implements the specified class by setting its prototype and class methods.
The following methods are automatically set in the metatable:
`cease` as `__close`, `equals` as `__eq`, `finalize` as `__gc`, `length` as `__len`, `pairs` as `__pairs`, `toString` as `__tostring`.
The metatable methods cannot be redefined.
@param class The class to implement
@tparam[opt] function defineInstanceFn An optional function that will be called with the class prototype to implement
@tparam[opt] function defineClassFn An optional function that will be called with the class
@return The class
@function define
@usage
local class = require('jls.lang.class')
local Person = class.create()
class.define(function(person)
  function person:initialize(name)
    self.name = name
  end
  function person:getName()
    return self.name
  end
end, function(Person)
  function Person:getDefaultHeight()
    return 1.75
  end
end)
local User = class.create(Person)
class.define(function(user, super)
  function user:initialize(name, registrationYear)
    super.initialize(self, name)
    self.registrationYear = registrationYear
  end
end)
local john = User:new('john', 2011)
john:getName() -- Returns 'john'
User:getDefaultHeight() -- Returns 1.75
]]
local function defineClass(class, defineInstanceFn, defineClassFn)
  local super = class.super
  if super then
    decorate(class.metatable, super.prototype)
  end
  if type(defineInstanceFn) == 'function' then
    -- prototype, superprototype, class, superclass
    defineInstanceFn(class.prototype, super and super.prototype, class, super)
    -- decorate the class with well known methods
    decorate(class.metatable, class.prototype)
  end
  if type(defineClassFn) == 'function' then
    -- class, superclass
    defineClassFn(class, super)
  end
  return class
end

--[[--
Modifies the specified instance.
This method allows to override class methods for a specific instance.
@param instance The instance to modify
@tparam function fn The function that will be called with the instance and its prototype
@return The modified instance
@function modifyInstance
]]
local function modifyInstance(instance, fn)
  local class = getClass(instance)
  if not class then
    error('No class found for the specified instance')
  end
  fn(instance, class.prototype)
end

--[[--
Returns a new class inheriting from specified base class.
The class is implemented using the specified functions by calling @{define}.
The class has a @{newInstance|new} method to create new instance and a @{isInstance} method to check compatibility.
@param[opt] super An optional base class to inherit from, could be the class name as a string
@tparam[opt] function defineInstanceFn An optional function that will be called with the class prototype
@tparam[optchain] function defineClassFn An optional function that will be called with the class
@return A new class
@function create
@usage
local Vehicle = class.create()
local Car = class.create(Vehicle)
local car = Car:new()
Vehicle:isInstance(car) -- Returns true
]]
local function createClass(super, defineInstanceFn, defineClassFn)
  if type(super) == 'function' then
    defineClassFn = defineInstanceFn
    defineInstanceFn = super
    super = nil
  elseif type(super) == 'string' then
    super = require(super)
  end
  -- create a prototype with its own default methods
  -- own methods can be overriden but will not be inherited
  local prototype = {
    getClass = getClass
  }
  -- create the class table with default fields
  local class = {
    metatable = {
      __index = prototype
    },
    prototype = prototype,
    super = super
  }
  -- let the instance metatable reference the class it belongs to
  class.metatable.class = class
  if super then
    -- create a super class metatable if necessary
    if not super.classMetaTable then
      super.classMetaTable = {
        __index = super
      }
    end
    -- let the new class inherit from the base class
    setmetatable(class, super.classMetaTable)
    -- check and restore class fields which are not inherited
    for k, v in pairs(ClassIndex) do
      if super[k] ~= v then
        class[k] = v
      end
    end
    -- let the new prototype inherit from the base class prototype
    setmetatable(prototype, super.metatable)
  else
    -- let the new class inherit from the root class
    setmetatable(class, ClassMetaTable)
    -- let the prototype have an initialize function
    prototype.initialize = emptyFunction
    -- let the prototype have a clone function
    prototype.clone = cloneInstance
  end
  return defineClass(class, defineInstanceFn, defineClassFn)
end

return {
  changeClass = changeClass,
  cloneInstance = cloneInstance,
  create = createClass,
  define = defineClass,
  emptyFunction = emptyFunction,
  getClass = getClass,
  isInstance = isInstance,
  makeInstance = makeInstance,
  newInstance = newInstance,
  modifyInstance = modifyInstance,
  asInstance = asInstance,
  getName = getName,
  byName = byName,
  isClass = isClass,
  notImplementedFunction = notImplementedFunction
}