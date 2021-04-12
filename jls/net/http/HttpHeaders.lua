--- This class provides common behavior for HTTP headers.
-- @module jls.net.http.HttpHeaders
-- @pragma nostrip

local logger = require('jls.lang.logger')
local StringBuffer = require('jls.lang.StringBuffer')
local strings = require('jls.util.strings')

--- The HttpHeaders class represents the headers for HTTP message.
-- @type HttpHeaders
return require('jls.lang.class').create(function(httpHeaders, _, HttpHeaders)

  --- Creates a new Message.
  -- @function HttpHeaders:new
  function httpHeaders:initialize(headers)
    if headers then
      self.headers = headers
    else
      self.headers = {}
    end
  end

  --- Returns the header value for the specified name.
  -- This is the raw value and may contains multiple entries.
  -- @tparam string name the name of the header.
  -- @treturn string the header value corresponding to the name or nil if there is no such header.
  function httpHeaders:getHeader(name)
    return self.headers[string.lower(name)]
  end

  function httpHeaders:getHeaderValues(name)
    --[[
      see
        https://www.iana.org/assignments/message-headers/message-headers.xhtml
        https://tools.ietf.org/html/rfc7231#section-5.3.4
        https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
    ]]
    local rawValue = self:getHeader(name)
    if rawValue then
      return strings.split(rawValue, '%s*,%s*')
    end
  end

  function httpHeaders:setHeaderValues(name, values)
    if type(values) == 'table' then
      self:setHeader(name, table.concat(values, ', '))
    end
  end

  function httpHeaders:hasHeaderIgnoreCase(name, value)
    return string.lower(self:getHeader(name)) == string.lower(value)
  end

  function httpHeaders:hasHeaderValue(name, value)
    local values = self:getHeaderValues(name)
    if values then
      for _, v in ipairs(values) do
        local pv = HttpHeaders.parseHeaderValue(v)
        if pv == value then
          return true
        end
      end
    end
    return false
  end

  function httpHeaders:setHeader(name, value)
    local valueType = type(value)
    if valueType == 'string' or valueType == 'number' or valueType == 'boolean' then
      self.headers[string.lower(name)] = tostring(value)
    else
      logger:fine('httpHeaders:setHeader('..tostring(name)..', '..tostring(value)..') Invalid value will be ignored')
    end
  end

  function httpHeaders:parseHeaderLine(line)
    local index, _, name, value = string.find(line, '^([^:]+):%s*(.*)%s*$')
    if index then
      self:setHeader(name, value)
      return true
    end
    return false
  end

  function httpHeaders:getHeadersTable()
    return self.headers
  end

  function httpHeaders:setHeadersTable(headers)
    for name, value in pairs(headers) do
      self:setHeader(name, value)
    end
  end

  function httpHeaders:appendHeaders(buffer)
    for name, value in pairs(self:getHeadersTable()) do
      -- TODO Capitalize names
      buffer:append(name, ': ', tostring(value), '\r\n')
    end
    return buffer
  end

  function httpHeaders:getRawHeaders()
    return self:appendHeaders(StringBuffer:new()):toString()
  end

  --- Returns the header start value and a table containing the header value parameters.
  -- @tparam string value the header value to parse.
  -- @treturn string the header start value.
  -- @treturn table a table containing the header value parameters.
  function HttpHeaders.parseHeaderValue(value)
    local params = strings.split(value, '%s*;%s*')
    local startValue = table.remove(params, 1)
    --return table.unpack(params)
    return startValue, params
  end

  --- Returns the header start value and a table containing the header value parameters.
  -- @tparam string value the header value to parse.
  -- @treturn string the header start value.
  -- @treturn table a table containing the header parameters as key, value.
  function HttpHeaders.parseHeaderValueAsTable(value)
    local startValue, params = HttpHeaders.parseHeaderValue(value)
    local t = {}
    for _, param in ipairs(params) do
      local k, v = string.match(param, '^([^=]+)%s*=%s*(.*)$')
      if k then
        t[k] = v
      end
    end
    return startValue, t
  end

  function HttpHeaders.equalsIgnoreCase(a, b)
    return a == b or (type(a) == 'string' and type(b) == 'string' and string.lower(a) == string.lower(b))
  end

  -- TODO Move HTTP headers constants here

end)
