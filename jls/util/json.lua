--- Provide JavaScript Object Notation (JSON) codec.
-- @module jls.util.json

local json = require('jls.lang.loader').requireOne('jls.util.json-cjson', 'jls.util.json-dkjson', 'jls.util.json-lunajson')
local StringBuffer = require('jls.lang.StringBuffer')
local TableList = require('jls.util.TableList')
local Map = require("jls.util.Map")

-- TODO json libs should takes empty array and empty object as argument to be able to keep format.

--- The opaque value representing null.
-- @field null

--- Returns the JSON encoded string representing the specified value.
-- @tparam table value The value to encode.
-- @return the encoded string.
-- @function encode
-- @usage
--require('jls.util.json').encode({aString = 'Hello world !'}) -- Returns '{"aString":"Hello world !"}'

--- Returns the value representing the specified string.
-- @tparam string jsonString The JSON string to decode.
-- @return the decoded value.
-- @function decode
-- @usage
--require('jls.util.json').decode('{"aString":"Hello world !"}') -- Returns {aString = 'Hello world !'}

--- Returns the value representing the specified string.
-- @tparam string jsonString The JSON string to parse.
-- @return the parsed value.
-- @function parse
json.parse = json.decode

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
  local function stringify(val, prefix)
    local valueType = type(val)
    if value == json.null then
      sb:append('null')
    elseif valueType == 'table' then
      local subPrefix = prefix..indent
      local isList, size = TableList.isList(val)
      if size == 0 then
        -- we cannot decide whether empty tables should be array or object
        -- cjson defaults empty tables to object
        if Map:isInstance(val) then
          sb:append('{}')
        else
          sb:append('[]')
        end
      elseif isList then
        sb:append('[', newline)
        for i, v in ipairs(val) do
          if i > 1 then
            sb:append(',', newline)
          end
          sb:append(subPrefix)
          stringify(v, subPrefix)
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
          else
            error('Invalid key type '..tk)
          end
          sb:append(subPrefix, '"', ec, '"', colon)
          stringify(v, subPrefix)
        end
        sb:append(newline, prefix, '}')
      end
    elseif valueType == 'string' then
      sb:append('"', encodeString(val), '"')
    elseif valueType == 'number' then
      sb:append(encodeNumber(val))
    elseif valueType == 'boolean' then
      sb:append(val and 'true' or 'false')
    else
      error('Invalid value type '..valueType)
    end
  end
  stringify(value, '')
  --print(xpcall(stringify, debug.traceback, value, ''))
  return sb:toString()
end

return json
