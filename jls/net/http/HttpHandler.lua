--[[--
Base HTTP handler class.

An HTTP handler provides a way to deal with an HTTP request.
Basicaly it consists in a function that will be called when an HTTP request
has been received but before the request body was consumed.

@module jls.net.http.HttpHandler
@pragma nostrip

@usage
local handler = HttpHandler:new(function(httpExchange)
  local response = httpExchange:getResponse()
  response:setBody('It works !')
end)
]]

local Promise = require('jls.lang.Promise')

--- A HttpHandler class.
-- By default the handler will be called after the request body is available.
-- The handler could also be configured to be called after the request headers but before the request body.
-- @type HttpHandler
return require('jls.lang.class').create(function(httpHandler)

  --- Creates an HTTP handler.
  -- @tparam[opt] function fn a function that will handle the HTTP exchange
  -- @function HttpHandler:new
  function httpHandler:initialize(fn)
    if type(fn) == 'function' then
      self.fn = fn
    end
  end

  --- Handles the request for the specified exchange.
  -- @tparam HttpExchange httpExchange the HTTP exchange to handle
  -- @treturn jls.lang.Promise a promise that resolves once the response is completed.
  function httpHandler:handle(httpExchange)
    if self.fn then
      return self.fn(httpExchange)
    end
  end

end, function(HttpHandler)

  function HttpHandler.onBody(fn)
    if type(fn) ~= 'function' then
      error('Invalid on body function handler, type ('..type(fn)..')')
    end
    return HttpHandler:new(function(httpExchange)
      -- TODO buffer only for POST and PUT request
      httpExchange:getRequest():bufferBody()
      return httpExchange:onRequestBody():next(function()
        local r = fn(httpExchange)
        if Promise:isInstance(r) then
          return r
        end
      end)
    end)
  end

end)
