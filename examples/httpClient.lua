local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local HttpClient = require('jls.net.http.HttpClient')
local StreamHandler = require('jls.io.streams.StreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local system = require('jls.lang.system')
local tables = require('jls.util.tables')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local File = require('jls.io.File')
local Path = require('jls.io.Path')
local URL = require('jls.net.URL')
local ZipFile = require('jls.util.zip.ZipFile')

--[[
lua examples\httpClient.lua -loglevel fine -maxRedirectCount 3 -out.headers true
]]

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  emptyPath = 'url',
  schema = {
    title = 'Request an URL',
    type = 'object',
    additionalProperties = false,
    required = {'url'},
    properties = {
      help = {
        title = 'Show the help',
        type = 'boolean',
        default = false
      },
      url = {
        title = 'The URL to request',
        type = 'string',
        pattern = '^https?://.+$',
      },
      method = {
        type = 'string',
        default = 'GET',
        enum = {'GET', 'POST', 'PUT'},
      },
      headers = {
        type = 'object',
        default = {
          [HTTP_CONST.HEADER_USER_AGENT] = HTTP_CONST.DEFAULT_USER_AGENT,
        },
      },
      out = {
        type = 'object',
        additionalProperties = false,
        properties = {
          file = {
            title = 'Write the response in the file',
            type = 'string',
          },
          overwrite = {
            title = 'Overwrite existing file',
            type = 'boolean',
            default = false
          },
          headers = {
            title = 'Write the response headers',
            type = 'boolean',
            default = false
          },
          body = {
            title = 'Write the response body',
            type = 'boolean',
            default = true
          },
          unzipTo = {
            title = 'Directory to unzip the received ZIP file',
            type = 'string',
          },
        },
      },
      maxRedirectCount = {
        type = 'integer',
        default = 0,
        minimum = 0,
        maximum = 3
      },
      loglevel = {
        title = 'The log level',
        type = 'string',
        default = 'WARN',
        enum = {'ERROR', 'WARN', 'INFO', 'CONFIG', 'FINE', 'FINER', 'FINEST', 'DEBUG', 'ALL'},
      },
    }
  }
})

logger:setLevel(options.loglevel)

local responseStreamHandler = StreamHandler.std
local outFile
if options.out.file and (options.out.headers or options.out.body) then
  outFile = File:new(options.out.file)
  if outFile:isDirectory() and options.url then
    local u = URL:new(options.url)
    local p = Path:new(u:getPath())
    outFile = File:new(outFile, p:getName())
  end
  --local tmpFile = File:new(outFile:getPathName()..'.tmp')
  responseStreamHandler = FileStreamHandler:new(outFile, options.out.overwrite, nil, true)
end

local unzipTo
if options.out.unzipTo then
  local unzipToDir = File:new(options.out.unzipTo)
  if unzipToDir:isDirectory() then
    unzipTo = unzipToDir
    if not outFile then
      outFile = File:new(unzipTo, 'tmp.zip')
      responseStreamHandler = FileStreamHandler:new(outFile, true, nil, true)
    end
  else
    print('Invalid directory to unzip to, "'..unzipToDir:getPath()..'"')
    os.exit(1)
  end
end

local client = HttpClient:new(options)

logger:finer('connecting client')
client:connect():next(function()
  logger:finer('client connected')
  return client:sendRequest()
end):next(function()
  return client:receiveResponseHeaders()
end):next(function(remainingBuffer)
  local response = client:getResponse()
  if options.out.headers then
    local lines = {}
    table.insert(lines, response:getLine())
    for name, value in pairs(response:getHeadersTable()) do
      table.insert(lines, '\t'..name..': '..tostring(value))
    end
    table.insert(lines, '')
    responseStreamHandler:onData(table.concat(lines, '\r\n'))
  end
  -- and response:getStatusCode() == 200
  if options.out.body then
    response:setBodyStreamHandler(responseStreamHandler)
  end
  return client:receiveResponseBody(remainingBuffer)
end):next(function()
  logger:finer('closing client')
  client:close()
  if outFile and outFile:isFile() and unzipTo then
    ZipFile.unzipTo(outFile, unzipTo)
    outFile:delete()
  end
end, function(err)
  print('error: ', err)
  client:close()
end)

event:loop()
logger:finer('client closed')
