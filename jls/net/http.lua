local HttpMessage = require('jls.net.http.HttpMessage')
local HttpServer = require('jls.net.http.HttpServer')
local HttpContext = require('jls.net.http.HttpContext')

return {
  CONST = HttpMessage.CONST,
  notFoundHandler = HttpContext.notFoundHandler,
  HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler'),
  Message = HttpMessage,
  Request = require('jls.net.http.HttpRequest'),
  Response = require('jls.net.http.HttpResponse'),
  Client = require('jls.net.http.HttpClient'),
  Context = HttpContext,
  ContextHolder = require('jls.net.http.HttpContextHolder'),
  getSecure = require('jls.lang.loader').singleRequirer('jls.net.secure'),
  Server = HttpServer
}