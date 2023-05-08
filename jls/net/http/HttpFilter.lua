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
  -- @tparam HttpExchange exchange the HTTP exchange to filter
  -- @treturn boolean false to indicate the request must not handled.
  function httpFilter:doFilter(exchange)
  end

  --- Closes this filter.
  -- Do nothing by default. Must support to be called multiple times.
  function httpFilter:close()
  end

end, function(HttpFilter)

  --- Creates a basic authentication filter.
  -- @param credentials a table with user name and password pairs or a function.
  -- The function receives the user and the password and return true when they match an existing credential.
  -- @tparam[opt] string realm an optional message.
  -- @treturn HttpFilter a HttpFilter.
  function HttpFilter.basicAuth(...)
    return require('jls.net.http.filter.BasicAuthenticationHttpFilter'):new(...)
  end

  function HttpFilter.session(...)
    return require('jls.net.http.filter.SessionHttpFilter'):new(...)
  end

  function HttpFilter.byPath(...)
    return require('jls.net.http.filter.PathHttpFilter'):new(...)
  end

end)
