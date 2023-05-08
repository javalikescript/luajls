--[[-- Provide a simple HTTP path filter.

This filter allows to restrict a filter to a set of allowed or excluded path patterns.

@module jls.net.http.filter.PathHttpFilter
@pragma nostrip
]]

--- A PathHttpFilter class.
-- @type PathHttpFilter
return require('jls.lang.class').create('jls.net.http.HttpFilter', function(pathFilter)

  function pathFilter:initialize(filter, patterns, excludedPatterns)
    self.filter = filter
    self.patterns = patterns or {}
    self.excludedPatterns = excludedPatterns or {}
  end

  function pathFilter:addAllowedPattern(pattern)
    table.insert(self.patterns, pattern)
    return self
  end

  function pathFilter:addExcludedPattern(pattern)
    table.insert(self.excludedPatterns, pattern)
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
