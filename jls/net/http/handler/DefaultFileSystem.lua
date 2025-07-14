--- File system API for HTTP file handler.
-- It exposes the File APIs with the associated HTTP exchange.
-- @module jls.net.http.handler.DefaultFileSystem
-- @pragma nostrip

local FileStreamHandler = require('jls.io.streams.FileStreamHandler')

local function getFileMetadata(file, name)
  return {
    isDir = file:isDirectory(),
    size = file:length(),
    time = file:lastModified(),
    name = name,
  }
end

--- A DefaultFileSystem class.
-- @type DefaultFileSystem
return require('jls.lang.class').create(function(fileSystem)

  --- Creates a DefaultFileSystem.
  -- @function DefaultFileSystem:new
  function fileSystem:initialize()
  end

  --- Returns the metadata for the specified file.
  -- The metadata consists in a table with the key-values: size, time, isDir and name.
  -- @tparam HttpExchange exchange the HTTP exchange
  -- @tparam File file The file
  -- @return the file metadata
  function fileSystem:getFileMetadata(exchange, file)
    if file:exists() then
      return getFileMetadata(file)
    end
  end

  --- Returns the list of file metadata for the specified directory.
  -- @tparam HttpExchange exchange the HTTP exchange
  -- @tparam File dir The directory
  -- @return the list of file metadata
  function fileSystem:listFileMetadata(exchange, dir)
    local files = {}
    for _, file in ipairs(dir:listFiles()) do
      local name = file:getName()
      if string.find(name, '^[^%.]') then
        table.insert(files, getFileMetadata(file, name))
      end
    end
    return files
  end

  --- Creates the specified directory.
  -- @tparam HttpExchange exchange the HTTP exchange
  -- @tparam File dir The directory
  -- @treturn boolean true if the directory is created
  function fileSystem:createDirectory(exchange, dir)
    return dir:mkdir()
  end

  --- Copies the specified file to a destination file.
  -- @tparam HttpExchange exchange the HTTP exchange
  -- @tparam File file The file to copy from
  -- @tparam File destFile The file to copy to
  -- @treturn boolean true if the file is copied
  function fileSystem:copyFile(exchange, file, destFile)
    return file:copyTo(destFile)
  end

  --- Renames the specified file to a destination file.
  -- @tparam HttpExchange exchange the HTTP exchange
  -- @tparam File file The file to rename from
  -- @tparam File destFile The file to rename to
  -- @treturn boolean true if the file is copied
  function fileSystem:renameFile(exchange, file, destFile)
    return file:renameTo(destFile)
  end

  --- Deletes the specified file.
  -- @tparam HttpExchange exchange the HTTP exchange
  -- @tparam File file The file to delete
  -- @tparam boolean recursive true to delete the sub files and directories
  -- @treturn boolean true if the file is deleted
  function fileSystem:deleteFile(exchange, file, recursive)
    if recursive then
      return file:deleteRecursive()
    end
    return file:delete()
  end

  --- Applies the specified stream handler to a file.
  -- @tparam HttpExchange exchange the HTTP exchange
  -- @tparam File file The file to read from
  -- @tparam StreamHandler sh The stream handler to use
  -- @tparam number md the file metadata
  -- @tparam number offset the offset to read from
  -- @tparam number length the length to read
  function fileSystem:setFileStreamHandler(exchange, file, sh, md, offset, length)
    FileStreamHandler.read(file, sh, offset, length)
  end

  --- Returns a stream handler for a file.
  -- @tparam HttpExchange exchange the HTTP exchange
  -- @tparam File file The file to write to
  -- @tparam number time the last modification time
  -- @treturn StreamHandler the stream handler
  function fileSystem:getFileStreamHandler(exchange, file, time)
    return FileStreamHandler:new(file, true, function()
      file:setLastModified(time)
    end, nil, true)
  end

end)
