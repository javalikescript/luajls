--- Provide a simple HTTP handler for ZIP file.
-- @module jls.net.http.handler.ZipFileHttpHandler
-- @pragma nostrip

local ZipFile = require('jls.util.zip.ZipFile')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local Date = require('jls.util.Date')

--- A ZipFileHttpHandler class.
-- @type ZipFileHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(zipFileHttpHandler)

  --- Creates a ZIP file @{HttpHandler}.
  -- @tparam jls.io.File zipFile the ZIP file.
  -- @function ZipFileHttpHandler:new
  function zipFileHttpHandler:initialize(zipFile)
    self.zipFile = ZipFile:new(zipFile, false)
  end

  function zipFileHttpHandler:handle(exchange)
    if not HttpExchange.methodAllowed(exchange, {HTTP_CONST.METHOD_GET, HTTP_CONST.METHOD_HEAD}) then
      return
    end
    local response = exchange:getResponse()
    local zipFile = self.zipFile
    local path = exchange:getRequestPath()
    local entry = zipFile:getEntry(path)
    if entry and not entry:isDirectory() then
      response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
      response:setContentType(FileHttpHandler.guessContentType(path))
      response:setCacheControl(true)
      local d = Date.fromLocalDateTime(entry:getDatetime(), true)
      if d then
        response:setLastModified(d)
      end
      response:setContentLength(entry:getSize())
      if exchange:getRequestMethod() == HTTP_CONST.METHOD_GET then
        local request = exchange:getRequest()
        local ifModifiedSince = request:getIfModifiedSince()
        if ifModifiedSince and d and d:getTime() <= ifModifiedSince then
          response:setStatusCode(HTTP_CONST.HTTP_NOT_MODIFIED, 'Not modified')
          return
        end
        --response:setBody(zipFile:getContent(entry))
        response:onWriteBodyStreamHandler(function()
          zipFile:getContent(entry, response:getBodyStreamHandler(), true)
        end)
      end
    else
      HttpExchange.notFound(exchange)
    end
  end

end)
