
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
    local fd, err = io.open(path, 'rb')
    if not fd then
      return nil, err
    end
    local data = fd:read('*a')
    fd:close()
    fd, err = io.open(newPath, 'wb')
    if not fd then
      return nil, err
    end
    fd:write(data)
    fd:close()
  end,
  dir = lfsLib.dir
}
