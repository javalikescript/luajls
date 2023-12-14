local lu = require('luaunit')

local Hpack = require('jls.net.http.Hpack')
local HttpMessage = require('jls.net.http.HttpMessage')
local Map = require('jls.util.Map')
local Codec = require('jls.util.Codec')
local hex = Codec.getInstance('hex', false, true)

local function assertEncodeInteger(expected, i, prefixLen, prefix)
  local s = Hpack.encodeInteger(i, prefixLen or 3, prefix or 0)
  if s ~= expected then
    lu.assertEquals('0x'..hex:encode(s), '0x'..hex:encode(expected))
  end
end

function Test_decodeInteger()
  lu.assertEquals(Hpack.decodeInteger('\0', 3), 0)
  lu.assertEquals(Hpack.decodeInteger('\5', 3), 5)
  lu.assertEquals(Hpack.decodeInteger('\31\69', 3), 100)
  lu.assertEquals(Hpack.decodeInteger('\31\141\2', 3), 300)
end

function Test_encodeInteger()
  assertEncodeInteger('\0', 0)
  assertEncodeInteger('\5', 5)
  assertEncodeInteger('\31\69', 100)
  assertEncodeInteger('\31\141\2', 300)
  assertEncodeInteger('\133', 5, 1, 1)
  assertEncodeInteger('\37', 5, 3, 1)
  assertEncodeInteger('\21', 5, 4, 1)
end

local function assertEncodeDecodeString(s)
  lu.assertEquals(Hpack.decodeString(Hpack.encodeString(s)), s)
end

function Test_encodeString()
  assertEncodeDecodeString(':status')
  lu.assertEquals(Hpack.encodeString('<<'), '\2<<')
  lu.assertEquals(Hpack.encodeString('&*,'), '\3&*,')
  lu.assertEquals(string.byte(Hpack.encodeString('0/1')), 0x82)
end

function Test_encodeDecodeInteger()
  for _, i in ipairs({0, 1, 10, 100, 200, 300, 0xcafecafe}) do
    for _, prefixLen in ipairs({1, 2, 3, 4}) do
      for _, prefix in ipairs({0, 1}) do
        lu.assertEquals(Hpack.decodeInteger(Hpack.encodeInteger(i, prefixLen, prefix), prefixLen, 1), i)
      end
    end
  end
end

local function assertPackUnpack(name, value)
  local n, v = Hpack.unpackHeader(Hpack.packHeader(name, value))
  lu.assertEquals(n, name)
  lu.assertEquals(v, value)
end

function Test_pack_unpack()
  --lu.assertEquals(Hpack.packHeader('n', 'v'), '\1nv')
  --lu.assertEquals({Hpack.unpackHeader('\1nv')}, {'n', 'v'})
  assertPackUnpack('a', 'b')
  assertPackUnpack('a', '')
  assertPackUnpack('', 'b')
  assertPackUnpack('', '')
  assertPackUnpack(string.rep('-', 300), 'b')
end

function Test_readBits()
  lu.assertEquals(Hpack.readBits('\241\227', 7, 0), 0x78)
  lu.assertEquals(Hpack.readBits('\241\227', 7, 7), 0x78)
  lu.assertEquals(Hpack.readBits('\241\227\194\229', 7, 14), 0x78)
  lu.assertEquals(Hpack.readBits('\241\227\194\229', 6, 21), 0x17)
  lu.assertEquals(Hpack.readBits('\249\99\231', 8, 14), 0xf9)
end

function Test_decodeHuffman()
  lu.assertEquals(Hpack.decodeHuffman(hex:decode('f1e3c2e5f23a6ba0ab90f4ff')), 'www.example.com')
  lu.assertEquals(Hpack.decodeHuffman(hex:decode('a8eb10649cbf')), 'no-cache')
  lu.assertEquals(Hpack.decodeHuffman(hex:decode('f963e7')), '*/*')
  lu.assertEquals(Hpack.decodeHuffman(hex:decode('ffcffd7ffffff9')), '$#\n')
end

function Test_encodeHuffman()
  lu.assertEquals(hex:encode(Hpack.encodeHuffman('www.example.com')), 'f1e3c2e5f23a6ba0ab90f4ff')
  lu.assertEquals(hex:encode(Hpack.encodeHuffman('no-cache')), 'a8eb10649cbf')
  lu.assertEquals(hex:encode(Hpack.encodeHuffman('*/*')), 'f963e7')
  -- 1ff9(13) ffa(12) 3ffffffc(30) = 55
  -- 11111111|11001 111|11111101|0 1111111|11111111|11111111|1111100 1
  lu.assertEquals(hex:encode(Hpack.encodeHuffman('$#\n')), 'ffcffd7ffffff9')
  -- 3ffffffc (30) 3ffffffd (30) = 60
  -- 11111111|11111111|11111111|111101 11|11111111|11111111|11111111|1100
  lu.assertEquals(hex:encode(Hpack.encodeHuffman('\13\10')), 'fffffff7ffffffcf')
end

function Test_huffman()
  for _, s in ipairs({'127.0.0.1:3002', 'curl/7.58.0', '*/*', 'chars $ # \r\n are rares'}) do
    lu.assertEquals(Hpack.decodeHuffman(Hpack.encodeHuffman(s)), s)
  end
end

local function decodeHeaders(hpack, data, offset, endOffset)
  local message = HttpMessage:new()
  hpack:decodeHeaders(message, data, offset, endOffset)
  local headers = message:getHeadersTable()
  if message:getMethod() then
    headers[':method'] = message:getMethod()
    headers[':scheme'] = message.scheme
    headers[':path'] = message:getTarget()
    headers[':authority'] = headers.host
    headers.host = nil
  else
    headers[':status'] = tostring(message:getStatusCode())
  end
  return headers
end

local function encodeHeaders(hpack, headers)
  local message = HttpMessage:new()
  if headers[':method'] then
    message:setMethod(headers[':method'])
    message.scheme = headers[':scheme']
    message:setTarget(headers[':path'])
  else
    message:setStatusCode(headers[':status'])
  end
  for name, value in pairs(headers) do
    message:setHeader(name, value)
  end
  return hpack:encodeHeaders(message)
end

local headersResponse1 = {
  [':status'] = '302',
  ['cache-control'] = 'private',
  ['date'] = 'Mon, 21 Oct 2013 20:13:21 GMT',
  ['location'] = 'https://www.example.com',
}
local headersResponse2 = Map.assign({}, headersResponse1, {
  [':status'] = '307',
})
local headersResponse3 = Map.assign({}, headersResponse1, {
  [':status'] = '200',
  ['date'] = 'Mon, 21 Oct 2013 20:13:22 GMT',
  ['content-encoding'] = 'gzip',
  ['set-cookie'] = 'foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1',
})

function Test_decodeHeadersResponse()
  local hpack = Hpack:new(256)
  lu.assertEquals(decodeHeaders(hpack, hex:decode([[
    4803 3330 3258 0770 7269 7661 7465 611d
    4d6f 6e2c 2032 3120 4f63 7420 3230 3133
    2032 303a 3133 3a32 3120 474d 546e 1768
    7474 7073 3a2f 2f77 7777 2e65 7861 6d70
    6c65 2e63 6f6d
  ]])), headersResponse1)
  lu.assertEquals(decodeHeaders(hpack, hex:decode(
    '4803 3330 37c1 c0bf'
  )), headersResponse2)
  lu.assertEquals(decodeHeaders(hpack, hex:decode([[
    88c1 611d 4d6f 6e2c 2032 3120 4f63 7420
    3230 3133 2032 303a 3133 3a32 3220 474d
    54c0 5a04 677a 6970 7738 666f 6f3d 4153
    444a 4b48 514b 425a 584f 5157 454f 5049
    5541 5851 5745 4f49 553b 206d 6178 2d61
    6765 3d33 3630 303b 2076 6572 7369 6f6e
    3d31
   ]])), headersResponse3)
end

function Test_decodeHeadersResponseHuffman()
  local hpack = Hpack:new(256)
  lu.assertEquals(decodeHeaders(hpack, hex:decode([[
    4882 6402 5885 aec3 771a 4b61 96d0 7abe
    9410 54d4 44a8 2005 9504 0b81 66e0 82a6
    2d1b ff6e 919d 29ad 1718 63c7 8f0b 97c8
    e9ae 82ae 43d3
  ]])), headersResponse1)
  lu.assertEquals(decodeHeaders(hpack, hex:decode(
    '4883 640e ffc1 c0bf'
  )), headersResponse2)
  lu.assertEquals(decodeHeaders(hpack, hex:decode([[
    88c1 6196 d07a be94 1054 d444 a820 0595
    040b 8166 e084 a62d 1bff c05a 839b d9ab
    77ad 94e7 821d d7f2 e6c7 b335 dfdf cd5b
    3960 d5af 2708 7f36 72c1 ab27 0fb5 291f
    9587 3160 65c0 03ed 4ee5 b106 3d50 07
  ]])), headersResponse3)
end

local headersRequest1 = {
  [':method'] = 'GET',
  [':scheme'] = 'http',
  [':path'] = '/',
  [':authority'] = 'www.example.com',
}
local headersRequest2 = Map.assign({}, headersRequest1, {
  ['cache-control'] = 'no-cache',
})
local headersRequest3 =  Map.assign({}, headersRequest1, {
  [':scheme'] = 'https',
  [':path'] = '/index.html',
  ['custom-key'] = 'custom-value',
})

function Test_decodeHeadersRequest()
  local hpack = Hpack:new(256)
  lu.assertEquals(decodeHeaders(hpack, hex:decode([[
    8286 8441 0f77 7777 2e65 7861 6d70 6c65
    2e63 6f6d
   ]])), headersRequest1)
  lu.assertEquals(decodeHeaders(hpack, hex:decode(
    '8286 84be 5808 6e6f 2d63 6163 6865'
  )), headersRequest2)
  lu.assertEquals(decodeHeaders(hpack, hex:decode([[
    8287 85bf 400a 6375 7374 6f6d 2d6b 6579
    0c63 7573 746f 6d2d 7661 6c75 65
  ]])), headersRequest3)
end

function Test_decodeHeadersRequestHuffman()
  local hpack = Hpack:new(256)
  lu.assertEquals(decodeHeaders(hpack, hex:decode([[
    8286 8441 8cf1 e3c2 e5f2 3a6b a0ab 90f4
    ff
    ]])), headersRequest1)
  lu.assertEquals(decodeHeaders(hpack, hex:decode(
    '8286 84be 5886 a8eb 1064 9cbf'
  )), headersRequest2)
  lu.assertEquals(decodeHeaders(hpack, hex:decode([[
    8287 85bf 4088 25a8 49e9 5ba9 7d7f 8925
    a849 e95b b8e8 b4bf
   ]])), headersRequest3)
end

function Test_encodeDecodeHeaders()
  local encHpack = Hpack:new()
  local decHpack = Hpack:new()
  lu.assertEquals(decodeHeaders(decHpack, encodeHeaders(encHpack, headersRequest1)), headersRequest1)
end

os.exit(lu.LuaUnit.run())
