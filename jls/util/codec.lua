--- Provide codec functions.
-- Available algorithms are base64, deflate, gzip, hex.
-- @module jls.util.codec
-- @pragma nostrip

--local class = require('jls.lang.class')

local codec = {}

local CODEC_MAP = {}

--- Returns a codec.
-- @tparam string alg the name of the encoding or decoding algorithm
-- @return the codec
function codec.getCodec(alg)
  if type(alg) == 'string' then
    local cd = CODEC_MAP[alg] or require('jls.util.cd.'..alg)
    -- TODO codec should be an instance
    --if class.isClass(cd) then
    --  return cd:new(...)
    --end
    -- TODO wrapped required codec if there are missing methods
    return cd
  end
  error('Algorithm not found')
end

function codec.registerCodec(alg, m)
  CODEC_MAP[alg] = m
  return m
end

--- Returns the decoded data.
-- @tparam string alg the name of the decoding algorithm
-- @tparam string data the data to decode
-- @treturn string the decoded data
function codec.decode(alg, data, ...)
  return codec.getCodec(alg).decode(data, ...)
end

--- Returns the encoded data.
-- @tparam string alg the name of the encoding algorithm
-- @tparam string data the data to encode
-- @treturn string the encoded data
function codec.encode(alg, data, ...)
  return codec.getCodec(alg).encode(data, ...)
end

--- Returns an decoding @{jls.io.StreamHandler}.
-- @tparam string alg the name of the decoding algorithm
-- @tparam StreamHandler sh the wrapped stream that will handle the decoded data
-- @treturn StreamHandler the stream handler that will decode data
function codec.decodeStream(alg, sh, ...)
  return codec.getCodec(alg).decodeStream(sh, ...)
end

--- Returns an encoding @{jls.io.StreamHandler}.
-- @tparam string alg the name of the encoding algorithm
-- @tparam StreamHandler sh the wrapped stream that will handle the encoded data
-- @treturn StreamHandler the stream handler that will encode data
function codec.encodeStream(alg, sh, ...)
  return codec.getCodec(alg).encodeStream(sh, ...)
end

return codec