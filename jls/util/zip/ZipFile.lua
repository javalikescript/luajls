--- Provide ZIP file utility.
-- ZIP files are archives that allow to store and compress multiple files.
-- @module jls.util.zip.ZipFile

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')
local LocalDateTime = require('jls.util.LocalDateTime')
local Date = require('jls.util.Date')

-- ----------------------------------------------------------------------
-- TODO Replace Struct by string.pack, string.packsize, and string.unpack
-- ----------------------------------------------------------------------
local Struct = require('jls.lang.class').create(function(struct)

  local TYPE_ID = {
    Char = 100,
    SignedByte = 101,
    UnsignedByte = 102,
    SignedShort = 201,
    UnsignedShort = 202,
    SignedInt = 401,
    UnsignedInt = 402,
    SignedLong = 801,
    UnsignedLong = 802
  }

  local TYPE_SIZE = {
    Char = 1,
    SignedByte = 1,
    UnsignedByte = 1,
    SignedShort = 2,
    UnsignedShort = 2,
    SignedInt = 4,
    UnsignedInt = 4,
    SignedLong = 8,
    UnsignedLong = 8
  }

  -- Creates a new Struct.
  -- @function Struct:new
  -- @tparam table structDef the structure definition as field-type key-value pairs
  -- @tparam string byteOrder bigEndian or littleEndian
  -- @return a new Struct
  function struct:initialize(structDef, byteOrder)
    self.struct = {}
    self.byteOrder = '>'
    self:setOrder(byteOrder)
    local position = 0
    for i, def in ipairs(structDef) do
      local id = TYPE_ID[def.type]
      if not id then
        error('Invalid Struct definition type "'..tostring(def.type)..'" at index '..tostring(i))
      end
      local length = def.length or 1
      local size = TYPE_SIZE[def.type] * length
      table.insert(self.struct, {
        id = id,
        length = length,
        name = def.name,
        position = position,
        size = size,
        type = def.type
      })
      position = position + size
    end
    local format = self:getOrder()
    for _, def in ipairs(self.struct) do
      local f
      if def.id == TYPE_ID.Char then
        f = 'c'..tostring(def.length)
      elseif def.id == TYPE_ID.SignedByte then
        f = 'i1'
      elseif def.id == TYPE_ID.UnsignedByte then
        f = 'I1'
      elseif def.id == TYPE_ID.SignedShort then
        f = 'i2'
      elseif def.id == TYPE_ID.UnsignedShort then
        f = 'I2'
      elseif def.id == TYPE_ID.SignedInt then
        f = 'i4'
      elseif def.id == TYPE_ID.UnsignedInt then
        f = 'I4'
      end
      format = format..f
    end
    self.format = format;
    self.size = string.packsize(self.format);
    if self.size ~= position then
      error('Internal size error ('..tostring(self.size)..'~='..tostring(position)..')')
    end
  end

  function struct:getOrder()
    return self.byteOrder
  end

  -- Sets the byte order.
  -- @tparam string byteOrder bigEndian or littleEndian
  function struct:setOrder(byteOrder)
    local bo = '='
    if type(byteOrder) == 'string' then
      bo = string.lower(string.sub(byteOrder, 1, 1))
      if bo == 'b' then
        bo = '>'
      elseif bo == 'l' then
        bo = '<'
      end
    end
    self.byteOrder = bo
    return self
  end

  -- Returns the size of this Struct that is the total size of its fields.
  -- @treturn number the size of this Struct.
  function struct:getSize()
    return self.size
  end

  function struct:getPackFormat()
    return self.format
  end

  -- Decodes the specifed byte array as a string.
  -- @tparam string s the value to decode as a string
  -- @treturn table the decoded values.
  function struct:fromString(s)
    local t = {}
    local values = table.pack(string.unpack(self:getPackFormat(), s))
    for i, def in ipairs(self.struct) do
      t[def.name] = values[i]
    end
    return t
  end

  -- Encodes the specifed values provided as a table.
  -- @tparam string t the values to encode as a table
  -- @treturn string the encoded values as a string.
  function struct:toString(t, strict)
    local values = {}
    for i, def in ipairs(self.struct) do
      local value = t[def.name]
      if not value then
        if strict then
          error('Missing value for field "'..tostring(def.name)..'" at index '..tostring(i))
        end
        if def.id == TYPE_ID.Char then
          value = ''
        else
          value = 0
        end
      end
      table.insert(values, value)
    end
    return string.pack(self:getPackFormat(), table.unpack(values))
  end

end)
-- ----------------------------------------------------------------------
-- End of Struct class
-- ----------------------------------------------------------------------

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
        self.fd:writeSync(rawFileHeader)
        self.fd:writeSync(name)
        if extra and #extra > 0 then
          self.fd:writeSync(extra)
        end
        if comment and #comment > 0 then
          self.fd:writeSync(comment)
        end
      end
      local rawEOCDR = ZipFile.STRUCT.EndOfCentralDirectoryRecord:toString({
        signature = ZipFile.CONSTANT.END_CENTRAL_DIR_SIGNATURE,
        entryCount = #self.entries,
        offset = self.offset
      })
      self.fd:writeSync(rawEOCDR)
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
    local lastModFileDate = (math.max(date:getYear() - 1980, 0) << 9) | ((date:getMonth()) << 5) | date:getDay()
    local lastModFileTime = (date:getHours() << 11) | (date:getMinutes() << 5) | (date:getSeconds() // 2)
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
      --versionNeeded = 0, -- TODO Check
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
    self.fd:writeSync(rawLocalFileHeader)
    self.fd:writeSync(name)
    if extra and #extra > 0 then
      self.fd:writeSync(extra)
    end
    if uncompressedSize > 0 then
      self.fd:writeSync(rawContent)
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
  -- @tparam[opt] function callback an optional function that will be called with the content.
  -- @treturn string the entry content
  function zipFile:getContent(entry, callback)
    if not callback then
      return self:getContentSync(entry)
    end
    if entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_STORED then
      self:readRawContent(entry, callback)
    elseif entry:getMethod() == ZipFile.CONSTANT.COMPRESSION_METHOD_DEFLATED then
      local inflater = Inflater:new(-15)
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

  local function keepFileName(name)
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

  function ZipFile.unzipTo(file, directory, adaptFileName)
    --local fil = File.asFile(file)
    local dir = File.asFile(directory)
    if not dir:isDirectory() then
      return false, 'The specified directory is invalid'
    end
    if type(adaptFileName) ~= 'function' then
      adaptFileName = keepFileName
    end
    local err = nil
    local zFile = ZipFile:new(file)
    for _, entry in ipairs(zFile:getEntries()) do
      local name = adaptFileName(entry:getName(), entry)
      if name then
        logger:info('unzip entry "'..name..'"')
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
          local content = zFile:getContent(entry)
          if content then
            entryFile:write(content)
          end
          local dt = entry:getDatetime()
          local date = Date.fromLocalDateTime(dt)
          entryFile:setLastModified(date:getTime())
        end
      else
        logger:info('skipping entry "'..entry:getName()..'"')
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

  function ZipFile.zipTo(file, directoryOrFiles, path)
    if File:isInstance(directoryOrFiles) then
      if directoryOrFiles:isDirectory() then
        return ZipFile.zipTo(file, directoryOrFiles:listFiles())
      end
      return ZipFile.zipTo(file, {directoryOrFiles})
    end
    local zFile = ZipFile:new(file)
    addFiles(zFile, path or '', directoryOrFiles)
    zFile:close()
  end
end)
