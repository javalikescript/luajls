local HttpMessage = require('jls.net.http.HttpMessage')
local HttpServer = require('jls.net.http.HttpServer')

return {
  CONST = HttpMessage.CONST,
  notFoundHandler = HttpServer.notFoundHandler,
  HeaderStreamHandler = require('jls.net.http.HeaderStreamHandler'),
  Message = HttpMessage,
  Request = require('jls.net.http.HttpRequest'),
  Response = require('jls.net.http.HttpResponse'),
  Client = require('jls.net.http.HttpClient'),
  getSecure = require('jls.lang.loader').singleRequirer('jls.net.secure'),
  Server = HttpServer
}