local event = require('jls.lang.event')
local system = require('jls.lang.system')
local tables = require('jls.util.tables')
local WebSocket = require('jls.net.http.WebSocket')

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  emptyPath = 'url',
  logPath = 'log-level',
  aliases = {
    h = 'help',
    ll = 'log-level',
  },
  schema = {
    title = 'Open a WebSocket',
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
        title = 'The WebSocket URL',
        type = 'string',
        pattern = '^wss?://.+$',
      },
      read = {
        title = 'Read and print incoming text messages',
        type = 'boolean',
        default = true
      },
      message = {
        title = 'The message to send',
        type = 'string'
      },
    }
  }
})

local webSocket = WebSocket:new(options.url)
webSocket:open():next(function()
  print('opened')
  function webSocket:onTextMessage(payload)
    print(payload)
  end
  if options.message then
    print('message sent')
    webSocket:sendTextMessage(options.message)
  end
  if options.read then
    webSocket:readStart()
  else
    webSocket:close()
  end
end, function(reason)
  print('cannot open', reason)
end)

event:loop()
