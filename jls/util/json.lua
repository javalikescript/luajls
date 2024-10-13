--- Provide JavaScript Object Notation (JSON) codec.
-- @module jls.util.json
-- @pragma nostrip

local loader = require('jls.lang.loader')
local jsonLib = loader.requireOne('jls.util.json-cjson', 'jls.util.json-dkjson', 'jls.util.json-lunajson')
local StringBuffer = require('jls.lang.StringBuffer')
local List = require('jls.util.List')
local Map = require('jls.util.Map')

local json = {
  decode = jsonLib.decode,
  encode = jsonLib.encode,
  null = jsonLib.null
}

-- TODO json libs should takes empty array and empty object as argument to be able to keep format.

--- The opaque value representing null.
-- @field json.null the opaque value representing null.

--- Returns the JSON encoded string representing the specified value.
-- @param value The value to encode.
-- @treturn string the encoded string.
-- @function json.encode
-- @usage
--local json = require('jls.util.json')
--json.encode({aString = 'Hello world !'}) -- Returns '{"aString":"Hello world !"}'

--- Returns the value representing the specified string.
-- @tparam string value The JSON string to decode.
-- @return the decoded value.
-- @function json.decode
-- @usage
--local json = require('jls.util.json')
--json.decode('{"aString":"Hello world !"}') -- Returns {aString = 'Hello world !'}

--- Returns the value representing the specified string.
-- Raises an error if the value cannot be parsed.
-- @tparam string value The JSON string to parse.
-- @return the parsed value.
function json.parse(value)
  local parsedValue = json.decode(value)
  if parsedValue == json.null then
    return nil
  end
  -- We may look for null values
  return parsedValue
end

local escapeMap = { ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t', ['"'] = '\\"', ['\\'] = '\\\\', ['/'] = '\\/', }

--local isUtf8Valid = utf8.len

local function escapeChar(c)
  return escapeMap[c] or string.format('\\u%04X', string.byte(c))
end

local function encodeString(s)
  return (string.gsub(s, '[%c"\\]', escapeChar))
end

if not string.match(tostring(1234.5), '^1234[%.,]5$') then
  error('Unsupported number locale')
end

local function encodeNumber(n)
  return (string.gsub(tostring(n), ',', '.', 1))
end

--- Returns the JSON encoded string representing the specified value.
-- When specifying space, the encoded string will includes new lines.
-- Invalid value will raise an error if lenient mode is not enabled.
-- @param value The value to to convert to a JSON encoded string.
-- @tparam[opt] number space The number of space characters to use as white space.
-- @tparam[opt] boolean lenient true to convert invalid JSON keys or values using tostring.
-- @treturn string the encoded string.
function json.stringify(value, space, lenient)
  if value == nil then
    return 'null'
  end
  local sb = StringBuffer:new()
  local indent = ''
  if type(space) == 'number' and space > 1 then
    indent = string.rep(' ', space)
  elseif type(space) == 'string' then
    indent = space
  end
  local colon, newline
  if indent == '' then
    colon = ':'
    newline = ''
  else
    colon = ': '
    newline = '\n'
  end
  local stack = {}
  local function stringify(val, prefix)
    local valueType = type(val)
    if valueType == 'string' then
      sb:append('"', encodeString(val), '"')
    elseif valueType == 'boolean' or math.type(val) == 'integer' then
      sb:append(val)
    elseif valueType == 'number' then
      sb:append(encodeNumber(val))
    elseif val == json.null then -- json.null could be a table
      sb:append('null')
    elseif valueType == 'table' then
      local size = -1
      if Map:isInstance(val) then
        val = val.map
      elseif type(val.toJSON) == 'function' then
        return stringify(val:toJSON(), prefix)
      elseif List:isInstance(val) then
        size = val:size()
      elseif next(val) ~= nil then -- empty tables are objects not arrays
        size = List.size(val, false, true)
      end
      if stack[val] then
        if lenient then
          sb:append('null')
          return
        end
        error('cycle detected')
      else
        stack[val] = true
      end
      local subPrefix = prefix..indent
      if size == 0 then
        sb:append('[]')
      elseif size > 0 then
        sb:append('[', newline, subPrefix)
        stringify(val[1], subPrefix)
        for i = 2, size do
          sb:append(',', newline, subPrefix)
          stringify(val[i], subPrefix)
        end
        sb:append(newline, prefix, ']')
      elseif Map.isEmpty(val) then
        sb:append('{}')
      else
        sb:append('{', newline)
        local firstValue = true
        for k, v in Map.spairs(val) do
          if type(k) == 'string' then
            if firstValue then
              firstValue = false
            else
              sb:append(',', newline)
            end
            sb:append(subPrefix, '"', encodeString(k), '"', colon)
            stringify(v, subPrefix)
          elseif not lenient then
            error('Invalid JSON key type '..type(k)..' ('..tostring(k)..')')
          end
        end
        sb:append(newline, prefix, '}')
      end
      stack[val] = nil
    elseif lenient then
      sb:append('null')
    else
      error('Invalid JSON value type '..valueType..' ('..tostring(val)..')')
    end
  end
  stringify(value, '')
  return sb:toString()
end

--- Loads the JSON resource for the specified name.
-- See @{jls.lang.loader|loader} loadResource function.
-- @tparam string name the JSON name.
-- @tparam[opt] boolean try true to return nil in place of raising an error
-- @return the JSON value.
function json.require(name, try)
  local value = loader.loadResource(name, try)
  if value then
    return json.decode(value)
  end
end

return json
