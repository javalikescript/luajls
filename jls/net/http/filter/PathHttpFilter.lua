--- Provide a simple HTTP path filter.
-- @module jls.net.http.filter.PathHttpFilter
-- @pragma nostrip

local strings = require('jls.util.strings')

--- A PathHttpFilter class.
-- @type PathHttpFilter
return require('jls.lang.class').create('jls.net.http.HttpFilter', function(pathFilter)

  --- Creates a @{HttpFilter} by path.
  -- This filter allows to restrict a filter to a set of allowed or excluded path patterns.
  -- @tparam HttpFilter filter the filter to apply depending on the allowed/excluded patterns.
  -- @tparam[opt] table patterns a list of allowed patterns.
  -- @tparam[opt] table excludedPatterns a list of excluded patterns.
  -- @function PathHttpFilter:new
  function pathFilter:initialize(filter, patterns, excludedPatterns)
    self.filter = filter
    self.patterns = patterns or {}
    self.excludedPatterns = excludedPatterns or {}
  end

  local function addPatterns(list, escape, ...)
    for _, pattern in ipairs({...}) do
      if escape then
        pattern = '^'..strings.escape(pattern)..'$'
      end
      table.insert(list, pattern)
    end
  end

  function pathFilter:allow(...)
    addPatterns(self.patterns, false, ...)
    return self
  end

  function pathFilter:allowPath(...)
    addPatterns(self.patterns, true, ...)
    return self
  end

  function pathFilter:exclude(...)
    addPatterns(self.excludedPatterns, false, ...)
    return self
  end

  function pathFilter:excludePath(...)
    addPatterns(self.excludedPatterns, true, ...)
    return self
  end

  function pathFilter:doFilter(exchange)
    local request = exchange:getRequest()
    local path = request:getTargetPath()
    for _, pattern in ipairs(self.excludedPatterns) do
      if string.match(path, pattern) then
        return
      end
    end
    if #self.patterns == 0 then
      return self.filter:doFilter(exchange)
    end
    for _, pattern in ipairs(self.patterns) do
      if string.match(path, pattern) then
        return self.filter:doFilter(exchange)
      end
    end
  end

end)
