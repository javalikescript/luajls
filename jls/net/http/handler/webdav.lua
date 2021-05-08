-- Deprecated, will be removed

local logger = require('jls.lang.logger')
local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')
local File = require('jls.io.File')
local Date = require('jls.util.Date')
local xml = require("jls.util.xml")
local setMessageBodyFile = require('jls.net.http.setMessageBodyFile')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local URL = require('jls.net.URL')

local function getFileResponse(propfind, file, baseHref, isChild)
  local isDir = file:isDirectory()
  local href = baseHref
  if isChild then
    href = href..file:getName()
    if isDir then
      href = href..'/'
    end
  end
  local getlastmodified = Date:new(file:lastModified()):toRFC822String(true)
  local props
  if isDir then
    props = {
      {name = 'creationdate'},
      {name = 'displayname'},
      {name = 'getlastmodified', getlastmodified},
      {name = 'resourcetype', {name = 'collection'}},
      {name = 'supportedlock'},
    }
  else
    props = {
      {name = 'creationdate'},
      {name = 'displayname'},
      {name = 'getcontentlength', tostring(file:length())},
      {name = 'getcontenttype', httpHandlerUtil.guessContentType(file)},
      {name = 'getetag'}, -- TODO
      {name = 'getlastmodified', getlastmodified},
      {name = 'resourcetype'},
      {name = 'supportedlock'},
    }
  end
  local propstat = {
    name = 'propstat',
    {name = 'prop', table.unpack(props)},
    {name = 'status', 'HTTP/1.1 200 OK'},
  }
  if propfind then
    if propfind.name == 'prop' then
      local names = {}
      for _, prop in ipairs(props) do
        names[prop.name] = true
      end
      for _, prop in ipairs(propfind) do
        if prop.name and not names[prop.name] then
          propstat = {name = 'propstat', {name = 'status', 'HTTP/1.1 404 Property '..prop.name..' Not Found'}}
          break
        end
      end
    elseif propfind.name == 'propname' then
      for _, prop in ipairs(props) do
        prop[1] = nil
      end
    end
  end
  return {
    name = 'response',
    {name = 'href', URL.encodeURI(href)},
    propstat,
  }
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
  if not httpHandlerUtil.isValidSubPath(path) then
    httpHandlerBase.forbidden(httpExchange)
    return
  end
  path = string.gsub(path, '/$', '')
  if logger:isLoggable(logger.FINE) then
    logger:fine('webdav '..method..' "'..path..'"')
  end
  local file = File:new(rootFile, path)
  if method == HTTP_CONST.METHOD_GET then
    if file:isFile() then
      local response = httpExchange:getResponse()
      response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
      response:setCacheControl(false)
      response:setContentType(httpHandlerUtil.guessContentType(file))
      response:setLastModified(file:lastModified())
      response:setContentLength(file:length())
      setMessageBodyFile(response, file)
    else
      httpHandlerBase.notFound(httpExchange)
    end
  elseif method == HTTP_CONST.METHOD_PUT then
    if request:getBodyLength() > 0 then
      file:write(request:getBody()) -- TODO Handle errors
    end
    httpHandlerBase.ok(httpExchange)
  elseif method == HTTP_CONST.METHOD_DELETE then
    if file:isFile() then
      file:delete() -- TODO Check
    elseif file:isDirectory() then
      file:deleteRecursive() -- TODO Check
    end
    httpHandlerBase.ok(httpExchange)
  elseif method == 'PROPFIND' then
    -- "0", "1", or "infinity" optionally suffixed ",noroot"
    local depth = request:getHeader('Depth') or 'infinity'
    if logger:isLoggable(logger.FINE) then
      logger:fine('-- webdav depth: '..tostring(depth)..' --------')
    end
    local propfind
    if request:getBodyLength() > 0 then
      local body = request:getBody()
      local t = xml.decode(body)
      if logger:isLoggable(logger.FINE) then
        logger:fine(xml.encode(t))
      end
      if t.name == 'propfind' then
        propfind = t[1]
      end
    end
    if file:exists() then
      local response = httpExchange:getResponse()
      local baseHref = request:getTargetPath()..'/'
      --local host = request:getHeader(HTTP_CONST.HEADER_HOST)
      --response:setHeader('Content-Location', 'http://'..host..baseHref)
      local multistatus = {name = 'multistatus'}
      if not string.find(depth, ',noroot$') then
        table.insert(multistatus, getFileResponse(propfind, file, baseHref, false))
      end
      if string.find(depth, '^1') and file:isDirectory() then
        local children = file:listFiles()
        for _, child in ipairs(children) do
          table.insert(multistatus, getFileResponse(propfind, child, baseHref, true))
        end
      end
      local body = xml.encode(xml.setNamespace(multistatus, 'DAV:', 'D'))
      response:setStatusCode(207, 'OK')
      --Content-Type: application/xml; charset="utf-8"
      response:setContentType('application/xml')
      if logger:isLoggable(logger.FINE) then
        logger:fine('-- webdav propfind response --------')
        logger:fine(body)
      end
      response:setBody('<?xml version="1.0" encoding="utf-8" ?>'..body)
    else
      httpHandlerBase.notFound(httpExchange)
    end
  elseif method == HTTP_CONST.METHOD_OPTIONS then
    local response = httpExchange:getResponse()
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setHeader('Allow', table.concat({HTTP_CONST.METHOD_OPTIONS, HTTP_CONST.METHOD_GET, HTTP_CONST.METHOD_PUT, HTTP_CONST.METHOD_DELETE, 'PROPFIND'}, ', '))
    response:setHeader('DAV', 1)
    response:setBody('')
  elseif method == 'MKCOL' then
    if file:exists() then
      httpHandlerBase.response(httpExchange, HTTP_CONST.HTTP_CONFLICT, 'Conflict, already exists')
    else
      local parentFile = file:getParentFile()
      if parentFile:isDirectory() then
        if file:mkdir() then
          httpHandlerBase.ok(httpExchange, HTTP_CONST.HTTP_CREATED, 'Created')
        else
          httpHandlerBase.badRequest(httpExchange)
        end
      else
        httpHandlerBase.response(httpExchange, HTTP_CONST.HTTP_CONFLICT, 'Conflict, parent does not exists')
      end
    end
  elseif method == 'COPY' or method == 'MOVE' then
    local destination = request:getHeader('destination')
    local overwrite = request:getHeader('overwrite') ~= 'F'
    if logger:isLoggable(logger.FINE) then
      logger:fine('destination: "'..tostring(destination)..'", overwrite: '..tostring(overwrite))
    end
    if string.find(destination, '://') then
      destination = URL:new(destination):getPath()
    end
    destination = URL.decodePercent(destination)
    if logger:isLoggable(logger.FINE) then
      logger:fine('destination: '..tostring(destination))
    end
    local destPath = context:getArguments(destination)
    if destPath then
      if logger:isLoggable(logger.FINE) then
        logger:fine('destPath: '..tostring(destPath))
      end
      local destFile = File:new(rootFile, destPath)
      if destFile:exists() and not overwrite then
        httpHandlerBase.response(httpExchange, HTTP_CONST.HTTP_PRECONDITION_FAILED, 'Already exists')
      elseif method == 'COPY' then
        if file:isFile() then
          file:copyTo(destFile)
          httpHandlerBase.ok(httpExchange, HTTP_CONST.HTTP_CREATED, 'Copied')
        else
          httpHandlerBase.badRequest(httpExchange)
        end
      elseif method == 'MOVE' then
        file:renameTo(destFile)
        httpHandlerBase.ok(httpExchange, HTTP_CONST.HTTP_CREATED, 'Moved')
      end
    else
      httpHandlerBase.badRequest(httpExchange)
    end
  elseif method == 'PROPPATCH' or method == 'LOCK' or method == 'UNLOCK' then
    httpHandlerBase.badRequest(httpExchange)
  else
    httpHandlerBase.methodNotAllowed(httpExchange)
  end
  if logger:isLoggable(logger.FINE) then
    local response = httpExchange:getResponse()
    logger:fine('webdav => '..tostring(response:getStatusCode()))
  end
end

return webdav
