--- This class provides common behavior for HTTP headers.
-- @module jls.net.http.HttpHeaders
-- @pragma nostrip

local logger = require('jls.lang.logger')
local StringBuffer = require('jls.lang.StringBuffer')
local strings = require('jls.util.strings')
local Map = require('jls.util.Map')
local List = require('jls.util.List')

local function normalizeName(name)
  return string.lower(name)
end

--- The HttpHeaders class represents the headers for HTTP message.
-- @type HttpHeaders
return require('jls.lang.class').create(function(httpHeaders, _, HttpHeaders)

  --- Creates a new Headers.
  -- @function HttpHeaders:new
  function httpHeaders:initialize(headers)
    self.headers = {}
    if headers then
      self:setHeadersTable(headers)
    end
  end

  --- Returns the header value for the specified name.
  -- This is the raw value and may contains multiple entries.
  -- @tparam string name the name of the header.
  -- @treturn string the header value corresponding to the name or nil if there is no such header.
  function httpHeaders:getHeader(name)
    return self.headers[normalizeName(name)]
  end

  --- Removes all the header values.
  function httpHeaders:clearHeaders()
    self.headers = {}
  end

  function httpHeaders:getHeaderValues(name)
    --[[
      see
        https://www.iana.org/assignments/message-headers/message-headers.xhtml
        https://tools.ietf.org/html/rfc7231#section-5.3.4
        https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
    ]]
    local rawValue = self:getHeader(name)
    if rawValue == nil then
      return {}
    end
    if type(rawValue) == 'string' then
      return strings.split(rawValue, '%s*,%s*')
    elseif type(rawValue) == 'table' then
      return rawValue
    end
    return {rawValue}
  end

  function httpHeaders:setHeaderValues(name, values)
    if type(values) == 'table' then
      self:setHeader(name, table.concat(values, ', '))
    end
  end

  function httpHeaders:hasHeaderValueIgnoreCase(name, value)
    local v = self:getHeader(name)
    if v then
      return string.lower(v) == string.lower(value)
    end
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

  --- Sets the specified header value.
  -- This is the raw value and may contains multiple entries.
  -- @tparam string name the name of the value.
  -- @param value the value to set.
  function httpHeaders:setHeader(name, value)
    local valueType = type(value)
    if valueType == 'string' or valueType == 'nil' then
      -- keep value
    elseif valueType == 'number' or valueType == 'boolean' then
      value = tostring(value)
    elseif valueType == 'table' then
      -- We should check that values are strings
      local t = {}
      for _, val in ipairs(value) do
        if type(val) == 'string' then
          table.insert(t, val)
        end
      end
      value = t
    else
      logger:fine('httpHeaders:setHeader(%s, %s) ignoring header value', name, valueType)
      return
    end
    self.headers[normalizeName(name)] = value
  end

  local HEADER_SET_COOKIE = 'set-cookie'

  function httpHeaders:setCookie(name, value, options)
    local list = self.headers[HEADER_SET_COOKIE]
    local nameEq = name..'='
    if type(list) == 'table' then
      List.removeIf(list, function(v)
        return string.sub(v, 1, #nameEq) == nameEq
      end)
    else
      list = {}
      self.headers[HEADER_SET_COOKIE] = list
    end
    if type(options) == 'table' then
      value = value..'; '..table.concat(options, '; ')
    end
    table.insert(list, nameEq..value)
  end

  function httpHeaders:getCookies()
    local map = {}
    local values = self.headers['cookie']
    if type(values) == 'string' then
      for name, value in string.gmatch(values, '([^=;%s]+)%s*=%s*([^=;%s]+)') do
        map[name] = value
      end
    end
    return map
  end

  function httpHeaders:getCookie(name)
    return self:getCookies()[name]
  end

  --- Adds the specified header value.
  -- @tparam string name the name of the value.
  -- @tparam string value the value to set.
  function httpHeaders:addHeaderValue(name, value)
    local key = normalizeName(name)
    local val = self.headers[key]
    if val == nil then
      self.headers[key] = tostring(value)
    elseif type(val) == 'string' then
      -- the "Set-Cookie" response header field often appears multiple times in a response message and does not use the list syntax
      if key == HEADER_SET_COOKIE then
        self.headers[key] = {val, tostring(value)}
      else
        self.headers[key] = val..', '..tostring(value)
      end
    elseif type(val) == 'table' then
      table.insert(val, tostring(value))
    end
  end

  function httpHeaders:parseHeaderLine(line)
    local index, _, name, value = string.find(line, '^([^:]+):%s*(.*)%s*$')
    if index then
      self:addHeaderValue(name, value)
      return true
    end
    return false
  end

  function httpHeaders:getHeadersTable()
    return self.headers
  end

  function httpHeaders:setHeadersTable(headers)
    self:clearHeaders()
    for name, value in pairs(headers) do
      self:setHeader(name, value)
    end
  end

  function httpHeaders:appendHeaders(buffer)
    for name, value in Map.spairs(self.headers) do
      if type(value) == 'string' then
        buffer:append(name, ': ', value, '\r\n')
      elseif type(value) == 'table' then
        for _, val in ipairs(value) do
          buffer:append(name, ': ', tostring(val), '\r\n')
        end
      end
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

  -- TODO Move HTTP headers constants here

end)
