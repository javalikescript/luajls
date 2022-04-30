--- Provide tar file utility.
-- Tar files are archives that allow to store multiple files.
-- @module jls.util.zip.tar

local logger = require('jls.lang.logger')
local strings = require('jls.util.strings')
local File = require('jls.io.File')
local StreamHandler = require('jls.io.StreamHandler')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
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
  local header, fullSize, sh
  local buffer = ''
  return StreamHandler:new(function(err, data)
    if err then
      if logger:isLoggable(logger.FINE) then
        logger:fine('error while extracting '..tostring(err))
      end
      return
    end
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
        sh:onData(block)
        if fullSize >= header.size then
          sh:onData()
          sh = nil
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
          sh = entryStreamFactory(header)
          fullSize = 0
        end
      end
    end
  end)
end

--[[--
Returns a @{jls.io.StreamHandler} that will extracts the tar content into the specified directory.

@param directory the directory to extract to, as a @{jls.io.File} or a string directory name
@tparam[opt] boolean decompress true to indicate that the stream is compressed using gzip
@return the @{jls.io.StreamHandler}
@function extractStreamTo

@usage
local tar = require('jls.util.zip.tar')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')

local sh = tar.extractStreamTo('.')
FileStreamHandler.readAllSync('test.tar', sh)
]]
local function extractStreamTo(directory, decompress)
  local dir = File.asFile(directory)
  if not dir:isDirectory() then
    error('The specified directory is invalid')
  end
  local sh = createExtractorStream(function(header)
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
    return FileStreamHandler:new(entryFile, false, function(fw)
      if header.mtime and header.mtime > 0 then
        fw:getFile():setLastModified(header.mtime * 1000)
      end
    end, false, true)
  end)
  if decompress then
    return gzip.decompressStream(sh)
  end
  return sh
end

--[[--
Extracts the specified file into the specified directory.
@param file the tar file to extract, as a @{jls.io.File} or a string file name
@param directory the directory to extract to, as a @{jls.io.File} or a string directory name
@function extractFileTo
@usage
local tar = require('jls.util.zip.tar')
tar.extractFileTo('test.tar', '.')
]]
local function extractFileTo(file, directory)
  file = File.asFile(file)
  if not file:exists() then
    error('The specified file is invalid')
  end
  local decompress = false
  if string.find(file:getName(), 'gz$') and gzip then
    logger:fine('Adding gzip stream decompression')
    -- we may look at magic gzip header bytes to activate decompression
    decompress = true
  end
  FileStreamHandler.readAllSync(file, extractStreamTo(directory, decompress))
end

return {
  FLAGS = FLAGS,
  parseHeader = parseHeader,
  createExtractorStream = createExtractorStream,
  extractStreamTo = extractStreamTo,
  extractFileTo = extractFileTo
}
