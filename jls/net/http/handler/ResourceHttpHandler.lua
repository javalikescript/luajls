--- Provide a simple HTTP handler for resources.
-- @module jls.net.http.handler.ResourceHttpHandler
-- @pragma nostrip

local loader = require('jls.lang.loader')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local Date = require('jls.util.Date')

--- A ResourceHttpHandler class.
-- @type ResourceHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(resourceHttpHandler)

  --- Creates a resource @{HttpHandler}.
  -- @function ResourceHttpHandler:new
  function resourceHttpHandler:initialize(prefix, filename)
    self.prefix = prefix or ''
    self.defaultFile = filename or 'index.html'
    self.date = Date:new()
  end

  function resourceHttpHandler:handle(exchange)
    if not HttpExchange.methodAllowed(exchange, {HTTP_CONST.METHOD_GET, HTTP_CONST.METHOD_HEAD}) then
      return
    end
    local response = exchange:getResponse()
    local path = exchange:getRequestPath()
    if path == '' or string.sub(path, -1) == '/' then
      path = path..self.defaultFile
    end
    local resource = loader.loadResource(self.prefix..path, true)
    if resource then
      response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
      response:setContentType(FileHttpHandler.guessContentType(path))
      response:setCacheControl(true)
      response:setLastModified(self.date)
      response:setContentLength(#resource)
      if exchange:getRequestMethod() == HTTP_CONST.METHOD_GET then
        local request = exchange:getRequest()
        local ifModifiedSince = request:getIfModifiedSince()
        if ifModifiedSince and self.date:getTime() <= ifModifiedSince then
          response:setStatusCode(HTTP_CONST.HTTP_NOT_MODIFIED, 'Not modified')
          return
        end
        response:setBody(resource)
      end
    else
      HttpExchange.notFound(exchange)
    end
  end

end)
