local FileStreamHandler = require('jls.io.streams.FileStreamHandler')

local function getFileMetadata(file, name)
  return {
    isDir = file:isDirectory(),
    size = file:length(),
    time = file:lastModified(),
    name = name,
  }
end

return require('jls.lang.class').create(function(fileSystem)

  function fileSystem:initialize()
  end

  function fileSystem:getFileMetadata(exchange, file)
    if file:exists() then
      return getFileMetadata(file)
    end
  end

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

  function fileSystem:createDirectory(exchange, file)
    return file:mkdir()
  end

  function fileSystem:copyFile(exchange, file, destFile)
    return file:copyTo(destFile)
  end

  function fileSystem:renameFile(exchange, file, destFile)
    return file:renameTo(destFile)
  end

  function fileSystem:deleteFile(exchange, file, recursive)
    if recursive then
      return file:deleteRecursive()
    end
    return file:delete()
  end

  function fileSystem:setFileStreamHandler(exchange, file, sh, md, offset, length)
    FileStreamHandler.read(file, sh, offset, length)
  end

  function fileSystem:getFileStreamHandler(exchange, file, time)
    return FileStreamHandler:new(file, true, function()
      file:setLastModified(time)
    end, nil, true)
  end

end)
