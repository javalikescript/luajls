local jsonLib = require('dkjson')

return {
  decode = jsonLib.decode,
  encode = jsonLib.encode,
  null = jsonLib.null
}