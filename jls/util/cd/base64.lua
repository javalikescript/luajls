local class = require('jls.lang.class')
local BlockStreamHandler = require('jls.io.streams.BlockStreamHandler')

local function getIndices(alpha)
  local indices = {}
  for i = 1, #alpha do
    local letter = string.sub(alpha, i, i)
    indices[letter] = i - 1
  end
  return indices
end

local function getLetters(alpha)
  local letters = {}
  for i = 1, #alpha do
    local letter = string.sub(alpha, i, i)
    letters[i - 1] = letter
  end
  return letters
end

local function decode(value, indices)
  if #value % 4 == 1 then
    error('Invalid length')
  end
  return (string.gsub(value, '(.)%s*(.)%s*(.?)%s*(.?)%s*', function(c1, c2, c3, c4)
    local i1 = indices[c1]
    if not i1 then error('Invalid character ('..c1..')') end
    local i2 = indices[c2]
    if not i2 then error('Invalid character ('..c2..')') end
    local b1 = (i1 << 2) | (i2 >> 4)
    if c3 == '' or c3 == '=' then
      return string.char(b1)
    else
      local i3 = indices[c3]
      if not i3 then error('Invalid character ('..c3..')') end
      local b2 = ((i2 & 15) << 4) | (i3 >> 2)
      if c4 == '' or c4 == '=' then
        return string.char(b1, b2)
      else
        local i4 = indices[c4]
        if not i4 then error('Invalid character ('..c4..')') end
        local b3 = ((i3 & 3) << 6) | i4
        return string.char(b1, b2, b3)
      end
    end
  end))
end

local function encode(value, letters, pad)
  return (string.gsub(value, '..?.?', function(ccc)
    local b1, b2, b3 = string.byte(ccc, 1, 3)
    local i1 = b1 >> 2
    local i2, i3, i4
    if b2 then
      i2 = ((b1 & 3) << 4) | (b2 >> 4)
      if b3 then
        i3 = ((b2 & 15) << 2) | (b3 >> 6)
        i4 = b3 & 63
        return letters[i1]..letters[i2]..letters[i3]..letters[i4]
      else
        i3 = ((b2 & 15) << 2)
        if pad then
          return letters[i1]..letters[i2]..letters[i3]..'='
        end
        return letters[i1]..letters[i2]..letters[i3]
      end
    else
      i2 = ((b1 & 3) << 4)
      if pad then
        return letters[i1]..letters[i2]..'=='
      end
      return letters[i1]..letters[i2]
    end
  end))
end

local DecodeStreamHandler = class.create(BlockStreamHandler, function(decodeStreamHandler, super)
  function decodeStreamHandler:initialize(handler, codec)
    super.initialize(self, handler, 4, true)
    self.indices = codec.indices
  end
  function decodeStreamHandler:onData(data)
    return self.handler:onData(data and decode(data, self.indices))
  end
end)

local EncodeStreamHandler = class.create(BlockStreamHandler, function(encodeStreamHandler, super)
  function encodeStreamHandler:initialize(handler, codec)
    super.initialize(self, handler, 3, true)
    self.letters = codec.letters
    self.pad = codec.pad
  end
  function encodeStreamHandler:onData(data)
    return self.handler:onData(data and encode(data, self.letters, self.pad))
  end
end)

local DEFAULT_ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

return require('jls.lang.class').create('jls.util.Codec', function(base64)

  function base64:initialize(alpha, pad)
    if alpha == nil then
      alpha = DEFAULT_ALPHA
    elseif type(alpha) == 'string' then
      if #alpha ~= 64 then
        error('invalid base64 alphabet length, '..tostring(#alpha)..', expected 64')
      end
    else
      error('invalid base64 alphabet type, '..type(alpha)..', expected string')
    end
    self.indices = getIndices(alpha)
    self.letters = getLetters(alpha)
    self.pad = pad ~= false
  end

  function base64:decode(value)
    return decode(value, self.indices)
  end

  function base64:encode(value)
    return encode(value, self.letters, self.pad)
  end

  function base64:decodeStream(sh)
    return DecodeStreamHandler:new(sh, self)
  end

  function base64:encodeStream(sh)
    return EncodeStreamHandler:new(sh, self)
  end

  function base64:getName()
    return 'Base64'
  end

end)
