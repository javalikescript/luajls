--- Represents an URL.
-- @module jls.net.URL
-- @pragma nostrip

--local logger = require("jls.lang.logger")
local StringBuffer = require('jls.lang.StringBuffer')

--- The URL class represents an Uniform Resource Locator.
-- see https://tools.ietf.org/html/rfc1738
-- @type URL
return require('jls.lang.class').create(function(url, _, URL)

  --- Creates a new URL.
  -- @function URL:new
  -- @param protocol The protocol or the URL as a string.
  -- @param host The host name.
  -- @param port The port number.
  -- @param file The file part of the URL.
  -- @return a new URL
  -- @usage
  --local url = URL:new('http://somehost:1234/some/path')
  --url:getHost() -- returns "somehost"
  function url:initialize(protocol, host, port, file)
    if not host then
      if type(protocol) == 'string' then
        self.s = protocol
        self.t = assert(URL.parse(protocol))
      elseif type(protocol) == 'table' then
        self.t = protocol
      else
        error('Invalid URL argument ('..type(protocol)..')')
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

  function url:getProtocol()
    return self.t.scheme
  end

  function url:	getUserInfo()
    if self.t.password then
      return self.t.username..':'..self.t.password
    end
    return self.t.username
  end

  --- Returns this URL hostname.
  -- @return this URL hostname.
  function url:getHost()
    return self.t.host
  end

  --- Returns this URL port.
  -- @return this URL port.
  function url:getPort()
    return self.t.port
  end

  function url:getPath()
    return self.t.path
  end

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

  --- Returns the string value representing this URL.
  -- @return the string value representing this URL.
  function url:toString()
    if not self.s then
      self.s = URL.format(self.t)
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
      return nil, 'Invalid common URL, bad host and port part ("'..scheme..specificPart..'")'
    end
    tUrl.host = host
    if #port > 0 then
      port = tonumber(port)
      if not port then
        return nil, 'Invalid common URL, bad port ("'..scheme..specificPart..'")'
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

  --- Returns the URL corresponding to the specified string.
  -- @tparam string sUrl The string to parse.
  -- @treturn table a table representing the URL or nil.
  function URL.parse(sUrl)
    -- scheme:[//[username[:password]@]host[:port]][/path][?query][#fragment]
    local scheme, specificPart = string.match(sUrl, '^([%w][%w%+%.%-]*):(.*)$')
    if not scheme then
      return nil
    end
    scheme = string.lower(scheme)
    if scheme == 'http' or scheme == 'https' or scheme == 'ws' or scheme == 'wss' then
      return parseHttp(scheme, specificPart)
    end
    return parseCommon(scheme, specificPart)
  end

  --- Returns the URL corresponding to the specified string.
  -- @tparam string sUrl The URL as a string.
  -- @treturn jls.net.URL the URL or nil.
  function URL.fromString(sUrl)
    local tUrl = URL.parse(sUrl)
    if tUrl then
      return URL:new(tUrl)
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
    return buffer:toString()
  end

  local function formatHttp(tUrl)
    local sUrl = formatCommon(tUrl)
    if tUrl.query then
      sUrl = sUrl..'?'..tUrl.query
    end
    if tUrl.fragment then
      sUrl = sUrl..'#'..tUrl.fragment
    end
    return sUrl
  end

  function URL.format(tUrl)
    if tUrl.scheme == 'http' or tUrl.scheme == 'https' then
      return formatHttp(tUrl)
    end
    return formatCommon(tUrl)
  end

  local function encodePercent(value, pattern)
    return (string.gsub(value, pattern, function(c)
      return string.format('%%%02X', string.byte(c))
    end))
  end

  function URL.encodeURIComponent(value, all)
    return encodePercent(value, "[^%a%d%-_%.!~%*'%(%)]")
  end

  function URL.encodeURI(value, all)
    return encodePercent(value, "[^%a%d%-%._~;,/%?:@&=%+%$!%*'%(%)#]")
  end

  function URL.encodePercent(value, all)
    return encodePercent(value, '[^%a%d%-%._~]')
  end

  function URL.decodePercent(value)
    return (string.gsub(value, '%%(%x%x)', function(v)
      local n = tonumber(v, 16)
      if n < 256 then
        return string.char(n)
      end
      return ''
    end))
  end

end)
