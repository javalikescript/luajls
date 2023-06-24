local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local HttpClient = require('jls.net.http.HttpClient')
local StreamHandler = require('jls.io.StreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local system = require('jls.lang.system')
local tables = require('jls.util.tables')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local File = require('jls.io.File')
local Path = require('jls.io.Path')
local Url = require('jls.net.Url')
local ZipFile = require('jls.util.zip.ZipFile')

--[[
lua examples\httpClient.lua -loglevel fine -maxRedirectCount 3 -out.headers true -out.body false
]]

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  emptyPath = 'url',
  aliases = {
    h = 'help',
    u = 'url',
    m = 'method',
    b = 'body',
    r = 'maxRedirectCount',
    ll = 'loglevel',
  },
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
      body = {
        title = 'The HTTP body to send',
        type = 'string',
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
          pretty = {
            title = 'Pretty print response body',
            type = 'boolean',
            default = false
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
        default = 'warn',
        enum = {'error', 'warn', 'info', 'config', 'fine', 'finer', 'finest', 'debug', 'all'},
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
    local u = Url:new(options.url)
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

Promise.async(function(await)

  logger:finer('connecting client')
  await(client:connect())
  logger:finer('client connected')

  await(client:sendRequest())

  local remainingBuffer = await(client:receiveResponseHeaders())

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
  if options.out.pretty then
    local contentType = response:getHeader('content-type')
    if contentType then
      contentType = string.lower(contentType)
      if contentType == 'application/json' then
        local json = require('jls.util.json')
        local rsh = responseStreamHandler
        responseStreamHandler = StreamHandler.buffer(StreamHandler:new(function(err, data)
          if err then
            rsh:onError(err)
          end
          if data then
            local status, result = pcall(json.decode, data)
            if status then
              data = json.stringify(result, '  ')
            end
          end
          rsh:onData(data)
        end))
      end
    end
  end
  -- and response:getStatusCode() == 200
  if options.out.body then
    response:setBodyStreamHandler(responseStreamHandler)
  end

  await(client:receiveResponseBody(remainingBuffer))

  logger:finer('closing client')
  await(client:close())
  logger:finer('client closed')

  if outFile and outFile:isFile() and unzipTo then
    ZipFile.unzipTo(outFile, unzipTo)
    outFile:delete()
  end

end):catch(function(reason)
  print('error: ', reason)
  client:close()
end)

event:loop()
