--- Provide a simple HTTP handler for files.
-- @module jls.net.http.handler.FileHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger')
local json = require('jls.util.json')
local Path = require('jls.io.Path')
local File = require('jls.io.File')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local StringBuffer = require('jls.lang.StringBuffer')
local HttpExchange = require('jls.net.http.HttpExchange')

--- A FileHttpHandler class.
-- @type FileHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(fileHttpHandler, _, FileHttpHandler)

  --- Creates a file @{HttpHandler}.
  -- The data will be pass to the wrapped handler once.
  -- @tparam File rootFile the root File
  -- @tparam[opt] string permissions a string containing the granted permissions, 'rwxlcud' default is 'r'
  -- @tparam[opt] string indexFilename the name of the file to use in case of GET request on a directory
  -- @function FileHttpHandler:new
  function fileHttpHandler:initialize(rootFile, permissions, indexFilename)
    self.rootFile = File.asFile(rootFile)
    if indexFilename then
      if type(indexFilename) == 'string' and indexFilename ~= '' then
        self.defaultFile = indexFilename
      end
    else
      self.defaultFile = 'index.html'
    end
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
    return FileHttpHandler.guessContentType(file)
  end

  function fileHttpHandler:handleGetDirectory(httpExchange, dir, showParent)
    local response = httpExchange:getResponse()
    local files = dir:listFiles()
    local body = ''
    local request = httpExchange:getRequest()
    if request:hasHeaderValue(HTTP_CONST.HEADER_ACCEPT, HttpExchange.CONTENT_TYPES.json) then
      local content = {}
      for _, file in ipairs(files) do
        table.insert(content, {
          name = file:getName(),
          isDirectory = file:isDirectory()
        })
      end
      body = json.encode(content)
      response:setContentType(HttpExchange.CONTENT_TYPES.json)
    else
      local buffer = StringBuffer:new()
      if showParent then
        buffer:append('<a href="..">..</a><br/>\n')
      end
      for _, file in ipairs(files) do
        local filename = file:getName()
        if file:isDirectory() then
          filename = filename..'/'
        end
        buffer:append('<a href="', filename, '">', filename, '</a><br/>\n')
      end
      body = buffer:toString()
      response:setContentType(HttpExchange.CONTENT_TYPES.html)
    end
    response:setCacheControl(false)
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setBody(body)
  end

  function fileHttpHandler:findFile(path, readOnly)
    local file = File:new(self.rootFile, path)
    if readOnly and file:isDirectory() and not self.allowList and self.defaultFile then
      file = File:new(file, self.defaultFile)
    end
    return file
  end

  function fileHttpHandler:handleGetFile(httpExchange, file)
    local response = httpExchange:getResponse()
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setContentType(self:getContentType(file))
    response:setCacheControl(false)
    response:setContentLength(file:length())
    if httpExchange:getRequestMethod() == HTTP_CONST.METHOD_GET then
      self:sendFile(httpExchange, file)
    end
  end

  function fileHttpHandler:receiveFile(httpExchange, file)
    httpExchange:getRequest():setBodyStreamHandler(FileStreamHandler:new(file, true))
  end

  function fileHttpHandler:sendFile(httpExchange, file)
    local response = httpExchange:getResponse()
    response:onWriteBodyStreamHandler(function()
      FileStreamHandler.readAll(file, response:getBodyStreamHandler())
    end)
  end

  function fileHttpHandler:handleFile(httpExchange, file, isDirectoryPath)
    local method = httpExchange:getRequestMethod()
    -- TODO Handle PATCH, MOVE
    if method == HTTP_CONST.METHOD_GET or method == HTTP_CONST.METHOD_HEAD then
      if file:isFile() then
        self:handleGetFile(httpExchange, file)
      elseif file:isDirectory() and self.allowList then
        self:handleGetDirectory(httpExchange, file, true)
      else
        HttpExchange.notFound(httpExchange)
      end
    elseif method == HTTP_CONST.METHOD_POST and self.allowUpdate then
      if self.allowCreate or file:isFile() then
        self:receiveFile(httpExchange, file)
        HttpExchange.ok(httpExchange)
      else
        HttpExchange.forbidden(httpExchange)
      end
    elseif method == HTTP_CONST.METHOD_PUT and self.allowCreate then
      if isDirectoryPath then
        file:mkdirs() -- TODO Handle errors
      else
        self:receiveFile(httpExchange, file)
      end
      HttpExchange.ok(httpExchange)
    elseif method == HTTP_CONST.METHOD_DELETE and self.allowDelete then
      if file:isFile() then
        file:delete() -- TODO Handle errors
      elseif file:isDirectory() then
        file:deleteRecursive() -- TODO Handle errors
      end
      HttpExchange.ok(httpExchange)
    else
      HttpExchange.methodNotAllowed(httpExchange)
    end
  end

  function fileHttpHandler:isValidPath(httpExchange, path)
  end

  function fileHttpHandler:handle(httpExchange)
    local method = httpExchange:getRequestMethod()
    local path = httpExchange:getRequestArguments()
    local isDirectoryPath = string.sub(path, -1) == '/'
    local filePath = isDirectoryPath and string.sub(path, 1, -2) or path
    if not HttpExchange.isValidSubPath(path) then
      HttpExchange.forbidden(httpExchange)
      return
    end
    local readOnly = method == HTTP_CONST.METHOD_GET or method == HTTP_CONST.METHOD_HEAD
    local file = self:findFile(filePath, readOnly)
    if logger:isLoggable(logger.FINE) then
      logger:fine('fileHttpHandler method is "'..method..'" file is "'..file:getPath()..'"')
    end
    self:handleFile(httpExchange, file, isDirectoryPath)
  end

  function FileHttpHandler.guessContentType(path, def)
    local extension
    if type(path) == 'string' then
      extension = Path.extractExtension(path)
    else
      extension = path:getExtension()
    end
    return HttpExchange.CONTENT_TYPES[extension] or def or HttpExchange.CONTENT_TYPES.bin
  end

end)
