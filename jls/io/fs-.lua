local isWindowsOS = string.sub(package.config, 1, 1) == '\\'

local function execute(cmd)
  local s, k, c = os.execute(cmd)
  --print('execute', cmd, '=>', s, k, c)
  return s, k, c
end

local function popen(cmd, def, mode)
  local l
  local f = io.popen(cmd)
  if f then
    l = f:read(mode or 'l')
    f:close()
  end
  --print('popen', cmd, '=>', l or def)
  return l or def
end

return {
  utime = function(path, atime, mtime)
    atime = atime or os.time()
    mtime = mtime or atime
    if isWindowsOS then
      return execute('powershell $d=(Get-Date 1970-01-01).AddSeconds('..mtime..'); $f=Get-Item "'..path..'"; % $f.LastWriteTime=$d')
    end
    return execute('touch -m -d @'..mtime..' "'..path..'"')
  end,
  stat = function(path)
    local item
    if isWindowsOS then
      item = popen('if exist "'..path..'" powershell $f=Get-Item "'..path..'"; \'{0},{1},{2}\' -f $f.Mode,$f.Length,([DateTimeOffset]$f.LastWriteTime).ToUnixTimeSeconds()', '')
    else
      item = popen('stat -c "%F,%s,%Y" "'..path..'"', '')
    end
    if item then
      local mode, size, modification = string.match(item, '^([^,]*),([^,]*),([^,]*)$')
      if mode then
        return {
          mode = string.find(mode, '^d') and 'directory' or 'file',
          modification = tonumber(modification),
          size = tonumber(size)
        }
      end
    end
    return nil
  end,
  currentdir = function()
    return popen(isWindowsOS and 'cd' or 'pwd', '.')
  end,
  mkdir = function(path)
    return execute('mkdir "'..path..'"')
  end,
  rmdir = function(path)
    return execute('rmdir "'..path..'"')
  end,
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
  dir = function(path)
    local f = io.popen((isWindowsOS and 'dir /b "' or 'ls -1 "')..path..'"')
    local names = {}
    if f then
      while true do
        local name = f:read('l')
        if name == nil then
          break
        end
        table.insert(names, name)
      end
      f:close()
    end
    local i = 0
    return function()
      i = i + 1
      return names[i]
    end
  end
}
