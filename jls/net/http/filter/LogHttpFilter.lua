--[[-- Provide a simple HTTP filter for logging.

After adding this filter, any request containing the header *jls-logger-level* will increase the global log level.

@module jls.net.http.filter.LogHttpFilter
@pragma nostrip
]]

local rootLogger = require('jls.lang.logger')

--- A LogHttpFilter class.
-- @type LogHttpFilter
return require('jls.lang.class').create('jls.net.http.HttpFilter', function(filter)

  function filter:doFilter(exchange)
    local ll = exchange:getRequest():getHeader('jls-logger-level')
    if ll then
      local config = rootLogger:getConfig()
      rootLogger:setConfig(ll)
      exchange:onClose():next(function()
        rootLogger:setConfig(config)
      end)
    end
  end

end)
