
local lfsLib = require('lfs')

return {
  utime = lfsLib.touch,
  stat = lfsLib.attributes,
  currentdir = lfsLib.currentdir,
  mkdir = lfsLib.mkdir,
  rmdir = lfsLib.rmdir,
  dir = lfsLib.dir
}
