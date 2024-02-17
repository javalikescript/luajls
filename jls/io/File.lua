--[[--
Provides file system abstraction.

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

local class = require('jls.lang.class')
local Path = require('jls.io.Path')
local FileDescriptor = require('jls.io.FileDescriptor')
--local logger = require('jls.lang.logger'):get(...)

--- A File class.
-- A File instance represents a file or a directory.
-- @type File
return class.create(Path, function(file, _, File)
  --- Creates a new File with the specified name.
  -- See @{Path}
  -- @function File:new
  -- @param[opt] parent The optional parent as a string, @{File} or @{Path}.
  -- @tparam string path The name of the file.
  -- @return a new File
  -- @usage
  --local workingDirectory = File:new('work')
  --local configurationPath = File:new(workingDirectory, 'configuration.json')

  --- Returns the path of the file as a string.
  -- The result is normalized with the OS separator.
  -- @treturn string the path of the file.
  -- @usage
  --local configurationPath = File:new('work/configuration.json')
  --configurationPath:getPath() -- returns 'work/configuration.json'
  function file:getPath()
    return self.npath
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
    return File:new(self:getAbsolutePath())
  end

  function file:getAbsolutePath()
    if self:isAbsolute() then
      return self.npath
    end
    return fs.currentdir()..Path.separator..self.npath
  end

  function file:stat()
    return fs.stat(self.npath)
  end

  --- Indicates whether or not this file exists.
  -- @treturn boolean true when this file exists, false otherwise.
  function file:exists()
    return self:stat() ~= nil
  end

  --- Indicates whether or not this file entry is a file.
  -- @treturn boolean true when this file entry exists and is a file, false otherwise.
  function file:isFile()
    local st = self:stat()
    return st ~= nil and st.mode == 'file'
  end

  --- Indicates whether or not this file entry is a directory.
  -- @treturn boolean true when this file entry exists and is a directory, false otherwise.
  function file:isDirectory()
    local st = self:stat()
    return st ~= nil and st.mode == 'directory'
  end

  --- Returns the length of the file entry represented by this file.
  -- @treturn boolean the size of this file entry or 0.
  function file:length()
    local st = self:stat()
    if st ~= nil and st.mode == 'file' then
      return st.size
    end
    return 0
  end

  --- Returns last modified time of the file entry represented by this file.
  -- The time is given as the number of milliseconds since the Epoch, 1970-01-01 00:00:00 +0000 (UTC). 
  -- @treturn number the last modified time of this file entry or 0.
  function file:lastModified()
    local st = self:stat()
    if st ~= nil then
      return st.modification * 1000
    end
    return 0
  end

  --- Sets the last modified time of the file entry represented by this file.
  -- @tparam number time the last modified time or nil to set the current time.
  function file:setLastModified(time)
    if type(time) == 'number' then
      time = math.floor(time / 1000)
    else
      time = os.time()
    end
    local modificationTimeInSec = time
    local accessTimeInSec = time
    --[[
    local st = self:stat()
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
  -- @param dest the new name of this file as a File or a string.
  -- @treturn boolean true if the file is renamed.
  -- In case of error, it returns nil, plus a string describing the error and the error code.
  function file:renameTo(dest)
    if type(dest) == 'string' then
      dest = File:new(dest)
    end
    return fs.rename(self.npath, dest.npath)
  end

  --- Deletes this file entry.
  -- This file may points to a file or an empty directory.
  -- @treturn boolean true if the file entry is deleted.
  function file:delete()
    local st = self:stat()
    if st == nil then
      return true
    end
    if st.mode == 'directory' then
      return fs.rmdir(self.npath)
    end
    return fs.unlink(self.npath)
  end

  function file:deleteAll()
    local files = self:listFiles()
    if not files then
      return false
    end
    for _, f in ipairs(files) do
      if f:isDirectory() then
        if not f:deleteAll() then
          return false
        end
      end
      if not f:delete() then
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

  --- Returns an array of strings naming the file system entries in the directory represented by this file.
  -- @treturn table An array of strings naming the file system entries or nil.
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
  -- @tparam[opt] function filter a filter function that will be called on each file.
  -- @treturn table An array of files or nil.
  function file:listFiles(filter)
    local filenames = self:list()
    if not filenames then
      return nil
    end
    local files = {}
    for _, filename in ipairs(filenames) do
      local e = File:new(self.path, filename)
      if not filter or filter(e) then
        table.insert(files, e)
      end
    end
    return files
  end

  function file:forEachFile(fn, recursive, filter)
    local files = self:listFiles()
    if files then
      for _, f in ipairs(files) do
        local r
        if recursive and f:isDirectory() then
          r = f:forEachFile(fn, recursive, filter)
        elseif not filter or filter(f) then
          r = fn(self, f)
        end
        if r then
          return r
        end
      end
    end
  end

  -- listRoots() getFreeSpace() getTotalSpace() getUsableSpace()

  -- Returns the lines of this file.
  -- @treturn table an array containing all the line of this file.
  function file:readAllLines()
    local t = {}
    for line in io.lines(self.npath) do
      table.insert(t, line)
    end
    return t
  end

  --- Returns the content of this file.
  -- @tparam number maxSize the maximum file size to read
  -- @treturn string the content of this file or nil.
  function file:readAll(maxSize)
    local st = self:stat()
    if st == nil then
      return nil, 'File not found'
    end
    if st.mode ~= 'file' then
      return nil, 'Not a file'
    end
    if st.size == 0 then
      return ''
    end
    if st.size > (maxSize or (2^27)) then
      return nil, 'File too big'
    end
    local fd, err = FileDescriptor.openSync(self.npath)
    if not fd then
      return nil, err
    end
    local content = nil
    content = fd:readSync(st.size)
    fd:closeSync()
    return content
  end

  --- Writes the specified data into this file.
  -- @param data the data to write as a string or an array of string
  -- @tparam boolean append true to indicate that the data should be appended to this file
  function file:write(data, append)
    local fd, err = FileDescriptor.openSync(self.npath, append and 'a' or 'w')
    if not fd then
      return nil, err
    end
    if type(data) == 'string' then
      fd:writeSync(data)
    elseif type(data) == 'table' then
      for _, d in ipairs(data) do
        fd:writeSync(d)
      end
    else
      fd:writeSync(tostring(data))
    end
    fd:closeSync()
  end

  function file:copyTo(dest)
    local f = File.asFile(dest)
    return fs.copyfile(self.npath, f.npath)
  end

  -- Returns a File.
  -- @param value a file, a path or a string representing a path.
  -- @treturn jls.io.File a file.
  function File.asFile(value)
    return class.asInstance(File, value)
  end

end)
