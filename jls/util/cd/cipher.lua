local class = require('jls.lang.class')
local logger = require('jls.lang.loggerFactory')(...)
local StreamHandler = require('jls.io.StreamHandler')
local RangeStreamHandler = require('jls.io.streams.RangeStreamHandler')
local opensslLib = require('openssl')
local cipherLib = opensslLib.cipher
local bnLib = opensslLib.bn
local strings = require('jls.util.strings')

local CipherStreamHandler = class.create(StreamHandler, function(cipherStreamHandler, super)
  function cipherStreamHandler:initialize(sh, alg, encrypt, key, iv, pad)
    if logger:isLoggable(logger.FINE) then
      logger:fine('CipherStreamHandler:new(?, %s, %s, ?, %s, %s)', alg, encrypt, iv and require('jls.util.hex').encode(iv), pad)
    end
    super.initialize(self, sh)
    self.handler = sh
    self.ctx = cipherLib.new(alg, encrypt, key, iv, pad ~= false) -- pad default value is true
  end
  function cipherStreamHandler:onData(data)
    if data then
      local cdata, err = self.ctx:update(data)
      if cdata then
        if #cdata > 0 then
          return self.handler:onData(cdata)
        end
      else
        self.handler:onError(err)
      end
    else
      local cdata, err = self.ctx:final()
      if cdata then
        return StreamHandler.fill(self.handler, cdata)
      else
        self.handler:onError(err)
      end
    end
  end
end)

-- cipherLib.get(alg):info() => key_length iv_length

local function asIv(iv)
  -- pad with 0 up to 16 (EVP_MAX_IV_LENGTH)
  if type(iv) == 'number' then
    return string.pack('>I16', iv)
  end
  if iv == nil then
    iv = ''
  elseif type(iv) ~= 'string' then
    iv = tostring(iv)
  end
  return strings.padLeft(iv, 16, '\0')
end

local function getCounterAlgBlockSize(alg)
  if alg == 'aes-128-ctr' or alg == 'aes-256-ctr' then
    return 16
  end
  return 1
end

return require('jls.lang.class').create('jls.util.Codec', function(cipher)

  function cipher:initialize(alg, key)
    self.alg = alg or 'aes128' -- TODO normalize algorithm name
    -- pad with 0 up to 64 (EVP_MAX_KEY_LENGTH)
    self.key = string.pack('c64', key or '')
  end

  function cipher:decode(value)
    return cipherLib.decrypt(self.alg, value, self.key)
  end

  function cipher:encode(value)
    return cipherLib.encrypt(self.alg, value, self.key)
  end

  function cipher:decodeStream(sh)
    return CipherStreamHandler:new(sh, self.alg, false, self.key)
  end

  function cipher:encodeStream(sh)
    return CipherStreamHandler:new(sh, self.alg, true, self.key)
  end

  function cipher:getName()
    return 'cipher'
  end

  function cipher:getAlgorithm()
    return self.alg
  end

  function cipher:decodeStreamPart(sh, iv, offset, length)
    if offset and length then
      local blockSize = getCounterAlgBlockSize(self.alg)
      if blockSize > 1 then
        local firstBlock, rangeOffset = 0, 0
        if offset > 0 then
          firstBlock, rangeOffset = offset // blockSize, offset % blockSize
          offset, length = firstBlock * blockSize, rangeOffset + length
        end
        if firstBlock > 0 then
          logger:fine('cipher.decodeStreamPart() first block: %d, range offset: %d', firstBlock, rangeOffset)
          -- use the first block as counter and to increment the initialization vector
          iv = bnLib.add(bnLib.text(asIv(iv)), firstBlock):totext()
        end
        if rangeOffset > 0 then
          sh = RangeStreamHandler:new(sh, rangeOffset, length)
        end
      end
    end
    return CipherStreamHandler:new(sh, self.alg, false, self.key, asIv(iv), false), offset, length
  end

  function cipher:encodeStreamPart(sh, iv)
    return CipherStreamHandler:new(sh, self.alg, true, self.key, asIv(iv), false)
  end

end)
