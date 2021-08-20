local jsonLib = require('cjson')

--jsonLib.encode_keep_buffer(false)

return {
  decode = jsonLib.decode,
  encode = jsonLib.encode,
  null = jsonLib.null or jsonLib.util.null,
}