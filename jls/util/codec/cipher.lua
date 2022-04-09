local class = require('jls.lang.class')
local StreamHandler = require('jls.io.streams.StreamHandler')
local cipher = require('openssl').cipher

local DEFAULT_ALG = 'aes128'

local CipherStreamHandler = class.create(StreamHandler, function(cipherStreamHandler, super)
  function cipherStreamHandler:initialize(sh, ...)
    super.initialize(self, sh)
    self.handler = sh
    self.ctx = cipher.new(...)
  end
  function cipherStreamHandler:onData(data)
    if data then
      return self.handler:onData(self.ctx:update(data))
    end
    self.handler:onData(self.ctx:final())
    self.handler:onData()
  end
end)

return {
  decode = function(data, alg, ...)
    return cipher.decrypt(alg or DEFAULT_ALG, data, ...)
  end,
  encode = function(data, alg, ...)
    return cipher.encrypt(alg or DEFAULT_ALG, data, ...)
  end,
  decodeStream = function(handler, alg, ...)
    return CipherStreamHandler:new(handler, alg or DEFAULT_ALG, false, ...)
  end,
  encodeStream = function(handler, alg, ...)
    return CipherStreamHandler:new(handler, alg or DEFAULT_ALG, true, ...)
  end,
}
