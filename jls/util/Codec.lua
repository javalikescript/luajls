--- Represents an encoder/decoder for string or stream.
-- Available codecs are `base64`, `deflate`, `gzip`, `hex`.
-- @module jls.util.Codec
-- @pragma nostrip

local class = require('jls.lang.class')
local WrappedStreamHandler = require('jls.io.StreamHandler').WrappedStreamHandler
local Exception = require('jls.lang.Exception')

local DecodeStreamHandler = class.create(WrappedStreamHandler, function(decodeStreamHandler, super)
  function decodeStreamHandler:initialize(handler, codec)
    super.initialize(self, handler)
    self.codec = codec
  end
  function decodeStreamHandler:onData(data)
    return self.handler:onData(data and self.codec:decode(data))
  end
end)

local EncodeStreamHandler = class.create(WrappedStreamHandler, function(encodeStreamHandler, super)
  function encodeStreamHandler:initialize(handler, codec)
    super.initialize(self, handler)
    self.codec = codec
  end
  function encodeStreamHandler:onData(data)
    return self.handler:onData(data and self.codec:encode(data))
  end
end)

--- The Codec class.
-- The Codec decodes or encodes a string or a stream.
-- @type Codec
return class.create(function(codec)

  --- Decodes the specified string.
  -- @tparam string value the data to decode
  -- @treturn string the decoded string
  -- @raise codec dependent message in case of decoding failure
  function codec:decode(value)
    return value
  end

  --- Encodes the specified string.
  -- @tparam string value the data to encode
  -- @treturn string the encoded string
  -- @raise codec dependent message in case of encoding failure
  function codec:encode(value)
    return value
  end

  function codec:decodeSafe(value)
    return Exception.try(self.decode, self, value)
  end

  function codec:encodeSafe(value)
    return Exception.try(self.encode, self, value)
  end

  --- Returns a decoding @{jls.io.StreamHandler}.
  -- The default implentation consists in using the decode method.
  -- @tparam StreamHandler sh the wrapped stream that will handle the decoded data
  -- @treturn StreamHandler the stream handler that will decode data
  function codec:decodeStream(sh)
    return DecodeStreamHandler:new(sh, self)
  end

  --- Returns a encoding @{jls.io.StreamHandler}.
  -- The default implentation consists in using the encode method.
  -- @tparam StreamHandler sh the wrapped stream that will handle the encoded data
  -- @treturn StreamHandler the stream handler that will encode data
  function codec:encodeStream(sh)
    return EncodeStreamHandler:new(sh, self)
  end

  --- Returns the name of the codec.
  -- @treturn string the name of the codec
  function codec:getName()
    return self.name or class.getName(self:getClass()) or 'Codec'
  end

end, function(Codec)

  --- Returns the Codec class corresponding to the specified name.
  -- @tparam string name The name of the codec
  -- @return The Codec class
  function Codec.getCodec(name)
    return require('jls.util.cd.'..string.lower(string.gsub(name, '[%s%-]', '')))
  end

  --- Returns a new Codec.
  -- @tparam string name The name of the codec
  -- @treturn Codec a new Codec
  -- @usage
  --local codec = Codec.getInstance('Base64')
  --codec:encode('Hello !')
  function Codec.getInstance(name, ...)
    return Codec.getCodec(name):new(...)
  end

  function Codec.decode(name, value, ...)
    return Codec.getCodec(name):new(...):decode(value)
  end
  function Codec.encode(name, value, ...)
    return Codec.getCodec(name):new(...):encode(value)
  end
  function Codec.decodeStream(name, sh, ...)
    return Codec.getCodec(name):new(...):decodeStream(sh)
  end
  function Codec.encodeStream(name, sh, ...)
    return Codec.getCodec(name):new(...):encodeStream(sh)
  end

  -- for compatibility, to remove
  function Codec:compat()
    return {
      decode = function(value, ...)
        return self:new(...):decode(value)
      end,
      encode = function(value, ...)
        return self:new(...):encode(value)
      end,
      decodeStream = function(sh, ...)
        return self:new(...):decodeStream(sh)
      end,
      encodeStream = function(sh, ...)
        return self:new(...):encodeStream(sh)
      end,
    }
  end

end)
