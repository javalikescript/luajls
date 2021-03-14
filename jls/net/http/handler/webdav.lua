local logger = require('jls.lang.logger')
local StringBuffer = require('jls.lang.StringBuffer')
local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')
local File = require('jls.io.File')
local Date = require('jls.util.Date')
local setMessageBodyFile = require('jls.net.http.setMessageBodyFile')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST

local function appendFile(buffer, file, baseHref, isChild)
  local isDir = file:isDirectory()
  local href = baseHref
  if isChild then
    href = href..file:getName()
    if isDir then
      href = href..'/'
    end
  end
  --percent encode
  href = string.gsub(href, "[ %c!#$%%&'()*+,:;=?@%[%]]", function(c)
    return string.format('%%%02X', string.byte(c))
  end)
  buffer:append('<D:response>\n<D:href>', href, '</D:href>\n<D:propstat>\n<D:prop>\n')
  if isDir then
    buffer:append('<D:creationdate/>\n<D:displayname/>\n')
    buffer:append('<D:resourcetype><D:collection/></D:resourcetype>\n')
  else
    buffer:append('<D:creationdate/>\n<D:displayname/>\n')
    buffer:append('<D:getcontentlength>', file:length(), '</D:getcontentlength>\n')
    buffer:append('<D:getcontenttype/>\n<D:getetag/>\n')
    buffer:append('<D:getlastmodified>', Date:new(file:lastModified()):toShortISOString(true), '</D:getlastmodified>\n')
    buffer:append('<D:resourcetype/>\n')
  end
  buffer:append('<D:supportedlock/>\n</D:prop>\n<D:status>HTTP/1.1 200 OK</D:status>\n</D:propstat>\n</D:response>\n')
end

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
  if logger:isLoggable(logger.FINE) then
    logger:fine('webdav '..method..' "'..path..'"')
  end
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
    -- "0", "1", or "infinity" optionally suffixed ",noroot"
    local depth = request:getHeader('Depth') or 'infinity'
    -- the request body contains the expected properties, such as
    -- <D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/><D:getcontentlength/></D:prop></D:propfind>
    if logger:isLoggable(logger.FINE) then
      logger:fine('-- webdav depth: '..tostring(depth)..', body --------')
      logger:fine(request:getBody())
    end
    if file:exists() then
      local response = httpExchange:getResponse()
      local baseHref = request:getTargetPath()..'/'
      local buffer = StringBuffer:new()
      buffer:append('<?xml version="1.0" encoding="utf-8" ?>\n<D:multistatus xmlns:D="DAV:">\n')
      if not string.find(depth, ',noroot$') then
        appendFile(buffer, file, baseHref, false)
      end
      if string.find(depth, '^1') and file:isDirectory() then
        local children = file:listFiles()
        for _, child in ipairs(children) do
          appendFile(buffer, child, baseHref, true)
        end
      end
      buffer:append('</D:multistatus>\n')
      response:setStatusCode(207, 'OK')
      --Content-Type: application/xml; charset="utf-8"
      response:setContentType(httpHandlerUtil.CONTENT_TYPES.xml)
      if logger:isLoggable(logger.FINE) then
        logger:fine('-- webdav propfind response --------')
        logger:fine(buffer:toString())
      end
      response:setBody(buffer)
    else
      httpHandlerBase.notFound(httpExchange)
    end
  elseif method == HTTP_CONST.METHOD_OPTIONS then
    local response = httpExchange:getResponse()
    response:setHeader('DAV', 1)
    httpHandlerBase.options(httpExchange, HTTP_CONST.METHOD_GET, HTTP_CONST.METHOD_PUT, HTTP_CONST.METHOD_DELETE, 'PROPFIND')
  elseif method == 'PROPPATCH' or method == 'MKCOL' or method == 'COPY' or method == 'MOVE' or method == 'LOCK' or method == 'UNLOCK' then
    httpHandlerBase.internalServerError(httpExchange)
  else
    httpHandlerBase.methodNotAllowed(httpExchange)
  end
end

return webdav
