--- Provide an HTTP handler for the WebDAV protocol.
-- Based on the file handler, see @{FileHttpHandler}.
-- @module jls.net.http.handler.WebDavHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger'):get(...)
local Date = require('jls.util.Date')
local xml = require("jls.util.xml")
local Url = require('jls.net.Url')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')

local function getFileResponse(propfind, md, baseHref, isChild)
  local href = baseHref
  if isChild then
    href = href..md.name
    if md.isDir then
      href = href..'/'
    end
  end
  local getlastmodified = Date:new(md.time):toRFC822String(true)
  local props
  if md.isDir then
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
      {name = 'getcontentlength', tostring(md.size)},
      {name = 'getcontenttype', FileHttpHandler.guessContentType(md.name)},
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
    {name = 'href', Url.encodeURI(href)},
    propstat,
  }
end

--- A WebDavHttpHandler class.
-- @type WebDavHttpHandler
return require('jls.lang.class').create(FileHttpHandler, function(webDavHttpHandler, super)

  function webDavHttpHandler:initialize(rootFile, permissions)
    super.initialize(self, rootFile, permissions, '')
    self.allowList = false
  end

  function webDavHttpHandler:handlePropFind(exchange, file, propfind)
    local request = exchange:getRequest()
    -- "0", "1", or "infinity" optionally suffixed ",noroot"
    local depth = request:getHeader('depth') or 'infinity'
    logger:fine('webdav depth: %s', depth)
    local response = exchange:getResponse()
    local baseHref = string.gsub(request:getTargetPath()..'/', '//+', '/')
    --local host = request:getHeader(HTTP_CONST.HEADER_HOST)
    --response:setHeader('Content-Location', 'http://'..host..baseHref)
    local multistatus = {name = 'multistatus'}
    if not string.find(depth, ',noroot$') then
      table.insert(multistatus, getFileResponse(propfind, FileHttpHandler.toFileMetadata(file), baseHref, false))
    end
    if string.find(depth, '^1') and file:isDirectory() then
      local list = self:listFileMetadata(exchange, file)
      for _, md in ipairs(list) do
        table.insert(multistatus, getFileResponse(propfind, md, baseHref, true))
      end
    end
    local body = xml.encode(xml.setNamespace(multistatus, 'DAV:', 'D'))
    response:setStatusCode(207, 'OK')
    --Content-Type: application/xml; charset="utf-8"
    response:setContentType('application/xml')
    logger:fine('propfind response: "%s"', body)
    response:setBody('<?xml version="1.0" encoding="utf-8" ?>'..body)
  end

  function webDavHttpHandler:handleFile(exchange, file, isDirectoryPath)
    local method = exchange:getRequestMethod()
    local request = exchange:getRequest()
    if method == 'PROPFIND' then
      if file:exists() then
        if request:getBodyLength() > 0 then
          request:bufferBody()
          return request:consume():next(function()
            local propfind
            local body = request:getBody()
            local t = xml.decode(body)
            if logger:isLoggable(logger.FINE) then
              logger:fine('request: "%s"', xml.encode(t))
            end
            if t.name == 'propfind' then
              propfind = t[1]
            end
            self:handlePropFind(exchange, file, propfind)
          end)
        else
          self:handlePropFind(exchange, file)
        end
      else
        HttpExchange.notFound(exchange)
      end
    elseif method == HTTP_CONST.METHOD_OPTIONS then
      local response = exchange:getResponse()
      response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
      response:setHeader('Allow', table.concat({HTTP_CONST.METHOD_OPTIONS, HTTP_CONST.METHOD_GET, HTTP_CONST.METHOD_PUT, HTTP_CONST.METHOD_DELETE, 'PROPFIND'}, ', '))
      response:setHeader('DAV', 1)
      response:setBody('')
    elseif method == 'MKCOL' then
      if file:exists() then
        HttpExchange.response(exchange, HTTP_CONST.HTTP_CONFLICT, 'Conflict, already exists')
      else
        if file:mkdir() then
          HttpExchange.response(exchange, HTTP_CONST.HTTP_CREATED, 'Created')
        else
          HttpExchange.badRequest(exchange)
        end
      end
    elseif method == 'COPY' or method == 'MOVE' then
      local overwrite = request:getHeader('overwrite') ~= 'F'
      local destPath = FileHttpHandler.getDestinationPath(exchange)
      logger:fine('destination path: "%s", overwrite: %s', destPath, overwrite)
      if destPath then
        local destFile = self:findFile(exchange, destPath)
        if destFile:exists() and not overwrite then
          HttpExchange.response(exchange, HTTP_CONST.HTTP_PRECONDITION_FAILED, 'Already exists')
        elseif method == 'COPY' then
          if file:isFile() then
            file:copyTo(destFile)
            HttpExchange.response(exchange, HTTP_CONST.HTTP_CREATED, 'Copied')
          else
            HttpExchange.badRequest(exchange)
          end
        elseif method == 'MOVE' then
          file:renameTo(destFile)
          HttpExchange.response(exchange, HTTP_CONST.HTTP_CREATED, 'Moved')
        end
      else
        HttpExchange.badRequest(exchange)
      end
    elseif method == 'PROPPATCH' or method == 'LOCK' or method == 'UNLOCK' then
      HttpExchange.badRequest(exchange)
    else
      super.handleFile(self, exchange, file, false)
    end
    logger:fine('webdav => %s', exchange)
  end

end)
