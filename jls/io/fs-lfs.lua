
local lfsLib = require('lfs')

return {
  utime = lfsLib.touch,
  stat = lfsLib.attributes,
  currentdir = lfsLib.currentdir,
  mkdir = lfsLib.mkdir,
  rmdir = lfsLib.rmdir,
  unlink = function(path)
    return os.remove(path)
  end,
  rename = function(path, newPath)
    return os.rename(path, newPath)
  end,
  copyfile = function(path, newPath)
    local fd = io.open(path, 'rb')
    if not fd then
      return nil, 'File not found'
    end
    local data = fd:read('a')
    fd:close()
    fd = io.open(newPath, 'wb')
    if fd then
      fd:write(data)
      fd:close()
    end
  end,
  dir = lfsLib.dir
}
