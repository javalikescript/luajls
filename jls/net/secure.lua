-- secure module.
-- @module jls.net.secure

local opensslLib = require('openssl')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local net = require('jls.net')
local File = require('jls.io.File')
local streams = require('jls.io.streams')


local BUFFER_SIZE = 8192

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
    self.sslContext = opensslLib.ssl.ctx_new(options.protocol or 'TLSv1_2', options.ciphers or DEFAULT_CIPHERS)
    --self.sslContext:mode(true, 'release_buffers')
    --self.sslContext:options(opensslLib.ssl.no_sslv2 | opensslLib.ssl.no_sslv3 | opensslLib.ssl.no_compression)
    
    self.sslContext:verify_mode(opensslLib.ssl.none)
    --self.sslContext:verify_mode(opensslLib.ssl.peer, function(arg) return true end)
    
    if options.certificate and options.key then
      self:use(options.certificate, options.key, options.password)
    end

    if options.cafile or options.capath then
      self:verifyLocations(options.cafile, options.capath)
    end

    self.sslContext:set_cert_verify(function(arg)
      --do some check
      return true --return false will fail ssh handshake
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


local SecureTcpClient = class.create(net.TcpClient, function(secureTcpClient, super, SecureTcpClient)

  function secureTcpClient:sslInit(isServer, secureContext)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:sslInit()')
    end
    if type(options) ~= 'table' then
      options = {}
    end
    self.inMem = opensslLib.bio.mem(BUFFER_SIZE)
    self.outMem = opensslLib.bio.mem(BUFFER_SIZE)
    if not secureContext then
      secureContext = SecureContext.getDefault()
    end
    self.ssl = secureContext:ssl(self.inMem, self.outMem, isServer)
  end

  function secureTcpClient:sslShutdown()
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:sslShutdown()')
    end
    if self.ssl then
      self.ssl:shutdown()
    end
    self.ssl = nil
    if self.inMem then
      self.inMem:close()
    end
    self.inMem = nil
    if self.outMem then
      self.outMem:close()
    end
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
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:connect()')
    end
    if not self.ssl then
      self:sslInit()
    end
    local cb, d = Promise.ensureCallback(callback)
    local ecb = function(err)
      cb(err or 'Connection failed')
    end
    local secureClient = self
    super.connect(self, addr, port):next(function()
      local dh = secureClient:startHandshake()
      dh:next(function()
        if logger:isLoggable(logger.FINE) then
          logger:fine('secureTcpClient:connect() handshake completed for '..net.socketToString(self.tcp))
        end
        cb()
      end, ecb)
    end, ecb)
    return d
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
      local secureClient = self
      return self:sslFlush(function(err)
        if err then
          callback(err)
        else
          secureClient:sslDoHandshake(callback)
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
    while self.inMem:pending() > 0 do
      local plainData, op = self.ssl:read()
      if plainData then
        if logger:isLoggable(logger.FINER) then
          if logger:isLoggable(logger.FINEST) then
            logger:finest('ssl:read() => "'..tostring(plainData)..'"')
          else
            logger:finer('ssl:read() => #'..tostring(string.len(plainData)))
          end
        end
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
  end

  function secureTcpClient:startHandshake()
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:startHandshake()')
    end
    local promise, resolutionCallback = Promise.createWithCallback()
    local sslStream = streams.StreamHandler:new()
    local secureClient = self
    function sslStream:onData(cipherData)
      if logger:isLoggable(logger.FINE) then
        logger:fine('sslStream:onData('..tostring(cipherData and #cipherData)..')')
      end
      if cipherData then
        if secureClient.inMem:write(cipherData) then
          secureClient:sslDoHandshake(resolutionCallback)
        end
      else
        secureClient:close()
        resolutionCallback('closed')
      end
    end
    function sslStream:onError(err)
      resolutionCallback(err or 'error during handshake')
    end
    promise:finally(function()
      logger:fine('handshake completed')
      secureClient:readStop()
    end)
    super.readStart(self, sslStream)
    secureClient:sslDoHandshake(resolutionCallback)
    return promise
  end

  SecureTcpClient.doNotCheckSecureTcp = os.getenv('JLS_DO_NOT_CHECK_SECURE_TCP')

  function secureTcpClient:readStart(stream)
    if logger:isLoggable(logger.FINER) then
      logger:finer('secureTcpClient:readStart()')
      --[[
      local tcp = self.tcp
      logger:debug('readable: '..tostring(tcp:is_readable()))
      logger:debug('writable: '..tostring(tcp:is_writable()))
      logger:debug('active: '..tostring(tcp:is_active()))
      logger:debug('closing: '..tostring(tcp:is_closing()))
      logger:debug('has_ref: '..tostring(tcp:has_ref()))
      logger:debug('fileno: '..tostring(tcp:fileno()))
      ]]
    end
    local sslStream = streams.StreamHandler:new()
    local secureClient = self
    function sslStream:onData(cipherData)
      if logger:isLoggable(logger.FINER) then
        logger:finer('sslStream:onData(#'..tostring(cipherData and #cipherData)..')')
      end
      if cipherData then
        if secureClient.inMem:write(cipherData) then
          secureClient:sslRead(stream)
        end
      else
        secureClient:close()
        stream:onData()
      end
    end
    function sslStream:onError(err)
      if logger:isLoggable(logger.FINE) then
        logger:fine('secureTcpClient:readStart() stream on error due to "'..tostring(err)..'"')
      end
      --[[
      if err == 'ECONNRESET' then
        local tcp = secureClient.tcp
        if logger:isLoggable(logger.DEBUG) then
          logger:debug('secureTcpClient:readStart() closing due to connection reset')
          logger:debug('readable: '..tostring(tcp:is_readable()))
          logger:debug('writable: '..tostring(tcp:is_writable()))
          logger:debug('active: '..tostring(tcp:is_active()))
          logger:debug('closing: '..tostring(tcp:is_closing()))
          logger:debug('has_ref: '..tostring(tcp:has_ref()))
          logger:debug('fileno: '..tostring(tcp:fileno()))
        end
        super.write(secureClient, '', function(err)
          logger:debug('write() => '..tostring(err))
        end)
        --super.readStart(secureClient, sslStream)
        --secureClient:readStop()
        secureClient:sslShutdown()
        secureClient:close()
        --super.close(secureClient)
        --tcp:unref()
        return
      end
      ]]
      stream:onError(err)
    end
    -- prior to start reading we want to be sure that the connection is still ok
    -- otherwise libuv will crash on an assertion
    if SecureTcpClient.doNotCheckSecureTcp then
      super.readStart(self, sslStream)
    else
      super.write(secureClient, '', function(err)
        if err then
          if logger:isLoggable(logger.FINE) then
            logger:fine('secureTcpClient:readStart() - write() => "'..tostring(err)..'" the connection may have been reset')
          end
          stream:onError(err)
        else
          super.readStart(secureClient, sslStream)
        end
      end)
    end
    if self.inMem:pending() > 0 then
      self:sslRead(stream)
    end
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

local SecureTcpServer = class.create(net.TcpServer, function(secureTcpServer)

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
        logger:finer('secureTcpServer:handleAccept() accepting '..net.socketToString(tcp))
      end
      local client = SecureTcpClient:new(tcp)
      client:sslInit(true, self:getSecureContext())
      local server = self
      client:startHandshake():next(function()
        logger:finer('secureTcpServer:handleAccept() handshake completed for '..net.socketToString(tcp))
        server:onAccept(client)
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

local function createCertificate(options)
  -- see https://en.wikipedia.org/wiki/X.509
  -- https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
  -- Country Name (C), State or Province (S), Locality or City (L), Organization (O), Organizational Unit (OU)
  options = options or {}
  local cadn = opensslLib.x509.name.new({
    {commonName = options.commonName or 'LHA'},
    {C = 'ZZ'},
    {O = 'LHA'}
  })
  local pkey = options.privateKey or createPrivateKey()
  local req = opensslLib.x509.req.new(cadn, pkey)
  local cacert = opensslLib.x509.new(1, req)
  local duration = options.duration or (3600 * 24 * 365)
  local time = os.time()
  cacert:validat(time, time + duration)
  cacert:sign(pkey, cacert) --self sign
  return cacert, pkey
end


return {
  createPrivateKey = createPrivateKey,
  createCertificate = createCertificate,
  Context = SecureContext,
  TcpServer = SecureTcpServer,
  TcpClient = SecureTcpClient
}