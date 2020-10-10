-- Provide gzip utility.
-- @module jls.util.zip.gzip

local logger = require('jls.lang.logger')
local StringBuffer = require('jls.lang.StringBuffer')
local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')
local StreamHandler = require('jls.io.streams.StreamHandler')
local CallbackStreamHandler = require('jls.io.streams.CallbackStreamHandler')
local Crc32 = require('jls.util.md.Crc32')

-- see https://tools.ietf.org/html/rfc1952

local gzip = {}

local FLAGS = {
  TEXT = 1,
  HCRC = 2,
  EXTRA = 4,
  NAME = 8,
  COMMENT = 16
}

function gzip.formatHeader(header)
  local compressionMethod = 8
  local flags = 0
  local mtime = 0
  local extraFlags = 0
  local os = 3 -- Unix
  local name, comment, extra
  if header then
    if type(header.modificationTime) == 'number' then
      mtime = header.modificationTime
    end
    if type(header.os) == 'number' then
      os = header.os
    end
    if type(header.extra) == 'string' then
      extra = header.extra
      flags = flags | FLAGS.EXTRA
    end
    if type(header.name) == 'string' then
      name = header.name
      flags = flags | FLAGS.NAME
    end
    if type(header.comment) == 'string' then
      comment = header.comment
      flags = flags | FLAGS.COMMENT
    end
  end
  local buffer = StringBuffer:new()
  buffer:append(string.pack('<BBBBI4BB', 0x1f, 0x8b, compressionMethod, flags, mtime, extraFlags, os))
  if extra then
    buffer:append(string.pack('<I2', #extra))
    buffer:append(extra)
  end
  if name then
    buffer:append(name)
    buffer:append('\0')
  end
  if comment then
    buffer:append(comment)
    buffer:append('\0')
  end
  return buffer:toString()
end

function gzip.parseHeader(data)
  local size = #data
  if size < 10 then
    return
  end
  local id1, id2, compressionMethod, flags, mtime, extraFlags, os = string.unpack('<BBBBI4BB', data)
  if id1 ~= 0x1f or id2 ~= 0x8b then
    return nil, nil, 'Invalid magic identification bytes'
  end
  local name, comment, extra
  local offset = 11
  if flags & FLAGS.EXTRA ~= 0 then
    if size < 12 then
      return
    end
    local extraSize = string.unpack('<I2', data, 11)
    offset = 13 + extraSize
    if size < offset then
      return
    end
    extra = string.sub(data, 13, offset)
  end
  if flags & FLAGS.NAME ~= 0 then
    local index = string.find(data, '\0', offset, true)
    if not index then
      return
    end
    name = string.sub(data, offset, index - 1)
    offset = index + 1
  end
  if flags & FLAGS.COMMENT ~= 0 then
    local index = string.find(data, '\0', offset, true)
    if not index then
      return
    end
    comment = string.sub(data, offset, index - 1)
    offset = index + 1
  end
  return {
    modificationTime = mtime,
    os = os,
    name = name,
    comment = comment,
    extra = extra,
  }, offset - 1
end


function gzip.compressStream(stream, header, compressionLevel)
  local cb = StreamHandler.ensureCallback(stream)
  cb(nil, gzip.formatHeader(header))
  local size = 0
  local crc = Crc32:new()
  local deflater = Deflater:new(compressionLevel, -15)
  return CallbackStreamHandler:new(function(err, data)
    if err then
      return cb(err)
    end
    if data then
      crc:update(data)
      size = size + #data
      cb(nil, deflater:deflate(data))
    else
      cb(nil, deflater:finish()..string.pack('<I4I4', crc:final(), size))
      cb(nil, nil)
    end
  end)
end

function gzip.decompressStream(stream, onHeader)
  if logger:isLoggable(logger.FINER) then
    logger:finer('decompressStream()')
  end
  local cb = StreamHandler.ensureCallback(stream)
  local header, inflated
  local buffer = ''
  local size = 0
  local crc = Crc32:new()
  local inflater = Inflater:new(-15)
  return CallbackStreamHandler:new(function(err, data)
    if err then
      return cb(err)
    end
    if header then
      if buffer then
        local footer
        if data then
          if #data < 8 then
            -- do not consume the buffer if data is less than footer
            buffer = buffer..data
            return
          end
        else
          local bufferSize = #buffer
          footer = string.sub(buffer, bufferSize - 7)
          buffer = string.sub(buffer, 1, bufferSize - 8)
          if logger:isLoggable(logger.FINER) then
            logger:finer('footer'..require('jls.util.hex').encode(footer))
          end
        end
        inflated = inflater:inflate(buffer)
        crc:update(inflated)
        size = size + #inflated
        cb(nil, inflated)
        if data then
          buffer = data
        else
          local crcFooter, sizeFooter = string.unpack('<I4I4', footer)
          if logger:isLoggable(logger.FINER) then
            logger:finer('decompressStream() CRC '..tostring(crc:final())..'/'..tostring(crcFooter)..', size '..tostring(size)..' expected '..tostring(sizeFooter))
          end
          if crcFooter ~= crc:final() then
            cb('Bad CRC (found '..tostring(crc:final())..' expected '..tostring(crcFooter)..')')
          elseif sizeFooter ~= size then
            cb('Bad size (found '..tostring(size)..' expected '..tostring(sizeFooter)..')')
          else
            cb()
          end
          if logger:isLoggable(logger.FINER) then
            logger:finer('decompressStream() completed')
          end
        end
      end
    else
      local err, headerSize
      buffer = buffer..data
      header, headerSize, err = gzip.parseHeader(buffer)
      if err then
        return cb(err)
      end
      if header then
        if type(onHeader) == 'function' then
          onHeader(header)
        end
        buffer = string.sub(buffer, headerSize + 1)
      else
        return
      end
    end
  end)
end

function gzip.compressStreamRaw(stream, compressionLevel)
  local cb = StreamHandler.ensureCallback(stream)
  local deflater = Deflater:new(compressionLevel)
  return CallbackStreamHandler:new(function(err, data)
    if err then
      return cb(err)
    end
    if data then
      cb(nil, deflater:deflate(data))
    else
      cb(nil, deflater:finish())
      cb(nil, nil)
    end
  end)
end

function gzip.decompressStreamRaw(stream)
  local cb = StreamHandler.ensureCallback(stream)
  local inflater = Inflater:new() -- auto detect
  return CallbackStreamHandler:new(function(err, data)
    if err then
      return cb(err)
    end
    if data then
      cb(nil, inflater:inflate(data))
    else
      cb()
    end
  end)
end

return gzip
