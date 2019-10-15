local logger = require('jls.lang.logger')
local strings = require('jls.util.strings')
local File = require('jls.io.File')
local FileWriter = require('jls.io.streams.FileWriter')
local StreamHandler = require('jls.io.streams.StreamHandler')
local CallbackStreamHandler = require('jls.io.streams.CallbackStreamHandler')
local gzip = require('jls.lang.loader').tryRequire('jls.util.zip.gzip')

-- see https://en.wikipedia.org/wiki/Tar_(computing)
-- see https://pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html#tag_20_92_13_06

local FLAGS = {
  NORMAL_FILE = '0', -- or '\0'
  HARD_LINK = '1',
  SYMBOLIC_LINK = '2',
  CHARACTER_SPECIAL = '3',
  BLOCK_SPECIAL = '4',
  DIRECTORY = '5',
  FIFO = '6',
  CONTIGUOUS_FILE = '7',
  GLOBAL_EXTENDED_HEADER_WITH_META_DATA = 'g',
  EXTENDED_HEADER_WITH_META_DATA = 'x',
}

local function parseNumber(value)
  -- Numeric values are encoded in octal numbers using ASCII digits, with leading zeroes.
  -- For historical reasons, a final NUL or space character should also be used.
  local octalValue = string.match(value, '^([0-7]+)[ \0]*$')
  if octalValue then
    return tonumber(octalValue, 8)
  end
  return 0
end

local function parseString(value)
  local index = string.find(value, '\0', 1, true)
  if index then
    return string.sub(value, 1, index - 1)
  end
  return value
end

local function parseHeader(block)
  if logger:isLoggable(logger.FINEST) then
    logger:finest('parseHeader(#'..tostring(#block)..': '..require('jls.util.hex').encode(block)..')')
  end
  local name, mode, uid, gid, size, mtime, chksum, typeflag, linkname, magic, extra = table.unpack(strings.cuts(block, 100, 8, 8, 8, 12, 12, 8, 1, 100, 6, 512))
  if logger:isLoggable(logger.FINER) then
    logger:finer('parseHeader(#'..tostring(#block)..') '..require('jls.util.hex').encode(name)..', '..require('jls.util.hex').encode(size)..', '..require('jls.util.hex').encode(mtime))
  end
  if magic == 'ustar\0' then
    local version, uname, gname, devmajor, devminor, prefix = table.unpack(strings.cuts(extra, 2, 32, 32, 8, 8, 155))
  end
  return {
    name = parseString(name),
    size = parseNumber(size),
    mtime = parseNumber(mtime),
    empty = ((string.byte(name, 1) == 0) and (string.byte(size, 1) == 0))
  }
end

local function createExtractorStream(entryStreamFactory)
  local header, fullSize, stream
  local buffer = ''
  return CallbackStreamHandler:new(function(err, data)
    if data then
      buffer = buffer..data
    else
      return
    end
    while #buffer >= 512 do
      local block = string.sub(buffer, 1, 512)
      buffer = string.sub(buffer, 513)
      if header then
        fullSize = fullSize + 512
        if fullSize > header.size then
          block = string.sub(block, 1, 512 - (fullSize - header.size))
        end
        stream:onData(block)
        if fullSize >= header.size then
          stream:onData()
          stream = nil
          header = nil
        end
      else
        header = parseHeader(block)
        if logger:isLoggable(logger.FINE) then
          logger:fine('header name: '..tostring(header.name)..', size: '..tostring(header.size)..', mtime: '..tostring(header.mtime))
        end
        -- The end of an archive is marked by at least two consecutive zero-filled records.
        if header.empty then
          header = nil
        else
          stream = entryStreamFactory(header)
          fullSize = 0
        end
      end
    end
  end)
end

local function createDirectoryExtractorStream(directory)
  local dir = File.asFile(directory)
  if not dir:isDirectory() then
    error('The specified directory is invalid')
  end
  return createExtractorStream(function(header)
    local entryFile = File:new(dir, header.name)
    local parent = entryFile:getParentFile()
    if parent and not parent:isDirectory() then
      if not parent:mkdirs() then
        return nil, 'Cannot create directory '..parent:getPath()
      end
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('Extracting "'..header.name..'" into "'..entryFile:getPath()..'"')
    end
    return FileWriter:new(entryFile, false, function(fw)
      if header.mtime and header.mtime > 0 then
        fw:getFile():setLastModified(header.mtime * 1000)
      end
    end)
  end)
end

local function extractTo(filename, directory)
  local file = File.asFile(filename)
  if not file:exists() then
    error('The specified file is invalid')
  end
  local dse = createDirectoryExtractorStream(directory)
  if string.find(file:getName(), 'gz$') and gzip then
    logger:fine('Adding gzip stream decompression')
    -- we may look at magic gzip header bytes to activate decompression
    dse = gzip.decompressStream(dse)
  end
  FileWriter.streamFile(file, dse)
end

return {
  FLAGS = FLAGS,
  parseHeader = parseHeader,
  createExtractorStream = createExtractorStream,
  createDirectoryExtractorStream = createDirectoryExtractorStream,
  extractTo = extractTo
}
