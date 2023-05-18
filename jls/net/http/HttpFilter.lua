--[[--
HTTP filter class.

A filter allows to process an HTTP exchange prior to call the handler.
It can be used for tasks such as authentication, access control, logging.

@module jls.net.http.HttpFilter
@pragma nostrip
]]

local class = require('jls.lang.class')

--- A HttpFilter class.
-- @type HttpFilter
return class.create(function(httpFilter)

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

  --- Applies the specified filters in the specified order.
  -- @tparam HttpExchange exchange the HTTP exchange to filter
  -- @param ... the filters.
  -- @treturn boolean false to indicate the request must not handled.
  function HttpFilter.filter(exchange, filters)
    for _, filter in ipairs(filters) do
      if filter:doFilter(exchange) == false then
        return false
      end
    end
    return true
  end

  local MultipleHttpFilter = class.create(HttpFilter, function(filter)
    function filter:initialize(...)
      self.filters = {...}
    end
    function filter:addFilter(f)
      table.insert(self.filters, f)
      return self
    end
    function filter:doFilter(exchange)
      return HttpFilter.filter(exchange, self.filters)
    end
  end)

  --- Returns a filter applying all the specified filters.
  -- @param ... the filters.
  -- @treturn HttpFilter a HttpFilter.
  function HttpFilter.multiple(...)
    return MultipleHttpFilter:new(...)
  end

  --- Creates a basic authentication filter.
  -- @param credentials a table with user name and password pairs or a function.
  -- The function receives the user and the password and return true when they match an existing credential.
  -- @tparam[opt] string realm an optional message.
  -- @treturn HttpFilter a HttpFilter.
  function HttpFilter.basicAuth(...)
    return require('jls.net.http.filter.BasicAuthenticationHttpFilter'):new(...)
  end

  --- Returns a session filter.
  -- This filter add a session id cookie to the response and maintain the exchange session.
  -- @tparam[opt] number maxAge the session max age in seconds, default to 12 hours.
  -- @treturn HttpFilter a HttpFilter.
  function HttpFilter.session(...)
    return require('jls.net.http.filter.SessionHttpFilter'):new(...)
  end

  --- Returns a filter by path.
  -- This filter allows to restrict a filter to a set of allowed or excluded path patterns.
  -- @tparam HttpFilter filter the filter to apply depending on the allowed/excluded patterns.
  -- @tparam[opt] table patterns a list of allowed patterns.
  -- @tparam[opt] table excludedPatterns a list of excluded patterns.
  -- @treturn HttpFilter a HttpFilter.
  function HttpFilter.byPath(...)
    return require('jls.net.http.filter.PathHttpFilter'):new(...)
  end

end)
