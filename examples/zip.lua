local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local tables = require('jls.util.tables')
local ZipFile = require('jls.util.zip.ZipFile')

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  emptyPath = 'file',
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
  local md = require('jls.util.MessageDigest'):new('Crc32')
  local zFile = ZipFile:new(options.file, false)
  local entries = zFile:getEntries()
  for _, entry in ipairs(entries) do
    print(entry:getName(), entry:getCompressedSize())
    if entry:getCompressedSize() > 0 then
      local rawContent = assert(zFile:readRawContentAll(entry))
      local crc32 = entry:getCrc32()
      if crc32 ~= 0 then
        local computedCrc32 = md:digest(rawContent)
        if crc32 ~= computedCrc32 then
          print(entry:getName(), 'Bad crc32 '..tostring(computedCrc32)..' expected '..tostring(crc32))
        else
          print(entry:getName(), 'Good crc32')
        end
      else
        print(entry:getName(), 'No crc32')
      end
    end
  end
  zFile:close()
end
