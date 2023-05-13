--- Wraps the HTTP request and the associated response.
-- @module jls.net.http.HttpExchange
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Exception = require('jls.lang.Exception')
local Promise = require('jls.lang.Promise')
local HttpHeaders = require('jls.net.http.HttpHeaders')
local HttpMessage = require('jls.net.http.HttpMessage')
local List = require('jls.util.List')
local strings = require('jls.util.strings')
local HTTP_CONST = HttpMessage.CONST

--- The HttpExchange class wraps the HTTP request and response.
-- This class inherits from @{HttpHeaders}.
-- @type HttpExchange
return require('jls.lang.class').create('jls.net.http.Attributes', function(httpExchange, super)

  function httpExchange:initialize(client)
    super.initialize(self)
    self.client = client
    self.request = HttpMessage:new()
    self.response = HttpMessage:new()
    self.response:setStatusCode(HttpMessage.CONST.HTTP_OK, 'OK')
  end

  --- Returns the HTTP context.
  -- Only available during the request handling
  -- @treturn HttpContext the HTTP context.
  function httpExchange:getContext()
    return self.context
  end

  function httpExchange:setContext(context)
    self.context = context
  end

  --- Returns the HTTP session.
  -- @treturn HttpSession the HTTP session.
  function httpExchange:getSession()
    return self.session
  end

  function httpExchange:setSession(session)
    self.session = session
  end

  --- Returns the HTTP request.
  -- @treturn HttpMessage the HTTP request.
  function httpExchange:getRequest()
    return self.request
  end

  --- Returns the HTTP response.
  -- @treturn HttpMessage the HTTP response.
  function httpExchange:getResponse()
    return self.response
  end

  --- Returns the HTTP request method.
  -- @treturn string the HTTP method.
  function httpExchange:getRequestMethod()
    return self.request:getMethod()
  end

  --- Returns the HTTP request headers.
  -- @treturn HttpHeaders the HTTP request.
  function httpExchange:getRequestHeaders()
    --return self.request
    return HttpHeaders:new(self.request:getHeadersTable())
  end

  --- Returns the captured values of the request target path using the context path.
  -- @treturn string the first captured value, nil if there is no captured value.
  function httpExchange:getRequestArguments()
    return self.context:getArguments(self:getRequest():getTargetPath())
  end

  --- Returns the request path as replaced by the context.
  -- @treturn string the request path.
  function httpExchange:getRequestPath()
    return self.context:replacePath(self:getRequest():getTargetPath())
  end

  --- Returns a promise that resolves once the request body is available.
  -- @tparam[opt] boolean buffer true to indicate that the request body must be bufferred.
  -- @treturn jls.lang.Promise a promise that resolves once the request body is available.
  function httpExchange:onRequestBody(buffer)
    if buffer then
      self.request:bufferBody()
    end
    if not self.requestBodyPromise then
      self.requestBodyPromise, self.requestBodyCallback = Promise.createWithCallback()
    end
    return self.requestBodyPromise
  end

  --- Returns a promise that resolves once the exchange is closed.
  -- @treturn jls.lang.Promise a promise that resolves once the exchange is closed.
  function httpExchange:onClose()
    if not self.closePromise then
      self.closePromise, self.closeCallback = Promise.createWithCallback()
    end
    return self.closePromise
  end

  function httpExchange:notifyRequestBody(reason)
    if self.requestBodyCallback then
      self.requestBodyCallback(reason, self)
      self.requestBodyCallback = nil
    end
  end

  --- Sets the status code for the response.
  -- @tparam number status the status code.
  -- @tparam[opt] string reason the reason phrase.
  -- @tparam[opt] string body the response body.
  function httpExchange:setResponseStatusCode(status, reason, body)
    self.response:setStatusCode(status, reason)
    if body then
      self.response:setBody(body)
    end
  end

  function httpExchange:applyKeepAlive()
    local connection = HttpMessage.CONST.HEADER_CONNECTION
    local requestConnection = self.request:getHeader(connection)
    local responseConnection = self.response:getHeader(connection)
    if strings.equalsIgnoreCase(requestConnection, HttpMessage.CONST.CONNECTION_KEEP_ALIVE) then
      if not responseConnection then
        self.response:setHeader(connection, requestConnection)
        return true
      elseif strings.equalsIgnoreCase(responseConnection, requestConnection) then
        return true
      end
      self.response:setHeader(connection, HttpMessage.CONST.CONNECTION_CLOSE)
    elseif not responseConnection then
      self.response:setHeader(connection, HttpMessage.CONST.CONNECTION_CLOSE)
    end
    return false
  end

  function httpExchange:prepareResponseHeaders()
    self.response:applyBodyLength()
  end

  function httpExchange:resetResponseToError(reason)
    local r = reason and tostring(reason) or 'Unkown error'
    local response = self.response
    response:close()
    response = HttpMessage:new()
    response:setStatusCode(HttpMessage.CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
    self.response = response
    self:notifyRequestBody(r)
  end

  function httpExchange:handleRequest(context)
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpExchange:handleRequest() "'..self.request:getTarget()..'"')
    end
    self.context = context
    local status, result = Exception.pcall(context.handleExchange, context, self)
    if status then
      -- always return a promise
      if Promise:isInstance(result) then
        return result:catch(function(reason)
          if logger:isLoggable(logger.WARN) then
            logger:warn('HttpExchange error while handling promise "%s", due to %s', self:getRequest():getTarget(), reason:toString(true))
          end
          self:resetResponseToError(reason)
        end)
      end
      return Promise.resolve()
    end
    if logger:isLoggable(logger.WARN) then
      logger:warn('HttpExchange error while handling "%s", due to %s', self:getRequest():getTarget(), result:toString(true))
    end
    self:resetResponseToError(result)
    return Promise.resolve()
  end

  function httpExchange:clientAsString()
    if self.client then
      local ip, port = self.client:getRemoteName()
      if ip then
        return ip..':'..tostring(port)
      end
    end
    return ''
  end

  function httpExchange:removeClient()
    local client = self.client
    self.client = nil
    return client
  end

  function httpExchange:close()
    logger:finest('httpExchange:close()')
    self.request:close()
    self.response:close()
    local client = self:removeClient()
    if client then
      --client:readStop()
      client:close()
    end
    if self.closeCallback then
      self.closeCallback()
      self.closeCallback = nil
    end
  end

end, function(HttpExchange)

  HttpExchange.CONTENT_TYPES = {
    bin = 'application/octet-stream',
    css = 'text/css',
    gif = 'image/gif',
    ico = 'image/vnd.microsoft.icon',
    --ico = 'image/x-icon',
    jpeg = 'image/jpeg',
    jpg = 'image/jpeg',
    js = 'application/javascript',
    json = 'application/json',
    htm = 'text/html',
    html = 'text/html',
    mp4 = 'video/mp4',
    svg = 'image/svg+xml',
    txt = 'text/plain',
    woff = 'font/woff',
    xml = 'text/xml',
    pdf = 'application/pdf',
  }

  HttpExchange.REASONS = {
    [HTTP_CONST.HTTP_OK] = 'OK',
    [HTTP_CONST.HTTP_BAD_REQUEST] = 'Bad Request',
    [HTTP_CONST.HTTP_FORBIDDEN] = 'Forbidden',
    [HTTP_CONST.HTTP_FOUND] = 'Found',
    [HTTP_CONST.HTTP_NOT_FOUND] = 'Not Found',
    [HTTP_CONST.HTTP_METHOD_NOT_ALLOWED] = 'Method Not Allowed',
    [HTTP_CONST.HTTP_PAYLOAD_TOO_LARGE] = 'Payload Too Large',
    [HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR] = 'Internal Server Error',
  }

  HttpExchange.CONTENTS = {
    [HTTP_CONST.HTTP_BAD_REQUEST] = '<p>Sorry something seems to be wrong in your request.</p>',
    [HTTP_CONST.HTTP_FORBIDDEN] = '<p>Sorry you are not authorized.</p>',
    [HTTP_CONST.HTTP_FOUND] = '<p>You are redirected.</p>',
    [HTTP_CONST.HTTP_NOT_FOUND] = '<p>Sorry the resource is not available.</p>',
    [HTTP_CONST.HTTP_METHOD_NOT_ALLOWED] = '<p>Sorry the method is not allowed.</p>',
    [HTTP_CONST.HTTP_PAYLOAD_TOO_LARGE] = '<p>Sorry the request is too large.</p>',
    [HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR] = '<p>Sorry something went wrong on our side.</p>',
  }

  local function updateResponseFor(exchange, status, reason, bodyContent)
    exchange:setResponseStatusCode(status, reason or HttpExchange.REASONS[status], bodyContent or HttpExchange.CONTENTS[status] or '')
  end

  --- Updates the response with the OK status code, 200.
  -- @tparam HttpExchange exchange ongoing HTTP exchange
  -- @tparam[opt] string body the response content.
  -- @tparam[opt] string contentType the response content type.
  function HttpExchange.ok(exchange, body, contentType)
    updateResponseFor(exchange, HTTP_CONST.HTTP_OK, nil, body)
    if type(contentType) == 'string' then
      exchange:getResponse():setContentType(contentType)
    end
  end

  --- Updates the response with the status code Bad Request, 400.
  -- @tparam HttpExchange exchange ongoing HTTP exchange
  -- @tparam[opt] string reason the response reason phrase.
  function HttpExchange.badRequest(exchange, reason)
    updateResponseFor(exchange, HTTP_CONST.HTTP_BAD_REQUEST, reason)
  end

  --- Updates the response with the status code Forbidden, 403.
  -- @tparam HttpExchange exchange ongoing HTTP exchange
  -- @tparam[opt] string reason the response reason phrase.
  function HttpExchange.forbidden(exchange, reason)
    updateResponseFor(exchange, HTTP_CONST.HTTP_FORBIDDEN, reason)
  end

  --- Updates the response with the status code Not Found, 404.
  -- @tparam HttpExchange exchange ongoing HTTP exchange
  function HttpExchange.notFound(exchange)
    updateResponseFor(exchange, HTTP_CONST.HTTP_NOT_FOUND, nil, '<p>The resource "'..exchange:getRequest():getTarget()..'" is not available.</p>')
  end

  --- Updates the response with the status code Method Not Allowed, 405.
  -- @tparam HttpExchange exchange ongoing HTTP exchange
  function HttpExchange.methodNotAllowed(exchange)
    updateResponseFor(exchange, HTTP_CONST.HTTP_METHOD_NOT_ALLOWED)
  end

  --- Updates the response with the status code Internal Server Error, 500.
  -- @tparam HttpExchange exchange ongoing HTTP exchange
  -- @tparam[opt] string reason the response reason phrase.
  function HttpExchange.internalServerError(exchange, reason)
    exchange:getResponse():setVersion(HTTP_CONST.VERSION_1_0)
    updateResponseFor(exchange, HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR, reason)
  end

  function HttpExchange.redirect(exchange, location, status, reason, bodyContent)
    exchange:getResponse():setHeader(HTTP_CONST.HEADER_LOCATION, location)
    updateResponseFor(exchange, status or HTTP_CONST.HTTP_FOUND, reason, bodyContent)
  end

  function HttpExchange.response(exchange, status, reason, bodyContent)
    updateResponseFor(exchange, status or HTTP_CONST.HTTP_OK, reason, bodyContent)
  end

  function HttpExchange.isValidSubPath(path)
    -- Checks whether it starts, ends or contains /../
    return not (string.find(path, '/../', 1, true) or string.match(path, '^%.%./') or string.match(path, '/%.%.$') or string.find(path, '\\', 1, true))
    --return not string.find(path, '..', 1, true)
  end

  function HttpExchange.methodAllowed(exchange, method)
    local requestMethod = exchange:getRequestMethod()
    if type(method) == 'string' then
      if requestMethod == method then
        return true
      end
    elseif type(method) == 'table' then
      if List.contains(method, requestMethod) then
        return true
      end
    end
    HttpExchange.methodNotAllowed(exchange)
    return false
  end

end)
