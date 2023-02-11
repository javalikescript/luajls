--- Provide JavaScript Object Notation (JSON) codec.
-- @module jls.util.json

local jsonLib = require('jls.lang.loader').requireOne('jls.util.json-cjson', 'jls.util.json-dkjson', 'jls.util.json-lunajson')
local StringBuffer = require('jls.lang.StringBuffer')
local List = require('jls.util.List')
local Map = require("jls.util.Map")

local json = {
  decode = jsonLib.decode,
  encode = jsonLib.encode,
  null = jsonLib.null
}

-- TODO json libs should takes empty array and empty object as argument to be able to keep format.

--- The opaque value representing null.
-- @field null

--- Returns the JSON encoded string representing the specified value.
-- @tparam table value The value to encode.
-- @return the encoded string.
-- @function encode
-- @usage
--local json = require('jls.util.json')
--json.encode({aString = 'Hello world !'}) -- Returns '{"aString":"Hello world !"}'

--- Returns the value representing the specified string.
-- @tparam string jsonString The JSON string to decode.
-- @return the decoded value.
-- @function decode
-- @usage
--local json = require('jls.util.json')
--json.decode('{"aString":"Hello world !"}') -- Returns {aString = 'Hello world !'}

--- Returns the value representing the specified string.
-- Raises an error if the value cannot be parsed.
-- @tparam string jsonString The JSON string to parse.
-- @return the parsed value.
-- @function parse
function json.parse(value)
  local parsedValue = json.decode(value)
  if parsedValue == json.null then
    return nil
  end
  return parsedValue
end

local escapeMap = { ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t', ['"'] = '\\"', ['\\'] = '\\\\', ['/'] = '\\/', }
local escapePattern = '[%c"\\]'
local escapePatternWithSlash = '[%c"/\\]'

local function encodeString(s)
  return string.gsub(s, escapePattern, function(c)
    return escapeMap[c] or string.format('\\u%04X', string.byte(c))
  end)
end

if not string.match(tostring(1234.5), '^1234[%.,]5$') then
  error('Unsupported number locale')
end

local function encodeNumber(n)
  local s = tostring(n)
  if math.type(n) == 'integer' then
    return s
  end
  return (string.gsub(s, ',', '.', 1))
end

--- Returns the JSON encoded string representing the specified value.
-- When specifying space, the encoded string will includes new lines.
-- @tparam table value The value to to convert to a JSON encoded string.
-- @tparam number space The number of space characters to use as white space.
-- @return the encoded string.
-- @function stringify
function json.stringify(value, space)
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
    if val == json.null then -- json.null could be a table or a userdata
      sb:append('null')
    elseif valueType == 'table' then
      local isList, size
      if Map:isInstance(val) then
        isList, size = false, val:size()
        val = val.map
      else
        isList, size = List.isList(val, true, false)
      end
      if stack[val] then
        error('cycle detected')
      end
      stack[val] = true
      local subPrefix = prefix..indent
      if size == 0 then
        -- we cannot decide whether empty tables should be array or object
        -- cjson defaults empty tables to object
        if isList then
          sb:append('[]')
        else
          sb:append('{}')
        end
      elseif isList then
        sb:append('[', newline)
        for i = 1, size do
          if i > 1 then
            sb:append(',', newline)
          end
          sb:append(subPrefix)
          local v = val[i]
          if v == nil then
            sb:append('null')
          else
            stringify(v, subPrefix)
          end
        end
        sb:append(newline, prefix, ']')
      else
        sb:append('{', newline)
        local firstValue = true
        for k, v in Map.spairs(val) do
          if firstValue then
            firstValue = false
          else
            sb:append(',', newline)
          end
          local tk = type(k)
          local ec
          if tk == 'string' then
            ec = encodeString(k)
          elseif tk == 'number' then
            local nk = math.tointeger(k)
            if nk then
              ec = tostring(nk)
            else
              error('Invalid number key, '..tostring(k))
            end
            if val[ec] then
              error('Duplicate integer key '..ec)
            end
          else
            error('Invalid key type '..tk)
          end
          sb:append(subPrefix, '"', ec, '"', colon)
          stringify(v, subPrefix)
        end
        sb:append(newline, prefix, '}')
      end
      stack[val] = nil
    elseif valueType == 'string' then
      sb:append('"', encodeString(val), '"')
    elseif valueType == 'number' then
      sb:append(encodeNumber(val))
    elseif valueType == 'boolean' then
      sb:append(val and 'true' or 'false')
    else
      error('Invalid value type '..valueType..' ('..tostring(val)..')')
    end
  end
  stringify(value, '')
  return sb:toString()
end

function json.require(name)
  local File = require('jls.io.File')
  local jsonpath = string.gsub(package.path, '%.lua', '.json')
  local path = assert(package.searchpath(name, jsonpath))
  local file = File:new(path)
  return json.decode(file:readAll())
end

return json
