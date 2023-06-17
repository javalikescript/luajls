local lu = require('luaunit')

local dns = require('jls.net.dns')
local logger = require('jls.lang.logger')
local tables = require('jls.util.tables')
local Codec = require('jls.util.Codec')
local hex = Codec.getInstance('hex')

local loop = require('jls.lang.loopWithTimeout')

local function assertAddressInfo(host, addr, family)
  local infos = {}
  dns.getAddressInfo(host):next(function(result)
    infos = result
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  local found = false
  for _, info in ipairs(infos) do
    if (not family or info.family == family) and info.addr == addr then
      found = true
    end
  end
  if not found then
    logger:error('getAddressInfo(%s) %s', host, tables.stringify(infos, 2))
  end
  lu.assertTrue(found)
end

function Test_getAddressInfo()
  assertAddressInfo('localhost', '127.0.0.1', 'inet')
end

function Test_getNameInfo()
  local info
  dns.getNameInfo('127.0.0.1'):next(function(result)
    info = result
  end)
  if not loop() then
    lu.fail('Timeout reached')
  end
  --lu.assertEquals(info, 'localhost')
  lu.assertEquals(type(info), 'string')
  --assertAddressInfo(info, '127.0.0.1', 'inet')
end

function Test_decode_encode_message()
  local raw = hex:decode('007b00000002000000000000045f697070045f746370056c6f63616c00000c0001055f69707073045f746370056c6f63616c00000c0001')
  local message = dns.decodeMessage(raw)
  lu.assertEquals(dns.encodeMessage(message), raw)
end

function Test_encode_decode_message()
  local message = {
    id = 123,
    flags = {
      qr = true,
      opcode = dns.OPCODES.UPDATE,
      aa = true,
      tc = false,
      rd = false,
      ra = false,
      z = false,
      ad = false,
      cd = false,
      rcode = dns.RCODES.NOTAUTH,
    },
    questions = {{
      name = '_ipp._tcp.local',
      type = dns.TYPES.PTR,
      class = dns.CLASSES.IN,
    }, {
      name = '_ipps._tcp.local',
      type = dns.TYPES.PTR,
      class = dns.CLASSES.IN,
      unicastResponse = true,
    }},
    answers={},
    authorities={},
    additionals={},
  }
  --print(tables.stringify(message, 2))
  local raw = dns.encodeMessage(message)
  lu.assertEquals(dns.decodeMessage(raw), message)
end

os.exit(lu.LuaUnit.run())
