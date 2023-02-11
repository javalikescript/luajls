local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local UdpSocket = require('jls.net.UdpSocket')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpServer = require('jls.net.http.HttpServer')
local HttpClient = require('jls.net.http.HttpClient')
local tables = require('jls.util.tables')
local xml = require("jls.util.xml")
local StringBuffer = require('jls.lang.StringBuffer')

local CONFIG_SCHEMA = {
  title = 'Simple Service Discovery Protocol (SSDP) Client and Server',
  description = 'The client searches for device, description and presentation URL, the server exposes such device.',
  type = 'object',
  additionalProperties = false,
  properties = {
    ['bind-address'] = {
      title = 'The binding address, use :: to bind on any',
      type = 'string',
      default = '127.0.0.1'
    },
    port = {
      title = 'The web server port',
      type = 'integer',
      default = 8000,
      minimum = 0,
      maximum = 65535,
    },
    ['ssdp-address'] = {
      title = 'The SSDP IP address',
      type = 'string',
      default = '239.255.255.250'
    },
    ['ssdp-port'] = {
      title = 'The SSDP port',
      type = 'integer',
      default = 1900,
      minimum = 0,
      maximum = 65535,
    },
    timeout = {
      type = 'number',
      default = 5,
      minimum = 1,
      maximum = 30,
    },
    mode = {
      title = 'The SSDP mode',
      type = 'string',
      default = 'client',
      enum = {'client', 'server'}
    },
    ['log-level'] = {
      title = 'The log level',
      type = 'string',
      default = 'warn',
      enum = {'error', 'warn', 'info', 'config', 'fine', 'finer', 'finest', 'debug', 'all'}
    }
  }
}

local function getNodeByName(node, name)
  for _, n in ipairs(node) do
    if n.name == name then
      return n
    end
  end
end

local function getNodeByNames(node, ...)
  local names = {...}
  for _, name in ipairs(names) do
    if not node then
      break
    end
    node = getNodeByName(node, name)
  end
  return node
end

local function getNodeText(node)
  if node then
    local buffer = StringBuffer:new()
    for _, n in ipairs(node) do
      if type(n) == 'string' then
        buffer:append(n)
      end
    end
    return buffer:toString()
  end
end

local config = tables.createArgumentTable(system.getArguments(), {
  configPath = 'config',
  emptyPath = 'dir',
  helpPath = 'help',
  aliases = {
    h = 'help',
    c = 'client',
    b = 'bind-address',
    m = 'mode',
    ll = 'log-level',
  },
  schema = CONFIG_SCHEMA
})

logger:setLevel(config['log-level'])

local ssdpAddress = config['ssdp-address']
local ssdpPort = config['ssdp-port']

if config.mode == 'client' then
  print('Searching for presentation URL...')
  local request = HttpMessage:new()
  request:setMethod('M-SEARCH')
  request:setTarget('*')
  request:setHeader(HttpMessage.CONST.HEADER_HOST, string.format('%s:%d', ssdpAddress, ssdpPort))
  request:setHeader('MAN', 'ssdp:discover')
  request:setHeader('ST', 'ssdp:all')
  request:setHeader('MX', tostring(math.max(1, math.min(config.timeout, 5))))
  local locations = {}
  local presentations = {}
  local sender = UdpSocket:new()
  sender:receiveStart(function(err, data)
    if data then
      logger:fine('received data: "%s"', data)
      local response = HttpMessage:new()
      HttpMessage.fromString(data, response)
      local location = response:getHeader('LOCATION')
      local server = response:getHeader('SERVER')
      if location and server and not locations[location] then
        logger:info('location: "%s", server: "%s"', location, server)
        locations[location] = true
        local client = HttpClient:new({
          url = location,
          method = 'GET',
          --headers = {}
        })
        client:connect():next(function()
          logger:finer('client connected')
          return client:sendReceive()
        end):next(function(response)
          logger:finest('received description: "%s"', response:getBody())
          local description = xml.decode(response:getBody())
          --logger:fine('received description: "%s"', tables.stringify(description, 2))
          local urlBase = getNodeText(getNodeByNames(description, 'URLBase'))
          local friendlyName = getNodeText(getNodeByNames(description, 'device', 'friendlyName'))
          local presentationURL = getNodeText(getNodeByNames(description, 'device', 'presentationURL'))
          if presentationURL then
            if urlBase then
              presentationURL = urlBase..presentationURL
            end
            if not presentations[presentationURL] then
              presentations[presentationURL] = true
              print('Presentation name:', friendlyName, 'URL:', presentationURL)
            end
          end
        end)
      end
    end
  end)
  sender:send(HttpMessage.toString(request), ssdpAddress, ssdpPort):finally(function()
    event:setTimeout(function()
      sender:close()
    end, config.timeout * 1000 + 500)
  end)
elseif config.mode == 'server' then
  local httpServer = HttpServer:new()
  local bindAddress = config['bind-address']
  httpServer:bind(bindAddress, config.port):next(function()
    logger:info('HTTP server bound to "'..bindAddress..'" on port '..tostring(config.port))
  end, function(err)
    print('Cannot bind HTTP server, '..tostring(err))
    os.exit(1)
  end)
  local baseUrl = string.format('http://%s:%d/', bindAddress, config.port)
  httpServer:createContext('/description.xml', function(httpExchange)
    logger:info('send description, headers: %s', httpExchange:getRequest():getRawHeaders())
    local response = httpExchange:getResponse()
    response:setBody([[<?xml version="1.0" encoding="UTF-8" ?>
    <root xmlns="urn:schemas-upnp-org:device-1-0">
      <specVersion>
        <major>1</major>
        <minor>0</minor>
      </specVersion>
      <URLBase>]]..baseUrl..[[</URLBase>
      <device>
        <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
        <friendlyName>Test</friendlyName>
        <manufacturer>luajls</manufacturer>
        <manufacturerURL>https://github.com/javalikescript/luajls</manufacturerURL>
        <modelDescription>Test</modelDescription>
        <modelName>Test</modelName>
        <modelNumber>Test</modelNumber>
        <modelURL>https://github.com/javalikescript/luajls</modelURL>
        <serialNumber>Test</serialNumber>
        <UDN>uuid:6bcec79a-8eae-11ed-a1eb-0242ac120002</UDN>
        <presentationURL>index.html</presentationURL>
      </device>
    </root>
    ]])
  end)
  httpServer:createContext('/index.html', function(httpExchange)
    logger:info('send description, headers: %s', httpExchange:getRequest():getRawHeaders())
    local response = httpExchange:getResponse()
    response:setBody([[<!DOCTYPE html>
    <html>
      <body>
        <p>It works !</p>
      </body>
    </html>
    ]])
    end)
  local descriptionLocation = baseUrl..'description.xml'
  logger:info('description available at %s', descriptionLocation)

  local receiver = UdpSocket:new()
  receiver:bind('0.0.0.0', ssdpPort, {reuseaddr = true})
  receiver:joinGroup(ssdpAddress, '0.0.0.0')
  receiver:receiveStart(function(err, data, addr)
    if err then
      logger:warn('receive error: "%s"', err)
      receiver:close()
    elseif data then
      logger:fine('received data: "%s", addr: %s', data, tables.stringify(addr))
      local request = HttpMessage:new()
      HttpMessage.fromString(data, request)
      logger:fine('method: "%s"', request:getMethod())
      if addr and request:getMethod() == 'M-SEARCH' then
        local response = HttpMessage:new()
        response:setStatusCode(HttpMessage.CONST.HTTP_OK, 'OK')
        response:setHeader('LOCATION', descriptionLocation)
        response:setHeader('SERVER', 'Linux/3.2.26, UPnP/1.0, luajls/0.1')
        response:setHeader('ST', 'ssdp:all')
        response:setHeader('USN', 'uuid:8df292b6-8eae-11ed-a1eb-0242ac120002')
        local sender = UdpSocket:new()
        logger:info('send response for %s to %s:%s', request:getMethod(), addr.ip, addr.port)
        sender:send(HttpMessage.toString(response), addr.ip, addr.port):finally(function()
          sender:close()
        end)
      else
        logger:info('ignoring request %s from %s:%s', request:getMethod(), addr.ip, addr.port)
      end
    else
      logger:warn('receive no data')
      receiver:close()
    end
  end)
  logger:info('SSDP receiver bound to "%s" on port %s', ssdpAddress, ssdpPort)
end

event:loop()
logger:info('SSDP ended')
