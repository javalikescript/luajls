--[[--
HTTP filter class.

A filter allows to process an HTTP exchange prior to call the handler.
It can be used for tasks such as authentication, access control, logging.

@module jls.net.http.HttpFilter
@pragma nostrip
]]

--- A HttpFilter class.
-- @type HttpFilter
return require('jls.lang.class').create(function(httpFilter)

  --- Creates an HTTP filter.
  -- @tparam[opt] function fn a function that will be call to filter the HTTP exchange
  -- @function HttpFilter:new
  function httpFilter:initialize(fn)
    if type(fn) == 'function' then
      self.doFilter = fn
    end
  end

  --- Filters the specified exchange.
  -- Called when the request headers have been received.
  -- @tparam HttpExchange httpExchange the HTTP exchange to filter
  -- @treturn boolean false to indicate the request must not handled.
  function httpFilter:doFilter(httpExchange)
  end

end)
