local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local List = require('jls.util.List')
local Codec = require('jls.util.Codec')

local base64 = Codec.getInstance('base64', 'safe', false)

local HEADER_FORMAT = '>c2I8I8'
local HEADER_SIZE = string.packsize(HEADER_FORMAT)

local function getIv(salt, ctr)
  return string.pack('>I8I8', salt, ctr or 0)
end

local function getNameExt(name)
  return string.match(name, '^([%w%-_%+/]+)%.(%w+)$')
end

local function generateEncName(mdCipher, name, extension)
  -- the same plain name must result to the same encoded name
  return base64:encode(mdCipher:encode('\7'..name))..'.'..extension
end

local function readEncFileMetadata(mdCipher, encFile, extension)
  local bname, ext = getNameExt(encFile:getName())
  if bname and ext == extension then
    local cname = base64:decodeSafe(bname)
    if cname then
      local name = mdCipher:decodeSafe(cname)
      if name and string.byte(name, 1) == 7 then
        return {
          name = string.sub(name, 2),
          size = encFile:length() - HEADER_SIZE, -- possibly incorrect
          time = encFile:lastModified(),
        } -- we could read the header to check the signature and get the size
      end
    end
  end
end

local function getEncFileMetadata(mdCipher, file, extension, full)
  local dir = file:getParentFile()
  if dir then
    local name = file:getName()
    local encFile = File:new(dir, generateEncName(mdCipher, name, extension))
    if encFile:isFile() then
      local md = {
        name = name,
        time = encFile:lastModified(),
        encFile = encFile,
      }
      if not full then
        return md
      end
      local fd = FileDescriptor.openSync(encFile, 'r')
      if fd then
        local header = fd:readSync(HEADER_SIZE)
        fd:closeSync()
        if header then
          local sig, size, salt = string.unpack(HEADER_FORMAT, header)
          if sig == 'EC' then
            md.size = size
            md.salt = salt
            return md
          end
        end
      end
    end
  end
end

return require('jls.lang.class').create('jls.net.http.handler.DefaultFileSystem', function(fileSystem, super)

  function fileSystem:initialize(alg, showEncoded, extension)
    super.initialize(self)
    self.alg = alg or 'aes-128-ctr'
    self.mdAlg = 'aes256'
    self.showEncoded = showEncoded == true
    self.extension = extension or 'enc'
  end

  function fileSystem:getCipher(exchange, key)
    local session = exchange:getSession()
    if session then
      local cipherKey = session:getAttribute('jls-cipher-key')
      if cipherKey then
        local cipherContext = session:getAttribute('jls-cipher-context')
        if not cipherContext then
          cipherContext = {
            cipher = Codec.getInstance('cipher', self.alg, cipherKey),
            mdCipher = Codec.getInstance('cipher', self.mdAlg, cipherKey)
          }
          session:setAttribute('jls-cipher-context', cipherContext)
        end
        if key then
          return cipherContext[key]
        end
        return cipherContext.cipher, cipherContext.mdCipher
      else
        session:setAttribute('jls-cipher-context')
      end
    end
  end

  function fileSystem:getFileMetadata(exchange, file)
    local mdCipher = self:getCipher(exchange, 'mdCipher')
    if mdCipher and not file:isDirectory() then
      return getEncFileMetadata(mdCipher, file, self.extension, true)
    end
    return super.getFileMetadata(self, exchange, file)
  end

  function fileSystem:listFileMetadata(exchange, dir)
    local mdCipher = self:getCipher(exchange, 'mdCipher')
    if mdCipher and dir:isDirectory() then
      local files = {}
      for _, file in ipairs(dir:listFiles()) do
        local md
        if file:isDirectory() then
          md = super.getFileMetadata(self, exchange, file)
          md.name = file:getName()
        else
          md = readEncFileMetadata(mdCipher, file, self.extension)
        end
        if md then
          table.insert(files, md)
        end
      end
      return files
    end
    local files = super.listFileMetadata(self, exchange, dir)
    if not self.showEncoded then
      return List.filter(files, function(md)
        local _, ext = getNameExt(md.name)
        return ext ~= self.extension
      end)
    end
    return files
  end

  function fileSystem:copyFile(exchange, file, destFile)
    local mdCipher = self:getCipher(exchange, 'mdCipher')
    if mdCipher then
      local md = getEncFileMetadata(mdCipher, file, self.extension)
      if md then
        file = md.encFile
        destFile = File:new(destFile:getParent(), generateEncName(mdCipher, destFile:getName(), self.extension))
      end
    end
    return super.copyFile(self, exchange, file, destFile)
  end

  function fileSystem:renameFile(exchange, file, destFile)
    local mdCipher = self:getCipher(exchange, 'mdCipher')
    if mdCipher then
      local md = getEncFileMetadata(mdCipher, file, self.extension)
      if md then
        return md.encFile:renameTo(File:new(file:getParent(), generateEncName(mdCipher, destFile:getName(), self.extension)))
      end
    end
    return super.renameFile(self, exchange, file, destFile)
  end

  function fileSystem:deleteFile(exchange, file, recursive)
    local mdCipher = self:getCipher(exchange, 'mdCipher')
    if mdCipher then
      local md = getEncFileMetadata(mdCipher, file, self.extension)
      if md then
        file = md.encFile
      end
    end
    return super.deleteFile(self, exchange, file, recursive)
  end

  function fileSystem:setFileStreamHandler(exchange, file, sh, md, offset, length)
    local cipher = self:getCipher(exchange, 'cipher')
    logger:fine('setFileStreamHandler(..., %s, %s)', offset, length)
    if cipher then
      if not (md and md.encFile and md.salt) then
        error('metadata are missing')
      end
      -- curl -o file -r 0- http://localhost:8000/file
      sh, offset, length = cipher:decodeStreamPart(sh, getIv(md.salt), offset, length)
      logger:fine('cipher:decodeStreamPart(0x%x) => %s, %s', md.salt, offset, length)
      offset = HEADER_SIZE + (offset or 0)
      file = md.encFile
    end
    super.setFileStreamHandler(self, exchange, file, sh, md, offset, length)
  end

  function fileSystem:getFileStreamHandler(exchange, file, ...)
    local cipher, mdCipher = self:getCipher(exchange)
    if cipher and mdCipher then
      local size = exchange:getRequest():getContentLength()
      if not size then
        error('content length is missing')
      end
      local encFile = File:new(file:getParent(), generateEncName(mdCipher, file:getName(), self.extension))
      local sh = super.getFileStreamHandler(self, exchange, encFile, ...)
      local salt = math.random(0, 0xffffffff)
      sh:onData(string.pack(HEADER_FORMAT, 'EC', size, salt))
      logger:fine('cipher:encodeStreamPart(%d, 0x%x)', size, salt)
      return cipher:encodeStreamPart(sh, getIv(salt))
    end
    return super.getFileStreamHandler(self, exchange, file, ...)
  end

end)
