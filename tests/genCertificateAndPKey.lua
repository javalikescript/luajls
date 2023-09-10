local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local Date = require('jls.util.Date')

local opensslLib = require('openssl')

local function createCertificateAndPrivateKey()
  local cadn = opensslLib.x509.name.new({{commonName='CA'}, {C='CN'}})
  local pkey = opensslLib.pkey.new()
  local req = opensslLib.x509.req.new(cadn, pkey)
  local cacert = opensslLib.x509.new(1, req)
  cacert:validat(os.time(), os.time() + 3600*24*365)
  cacert:sign(pkey, cacert) --self sign
  return cacert, pkey
end

local function writeCertificateAndPrivateKey(cacertFile, pkeyFile)
  local cacert, pkey = createCertificateAndPrivateKey()
  local cacertPem  = cacert:export('pem')
  -- pkey:export('pem', true, 'secret') -- format='pem' raw=true,  passphrase='secret'
  local pkeyPem  = pkey:export('pem')
  cacertFile:write(cacertPem)
  pkeyFile:write(pkeyPem)
end

local function readCertificate(certFile)
  return opensslLib.x509.read(certFile:readAll())
end

return function(caCertPem, pKeyPem)
  local cacertFile = File:new(caCertPem or 'tests/cacert.pem')
  local pkeyFile = File:new(pKeyPem or 'tests/pkey.pem')
  if not cacertFile:isFile() or not pkeyFile:isFile() then
    logger:info('creating certificate')
    writeCertificateAndPrivateKey(cacertFile, pkeyFile)
  else
    local cert = readCertificate(cacertFile)
    local isValid, notbefore, notafter = cert:validat()
    local notafterDate = Date:new(notafter:get() * 1000)
    local notafterText = notafterDate:toISOString(true)
    logger:info('certificate valid until %s', notafterText)
    if not isValid then
      logger:warn('re-creating invalid certificate')
      writeCertificateAndPrivateKey(cacertFile, pkeyFile)
    end
  end
  return cacertFile:getPath(), pkeyFile:getPath()
end
