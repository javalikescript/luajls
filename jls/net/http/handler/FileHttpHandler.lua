--- Provide a simple HTTP handler for files.
-- @module jls.net.http.handler.FileHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local httpHandlerBase = require('jls.net.http.handler.base')
local httpHandlerUtil = require('jls.net.http.handler.util')
local json = require('jls.util.json')
local File = require('jls.io.File')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local StringBuffer = require('jls.lang.StringBuffer')

--- A FileHttpHandler class.
-- @type FileHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(fileHttpHandler)

  --- Creates a file @{HttpHandler}.
  -- The data will be pass to the wrapped handler once.
  -- @tparam File rootFile the root File
  -- @tparam[opt] string permissions a string containing the granted permissions, 'rwxlcud' default is 'r'
  -- @tparam[opt] string indexFilename the name of the file to use in case of GET request on a directory
  -- @function FileHttpHandler:new
  function fileHttpHandler:initialize(rootFile, permissions, indexFilename)
    self.rootFile = File.asFile(rootFile)
    self.defaultFile = indexFilename or 'index.html'
    if type(permissions) ~= 'string' then
      permissions = 'r'
    end
    self.allowRead = not not string.match(permissions, 'r')
    self.allowList = not not string.match(permissions, '[xl]')
    self.allowUpdate = not not string.match(permissions, '[wu]')
    self.allowCreate = not not string.match(permissions, '[wc]')
    self.allowDelete = not not string.match(permissions, '[wd]')
    if logger:isLoggable(logger.FINE) then
      logger:fine('fileHttpHandler permissions is "'..permissions..'"')
      for k, v in pairs(self) do
        logger:fine('  '..tostring(k)..': "'..tostring(v)..'"')
      end
    end
  end

  function fileHttpHandler:getContentType(file)
    return httpHandlerUtil.guessContentType(file)
  end

  function fileHttpHandler:handleHeadFile(httpExchange, file)
    local response = httpExchange:getResponse()
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setContentType(self:getContentType(file))
    response:setCacheControl(false)
    response:setContentLength(file:length())
  end

  function fileHttpHandler:handleGetFile(httpExchange, file)
    local response = httpExchange:getResponse()
    self:handleHeadFile(httpExchange, file)
    response:onWriteBodyStreamHandler(function()
      FileStreamHandler.readAll(file, response:getBodyStreamHandler())
    end)
  end

  function fileHttpHandler:handleGetDirectory(httpExchange, file, showParent)
    local response = httpExchange:getResponse()
    local filenames = file:list()
    local body = ''
    local request = httpExchange:getRequest()
    if request:hasHeaderValue(HTTP_CONST.HEADER_ACCEPT, httpHandlerUtil.CONTENT_TYPES.json) then
      local dir = {}
      for _, filename in ipairs(filenames) do
        local f = File:new(file, filename)
        table.insert(dir, {
          name = filename,
          isDirectory = f:isDirectory()
        })
      end
      body = json.encode(dir)
      response:setContentType(httpHandlerUtil.CONTENT_TYPES.json)
    else
      local buffer = StringBuffer:new()
      if showParent then
        buffer:append('<a href="..">..</a><br/>\n')
      end
      for _, filename in ipairs(filenames) do
        local f = File:new(file, filename)
        if f:isDirectory() then
          filename = filename..'/'
        end
        buffer:append('<a href="', filename, '">', filename, '</a><br/>\n')
      end
      body = buffer:toString()
      response:setContentType(httpHandlerUtil.CONTENT_TYPES.html)
    end
    response:setCacheControl(false)
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setBody(body)
  end

  function fileHttpHandler:handle(httpExchange)
    local method = httpExchange:getRequestMethod()
    local path = httpExchange:getRequestArguments()
    local isDirectoryPath = string.sub(path, -1) == '/'
    local filePath = isDirectoryPath and string.sub(path, 1, -2) or path
    if filePath == '' and method ~= HTTP_CONST.METHOD_GET or not httpHandlerUtil.isValidSubPath(path) then
      httpHandlerBase.forbidden(httpExchange)
      return
    end
    local file = File:new(self.rootFile, filePath)
    if logger:isLoggable(logger.FINE) then
      logger:fine('fileHttpHandler method is "'..method..'" file is "'..file:getPath()..'"')
    end
    -- TODO Handle HEAD as a GET without body
    -- TODO Handle PATCH, MOVE
    if method == HTTP_CONST.METHOD_GET then
      if file:isFile() then
        self:handleGetFile(httpExchange, file)
      elseif file:isDirectory() then
        if self.allowList then
          self:handleGetDirectory(httpExchange, file, true)
        else
          file = File:new(file, self.defaultFile)
          if file:isFile() then
            self:handleGetFile(httpExchange, file)
          else
            httpHandlerBase.notFound(httpExchange)
          end
        end
      else
        httpHandlerBase.notFound(httpExchange)
      end
    elseif method == HTTP_CONST.METHOD_POST and self.allowUpdate then
      if self.allowCreate or file:isFile() then
        httpExchange:getRequest():setBodyStreamHandler(FileStreamHandler:new(file, true))
        httpHandlerBase.ok(httpExchange)
      else
        httpHandlerBase.forbidden(httpExchange)
      end
    elseif method == HTTP_CONST.METHOD_PUT and self.allowCreate then
      if isDirectoryPath then
        file:mkdirs() -- TODO Handle errors
      else
        httpExchange:getRequest():setBodyStreamHandler(FileStreamHandler:new(file, true))
      end
      httpHandlerBase.ok(httpExchange)
    elseif method == HTTP_CONST.METHOD_DELETE and self.allowDelete then
      if file:isFile() then
        file:delete() -- TODO Handle errors
      elseif file:isDirectory() then
        file:deleteRecursive() -- TODO Handle errors
      end
      httpHandlerBase.ok(httpExchange)
    else
      httpHandlerBase.methodNotAllowed(httpExchange)
    end
  end

end)
