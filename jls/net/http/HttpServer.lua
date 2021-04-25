--- An HTTP server implementation that handles HTTP requests.
-- @module jls.net.http.HttpServer
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local TcpServer = require('jls.net.TcpServer')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpRequest = require('jls.net.http.HttpRequest')
local HttpResponse = require('jls.net.http.HttpResponse')
local HttpExchange = require('jls.net.http.HttpExchange')
local HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler')
local readBody = require('jls.net.http.readBody')

--[[-- An HTTP server.
The HttpServer inherits from @{HttpContextHolder}.
@usage
local event = require('jls.lang.event')
local HttpServer = require('jls.net.http.HttpServer')
local hostname, port = '::', 3001
local httpServer = HttpServer:new()
httpServer:bind(hostname, port):next(function()
  print('Server bound to "'..hostname..'" on port '..tostring(port))
end, function(err) -- could failed if address is in use or hostname cannot be resolved
  print('Cannot bind HTTP server, '..tostring(err))
end)
httpServer:createContext('/', function(httpExchange)
  local response = httpExchange:getResponse()
  response:setBody('It works !')
end)
event:loop()
@type HttpServer
]]
return require('jls.lang.class').create(require('jls.net.http.HttpContextHolder'), function(httpServer, super)

  --- Creates a new HTTP server.
  -- @function HttpServer:new
  -- @return a new HTTP server
  function httpServer:initialize(tcp)
    super.initialize(self)
    self.filters = {}
    self.tcpServer = tcp or TcpServer:new()
    self.tcpServer.onAccept = function(_, client)
      self:onAccept(client)
    end
  end

  --[[
    The presence of a message body in a request is signaled by a
  Content-Length or Transfer-Encoding header field.  Request message
  framing is independent of method semantics, even if the method does
  not define any use for a message body
  ]]
  function httpServer:onAccept(client, buffer)
    logger:finer('httpServer:onAccept()')
    local exchange = HttpExchange:new(self, client)
    local keepAlive = false
    local remainingBuffer = nil
    local requestHeadersPromise = nil
    local hsh = HeaderStreamHandler:new(exchange:getRequest())
    -- TODO limit headers
    hsh:read(client, buffer):next(function(remainingHeaderBuffer)
      logger:finer('httpServer:onAccept() header read')
      requestHeadersPromise = exchange:processRequestHeaders()
      -- TODO limit request body
      return readBody(exchange:getRequest(), client, remainingHeaderBuffer)
    end):next(function(remainingBodyBuffer)
      logger:fine('httpServer:onAccept() body done')
      exchange:notifyRequestBody()
      remainingBuffer = remainingBodyBuffer
      if requestHeadersPromise then
        return requestHeadersPromise
      end
    end):next(function()
      logger:fine('httpServer:onAccept() request processed')
      keepAlive = exchange:applyKeepAlive()
      local status, res = pcall(function ()
        return exchange:processResponse()
      end)
      if not status then
        logger:warn('HttpExchange:processResponse() in error due to "'..tostring(res)..'"')
        return Promise.reject(res)
      end
      return res
    end):next(function()
      logger:fine('httpServer:onAccept() response processed')
      if keepAlive and not self.tcpServer:isClosed() then
        local c = exchange:removeClient()
        if c then
          logger:fine('httpServer:onAccept() keeping client alive')
          exchange:close()
          return self:onAccept(c, remainingBuffer) -- tail call
        end
      end
      exchange:close()
    end, function(err)
      if logger:isLoggable(logger.FINE) then
        logger:fine('httpServer:onAccept() read header error "'..tostring(err)..'"')
      end
      exchange:close()
    end)
  end

  --- Binds this server to the specified address and port number.
  -- @tparam[opt] string node the address, the address could be an IP address or a host name.
  -- @tparam[opt] number port the port number, 0 to let the system automatically choose a port, default is 80.
  -- @tparam[opt] number backlog the accept queue size, default is 32.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is bound.
  -- @usage
  --local s = HttpServer:new()
  --s:bind('127.0.0.1', 80)
  function httpServer:bind(node, port, backlog, callback)
    return self.tcpServer:bind(node or '::', port or 80, backlog, callback)
  end

  function httpServer:getAddress()
    return self.tcpServer:getLocalName()
  end
  --- Closes this server.
  -- @tparam[opt] function callback an optional callback function to use in place of promise.
  -- @treturn jls.lang.Promise a promise that resolves once the server is closed.
  function httpServer:close(callback)
    return self.tcpServer:close(callback)
  end
end, function(HttpServer)

  local getSecure = require('jls.lang.loader').singleRequirer('jls.net.secure')

  function HttpServer.createSecure(secureContext)
    local secure = getSecure()
    if secure then
      local tcp = secure.TcpServer:new()
      if type(secureContext) == 'table' then
        tcp:setSecureContext(secure.Context:new(secureContext))
      end
      return HttpServer:new(tcp), tcp
    end
  end

end)
