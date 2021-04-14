--- The HttpExchange class wraps the HTTP request and response.
-- @module jls.net.http.HttpExchange
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local HttpHeaders = require('jls.net.http.HttpHeaders')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpResponse = require('jls.net.http.HttpResponse')

--- The HttpExchange class wraps the HTTP request and response.
-- @type HttpExchange
return require('jls.lang.class').create(require('jls.net.http.Attributes'), function(httpExchange, super)

  --- Creates a new Exchange.
  -- @function HttpExchange:new
  function httpExchange:initialize(server, client)
    super.initialize(self)
    self.server = server
    self.client = client
  end

  --- Returns the HTTP context.
  -- @treturn HttpContext the HTTP context.
  function httpExchange:getContext()
    return self.context
  end

  function httpExchange:setContext(value)
    self.context = value
  end

  -- TODO Remove
  function httpExchange:getRequest()
    return self.request
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

  --- Returns a promise that resolves once the request body is available.
  -- @treturn jls.lang.Promise a promise that resolves once the request body is available.
  function httpExchange:onRequestBody()
    if not self.requestBodyPromise then
      self.requestBodyPromise, self.requestBodyCallback = Promise.createWithCallback()
    end
    return self.requestBodyPromise
  end

  function httpExchange:notifyRequestBody(error)
    if self.requestBodyCallback then
      self.requestBodyCallback(error, self)
      self.requestBodyCallback = nil
    end
  end

  function httpExchange:setRequest(request)
    self.request = request
  end

  --- Returns the captured values of the request target path using the context path.
  -- @treturn string the first captured value, nil if there is no captured value.
  function httpExchange:getRequestArguments()
    return self:getContext():getArguments(self:getRequest():getTargetPath())
  end

  --- Returns the HTTP response.
  -- @treturn HttpResponse the HTTP response.
  function httpExchange:getResponse()
    return self.response
  end

  function httpExchange:setResponse(response)
    self.response = response
  end

  function httpExchange:setResponseStatusCode(statusCode, reasonPhrase, body)
    self.response:setStatusCode(statusCode, reasonPhrase)
    if body then
      self.response:setBody(body)
    end
  end

  function httpExchange:createResponse()
    return HttpResponse:new()
  end

  function httpExchange:getOrCreateResponse()
    if not self.response then
      self.response = self:createResponse()
    end
    return self.response
  end

  function httpExchange:applyKeepAlive()
    local connection = HttpMessage.CONST.HEADER_CONNECTION
    local requestConnection = self.request:getHeader(connection)
    if requestConnection == HttpMessage.CONST.CONNECTION_KEEP_ALIVE then
      local responseConnection = self.response:getHeader(connection)
      if not responseConnection then
        self.response:setHeader(connection, requestConnection)
        return true
      elseif responseConnection == requestConnection then
        return true
      end
    end
    self.response:setHeader(connection, HttpMessage.CONST.CONNECTION_CLOSE)
    return false
  end

  function httpExchange:prepareResponse(response)
    response:setHeader(HttpMessage.CONST.HEADER_SERVER, HttpMessage.CONST.DEFAULT_SERVER)
    if not response:getContentLength() then
      if response:hasBody() then
        response:setContentLength(response:getBodyLength())
      else
        response:setContentLength(0)
      end
    end
  end

  function httpExchange:handleRequest(context)
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpExchange:handleRequest() "'..self.request:getTarget()..'"')
    end
    local status, result = xpcall(function ()
      return context:handleExchange(self)
    end, debug.traceback)
    if status then
      -- always return a promise
      if Promise:isInstance(result) then
        return result
      end
      return Promise.resolve()
    end
    if logger:isLoggable(logger.WARN) then
      logger:warn('HttpExchange error while handling "'..self:getRequest():getTarget()..'", due to "'..tostring(result)..'"')
    end
    local error = result or 'Unkown error'
    local response = self:getResponse()
    response:close()
    response = self:createResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
    self:setResponse(response)
    self:notifyRequestBody(error)
    return Promise.reject(error)
  end

  function httpExchange:processRequestHeaders()
    local path = self.request:getTargetPath()
    self.context = self.server:getMatchingContext(path)
    return self:handleRequest(self:getContext())
  end

  function httpExchange:processResponse()
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpExchange:processResponse()')
    end
    local response = self:getResponse()
    if not response then
      return Promise.reject('No response to process')
    end
    self:prepareResponse(response)
    return response:writeHeaders(self.client):next(function()
      return response:writeBody(self.client)
    end)
  end

  function httpExchange:removeClient()
    local client = self.client
    self.client = nil
    return client
  end

  function httpExchange:close()
    logger:finest('httpExchange:close()')
    self:cleanAttributes()
    if self.request then
      self.request:close()
      self.request = nil
    end
    if self.response then
      self.response:close()
      self.response = nil
    end
    if self.client then
      --self.client:readStop()
      self.client:close()
      self.client = nil
    end
  end
end)
