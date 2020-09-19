--- The URL class module.
-- @module jls.net.URL
-- @pragma nostrip

--local logger = require("jls.lang.logger")

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
        self.t = URL.parse(protocol)
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

  -- //<user>:<password>@<host>:<port>/<url-path>
  local function parseCommon(scheme, specificPart)
    local t = {
      scheme = scheme,
      port = PORT_BY_SCHEME[scheme]
    }
    local authority, path = string.match(specificPart, '^//([^/]+)(/?.*)$') -- we are lazy on the slash
    if not authority then
      error('Invalid common URL ("'..scheme..specificPart..'")')
    end
    t.path = path
    local authentication, hostport = string.match(authority, '^([^@]+)@(.*)$')
    if authentication then
      local user, password = string.match(authentication, '^([^:]+):?(.*)$')
      if not user then
        error('Invalid common URL, bad authentication part ("'..scheme..specificPart..'")')
      end
      t.user = user
      if password and #password > 0 then
        t.password = password
      end
    else
      hostport = authority
    end
    local host, port
    if string.find(hostport, '^%[') then -- IPv6 addresses are enclosed in brackets
      host, port = string.match(hostport, '^%[([^%]]+)%]:?(%d*)$')
    else
      host, port = string.match(hostport, '^([^:]+):?(%d*)$')
    end
    if not host then
      error('Invalid common URL, bad host and port part ("'..scheme..specificPart..'")') -- TODO refactor
    end
    t.host = host
    if #port > 0 then
      port = tonumber(port)
      if not port then
        error('Invalid common URL, bad port ("'..scheme..specificPart..'")') -- TODO refactor
      end
      t.port = port
    end
    return t
  end

  local function parseHttp(scheme, specificPart)
    local t = parseCommon(scheme, specificPart)
    if not t.path then
      return t
    end
    local path, fragment = string.match(t.path, '^([^#]*)#(.*)$')
    if path then
      t.fragment = fragment
    else
      path = t.path
    end
    local qpath, query = string.match(path, '^([^%?]*)%?(.*)$')
    if qpath then
      path = qpath
      t.query = query
    end
    t.path = path
    return t
  end

  --- Returns the URL corresponding to the specified string.
  -- @tparam string url The string to parse.
  -- @treturn jls.net.URL the URL corresponding to the string.
  function URL.parse(url)
    -- scheme:[//[user[:password]@]host[:port]][/path][?query][#fragment]
    local scheme, specificPart = string.match(url, '^([%w][%w%+%.%-]*):(.*)$')
    scheme = string.lower(scheme)
    if scheme == 'http' or scheme == 'https' or scheme == 'ws' or scheme == 'wss' then
      return parseHttp(scheme, specificPart)
    end
    return parseCommon(scheme, specificPart)
  end

  local function formatCommon(t)
    local url = t.scheme..'://'
    if t.user then
      url = url..t.user
      if t.password then
        url = url..':'..t.password
      end
      url = url..'@'
    end
    if string.find(t.host, ':') then -- IPv6 addresses are enclosed in brackets
      url = url..'['..t.host..']'
    else
      url = url..t.host
    end
    if t.port and t.port ~= PORT_BY_SCHEME[t.scheme] then
      url = url..':'..t.port
    end
    if t.path then
      url = url..'/'..t.path
    end
    return url
  end

  local function formatHttp(t)
    local url = formatCommon(t)
    if t.query then
      url = url..'?'..t.query
    end
    if t.fragment then
      url = url..'#'..t.fragment
    end
    return url
  end

  function URL.format(t)
    if t.scheme == 'http' or t.scheme == 'https' then
      return formatHttp(t)
    end
    return formatCommon(t)
  end

  function URL.encodePercent(value)
    local r = ''
    for i = 1, #value do
      local b = string.byte(value, i)
      if b < 48 or ((b > 57) and (b < 65)) or ((b > 90) and (b < 97)) or b > 122 then
        r = r..string.format("%%%02X", b)
      end
      r = r..string.char(b)
    end
    return r
  end

end)
