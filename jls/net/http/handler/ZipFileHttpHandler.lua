--- Provide a simple HTTP handler for ZIP file.
-- @module jls.net.http.handler.ZipFileHttpHandler
-- @pragma nostrip

local ZipFile = require('jls.util.zip.ZipFile')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')

--- A ZipFileHttpHandler class.
-- @type ZipFileHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(zipFileHttpHandler)

  --- Creates a ZIP file @{HttpHandler}.
  -- @tparam jls.io.File zipFile the ZIP file.
  function zipFileHttpHandler:initialize(zipFile)
    self.zipFile = ZipFile:new(zipFile, false)
  end

  function zipFileHttpHandler:handle(httpExchange)
    if not HttpExchange.methodAllowed(httpExchange, {HTTP_CONST.METHOD_GET, HTTP_CONST.METHOD_HEAD}) then
      return
    end
    local response = httpExchange:getResponse()
    local zipFile = self.zipFile
    local path = httpExchange:getRequestArguments()
    local entry = zipFile:getEntry(path)
    if entry and not entry:isDirectory() then
      response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
      response:setContentType(FileHttpHandler.guessContentType(path))
      response:setCacheControl(true)
      response:setContentLength(entry:getSize())
      if httpExchange:getRequestMethod() == HTTP_CONST.METHOD_GET then
        --response:setBody(zipFile:getContent(entry))
        response:onWriteBodyStreamHandler(function()
          zipFile:getContent(entry, response:getBodyStreamHandler(), true)
        end)
      end
    else
      HttpExchange.notFound(httpExchange)
    end
  end

end)
