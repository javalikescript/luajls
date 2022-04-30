-- secure module.
-- @module jls.net.secure

local opensslLib = require('openssl')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local TcpClient = require('jls.net.TcpClient')
local TcpServer = require('jls.net.TcpServer')
local File = require('jls.io.File')
local StreamHandler = require('jls.io.StreamHandler')


local function getLuaOpensslVersion()
  return string.gsub(opensslLib.version(), '(%d+)', function(n) return string.sub('000'..n, -3); end)
end

local BUFFER_SIZE = 8192

local DEFAULT_PROTOCOL = 'TLS'
if getLuaOpensslVersion() < '000.007.006' then
  DEFAULT_PROTOCOL = 'TLSv1_2'
end

local DEFAULT_CIPHERS = 'ECDHE-RSA-AES128-SHA256:AES128-GCM-SHA256:' .. -- TLS 1.2
                        'RC4:HIGH:!MD5:!aNULL:!EDH'                     -- TLS 1.0


local SecureContext = class.create(function(secureContext)

  function secureContext:initialize(options)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureContext:initialize()')
    end
    if type(options) ~= 'table' then
      options = {}
    end
    self.sslContext = opensslLib.ssl.ctx_new(options.protocol or DEFAULT_PROTOCOL, options.ciphers or DEFAULT_CIPHERS)
    --self.sslContext:mode(true, 'release_buffers')
    --self.sslContext:options(opensslLib.ssl.no_sslv2 | opensslLib.ssl.no_sslv3 | opensslLib.ssl.no_compression)
    
    self.sslContext:verify_mode(opensslLib.ssl.none)
    --[[
      self.sslContext:verify_mode(opensslLib.ssl.peer, function(arg)
        if logger:isLoggable(logger.FINE) then
          logger:fine('sslContext verify()')
          for k,v in pairs(arg) do
            logger:fine('  '..tostring(k)..': '..tostring(v))
          end
        end
        return true
      end)
    ]]
    if options.certificate and options.key then
      self:use(options.certificate, options.key, options.password)
    end

    if options.cafile or options.capath then
      self:verifyLocations(options.cafile, options.capath)
    end

    self.sslContext:set_cert_verify(function(arg)
      --[[if logger:isLoggable(logger.FINE) then
        logger:fine('sslContext cert_verify()')
        for k,v in pairs(arg) do
          logger:fine('  '..tostring(k)..': '..tostring(v))
        end
      end]]
      return true
    end)
  end

  function secureContext:verifyLocations(cafile, capath)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureContext:verifyLocations()')
    end
    self.sslContext:verify_locations(cafile, capath)
  end

  function secureContext:use(certificate, key, password)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureContext:use()')
    end
    local certificateFile = File:new(certificate)
    local keyFile = File:new(key)
    if certificateFile:isFile() and keyFile:isFile() then
      local xcert = opensslLib.x509.read(certificateFile:readAll())
      local xkey = opensslLib.pkey.read(keyFile:readAll(), true, 'pem', password)
      self.sslContext:use(xkey, xcert)
    else
      logger:warn('Certificate or key file not found')
    end
  end

  function secureContext:ssl(inMem, outMem, isServer)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureContext:ssl('..tostring(inMem)..', '..tostring(outMem)..', '..tostring(isServer)..')')
    end
    return self.sslContext:ssl(inMem, outMem, isServer)
  end
end)

local DEFAULT_SECURE_CONTEXT = nil

function SecureContext.getDefault()
  if not DEFAULT_SECURE_CONTEXT then
    -- TODO use env
    DEFAULT_SECURE_CONTEXT = SecureContext:new()
  end
  return DEFAULT_SECURE_CONTEXT
end

function SecureContext.setDefault(context)
  DEFAULT_SECURE_CONTEXT = context
end


local SecureTcpClient = class.create(TcpClient, function(secureTcpClient, super, SecureTcpClient)

  function secureTcpClient:sslInit(isServer, secureContext)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:sslInit()')
    end
    self.inMem = opensslLib.bio.mem(BUFFER_SIZE)
    self.outMem = opensslLib.bio.mem(BUFFER_SIZE)
    if not secureContext then
      secureContext = SecureContext.getDefault()
    end
    self.ssl = secureContext:ssl(self.inMem, self.outMem, isServer)
    self.sslReading = false
    --[[if self.sslCheckHost == nil then
      logger:fine('secureTcpClient:sslInit() use default check host')
      self.sslCheckHost = not isServer
    end]]
  end

  function secureTcpClient:sslShutdown()
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:sslShutdown()')
    end
    if self.ssl then
      self.ssl:shutdown()
    end
    self.ssl = nil
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:sslShutdown() in and out Mem')
    end
    if self.inMem then
      self.inMem:close()
    end
    if self.outMem then
      self.outMem:close()
    end
    self.inMem = nil
    self.outMem = nil
  end

  function secureTcpClient:close(callback)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:close()')
    end
    local cb, d = Promise.ensureCallback(callback)
    super.close(self, function(err)
      self:sslShutdown()
      cb(err)
    end)
    return d
  end

  function secureTcpClient:connect(addr, port, callback)
    logger:finer('secureTcpClient:connect()')
    local cb, d = Promise.ensureCallback(callback)
    super.connect(self, addr, port):next(function()
      return self:onConnected(addr)
    end):next(Promise.callbackToNext(cb))
    return d
  end

  function secureTcpClient:onConnected(host, startData)
    logger:finer('secureTcpClient:onConnected()')
    return self:startHandshake(startData):next(function()
      if logger:isLoggable(logger.FINE) then
        logger:fine('secureTcpClient:connect() handshake completed for '..TcpClient.socketToString(self.tcp))
        if logger:isLoggable(logger.FINER) then
          logger:finer('getpeerverification() => '..tostring(self.ssl:getpeerverification()))
          logger:finer('peerCert:subject() => '..tostring(self.ssl:peer():subject():oneline()))
        end
      end
      if self.sslCheckHost then
        local peerCert = self.ssl:peer()
        if host and not peerCert:check_host(host) then
          logger:fine('secureTcpClient:connect() => Wrong host')
          return Promise.reject('Wrong host')
        end
      end
      return Promise.resolve()
    end)
  end

  function secureTcpClient:sslFlush(callback)
    local chunks = {}
    while self.outMem:pending() > 0 do
      table.insert(chunks, self.outMem:read())
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:sslFlush() #chunks is '..tostring(#chunks))
    end
    if #chunks > 0 then
      return super.write(self, table.concat(chunks), callback)
    end
    local cb, d = Promise.ensureCallback(callback)
    cb()
    return d
  end

  function secureTcpClient:sslDoHandshake(callback)
    logger:finest('secureTcpClient:sslDoHandshake()')
    local ret, err = self.ssl:handshake()
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:sslDoHandshake() ssl:handshake() => '..tostring(ret)..', '..tostring(err))
    end
    if ret == nil then
      self:close()
      callback('closed')
      return
    end
    if self.outMem:pending() > 0 then
      return self:sslFlush(function(err)
        if err then
          callback(err)
        else
          self:sslDoHandshake(callback)
        end
      end)
    else
      logger:finer('ssl:handshake() nothing to flush')
    end
    if ret == false then
      return
    end
    logger:finer('ssl:handshake() ok')
    callback()
  end

  --[[
    All SSL object IO operation methods return nil or false when fail or error.
    When nil returned, it followed by ‘ssl’ or ‘syscall’, means SSL layer or system layer error.
    When false returned, it is followed by number 0, ‘want_read’, ‘want_write’,‘want_x509_lookup’,‘want_connect’,‘want_accept’.
      Number 0 means SSL connection closed, other numbers means you should do some SSL operation.
  ]]
  function secureTcpClient:sslRead(stream)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:sslRead()')
    end
    --local data = nil -- we may want to proceed all the available data
    while self.sslReading and (self.inMem:pending() > 0 or self.ssl:pending() > 0) do
      local plainData, op = self.ssl:read()
      if plainData then
        if logger:isLoggable(logger.FINER) then
          if logger:isLoggable(logger.FINEST) then
            logger:finest('ssl:read() => "'..tostring(plainData)..'"')
          else
            logger:finer('ssl:read() => #'..tostring(string.len(plainData)))
          end
        end
        --[[if data then
          data = data..plainData
        else
          data = plainData
        end]]
        -- TODO triggering onData is problematic as it may result in stop reading or closing the connection
        -- the stream may be no more relevant
        stream:onData(plainData)
      else
        if logger:isLoggable(logger.FINER) then
          logger:finer('ssl:read() fail due to "'..tostring(op)..'"')
        end
        if plainData == nil then
          stream:onError('SSL error "'..tostring(op)..'"')
        elseif op == 0 then
          --self:close()
          stream:onError('SSL connection closed')
        end
        return
      end
    end
    --[[if data then
      stream:onData(data)
    end]]
  end

  function secureTcpClient:startHandshake(startData)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:startHandshake()')
    end
    if not self.ssl then
      self:sslInit()
    end
    local promise, resolutionCallback = Promise.createWithCallback()
    if startData and #startData > 0 and self.inMem:write(startData) then
      local handshakeCompleted = false
      self:sslDoHandshake(function(err)
        handshakeCompleted = true
        resolutionCallback(err)
      end)
      if handshakeCompleted then
        return promise
      end
    end
    super.readStart(self, StreamHandler:new(function(_, cipherData)
      if logger:isLoggable(logger.FINE) then
        logger:fine('sslStream:onData('..tostring(cipherData and #cipherData)..')')
      end
      if cipherData then
        if self.inMem:write(cipherData) then
          self:sslDoHandshake(resolutionCallback)
        end
      else
        --self:close()
        resolutionCallback('closed')
      end
    end, function(_, err)
      resolutionCallback(err or 'error during handshake')
    end))
    promise:finally(function()
      logger:fine('handshake completed')
      self:readStop()
    end)
    if logger:isLoggable(logger.FINE) then
      local luvLib = require('jls.lang.loader').getRequired('luv')
      if luvLib and luvLib.loop_mode() == nil then
        logger:fine('secureTcpClient:startHandshake() event loop is not running !')
      end
    end
    self:sslDoHandshake(resolutionCallback)
    return promise
  end

  SecureTcpClient.doNotCheckSecureTcp = os.getenv('JLS_DO_NOT_CHECK_SECURE_TCP')

  function secureTcpClient:readStart(stream)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:readStart()')
      if logger:isLoggable(logger.FINEST) and self.tcp then
        for _, n in ipairs({'is_readable', 'is_writable', 'is_active', 'is_closing', 'has_ref', 'fileno'}) do
          local fn = self.tcp[n]
          if type(fn) == 'function' then
            logger:finest('  '..n..': '..tostring(fn(self.tcp)))
          end
        end
      end
    end
    local sslStream = StreamHandler:new(function(_, cipherData)
      if logger:isLoggable(logger.FINER) then
        logger:finer('sslStream:onData(#'..tostring(cipherData and #cipherData)..')')
      end
      if cipherData then
        if self.inMem:write(cipherData) then
          self:sslRead(stream)
        end
      else
        self:close()
        stream:onData()
      end
    end, function(_, err)
      if logger:isLoggable(logger.FINE) then
        logger:fine('secureTcpClient:readStart() stream on error due to "'..tostring(err)..'"')
      end
      --[[
      if err == 'ECONNRESET' then
        local tcp = self.tcp
        if logger:isLoggable(logger.DEBUG) then
          logger:debug('secureTcpClient:readStart() closing due to connection reset')
          logger:debug('readable: '..tostring(tcp:is_readable()))
          logger:debug('writable: '..tostring(tcp:is_writable()))
          logger:debug('active: '..tostring(tcp:is_active()))
          logger:debug('closing: '..tostring(tcp:is_closing()))
          logger:debug('has_ref: '..tostring(tcp:has_ref()))
          logger:debug('fileno: '..tostring(tcp:fileno()))
        end
        super.write(self, '', function(err)
          logger:debug('write() => '..tostring(err))
        end)
        --super.readStart(self, sslStream)
        --self:readStop()
        self:sslShutdown()
        self:close()
        --super.close(self)
        --tcp:unref()
        return
      end
      ]]
      stream:onError(err)
    end)
    if logger:isLoggable(logger.FINER) then
      logger:finer('ssl:pending() => '..tostring(self.ssl:pending()))
      logger:finer('inMem:pending() => '..tostring(self.inMem:pending()))
      logger:finer('outMem:pending() => '..tostring(self.outMem:pending()))
      --[[if self.ssl:pending() > 0 then
        local plainData, op = self.ssl:read()
        logger:finer('ssl:read() => '..tostring(plainData and #plainData)..', '..tostring(op))
      end]]
    end
    -- prior to start reading we want to be sure that the connection is still ok
    -- otherwise libuv will crash on an assertion
    if SecureTcpClient.doNotCheckSecureTcp then
      self.sslReading = true
      super.readStart(self, sslStream)
      self:sslRead(stream)
    else
      super.write(self, '', function(err)
        if err then
          if logger:isLoggable(logger.FINE) then
            logger:fine('secureTcpClient:readStart() - write() => "'..tostring(err)..'" the connection may have been reset')
          end
          stream:onError(err)
        else
          self.sslReading = true
          super.readStart(self, sslStream)
          self:sslRead(stream)
        end
      end)
    end
  end

  function secureTcpClient:readStop()
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:readStop()')
    end
    self.sslReading = false
    return super.readStop(self)
  end

  function secureTcpClient:write(data, callback)
    if logger:isLoggable(logger.FINER) then
      if logger:isLoggable(logger.FINEST) then
        logger:finest('secureTcpClient:write('..tostring(data)..')')
      else
        logger:finer('secureTcpClient:write(#'..tostring(data and #data)..')')
      end
    end
    local ret, err = self.ssl:write(data)
    if logger:isLoggable(logger.FINER) then
      logger:finer('ssl:write() => '..tostring(ret)..', '..tostring(err))
    end
    return self:sslFlush(callback)
  end
end)

local SecureTcpServer = class.create(TcpServer, function(secureTcpServer)

  function secureTcpServer:getSecureContext()
    if not self.secureContext then
      self.secureContext = SecureContext:new()
      --self.secureContext:use(certificate, key, password)
    end
    return self.secureContext
  end

  function secureTcpServer:setSecureContext(context)
    self.secureContext = context
  end

  function secureTcpServer:handleAccept()
    local tcp = self:tcpAccept()
    if tcp then
      if logger:isLoggable(logger.FINER) then
        logger:finer('secureTcpServer:handleAccept() accepting '..TcpClient.socketToString(tcp))
      end
      local client = SecureTcpClient:new(tcp)
      client:sslInit(true, self:getSecureContext())
      client:startHandshake():next(function()
        logger:finer('secureTcpServer:handleAccept() handshake completed for '..TcpClient.socketToString(tcp))
        self:onAccept(client)
      end, function(err)
        client:close()
        logger:fine('secureTcpServer:handleAccept() handshake error')
      end)
    else
      logger:fine('secureTcpServer:handleAccept() error')
    end
  end
end)

local function createPrivateKey()
  return opensslLib.pkey.new()
end

local function addName(names, options, name, key)
  if options[name] then
    table.insert(names, {[key or name] = options[name]})
  end
  return names
end

local function createCertificate(options)
  -- see https://en.wikipedia.org/wiki/X.509
  -- https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
  -- Country Name (C), State or Province (S), Locality or City (L), Organization (O), Organizational Unit (OU)
  options = options or {}
  local names = {
    {CN = options.commonName or 'JLS'},
    {C = options.countryName or 'ZZ'},
    {O = options.organizationName or 'JLS'}
  }
  addName(names, options, 'localityName', 'L')
  addName(names, options, 'stateOrProvinceName', 'ST')
  addName(names, options, 'organizationalUnitName', 'OU')
  local cadn = opensslLib.x509.name.new(names)
  local pkey = options.privateKey or createPrivateKey()
  local req = opensslLib.x509.req.new(cadn, pkey)
  local cacert = opensslLib.x509.new(1, req)
  local duration = options.duration or (3600 * 24 * (365 + 31)) -- one year
  local time = os.time()
  cacert:validat(time, time + duration)
  cacert:sign(pkey, cacert) -- self sign
  return cacert, pkey
end

local function readCertificate(data)
  local cert = opensslLib.x509.read(data)
  -- cert:validat([time]) => validity, notbefore, notafter
  return cert
end


return {
  createPrivateKey = createPrivateKey,
  createCertificate = createCertificate,
  readCertificate = readCertificate,
  Context = SecureContext,
  TcpServer = SecureTcpServer,
  TcpClient = SecureTcpClient
}