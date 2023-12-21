local jsonLib = require('cjson')

--[[
On the first load, the cjson library determines the locale decimal point.
If the locale decimal point changes after loading then the library will not be able to encode numbers.
This issue can be quickly determined as json.encode(0.5) gives '0,5'.

The cjson library encodes sparse Lua arrays as JSON arrays using JSON null for the missing entries.
The cjson library accepts number keys and encodes them as string.
]]

-- no sparse array
jsonLib.encode_sparse_array(false, 1, 0)

--jsonLib.encode_keep_buffer(false)

return {
  decode = jsonLib.decode,
  encode = jsonLib.encode,
  null = jsonLib.null or jsonLib.util.null,
}
