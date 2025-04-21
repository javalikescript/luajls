local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local Url = require('jls.net.Url')
local HttpClient = require('jls.net.http.HttpClient')
local strings = require('jls.util.strings')
local Date = require('jls.util.Date')
local List = require('jls.util.List')
local Codec = require('jls.util.Codec')
local json = require('jls.util.json')
local Base64 = Codec.getCodec('base64')

local opensslLib = require('openssl')

local base64Url = Base64:new('safe', false)

local function getJson(response)
  local status, reason = response:getStatusCode()
  local contentType = response:getHeader('content-type')
  logger:finer('response status %d "%s" content type %s', status, reason, contentType)
  if not strings.equalsIgnoreCase(contentType, 'application/json') then
    return response:text():next(function(text)
      logger:fine('response body "%s"', text)
      return Promise.reject('Invalid or missing content type')
    end)
  end
  if logger:isLoggable(logger.FINER) then
    return response:json():next(function(o)
      logger:finer('response body JSON %T', o)
      return o
    end)
  end
  return response:json()
end

local function getChallenge(challenges, t)
  for _, challenge in ipairs(challenges) do
    if challenge.type == t then
      return challenge
    end
  end
end

local function readPrivateKey(file, password, format)
  local keyFile = class.asInstance(File, file)
  return opensslLib.pkey.read(keyFile:readAll(), true, format or 'pem', password)
end


-- see https://datatracker.ietf.org/doc/html/rfc8555

return require('jls.lang.class').create(function(acme)

  function acme:initialize(url, dir)
    self.url = url
    self.wwwDir = class.asInstance(File, dir or '.')
  end

  function acme:setAccountKeyFile(file, passphrase, format)
    local keyFile = class.asInstance(File, file)
    if keyFile:exists() then
      self.accountKey = readPrivateKey(keyFile, passphrase, format)
    else
      keyFile:write(self:getAccountKey():export('pem', false, passphrase))
    end
  end

  function acme:getAccountKey()
    if not self.accountKey then
      self.accountKey = opensslLib.pkey.new('rsa', 4096)
    end
    return self.accountKey
  end

  function acme:setAccountUrl(accountUrl)
    self.accountUrl = accountUrl
  end

  function acme:setDomainKeyFile(file, passphrase, format)
    local keyFile = class.asInstance(File, file)
    if keyFile:exists() then
      self.domainKey = readPrivateKey(keyFile, passphrase, format)
    else
      keyFile:write(self:getDomainKey():export('pem', false, passphrase))
    end
  end

  function acme:getDomainKey()
    if not self.domainKey then
      self.domainKey = opensslLib.pkey.new('rsa', 4096)
    end
    return self.domainKey
  end

  function acme:getJwk()
    if not self.jwk then
      local rsa = self:getAccountKey():get_public():parse().rsa:parse()
      self.jwk = {kty = 'RSA', e = base64Url:encode(rsa.e:totext()), n = base64Url:encode(rsa.n:totext())}
    end
    return self.jwk
  end

  function acme:getJwkThumbPrint()
    if not self.jwkThumbPrint then
      local md = opensslLib.digest.get('sha256')
      self.jwkThumbPrint = base64Url:encode(md:digest (json.stringify(self:getJwk())))
    end
    return self.jwkThumbPrint
  end

  function acme:getClient(url)
    if self.client then
      local v = Url:new(self.client:getUrl())
      if url:getProtocol() == v:getProtocol() and url:getHost() == v:getHost() and url:getPort() == v:getPort() then
        return self.client
      end
    end
    self.client = HttpClient:new(url)
    return self.client
  end

  function acme:fetch(resource, options)
    local u = class.asInstance(Url, resource)
    logger:finer('fetch(%s, %T)', resource, options)
    return self:getClient(u):fetch(u:getFile(), options)
  end

  function acme:fetchDirectory()
    if self.directory then
      return Promise.resolve(self.directory)
    end
    return self:fetch(self.url):next(getJson):next(function(directory)
      self.directory = directory
      return directory
    end)
  end

  function acme:request(resource, content)
    return self:fetchDirectory():next(function(directory)
      return self:fetch(directory.newNonce, {method = 'HEAD'})
    end):next(function(response)
      local nonce = response:getHeader('replay-nonce')
      logger:finer('nonce is "%s"', nonce)
      local header = {alg = 'RS256', nonce = nonce, url = resource}
      if self.accountUrl then
        header.kid = self.accountUrl
      else
        header.jwk = self:getJwk()
      end
      local jwsProtected = base64Url:encode(json.stringify(header))
      local jwsPayload = base64Url:encode(content or '')
      local md = opensslLib.digest.get('sha256')
      local digestCtx = opensslLib.digest.signInit(md, self:getAccountKey())
      digestCtx:signUpdate(jwsProtected)
      digestCtx:signUpdate('.')
      digestCtx:signUpdate(jwsPayload)
      local jwsSignature = base64Url:encode(digestCtx:signFinal())
      local jws = {protected = jwsProtected, payload = jwsPayload, signature = jwsSignature}
      return self:fetch(resource, {method = 'POST', body = json.stringify(jws), headers = {['Content-Type'] = 'application/jose+json'}})
    end)
  end

  function acme:createAccount(contactEMails)
    if type(contactEMails) == 'string' then
      contactEMails = {contactEMails}
    end
    return self:fetchDirectory():next(function(directory)
      local request = {termsOfServiceAgreed = true}
      if contactEMails then
        request.contact = {}
        for _, contactEMail in ipairs(contactEMails) do
          table.insert(request.contact, 'mailto:'..contactEMail)
        end
      end
      return self:request(directory.newAccount, json.stringify(request))
    end):next(function(response)
      self.accountUrl = response:getHeader('location')
      logger:finer('account URL is "%s"', self.accountUrl)
      return getJson(response)
    end)
  end

  function acme:setupChallenges()
    if not self.wwwDir:isDirectory() then
      error('not a directory, '..self.wwwDir:getPath())
    end
    self.acmeDir = File:new(self.wwwDir, '.well-known/acme-challenge')
    if not self.acmeDir:isDirectory() then
      if not self.acmeDir:mkdirs() then
        error('cannot create directory, '..self.acmeDir:getPath())
      end
    end
    logger:info('directory %s created', self.acmeDir)
  end

  function acme:cleanupChallenges()
  end

  function acme:setupChallenge(challenge)
    local token = File:new(self.acmeDir, challenge.token)
    local keyAuth = challenge.token..'.'..self:getJwkThumbPrint()
    assert(token:write(keyAuth))
  end

  function acme:cleanupChallenge(challenge)
    local token = File:new(self.acmeDir, challenge.token)
    token:delete()
  end

  function acme:waitOrder(orderUrl, target)
    return Promise:new(function(resolve, reject)
      local n, duration, timeout = 0, 0, 180
      local function checkStatus()
        self:request(orderUrl):next(getJson):next(function(o)
          logger:fine('order status is %s (%d %d/%ds)', o.status, n, duration, timeout)
          if o.status == target then
            resolve(o)
          elseif o.status ~= 'pending' and o.status ~= 'processing' then
            reject(o.status)
          elseif duration > timeout then
            reject('timeout')
          else
            n = n + 1
            local delay = n * 5
            duration = duration + delay
            event:setTimeout(checkStatus, delay * 1000)
          end
        end, reject)
      end
      logger:fine('waiting for order to be '..target)
      checkStatus()
    end)
  end

  function acme:orderCertificate(domains)
    if type(domains) == 'string' then
      domains = {domains}
    end
    self:setupChallenges()
    local orderUrl, finalizeUrl
    return self:fetchDirectory():next(function(directory)
      local identifiers = {}
      for _, domain in ipairs(domains) do
        table.insert(identifiers, {type = 'dns', value = domain})
      end
      local request = {identifiers = identifiers}
      return self:request(directory.newOrder, json.stringify(request))
    end):next(function(response)
      orderUrl = response:getHeader('location')
      return getJson(response)
    end):next(function(order)
      finalizeUrl = order.finalize
      return Promise.all(List.map(order.authorizations, function(authorization)
        return self:request(authorization):next(getJson)
      end))
    end):next(function(auths)
      return List.map(auths, function(auth)
        return getChallenge(auth.challenges, 'http-01')
      end)
    end):next(function(challenges)
      return Promise.all(List.map(challenges, function(challenge, i)
        self:setupChallenge(challenge)
        return self:request(challenge.url, '{}'):next(getJson)
      end)):next(function()
        return self:waitOrder(orderUrl, 'ready')
      end):finally(function()
        logger:fine('cleanup challenges')
        for _, challenge in ipairs(challenges) do
          self:cleanupChallenge(challenge)
        end
        self:cleanupChallenges()
      end)
    end):next(function()
      local names = {{CN = domains[1]}}
      local cadn = opensslLib.x509.name.new(names)
      local req = opensslLib.x509.req.new(cadn, self:getDomainKey())
      local request = {csr = base64Url:encode(req:export('der'))}
      return self:request(finalizeUrl, json.stringify(request)):next(getJson)
    end):next(function()
      return self:waitOrder(orderUrl, 'valid')
    end):next(function(o)
      return self:request(o.certificate)
    end):next(function(response)
      return response:text()
    end):next(function(rawCertificate)
      self.rawCertificate = rawCertificate
      return opensslLib.x509.read(rawCertificate)
    end)
  end

  function acme:close()
    if self.client then
      self.client:close()
    end
  end

end)
