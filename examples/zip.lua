local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local tables = require('jls.util.tables')
local ZipFile = require('jls.util.zip.ZipFile')

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  emptyPath = 'file',
  aliases = {
    h = 'help',
    a = 'action',
    d = 'dir',
    f = 'file',
    o = 'overwrite',
    ll = 'loglevel',
  },
  schema = {
    title = 'ZIP utility',
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
        title = 'The ZIP file',
        type = 'string'
      },
      overwrite = {
        title = 'Overwrite existing ZIP file',
        type = 'boolean',
        default = false
      },
      dir = {
        title = 'The directory',
        type = 'string',
        default = '.'
      },
      action = {
        title = 'The mode to execute',
        type = 'string',
        default = 'list',
        enum = {'list', 'create', 'extract', 'check'},
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

if options.action == 'extract' then
  ZipFile.unzipTo(options.file, options.dir)
elseif options.action == 'create' then
  ZipFile.zipTo(options.file, options.dir, options.overwrite)
elseif options.action == 'list' then
  local zFile = ZipFile:new(options.file, false)
  local entries = zFile:getEntries()
  zFile:close()
  print('Name', 'Datetime', 'Method', 'CompressedSize', 'Size')
  for _, entry in ipairs(entries) do
    print(entry:getName(), entry:getDatetime():toString(), entry:getMethod(), entry:getCompressedSize(), entry:getSize())
  end
elseif options.action == 'check' then
  local MessageDigest = require('jls.util.MessageDigest')
  local md = MessageDigest:new('Crc32')
  local zFile = ZipFile:new(options.file, false)
  local entries = zFile:getEntries()
  print('Name', 'CRC', 'Check', 'Method', 'CompressedSize', 'Size')
  for _, entry in ipairs(entries) do
    local crc32 = entry:getCrc32()
    local computedCrc32 = 0
    if entry:getSize() > 0 and crc32 ~= 0 then
      local rawContent = assert(zFile:getContentSync(entry))
      computedCrc32 = md:digest(rawContent)
    end
    print(entry:getName(), crc32, crc32 == computedCrc32 and 'ok' or computedCrc32, entry:getMethod(), entry:getCompressedSize(), entry:getSize())
  end
  zFile:close()
end
