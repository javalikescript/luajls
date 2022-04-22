local class = require('jls.lang.class')
local StreamHandler = require('jls.io.streams.StreamHandler')
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
local DEFAULT_KEY = 'secret'
return {
  decode = function(data, alg, key, ...)
    return cipherLib.decrypt(alg or DEFAULT_ALG, data, key or DEFAULT_KEY, ...)
  end,
  encode = function(data, alg, key, ...)
    return cipherLib.encrypt(alg or DEFAULT_ALG, data, key or DEFAULT_KEY, ...)
  end,
  decodeStream = function(handler, alg, key, ...)
    return CipherStreamHandler:new(handler, alg or DEFAULT_ALG, false, key or DEFAULT_KEY, ...)
  end,
  encodeStream = function(handler, alg, key, ...)
    return CipherStreamHandler:new(handler, alg or DEFAULT_ALG, true, key or DEFAULT_KEY, ...)
  end,
}
