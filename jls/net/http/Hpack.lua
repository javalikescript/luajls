--- Compression format for HTTP headers in HTTP/2
-- @module jls.net.http.Hpack
-- @pragma nostrip

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Map = require('jls.util.Map')
local List = require('jls.util.List')

--local hex = require('jls.util.Codec').getInstance('hex')
--logger = logger:getClass():new(); logger:setLevel('finer')

local function decodeInteger(data, prefixLen, offset)
  prefixLen = prefixLen or 0
  offset = offset or 1
  local max = 0xff >> prefixLen
  local b
  b = string.byte(data, offset)
  --logger:fine('decodeInteger(%q, %d, %d)', data, prefixLen, offset)
  if b then
    offset = offset + 1
    local i = b & max
    if i == max then
      local m = 0
      repeat
        b = string.byte(data, offset)
        if not b then
          return
        end
        --logger:fine('decodeInteger() b:%d(%02x) i:%d m:%d', b, b, i, m)
        offset = offset + 1
        i = ((b & 0x7f) << m) + i
        m = m + 7
      until b & 0x80 == 0
    end
    return i, offset
  end
end

local function encodeInteger(i, prefixLen, prefix)
  prefixLen = prefixLen or 0
  prefix = prefix or 0
  local max = 0xff >> prefixLen
  local q = prefix << 8 - prefixLen
  --logger:fine('encodeInteger(%d, %d, %d) max:%d(%x) q:%d(%x)', i, prefixLen, prefix, max, max, q, q)
  if i < max then
    return string.char(q | i)
  end
  local bytes = { q | max }
  i = i - max
  while i > 0x7f do
    table.insert(bytes, 0x80 | (i & 0x7f))
    i = i >> 7
  end
  table.insert(bytes, i)
  return string.char(table.unpack(bytes))
end

local function packHeader(name, value)
  --return table.concat({ encodeInteger(#name, 0), name, value })
  return {name, value}
end

local function unpackHeader(p)
  --[[
  local len, offset = decodeInteger(s, 0, 1)
  if len then
    local index = offset + len
    return string.sub(s, offset, index - 1), string.sub(s, index)
  end
  ]]
  return p[1], p[2]
end

local function packEqual(p, pp)
  return p[1] == pp[1] and p[2] == pp[2]
end

-- ^ *\| *\d+ *\| *([^ ]+) *\| *([^ ]*) *\| *$

-- See RFC 7541 Appendix A
local STATIC_INDEX_TABLE = List.map({
  ":authority",
  ":method=GET",
  ":method=POST",
  ":path=/",
  ":path=/index.html",
  ":scheme=http",
  ":scheme=https",
  ":status=200",
  ":status=204",
  ":status=206",
  ":status=304",
  ":status=400",
  ":status=404",
  ":status=500",
  "accept-charset",
  "accept-encoding=gzip, deflate",
  "accept-language",
  "accept-ranges",
  "accept",
  "access-control-allow-origin",
  "age",
  "allow",
  "authorization",
  "cache-control",
  "content-disposition",
  "content-encoding",
  "content-language",
  "content-length",
  "content-location",
  "content-range",
  "content-type",
  "cookie",
  "date",
  "etag",
  "expect",
  "expires",
  "from",
  "host",
  "if-match",
  "if-modified-since",
  "if-none-match",
  "if-range",
  "if-unmodified-since",
  "last-modified",
  "link",
  "location",
  "max-forwards",
  "proxy-authenticate",
  "proxy-authorization",
  "range",
  "referer",
  "refresh",
  "retry-after",
  "server",
  "set-cookie",
  "strict-transport-security",
  "transfer-encoding",
  "user-agent",
  "vary",
  "via",
  "www-authenticate",
}, function(s)
  local p = string.find(s, '=', 1, true)
  if p then
    return packHeader(string.sub(s, 1, p - 1), string.sub(s, p + 1))
  end
  return packHeader(s, '')
end)

-- ^.* \|([01\|]+) .*$
-- ^.*([0-9a-f]+) +\[ *(\d+)\] *$
-- { value = 0x$1, bits = $2 },

-- See RFC 7541 Appendix B
local HUFFMAN_CODE = {
  [0] = { value = 0x1ff8, bits = 13 },
  { value = 0x7fffd8, bits = 23 },
  { value = 0xfffffe2, bits = 28 },
  { value = 0xfffffe3, bits = 28 },
  { value = 0xfffffe4, bits = 28 },
  { value = 0xfffffe5, bits = 28 },
  { value = 0xfffffe6, bits = 28 },
  { value = 0xfffffe7, bits = 28 },
  { value = 0xfffffe8, bits = 28 },
  { value = 0xffffea, bits = 24 },
  { value = 0x3ffffffc, bits = 30 },
  { value = 0xfffffe9, bits = 28 },
  { value = 0xfffffea, bits = 28 },
  { value = 0x3ffffffd, bits = 30 },
  { value = 0xfffffeb, bits = 28 },
  { value = 0xfffffec, bits = 28 },
  { value = 0xfffffed, bits = 28 },
  { value = 0xfffffee, bits = 28 },
  { value = 0xfffffef, bits = 28 },
  { value = 0xffffff0, bits = 28 },
  { value = 0xffffff1, bits = 28 },
  { value = 0xffffff2, bits = 28 },
  { value = 0x3ffffffe, bits = 30 },
  { value = 0xffffff3, bits = 28 },
  { value = 0xffffff4, bits = 28 },
  { value = 0xffffff5, bits = 28 },
  { value = 0xffffff6, bits = 28 },
  { value = 0xffffff7, bits = 28 },
  { value = 0xffffff8, bits = 28 },
  { value = 0xffffff9, bits = 28 },
  { value = 0xffffffa, bits = 28 },
  { value = 0xffffffb, bits = 28 },
  { value = 0x14, bits = 6 },
  { value = 0x3f8, bits = 10 },
  { value = 0x3f9, bits = 10 },
  { value = 0xffa, bits = 12 },
  { value = 0x1ff9, bits = 13 },
  { value = 0x15, bits = 6 },
  { value = 0xf8, bits = 8 },
  { value = 0x7fa, bits = 11 },
  { value = 0x3fa, bits = 10 },
  { value = 0x3fb, bits = 10 },
  { value = 0xf9, bits = 8 },
  { value = 0x7fb, bits = 11 },
  { value = 0xfa, bits = 8 },
  { value = 0x16, bits = 6 },
  { value = 0x17, bits = 6 },
  { value = 0x18, bits = 6 },
  { value = 0x0, bits = 5 },
  { value = 0x1, bits = 5 },
  { value = 0x2, bits = 5 },
  { value = 0x19, bits = 6 },
  { value = 0x1a, bits = 6 },
  { value = 0x1b, bits = 6 },
  { value = 0x1c, bits = 6 },
  { value = 0x1d, bits = 6 },
  { value = 0x1e, bits = 6 },
  { value = 0x1f, bits = 6 },
  { value = 0x5c, bits = 7 },
  { value = 0xfb, bits = 8 },
  { value = 0x7ffc, bits = 15 },
  { value = 0x20, bits = 6 },
  { value = 0xffb, bits = 12 },
  { value = 0x3fc, bits = 10 },
  { value = 0x1ffa, bits = 13 },
  { value = 0x21, bits = 6 },
  { value = 0x5d, bits = 7 },
  { value = 0x5e, bits = 7 },
  { value = 0x5f, bits = 7 },
  { value = 0x60, bits = 7 },
  { value = 0x61, bits = 7 },
  { value = 0x62, bits = 7 },
  { value = 0x63, bits = 7 },
  { value = 0x64, bits = 7 },
  { value = 0x65, bits = 7 },
  { value = 0x66, bits = 7 },
  { value = 0x67, bits = 7 },
  { value = 0x68, bits = 7 },
  { value = 0x69, bits = 7 },
  { value = 0x6a, bits = 7 },
  { value = 0x6b, bits = 7 },
  { value = 0x6c, bits = 7 },
  { value = 0x6d, bits = 7 },
  { value = 0x6e, bits = 7 },
  { value = 0x6f, bits = 7 },
  { value = 0x70, bits = 7 },
  { value = 0x71, bits = 7 },
  { value = 0x72, bits = 7 },
  { value = 0xfc, bits = 8 },
  { value = 0x73, bits = 7 },
  { value = 0xfd, bits = 8 },
  { value = 0x1ffb, bits = 13 },
  { value = 0x7fff0, bits = 19 },
  { value = 0x1ffc, bits = 13 },
  { value = 0x3ffc, bits = 14 },
  { value = 0x22, bits = 6 },
  { value = 0x7ffd, bits = 15 },
  { value = 0x3, bits = 5 },
  { value = 0x23, bits = 6 },
  { value = 0x4, bits = 5 },
  { value = 0x24, bits = 6 },
  { value = 0x5, bits = 5 },
  { value = 0x25, bits = 6 },
  { value = 0x26, bits = 6 },
  { value = 0x27, bits = 6 },
  { value = 0x6, bits = 5 },
  { value = 0x74, bits = 7 },
  { value = 0x75, bits = 7 },
  { value = 0x28, bits = 6 },
  { value = 0x29, bits = 6 },
  { value = 0x2a, bits = 6 },
  { value = 0x7, bits = 5 },
  { value = 0x2b, bits = 6 },
  { value = 0x76, bits = 7 },
  { value = 0x2c, bits = 6 },
  { value = 0x8, bits = 5 },
  { value = 0x9, bits = 5 },
  { value = 0x2d, bits = 6 },
  { value = 0x77, bits = 7 },
  { value = 0x78, bits = 7 },
  { value = 0x79, bits = 7 },
  { value = 0x7a, bits = 7 },
  { value = 0x7b, bits = 7 },
  { value = 0x7ffe, bits = 15 },
  { value = 0x7fc, bits = 11 },
  { value = 0x3ffd, bits = 14 },
  { value = 0x1ffd, bits = 13 },
  { value = 0xffffffc, bits = 28 },
  { value = 0xfffe6, bits = 20 },
  { value = 0x3fffd2, bits = 22 },
  { value = 0xfffe7, bits = 20 },
  { value = 0xfffe8, bits = 20 },
  { value = 0x3fffd3, bits = 22 },
  { value = 0x3fffd4, bits = 22 },
  { value = 0x3fffd5, bits = 22 },
  { value = 0x7fffd9, bits = 23 },
  { value = 0x3fffd6, bits = 22 },
  { value = 0x7fffda, bits = 23 },
  { value = 0x7fffdb, bits = 23 },
  { value = 0x7fffdc, bits = 23 },
  { value = 0x7fffdd, bits = 23 },
  { value = 0x7fffde, bits = 23 },
  { value = 0xffffeb, bits = 24 },
  { value = 0x7fffdf, bits = 23 },
  { value = 0xffffec, bits = 24 },
  { value = 0xffffed, bits = 24 },
  { value = 0x3fffd7, bits = 22 },
  { value = 0x7fffe0, bits = 23 },
  { value = 0xffffee, bits = 24 },
  { value = 0x7fffe1, bits = 23 },
  { value = 0x7fffe2, bits = 23 },
  { value = 0x7fffe3, bits = 23 },
  { value = 0x7fffe4, bits = 23 },
  { value = 0x1fffdc, bits = 21 },
  { value = 0x3fffd8, bits = 22 },
  { value = 0x7fffe5, bits = 23 },
  { value = 0x3fffd9, bits = 22 },
  { value = 0x7fffe6, bits = 23 },
  { value = 0x7fffe7, bits = 23 },
  { value = 0xffffef, bits = 24 },
  { value = 0x3fffda, bits = 22 },
  { value = 0x1fffdd, bits = 21 },
  { value = 0xfffe9, bits = 20 },
  { value = 0x3fffdb, bits = 22 },
  { value = 0x3fffdc, bits = 22 },
  { value = 0x7fffe8, bits = 23 },
  { value = 0x7fffe9, bits = 23 },
  { value = 0x1fffde, bits = 21 },
  { value = 0x7fffea, bits = 23 },
  { value = 0x3fffdd, bits = 22 },
  { value = 0x3fffde, bits = 22 },
  { value = 0xfffff0, bits = 24 },
  { value = 0x1fffdf, bits = 21 },
  { value = 0x3fffdf, bits = 22 },
  { value = 0x7fffeb, bits = 23 },
  { value = 0x7fffec, bits = 23 },
  { value = 0x1fffe0, bits = 21 },
  { value = 0x1fffe1, bits = 21 },
  { value = 0x3fffe0, bits = 22 },
  { value = 0x1fffe2, bits = 21 },
  { value = 0x7fffed, bits = 23 },
  { value = 0x3fffe1, bits = 22 },
  { value = 0x7fffee, bits = 23 },
  { value = 0x7fffef, bits = 23 },
  { value = 0xfffea, bits = 20 },
  { value = 0x3fffe2, bits = 22 },
  { value = 0x3fffe3, bits = 22 },
  { value = 0x3fffe4, bits = 22 },
  { value = 0x7ffff0, bits = 23 },
  { value = 0x3fffe5, bits = 22 },
  { value = 0x3fffe6, bits = 22 },
  { value = 0x7ffff1, bits = 23 },
  { value = 0x3ffffe0, bits = 26 },
  { value = 0x3ffffe1, bits = 26 },
  { value = 0xfffeb, bits = 20 },
  { value = 0x7fff1, bits = 19 },
  { value = 0x3fffe7, bits = 22 },
  { value = 0x7ffff2, bits = 23 },
  { value = 0x3fffe8, bits = 22 },
  { value = 0x1ffffec, bits = 25 },
  { value = 0x3ffffe2, bits = 26 },
  { value = 0x3ffffe3, bits = 26 },
  { value = 0x3ffffe4, bits = 26 },
  { value = 0x7ffffde, bits = 27 },
  { value = 0x7ffffdf, bits = 27 },
  { value = 0x3ffffe5, bits = 26 },
  { value = 0xfffff1, bits = 24 },
  { value = 0x1ffffed, bits = 25 },
  { value = 0x7fff2, bits = 19 },
  { value = 0x1fffe3, bits = 21 },
  { value = 0x3ffffe6, bits = 26 },
  { value = 0x7ffffe0, bits = 27 },
  { value = 0x7ffffe1, bits = 27 },
  { value = 0x3ffffe7, bits = 26 },
  { value = 0x7ffffe2, bits = 27 },
  { value = 0xfffff2, bits = 24 },
  { value = 0x1fffe4, bits = 21 },
  { value = 0x1fffe5, bits = 21 },
  { value = 0x3ffffe8, bits = 26 },
  { value = 0x3ffffe9, bits = 26 },
  { value = 0xffffffd, bits = 28 },
  { value = 0x7ffffe3, bits = 27 },
  { value = 0x7ffffe4, bits = 27 },
  { value = 0x7ffffe5, bits = 27 },
  { value = 0xfffec, bits = 20 },
  { value = 0xfffff3, bits = 24 },
  { value = 0xfffed, bits = 20 },
  { value = 0x1fffe6, bits = 21 },
  { value = 0x3fffe9, bits = 22 },
  { value = 0x1fffe7, bits = 21 },
  { value = 0x1fffe8, bits = 21 },
  { value = 0x7ffff3, bits = 23 },
  { value = 0x3fffea, bits = 22 },
  { value = 0x3fffeb, bits = 22 },
  { value = 0x1ffffee, bits = 25 },
  { value = 0x1ffffef, bits = 25 },
  { value = 0xfffff4, bits = 24 },
  { value = 0xfffff5, bits = 24 },
  { value = 0x3ffffea, bits = 26 },
  { value = 0x7ffff4, bits = 23 },
  { value = 0x3ffffeb, bits = 26 },
  { value = 0x7ffffe6, bits = 27 },
  { value = 0x3ffffec, bits = 26 },
  { value = 0x3ffffed, bits = 26 },
  { value = 0x7ffffe7, bits = 27 },
  { value = 0x7ffffe8, bits = 27 },
  { value = 0x7ffffe9, bits = 27 },
  { value = 0x7ffffea, bits = 27 },
  { value = 0x7ffffeb, bits = 27 },
  { value = 0xffffffe, bits = 28 },
  { value = 0x7ffffec, bits = 27 },
  { value = 0x7ffffed, bits = 27 },
  { value = 0x7ffffee, bits = 27 },
  { value = 0x7ffffef, bits = 27 },
  { value = 0x7fffff0, bits = 27 },
  { value = 0x3ffffee, bits = 26 },
}

local HUFFMAN_CODE_BY_VALUE = {}
for index = 0, #HUFFMAN_CODE do
  local item = HUFFMAN_CODE[index]
  HUFFMAN_CODE_BY_VALUE[item.value] = { bits = item.bits, index = index, char = string.char(index) }
end

local HUFFMAN_BITS = {}
for index = 0, #HUFFMAN_CODE do
  HUFFMAN_BITS[HUFFMAN_CODE[index].bits] = true
end
HUFFMAN_BITS = Map.skeys(HUFFMAN_BITS)

--local HUFFMAN_CODE_SORTED = List.map({}, HUFFMAN_CODE, function(item, index) return { value = item.value, bits = item.bits, index = index }; end)
--table.sort(HUFFMAN_CODE_SORTED, function(a, b) return a.bits < b.bits; end)


local function readBits(data, bits, offset)
  --logger:fine('readBits(#%d %s, %s, %s)', #data, hex:encode(data), bits, offset)
  local s = offset // 8 + 1
  local e = (offset + bits - 1) // 8 + 1
  local b1, b2, b3, b4, b5 = string.byte(data, s, e)
  if not b1 then
    error('out of range')
  end
  local v
  local c = e - s
  local d = offset % 8
  if d > 0 then
    --logger:fine('first byte: 0x%x', b1)
    b1 = b1 & (0xff >> d)
    --logger:fine('aligned (%d) first byte: 0x%x', d, b1)
  end
  if c == 0 then
    v = b1
  elseif c == 1 then
    v = (b1 << 8) | b2
  elseif c == 2 then
    v = (b1 << 16) | (b2 << 8) | b3
  elseif c == 3 then
    v = (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
  elseif c == 4 then
    v = (b1 << 32) | (b2 << 24) | (b3 << 16) | (b4 << 8) | b5
  else
    error('invalid bit size')
  end
  d = ((8 - d) + c * 8) - bits
  if d > 0 then
    --logger:fine('full value: 0x%x (%d)', v, d)
    v = v >> d
  end
  --logger:fine('value(%s, %s): %s-%s(%s) 0x%x', bits, offset, s, e, c, v)
  return v
end

local function decodeHuffman(data)
  --logger:fine('decodeHuffman(#%d %s)', #data, hex:encode(data))
  local offset = 0
  local chars = {}
  local size = #data * 8
  while true do
    local noMatch = true
    for _, bits in ipairs(HUFFMAN_BITS) do
      local nextOffset = offset + bits
      if nextOffset > size then
        if size - offset < 8 then -- padding
          return table.concat(chars)
        end
        logger:warn('decodeHuffman(#%d) end of stream at %d/%d "%s"...', #data, offset, size, table.concat(chars))
        error('end of stream')
      end
      local value = readBits(data, bits, offset)
      --logger:fine('readBits(%d, %d): 0x%x', bits, offset, value)
      local item = HUFFMAN_CODE_BY_VALUE[value]
      if item and item.bits == bits then
        offset = nextOffset
        if item.index < 256 then
          table.insert(chars, item.char)
        else
          size = -1
        end
        --logger:fine('decodeHuffman(): "%s"...', table.concat(chars))
        noMatch = false
        break
      end
      item = nil
    end
    if noMatch then
      logger:warn('decodeHuffman(#%d) invalid code at %d/%d "%s"...', #data, offset, size, table.concat(chars))
      error('invalid code')
    end
  end
end

local function encodeHuffman(s)
  --logger:fine('encodeHuffman(#%d %s)', #s, s)
  local l = #s
  local chars = {}
  local offset = 0
  local b = 0
  for i = 1, l do
    local item = HUFFMAN_CODE[string.byte(s, i)]
    local v = item.value
    local bits = item.bits
    --logger:fine('value: 0x%x #%d at %d', v, bits, offset)
    local d = offset % 8
    if d > 0 then
      v = (b << bits) | v
      bits = bits + d
      --logger:fine('full value (%d): 0x%x #%d', d, v, bits)
    end
    while bits > 7 do
      bits = bits - 8
      b = (v >> bits) & 0xff
      table.insert(chars, string.char(b))
      --logger:fine('byte[%d]: 0x%x bits: %d', #chars, b, bits)
    end
    if bits > 0 then
      b = (0xff >> (8 - bits)) & v
      --logger:fine('left byte: 0x%x bits: %d', b, bits)
    end
    offset = offset + item.bits
  end
  local d = offset % 8
  if d > 0 then
    b = (b << (8 - d)) | (0xff >> d)
    table.insert(chars, string.char(b))
  end
  return table.concat(chars)
end

local function decodeString(data, offset)
  local b = string.byte(data, offset)
  if b then
    local h = b & 0x80 ~= 0
    local l
    l, offset = decodeInteger(data, 1, offset)
    local v = string.sub(data, offset, offset + l - 1)
    if h then
      v = decodeHuffman(v)
    end
    return v, offset + l
  end
end

local function encodeString(s, h)
  if h ~= false then
    local es = encodeHuffman(s)
    if h or #s > #es then
      s, h = es, true
    end
  end
  return encodeInteger(#s, 1, h and 1 or 0)..s
end

local HEADER_METHOD = ':method'
local HEADER_SCHEME = ':scheme'
local HEADER_AUTHORITY = ':authority'
local HEADER_PATH = ':path'
local HEADER_STATUS = ':status'
local HEADER_PROTOCOL = ':protocol'

--- The Hpack decodes and encodes HTTP/2 headers.
-- @type Hpack
return class.create(function(hpack)

  --- Creates a new HPACK codec.
  -- @tparam[opt] number maxSize the dynamic table size.
  -- @function Hpack:new
  function hpack:initialize(maxSize)
    -- The dynamic table uses first-in, first-out order
    -- The first and newest entry is at the lowest index, and the oldest entry is at the highest index.
    self.indexes = {}
    self.indexMaxSize = maxSize or math.maxinteger
    self.indexSize = 0
    self.neverIndexed = {}
  end

  function hpack:evictIndex()
    local count = #self.indexes
    if count > 0 then
      local name, value = unpackHeader(self.indexes[count])
      self.indexes[count] = nil
      self.indexSize = self.indexSize - (#name + #value + 32)
      logger:fine('evictIndex() "%s" %d %d/%d', name, count, self.indexSize, self.indexMaxSize)
      return true
    end
    return false
  end

  function hpack:resizeIndexes(indexMaxSize)
    logger:fine('resizeIndexes(%d)', indexMaxSize)
    while self.indexSize > indexMaxSize and self:evictIndex() do end
    self.indexMaxSize = indexMaxSize
  end

  function hpack:getHeader(index)
    logger:finest('getHeader(%d)', index)
    if index <= #STATIC_INDEX_TABLE then
      return unpackHeader(STATIC_INDEX_TABLE[index])
    end
    local i = index - #STATIC_INDEX_TABLE
    if i <= #self.indexes then
      return unpackHeader(self.indexes[i])
    end
    logger:warn('index %d not found', index)
    return ''
  end

  function hpack:indexHeader(name, value)
    if self.indexMaxSize == 0 then
      logger:fine('cannot add header %s %d/%d', name, self.indexSize, self.indexMaxSize)
      return false
    end
    local size = #name + #value + 32
    while self.indexSize + size > self.indexMaxSize and self:evictIndex() do end
    if self.indexSize + size <= self.indexMaxSize then
      self.indexSize = self.indexSize + size
      table.insert(self.indexes, 1, packHeader(name, value))
      logger:fine('indexHeader("%s")', name)
      return true
    end
    logger:fine('cannot add header "%s" %d/%d', name, self.indexSize, self.indexMaxSize)
    return false
  end

  function hpack:getIndex(name, value)
    local p = packHeader(name, value)
    for index, pp in ipairs(STATIC_INDEX_TABLE) do
      if packEqual(p, pp) then
        return index
      end
    end
    for index, pp in ipairs(self.indexes) do
      if packEqual(p, pp) then
        return index + #STATIC_INDEX_TABLE
      end
    end
    return 0
  end

  function hpack:getNameIndex(name)
    for index, p in ipairs(STATIC_INDEX_TABLE) do
      if name == unpackHeader(p) then
        return index
      end
    end
    for index, p in ipairs(self.indexes) do
      if name == unpackHeader(p) then
        return index + #STATIC_INDEX_TABLE
      end
    end
    return 0
  end

  local function addHeader(message, name, value)
    if string.byte(name) == 0x3a then -- ':' character
      if name == HEADER_STATUS then
        message:setStatusCode(value)
      elseif name == HEADER_METHOD then
        message:setMethod(value)
      elseif name == HEADER_PATH then
        message:setTarget(value)
      elseif name == HEADER_AUTHORITY then
        message:setHeader('host', value)
      elseif name == HEADER_SCHEME then
        message.scheme = value
      end
    else
      message:addHeaderValue(name, value)
    end
  end

  function hpack:decodeHeader(data, prefixLen, offset)
    local index, name, value
    index, offset = decodeInteger(data, prefixLen, offset)
    if index == 0 then -- New Name
      name, offset = decodeString(data, offset)
      value, offset = decodeString(data, offset)
    else
      name = self:getHeader(index)
      value, offset = decodeString(data, offset)
    end
    return name, value, offset
  end

  --- Returns the decoded headers.
  -- @tparam jls.net.http.HttpMessage message the target HTTP message.
  -- @tparam string data the data to decode.
  -- @tparam[opt] number offset the data offset.
  -- @tparam[opt] number endOffset the data end offset.
  -- @treturn number the offset after the decoded headers.
  function hpack:decodeHeaders(message, data, offset, endOffset)
    offset = offset or 1
    endOffset = endOffset or #data
    local name, value, index
    while offset <= endOffset do
      local b = string.byte(data, offset)
      if b & 0x80 ~= 0 then
        index, offset = decodeInteger(data, 1, offset)
        if index == 0 then
          error('invalid index')
        end
        name, value = self:getHeader(index)
        addHeader(message, name, value)
      elseif b & 0x40 ~= 0 then
        name, value, offset = self:decodeHeader(data, 2, offset)
        self:indexHeader(name, value)
        addHeader(message, name, value)
      elseif b & 0x20 ~= 0 then
        index, offset = decodeInteger(data, 3, offset)
        self:resizeIndexes(index)
      else
        name, value, offset = self:decodeHeader(data, 4, offset)
        addHeader(message, name, value)
        if b & 0x10 ~= 0 then
          self.neverIndexed[name] = true
        end
      end
      logger:finer('decoded header (0x%02x) "%s" = "%s"', b, name, value)
    end
    logger:fine('decoded headers, indexes %d %d', #self.indexes, self.indexSize)
    return offset
  end

  function hpack:needIndexing(name, value)
    return false, false
  end

  function hpack:encodeHeader(parts, name, value)
    local index = self:getIndex(name, value)
    if index > 0 then
      table.insert(parts, encodeInteger(index, 1, 1))
    else
      local needIndex, neverIndexed = self:needIndexing(name, value)
      index = self:getNameIndex(name)
      if needIndex then
        self:indexHeader(name, value)
        table.insert(parts, encodeInteger(index, 2, 1))
      else
        table.insert(parts, encodeInteger(index, 4, neverIndexed and 1 or 0))
      end
      if index == 0 then
        table.insert(parts, encodeString(name))
      end
      table.insert(parts, encodeString(value))
    end
    logger:finer('encoded header "%s" = "%s", index: %d', name, value, index)
  end

  --- Returns the encoded headers.
  -- @tparam jls.net.http.HttpMessage message the HTTP message.
  -- @treturn string the encoded headers.
  function hpack:encodeHeaders(message)
    local parts = {}
    if message:isRequest() then
      self:encodeHeader(parts, HEADER_METHOD, message:getMethod())
      self:encodeHeader(parts, HEADER_SCHEME, message.scheme or 'https')
      self:encodeHeader(parts, HEADER_PATH, message:getTarget())
      local host = message:getHeader('host')
      if host then
        self:encodeHeader(parts, HEADER_AUTHORITY, host)
      end
    elseif message:isResponse() then
      self:encodeHeader(parts, HEADER_STATUS, tostring(message:getStatusCode()))
    end
    for name, value in Map.spairs(message.headers) do
      if name ~= 'host' then
        if type(value) == 'string' then
          self:encodeHeader(parts, name, value)
        elseif type(value) == 'table' then
          for _, val in ipairs(value) do
            self:encodeHeader(parts, name, val)
          end
        end
      end
    end
    logger:fine('encoded headers, indexes %d %d', #self.indexes, self.indexSize)
    --logger:finest('headers: %s', hex:encode(table.concat(parts)))
    return table.concat(parts)
  end

end, function(Hpack)

  Hpack.decodeInteger = decodeInteger
  Hpack.encodeInteger = encodeInteger

  Hpack.readBits = readBits

  Hpack.decodeHuffman = decodeHuffman
  Hpack.encodeHuffman = encodeHuffman

  Hpack.decodeString = decodeString
  Hpack.encodeString = encodeString

  Hpack.packHeader = packHeader
  Hpack.unpackHeader = unpackHeader

  Hpack.HEADERS = {
    METHOD = HEADER_METHOD,
    SCHEME = HEADER_SCHEME,
    AUTHORITY = HEADER_AUTHORITY,
    PATH = HEADER_PATH,
    STATUS = HEADER_STATUS,
    PROTOCOL = HEADER_PROTOCOL,
  }

end)