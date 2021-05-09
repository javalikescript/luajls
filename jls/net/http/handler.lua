local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')

-- Deprecated, will be removed

return {
  -- utils
  CONTENT_TYPES = httpHandlerUtil.CONTENT_TYPES,
  REST_NOT_FOUND = httpHandlerUtil.REST_NOT_FOUND,
  REST_ANY = httpHandlerUtil.REST_ANY,
  REST_METHOD = httpHandlerUtil.REST_METHOD,
  replyJson = httpHandlerUtil.replyJson,
  chain = httpHandlerUtil.chain,
  shiftPath = httpHandlerUtil.shiftPath,
  restPart = httpHandlerUtil.restPart,
  -- basics
  methodNotAllowed = httpHandlerBase.methodNotAllowed,
  internalServerError = httpHandlerBase.internalServerError,
  notFound = httpHandlerBase.notFound,
  badRequest = httpHandlerBase.badRequest,
  forbidden = httpHandlerBase.forbidden,
  ok = httpHandlerBase.ok,
  methodAllowed = httpHandlerBase.methodAllowed,
  -- handlers
  basicAuthentication = require('jls.net.http.handler.basicAuthentication'),
  rest = require('jls.net.http.handler.rest'),
  file = require('jls.net.http.handler.file'),
  files = require('jls.net.http.handler.files'),
  webdav = require('jls.net.http.handler.webdav'),
  zip = require('jls.net.http.handler.zip'),
  redirect = require('jls.net.http.handler.redirect'),
  table = require('jls.net.http.handler.table'),
}
