--- Provide codec functions.
-- @module jls.util.codec

local codec = {}

local CODEC_MAP = {}

--[[
  A codec exposes the following function: decodeStream(sh), encodeStream(sh), decode(d), encode(d)
  Functions may be omited decode() have a default implementation using decodeStream()
]]
function codec.getCodec(alg, ...)
  if type(alg) == 'string' then
    -- TODO wrapped required codec if there are missing methods
    return CODEC_MAP[alg] or require('jls.util.codec.'..alg)
  elseif type(alg) == 'table' then
    return alg
  end
  error('Algorithm not found')
end

function codec.registerCodec(alg, m)
  CODEC_MAP[alg] = m
  return m
end

function codec.decode(alg, data, ...)
  return codec.getCodec(alg).decode(data, ...)
end

function codec.encode(alg, data, ...)
  return codec.getCodec(alg).encode(data, ...)
end

function codec.decodeStream(alg, sh, ...)
  return codec.getCodec(alg).decodeStream(sh, ...)
end

--- Returns an encoding @{jls.io.streams.StreamHandler}.
-- @tparam string alg the name of the encoding or decoding algorithm
-- @tparam StreamHandler stream the wrapped stream that will handle the encoded data
-- @treturn StreamHandler the stream handler that will encode data
function codec.encodeStream(alg, sh, ...)
  return codec.getCodec(alg).encodeStream(sh, ...)
end

return codec