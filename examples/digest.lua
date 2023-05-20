local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local File = require('jls.io.File')
local StreamHandler = require('jls.io.StreamHandler')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local tables = require('jls.util.tables')
local MessageDigest = require('jls.util.MessageDigest')
local hex = require('jls.util.hex')

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  aliases = {
    h = 'help',
    f = 'file',
    a = 'alg',
    ll = 'loglevel',
  },
  schema = {
    title = 'Digest utility',
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
      alg = {
        title = 'The message digest algorithm',
        type = 'string',
        default = 'md5',
      },
      list = {
        title = 'Lists (openssl) algorithms',
        type = 'boolean',
        default = false
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

if options.list then
  local opensslLib = require('openssl')
  print('Digest algorithms:')
  for _, v in pairs(opensslLib.digest.list()) do
    print('', v)
  end
  os.exit(0)
end

if not options.file then
  print('Please specify an input file')
  os.exit(1)
end

local md = MessageDigest.getInstance(options.alg)

local inFile = File:new(options.file)
if not inFile:exists() then
  print('The input file does not exist', inFile:getPath())
  os.exit(1)
end

local sh = StreamHandler:new(function(err, data)
  if err then
    print('error', err)
    os.exit(1)
  else
    if data then
      md:update(data)
    else
      print('digest', hex.encode(md:digest()))
    end
  end
end)

FileStreamHandler.readSync(inFile, sh)
