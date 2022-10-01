--- Provide table helper functions.
-- @module jls.util.tables

local StringBuffer = require('jls.lang.StringBuffer')
local List = require('jls.util.List')
local Map = require('jls.util.Map')

local tables = {}

-- Returns a table corresponding to the specifed text.
-- @tparam string text The string to parse.
-- @treturn table a table corresponding to the specifed text.
function tables.parse(text)
  -- TODO parse the text 
  local f, err = load('return '..text, nil, 't')
  if f then
    return f()
  end
  return nil, err
end

-- Returns a string representing the specifed table value.
-- @tparam table value The table to convert.
-- @tparam[opt] string space The indent value to use.
-- @treturn string a string representing the specifed table value.
function tables.stringify(value, space, lenient)
  local sb = StringBuffer:new()
  local indent = ''
  if type(space) == 'number' and space > 1 then
    indent = string.rep(' ', space)
  elseif type(space) == 'string' then
    indent = space
  end
  local newline, equal
  if indent == '' then
    newline = ''
    equal = '='
  else
    newline = '\n'
    equal = ' = '
  end
  local stack = {}
  local function stringify(value, prefix)
    local valueType = type(value)
    if valueType == 'table' then
      if stack[value] then
        if lenient then
          sb:append('"_0_CYCLE"')
          return
        end
        --print('buffer:', sb:toString())
        error('cycle detected')
      end
      stack[value] = true
      local subPrefix = prefix..indent
      sb:append('{', newline)
      if List.isList(value) then
        -- it looks like a list
        for _, v in ipairs(value) do
          sb:append(subPrefix)
          stringify(v, subPrefix)
          sb:append(',', newline)
        end
      else
        -- it looks like a map
        -- The order in which the indices are enumerated is not specified
        for k, v in Map.spairs(value) do
          sb:append(subPrefix)
          if type(k) == 'string' and List.isName(k) then
            sb:append(k)
          else
            sb:append('[')
            stringify(k, subPrefix)
            sb:append(']')
          end
          sb:append(equal)
          stringify(v, subPrefix)
          sb:append(',', newline)
        end
      end
      sb:append(prefix, '}')
      stack[value] = nil
    elseif valueType == 'string' then
      sb:append(string.format('%q', value))
    elseif valueType == 'number' or valueType == 'boolean' then
      sb:append(tostring(value))
    else
      if lenient then
        sb:append(string.format('%q', valueType))
      else
        error('Invalid type '..valueType)
      end
    end
  end
  stringify(value, '')
  return sb:toString()
end


-- Tree table / Deep table manipulation

function tables.shallowCopy(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = v
  end
  return c
end

function tables.deepCopy(t)
  local c = {}
  for k, v in pairs(t) do
    if type(v) == 'table' then
      v = tables.deepCopy(v)
    end
    c[k] = v
  end
  return c
end

function tables.deepEquals(a, b)
  for k, va in pairs(a) do
    local vb = b[k]
    if not vb then
      return false
    end
    local vat = type(va)
    local vbt = type(vb)
    if vat ~= vbt then
      return false
    end
    if vat == 'table' then
      if not tables.deepEquals(va, vb) then
        return false
      end
    elseif va ~= vb then
      return false
    end
  end
  for k, vb in pairs(b) do
    if not a[k] then
      return false
    end
  end
  return true
end

--- Copies the value from the source table into the target.
-- This is a deep copy, sub table are also merged.
-- @tparam table target the table to copy.
-- @tparam table source a modified table.
-- @tparam boolean keep true to indicate that existing target value should be kept, default is false.
-- @treturn table the target table.
function tables.merge(target, source, keep)
  for key, sourceValue in pairs(source) do
    local targetValue = target[key]
    if type(targetValue) == 'table' and type(sourceValue) == 'table' then
      tables.merge(targetValue, sourceValue, keep)
    elseif targetValue == nil or not keep then
      target[key] = sourceValue
    end
  end
  return target
end

function tables.forEach(t, fn)
  for key, value in pairs(t) do
    if type(value) == 'table' then
      tables.forEach(value, fn)
    else
      fn(key, value, t)
    end
  end
  return t
end

--- Returns a table containing the differences between the two specified tables.
-- The additions or modifications are availables, the same values are discarded
-- and the deleted values are listed in a specific table entry named "_deleted".
-- @tparam table oldTable a base table.
-- @tparam table newTable a modified table.
-- @treturn table the differences or nil if there is no such difference.
function tables.compare(oldTable, newTable)
  -- oldTable and newTable must be of type table
  local diff
  -- TODO we may want to detect renamed keys
  -- TODO we may want to detect moved list entries
  -- TODO we may want to compare long strings
  for key, newValue in pairs(newTable) do
    local oldValue = oldTable[key]
    local oldType = type(oldValue)
    local newType = type(newValue)
    local diffValue
    if oldType ~= newType then -- new type and value cannot be nil
      diffValue = newValue
    else
      if newType == 'table' then
        diffValue = tables.compare(oldValue, newValue)
      else
        if oldValue ~= newValue then
          diffValue = newValue
        end
      end
    end
    if diffValue ~= nil then
      if not diff then
        diff = {}
      end
      diff[key] = diffValue
    end
  end
  local deleted
  for key, oldValue in pairs(oldTable) do
    if newTable[key] == nil then
      if deleted then
        table.insert(deleted, key)
      else
        deleted = {key}
      end
    end
  end
  if deleted then
    if not diff then
      diff = {}
    end
    diff._deleted = deleted
  end
  return diff
end

--- Returns a table patched according to the specified differences.
-- @tparam table oldTable a base table.
-- @tparam table diff the differences to apply to the base table.
-- @treturn table the differences or nil if there is no such difference.
function tables.patch(oldTable, diff)
  local newTable = {}
  local deleted = {}
  if diff._deleted then
    for _, key in ipairs(diff._deleted) do
      deleted[key] = true
    end
  end
  for key, oldValue in pairs(oldTable) do
    if not deleted[key] then
      local newValue
      local oldType = type(oldValue)
      local diffValue = diff[key]
      if diffValue ~= nil then
        local diffType = type(diffValue)
        if oldType == diffType and oldType == 'table' then
          newValue = tables.patch(oldValue, diffValue)
        else
          newValue = diffValue
        end
      else
        newValue = oldValue
      end
      newTable[key] = newValue -- we may want to deep copy the value in case of table
    end
  end
  for key, diffValue in pairs(diff) do
    if oldTable[key] == nil and key ~= '_deleted' then
      newTable[key] = diffValue -- we may want to deep copy the value in case of table
    end
  end
  return newTable
end

local DEFAULT_PATH_SEPARATOR = '/'

local function getPathKey(path, separator)
  local key, remainingPath
  local sep = separator or DEFAULT_PATH_SEPARATOR
  local keyIndex = 1
  -- TODO correctly find protected separator
  local sepIndex = string.find(path, sep, keyIndex, true)
  if sepIndex == 1 then
    keyIndex = keyIndex + #sep
    sepIndex = string.find(path, sep, keyIndex, true)
  end
  if sepIndex then
    key = string.sub(path, keyIndex, sepIndex - 1)
    remainingPath = string.sub(path, sepIndex + #sep)
  elseif keyIndex > 1 then
    key = string.sub(path, keyIndex)
  else
    key = path
  end
  local ekey = string.match(key, '^%[(.*)%]$')
  if ekey then
    local skey = string.match(ekey, '^"(.*)"$')
    if skey then
      return skey, remainingPath
    end
    if ekey == 'true' or ekey == 'false' then
      return ekey == 'true', remainingPath
    end
    local n = tonumber(ekey)
    if n then
      return n, remainingPath
    end
  end
  -- accepts positive integer keys
  if string.find(key, '^[1-9][0-9]*$') then
    return tonumber(key), remainingPath
  end
  return key, remainingPath
end

--- Returns the value at the specified path in the specified table.
-- A path consists in table keys separated by slashes.
-- The key are considered as string, number or boolean. Table or userdata keys are not supported.
-- @tparam table t a table.
-- @tparam string path the path to look in the table.
-- @param defaultValue the default value to return if there is no value for the path.
-- @tparam[opt] string separator the path separator, default is /.
-- @return the value
function tables.getPath(t, path, defaultValue, separator)
  local key, remainingPath = getPathKey(path, separator)
  local value
  if key == '' then
    value = t
  else
    value = t[key]
  end
  if remainingPath then
    if type(value) == 'table' then
      return tables.getPath(value, remainingPath, defaultValue, separator)
    end
    value = nil
  end
  if value == nil then
    return defaultValue, t, key
  end
  return value, t, key
end

--- Sets the specified value at the specified path in the specified table.
-- @tparam table t a table.
-- @tparam string path the path to set in the table.
-- @param value the value to set.
-- @tparam[opt] string separator the path separator.
-- @return the previous value.
function tables.setPath(t, path, value, separator)
  local key, remainingPath = getPathKey(path, separator)
  local v = t[key]
  if remainingPath and remainingPath ~= '' then
    if type(v) ~= 'table' then
      if value == nil then
        return
      end
      -- if the entry does not exist or is not a table then create an intermediary table
      v = {}
      t[key] = v
    end
    return tables.setPath(v, remainingPath, value, separator)
  end
  t[key] = value
  return v, t, key
end

function tables.mergePath(t, path, value, keep, separator)
  local key, remainingPath = getPathKey(path, separator)
  local v = t[key]
  if remainingPath and remainingPath ~= '' then
    if type(v) ~= 'table' then
      -- if the entry does not exist or is not a table then create an intermediary table
      v = {}
      t[key] = v
    end
    return tables.mergePath(v, remainingPath, value, keep, separator)
  end
  if type(v) ~= 'table' then
    t[key] = value
    return value
  end
  tables.merge(v, value, keep)
  return v
end

--- Removes the value at the specified path in the specified table.
-- @tparam table t a table.
-- @tparam string path the path to remove in the table.
-- @tparam[opt] string separator the path separator.
-- @return the removed value.
function tables.removePath(t, path, separator)
  local key, remainingPath = getPathKey(path, separator)
  local value = t[key]
  if remainingPath then
    if type(value) == 'table' then
      return tables.removePath(value, remainingPath, separator)
    end
    return nil
  end
  if type(key) == 'number' then
    table.remove(t, key)
  else
    t[key] = nil
  end
  return value, t, key
end

local function keyToPath(key, separator)
  if type(key) == 'string' then
    if string.find(key, '^[1-9][0-9]*$')
      or string.find(key, '^%[.*%]$')
      or string.find(key, separator, 1, true)
      or key == 'false' or key == 'true'
    then
      return '["'..key..'"]'
    end
    return key
  elseif math.type(key) == 'integer' and key > 0 then
    return tostring(key)
  elseif type(key) == 'boolean' then
    return '['..tostring(key)..']'
  end
  error('Invalid key type '..type(key))
end

local function mapValuesByPath(t, paths, path, separator)
  for k, v in pairs(t) do
    local p = path..separator..keyToPath(k, separator)
    if type(v) == 'table' then
      mapValuesByPath(v, paths, p, separator)
    else
      paths[p] = v
    end
  end
end

function tables.mapValuesByPath(t, path, separator)
  local paths = {}
  mapValuesByPath(t, paths, path or '', separator or DEFAULT_PATH_SEPARATOR)
  return paths
end

function tables.setByPath(baseTable, mergeTable)
  local valuesByPath = mapValuesByPath(mergeTable, {}, '')
  for path, value in pairs(valuesByPath) do
    tables.setPath(baseTable, path, value)
  end
  return baseTable
end

local EMPTY_TABLE = {}

local function mergeValuesByPath(oldTable, newTable, paths, path, separator)
  for k, oldValue in pairs(oldTable) do
    local p = path..separator..tostring(k)
    local oldType = type(oldValue)
    local newValue = newTable[k]
    if newValue == nil then
      if oldType == 'table' then
        mergeValuesByPath(oldValue, EMPTY_TABLE, paths, p, separator)
      else
        paths[p] = {old = oldValue}
      end
    else
      local newType = type(newValue)
      if oldType == 'table' then
        if newType == 'table' then
          mergeValuesByPath(oldValue, newValue, paths, p, separator)
        else
          mergeValuesByPath(oldValue, EMPTY_TABLE, paths, p, separator)
          paths[p] = {new = newValue}
        end
      elseif newType == 'table' then
        mergeValuesByPath(EMPTY_TABLE, newValue, paths, p, separator)
        paths[p] = {old = oldValue}
      else
        paths[p] = {old = oldValue, new = newValue}
      end
    end
  end
  for k, newValue in pairs(newTable) do
    if oldTable[k] == nil then
      local p = path..separator..tostring(k)
      if type(newValue) == 'table' then
        mergeValuesByPath(EMPTY_TABLE, newValue, paths, p, separator)
      else
        paths[p] = {new = newValue}
      end
    end
  end
  return paths
end

function tables.mergeValuesByPath(oldTable, newTable, path, separator)
  return mergeValuesByPath(oldTable, newTable, {}, path or '', separator or DEFAULT_PATH_SEPARATOR)
end

-- JSON Schema compatible with Lua table
-- See also https://github.com/jdesgats/ljsonschema and https://github.com/api7/jsonschema

local function getPathKeyAndSchema(schema, path, separator)
  local key, remainingPath = getPathKey(path, separator)
  local resultSchema
  if schema then
    if key == '' then
      resultSchema = schema
    elseif schema.type == 'object' and schema.properties then
      resultSchema = schema.properties[key]
    elseif schema.type == 'array' and schema.items then
      resultSchema = schema.items
    end
  end
  return key, resultSchema, remainingPath
end

function tables.getSchemaByPath(schema, path, separator)
  local key, resultSchema, remainingPath = getPathKeyAndSchema(schema, path, separator)
  if remainingPath then
    if resultSchema then
      return tables.getSchemaByPath(resultSchema, remainingPath, separator)
    end
  else
    return resultSchema, schema, key
  end
end

local function mapSchemasByPath(schema, paths, path, separator)
  local bp = path == '' and path or (path..separator)
  if schema.type == 'object' and schema.properties then
    for k, s in pairs(schema.properties) do
      local p = bp..tostring(k)
      mapSchemasByPath(s, paths, p, separator)
    end
  elseif schema.type == 'array' and schema.items then
    local p = bp..'#'
    mapSchemasByPath(schema.items, paths, p, separator)
  else
    paths[path] = schema
  end
end

function tables.mapSchemasByPath(schema, path, separator)
  local paths = {}
  mapSchemasByPath(schema, paths, path or '', separator or DEFAULT_PATH_SEPARATOR)
  return paths
end

local SCHEMA_ERRORS = {
  MISSING_SCHEMA = 'Missing or invalid schema',
  INVALID_SCHEMA_TYPE = 'Missing, invalid or unsupported schema type',
  INVALID_PROPERTY_COUNT = 'Invalid property count',
  INVALID_PROPERTY = 'Unexpected property',
  MISSING_PROPERTY = 'Missing required property',
  INVALID_ARRAY_VALUE = 'Invalid array value',
  INVALID_ARRAY_SIZE = 'Invalid array value',
  INCOMPATIBLE_VALUE_TYPE = 'Incompatible value type',
  CANNOT_PARSE_VALUE = 'Cannot parse value',
  INVALID_CONST_VALUE = 'Invalid const value',
  INVALID_ENUM_VALUE = 'Invalid enum value',
  INVALID_INTEGER_VALUE = 'Invalid integer value',
  INVALID_STRING_LENGTH = 'Invalid string length value',
  INVALID_STRING_PATTERN = 'Invalid string pattern value',
  INVALID_NUMBER_RANGE = 'Invalid number range value',
  INVALID_NUMBER_MULTIPLE = 'Invalid number multipleOf value',
}

local function returnError(code, schema, value, path, tip)
  local message = SCHEMA_ERRORS[code] or code
  if tip ~= nil then
    message = message..', ('..tostring(tip)..')'
  end
  if path and path ~= '' then
    message = message..', path is '..path
  end
  local valueType = type(value)
  if valueType ~= 'table' then
    message = message..', value is "'..tostring(value)..'"('..valueType..')'
  end
  if schema and valueType ~= schema.type then
    message = message..', expected type is '..tostring(schema.type)
  end
  return message
end

local function returnNil()
  return nil
end

local function isNearInteger(value)
  return math.abs(value - math.floor(value + 0.5)) < 0.0000001
end

local function getSchemaValue(schema, value, translateValues, onError, path)
  if type(schema) ~= 'table' then
    return nil, onError('MISSING_SCHEMA', schema, value, path)
  end
  -- TODO Support complex schema (definitions, $ref)
  -- TODO Support schema composition (allOf, anyOf, oneOf, not)
  -- schema types: string, number, integer, object, array, boolean, null
  local schemaType = schema.type
  if type(schemaType) ~= 'string' then
    -- TODO support type list
    return nil, onError('INVALID_SCHEMA_TYPE', schema, value, path)
  elseif value == nil then
    if translateValues then
      return schema.default or schema.const
    end
    return nil
  elseif type(value) == 'table' then
    -- TODO patternProperties
    if schemaType == 'object' then
      local keys = Map.keys(value)
      if schema.minProperties and #keys < schema.minProperties or schema.maxProperties and #keys > schema.maxProperties then
        return nil, onError('INVALID_PROPERTY_COUNT', schema, value, path)
      end
      if schema.additionalProperties == false then
        for _, key in ipairs(keys) do
          if not schema.properties[key] then
            return nil, onError('INVALID_PROPERTY', schema, value, path, key)
          end
        end
      end
      if schema.propertyNames and schema.propertyNames.pattern then
        local pattern = schema.propertyNames.pattern
        for _, key in ipairs(keys) do
          if not string.match(key, pattern) then
            return nil, onError('INVALID_PROPERTY', schema, value, path, key)
          end
        end
      end
      if schema.required then
        for _, required in ipairs(schema.required) do
          if not List.contains(keys, required) then
            return nil, onError('MISSING_PROPERTY', schema, value, path, required)
          end
        end
      end
    elseif schemaType == 'array' then
      local isEmpty = next(value) == nil
      if not value[1] and not isEmpty then
        return nil, onError('INVALID_ARRAY_VALUE', schema, value, path)
      end
      if schema.minItems and #value < schema.minItems or schema.maxItems and #value > schema.maxItems then
        return nil, onError('INVALID_ARRAY_SIZE', schema, value, path)
      end
    else
      return nil, onError('INCOMPATIBLE_VALUE_TYPE', schema, value, path)
    end
    if not translateValues then
      return value
    end
    local t = {}
    if schemaType == 'array' then
      local itemSchema = schema.items
      if itemSchema then
        for i, v in ipairs(value) do
          local sv, err = getSchemaValue(itemSchema, v, true, onError, path..'['..tostring(i)..']')
          if err then
            return nil, err
          end
          t[i] = sv
        end
      else
        return value
      end
    else -- object
      local propSchema = schema.properties
      if propSchema then
        for k, v in pairs(value) do
          local propertySchema = propSchema[k]
          if propertySchema then
            local sp = tostring(k)
            if path ~= '' then
              sp = path..'.'..sp
            end
            local sv, err = getSchemaValue(propertySchema, v, true, onError, sp)
            if err then
              return nil, err
            end
            t[k] = sv
          else
            t[k] = v
          end
        end
        for k, propertySchema in pairs(propSchema) do
          if value[k] == nil then
            if propertySchema.default ~= nil then
              t[k] = propertySchema.default
            elseif propertySchema.const ~= nil then
              t[k] = propertySchema.const
            elseif propertySchema.type == 'object' then
              t[k] = getSchemaValue(propertySchema, {}, true, returnNil, path)
            end
          end
        end
      else
        return value
      end
    end
    return t
  end
  -- parsing simple types
  local valueType = type(value)
  if translateValues then
    if valueType == 'string' and schemaType ~= 'string' then
      local parsedValue
      if schemaType == 'number' or schemaType == 'integer' then
        parsedValue = tonumber(value)
      elseif schemaType == 'boolean' then
        if value == 'true' then
          parsedValue = true
        elseif value == 'false' then
          parsedValue = false
        end
      end
      if parsedValue == nil then
        return nil, onError('CANNOT_PARSE_VALUE', schema, value, path)
      end
      value = parsedValue
    elseif schemaType == 'string' and (valueType == 'number' or valueType == 'boolean') then
      value = tostring(value)
    end
    valueType = type(value)
  end
  -- validating simple types
  if schemaType ~= valueType then
    if schemaType == 'integer' and valueType == 'number' then
      local i = math.tointeger(value)
      if not i then
        return nil, onError('INVALID_INTEGER_VALUE', schema, value, path)
      end
      value = i
    else
      return nil, onError('INCOMPATIBLE_VALUE_TYPE', schema, value, path)
    end
  end
  if schema.const ~= nil and value ~= schema.const then
    return nil, onError('INVALID_CONST_VALUE', schema, value, path)
  end
  if schema.enum ~= nil and not List.contains(schema.enum, value) then
    return nil, onError('INVALID_ENUM_VALUE', schema, value, path)
  end
  if schemaType == 'string' then
    if schema.minLength and #value < schema.minLength or schema.maxLength and #value > schema.maxLength then
      return nil, onError('INVALID_STRING_LENGTH', schema, value, path)
    end
    if schema.pattern and not string.match(value, schema.pattern) then
      return nil, onError('INVALID_STRING_PATTERN', schema, value, path)
    end
  elseif schemaType == 'number' or schemaType == 'integer' then
    if schema.minimum and value < schema.minimum or schema.maximum and value > schema.maximum
    or schema.exclusiveMinimum and value <= schema.exclusiveMinimum
    or schema.exclusiveMaximum and value >= schema.exclusiveMaximum then
      return nil, onError('INVALID_NUMBER_RANGE', schema, value, path)
    end
    if schema.multipleOf and not isNearInteger(value / schema.multipleOf) then
      return nil, onError('INVALID_NUMBER_MULTIPLE', schema, value, path)
    end
  end
  return value
end

--- Returns the value validated by the JSON schema or nil.
-- See https://json-schema.org/
-- @tparam table schema the JSON schema.
-- @param value the value to get from.
-- @tparam[opt] boolean translateValues true to parse string values and populate objects, default is false.
-- @tparam[opt] function onError a function that will be called when a validation error has been found.
-- the function is called with the arguments: code, schema, value, path.
-- @return the value validated against the schema.
function tables.getSchemaValue(schema, value, translateValues, onError)
  return getSchemaValue(schema, value, translateValues, onError or returnError, '')
end

-- Command line argument parsing

local ARGUMENT_PATH_SEPARATOR = '.'
local ARGUMENT_DEFAULT_PATH = '0'

local function loadJsonFile(path)
  local File = require('jls.io.File')
  local file = File:new(path)
  if file:exists() then
    local json = require('jls.util.json')
    return json.decode(file:readAll())
  end
end

local function loadIfString(name)
  if type(name) == 'string' then
    local path = package.searchpath(name, string.gsub(package.path, '%.lua', '.json'))
    print('loadIfString', name, path)
    if path then
      return loadJsonFile(path)
    end
    return require('jls.lang.loader').load(name, package.path)
  end
  return name
end

--- Returns a table containing an entry for each argument name.
-- An entry contains a string or a list of string.
-- An argument name starts with a comma ('-').
-- @tparam string arguments the command line containing the arguments.
-- @tparam[opt] table options the options.
-- @tparam[opt] string options.separator the path separator, default is the dot ('.').
-- @tparam[opt] string options.emptyPath the path used for arguments without name, default is zero ('0').
-- @tparam[opt] table options.defaultValues the default values, could be a module name.
-- @tparam[opt] string options.helpPath the path used to print the help from the schema.
-- @tparam[opt] string options.help the help text to display.
-- @tparam[opt] string options.configPath the path for a configuration file.
-- @tparam[opt] function options.configLoader the function to load the configuration file, could be a module name.
-- @tparam[opt] table options.schema the schema to validate the argument table, could be a module name.
-- @tparam[opt] boolean options.keepComma true to keep leading commas from argument names.
-- @tparam[opt] string options.argumentPattern the pattern used to match the argument name, default is '^-+(.+)$'.
-- @treturn table the arguments as a table.
-- @treturn table the custom arguments from command line and configuration file.
function tables.createArgumentTable(arguments, options)
  if type(options) ~= 'table' then
    options = {}
  end
  local separator = options.separator or ARGUMENT_PATH_SEPARATOR
  local emptyPath = options.emptyPath or ARGUMENT_DEFAULT_PATH
  local argumentPattern = options.argumentPattern or '^-+(.+)$'
  local argumentPrefix = options.argumentPrefix or '-'
  local keepComma = options.keepComma == true
  local aliases = options.aliases or {}
  local t = {}
  local name = emptyPath
  local schema = loadIfString(options.schema)
  if schema and type(schema) ~= 'table' then
    error('Invalid schema type')
  end
  local defaultValues = loadIfString(options.defaultValues)
  if defaultValues and type(defaultValues) ~= 'table' then
    error('Invalid default values type')
  end
  for _, argument in ipairs(arguments) do
    local argumentName = string.match(argument, argumentPattern)
    -- Do not accept number as argument name, number is value only
    if argumentName and not tonumber(argument) then
      name = keepComma and argument or argumentName
      name = aliases[name] or name
      if tables.getPath(t, name, nil, separator) == nil then
        tables.setPath(t, name, true, separator)
      end
    else
      local value
      local currentValue = tables.getPath(t, name, nil, separator)
      if currentValue == true or currentValue == nil then
        value = argument
      elseif type(currentValue) == 'table' then
        if List.isList(currentValue) then
          table.insert(currentValue, argument)
        else
          value = argument
        end
      else
        value = {currentValue, argument}
      end
      if value then
        tables.setPath(t, name, value, separator)
      end
      name = emptyPath
    end
  end
  -- Load configuration file, if specified and found
  if options.configPath then
    local configPath = tables.getPath(t, options.configPath, nil, separator)
    if not configPath and defaultValues then
      configPath = tables.getPath(defaultValues, options.configPath, nil, separator)
    end
    if not configPath and schema then
      local configSchema = tables.getSchemaByPath(schema, options.configPath, separator)
      if configSchema then
        configPath = configSchema.default
      end
    end
    if configPath then
      local configLoader = loadIfString(options.configLoader) or loadJsonFile
      if type(configLoader) ~= 'function' then
        error('Invalid config loader type')
      end
      local status, result = pcall(configLoader, configPath)
      if not status then
        print('Invalid configuration file "'..configPath..'", '..tostring(result))
        os.exit(1)
      end
      if result then
        tables.merge(t, result, true)
      end
    end
  end
  local ct = tables.deepCopy(t)
  -- Merge default values
  if defaultValues then
    tables.merge(t, defaultValues, true)
  end
  -- Display help
  if options.helpPath and tables.getPath(t, options.helpPath, nil, separator) == true then
    if options.help then
      print(options.help)
    end
    if schema then
      local schemaPaths = tables.mapSchemasByPath(schema, '', separator)
      local buffer = StringBuffer:new()
      if schema.title then
        print(tostring(schema.title))
      end
      if schema.description then
        print(tostring(schema.description))
      end
      local aliasMap = Map.reverse(aliases)
      print('Arguments:')
      for path, s in Map.spairs(schemaPaths) do
        buffer:append('  ')
        local alias = aliasMap[path]
        if alias then
          buffer:append(argumentPrefix, alias, ' or ')
        end
        buffer:append(argumentPrefix, path)
        if s.default ~= nil then
          buffer:append(' =', tables.stringify(s.default))
        end
        if s.enum then
          buffer:append(' |')
          for _, v in ipairs(s.enum) do
            buffer:append(tostring(v), '|')
          end
        end
        if s.type then
          buffer:append(' (', tostring(s.type), ')')
        end
        if s.title then
          buffer:append(': ', tostring(s.title))
        end
        print(buffer:toString())
        buffer:clear()
      end
    end
    if defaultValues then
      print('Default values:')
      local valuesByPath = tables.mapValuesByPath(defaultValues, '', separator)
      for path, v in Map.spairs(valuesByPath) do
        print('  '..argumentPrefix..string.sub(path, 2)..' ='..tostring(v))
      end
    end
    os.exit(0)
  end
  -- Validate using schema and add schema default values
  if schema then
    local st, serr = tables.getSchemaValue(schema, t, true)
    if serr then
      print(serr)
      os.exit(22)
    end
    t = st
  end
  return t, ct
end

function tables.getArgument(t, name, defaultValue, index, asString, separator)
  local value = tables.getPath(t, name or ARGUMENT_DEFAULT_PATH, nil, separator or ARGUMENT_PATH_SEPARATOR)
  if value == nil then
    return defaultValue
  elseif asString and type(value) == 'boolean' then
    return tostring(value)
  elseif type(value) == 'table' then
    return value[index or 1] or defaultValue
  end
  if index and index ~= 1 then
    return defaultValue
  end
  return value
end

function tables.getArguments(t, name, separator)
  local value = tables.getPath(t, name or ARGUMENT_DEFAULT_PATH, nil, separator or ARGUMENT_PATH_SEPARATOR)
  if value == nil or type(value) == 'boolean' then
    return {}
  elseif type(value) == 'table' then
    return value
  end
  return {value}
end

-- Map functions, for compatibilities
-- TODO Remove
tables.keys = Map.keys
tables.values = Map.values
tables.size = Map.size
tables.spairs = Map.spairs

return tables