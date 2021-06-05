local jsonLib = require('cjson')

return {
  decode = jsonLib.decode,
  encode = jsonLib.encode,
  null = jsonLib.null or jsonLib.util.null,
}