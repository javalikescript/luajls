--[[--
Provide file system abstraction.

A File extends @{Path} by adding file system manipulation, such as deleting, renaming, listing.

@module jls.io.File
@pragma nostrip

@usage
local dir = File:new('work')
for _, file in ipairs(dir:listFiles()) do
  if file:isFile() then
    print('The file "'..file:getPath()..'" length is '..tostring(file:length()))
  end
end
]]

local fs = require('jls.io.fs')

local Path = require('jls.io.Path')
--local logger = require('jls.lang.logger')

--- A File class.
-- A File instance represents a file or a directory.
-- @type File
return require('jls.lang.class').create(Path, function(file, _, File)
  --- Creates a new File with the specified name.
  -- See @{Path}
  -- @function File:new
  -- @usage
  --local workingDirectory = File:new('work')
  --local configurationPath = File:new(workingDirectory, 'configuration.json')

  --- Returns the path of the file as a string.
  -- @treturn string the path of the file.
  -- @usage
  --local configurationPath = File:new('work/configuration.json')
  --configurationPath:getPath() -- returns 'work/configuration.json'
  function file:getPath()
    return self.path
  end

  --- Returns the parent of this file entry as a File.
  -- @return the parent of this file as a File.
  -- @usage
  --local configurationPath = File:new('work/configuration.json')
  --configurationPath:getParentFile():getName() -- returns 'work'
  function file:getParentFile()
    local p = self:getParent()
    if p then
      return File:new(p)
    end
    return nil
  end

  function file:getAbsoluteFile()
    if self:isAbsolute() then
      return self
    end
    return File:new(fs.currentdir()..Path.separator..self.path)
  end

  function file:getAbsolutePath()
    if self:isAbsolute() then
      return self.path
    end
    return fs.currentdir()..Path.separator..self.path
  end

  --- Indicates whether or not this file exists.
  -- @treturn boolean true when this file exists, false otherwise.
  function file:exists()
    return fs.stat(self.npath) ~= nil
  end

  --- Indicates whether or not this file entry is a file.
  -- @treturn boolean true when this file entry exists and is a file, false otherwise.
  function file:isFile()
    local st = fs.stat(self.npath)
    return st ~= nil and st.mode == 'file'
  end

  --- Indicates whether or not this file entry is a directory.
  -- @treturn boolean true when this file entry exists and is a directory, false otherwise.
  function file:isDirectory()
    local st = fs.stat(self.npath)
    return st ~= nil and st.mode == 'directory'
  end

  --- Returns the length of the file entry represented by this file.
  -- @treturn boolean the size of this file entry or 0.
  function file:length()
    local st = fs.stat(self.npath)
    if st ~= nil then
      return st.size
    end
    return 0
  end

  --- Returns last modified time of the file entry represented by this file.
  -- The time is given as the number of milliseconds since the Epoch, 1970-01-01 00:00:00 +0000 (UTC). 
  -- @treturn number the last modified time of this file entry or 0.
  function file:lastModified()
    local st = fs.stat(self.npath)
    if st ~= nil then
      return st.modification * 1000
    end
    return 0
  end

  --- Sets the last modified time of the file entry represented by this file.
  -- @tparam number time the last modified time or nil to set the current time.
  function file:setLastModified(time)
    if type(time) == 'number' then
      time = time // 1000
    else
      time = os.time()
    end
    local modificationTimeInSec = time
    local accessTimeInSec = time
    --[[
    local st = fs.stat(self.npath)
    if st ~= nil then
      accessTimeInSec = st.access
    end
    ]]
    return fs.utime(self.npath, accessTimeInSec, modificationTimeInSec)
  end

  --- Creates the directory named by this file entry.
  -- @treturn boolean true if the directory is created.
  function file:mkdir()
    return fs.mkdir(self.npath)
  end

  function file:mkdirs()
    if self:exists() then
      return false
    end
    if self:mkdir() then
      return true
    end
    local parent = self:getParentFile()
    return parent and parent:mkdirs() and self:mkdir()
  end

  --- Renames this file entry.
  -- @param file the new name of this file as a File or a string.
  -- @treturn boolean true if the file is renamed.
  -- In case of error, it returns nil, plus a string describing the error and the error code.
  function file:renameTo(file)
    if type(file) == 'string' then
      file = File:new(file)
    end
    return os.rename(self.npath, file.npath)
  end

  --- Deletes this file entry.
  -- This file may points to a file or an empty directory.
  -- @treturn boolean true if the file entry is deleted.
  function file:delete()
    local st = fs.stat(self.npath)
    if st == nil then
      return true
    end
    if st.mode == 'directory' then
      return fs.rmdir(self.npath)
    elseif st.mode == 'file' then
      return os.remove(self.npath)
    end
    error('Cannot delete this file')
  end

  function file:deleteAll()
    local files = self:listFiles()
    if not files then
      return false
    end
    for _, file in ipairs(files) do
      if file:isDirectory() then
        if not file:deleteAll() then
          return false
        end
      end
      if not file:delete() then
        return false
      end
    end
    return true
  end

  function file:deleteRecursive()
    if self:isDirectory() then
      if not self:deleteAll() then
        return false
      end
    end
    return self:delete()
  end

  function file:forEachFile(fn, recursive)
    if not self:isDirectory() then
      return
    end
    for filename in fs.dir(self.npath) do
      if filename ~= '.' and filename ~= '..' then
        local f = File:new(self.path, filename)
        local r
        if recursive and f:isDirectory() then
          r = f:forEachFile(fn, recursive)
        else
          r = fn(self, f)
        end
        if r then
          return r
        end
      end
    end
  end

  --- Returns an array of strings naming the file system entries in the directory represented by this file.
  -- @treturn table An array of strings naming the file system entries.
  function file:list()
    if not self:isDirectory() then
      return nil
    end
    local filenames = {}
    for filename in fs.dir(self.npath) do
      if filename ~= '.' and filename ~= '..' then
        table.insert(filenames, filename)
      end
    end
    return filenames
  end

  --- Returns an array of files in the directory represented by this file.
  -- @treturn table An array of files.
  function file:listFiles()
    if not self:isDirectory() then
      return nil
    end
    local files = {}
    for filename in fs.dir(self.npath) do
      if filename ~= '.' and filename ~= '..' then
        table.insert(files, File:new(self.path, filename))
      end
    end
    return files
  end

  --- Returns the lines of this file.
  -- @treturn table an array containing all the line of this file.
  function file:readAllLines()
    local t = {}
    for line in io.lines(self.npath) do 
      table.insert(t, line)
    end
    return t
  end

  --- Returns the content of this file.
  -- @treturn string the content of this file.
  function file:readAll()
    local fd = io.open(self.npath, 'rb')
    local content = nil
    if fd then
      content = fd:read('a')
      fd:close()
    end
    return content
  end

  --- Writes the specified data into this file.
  -- @param data the data to write as a string or an array of string
  -- @tparam boolean append true to indicate that the data should be appended to this file
  function file:write(data, append)
    local mode = 'wb'
    if append then
      mode = 'ab'
    end
    local fd = io.open(self.npath, mode)
    if fd then
      if type(data) == 'string' then
        fd:write(data)
      elseif type(data) == 'table' then
        for _, d in ipairs(data) do
          fd:write(d)
        end
      else
        fd:write(tostring(data))
      end
      fd:close()
    end
  end

  function file:copyTo(file)
    if type(file) == 'string' then
      file = File:new(file)
    end
    -- TODO use async and window buffer
    local content = self:readAll()
    if content then
      file:write(content)
    end
  end

  function File.asFile(file)
    if File:isInstance(file) then
      return file
    end
    return File:new(file)
  end
  
end)
