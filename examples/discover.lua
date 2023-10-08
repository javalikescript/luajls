local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local dns = require('jls.net.dns')
local UdpSocket = require('jls.net.UdpSocket')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpServer = require('jls.net.http.HttpServer')
local HttpClient = require('jls.net.http.HttpClient')
local Http1 = require('jls.net.http.Http1')
local tables = require('jls.util.tables')
local xml = require("jls.util.xml")
local StringBuffer = require('jls.lang.StringBuffer')
local Codec = require('jls.util.Codec')
local hex = Codec.getInstance('hex')

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

local function getDescription(location)
  local client = HttpClient:new(location)
  return client:fetch():next(function(response)
    logger:finer('client fetched')
    return response:text()
  end):next(function(body)
    logger:finest('received description: "%s"', body)
    local description = xml.decode(body)
    --logger:fine('received description: "%s"', tables.stringify(description, 2))
    return description
  end):finally(function()
    client:close()
  end)
end

local CONFIG_SCHEMA = {
  title = 'Service discovery utility',
  description = 'The client searches for device, description and presentation URL, the server exposes such device.',
  type = 'object',
  additionalProperties = false,
  properties = {
    protocol = {
      title = 'The discovery protocol',
      type = 'string',
      default = 'SSDP',
      enum = {'SSDP', 'mDNS'}
    },
    mode = {
      title = 'The discovery mode',
      type = 'string',
      default = 'client',
      enum = {'client', 'server'}
    },
    mdns = {
      title = 'Multicast DNS',
      type = 'object',
      additionalProperties = false,
      properties = {
        address = {
          title = 'The mDNS IP address',
          type = 'string',
          default = '224.0.0.251'
        },
        port = {
          title = 'The mDNS port',
          type = 'integer',
          default = 5353,
          minimum = 0,
          maximum = 65535,
        },
        name = {
          title = 'The question name',
          type = 'string',
          default = '_services._dns-sd._udp.local',
        },
        type = {
          title = 'The question type',
          type = 'string',
          enum = {'A', 'PTR', 'TXT', 'AAAA', 'SRV', 'ANY'},
          default = 'PTR',
        },
        unicastResponse = {
          title = 'true if the response is expected unicast',
          type = 'boolean',
          default = true,
        },
        additionals = {
          title = 'true to print the additionals responses',
          type = 'boolean',
          default = false,
        },
      }
    },
    ssdp = {
      title = 'Service Discovery Protocol',
      type = 'object',
      additionalProperties = false,
      properties = {
        address = {
          title = 'The SSDP IP address',
          type = 'string',
          default = '239.255.255.250'
        },
        port = {
          title = 'The SSDP port',
          type = 'integer',
          default = 1900,
          minimum = 0,
          maximum = 65535,
        },
        description = {
          title = 'The description location to use in the server response',
          description = 'If not provided, a web server will be started to host a test description.',
          type = 'string',
          pattern = '^https?://.+$',
        },
        ['web-server'] = {
          title = 'Web server',
          type = 'object',
          additionalProperties = false,
          properties = {
            address = {
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
          }
        }
      }
    },
    timeout = {
      title = 'The max duration, in seconds, for the client discovery',
      type = 'number',
      default = 5,
      minimum = 1,
      maximum = 300,
    },
    ['log-level'] = {
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
  aliases = {
    h = 'help',
    m = 'mode',
    p = 'protocol',
    b = 'bind-address',
    t = 'timeout',
    ll = 'log-level',
  },
  schema = CONFIG_SCHEMA
})

logger:setLevel(config['log-level'])

if config.protocol == 'SSDP' then
  local ssdpAddress = config.ssdp.address
  local ssdpPort = config.ssdp.port
  if config.mode == 'client' then
    print('Searching for presentation URL...')
    local maxTimeout = 5
    local searchTimeout = math.max(1, math.min(config.timeout, maxTimeout))
    logger:info('search timeout: %d', searchTimeout)
    local request = HttpMessage:new()
    request:setMethod('M-SEARCH')
    request:setTarget('*')
    request:setHeader(HttpMessage.CONST.HEADER_HOST, string.format('%s:%d', ssdpAddress, ssdpPort))
    request:setHeader('MAN', 'ssdp:discover')
    request:setHeader('ST', 'ssdp:all')
    request:setHeader('MX', tostring(searchTimeout))
    local locations = {}
    local presentations = {}
    local sender = UdpSocket:new()
    sender:receiveStart(function(err, data)
      if data then
        logger:fine('received data: "%s"', data)
        local response = HttpMessage:new()
        Http1.fromString(data, response)
        local location = response:getHeader('LOCATION')
        local server = response:getHeader('SERVER')
        if location and server and not locations[location] then
          logger:info('location: "%s", server: "%s"', location, server)
          locations[location] = true
          getDescription(location):next(function(description)
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
      elseif err then
        print('receive error', err)
      else
        print('receive no data')
      end
    end)
    local data = Http1.toString(request)
    local timer
    local start = system.currentTime()
    timer = event:setInterval(function()
      local duration = system.currentTime() - start
      if duration > config.timeout then
        event:clearInterval(timer)
        sender:close()
      elseif duration % 30 < maxTimeout then
        logger:info('sending...')
        sender:send(data, ssdpAddress, ssdpPort):catch(function(reason)
          print('error while sending', reason)
        end)
      end
    end, 1000)
  elseif config.mode == 'server' then
    local descriptionLocation = config.description
    if not descriptionLocation then
      local httpServer = HttpServer:new()
      local wsConfig = config.ssdp['web-server']
      httpServer:bind(wsConfig.address, wsConfig.port):next(function()
        logger:info('HTTP server bound to "%s" on port %d', wsConfig.address, wsConfig.port)
      end, function(err)
        print('Cannot bind HTTP server, '..tostring(err))
        os.exit(1)
      end)
      local host
      if wsConfig.address == '::' or wsConfig.address == '0.0.0.0' then
        host = 'localhost'
      else
        host = wsConfig.address
      end
      local baseUrl = string.format('http://%s:%d/', host, wsConfig.port)
      httpServer:createContext('/description.xml', function(exchange)
        local request = exchange:getRequest()
        logger:info('send description, headers: %s', request:getRawHeaders())
        local hostport = request:getHeader(HttpMessage.CONST.HEADER_HOST)
        if not hostport then
          HttpExchange.badRequest(exchange, 'missing host header')
          return
        end
        local response = exchange:getResponse()
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
      httpServer:createContext('/index.html', function(exchange)
        logger:info('send description, headers: %s', exchange:getRequest():getRawHeaders())
        local response = exchange:getResponse()
        response:setBody([[<!DOCTYPE html>
<html>
  <body>
    <p>It works !</p>
  </body>
</html>
]])
      end)
      descriptionLocation = baseUrl..'description.xml'
    end
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
        Http1.fromString(data, request)
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
          sender:send(Http1.toString(response), addr.ip, addr.port):finally(function()
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
elseif config.protocol == 'mDNS' then
  local mdnsAddress = config.mdns.address
  local mdnsPort = config.mdns.port
  local id = math.random(0xfff)
  local function printRRs(list, details)
    for _, rr in ipairs(list) do
      if details then
        print(string.format('name "%s" type %s class %s', rr.name, dns.TYPES_MAP[rr.type] or rr.type, dns.CLASSES_MAP[rr.class] or rr.class))
      end
      if rr.value then
        print('value', tables.stringify(rr.value, 2))
      else
        print('data', hex:encode(rr.data))
      end
    end
  end
  if config.mode == 'client' then
    local sender = UdpSocket:new()
    sender:receiveStart(function(err, data, addr)
      if data then
        if logger:isLoggable(logger.FINE) then
          logger:fine('received data: (%d) %s', #data, hex:encode(data))
        end
        local _, message = pcall(dns.decodeMessage, data)
        if logger:isLoggable(logger.FINE) then
          logger:fine('message: %s', tables.stringify(message, 2))
        end
        if message.id == id then
          print(string.format('Received %s answers from %s', #message.answers, addr and addr.ip or '?'))
          printRRs(message.answers)
          if config.mdns.additionals then
            print(string.format('Received %s additionals', #message.additionals))
            printRRs(message.additionals, true)
          end
        end
      elseif err then
        print('receive error', err)
      else
        print('receive no data')
      end
    end)
    print(string.format('Sending mDNS question name "%s" type %s with id %d', config.mdns.name, config.mdns.type, id))
    local message = {
      id = id,
      questions = {{
        name = config.mdns.name,
        type = dns.TYPES[config.mdns.type] or dns.TYPES.PTR,
        class = dns.CLASSES.IN,
        unicastResponse = config.mdns.unicastResponse,
      }}
    }
    local data = dns.encodeMessage(message)
    if logger:isLoggable(logger.FINE) then
      logger:fine('sending data: (%d) %s', #data, hex:encode(data))
    end
    sender:send(data, mdnsAddress, mdnsPort):catch(function(reason)
      print('error while sending', reason)
    end)
    event:setTimeout(function()
      sender:close()
    end, config.timeout * 1000 + 500)
  elseif config.mode == 'server' then
    local receiver = UdpSocket:new()
    receiver:bind('0.0.0.0', mdnsPort, {reuseaddr = true})
    receiver:joinGroup(mdnsAddress, '0.0.0.0')
    receiver:receiveStart(function(err, data, addr)
      if err then
        logger:warn('receive error: "%s"', err)
        receiver:close()
      elseif data then
        if logger:isLoggable(logger.FINE) then
          logger:fine('received data: (%d) %s from %s', #data, hex:encode(data), tables.stringify(addr))
        end
        local _, message = pcall(dns.decodeMessage, data)
        if logger:isLoggable(logger.INFO) then
          logger:info('message: %s', tables.stringify(message, 2))
        end
      else
        logger:warn('receive no data')
      end
    end)
    logger:info('mDNS receiver bound to "%s" on port %s', mdnsAddress, mdnsPort)
  end
end

event:loop()
logger:info('%s discovery ended', config.protocol)
