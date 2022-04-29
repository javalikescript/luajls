local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local StreamHandler = require('jls.io.streams.StreamHandler')
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

--[[
return class.create(function(cipher)
  function cipher:initialize(sh, alg, ...)
    self.alg = alg or 'aes128'
    self.args = table.pack(...)
  end
  function cipher:decode(data)
    return cipherLib.decrypt(self.alg, data, table.unpack(self.args))
  end
  function cipher:encode(data)
    return cipherLib.encrypt(self.alg, data, table.unpack(self.args))
  end
  function cipher:decodeStream(handler)
    return CipherStreamHandler:new(handler, self.alg, false, table.unpack(self.args))
  end
  function cipher:encodeStream(handler)
    return CipherStreamHandler:new(handler, self.alg, true, table.unpack(self.args))
  end
end)
]]

local DEFAULT_ALG = 'aes128'

-- cipherLib.get(alg):info() => key_length iv_length

local function asKey(key, alg)
  -- pad with 0 up to 64 (EVP_MAX_KEY_LENGTH)
  return string.pack('c64', key or '')
end

local function asIv(iv, alg)
  -- pad with 0 up to  16(EVP_MAX_IV_LENGTH)
  if type(iv) == 'number' then
    return string.pack('>I16', iv)
  end
  return string.pack('c16', iv or '')
end

return {
  decode = function(data, alg, key, ...)
    return cipherLib.decrypt(alg or DEFAULT_ALG, data, asKey(key), ...)
  end,
  encode = function(data, alg, key, ...)
    return cipherLib.encrypt(alg or DEFAULT_ALG, data, asKey(key), ...)
  end,
  decodeStream = function(handler, alg, key, ...)
    return CipherStreamHandler:new(handler, alg or DEFAULT_ALG, false, asKey(key), ...)
  end,
  decodeStreamPart = function(handler, alg, key, iv, offset, length)
    if offset and length then
      local rangeOffset = offset
      local firstBlock = 0
      if not iv and offset > 0 and alg == 'aes-128-ctr' or alg == 'aes-256-ctr' then
        firstBlock, rangeOffset = offset // 16, offset % 16
        offset, length = firstBlock * 16, rangeOffset + length
      end
      if logger:isLoggable(logger.FINE) then
        logger:fine('ciipher.decodeStreamPart() iv: '..tostring(firstBlock)..', range offset: '..tostring(rangeOffset))
      end
      iv = firstBlock
      handler = RangeStreamHandler:new(handler, rangeOffset, length)
    end
    return CipherStreamHandler:new(handler, alg or DEFAULT_ALG, false, asKey(key), asIv(iv), false), offset, length
  end,
  encodeStream = function(handler, alg, key, ...)
    return CipherStreamHandler:new(handler, alg or DEFAULT_ALG, true, asKey(key), ...)
  end,
  encodeStreamPart = function(handler, alg, key, iv)
    return CipherStreamHandler:new(handler, alg or DEFAULT_ALG, true, asKey(key), asIv(iv), false)
  end,
}
