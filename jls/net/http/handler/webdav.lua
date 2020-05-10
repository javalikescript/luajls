--local logger = require('jls.lang.logger')
local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')
local File = require('jls.io.File')
local setMessageBodyFile = require('jls.net.http.setMessageBodyFile')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

local function webdav(httpExchange)
  local request = httpExchange:getRequest()
  local context = httpExchange:getContext()
  local rootFile = context:getAttribute('rootFile') or File:new('.')
  if not rootFile then
    rootFile = File:new(context:getAttribute('rootPath') or '.')
    context:setAttribute('rootFile', rootFile)
  end
  local method = string.upper(request:getMethod())
  local path = httpExchange:getRequestArguments()
  path = string.gsub(path, '/$', '')
  local file = File:new(rootFile, path)
  if method == HTTP_CONST.METHOD_GET then
    if file:isFile() then
      local response = httpExchange:getResponse()
      response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
      response:setContentType(httpHandlerUtil.CONTENT_TYPES.bin)
      response:setCacheControl(false)
      response:setContentLength(file:length())
      setMessageBodyFile(response, file)
    else
      httpHandlerBase.notFound(httpExchange)
    end
  elseif method == HTTP_CONST.METHOD_PUT then
    if request:hasBody() then
      file:write(request:getBody()) -- TODO Handle errors
    end
    httpHandlerBase.ok(httpExchange)
  elseif method == HTTP_CONST.METHOD_DELETE then
    if file:isFile() then
      file:delete() -- TODO Check
      httpHandlerBase.ok(httpExchange)
    end
  elseif method == 'PROPFIND' then
    if file:isDirectory() then
      -- "0", "1", or "infinity"
      local uriPath = request:getTargetPath()
      uriPath = uriPath..'/'
      local depth = request:getHeader('Depth') or 'infinity'
      local filenames = file:list()
      local body = '<?xml version="1.0" encoding="utf-8" ?>\n<multistatus xmlns="DAV:">\n'
      for i, filename in ipairs(filenames) do
        local f = File:new(file, filename)
        if f:isDirectory() then
          filename = filename..'/'
        end
        body = body..'<response>\n<href>'..uriPath..filename..'</href>\n'..
            '<propstat>\n<prop>\n<creationdate/>\n<displayname/>\n<getcontentlength/>\n<getcontenttype/>\n<getetag/>\n'..
            '<getlastmodified/>\n<resourcetype/>\n<supportedlock/>\n</prop>\n'..
            '<status>HTTP/1.1 200 OK</status>\n</propstat>\n</response>\n'
      end
      body = body..'</multistatus>\n'
      httpHandlerBase.ok(httpExchange, body, httpHandlerUtil.CONTENT_TYPES.xml)
    else
      httpHandlerBase.notFound(httpExchange)
    end
  elseif method == 'PROPPATCH' or method == 'MKCOL' or method == 'COPY' or method == 'MOVE' or method == 'LOCK' or method == 'UNLOCK' then
    httpHandlerBase.internalServerError(httpExchange)
  else
    httpHandlerBase.methodNotAllowed(httpExchange)
  end
end

return webdav
