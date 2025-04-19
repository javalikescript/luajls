local fs = require('jls.io.fs-')
local lfsLib = require('lfs')

return {
  utime = lfsLib.touch,
  stat = lfsLib.attributes,
  currentdir = lfsLib.currentdir,
  mkdir = lfsLib.mkdir,
  rmdir = lfsLib.rmdir,
  unlink = fs.unlink,
  rename = fs.rename,
  copyfile = fs.copyfile,
  dir = lfsLib.dir
}
