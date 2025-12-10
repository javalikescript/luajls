local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local Date = require('jls.util.Date')

local opensslLib = require('openssl')

local function createPrivateKeyAndCertificates()
  -- openssl x509 -in tests/cacert.pem -text
  local pkey = opensslLib.pkey.new()
  local cadn = opensslLib.x509.name.new({{commonName='localhost'}, {C='ZZ'}, {O='JLS'}})
  local req = opensslLib.x509.req.new(cadn, pkey)
  local ext = opensslLib.x509.extension.new_extension({object='subjectAltName', value='IP:127.0.0.1'})
  req:extensions({ext})
  local cacert = opensslLib.x509.new(1, req)
  cacert:validat(os.time(), os.time() + 3600*24*365)
  cacert:sign(pkey, cacert) --self sign
  -- invalid
  local reqi = opensslLib.x509.req.new(cadn, pkey)
  reqi:extensions({ext})
  local cacerti = opensslLib.x509.new(1, reqi)
  cacerti:validat(os.time() - 3600*24*365, os.time() - 3600*24)
  cacerti:sign(pkey, cacerti)
  -- unkown host
  local cadnu = opensslLib.x509.name.new({{commonName='NA'}, {C='ZZ'}, {O='JLS'}})
  local requ = opensslLib.x509.req.new(cadnu, pkey)
  local cacertu = opensslLib.x509.new(1, requ)
  cacertu:validat(os.time(), os.time() + 3600*24*365)
  cacertu:sign(pkey, cacertu) --self sign
  return pkey, cacert, cacerti, cacertu
end

local function writePrivateKeyAndCertificates(...)
  local files = {...}
  local items = {createPrivateKeyAndCertificates()}
  -- pkey:export('pem', true, 'secret') -- format='pem' raw=true,  passphrase='secret'
  for i, item in ipairs(items) do
    local data = item:export('pem')
    local file = files[i]
    if file then
      file:write(data)
    end
  end
end

local function readCertificate(certFile)
  return opensslLib.x509.read(certFile:readAll())
end

return function(caCertPem, pKeyPem)
  local cacertFile = File:new(caCertPem or 'tests/cacert.pem')
  local pkeyFile = File:new(pKeyPem or 'tests/pkey.pem')
  local cacertInvalidFile = File:new(caCertPem or 'tests/cacert-invalid.pem')
  local cacertUnknownFile = File:new(caCertPem or 'tests/cacert-unknown.pem')
  if not (cacertFile:isFile() and pkeyFile:isFile() and cacertInvalidFile:isFile() and cacertUnknownFile:isFile()) then
    logger:info('creating private key and certificates')
    writePrivateKeyAndCertificates(pkeyFile, cacertFile, cacertInvalidFile, cacertUnknownFile)
  else
    local cert = readCertificate(cacertFile)
    local isValid, notbefore, notafter = cert:validat()
    local notafterDate = Date:new(notafter:get() * 1000)
    local notafterText = notafterDate:toISOString(true)
    logger:info('certificate valid until %s', notafterText)
    if not isValid then
      logger:warn('re-creating invalid certificate')
      writePrivateKeyAndCertificates(pkeyFile, cacertFile, cacertInvalidFile, cacertUnknownFile)
    end
  end
  return cacertFile:getPath(), pkeyFile:getPath(), cacertInvalidFile:getPath(), cacertUnknownFile:getPath()
end
