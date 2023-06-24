--- Provides DNS related functions.
-- @module jls.net.dns
-- @pragma nostrip

local lib = require('jls.lang.loader').requireOne('jls.net.dns-luv', 'jls.net.dns-socket')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local Map = require("jls.util.Map")
local List = require("jls.util.List")
local strings = require("jls.util.strings")
local StringBuffer = require('jls.lang.StringBuffer')

local dns = {}

--- Lookups address info for a specified hostname.
-- The result consists in a table with an "addr" field containing the IP address.
-- @tparam string node the hostname.
-- @tparam[opt] function callback an optional callback function to use in place of promise.
-- @treturn jls.lang.Promise a promise that resolves to the address informations.
function dns.getAddressInfo(node, callback)
  local cb, d = Promise.ensureCallback(callback)
  lib.getaddrinfo(node, cb)
  return d
end

--- Lookups host name for a specified IP address.
-- @tparam string addr the IP Address.
-- @tparam[opt] function callback an optional callback function to use in place of promise.
-- @treturn jls.lang.Promise a promise that resolves to the host name.
function dns.getNameInfo(addr, callback)
  local cb, d = Promise.ensureCallback(callback)
  lib.getnameinfo(addr, cb)
  return d
end

function dns.getInterfaceAddresses(family)
  family = family or 'inet'
  local ips = {}
  local addresses = lib.interface_addresses()
  -- eth0 Ethernet Wi-Fi
  for name, addresse in pairs(addresses) do
    for _, info in ipairs(addresse) do
      if not info.internal and info.family == family then
        table.insert(ips, info.ip)
      end
    end
  end
  return ips
end

-- Message encoding/decoding
-- see https://datatracker.ietf.org/doc/html/rfc1035

local OPCODES = {
  QUERY = 0,
  IQUERY = 1,
  STATUS = 2,
  NOTIFY = 4,
  UPDATE = 5,
}
local RCODES = {
  NOERROR = 0, -- No error condition
  FORMERR = 1, -- Format error - The name server was unable to interpret the query.
  SERVFAIL = 2, -- Server failure - The name server was unable to process this query due to a problem with the name server.
  NXDOMAIN = 3, -- Name Error - Meaningful only for responses from an authoritative name server, this code signifies that the domain name referenced in the query does not exist.
  NOTIMP = 4, -- Not Implemented - The name server does not support the requested kind of query.
  REFUSED = 5, -- Refused - The name server refuses to perform the specified operation for policy reasons.
  YXDOMAIN = 6,
  YXRRSET = 7,
  NXRRSET = 8,
  NOTAUTH = 9,
  NOTZONE = 10,
}
local CLASSES = {
  IN = 1, -- the Internet
  CS = 2, -- the CSNET class (Obsolete - used only for examples in some obsolete RFCs)
  CH = 3, -- the CHAOS class
  HS = 4, -- Hesiod [Dyer 87]
  ANY = 255, -- *
}
local TYPES = {
  A = 1, -- a host address
  NS = 2, -- an authoritative name server
  -- MD = 3, -- a mail destination (Obsolete - use MX)
  -- MF = 4, -- a mail forwarder (Obsolete - use MX)
  CNAME = 5, -- the canonical name for an alias
  SOA = 6, -- marks the start of a zone of authority
  -- MB = 7 -- a mailbox domain name (EXPERIMENTAL)
  -- MG = 8 -- a mail group member (EXPERIMENTAL)
  -- MR = 9 -- a mail rename domain name (EXPERIMENTAL)
  NULL = 10,-- a null RR (EXPERIMENTAL)
  WKS = 11, -- a well known service description
  PTR = 12, -- a domain name pointer
  HINFO = 13, -- host information
  MINFO = 14, -- mailbox or mail list information
  MX = 15, -- mail exchange
  TXT = 16, -- text strings
  RP = 17,
  AFSDB = 18,
  SIG = 24,
  KEY = 25,
  AAAA = 28,
  LOC = 29,
  SRV = 33, -- Service locator
  NAPTR = 35,
  KX = 36,
  CERT = 37,
  DNAME = 39,
  OPT = 41,
  APL = 42,
  DS = 43,
  SSHFP = 44,
  IPSECKEY = 45,
  RRSIG = 46,
  NSEC = 47,
  DNSKEY = 48,
  DHCID = 49,
  NSEC3 = 50,
  NSEC3PARAM = 51,
  TLSA = 52,
  HIP = 55,
  CDS = 59,
  CDNSKEY = 60,
  SPF = 99,
  TKEY = 249,
  TSIG = 250,
  IXFR = 251,
  AXFR = 252, -- 252 A request for a transfer of an entire zone
  -- MAILB = 253, -- A request for mailbox-related records (MB, MG or MR)
  -- MAILA = 254, -- A request for mail agent RRs (Obsolete - see MX)
  ANY = 255, -- 255 A request for all records
  CAA = 257,
  TA = 32768,
  DLV = 32769,
}

local OPCODES_MAP = Map.reverse(OPCODES)
local RCODES_MAP = Map.reverse(RCODES)
local TYPES_MAP = Map.reverse(TYPES)
local CLASSES_MAP = Map.reverse(CLASSES)

dns.OPCODES = OPCODES
dns.RCODES = RCODES
dns.TYPES = TYPES
dns.CLASSES = CLASSES
dns.TYPES_MAP = TYPES_MAP
dns.CLASSES_MAP = CLASSES_MAP

local function decodeNameParts(data, offset)
  local parts = {}
  local size = #data
  while offset <= size do
    local len = string.byte(data, offset)
    --logger:fine('offset: %d, len: %d', offset, len)
    offset = offset + 1
    if len == 0 then
      break
    elseif len & 0xc0 == 0xc0 then
      local ptr = string.byte(data, offset)
      offset = offset + 1
      ptr = ((len - 0xc0) << 8) + ptr
      if ptr >= offset then
        error('bad pointer')
      end
      List.concat(parts, (decodeNameParts(data, ptr + 1)))
      break
    end
    local part = string.sub(data, offset, offset + len - 1)
    offset = offset + len
    table.insert(parts, part)
  end
  return parts, offset
end

local function decodeName(data, offset)
  local parts
  parts, offset = decodeNameParts(data, offset)
  return table.concat(parts, '.'), offset
end

local function encodeName(name)
  local buffer = StringBuffer:new()
  local parts = strings.split(name, '.', true)
  -- TODO compression
  for _, part in ipairs(parts) do
    if #part > 0 then
      buffer:append(string.char(#part), part)
    end
  end
  buffer:append('\0')
  return buffer:toString()
end

local DECODERS = {
  [TYPES.A] = function(data, offset)
    return string.format('%d.%d.%d.%d', string.byte(data, offset, offset + 3))
  end,
  [TYPES.PTR] = function(data, offset)
    return decodeName(data, offset)
  end,
  [TYPES.SRV] = function(data, offset)
    local priority, weight, port, target
    priority, weight, port, offset = string.unpack('>I2I2I2', data, offset)
    target = decodeName(data, offset)
    return {
      priority = priority,
      weight = weight,
      port = port,
      target = target,
    }
  end,
  [TYPES.TXT] = function(data, offset)
    local parts = {}
    local size = #data
    while offset <= size do
      local len = string.byte(data, offset)
      offset = offset + 1
      local part
      if len > 0 then
        part = string.sub(data, offset, offset + len - 1)
        offset = offset + len
      else
        part = ''
      end
      table.insert(parts, part)
    end
    return parts, offset
  end,
}
local ENCODERS = {
  [TYPES.A] = function(value)
    return string.char(table.unpack(List.map({string.match(value, '(%d+)%.(%d+)%.(%d+)%.(%d+)')}, function(s) return tonumber(s); end)))
  end,
  [TYPES.PTR] = function(value)
    return encodeName(value)
  end,
  [TYPES.SRV] = function(value)
    return string.pack('>I2I2I2', value.priority or 0, value.weight or 0, value.port or 0)..encodeName(value.target or '')
  end,
  [TYPES.TXT] = function(value)
    local buffer = StringBuffer:new()
    for _, part in ipairs(value) do
      buffer:append(string.char(#part), part)
    end
    return buffer:toString()
  end,
}

local questionFormat = '>I2I2'

local function decodeQuestion(data, offset)
  local name, qtype, qclass
  name, offset = decodeName(data, offset)
  logger:fine('name: "%s" => %d', name, offset)
  qtype, qclass, offset = string.unpack(questionFormat, data, offset)
  if logger:isLoggable(logger.FINE) then
    logger:fine('question: %s(%d) %s(%d) => %d', TYPES_MAP[qtype], qtype, CLASSES_MAP[qclass], qclass, offset)
  end
  return {
    name = name,
    type = qtype,
    class = qclass & 0x7fff,
    unicastResponse = ((qclass >> 15) & 1 == 1) or nil,
  }, offset
end

local function encodeQuestion(question)
  local qclass = question.class
  if question.unicastResponse then
    qclass = qclass | 0x8000
  end
  return encodeName(question.name)..string.pack(questionFormat, question.type, qclass)
end

local resourceRecordFormat = '>I2I2I4I2'

local function decodeResourceRecord(data, offset)
  local name, qtype, qclass, ttl, rdLen
  name, offset = decodeName(data, offset)
  qtype, qclass, ttl, rdLen, offset = string.unpack(resourceRecordFormat, data, offset)
  local rdData = string.sub(data, offset, offset + rdLen - 1)
  -- The format of this information varies according to the TYPE and CLASS of the resource record.
  -- For example, the if the TYPE is A and the CLASS is IN, the RDATA field is a 4 octet ARPA Internet address.
  local decode = DECODERS[qtype]
  local value
  if decode then
    value = decode(data, offset)
  end
  return {
    name = name,
    type = qtype,
    class = qclass & 0x7fff,
    cacheFlush = ((qclass >> 15) & 1 == 1) or nil,
    ttl = ttl,
    data = rdData,
    value = value
  }, offset + rdLen
end

local function encodeResourceRecord(rr)
  local qclass = rr.class
  if rr.cacheFlush then
    qclass = qclass | 0x8000
  end
  local data
  local encode = ENCODERS[rr.type]
  if rr.value and encode then
    data = encode(rr.value)
  else
    data = rr.data or ''
  end
  return encodeName(rr.name)..string.pack(resourceRecordFormat, rr.type, qclass, rr.ttl or 0, #data)..data
end

local function decodeList(data, offset, decode, count)
  local items = {}
  for _ = 1, count do
    local item
    item, offset = decode(data, offset)
    table.insert(items, item)
  end
  return items, offset
end

local function encodeList(list, encode, parts)
  if list then
    for _, item in ipairs(list) do
      table.insert(parts, encode(item))
    end
  end
end

local headerFormat = '>I2I2I2I2I2I2'

function dns.decodeMessage(data, offset)
  local id, flags, nbQuestions, nbAnswers, nbAuthorities, nbAdditionals
  id, flags, nbQuestions, nbAnswers, nbAuthorities, nbAdditionals, offset = string.unpack(headerFormat, data, offset or 1)
  logger:fine('header is id: 0x%x, flags: 0x%x, %d %d %d %d => %d', id, flags, nbQuestions, nbAnswers, nbAuthorities, nbAdditionals, offset)
  local questions, answers, authorities, additionals
  questions, offset = decodeList(data, offset, decodeQuestion, nbQuestions)
  answers, offset = decodeList(data, offset, decodeResourceRecord, nbAnswers)
  authorities, offset = decodeList(data, offset, decodeResourceRecord, nbAuthorities)
  additionals, offset = decodeList(data, offset, decodeResourceRecord, nbAdditionals)
  return {
    id = id,
    flags = {
      qr = ((flags >> 15) & 1) == 1, -- message is a query (0), or a response (1)
      opcode = (flags >> 11) & 0xf,
      aa = ((flags >> 10) & 1) == 1, -- Authoritative Answer 
      tc = ((flags >> 9) & 1) == 1, -- TrunCation specifies that this message was truncated
      rd = ((flags >> 8) & 1) == 1, -- Recursion Desired
      ra = ((flags >> 7) & 1) == 1, -- Recursion Available
      z = ((flags >> 6) & 1) == 1, -- Reserved for future use
      ad = ((flags >> 5) & 1) == 1, -- authentic data
      cd = ((flags >> 4) & 1) == 1, -- checking disabled
      rcode = flags & 0xf,
    },
    questions = questions,
    answers = answers,
    authorities = authorities,
    additionals = additionals,
  }
end

function dns.encodeMessage(message)
  local parts = {}
  local flags = message.flags
  if type(flags) == 'table' then
    flags = ((flags.rcode or 0) & 0xf)
      | ((flags.cd and 1 or 0) << 4)
      | ((flags.ad and 1 or 0) << 5)
      | ((flags.z and 1 or 0) << 6)
      | ((flags.ra and 1 or 0) << 7)
      | ((flags.rd and 1 or 0) << 8)
      | ((flags.tc and 1 or 0) << 9)
      | ((flags.aa and 1 or 0) << 10)
      | (((flags.opcode or 0) & 0xf) << 11)
      | ((flags.qr and 1 or 0) << 15)
  elseif type(flags) == 'number' then
    flags = flags & 0xffff
  else
    flags = 0
  end
  local id = message.id or math.random(0, 0xffff)
  local header = string.pack(headerFormat, id, flags,
    message.questions and #message.questions or 0, message.answers and #message.answers or 0,
    message.authorities and #message.authorities or 0, message.additionals and #message.additionals or 0)
  table.insert(parts, header)
  encodeList(message.questions, encodeQuestion, parts)
  encodeList(message.answers, encodeResourceRecord, parts)
  encodeList(message.authorities, encodeResourceRecord, parts)
  encodeList(message.additionals, encodeResourceRecord, parts)
  return table.concat(parts)
end

return dns
