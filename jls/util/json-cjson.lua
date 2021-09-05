local jsonLib = require('cjson')

--jsonLib.encode_keep_buffer(false)

-- On the first load, the cjson library determines the locale decimal point.
-- If the locale decimal point changes after loading then the library will not be able to code numbers.
-- This issue can be quickly determined as json.encode(0.5) gives '0,5'.

return {
  decode = jsonLib.decode,
  encode = jsonLib.encode,
  null = jsonLib.null or jsonLib.util.null,
}
