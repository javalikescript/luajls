--- Provide ZIP file utility.
-- ZIP files are archives that allow to store and compress multiple files.
-- The goal is to provide a minimal implementation compatible with the ZIP format.
-- The file storage methods are deflated and stored.
-- The encryption and multiple volumes features are not supported.
-- Note that CRC32 is not verified.
-- @module jls.util.zip.ZipFile
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local StreamHandler = require('jls.io.StreamHandler')
local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')
local LocalDateTime = require('jls.util.LocalDateTime')
local Date = require('jls.util.Date')
local Struct = require('jls.util.Struct')
local MessageDigest = require('jls.util.MessageDigest')
local inflateStream = require('jls.util.cd.deflate').decodeStream -- Inflater.inflateStream


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
      local month = (fileHeader.lastModFileDate >> 5) & 0x000f
      local day = fileHeader.lastModFileDate & 0x001f
      local hour = (fileHeader.lastModFileTime >> 11) & 0x001f
      local min = (fileHeader.lastModFileTime >> 5) & 0x003f
      local sec = (fileHeader.lastModFileTime & 0x001f) * 2
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

  function zipEntry:getCrc32()
    return self.crc
  end

  function zipEntry:getSize()
    return self.size
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
-- @type ZipFile
return class.create(function(zipFile, _, ZipFile)

  ZipFile._Struct = Struct

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
      {name = 'signature', type = 'I4'},
      {name = 'diskNumber', type = 'I2'},
      {name = 'centralDirectoryDiskNumber', type = 'I2'},
      {name = 'diskEntryCount', type = 'I2'},
      {name = 'entryCount', type = 'I2'},
      {name = 'size', type = 'I4'},
      {name = 'offset', type = 'I4'},
      {name = 'commentLength', type = 'I2'}
    }, '<'),
    DataDescriptor = Struct:new({
      {name = 'crc32', type = 'I4'},
      {name = 'compressedSize', type = 'I4'},
      {name = 'uncompressedSize', type = 'I4'}
    }, '<'),
    LocalFileHeader = Struct:new({
      {name = 'signature', type = 'I4'},
      {name = 'versionNeeded', type = 'I2'},
      {name = 'generalPurposeBitFlag', type = 'I2'},
      {name = 'compressionMethod', type = 'I2'},
      {name = 'lastModFileTime', type = 'I2'},
      {name = 'lastModFileDate', type = 'I2'},
      {name = 'crc32', type = 'I4'},
      {name = 'compressedSize', type = 'I4'},
      {name = 'uncompressedSize', type = 'I4'},
      {name = 'filenameLength', type = 'I2'},
      {name = 'extraFieldLength', type = 'I2'}
    }, '<'),
    FileHeader = Struct:new({
      {name = 'signature', type = 'I4'},
      {name = 'versionMadeBy', type = 'I2'},
      {name = 'versionNeeded', type = 'I2'},
      {name = 'generalPurposeBitFlag', type = 'I2'},
      {name = 'compressionMethod', type = 'I2'},
      {name = 'lastModFileTime', type = 'I2'},
      {name = 'lastModFileDate', type = 'I2'},
      {name = 'crc32', type = 'I4'},
      {name = 'compressedSize', type = 'I4'},
      {name = 'uncompressedSize', type = 'I4'},
      {name = 'filenameLength', type = 'I2'},
      {name = 'extraFieldLength', type = 'I2'},
      {name = 'fileCommentLength', type = 'I2'},
      {name = 'diskNumberStart', type = 'I2'},
      {name = 'internalFileAttributes', type = 'I2'},
      {name = 'externalFileAttributes', type = 'I4'},
      {name = 'relativeOffset', type = 'I4'}
    }, '<')
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
      if logger:isLoggable(logger.FINER) then
        logger:finer('readEntries() bad Central Directory Record signature, searching at '..tostring(offset))
      end
      local buffer = fd:readSync(size, offset)
      local index = string.find(buffer, 'PK\x05\x06', 1, true)
      if index then
        offset = offset + index - 1
        header = ZipFile.STRUCT.EndOfCentralDirectoryRecord:fromString(string.sub(buffer, index))
      end
      if header.signature ~= ZipFile.CONSTANT.END_CENTRAL_DIR_SIGNATURE then
        return nil, 'Invalid zip file, bad Central Directory Record signature (0x'..string.format('%08x', header.signature)..')'
      end
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('readEntries() EOCDR size: '..tostring(size)..' offset: '..tostring(offset))
      if logger:isLoggable(logger.FINEST) then
        logger:finest('eocdRecord: '..require('jls.util.tables').stringify(header, 2))
      end
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
      if logger:isLoggable(logger.FINEST) then
        logger:finest('FileHeader: '..require('jls.util.tables').stringify(fileHeader, 2))
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
        logger:finer('readEntries() entry: '..tostring(i)..' at: '..tostring(offset)..' filename: '..filename..' offset: '..tostring(entry:getOffset())..' comment: #'..tostring(fileHeader.fileCommentLength))
      end
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('readEntries() entries: #'..tostring(#entries)..' entry count: '..tostring(entryCount))
    end
    return entries, entryCount, header
  end

  --- Creates a new ZipFile with the specified file or filename.
  -- @tparam File file the zip file.
  -- @tparam[opt] boolean create true to indicate that the zip file shall be created
  -- @tparam[opt] boolean overwrite true to indicate that the zip file shall be overwrited
  -- @function ZipFile:new
  function zipFile:initialize(file, create, overwrite)
    local f = File.asFile(file)
    if create == nil then
      create = not f:exists()
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('ZipFile:new("'..f:getPath()..'", '..tostring(create)..', '..tostring(overwrite)..')')
    end
    local fd, entries, err
    if create then
      if not overwrite and f:exists() then
        error('The zip file "'..f:getPath()..'" exists')
      end
      fd, err = FileDescriptor.openSync(f, 'w')
      entries = {}
      self.offset = 0
      self.writable = true
    elseif not f:isFile() then
      error('The zip file "'..f:getPath()..'" does not exist')
    else
      fd, err = FileDescriptor.openSync(f)
      if fd then
        entries, err = readEntries(fd, f:length())
        if entries then
          err = nil
        else
          fd:closeSync()
        end
      end
    end
    if err then
      logger:warn('ZipFile:new("'..f:getPath()..'", '..tostring(create)..') err: "'..tostring(err)..'"')
      error(err)
    end
    self.fd = fd
    self.entries = entries
  end

  --- Closes this ZIP file
  function zipFile:close()
    if logger:isLoggable(logger.FINER) then
      logger:finest('zipFile:close()')
    end
    if self.writable then
      if logger:isLoggable(logger.FINER) then
        logger:finer('writing '..tostring(#self.entries)..' entries at '..tostring(self.offset))
      end
      local startOffset = self.offset
      local size = 0
      for _, entry in ipairs(self.entries) do
        local name = entry:getName() or ''
        if logger:isLoggable(logger.FINER) then
          logger:finest('writing entry "'..name..'" at '..tostring(startOffset + size))
        end
        local extra = entry:getExtra() or ''
        local comment = entry:getComment() or ''
        local localFileHeader = entry:getLocalFileHeader()
        local fileHeader = {
          signature = ZipFile.CONSTANT.FILE_HEADER_SIGNATURE,
          --versionMadeBy = 0, -- MS-DOS and can be read by PKZIP
          versionNeeded = 20,
          internalFileAttributes = localFileHeader.compressedSize == 0 and 0 or 1,
          --externalFileAttributes = 0,
          relativeOffset = entry:getOffset() or 0,
          fileCommentLength = #comment
        }
        for k, v in pairs(localFileHeader) do
          if not fileHeader[k] then
            fileHeader[k] = v
          end
        end
        if logger:isLoggable(logger.FINEST) then
          logger:finest('FileHeader: '..require('jls.util.tables').stringify(fileHeader, 2))
        end
          local rawFileHeader = ZipFile.STRUCT.FileHeader:toString(fileHeader)
        self.fd:writeSync(rawFileHeader)
        self.fd:writeSync(name)
        if #extra > 0 then
          self.fd:writeSync(extra)
        end
        if #comment > 0 then
          self.fd:writeSync(comment)
        end
        size = size + ZipFile.STRUCT.FileHeader:getSize() + #name + #extra + #comment
      end
      local eocdRecord = {
        signature = ZipFile.CONSTANT.END_CENTRAL_DIR_SIGNATURE,
        entryCount = #self.entries,
        diskEntryCount = #self.entries,
        offset = startOffset,
        size = size
      }
      if logger:isLoggable(logger.FINEST) then
        logger:finest('EndOfCentralDirectoryRecord: '..require('jls.util.tables').stringify(eocdRecord, 2))
      end
      local rawEOCDR = ZipFile.STRUCT.EndOfCentralDirectoryRecord:toString(eocdRecord)
      self.fd:writeSync(rawEOCDR)
      self.offset = self.offset + size + ZipFile.STRUCT.EndOfCentralDirectoryRecord:getSize()
      if logger:isLoggable(logger.FINER) then
        logger:finer('writing EndOfCentralDirectoryRecord of size '..tostring(size)..' total file size '..tostring(self.offset))
        if logger:isLoggable(logger.FINEST) then
          for k, v in pairs(ZipFile.STRUCT) do
            logger:finest(k..' size: '..tostring(v:getSize()))
          end
        end
      end
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

  local function readFileBlocks(file, md, deflater, blockSize)
    blockSize = blockSize or 1024
    local fd, err = FileDescriptor.openSync(file)
    if not fd then
      return nil, err
    end
    local blocks = {}
    local data
    local size = 0
    local dsize = 0
    while true do
      data, err = fd:readSync(blockSize)
      if err then
        fd:closeSync()
        return nil, err
      elseif data then
        size = size + #data
        if md then
          md:update(data)
        end
        if deflater then
          data = deflater:deflate(data)
          dsize = dsize + #data
        end
        table.insert(blocks, data)
      else
        if deflater then
          data = deflater:finish()
          dsize = dsize + #data
          table.insert(blocks, data)
        else
          dsize = size
        end
        break
      end
    end
    fd:closeSync()
    return blocks, size, dsize
  end

  function zipFile:addFile(file, name, comment, extra)
    local f = File.asFile(file)
    if logger:isLoggable(logger.FINER) then
      logger:finer('zipFile:addFile("%s", "%s")', f:getName(), name)
    end
    local date = Date:new(f:lastModified())
    local lastModFileDate = (math.max(date:getYear() - 1980, 0) << 9) | ((date:getMonth()) << 5) | date:getDay()
    local lastModFileTime = (date:getHours() << 11) | (date:getMinutes() << 5) | (date:getSeconds() // 2)
    name = name or f:getName()
    local uncompressedSize = f:length()
    local compressedSize = 0
    local crc32 = 0
    local method = ZipFile.CONSTANT.COMPRESSION_METHOD_STORED
    local blocks = {}
    if f:isDirectory() then
      name = name..'/'
    elseif uncompressedSize > 0 then
      local md = MessageDigest:new('Crc32')
      local d
      if uncompressedSize > 200 then
        method = ZipFile.CONSTANT.COMPRESSION_METHOD_DEFLATED
        d = Deflater:new(nil, -15)
      end
      blocks, uncompressedSize, compressedSize = readFileBlocks(f, md, d, 4096)
      crc32 = md:finish()
      logger:finer('crc32 for "%s" is %d', name, crc32)
    end
    local entry = ZipEntry:new(name, comment, extra)
    extra = extra or ''
    local localFileHeader = {
      signature = ZipFile.CONSTANT.LOCAL_FILE_HEADER_SIGNATURE,
      --versionNeeded = 0, -- TODO Check
      compressionMethod = method,
      lastModFileTime = lastModFileTime,
      lastModFileDate = lastModFileDate,
      crc32 = crc32,
      compressedSize = compressedSize,
      uncompressedSize = uncompressedSize,
      filenameLength = #name,
      extraFieldLength = #extra,
    }
    if logger:isLoggable(logger.FINEST) then
      logger:finest('localFileHeader: '..require('jls.util.tables').stringify(localFileHeader, 2))
    end
    entry:setOffset(self.offset)
    entry:setLocalFileHeader(localFileHeader)
    local rawLocalFileHeader = ZipFile.STRUCT.LocalFileHeader:toString(localFileHeader)
    self.fd:writeSync(rawLocalFileHeader)
    self.fd:writeSync(name)
    if #extra > 0 then
      self.fd:writeSync(extra)
    end
    if compressedSize > 0 then
      self.fd:writeSync(blocks)
    end
    self.offset = self.offset + ZipFile.STRUCT.LocalFileHeader:getSize() + #name + #extra + compressedSize
    table.insert(self.entries, entry)
    if logger:isLoggable(logger.FINER) then
      logger:finer('added at '..tostring(entry:getOffset())..'-'..tostring(self.offset)..', '..tostring(#self.entries)..' entries')
    end
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
    if logger:isLoggable(logger.FINEST) then
      logger:finest('localFileHeader: '..require('jls.util.tables').stringify(localFileHeader, 2))
    end
    offset = offset + size + localFileHeader.filenameLength + localFileHeader.extraFieldLength
    return localFileHeader, offset
  end

  function zipFile:readRawContentAll(entry)
    local localFileHeader, offset = self:readLocalFileHeader(entry)
    if not localFileHeader then
      return nil, offset or 'Cannot read LocalFileHeader'
    end
    local rawContent, err = self.fd:readSync(localFileHeader.compressedSize, offset)
    if not rawContent then
      return nil, err or 'Cannot read raw content'
    end
    return rawContent, localFileHeader
  end

  function zipFile:readRawContentParts(entry, stream, async)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('readRawContentParts("'..entry:getName()..'", ?, '..tostring(async)..')')
    end
    local callback = StreamHandler.ensureCallback(stream)
    local localFileHeader, offset = self:readLocalFileHeader(entry)
    if not localFileHeader then
      callback(offset or 'Cannot read LocalFileHeader')
      return
    end
    local uncompressedSize = localFileHeader.uncompressedSize > 0 and localFileHeader.uncompressedSize or entry:getSize()
    local compressedSize = localFileHeader.compressedSize > 0 and localFileHeader.compressedSize or entry:getCompressedSize()
    local ratio = math.max(1, math.min(8, uncompressedSize // compressedSize))
    local bufferSize = 4096 // ratio
    if logger:isLoggable(logger.FINER) then
      logger:finer('readRawContentParts("'..entry:getName()..'") size: '..tostring(compressedSize)..'->'..tostring(uncompressedSize)..', with buffer '..tostring(bufferSize))
    end
    local endOffset = offset + compressedSize
    if async then
      local function readCallback(err, data)
        if err then
          callback(err)
        else
          if data then
            if callback(nil, data) == false then
              return
            end
          end
          if offset < endOffset then
            local nextOffset = offset + bufferSize
            if nextOffset >= endOffset then
              bufferSize = endOffset - offset
            end
            if logger:isLoggable(logger.FINER) then
              logger:finer('readRawContentParts("'..entry:getName()..'") read #'..tostring(bufferSize)..' at '..tostring(offset))
            end
            self.fd:read(bufferSize, offset, readCallback)
            offset = nextOffset
          else
            callback()
          end
        end
      end
      readCallback()
    else
      while offset < endOffset do
        local nextOffset = offset + bufferSize
        if nextOffset >= endOffset then
          bufferSize = endOffset - offset
        end
        if logger:isLoggable(logger.FINER) then
          logger:finer('readRawContentParts("'..entry:getName()..'") read #'..tostring(bufferSize)..' at '..tostring(offset))
        end
        local data = self.fd:readSync(bufferSize, offset)
        callback(nil, data)
        offset = nextOffset
      end
      callback()
    end
  end

  local INFLATER_WINDOW_BITS = -15

  --- Returns the content of the specified entry.
  -- @param entry the entry
  -- @treturn string the entry content
  function zipFile:getContentSync(entry)
    local rawContent, err = self:readRawContentAll(entry)
    if not rawContent then
      return nil, err
    end
    if entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_STORED then
      return rawContent
    elseif entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_DEFLATED then
      local inflater = Inflater:new(INFLATER_WINDOW_BITS)
      return inflater:inflate(rawContent)
    else
      return nil, 'Unsupported method ('..tostring(entry:getMethod())..')'
    end
  end

  --- Returns the content of the specified entry.
  -- @param entry the entry
  -- @tparam[opt] StreamHandler stream an optional @{jls.io.StreamHandler} that will be called with the content.
  -- @tparam[opt] boolean async true to get the consent asynchronously.
  -- @treturn string the entry content
  function zipFile:getContent(entry, stream, async)
    if logger:isLoggable(logger.FINE) then
      logger:fine('getContent("%s")', entry:getName())
    end
    if not stream then
      return self:getContentSync(entry)
    end
    if entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_STORED then
      self:readRawContentParts(entry, stream, async)
    elseif entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_DEFLATED then
      self:readRawContentParts(entry, inflateStream(stream, INFLATER_WINDOW_BITS), async)
    else
      stream:onError('Unsupported method ('..tostring(entry:getMethod())..')')
    end
  end

  local function keepFileName(name, entry)
    return name
  end

  local function newRemoveRootFileName(rootName)
    return function(name)
      local basename, path = string.match(name, '^([^/]+)/?(.*)$')
      if rootName then
        if basename ~= rootName then
          return nil
        end
      else
        rootName = basename
      end
      if path and path ~= '' then
        return path
      end
    end
  end

  ZipFile.fileNameAdapter = {
    default = keepFileName,
    newRemoveRoot = newRemoveRootFileName
  }

  function ZipFile.unzipToSync(file, directory, adaptFileName)
    if logger:isLoggable(logger.FINER) then
      logger:finer('ZipFile.unzipToSync()')
    end
    --local fil = File.asFile(file)
    local dir = File.asFile(directory)
    if not dir:isDirectory() then
      return false, 'The specified directory is invalid'
    end
    if type(adaptFileName) ~= 'function' then
      adaptFileName = keepFileName
    end
    local err = nil
    local zFile = ZipFile:new(file, false)
    for _, entry in ipairs(zFile:getEntries()) do
      local name = adaptFileName(entry:getName(), entry)
      if name then
        if logger:isLoggable(logger.FINE) then
          logger:fine('unzip entry "'..name..'"')
        end
        local entryFile = File:new(dir, name)
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
          local content = zFile:getContentSync(entry)
          if content then
            entryFile:write(content)
          end
          local dt = entry:getDatetime()
          local date = Date.fromLocalDateTime(dt)
          entryFile:setLastModified(date:getTime())
        end
      else
        if logger:isLoggable(logger.FINE) then
          logger:fine('skipping entry "'..entry:getName()..'"')
        end
      end
    end
    zFile:close()
    return not err, err
  end

  local function asFiles(directoryOrFiles)
    if type(directoryOrFiles) == 'string' then
      return {File.asFile(directoryOrFiles)}
    elseif File:isInstance(directoryOrFiles) then
      if directoryOrFiles:isDirectory() then
        return directoryOrFiles:listFiles()
      else
        return {directoryOrFiles}
      end
    elseif type(directoryOrFiles) == 'table' then
      return directoryOrFiles
    end
    error('Invalid files')
  end

  local function forEachFiles(path, files, fn)
    for _, file in ipairs(files) do
      local name = path..file:getName()
      fn(file, name)
      if file:isDirectory() then
        forEachFiles(name..'/', file:listFiles(), fn)
      end
    end
  end

  function ZipFile.zipToSync(file, directoryOrFiles, overwrite, path)
    logger:finer('ZipFile.zipToSync()')
    local zFile = ZipFile:new(file, true, overwrite)
    forEachFiles(path or '', asFiles(directoryOrFiles), function(f, name)
      zFile:addFile(f, name)
    end)
    zFile:close()
  end

  local function requireDefer()
    local event = require('jls.lang.event')
    local Promise = require('jls.lang.Promise')
    local Exception = require('jls.lang.Exception')
    return function(fn, ...)
      local args = table.pack(...)
      return Promise:new(function(resolve, reject)
        event:setTimeout(function()
          if type(fn) == 'function' then
            local status, err = Exception.pcall(fn, table.unpack(args, 1, args.n))
            if status then
              resolve()
            else
              reject(err)
            end
          else
            resolve(fn)
          end
        end)
      end)
    end
  end

  function ZipFile.zipToAsync(file, directoryOrFiles, overwrite, path)
    local defer = requireDefer()
    logger:finer('ZipFile.zipToAsync()')
    local zFile
    local p = defer(function()
      zFile = ZipFile:new(file, true, overwrite)
    end)
    forEachFiles(path or '', asFiles(directoryOrFiles), function(f, name)
      p = p:next(function()
        return defer(zFile.addFile, zFile, f, name)
      end)
    end)
    p:finally(function()
      zFile:close()
    end)
    return p
  end

  -- TODO Use async by default
  ZipFile.zipTo = ZipFile.zipToSync
  ZipFile.unzipTo = ZipFile.unzipToSync

end)
