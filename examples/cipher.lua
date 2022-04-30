local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local File = require('jls.io.File')
local StreamHandler = require('jls.io.StreamHandler')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local tables = require('jls.util.tables')
local cipher = require('jls.util.cd.cipher')

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
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
    ll = 'loglevel',
  },
  schema = {
    title = 'Cipher utility',
    type = 'object',
    additionalProperties = false,
    required = {'file'},
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
      offset = {
        title = 'The start offset',
        type = 'integer',
      },
      length = {
        title = 'The length, -1 for input file size',
        type = 'integer',
      },
      overwrite = {
        title = 'Overwrite existing ZIP file',
        type = 'boolean',
        default = false
      },
      alg = {
        title = 'The cipher algorithm',
        type = 'string',
        default = 'aes-128-ctr',
      },
      key = {
        title = 'The secret key',
        type = 'string',
        default = 'secret',
      },
      loglevel = {
        title = 'The log level',
        type = 'string',
        default = 'warn',
        enum = {'error', 'warn', 'info', 'config', 'fine', 'finer', 'finest', 'debug', 'all'},
      },
    }
  }
})

logger:setLevel(options.loglevel)

if options.info then
  local cipherLib = require('openssl').cipher
  local info = cipherLib.get(options.alg):info()
  print(options.alg)
  for k, v in pairs(info) do
    print('', k, v, type(v))
  end
  os.exit(0)
end

local inFile = File:new(options.file)

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
  sh = StreamHandler.file(outFile, options.overwrite, nil, nil, true)
else
  sh = StreamHandler.std
end
local o, l = offset, length
if options.part then
  if options.decode then
    sh, o, l = cipher.decodeStreamPart(sh, options.alg, options.key, nil, offset, length)
  elseif options.encode then
    sh = cipher.encodeStreamPart(sh, options.alg, options.key)
  end
else
  if options.decode then
    sh = cipher.decodeStream(sh, options.alg, options.key)
  elseif options.encode then
    sh = cipher.encodeStream(sh, options.alg, options.key)
  end
end
FileStreamHandler.readSync(inFile, sh, o, l)
