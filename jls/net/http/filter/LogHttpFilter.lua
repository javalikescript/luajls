--[[-- Provide a simple HTTP filter for logging.

After adding this filter, any request containing the header *jls-logger-level* will increase the global log level.

@module jls.net.http.filter.LogHttpFilter
@pragma nostrip
]]

local logger = require('jls.lang.logger')

--- A LogHttpFilter class.
-- @type LogHttpFilter
return require('jls.lang.class').create('jls.net.http.HttpFilter', function(logHttpFilter)

  function logHttpFilter:doFilter(exchange)
    local ml = exchange:getRequest():getHeader('jls-logger-level')
    if ml then
      ml = logger:getClass().levelFromString(ml)
      if ml then
        local level = logger:getLevel()
        if ml < level then
          logger:setLevel(ml)
          exchange:onClose():next(function()
            logger:setLevel(level)
          end)
        end
      end
    end
  end

end)
