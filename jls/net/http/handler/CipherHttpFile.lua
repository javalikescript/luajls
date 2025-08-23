local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local Path = require('jls.io.Path')
local FileDescriptor = require('jls.io.FileDescriptor')
local HttpFile = require('jls.net.http.handler.FileHttpHandler').HttpFile
local Codec = require('jls.util.Codec')

local base64 = Codec.getInstance('base64', 'safe', false)

local HEADER_SIGNATURE = 'EC'
local SUB_HEADER_FORMAT = '>I8I8'
local HEADER_FORMAT = '>c'..#HEADER_SIGNATURE..string.sub(SUB_HEADER_FORMAT, 2)
local HEADER_SIZE = string.packsize(HEADER_FORMAT)
local NAME_SIGNATURE = 7

local function getIv(salt, ctr)
  return string.pack(SUB_HEADER_FORMAT, salt, ctr or 0)
end

local function generateEncName(mdCipher, name, extension)
  -- the same plain name must result to the same encoded name
  return base64:encode(mdCipher:encode(string.char(NAME_SIGNATURE)..name))..'.'..extension
end

local function getDecName(mdCipher, encName, extension)
  local ext, bname = Path.extractExtension(encName)
  if ext == extension then
    local cname = base64:decodeSafe(bname)
    if cname then
      local name = mdCipher:decodeSafe(cname)
      if name and string.byte(name, 1) == NAME_SIGNATURE then
        return string.sub(name, 2)
      end
    end
  end
end

local function renameFile(file, name)
  if name then
    local p = file:getParentFile()
    if p then
      return File:new(p, name)
    end
    return File:new(name)
  end
  return file
end

local function getEncFile(mdCipher, file, extension)
  return renameFile(file, generateEncName(mdCipher, file:getName(), extension))
end

local function readEncFileHeader(file)
  local fd = FileDescriptor.openSync(file, 'r')
  if fd then
    local header = fd:readSync(HEADER_SIZE)
    fd:closeSync()
    if header then
      local sig, size, salt = string.unpack(HEADER_FORMAT, header)
      if sig == HEADER_SIGNATURE then
        return size, salt
      end
    end
  end
end

return class.create(File, function(cipherHttpFile, super, CipherHttpFile)

  function cipherHttpFile:initialize(file, cipher, mdCipher, extension, encName)
    local name = file:getName()
    encName = encName or generateEncName(mdCipher, name, extension)
    local p = file:getParentFile()
    if p then
      super.initialize(self, p, encName)
    else
      super.initialize(self, encName)
    end
    self.name = name
    self.cipher = cipher
    self.mdCipher = mdCipher
    self.extension = extension or 'enc'
  end

  function cipherHttpFile:getName()
    return self.name
  end

  function cipherHttpFile:length()
    local length = super.length(self)
    if length >= HEADER_SIZE then
      return length - HEADER_SIZE -- possibly incorrect
    end
    return length
  end

  function cipherHttpFile:listFiles()
    local list = {}
    local files = super.listFiles(self)
    if files then
      for _, file in ipairs(files) do
        local f
        local encName = file:getName()
        if file:isDirectory() then
          f = file
        else
          local name = getDecName(self.mdCipher, encName, self.extension)
          if name then
            f = renameFile(file, name)
          end
        end
        if f then
          table.insert(list, CipherHttpFile:new(f, self.cipher, self.mdCipher, self.extension, encName))
        end
      end
    end
    return list
  end

  function cipherHttpFile:copyTo(destFile)
    return super.copyTo(self, getEncFile(self.mdCipher, destFile, self.extension))
  end

  function cipherHttpFile:renameTo(destFile)
    return super.renameTo(self, getEncFile(self.mdCipher, destFile, self.extension))
  end

  local superHttpFile = HttpFile.prototype

  function cipherHttpFile:setFileStreamHandler(sh, offset, length)
    logger:fine('setFileStreamHandler(..., %s, %s)', offset, length)
    local size, salt = readEncFileHeader(self)
    if size and salt then
      -- curl -o file -r 0- http://localhost:8000/file
      sh, offset, length = self.cipher:decodeStreamPart(sh, getIv(salt), offset, length)
      logger:fine('cipher:decodeStreamPart(0x%x) => %s, %s', salt, offset, length)
      offset = HEADER_SIZE + (offset or 0)
    end
    superHttpFile.setFileStreamHandler(self, sh, offset, length)
  end

  function cipherHttpFile:getFileStreamHandler(time, size)
    if not size then
      error('content length is missing')
    end
    local sh = superHttpFile.getFileStreamHandler(self, time)
    local salt = math.random(0, 0xffffffff)
    sh:onData(string.pack(HEADER_FORMAT, HEADER_SIGNATURE, size, salt))
    logger:fine('cipher:encodeStreamPart(%d, 0x%x)', size, salt)
    return self.cipher:encodeStreamPart(sh, getIv(salt))
  end

end, function(CipherHttpFile)

  CipherHttpFile.getCreateHttpFilefromSession = function(keyName, alg, mdAlg, extension, contextName)
    keyName = keyName or 'jls-cipher-key'
    alg = alg or 'aes-128-ctr'
    mdAlg = mdAlg or 'aes256'
    extension = extension or 'enc'
    contextName = contextName or 'jls-cipher-context'
    return function(self, exchange, file, isDir)
      local session = exchange:getSession()
      if session then
        local cipherKey = session:getAttribute(keyName)
        if cipherKey then
          local cipher, mdCipher
          local cipherContext = session:getAttribute(contextName)
          if cipherContext then
            cipher, mdCipher = cipherContext.cipher, cipherContext.mdCipher
          else
            cipher = Codec.getInstance('cipher', alg, cipherKey)
            mdCipher = Codec.getInstance('cipher', mdAlg, cipherKey)
            session:setAttribute(contextName, { cipher = cipher, mdCipher = mdCipher })
          end
          -- a directory name is not encoded
          return CipherHttpFile:new(file, cipher, mdCipher, extension, isDir and file:getName() or nil)
        else
          session:setAttribute(contextName)
        end
      end
    end
  end

  CipherHttpFile.fromSession = function(fileHttpHandler, keyName, alg, mdAlg, extension, contextName)
    fileHttpHandler.createHttpFile = CipherHttpFile.getCreateHttpFilefromSession(keyName, alg, mdAlg, extension, contextName)
    return fileHttpHandler
  end

end)
