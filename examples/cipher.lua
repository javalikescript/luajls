local system = require('jls.lang.system')
local File = require('jls.io.File')
local StreamHandler = require('jls.io.StreamHandler')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local tables = require('jls.util.tables')
local Codec = require('jls.util.Codec')
local hex = Codec.getInstance('hex')

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  logPath = 'log-level',
  aliases = {
    h = 'help',
    f = 'file',
    o = 'out',
    a = 'alg',
    k = 'key',
    d = 'decode',
    e = 'encode',
    p = 'part',
    os = 'offset',
    l = 'length',
    ow = 'overwrite',
    ll = 'log-level',
  },
  schema = {
    title = 'Cipher utility',
    type = 'object',
    additionalProperties = false,
    properties = {
      help = {
        title = 'Show the help',
        type = 'boolean',
        default = false
      },
      file = {
        title = 'The input file',
        type = 'string',
      },
      out = {
        title = 'The output file',
        type = 'string',
      },
      info = {
        title = 'Prints algorithm information',
        type = 'boolean',
        default = false
      },
      list = {
        title = 'Lists algorithm',
        type = 'boolean',
        default = false
      },
      digest = {
        title = 'Digest input rather than cipher',
        type = 'boolean',
        default = false
      },
      encoding = {
        title = 'The output encoding',
        type = 'string',
        default = 'none',
        enum = {'none', 'base64', 'hex'},
      },
      decode = {
        title = 'Enables decoding',
        type = 'boolean',
        default = false
      },
      encode = {
        title = 'Enables encoding',
        type = 'boolean',
        default = false
      },
      part = {
        title = 'Enables part decoding',
        type = 'boolean',
        default = false
      },
      iv = {
        title = 'The initial vector in hexadecimal',
        type = 'string',
        pattern = '^%x+$',
        default = '0'
      },
      offset = {
        title = 'The start offset',
        type = 'integer',
      },
      length = {
        title = 'The length, -1 for input file size',
        type = 'integer',
      },
      overwrite = {
        title = 'Overwrite existing output file',
        type = 'boolean',
        default = false
      },
      alg = {
        title = 'The algorithm',
        type = 'string',
      },
      key = {
        title = 'The secret key',
        type = 'string',
        default = 'secret',
      },
    }
  }
})

if options.list then
  local opensslLib = require('openssl')
  local libKey = options.digest and 'digest' or 'cipher'
  print(libKey..' algorithms:')
  for _, v in pairs(opensslLib[libKey].list()) do
    print('', v)
  end
  os.exit(0)
elseif options.info then
  local cipherLib = require('openssl').cipher
  local info = cipherLib.get(options.alg):info()
  print(options.alg)
  for k, v in pairs(info) do
    print('', k, v, type(v))
  end
  os.exit(0)
end

if not options.file then
  print('Please specify an input file')
  os.exit(1)
end

local inFile = File:new(options.file)
if not inFile:exists() then
  print('The input file does not exist', inFile:getPath())
  os.exit(1)
end
local offset = options.offset
local length = options.length
if offset or length then
  offset = offset or 0
  length = length or -1
end
if length and length < 0 then
  length = inFile:length() - offset
end
local sh
if options.out then
  local outFile = File:new(options.out)
  sh = StreamHandler.toFile(outFile, options.overwrite, nil, nil, true)
else
  sh = StreamHandler.std
end
if options.encoding ~= 'none' then
  local codec = Codec.getInstance(options.encoding)
  sh = codec:encodeStream(sh)
end

if options.digest then
  local MessageDigest = require('jls.util.MessageDigest')
  local md = MessageDigest.getInstance(options.alg or 'md5')
  local osh = sh
  sh = StreamHandler:new(function(err, data)
    if err then
      error(err)
    end
    if data then
      md:update(data)
    else
      osh:onData(md:digest())
    end
  end)
else
  local cipher = Codec.getInstance('cipher', options.alg, options.key)
  if options.part then
    local iv = hex:decode(options.iv)
    if options.decode then
      sh, offset, length = cipher:decodeStreamPart(sh, iv, offset, length)
    elseif options.encode then
      sh = cipher:encodeStreamPart(sh, iv)
    end
  else
    if options.decode then
      sh = cipher:decodeStream(sh)
    elseif options.encode then
      sh = cipher:encodeStream(sh)
    end
  end
end

FileStreamHandler.readSync(inFile, sh, offset, length)
