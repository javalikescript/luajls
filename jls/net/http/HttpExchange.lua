--- The HttpExchange class wraps the HTTP request and response.
-- @module jls.net.http.HttpExchange
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local protectedCall = require('jls.lang.protectedCall')
local HttpHeaders = require('jls.net.http.HttpHeaders')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpRequest = require('jls.net.http.HttpRequest')
local HttpResponse = require('jls.net.http.HttpResponse')
local List = require('jls.util.List')
local HTTP_CONST = HttpMessage.CONST

--- The HttpExchange class wraps the HTTP request and response.
-- @type HttpExchange
return require('jls.lang.class').create('jls.net.http.Attributes', function(httpExchange, super)

  function httpExchange:initialize(client)
    super.initialize(self)
    self.client = client
    self.request = HttpRequest:new()
    self.response = HttpResponse:new()
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

  --- Returns the HTTP request.
  -- @treturn HttpRequest the HTTP request.
  function httpExchange:getRequest()
    return self.request
  end

  --- Returns the HTTP response.
  -- @treturn HttpResponse the HTTP response.
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
  -- @tparam number statusCode the status code.
  -- @tparam[opt] string reasonPhrase the reason phrase.
  -- @tparam[opt] string body the response body.
  function httpExchange:setResponseStatusCode(statusCode, reasonPhrase, body)
    self.response:setStatusCode(statusCode, reasonPhrase)
    if body then
      self.response:setBody(body)
    end
  end

  function httpExchange:applyKeepAlive()
    local connection = HttpMessage.CONST.HEADER_CONNECTION
    local requestConnection = self.request:getHeader(connection)
    local responseConnection = self.response:getHeader(connection)
    if requestConnection == HttpMessage.CONST.CONNECTION_KEEP_ALIVE then
      if not responseConnection then
        self.response:setHeader(connection, requestConnection)
        return true
      elseif responseConnection == requestConnection then
        return true
      end
      self.response:setHeader(connection, HttpMessage.CONST.CONNECTION_CLOSE)
    elseif not responseConnection then
      self.response:setHeader(connection, HttpMessage.CONST.CONNECTION_CLOSE)
    end
    return false
  end

  function httpExchange:prepareResponseHeaders()
    self.response:setHeader(HttpMessage.CONST.HEADER_SERVER, HttpMessage.CONST.DEFAULT_SERVER)
    self.response:applyBodyLength()
  end

  function httpExchange:resetResponseToError(reason)
    local r = reason and tostring(reason) or 'Unkown error'
    local response = self.response
    response:close()
    response = HttpResponse:new()
    response:setStatusCode(HttpMessage.CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
    self.response = response
    self:notifyRequestBody(r)
  end

  function httpExchange:handleRequest(context)
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpExchange:handleRequest() "'..self.request:getTarget()..'"')
    end
    self.context = context
    local status, result = protectedCall(context.handleExchange, context, self)
    if status then
      -- always return a promise
      if Promise:isInstance(result) then
        return result:catch(function(reason)
          logger:warn('HttpExchange error while handling "'..self:getRequest():getTarget()..'", due to "'..tostring(reason)..'"')
          self:resetResponseToError(reason)
        end)
      end
      return Promise.resolve()
    end
    if logger:isLoggable(logger.WARN) then
      logger:warn('HttpExchange error while handling "'..self:getRequest():getTarget()..'", due to "'..tostring(result)..'"')
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
    [HTTP_CONST.HTTP_NOT_FOUND] = 'Not Found',
    [HTTP_CONST.HTTP_METHOD_NOT_ALLOWED] = 'Method Not Allowed',
    [HTTP_CONST.HTTP_PAYLOAD_TOO_LARGE] = 'Payload Too Large',
    [HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR] = 'Internal Server Error',
  }

  HttpExchange.CONTENTS = {
    [HTTP_CONST.HTTP_BAD_REQUEST] = '<p>Sorry something seems to be wrong in your request.</p>',
    [HTTP_CONST.HTTP_FORBIDDEN] = '<p>The server cannot process your request.</p>',
    [HTTP_CONST.HTTP_NOT_FOUND] = '<p>The resource is not available.</p>',
    [HTTP_CONST.HTTP_METHOD_NOT_ALLOWED] = '<p>Sorry the method is not allowed.</p>',
    [HTTP_CONST.HTTP_PAYLOAD_TOO_LARGE] = '<p>Sorry the request is too large.</p>',
    [HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR] = '<p>Sorry something went wrong on our side.</p>',
  }

  local function updateResponseFor(httpExchange, statusCode, reasonPhrase, bodyContent)
    httpExchange:setResponseStatusCode(statusCode, reasonPhrase or HttpExchange.REASONS[statusCode], bodyContent or HttpExchange.CONTENTS[statusCode] or '')
  end

  --- Updates the response with the OK status code, 200.
  -- @tparam HttpExchange httpExchange ongoing HTTP exchange
  -- @tparam[opt] string body the response content.
  -- @tparam[opt] string contentType the response content type.
  function HttpExchange.ok(httpExchange, body, contentType)
    updateResponseFor(httpExchange, HTTP_CONST.HTTP_OK, nil, body)
    if type(contentType) == 'string' then
      httpExchange:getResponse():setContentType(contentType)
    end
  end

  --- Updates the response with the status code Bad Request, 400.
  -- @tparam HttpExchange httpExchange ongoing HTTP exchange
  -- @tparam[opt] string reasonPhrase the response reason phrase.
  function HttpExchange.badRequest(httpExchange, reasonPhrase)
    updateResponseFor(httpExchange, HTTP_CONST.HTTP_BAD_REQUEST, reasonPhrase)
  end

  --- Updates the response with the status code Forbidden, 403.
  -- @tparam HttpExchange httpExchange ongoing HTTP exchange
  -- @tparam[opt] string reasonPhrase the response reason phrase.
  function HttpExchange.forbidden(httpExchange, reasonPhrase)
    updateResponseFor(httpExchange, HTTP_CONST.HTTP_FORBIDDEN, reasonPhrase)
  end

  --- Updates the response with the status code Not Found, 404.
  -- @tparam HttpExchange httpExchange ongoing HTTP exchange
  function HttpExchange.notFound(httpExchange)
    updateResponseFor(httpExchange, HTTP_CONST.HTTP_NOT_FOUND, nil, '<p>The resource "'..httpExchange:getRequest():getTarget()..'" is not available.</p>')
  end

  --- Updates the response with the status code Method Not Allowed, 405.
  -- @tparam HttpExchange httpExchange ongoing HTTP exchange
  function HttpExchange.methodNotAllowed(httpExchange)
    updateResponseFor(httpExchange, HTTP_CONST.HTTP_METHOD_NOT_ALLOWED)
  end

  --- Updates the response with the status code Internal Server Error, 500.
  -- @tparam HttpExchange httpExchange ongoing HTTP exchange
  function HttpExchange.internalServerError(httpExchange)
    httpExchange:getResponse():setVersion(HTTP_CONST.VERSION_1_0)
    updateResponseFor(httpExchange, HTTP_CONST.HTTP_INTERNAL_SERVER_ERROR)
  end

  function HttpExchange.response(httpExchange, statusCode, reasonPhrase, bodyContent)
    updateResponseFor(httpExchange, statusCode or HTTP_CONST.HTTP_OK, reasonPhrase, bodyContent)
  end

  function HttpExchange.isValidSubPath(path)
    -- Checks whether it starts, ends or contains /../
    return not (string.find(path, '/../', 1, true) or string.match(path, '^%.%./') or string.match(path, '/%.%.$') or string.find(path, '\\', 1, true))
    --return not string.find(path, '..', 1, true)
  end

  function HttpExchange.methodAllowed(httpExchange, method)
    local requestMethod = httpExchange:getRequestMethod()
    if type(method) == 'string' then
      if requestMethod == method then
        return true
      end
    elseif type(method) == 'table' then
      if List.contains(method, requestMethod) then
        return true
      end
    end
    HttpExchange.methodNotAllowed(httpExchange)
    return false
  end

end)
