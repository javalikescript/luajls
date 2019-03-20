
local luvLib = require('luv')

local NEW_DIR_MODE = tonumber('777', 8)

-- https://docs.oracle.com/javase/7/docs/api/java/nio/file/attribute/BasicFileAttributes.html
local function adaptStat(st)
  -- make a stat table compatible with lfs
  if st then
    --st.moden = st.mode -- not used
    st.mode = st.type
    if st.mtime then
      st.modification = st.mtime.sec
    end
    if st.atime then
      st.access = st.atime.sec
    end
    if st.ctime then
      st.change = st.ctime.sec
    end
  end
  return st
end

return {
  utime = function(path, atime, mtime)
    return luvLib.fs_utime(path, atime, mtime)
  end,
  stat = function(path)
    return adaptStat(luvLib.fs_stat(path))
  end,
  currentdir = luvLib.cwd,
  mkdir = function(path)
    return luvLib.fs_mkdir(path, NEW_DIR_MODE)
  end,
  rmdir = luvLib.fs_rmdir,
  dir = function(path)
    local req = luvLib.fs_scandir(path)
    return function()
      return luvLib.fs_scandir_next(req)
    end
  end
}
