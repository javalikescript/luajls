local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local StreamHandler = require('jls.io.StreamHandler')
local RangeStreamHandler = require('jls.io.streams.RangeStreamHandler')
local cipherLib = require('openssl').cipher

local CipherStreamHandler = class.create(StreamHandler, function(cipherStreamHandler, super)
  function cipherStreamHandler:initialize(sh, ...)
    super.initialize(self, sh)
    self.handler = sh
    self.ctx = cipherLib.new(...)
  end
  function cipherStreamHandler:onData(data)
    if data then
      return self.handler:onData(self.ctx:update(data))
    end
    return StreamHandler.fill(self.handler, self.ctx:final())
  end
end)

-- cipherLib.get(alg):info() => key_length iv_length

local function asIv(iv)
  -- pad with 0 up to  16(EVP_MAX_IV_LENGTH)
  if type(iv) == 'number' then
    return string.pack('>I16', iv)
  end
  return string.pack('c16', iv or '')
end

return require('jls.lang.class').create('jls.util.Codec', function(cipher)

  function cipher:initialize(alg, key)
    self.alg = alg or 'aes128'
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

  function cipher:decodeStreamPart(sh, iv, offset, length)
    if offset and length then
      local rangeOffset = offset
      local firstBlock = 0
      if not iv and offset > 0 and self.alg == 'aes-128-ctr' or self.alg == 'aes-256-ctr' then
        firstBlock, rangeOffset = offset // 16, offset % 16
        offset, length = firstBlock * 16, rangeOffset + length
      end
      if logger:isLoggable(logger.FINE) then
        logger:fine('ciipher.decodeStreamPart() iv: '..tostring(firstBlock)..', range offset: '..tostring(rangeOffset))
      end
      iv = firstBlock
      sh = RangeStreamHandler:new(sh, rangeOffset, length)
    end
    return CipherStreamHandler:new(sh, self.alg, false, self.key, asIv(iv), false), offset, length
  end

  function cipher:encodeStreamPart(sh, iv)
    return CipherStreamHandler:new(sh, self.alg, true, self.key, asIv(iv), false)
  end

end)
