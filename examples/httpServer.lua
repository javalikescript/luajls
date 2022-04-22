local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local File = require('jls.io.File')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpHandler = require('jls.net.http.HttpHandler')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local ZipFileHttpHandler = require('jls.net.http.handler.ZipFileHttpHandler')
local ProxyHttpHandler = require('jls.net.http.handler.ProxyHttpHandler')
local WebDavHttpHandler = require('jls.net.http.handler.WebDavHttpHandler')
local Url = require('jls.net.Url')
local tables = require('jls.util.tables')
local base64 = require('jls.util.base64')
local Scheduler = require('jls.util.Scheduler')
local EventPublisher = require("jls.util.EventPublisher")

local CONFIG_SCHEMA = {
  title = 'HTTP server',
  type = 'object',
  additionalProperties = false,
  properties = {
    config = {
      title = 'The configuration file',
      type = 'string',
      default = 'httpServer.json'
    },
    server = {
      type = 'object',
      additionalProperties = false,
      properties = {
        address = {
          title = 'The binding address',
          type = 'string',
          default = '::'
        },
        port = {
          type = 'integer',
          default = 8080,
          minimum = 0,
          maximum = 65535,
        },
        secure = {
          type = 'object',
          additionalProperties = false,
          properties = {
            enabled = {
              type = 'boolean',
              default = false
            },
          },
        },
      },
      credentials = {
        title = 'The credentials as name/password pairs for basic authentication',
        type = 'array',
        items = {
          type = 'object',
          properties = {
            name = {
              title = 'The user name',
              type = 'string'
            },
            password = {
              title = 'The user password',
              type = 'string'
            }
          }
        }
      },
    },
    endpoints = {
      type = 'array',
      items = {
        type = 'object',
        required = {'path', 'target'},
        additionalProperties = false,
        properties = {
          path = {
            title = 'The path where the endpoint is available',
            type = 'string',
          },
          target = {
            title = 'The endpoint URI target',
            description = 'The URI with a supported scheme: file, zip, webdav, http, https, data, lua',
            type = 'string',
          },
          permissions = {
            title = 'The endpoint permissions',
            type = 'string',
          }
        }
      },
    },
    scheduler = {
      type = 'object',
      additionalProperties = false,
      properties = {
        enabled = {
          type = 'boolean',
          default = true,
        },
        heartbeat = {
          type = 'number',
          default = 15,
          multipleOf = 0.1,
          minimum = 0.5,
          maximum = 3600,
        },
        refresh = {
          title = 'The refresh scheduler recurrence',
          type = 'string',
          default = '*/15 * * * *',
        },
      },
    },
    loglevel = {
      title = 'The log level',
      type = 'string',
      default = 'warn',
      enum = {'error', 'warn', 'info', 'config', 'fine', 'finer', 'finest', 'debug', 'all'}
    }
  }
}

local config = tables.createArgumentTable(system.getArguments(), {
  configPath = 'config',
  emptyPath = 'dir',
  helpPath = 'help',
  schema = CONFIG_SCHEMA
})

logger:setLevel(config.loglevel)

local eventPublisher = EventPublisher:new()

local httpServer = HttpServer:new()
httpServer:bind(config.server.address, config.server.port):next(function()
  logger:info('HTTP server bound to "'..config.server.address..'" on port '..tostring(config.server.port))
end, function(err) -- could failed if address is in use or hostname cannot be resolved
  print('Cannot bind HTTP server, '..tostring(err))
  os.exit(1)
end)

if type(config.server.credentials) == 'table' and next(config.server.credentials) then
  local BasicAuthenticationHttpFilter = require('jls.net.http.filter.BasicAuthenticationHttpFilter')
  local namePasswordMap = {}
  for _, credential in ipairs(config.server.credentials) do
    namePasswordMap[credential.name] = credential.password
  end
  httpServer:addFilter(BasicAuthenticationHttpFilter:new(namePasswordMap, 'HTTP Server'))
end

eventPublisher:subscribeEvent('terminate', function()
  logger:info('Closing HTTP server')
  httpServer:close()
end)

if config.scheduler and config.scheduler.enabled then
  local scheduler = Scheduler:new()
  if config.scheduler.refresh then
    scheduler:schedule(config.scheduler.refresh, function(t)
      logger:info('Refreshing')
      eventPublisher:publishEvent('refresh')
    end)
  end
  local schedulerIntervalId = event:setInterval(function()
    scheduler:runTo()
  end, math.floor(config.scheduler.heartbeat * 1000))
  eventPublisher:subscribeEvent('terminate', function()
    logger:info('Closing event publisher')
    event:clearInterval(schedulerIntervalId)
  end)
end

for _, endpoint in ipairs(config.endpoints) do
  local scheme, specificPart = string.match(endpoint.target, '^([%w][%w%+%.%-]*):(.*)$')
  --local targetUri = Url.fromString(endpoint.target)
  if scheme then
    if scheme == 'file' or scheme == 'zip' or scheme == 'webdav' then
      local targetFile = File:new(specificPart)
      if targetFile:exists() then
        local handler, path
        if scheme == 'zip' and targetFile:isFile() then
          handler = ZipFileHttpHandler:new(targetFile)
        elseif scheme == 'webdav' and targetFile:isDirectory() then
          handler = WebDavHttpHandler:new(targetFile, endpoint.permissions)
        elseif scheme == 'file' and targetFile:isDirectory() then
          handler = FileHttpHandler:new(targetFile, endpoint.permissions)
        elseif scheme == 'file' and targetFile:isFile() then
          handler = HttpHandler:new(function(_, exchange)
            HttpExchange.ok(exchange, targetFile:readAll(), FileHttpHandler.guessContentType(targetFile:getName()))
          end)
          path = endpoint.path
        end
        if not path then
          path = endpoint.path..'(.*)'
        end
        if handler then
          logger:fine('create context "'..tostring(path)..'" using '..tostring(class.getName(handler:getClass())))
          httpServer:createContext(path, handler)
        else
          logger:warn('invalid endpoint target "'..tostring(endpoint.target)..'"')
        end
      else
        logger:warn('target endpoint not found "'..targetFile:getPath()..'"')
      end
    elseif scheme == 'http' or scheme == 'https' then
      httpServer:createContext(endpoint.path..'(.*)', ProxyHttpHandler:new():configureReverse(endpoint.target))
    elseif scheme == 'data' then
      -- data:[<media type>[;attribute=value]][;base64],<data>
      local mediaType, body = string.match(specificPart, '^([^,]*),(.*)$')
      if body then
        if mediaType and string.match(mediaType, ';base64$') then
          mediaType = string.gsub(mediaType, ';base64$', '')
          body = base64.decode(body)
        else
          body = Url.decodePercent(body)
        end
        httpServer:createContext(endpoint.path, HttpHandler:new(function(_, exchange)
          HttpExchange.ok(exchange, body, mediaType or 'text/plain;charset=US-ASCII')
        end))
      else
        logger:warn('unsupported data endpoint "'..tostring(specificPart)..'"')
      end
    elseif scheme == 'lua' then
      local handler, err = load('local exchange, event = ...; '..specificPart)
      if handler then
        httpServer:createContext(endpoint.path, HttpHandler:new(function(_, exchange)
          return handler(exchange, eventPublisher)
        end))
      else
        logger:warn('Error "'..tostring(err)..'" while loading: '..tostring(specificPart))
      end
    else
      logger:warn('unsupported endpoint scheme "'..tostring(scheme)..'"')
    end
  else
    logger:warn('unsupported endpoint target "'..tostring(endpoint.target)..'"')
  end
end

event:loop()
logger:info('HTTP server closed')
