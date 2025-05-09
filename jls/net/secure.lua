local opensslLib = require('openssl')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local TcpSocket = require('jls.net.TcpSocket')
local StreamHandler = require('jls.io.StreamHandler')

--logger = logger:getClass():new(); logger:setLevel('fine')

-- LOPENSSL_VERSION_NUM: 0xMNNFFPPS
-- OPENSSL_VERSION_NUMBER: 0xMNN00PP0L Major miNor Patch
local LOPENSSL_VERSION_NUM, _, OPENSSL_VERSION_NUMBER = opensslLib.version(true)

local BUFFER_SIZE = 8192

local DEFAULT_PROTOCOL = 'TLS'
if LOPENSSL_VERSION_NUM < 0x00706000 then -- 0.7.6
  DEFAULT_PROTOCOL = 'TLSv1_2'
end

local DEFAULT_CIPHERS = 'ECDHE-RSA-AES128-SHA256:AES128-GCM-SHA256:' .. -- TLS 1.2
                        'RC4:HIGH:!MD5:!aNULL:!EDH'                     -- TLS 1.0


local SecureContext = class.create(function(secureContext)

  function secureContext:initialize(options)
    logger:finer('initialize()')
    if type(options) ~= 'table' then
      options = {}
    end
    self.sslContext = opensslLib.ssl.ctx_new(options.protocol or DEFAULT_PROTOCOL, options.ciphers or DEFAULT_CIPHERS)
    --self.sslContext:mode(true, 'release_buffers')
    if options.options then
      -- opensslLib.ssl.no_sslv2 | opensslLib.ssl.no_sslv3 | opensslLib.ssl.no_compression
      self.sslContext:options(options.options)
    end
    if type(options.peerVerifyFn) == 'function' then
      self.sslContext:verify_mode(opensslLib.ssl.peer, options.peerVerifyFn)
    else
      self.sslContext:verify_mode(opensslLib.ssl.none)
    end
    if options.certificate and options.key then
      self:use(options.certificate, options.key, options.password)
    end
    if options.cafile or options.capath then
      self:verifyLocations(options.cafile, options.capath)
    end
    if type(options.peerVerifyFn) == 'function' then
      self.sslContext:set_cert_verify(options.peerVerifyFn)
    else
      self.sslContext:set_cert_verify(function()
        return true
      end)
    end
    if self.sslContext.set_alpn_select_cb then
      if type(options.alpnSelectCb) == 'function' then
        self.sslContext:set_alpn_select_cb(options.alpnSelectCb)
      elseif type(options.alpnSelectProtos) == 'table' then
        self:setAlpnSelectProtos(options.alpnSelectProtos)
      end
      if type(options.alpnProtos) == 'table' then
        self.sslContext:set_alpn_protos(options.alpnProtos)
      end
    end
  end

  function secureContext:verifyLocations(cafile, capath)
    logger:finer('verifyLocations()')
    self.sslContext:verify_locations(cafile, capath)
  end

  function secureContext:use(certificate, key, password)
    logger:finer('use()')
    local File = require('jls.io.File')
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
    logger:finer('ssl(%s, %s, %s)', inMem, outMem, isServer)
    return self.sslContext:ssl(inMem, outMem, isServer)
  end

  function secureContext:setAlpnSelectCb(cb)
    return self.sslContext:set_alpn_select_cb(cb)
  end

  function secureContext:setAlpnSelectProtos(protoList)
    self:setAlpnSelectCb(function(list)
      if logger:isLoggable(logger.FINE) then
        logger:fine('ALPN select: %s', table.concat(list, ','))
      end
      for _, proto in ipairs(protoList) do
        for _, name in ipairs(list) do
          if name == proto then
            logger:fine('ALPN selected: %s', name)
            return name
          end
        end
      end
    end)
  end

  function secureContext:setAlpnProtocols(list)
    return self.sslContext:set_alpn_protos(list)
  end

end, function(SecureContext)

  local DEFAULT_SECURE_CONTEXT = nil

  function SecureContext.getDefault()
    if not DEFAULT_SECURE_CONTEXT then
      DEFAULT_SECURE_CONTEXT = SecureContext:new()
      local protos = os.getenv('JLS_SSL_ALPN_PROTOS')
      if protos and OPENSSL_VERSION_NUMBER >= 0x10002000 then
        logger:fine('Using ALPN protocols: %s', protos)
        local protoList = {}
        for proto in string.gmatch(protos, '[^%s]+') do
          table.insert(protoList, proto)
        end
        DEFAULT_SECURE_CONTEXT:setAlpnProtocols(protoList)
        DEFAULT_SECURE_CONTEXT:setAlpnSelectProtos(protoList)
      end
    end
    return DEFAULT_SECURE_CONTEXT
  end

  function SecureContext.setDefault(context)
    DEFAULT_SECURE_CONTEXT = context ~= nil and class.asInstance(SecureContext, context) or nil
  end

end)


local SecureTcpSocket = class.create(TcpSocket, function(secureTcpSocket, super, SecureTcpSocket)

  function secureTcpSocket:sslInit(isServer, secureContext)
    logger:finer('sslInit()')
    self.inMem = opensslLib.bio.mem(BUFFER_SIZE)
    self.outMem = opensslLib.bio.mem(BUFFER_SIZE)
    if not secureContext then
      secureContext = self:getSecureContext()
    end
    self.ssl = secureContext:ssl(self.inMem, self.outMem, isServer)
    self.sslReading = false
    --[[if self.sslCheckHost == nil then
      logger:fine('sslInit() use default check host')
      self.sslCheckHost = not isServer
    end]]
  end

  function secureTcpSocket:sslGetAlpnSelected()
    if not self.ssl.get_alpn_selected then
      return nil
    end
    return self.ssl:get_alpn_selected()
  end

  function secureTcpSocket:sslShutdown()
    logger:finer('sslShutdown()')
    if self.sslReading then
      self:readStop()
    end
    if self.ssl then
      self.ssl:shutdown()
    end
    self.ssl = nil
    logger:finer('sslShutdown() in and out Mem')
    if self.inMem then
      self.inMem:close()
    end
    if self.outMem then
      self.outMem:close()
    end
    self.inMem = nil
    self.outMem = nil
  end

  function secureTcpSocket:close(callback)
    logger:finer('close()')
    local cb, d = Promise.ensureCallback(callback, true)
    super.close(self, function(err)
      self:sslShutdown()
      cb(err)
    end)
    return d
  end

  function secureTcpSocket:connect(addr, port, callback)
    logger:finer('connect()')
    local cb, d = Promise.ensureCallback(callback)
    super.connect(self, addr, port):next(function()
      return self:onConnected(addr)
    end):next(Promise.callbackToNext(cb))
    return d
  end

  function secureTcpSocket:onConnected(host, startData)
    logger:finer('onConnected()')
    return self:startHandshake(startData):next(function()
      if logger:isLoggable(logger.FINE) then
        logger:fine('connect() handshake completed for %s', self.tcp)
        if logger:isLoggable(logger.FINER) then
          logger:finer('getpeerverification() => %s', self.ssl:getpeerverification())
          logger:finer('peerCert:subject() => %s', self.ssl:peer():subject():oneline())
        end
      end
      if self.sslCheckHost then
        local peerCert = self.ssl:peer()
        if host and not peerCert:check_host(host) then
          logger:fine('connect() => Wrong host')
          return Promise.reject('Wrong host')
        end
      end
      return Promise.resolve()
    end)
  end

  function secureTcpSocket:sslFlush(callback)
    local chunks = {}
    while self.outMem:pending() > 0 do
      table.insert(chunks, self.outMem:read())
    end
    logger:finer('sslFlush() %l chunks', chunks)
    if #chunks > 0 then
      return super.write(self, chunks, callback)
    end
    return Promise.applyCallback(callback)
  end

  function secureTcpSocket:sslDoHandshake(callback)
    logger:finest('sslDoHandshake()')
    local ret, err = self.ssl:handshake()
    logger:finer('sslDoHandshake() ssl:handshake() => %s, %s', ret, err)
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
  function secureTcpSocket:sslRead(stream)
    logger:finer('sslRead()')
    --local data = nil -- we may want to proceed all the available data
    while self.sslReading and (self.inMem:pending() > 0 or self.ssl:pending() > 0) do
      local plainData, op = self.ssl:read()
      if plainData then
        logger:finer('ssl:read() => #%l', plainData)
        logger:finest('ssl:read() => "%s"', plainData)
        --[[if data then
          data = data..plainData
        else
          data = plainData
        end]]
        -- TODO triggering onData is problematic as it may result in stop reading or closing the connection
        -- the stream may be no more relevant
        stream:onData(plainData)
      else
        logger:finer('ssl:read() fail due to "%s"', op)
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

  function secureTcpSocket:startHandshake(startData)
    logger:finer('startHandshake()')
    if not self.ssl then
      self:sslInit(false)
    end
    local promise, resolutionCallback = Promise.withCallback()
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
      logger:fine('onData(%l)', cipherData)
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
        logger:fine('startHandshake() event loop is not running !')
      end
    end
    self:sslDoHandshake(resolutionCallback)
    return promise
  end

  SecureTcpSocket.doNotCheckSecureTcp = os.getenv('JLS_DO_NOT_CHECK_SECURE_TCP')

  function secureTcpSocket:readStart(stream)
    local str = StreamHandler.ensureStreamHandler(stream)
    if logger:isLoggable(logger.FINER) then
      logger:finer('readStart()')
      if logger:isLoggable(logger.FINEST) and self.tcp then
        for _, n in ipairs({'is_readable', 'is_writable', 'is_active', 'is_closing', 'has_ref', 'fileno'}) do
          local fn = self.tcp[n]
          if type(fn) == 'function' then
            logger:finest('  %s: %s', n, fn(self.tcp))
          end
        end
      end
    end
    local sslStream = StreamHandler:new(function(_, cipherData)
      logger:finer('onData(#%l)', cipherData)
      if cipherData then
        if self.inMem:write(cipherData) then
          self:sslRead(str)
        end
      else
        self:close()
        str:onData()
      end
    end, function(_, err)
      logger:fine('readStart() stream on error due to "%s"', err)
      str:onError(err)
    end)
    if logger:isLoggable(logger.FINER) then
      logger:finer('ssl:pending() => %s', self.ssl:pending())
      logger:finer('inMem:pending() => %s', self.inMem:pending())
      logger:finer('outMem:pending() => %s', self.outMem:pending())
    end
    -- prior to start reading we want to be sure that the connection is still ok
    -- otherwise libuv will crash on an assertion
    if SecureTcpSocket.doNotCheckSecureTcp then
      self.sslReading = true
      super.readStart(self, sslStream)
      self:sslRead(str)
    else
      super.write(self, '', function(err)
        if err then
          logger:fine('readStart() - write() => "%s" the connection may have been reset', err)
          str:onError(err)
        else
          self.sslReading = true
          super.readStart(self, sslStream)
          self:sslRead(str)
        end
      end)
    end
  end

  function secureTcpSocket:readStop()
    logger:finer('readStop()')
    self.sslReading = false
    return super.readStop(self)
  end

  function secureTcpSocket:write(data, callback)
    logger:finer('write(#%l)', data)
    logger:finest('write(%s)', data)
    if type(data) ~= 'string' then
      if type(data) ~= 'table' then
        error('invalid data type')
      end
      data = table.concat(data) -- TODO multiple writes
    end
    if not self.ssl then
      return Promise.reject('shutdown')
    end
    local ret, err = self.ssl:write(data)
    -- See https://www.openssl.org/docs/man1.0.2/man3/SSL_write.html
    if ret and ret > 0 then
      -- The write operation was successful, the return value is the number of bytes actually written to the TLS/SSL connection.
      logger:finer('ssl:write() => %d', ret)
    else
      -- The write operation was not successful, because either the connection was closed, an error occurred or action must be taken by the calling process.
      logger:fine('ssl:write() => %s, "%s"', ret, err)
      return Promise.reject(err or 'unknown SSL write error')
    end
    return self:sslFlush(callback)
  end

  function secureTcpSocket:getSecureContext()
    if self.secureContext then
      return self.secureContext
    end
    return SecureContext.getDefault()
  end

  function secureTcpSocket:setSecureContext(context)
    self.secureContext = context ~= nil and class.asInstance(SecureContext, context) or nil
  end

  function secureTcpSocket:onHandshakeStarting(client)
  end

  function secureTcpSocket:onHandshakeCompleted(client)
  end

  function secureTcpSocket:handleAccept(tcp)
    logger:finer('handleAccept() accepting %s', tcp)
    local client = SecureTcpSocket:new(tcp)
    client:sslInit(true, self:getSecureContext())
    self:onHandshakeStarting(client)
    client:startHandshake():next(function()
      logger:finer('handleAccept() handshake completed for %s', tcp)
      self:onHandshakeCompleted(client)
      self:onAccept(client)
    end, function(reason)
      client:close()
      logger:fine('handleAccept() handshake error, %s', reason)
    end)
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
  local time = os.time()
  local serialNumber = options.serialNumber
  if not serialNumber then
    local d = os.date('*t', time)
    serialNumber = math.random(0, 0xffffffff) * 0x10000 + d.year * 12 + d.month
  end
  local cacert = opensslLib.x509.new(serialNumber, req)
  local duration = options.duration or (3600 * 24 * (365 + 31)) -- one year
  cacert:validat(time, time + duration)
  cacert:sign(pkey, cacert) -- self sign
  return cacert, pkey
end

local function readCertificate(data, format)
  local cert = opensslLib.x509.read(data, format)
  -- cert:validat([time]) => validity, notbefore, notafter
  return cert
end

local function readPrivateKey(data, format, passhprase)
  return opensslLib.pkey.read(data, true, format, passhprase)
end


return {
  createPrivateKey = createPrivateKey,
  createCertificate = createCertificate,
  readCertificate = readCertificate,
  readPrivateKey = readPrivateKey,
  Context = SecureContext,
  TcpSocket = SecureTcpSocket
}