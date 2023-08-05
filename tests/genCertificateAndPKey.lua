local File = require('jls.io.File')

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

return function(caCertPem, pKeyPem)
  local cacertFile = File:new(caCertPem or 'tests/cacert.pem')
  local pkeyFile = File:new(pKeyPem or 'tests/pkey.pem')
  if not cacertFile:isFile() or not pkeyFile:isFile() then
    writeCertificateAndPrivateKey(cacertFile, pkeyFile)
  end
  return cacertFile:getPath(), pkeyFile:getPath()
end
