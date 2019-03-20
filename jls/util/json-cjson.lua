--- Provide JavaScript Object Notation (JSON) codec.
-- @module jls.util.json

local jsonLib = require('cjson')

local json = {}

--- The opaque value representing null.
-- @field null
json.null = jsonLib.null or jsonLib.util.null

--- Returns the JSON encoded string representing the specified value.
-- @tparam table value The value to encode.
-- @return the encoded string.
-- @function encode
-- @usage
--require('jls.util.json').encode({aString = 'Hello world !'}) -- Returns '{"aString":"Hello world !"}'
json.encode = jsonLib.encode

--- Returns the value representing the specified string.
-- @tparam string jsonString The JSON string to decode.
-- @return the decoded value.
-- @function decode
-- @usage
--require('jls.util.json').decode('{"aString":"Hello world !"}') -- Returns {aString = 'Hello world !'}
json.decode = jsonLib.decode

return json