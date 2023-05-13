--- Represents an Uniform Resource Locator.
-- @module jls.net.Url
-- @pragma nostrip

--local logger = require("jls.lang.logger")
local StringBuffer = require('jls.lang.StringBuffer')
local Map = require('jls.util.Map')

--- The Url class represents an Uniform Resource Locator.
-- see https://tools.ietf.org/html/rfc1738
-- @type Url
return require('jls.lang.class').create(function(url, _, Url)

  --- Creates a new Url.
  -- @function Url:new
  -- @param protocol The protocol or the Url as a string or the Url as a table.
  -- @tparam[opt] string host The host name.
  -- @tparam[opt] string port The port number.
  -- @tparam[opt] string file The file part of the Url.
  -- @return a new Url
  -- @usage
  --local url = Url:new('http://somehost:1234/some/path')
  --url:getHost() -- returns "somehost"
  function url:initialize(protocol, host, port, file)
    if not host then
      if type(protocol) == 'string' then
        self.s = protocol
        self.t = assert(Url.parse(protocol))
      elseif type(protocol) == 'table' then
        self.t = protocol
      else
        error('Invalid Url argument ('..type(protocol)..')')
      end
    else
      self.t = {
        scheme = protocol,
        host = host,
        port = port,
        path = file
      }
    end
  end

  --- Returns this Url scheme.
  -- @return this Url scheme.
  function url:getProtocol()
    return self.t.scheme
  end

  --- Returns this Url userInfo.
  -- @return this Url userInfo.
  function url:getUserInfo()
    if self.t.password then
      return self.t.username..':'..self.t.password
    end
    return self.t.username
  end

  --- Returns this Url hostname.
  -- @return this Url hostname.
  function url:getHost()
    return self.t.host
  end

  --- Returns this Url port.
  -- @return this Url port.
  function url:getPort()
    return self.t.port
  end

  --- Returns this Url path.
  -- @return this Url path.
  function url:getPath()
    return self.t.path
  end

  --- Returns this Url query.
  -- @return this Url query.
  function url:getQuery()
    return self.t.query
  end

  function url:getFile()
    local file = self.t.path
    if file == '' then
      file = '/'
    end
    if self.t.query then
      if file then
        file = file..'?'..self.t.query
      else
        file = '?'..self.t.query
      end
    end
    return file
  end

  function url:getRef()
    return self.t.fragment
  end

  --- Returns the string value representing this Url.
  -- @return the string value representing this Url.
  function url:toString()
    if not self.s then
      self.s = Url.format(self.t)
    end
    return self.s
  end

  local PORT_BY_SCHEME = {
    http = 80,
    https = 443,
    ws = 80,
    wss = 443
  }

  local function parseHostPort(hostport)
    if string.find(hostport, '^%[') then -- IPv6 addresses are enclosed in brackets
      return string.match(hostport, '^%[([^%]]+)%]:?(%d*)$')
    end
    return string.match(hostport, '^([^:]+):?(%d*)$')
  end

  -- //<username>:<password>@<host>:<port>/<url-path>
  local function parseCommon(scheme, specificPart)
    local tUrl = {
      scheme = scheme,
      port = PORT_BY_SCHEME[scheme]
    }
    local authority, path = string.match(specificPart, '^//([^/]+)(/?.*)$') -- we are lazy on the slash
    if not authority then
      tUrl.path = specificPart
      return tUrl
    end
    tUrl.path = path
    local userinfo, hostport = string.match(authority, '^([^@]+)@(.*)$')
    if userinfo then
      local username, password = string.match(userinfo, '^([^:]+):(.*)$')
      if username then
        tUrl.username = username
        tUrl.password = password
      else
        tUrl.userinfo = userinfo
      end
    else
      hostport = authority
    end
    local host, port = parseHostPort(hostport)
    if not host then
      return nil, 'Invalid common Url, bad host and port part ("'..scheme..specificPart..'")'
    end
    tUrl.host = host
    if #port > 0 then
      port = tonumber(port)
      if not port then
        return nil, 'Invalid common Url, bad port ("'..scheme..specificPart..'")'
      end
      tUrl.port = port
    end
    return tUrl
  end

  local function parseHttp(scheme, specificPart)
    local tUrl, err = parseCommon(scheme, specificPart)
    if err then
      return nil, err
    end
    if not tUrl.path then
      return tUrl
    end
    local path, fragment = string.match(tUrl.path, '^([^#]*)#(.*)$')
    if path then
      tUrl.fragment = fragment
    else
      path = tUrl.path
    end
    local qpath, query = string.match(path, '^([^%?]*)%?(.*)$')
    if qpath then
      path = qpath
      tUrl.query = query
    end
    tUrl.path = path
    return tUrl
  end

  --- Returns the Url corresponding to the specified string.
  -- The table contains the keys: scheme, host, port, path, query, userinfo, username, password.
  -- @tparam string sUrl The string to parse.
  -- @treturn table a table representing the Url or nil.
  function Url.parse(sUrl)
    -- scheme:[//[username[:password]@]host[:port]][/path][?query][#fragment]
    local scheme, specificPart = string.match(sUrl, '^([%w][%w%+%.%-]*):(.*)$')
    if not scheme then
      return nil, 'Invalid URL scheme ("'..sUrl..'")'
    end
    scheme = string.lower(scheme)
    if scheme == 'http' or scheme == 'https' or scheme == 'ws' or scheme == 'wss' then
      return parseHttp(scheme, specificPart)
    end
    return parseCommon(scheme, specificPart)
  end

  --- Returns the Url corresponding to the specified string.
  -- @tparam string sUrl The Url as a string.
  -- @treturn jls.net.Url the Url or nil.
  function Url.fromString(sUrl)
    local tUrl = Url.parse(sUrl)
    if tUrl then
      return Url:new(tUrl)
    end
    return nil
  end

  local function formatCommon(tUrl)
    local buffer = StringBuffer:new()
    buffer:append(tUrl.scheme, ':')
    if tUrl.host then
      buffer:append('//')
      if tUrl.userinfo then
        buffer:append(tUrl.userinfo)
        buffer:append('@')
      elseif tUrl.username or tUrl.user then
        buffer:append(tUrl.username or tUrl.user)
        if tUrl.password then
          buffer:append(':', tUrl.password)
        end
        buffer:append('@')
      end
      if string.find(tUrl.host, ':') then -- IPv6 addresses are enclosed in brackets
        buffer:append('[', tUrl.host, ']')
      else
        buffer:append(tUrl.host)
      end
      if tUrl.port and tUrl.port ~= PORT_BY_SCHEME[tUrl.scheme] then
        buffer:append(':', tUrl.port)
      end
      if tUrl.path and string.match(tUrl.path, '^/') then
        buffer:append(tUrl.path)
      end
    elseif tUrl.path then
      buffer:append(tUrl.path)
    end
    return buffer
  end

  local function formatQuery(buffer, query, keyValues)
    local needAmp = false
    if query then
      buffer:append('?')
      buffer:append(query)
      needAmp = true
    end
    if type(keyValues) == 'table' then
      for key, value in Map.spairs(keyValues) do
        if needAmp then
          buffer:append('&')
        else
          buffer:append('?')
          needAmp = true
        end
        buffer:append(Url.encodeURIComponent(key))
        buffer:append('=')
        buffer:append(Url.encodeURIComponent(value))
      end
    end
    return buffer
  end

  local function formatHttp(tUrl)
    local buffer = formatCommon(tUrl)
    formatQuery(buffer, tUrl.query, tUrl.queryValues)
    if tUrl.fragment then
      buffer:append('#')
      buffer:append(tUrl.fragment)
    end
    return buffer
  end

  --- Returns the query representing the key value pairs including the question mark.
  -- @tparam table keyValues the key value pairs.
  -- @tparam[opt] string query the base query to add key values.
  -- @return the query representing the key value pairs.
  function Url.mapToQuery(keyValues, query)
    return formatQuery(StringBuffer:new(), query, keyValues):toString()
  end

  --- Returns the string value representing the specified Url.
  -- @tparam table tUrl The Url as a table.
  -- @return the string value representing the Url.
  function Url.format(tUrl)
    if tUrl.scheme == 'http' or tUrl.scheme == 'https' then
      return formatHttp(tUrl):toString()
    end
    return formatCommon(tUrl):toString()
  end

  local function encodePercentChar(c)
      return string.format('%%%02X', string.byte(c))
    end
  local function encodePercent(value, pattern)
    return (string.gsub(value, pattern, encodePercentChar))
  end

  function Url.encodeURIComponent(value)
    return encodePercent(value, "[^%a%d%-_%.!~%*'%(%)]")
  end

  function Url.encodeURI(value)
    return encodePercent(value, "[^%a%d%-%._~;,/%?:@&=%+%$!%*'%(%)#]")
  end

  function Url.encodePercent(value)
    return encodePercent(value, '[^%a%d%-%._~]')
  end

  local function decodePercent(v)
      local n = tonumber(v, 16)
      if n < 256 then
        return string.char(n)
      end
      return ''
    end
  function Url.decodePercent(value)
    return (string.gsub(value, '%%(%x%x)', decodePercent))
  end

end)
