--- The HttpExchange class wraps the HTTP request and response.
-- @module jls.net.http.HttpExchange
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local HttpMessage = require('jls.net.http.HttpMessage')
local HttpResponse = require('jls.net.http.HttpResponse')

--- The HttpExchange class wraps the HTTP request and response.
-- @type HttpExchange
return require('jls.lang.class').create(require('jls.net.http.Attributes'), function(httpExchange)

  --- Creates a new Exchange.
  -- @function HttpExchange:new
  function httpExchange:initialize(server, client)
    self.attributes = {}
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

  --- Returns the HTTP request.
  -- @treturn HttpRequest the HTTP request.
  function httpExchange:getRequest()
    return self.request
  end

  function httpExchange:setRequest(value)
    self.request = value
  end

  --- Returns the HTTP response.
  -- @treturn HttpResponse the HTTP response.
  function httpExchange:getResponse()
    return self.response
  end

  function httpExchange:setResponse(value)
    self.response = value
  end

  --- Returns the captured values of the request target path using the context path.
  -- @treturn string the first captured value, nil if there is no captured value.
  function httpExchange:getRequestArguments()
    return select(3, string.find(self:getRequest():getTargetPath(), '^'..self:getContext():getPath()..'$'))
  end

  --- Returns a new HTTP response.
  -- @treturn HttpResponse a new HTTP response.
  function httpExchange:createResponse()
    local response = HttpResponse:new()
    response:setHeader(HttpMessage.CONST.HEADER_CONNECTION, HttpMessage.CONST.CONNECTION_CLOSE)
    response:setHeader(HttpMessage.CONST.HEADER_SERVER, HttpMessage.CONST.DEFAULT_SERVER)
    return response
  end

  function httpExchange:prepareResponse(response)
    local body = response:getBody()
    if not response:getContentLength() then
      if type(body) == 'string' then
        response:setContentLength(string.len(body))
      else
        response:setContentLength(0)
      end
    end
  end

  function httpExchange:handleRequest(context)
    if logger:isLoggable(logger.FINER) then
      logger:finer('HttpServer:handleRequest() "'..self:getRequest():getTarget()..'"')
    end
    self:setContext(context)
    local status, result = pcall(function ()
      local handler = context:getHandler()
      return handler(self)
    end)
    if status then
      -- always return a promise
      if Promise:isInstance(result) then
        return result
      end
      return Promise.resolve()
    end
    if logger:isLoggable(logger.WARN) then
      logger:warn('HttpServer error while handling "'..self:getRequest():getTarget()..'", due to "'..tostring(result)..'"')
    end
    local response = self:getResponse()
    response:close()
    response = self:createResponse()
    response:setStatusCode(HttpMessage.CONST.HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error')
    self:setResponse(response)
    return Promise.reject(result or 'Unkown error')
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

  function httpExchange:processRequest()
    if logger:isLoggable(logger.FINER) then
      logger:finer('httpExchange:processRequest()')
    end
    local request = self:getRequest()
    local path = request:getTargetPath()
    local context = self.server:getHttpContext(path)
    self:setResponse(self:createResponse())
    return self:handleRequest(context)
  end

  function httpExchange:removeClient()
    local client = self.client
    self.client = nil
    return client
  end

  function httpExchange:close()
    logger:finest('httpExchange:close()')
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