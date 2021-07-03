local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local HttpClient = require('jls.net.http.HttpClient')
local StreamHandler = require('jls.io.streams.StreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local system = require('jls.lang.system')
local tables = require('jls.util.tables')

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
      show = {
        type = 'object',
        additionalProperties = false,
        properties = {
          headers = {
            type = 'boolean',
            default = false
          },
          body = {
            type = 'boolean',
            default = true
          },
        },
      },
      maxRedirectCount = {
        type = 'integer',
        default = 0,
        minimum = 0,
        maximum = 3
      },
    }
  }
})

local client = HttpClient:new(options)

logger:finer('connecting client')
client:connect():next(function()
  logger:finer('client connected')
  return client:sendRequest()
end):next(function()
  return client:receiveResponseHeaders()
end):next(function(remainingBuffer)
  local response = client:getResponse()
  if options.show.headers then
    print(response:getLine())
    print('Response headers:')
    for name, value in pairs(response:getHeadersTable()) do
      print('', name, value)
    end
  end
  if options.show.body then
    response:setBodyStreamHandler(StreamHandler.std)
  end
  return client:receiveResponseBody(remainingBuffer)
end):next(function()
  logger:finer('closing client')
  client:close()
end, function(err)
  print('error: ', err)
  client:close()
end)

event:loop()
logger:finer('client closed')
