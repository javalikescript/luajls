--- Provide a simple HTTP handler for files.
-- @module jls.net.http.handler.FileHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger'):get(...)
local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local Path = require('jls.io.Path')
local File = require('jls.io.File')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local Url = require('jls.net.Url')

--- A HttpFile class extends jls.io.File to provide file stream handler.
-- @type HttpFile
local HttpFile = class.create(File, function(httpFile)

  --- Creates a HttpFile.
  -- @tparam File file the file
  -- @function HttpFile:new
  function httpFile:initialize(file)
    for k, v in pairs(file) do
      self[k] = v
    end
  end

  --- Applies the specified stream handler to this file.
  -- @tparam StreamHandler sh The stream handler to use
  -- @tparam number offset the offset to read from
  -- @tparam number length the length to read
  function httpFile:setFileStreamHandler(sh, offset, length)
    FileStreamHandler.read(self, sh, offset, length)
  end

  --- Returns a stream handler for this file.
  -- @tparam number time the last modification time
  -- @treturn StreamHandler the stream handler
  function httpFile:getFileStreamHandler(time)
    return FileStreamHandler:new(self, true, function()
      self:setLastModified(time)
    end, nil, true)
  end

end)

--- Returns a table containing the file metadata to be exposed as JSON.
local function toFileMetadata(file)
  if file:isDirectory() then
    return {
      isDir = true,
      time = file:lastModified(),
      name = file:getName(),
    }
  end
  return {
    size = file:length(),
    time = file:lastModified(),
    name = file:getName(),
  }
end

--- Returns the content type based on the path.
local function guessContentType(path, def)
  local extension
  if type(path) == 'string' then
    extension = Path.extractExtension(path)
  elseif Path:isInstance(path) then
    extension = path:getExtension()
  end
  extension = string.lower(extension or '')
  return HttpExchange.CONTENT_TYPES[extension] or def or HttpExchange.CONTENT_TYPES.bin
end

--- Returns the destination header as a path in the exchange context.
local function getDestinationPath(exchange, name)
  local request = exchange:getRequest()
  local destination = request:getHeader(name or 'destination')
  if destination then
    if string.find(destination, '://') then
      destination = Url:new(destination):getPath()
    end
    destination = Url.decodePercent(destination)
    return exchange:getContext():getArguments(destination)
  end
end

--- A FileHttpHandler class.
-- @type FileHttpHandler
return class.create('jls.net.http.HttpHandler', function(fileHttpHandler, _, FileHttpHandler)

  --- Creates a file @{HttpHandler}.
  -- @tparam File rootFile the root File
  -- @tparam[opt] string permissions a string containing the granted permissions, 'rwxlcud' default is 'r'
  -- @tparam[opt] string filename the name of the file to use in case of GET request on a directory, default is 'index.html'
  -- @function FileHttpHandler:new
  function fileHttpHandler:initialize(rootFile, permissions, filename)
    self.rootFile = File.asFile(rootFile)
    if type(filename) == 'string' and filename ~= '' then
      self.defaultFile = filename
    else
      self.defaultFile = 'index.html'
    end
    self.cacheControl = 0
    if type(permissions) ~= 'string' then
      permissions = 'r'
    end
    self.allowRead = not not string.match(permissions, 'r')
    self.allowList = not not string.match(permissions, '[xl]')
    self.allowUpdate = not not string.match(permissions, '[wu]')
    self.allowCreate = not not string.match(permissions, '[wc]')
    self.allowDelete = not not string.match(permissions, '[wd]')
    self.allowDeleteRecursive = not not string.match(permissions, '[RD]')
    logger:finer('permissions are "%s"', permissions)
    if logger:isLoggable(logger.FINEST) then
      for k, v in pairs(self) do
        logger:finest('  %s: "%s"', k, v)
      end
    end
  end

  function fileHttpHandler:getCacheControl()
    return self.cacheControl
  end

  function fileHttpHandler:setCacheControl(cacheControl)
    self.cacheControl = cacheControl
    return self
  end

  function fileHttpHandler:getContentType(path)
    return guessContentType(path)
  end

  function fileHttpHandler:listFileMetadata(exchange, dir)
    local files = dir:listFiles()
    local list = {}
    if files then
      for _, file in ipairs(files) do
        if string.find(file:getName(), '^[^%.]') then -- TODO Remove filter
          table.insert(list, toFileMetadata(file))
        end
      end
    end
    return list
  end

  function fileHttpHandler:handleGetDirectory(exchange, dir)
    local response = exchange:getResponse()
    local request = exchange:getRequest()
    local list = self:listFileMetadata(exchange, dir)
    local body = ''
    if request:hasHeaderValue(HTTP_CONST.HEADER_ACCEPT, HttpExchange.CONTENT_TYPES.json) then
      body = json.encode(list)
      response:setContentType(HttpExchange.CONTENT_TYPES.json)
    else
      local buffer = StringBuffer:new()
      for _, file in ipairs(list) do
        buffer:append(file.name, '\n')
      end
      body = buffer:toString()
      response:setContentType(HttpExchange.CONTENT_TYPES.txt)
    end
    response:setCacheControl(false)
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setBody(body)
  end

  function fileHttpHandler:createHttpFile(exchange, file, isDir)
    return HttpFile:new(file)
  end

  function fileHttpHandler:findFile(exchange, path, readOnly)
    local file = File:new(self.rootFile, path)
    if readOnly and file:isDirectory() and not self.allowList and self.defaultFile then
      file = File:new(file, self.defaultFile)
    end
    return file
  end

  function fileHttpHandler:handleGetFile(exchange, file)
    local response = exchange:getResponse()
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setContentType(self:getContentType(file:getName()))
    local size = file:length()
    local time = file:lastModified() or 0
    if time > 0 then
      response:setLastModified(time)
    end
    response:setCacheControl(self.cacheControl)
    response:setContentLength(size)
    response:setHeader('Accept-Ranges', 'bytes')
    if exchange:getRequestMethod() == HTTP_CONST.METHOD_GET then
      local request = exchange:getRequest()
      local ifModifiedSince = request:getIfModifiedSince()
      if ifModifiedSince and time > 0 and time <= ifModifiedSince then
        response:setStatusCode(HTTP_CONST.HTTP_NOT_MODIFIED, 'Not modified')
        return
      end
      local range = request:getHeader('range')
      local offset, length
      if range then
        -- only support a single range
        local first, last = string.match(range, '^bytes=(%d*)%-(%d*)%s*$')
        first = first and tonumber(first)
        last = last and tonumber(last)
        if first and first < size or last and last < size then
          offset = first or (size - last)
          if first and last and first <= last then
            length = last - first + 1
          else
            length = size - offset
          end
        end
      end
      if offset and length then
        response:setStatusCode(HTTP_CONST.HTTP_PARTIAL_CONTENT, 'Partial')
        response:setContentLength(length)
        local contentRange = 'bytes '..tostring(offset)..'-'..tostring(offset + length - 1)..'/'..tostring(size)
        logger:fine('Content-Range: %s, from Range: %s', contentRange, range)
        response:setHeader('Content-Range', contentRange)
      end
      response:onWriteBodyStreamHandler(function()
        file:setFileStreamHandler(response:getBodyStreamHandler(), offset, length)
      end)
    end
  end

  function fileHttpHandler:receiveFile(exchange, file)
    local request = exchange:getRequest()
    local time = tonumber(request:getHeader('jls-last-modified'))
    request:setBodyStreamHandler(file:getFileStreamHandler(time, request:getContentLength()))
  end

  function fileHttpHandler:handleGetHeadFile(exchange, file)
    if file:isDirectory() then
      if self.allowList then
        self:handleGetDirectory(exchange, file)
      else
        HttpExchange.forbidden(exchange)
      end
    elseif file:isFile() then
      self:handleGetFile(exchange, file)
    else
      HttpExchange.notFound(exchange)
    end
  end

  function fileHttpHandler:prepareFile(exchange, file)
    return Promise.resolve()
  end

  function fileHttpHandler:handleFile(exchange, file, isDirectoryPath)
    local method = exchange:getRequestMethod()
    if method == HTTP_CONST.METHOD_GET or method == HTTP_CONST.METHOD_HEAD then
      return self:prepareFile(exchange, file):next(function()
        self:handleGetHeadFile(exchange, file)
      end, function()
        HttpExchange.notFound(exchange)
      end)
    elseif method == HTTP_CONST.METHOD_POST and self.allowUpdate then
      if self.allowCreate or file:isFile() then
        self:receiveFile(exchange, file)
        HttpExchange.ok(exchange)
      else
        HttpExchange.forbidden(exchange)
      end
    elseif method == HTTP_CONST.METHOD_PUT and self.allowCreate then
      if self.allowUpdate or not file:exists() then
        if isDirectoryPath then
          file:mkdir() -- TODO Handle errors
        else
          self:receiveFile(exchange, file)
        end
        HttpExchange.ok(exchange)
      else
        HttpExchange.forbidden(exchange)
      end
    elseif method == HTTP_CONST.METHOD_DELETE and self.allowDelete then
      if self.allowDeleteRecursive then
        file:deleteRecursive() -- TODO Handle errors
      else
        file:delete() -- TODO Handle errors
      end
      HttpExchange.ok(exchange)
    elseif method == 'MOVE' and self.allowCreate and self.allowDelete then
      local destPath = getDestinationPath(exchange)
      if destPath then
        local destFile = self:findFile(exchange, destPath)
        file:renameTo(destFile)
        HttpExchange.response(exchange, HTTP_CONST.HTTP_CREATED, 'Moved')
      else
        HttpExchange.badRequest(exchange)
      end
    else
      HttpExchange.methodNotAllowed(exchange)
    end
  end

  function fileHttpHandler:getPath(exchange)
    return exchange:getRequestPath()
  end

  function fileHttpHandler:isValidPath(exchange, path)
  end

  function fileHttpHandler:handle(exchange)
    local method = exchange:getRequestMethod()
    local path = self:getPath(exchange)
    local isDirectoryPath = path == '' or string.sub(path, -1) == '/'
    local filePath = isDirectoryPath and string.sub(path, 1, -2) or path
    filePath = Url.decodePercent(filePath)
    if not HttpExchange.isValidSubPath(path) then
      HttpExchange.forbidden(exchange)
      return
    end
    local readOnly = method == HTTP_CONST.METHOD_GET or method == HTTP_CONST.METHOD_HEAD
    local file = self:findFile(exchange, filePath, readOnly)
    if logger:isLoggable(logger.FINE) then
      logger:fine('method is "%s" path is "%s" file is "%s"', method, path, file:getPath())
    end
    local httpFile = self:createHttpFile(exchange, file, isDirectoryPath)
    if not httpFile then
      HttpExchange.internalServerError(exchange, 'HTTP file not available')
      return
    end
    return self:handleFile(exchange, httpFile, isDirectoryPath)
  end

  FileHttpHandler.HttpFile = HttpFile

  FileHttpHandler.toFileMetadata = toFileMetadata

  FileHttpHandler.guessContentType = guessContentType

  FileHttpHandler.getDestinationPath = getDestinationPath

end)
