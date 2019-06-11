--- Provide ZIP file utility.
-- ZIP files are archives that allow to store and compress multiple files.
-- @module jls.util.zip.ZipFile

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Struct = require('jls.util.Struct')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')
local LocalDateTime = require('jls.util.LocalDateTime')
local Date = require('jls.util.Date')


local ZipEntry = class.create(function(zipEntry)

  function zipEntry:initialize(name, comment, extra, fileHeader, localFileHeader)
    self.name = name
    self.comment = comment
    self.extra = extra
    self.compressedSize = 0
    self.crc = nil
    self.method = nil
    self.size = 0
    self.datetime = nil
    self.offset = 0
    self.fileHeader = fileHeader
    self.localFileHeader = localFileHeader
    if fileHeader then
      self.compressedSize = fileHeader.compressedSize
      self.crc = fileHeader.crc32
      self.method = fileHeader.compressionMethod
      self.size = fileHeader.uncompressedSize
      self.offset = fileHeader.relativeOffset
      -- MS DOS Date & Time
      -- bits: day(1 - 31), month(1 - 12), years(from 1980): 5, 4, 7 - second, minute, hour: 5, 6, 5
      local year = 1980 + ((fileHeader.lastModFileDate >> 9) & 0x007f)
      local month = ((fileHeader.lastModFileDate >> 5) & 0x000f) - 1
      local day = fileHeader.lastModFileDate & 0x001f
      local hour = (fileHeader.lastModFileTime >> 11) & 0x001f
      local min = (fileHeader.lastModFileTime >> 5) & 0x003f
      local sec = fileHeader.lastModFileTime & 0x001f
      self.datetime = LocalDateTime:new(year, month, day, hour, min, sec)
    end
  end

  function zipEntry:getFileHeader()
    return self.fileHeader
  end

  function zipEntry:getLocalFileHeader()
    return self.localFileHeader
  end

  function zipEntry:setLocalFileHeader(localFileHeader)
    self.localFileHeader = localFileHeader
    return self
  end

  function zipEntry:getName()
    return self.name
  end

  function zipEntry:getComment()
    return self.comment
  end

  function zipEntry:getExtra()
    return self.extra
  end

  function zipEntry:getDatetime()
    return self.datetime
  end

  function zipEntry:isDirectory()
    return string.find(self.name, '/$')
  end

  function zipEntry:getMethod()
    return self.method
  end

  function zipEntry:getCompressedSize()
    return self.compressedSize
  end

  function zipEntry:getOffset()
    return self.offset
  end

  function zipEntry:setOffset(offset)
    self.offset = offset
    return self
  end
end)

--- The ZipFile class.
-- A ZipFile instance represents a ZIP file.
return class.create(function(zipFile, _, ZipFile)

  ZipFile.ZipEntry = ZipEntry

  ZipFile.CONSTANT = {
    COMPRESSION_METHOD_STORED = 0,
    COMPRESSION_METHOD_DEFLATED = 8,
    GENERAL_PURPOSE_DEFLATE_MASK = 6,
    GENERAL_PURPOSE_DEFLATE_NORMAL = 0,
    GENERAL_PURPOSE_DEFLATE_MAXIMUM = 2,
    GENERAL_PURPOSE_DEFLATE_FAST = 4,
    GENERAL_PURPOSE_DEFLATE_SUPER_FAST = 6,
    GENERAL_PURPOSE_DATA_DESCRIPTOR = 8,
    GENERAL_PURPOSE_LANGUAGE_ENCODING = 0x0800,
    LOCAL_FILE_HEADER_SIGNATURE = 0x04034b50,
    FILE_HEADER_SIGNATURE = 0x02014b50,
    END_CENTRAL_DIR_SIGNATURE = 0x06054b50
  }

  ZipFile.STRUCT = {
    EndOfCentralDirectoryRecord = Struct:new({
      {name = 'signature', type = 'UnsignedInt'},
      {name = 'diskNumber', type = 'UnsignedShort'},
      {name = 'centralDirectoryDiskNumber', type = 'UnsignedShort'},
      {name = 'diskEntryCount', type = 'UnsignedShort'},
      {name = 'entryCount', type = 'UnsignedShort'},
      {name = 'size', type = 'UnsignedInt'},
      {name = 'offset', type = 'UnsignedInt'},
      {name = 'commentLength', type = 'UnsignedShort'}
    }, 'le'),
    DataDescriptor = Struct:new({
      {name = 'crc32', type = 'UnsignedInt'},
      {name = 'compressedSize', type = 'UnsignedInt'},
      {name = 'uncompressedSize', type = 'UnsignedInt'}
    }, 'le'),
    LocalFileHeader = Struct:new({
      {name = 'signature', type = 'UnsignedInt'},
      {name = 'versionNeeded', type = 'UnsignedShort'},
      {name = 'generalPurposeBitFlag', type = 'UnsignedShort'},
      {name = 'compressionMethod', type = 'UnsignedShort'},
      {name = 'lastModFileTime', type = 'UnsignedShort'},
      {name = 'lastModFileDate', type = 'UnsignedShort'},
      {name = 'crc32', type = 'UnsignedInt'},
      {name = 'compressedSize', type = 'UnsignedInt'},
      {name = 'uncompressedSize', type = 'UnsignedInt'},
      {name = 'filenameLength', type = 'UnsignedShort'},
      {name = 'extraFieldLength', type = 'UnsignedShort'}
    }, 'le'),
    FileHeader = Struct:new({
      {name = 'signature', type = 'UnsignedInt'},
      {name = 'versionMadeBy', type = 'UnsignedShort'},
      {name = 'versionNeeded', type = 'UnsignedShort'},
      {name = 'generalPurposeBitFlag', type = 'UnsignedShort'},
      {name = 'compressionMethod', type = 'UnsignedShort'},
      {name = 'lastModFileTime', type = 'UnsignedShort'},
      {name = 'lastModFileDate', type = 'UnsignedShort'},
      {name = 'crc32', type = 'UnsignedInt'},
      {name = 'compressedSize', type = 'UnsignedInt'},
      {name = 'uncompressedSize', type = 'UnsignedInt'},
      {name = 'filenameLength', type = 'UnsignedShort'},
      {name = 'extraFieldLength', type = 'UnsignedShort'},
      {name = 'fileCommentLength', type = 'UnsignedShort'},
      {name = 'diskNumberStart', type = 'UnsignedShort'},
      {name = 'internalFileAttributes', type = 'UnsignedShort'},
      {name = 'externalFileAttributes', type = 'UnsignedInt'},
      {name = 'relativeOffset', type = 'UnsignedInt'}
    }, 'le')
  }

  local function readEntries(fd, fileLength)
    local entries = {}
    local size = ZipFile.STRUCT.EndOfCentralDirectoryRecord:getSize()
    local offset = fileLength - size
    local header = ZipFile.STRUCT.EndOfCentralDirectoryRecord:fromString(fd:readSync(size, offset))
    if logger:isLoggable(logger.FINER) then
      logger:finer('readEntries() file length: '..tostring(fileLength))
    end
    if header.signature ~= ZipFile.CONSTANT.END_CENTRAL_DIR_SIGNATURE then
      -- the header may have a comment
      size = 1024
      offset = fileLength - size
      local buffer = fd:readSync(size, offset)
      local index = string.find(buffer, 'PK\x05\x06', 1, true)
      if index then
        offset = offset + index - 1
        header = ZipFile.STRUCT.EndOfCentralDirectoryRecord:fromString(string.sub(buffer, index))
      end
      if header.signature ~= ZipFile.CONSTANT.END_CENTRAL_DIR_SIGNATURE then
        return nil, 'Invalid zip file, Bad Central Directory Record signature (0x'..string.format('%08x', header.signature)..')'
      end
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('readEntries() EOCDR size: '..tostring(size)..' offset: '..tostring(offset))
    end
    local entryCount = header.entryCount
    size = ZipFile.STRUCT.FileHeader:getSize()
    offset = header.offset
    if logger:isLoggable(logger.FINER) then
      logger:finer('readEntries() offset: '..tostring(offset)..' entry count: '..tostring(entryCount)..' FileHeader size: '..tostring(size))
    end
    for i = 1, entryCount do
      local fileHeader = ZipFile.STRUCT.FileHeader:fromString(fd:readSync(size, offset))
      if fileHeader.signature ~= ZipFile.CONSTANT.FILE_HEADER_SIGNATURE then
        return nil, 'Invalid zip file, Bad File Header signature (0x'..string.format('%08x', fileHeader.signature)..') for entry '..tostring(i)
      end
      offset = offset + size
      local filename = ''
      if fileHeader.filenameLength > 0 then
        filename = fd:readSync(fileHeader.filenameLength, offset) -- UTF-8 filename
        offset = offset + fileHeader.filenameLength
      end
      offset = offset + fileHeader.extraFieldLength
      local comment = ''
      if fileHeader.fileCommentLength > 0 then
        comment = fd:readSync(fileHeader.fileCommentLength, offset) -- UTF-8 comment
        offset = offset + fileHeader.fileCommentLength
      end
      local entry = ZipEntry:new(filename, comment, nil, fileHeader)
      table.insert(entries, entry)
      --entries[filename] = entry
      if logger:isLoggable(logger.FINER) then
        logger:finer('readEntries() entry: '..tostring(i)..' offset: '..tostring(offset)..' filename: #'..tostring(fileHeader.filenameLength)..' comment: #'..tostring(fileHeader.fileCommentLength))
      end
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('readEntries() entries: #'..tostring(#entries)..' entry count: '..tostring(entryCount))
    end
    return entries, entryCount, header
  end

  --- Creates a new ZipFile with the specified file or filename.
  -- @function ZipFile:new
  function zipFile:initialize(file)
    local f = File.asFile(file)
    local fd, entries, err
    if f:isFile() then
      fd = FileDescriptor.openSync(f)
      entries, err = readEntries(fd, f:length())
      if not entries then
        fd:closeSync()
        error(err)
      end
    else
      fd = FileDescriptor.openSync(f, 'w')
      entries = {}
      self.offset = 0
      self.writable = true
    end
    self.fd = fd
    self.entries = entries
  end

  --- Closes this ZIP file
  function zipFile:close()
    if self.writable then
      for _, entry in ipairs(self.entries) do
        local name = entry:getName() or ''
        local extra = entry:getExtra() or ''
        local comment = entry:getComment() or ''
        local localFileHeader = entry:getLocalFileHeader()
        local fileHeader = {
          signature = ZipFile.CONSTANT.FILE_HEADER_SIGNATURE,
          relativeOffset = entry:getOffset() or 0,
          fileCommentLength = #comment
        }
        for k, v in pairs(localFileHeader) do
          if not fileHeader[k] then
            fileHeader[k] = v
          end
        end
        local rawFileHeader = ZipFile.STRUCT.FileHeader:toString(fileHeader)
        fd:writeSync(rawFileHeader)
        fd:writeSync(name)
        if extra and #extra > 0 then
          fd:writeSync(extra)
        end
        if comment and #comment > 0 then
          fd:writeSync(comment)
        end
      end
      local rawEOCDR = ZipFile.STRUCT.EndOfCentralDirectoryRecord:toString({
        signature = ZipFile.CONSTANT.END_CENTRAL_DIR_SIGNATURE,
        entryCount = #self.entries,
        offset = self.offset
      })
      fd:writeSync(rawEOCDR)
    end
    if self.fd then
      self.fd:closeSync()
      self.fd = nil
    end
    self.entries = {}
  end

  --- Returns the entries of this ZIP file.
  -- @treturn table the entries.
  function zipFile:getEntries()
    return self.entries
  end

  function zipFile:addFile(file, name, comment, extra)
    local f = File.asFile(file)
    local date = Date:new(f:lastModified())
    local lastModFileDate = (date:getYear() - 1980) << 9 + (date:getMonth()) << 5 + date:getDay()
    local lastModFileTime = date:getHours() << 11 + date:getMinutes() << 5 + date:getSeconds()
    name = name or f:getName()
    local entry = ZipEntry:new(name, comment, extra)
    local rawContent
    if f:isDirectory() then
      rawContent = ''
      name = name + '/'
    else
      rawContent = f:readAll()
    end
    local uncompressedSize = #rawContent
    local method = ZipFile.CONSTANT.COMPRESSION_METHOD_STORED
    if uncompressedSize > 200 then
      method = ZipFile.CONSTANT.COMPRESSION_METHOD_DEFLATED
      local deflater = Deflater:new(nil, -15)
      rawContent = deflater:deflate(rawContent, 'finish')
    end
    local crc32 = 0
    -- TODO Compute crc32
    extra = extra or ''
    local localFileHeader = {
      signature = ZipFile.CONSTANT.LOCAL_FILE_HEADER_SIGNATURE,
      compressionMethod = method,
      lastModFileTime = lastModFileTime,
      lastModFileDate = lastModFileDate,
      crc32 = crc32,
      compressedSize = #rawContent,
      uncompressedSize = uncompressedSize,
      filenameLength = #name,
      extraFieldLength = #extra,
    }
    entry:setOffset(self.offset)
    entry:setLocalFileHeader(localFileHeader)
    local rawLocalFileHeader = ZipFile.STRUCT.LocalFileHeader:toString(localFileHeader)
    fd:writeSync(name)
    if extra and #extra > 0 then
      fd:writeSync(extra)
    end
    if uncompressedSize > 0 then
      fd:writeSync(rawContent)
    end
    self.offset = self.offset + ZipFile.STRUCT.LocalFileHeader:getSize() + #name + #extra + #rawContent
    table.insert(self.entries, entry)
  end

  --- Returns the entry for the specified name.
  -- @tparam string name the entry name
  -- @return the entry
  function zipFile:getEntry(name)
    for i, entry in ipairs(self.entries) do
      if entry.name == name then
        return entry, i
      end
    end
    return nil
  end

  function zipFile:hasEntry(name)
    if self:getEntry(name) then
      return true
    end
    return false
  end

  function zipFile:readLocalFileHeader(entry)
    if not entry then
      return nil, 'Invalid entry'
    end
    local offset = entry:getOffset()
    local size = ZipFile.STRUCT.LocalFileHeader:getSize()
    local rawHeader = self.fd:readSync(size, offset)
    local localFileHeader = ZipFile.STRUCT.LocalFileHeader:fromString(rawHeader)
    if localFileHeader.signature ~= ZipFile.CONSTANT.LOCAL_FILE_HEADER_SIGNATURE then
      return nil, 'Invalid zip file, Bad Local File Header signature'
    end
    offset = offset + size + localFileHeader.filenameLength + localFileHeader.extraFieldLength
    return localFileHeader, offset
  end

  function zipFile:readSyncRawContent(entry)
    local localFileHeader, offset = self:readLocalFileHeader(entry)
    if not localFileHeader then
      return nil, offset or 'Cannot read LocalFileHeader'
    end
    local rawContent = self.fd:readSync(localFileHeader.compressedSize, offset)
    return rawContent, localFileHeader
  end

  function zipFile:readRawContent(entry, callback)
    local localFileHeader, offset = self:readLocalFileHeader(entry)
    if not localFileHeader then
      callback(nil, offset or 'Cannot read LocalFileHeader')
      return
    end
    local bufferSize = 4096
    local endOffset = offset + localFileHeader.compressedSize
    while offset < endOffset do
      local nextOffset = offset + bufferSize
      if nextOffset >= endOffset then
        bufferSize = endOffset - offset
      end
      local data = self.fd:readSync(bufferSize, offset)
      callback(data)
      offset = nextOffset
    end
    callback('')
  end

  --- Returns the content of the specified entry.
  -- @param entry the entry
  -- @treturn string the entry content
  function zipFile:getContentSync(entry)
    local rawContent, err = self:readSyncRawContent(entry)
    if not rawContent then
      return nil, err
    end
    if entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_STORED then
      return rawContent
    elseif entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_DEFLATED then
      local inflater = Inflater:new(-15)
      return inflater:inflate(rawContent)
    else
      return nil, 'Unsupported method ('..tostring(entry:getMethod())..')'
    end
  end

  --- Returns the content of the specified entry.
  -- @param entry the entry
  -- @treturn string the entry content
  function zipFile:getContent(entry, callback)
    if not callback then
      return self:getContentSync(entry)
    end
    if entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_STORED then
      self:readRawContent(entry, callback)
    elseif entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_DEFLATED then
      local inflater = Inflater:new(-15)
      local cb = callback
      callback = 
      self:readRawContent(entry, function(data, err)
        if err then
          callback(nil, err)
        else
          callback(inflater:inflate(data))
        end
      end)
    else
      callback(nil, 'Unsupported method ('..tostring(entry:getMethod())..')')
    end
  end

  function ZipFile.unzipTo(file, directory)
    --local fil = File.asFile(file)
    local dir = File.asFile(directory)
    if not dir:isDirectory() then
      return false, 'The specified directory is invalid'
    end
    local err = nil
    local zFile = ZipFile:new(file)
    for _, entry in ipairs(zFile:getEntries()) do
      logger:info('unzip entry "'..entry:getName()..'"')
      local entryFile = File:new(dir, entry:getName())
      if entry:isDirectory() then
        if not entryFile:isDirectory() then
          if not entryFile:mkdirs() then
            err = 'Cannot create directory'
            break
          end
        end
      else
        local parent = entryFile:getParentFile()
        if parent and not parent:isDirectory() then
          if not parent:mkdirs() then
            err = 'Cannot create directory'
            break
          end
        end
        local content = zFile:getContent(entry)
        if content then
          entryFile:write(content)
        end
        --[[
        local dt = entry:getDatetime()
        local date = Date.fromLocalDateTime(dt)
        entryFile:setLastModified(date:getTime())
        ]]
      end
    end
    zFile:close()
    return not err, err
  end

  local function addFiles(zFile, path, files)
    for _, file in ipairs(files) do
      local name = path..file:getName()
      zFile:addFile(file, name)
      if file:isDirectory() then
        addFiles(zFile, name..'/', file:listFiles())
      end
    end
  end

  function ZipFile.zipTo(file, directoryOrfiles, path)
    if class.isInstanceOf(directoryOrfiles, File) then
      if directoryOrfiles:isDirectory() then
        return ZipFile.zipTo(file, directoryOrfiles:listFiles())
      end
      return ZipFile.zipTo(file, {directoryOrfiles})
    end
    local zFile = ZipFile:new(file)
    addFiles(zFile, path or '', directoryOrfiles)
    zFile:close()
  end
end)

