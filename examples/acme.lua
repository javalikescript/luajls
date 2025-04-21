local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local Acme = require('jls.net.Acme')
local system = require('jls.lang.system')
local tables = require('jls.util.tables')

local options = tables.createArgumentTable(system.getArguments(), {
  helpPath = 'help',
  emptyPath = 'url',
  logPath = 'log-level',
  aliases = {
    h = 'help',
    d = 'domain',
    u = 'url',
    t = 'test',
    w = 'webRoot',
    ak = 'accountKey',
    au = 'accountUrl',
    dk = 'domainKey',
    ll = 'log-level',
  },
  schema = {
    title = 'Order a certificate',
    type = 'object',
    additionalProperties = false,
    required = {'domain'},
    properties = {
      help = {
        title = 'Show the help',
        type = 'boolean',
        default = false
      },
      domain = {
        title = 'The certificate domain',
        type = 'string'
      },
      contactEMail = {
        title = 'The contact email',
        type = 'string',
        pattern = '^.+@.+$'
      },
      url = {
        title = 'The ACME v2 URL',
        type = 'string',
        pattern = '^https?://.+$',
        default = 'https://acme-v02.api.letsencrypt.org/directory'
      },
      stagingUrl = {
        title = 'The ACME v2 staging endpoint',
        type = 'string',
        pattern = '^https?://.+$',
        default = 'https://acme-staging-v02.api.letsencrypt.org/directory'
      },
      test = {
        title = 'Use the staging endpoint',
        type = 'boolean',
        default = false
      },
      webRoot = {
        title = 'The web root directory to use for challenges',
        type = 'string',
        default = '.'
      },
      accountUrl = {
        title = 'The account URL',
        type = 'string',
        pattern = '^https?://.+$'
      },
      accountKey = {
        title = 'The account key file name',
        type = 'string'
      },
      domainKey = {
        title = 'The domain key file name',
        type = 'string'
      },
    }
  }
})

local acme = Acme:new(options.test and options.stagingUrl or options.url, options.webRoot)

if options.accountKey then
  acme:setAccountKeyFile(options.accountKey)
end
if options.domainKey then
  acme:setDomainKeyFile(options.domainKey)
end

Promise.async(function(await)
  if options.accountUrl then
    acme:setAccountUrl(options.accountUrl)
  else
    await(acme:createAccount(options.contactEMail))
  end
  await(acme:orderCertificate(options.domain))
  print(acme.rawCertificate)
end):catch(function(reason)
  print('error: ', reason)
  acme:close()
end)

event:loop()
