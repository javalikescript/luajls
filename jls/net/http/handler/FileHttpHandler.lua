--- Provide a simple HTTP handler for files.
-- @module jls.net.http.handler.FileHttpHandler
-- @pragma nostrip

local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local StringBuffer = require('jls.lang.StringBuffer')
local Path = require('jls.io.Path')
local File = require('jls.io.File')
local FileStreamHandler = require('jls.io.streams.FileStreamHandler')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local Url = require('jls.net.Url')
local json = require('jls.util.json')

local function getFileMetadata(file, name)
  return {
    isDir = file:isDirectory(),
    size = file:length(),
    time = file:lastModified(),
    name = name,
  }
end

local FS = {
  getFileMetadata = function(exchange, file)
    if file:exists() then
      return getFileMetadata(file)
    end
  end,
  listFileMetadata = function(exchange, dir)
    local files = {}
    for _, file in ipairs(dir:listFiles()) do
      local name = file:getName()
      if string.find(name, '^[^%.]') then
        table.insert(files, getFileMetadata(file, name))
      end
    end
    return files
  end,
  createDirectory = function(exchange, file)
    return file:mkdir()
  end,
  copyFile = function(exchange, file, destFile)
    return file:copyTo(destFile)
  end,
  renameFile = function(exchange, file, destFile)
    return file:renameTo(destFile)
  end,
  deleteFile = function(exchange, file, recursive)
    if recursive then
      return file:deleteRecursive()
    end
    return file:delete()
  end,
  setFileStreamHandler = function(exchange, file, sh, md, offset, length)
    FileStreamHandler.read(file, sh, offset, length)
  end,
  getFileStreamHandler = function(exchange, file, time)
    return FileStreamHandler:new(file, true, function()
      file:setLastModified(time)
    end, nil, true)
  end,
}

--- A FileHttpHandler class.
-- @type FileHttpHandler
return require('jls.lang.class').create('jls.net.http.HttpHandler', function(fileHttpHandler, _, FileHttpHandler)

  --- Creates a file @{HttpHandler}.
  -- @tparam File rootFile the root File
  -- @tparam[opt] string permissions a string containing the granted permissions, 'rwxlcud' default is 'r'
  -- @tparam[opt] string filename the name of the file to use in case of GET request on a directory, default is 'index.html'
  -- @function FileHttpHandler:new
  function fileHttpHandler:initialize(rootFile, permissions, filename)
    self.rootFile = File.asFile(rootFile)
    if filename then
      if type(filename) == 'string' and filename ~= '' then
        self.defaultFile = filename
      end
    else
      self.defaultFile = 'index.html'
    end
    self.fs = FS
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

  function fileHttpHandler:getContentType(file)
    return FileHttpHandler.guessContentType(file)
  end

  function fileHttpHandler:getFileSystem()
    return self.fs
  end

  function fileHttpHandler:setFileSystem(fs)
    self.fs = fs or FS
    return self
  end

  function fileHttpHandler:handleGetDirectory(exchange, dir)
    local response = exchange:getResponse()
    local files = self.fs.listFileMetadata(exchange, dir)
    local body = ''
    local request = exchange:getRequest()
    if request:hasHeaderValue(HTTP_CONST.HEADER_ACCEPT, HttpExchange.CONTENT_TYPES.json) then
      body = json.encode(files)
      response:setContentType(HttpExchange.CONTENT_TYPES.json)
    else
      local buffer = StringBuffer:new()
      for _, file in ipairs(files) do
        buffer:append(file.name, '\n')
      end
      body = buffer:toString()
      response:setContentType(HttpExchange.CONTENT_TYPES.txt)
    end
    response:setCacheControl(false)
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setBody(body)
  end

  function fileHttpHandler:findFile(exchange, path, readOnly)
    local file = File:new(self.rootFile, path)
    if readOnly and file:isDirectory() and not self.allowList and self.defaultFile then
      file = File:new(file, self.defaultFile)
    end
    return file
  end

  function fileHttpHandler:handleGetFile(exchange, file, md)
    local response = exchange:getResponse()
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setContentType(self:getContentType(file))
    if md.time then
      response:setLastModified(md.time)
    end
    response:setCacheControl(self.cacheControl)
    response:setContentLength(md.size)
    response:setHeader('Accept-Ranges', 'bytes')
    if exchange:getRequestMethod() == HTTP_CONST.METHOD_GET then
      local request = exchange:getRequest()
      local ifModifiedSince = request:getIfModifiedSince()
      if ifModifiedSince and md.time and md.time <= ifModifiedSince then
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
        if first and first < md.size or last and last < md.size then
          offset = first or (md.size - last)
          if first and last and first <= last then
            length = last - first + 1
          else
            length = md.size - offset
          end
        end
      end
      if offset and length then
        response:setStatusCode(HTTP_CONST.HTTP_PARTIAL_CONTENT, 'Partial')
        response:setContentLength(length)
        local contentRange = 'bytes '..tostring(offset)..'-'..tostring(offset + length - 1)..'/'..tostring(md.size)
        logger:fine('Content-Range: %s, from Range: %s', contentRange, range)
        response:setHeader('Content-Range', contentRange)
      end
      response:onWriteBodyStreamHandler(function()
        local sh = response:getBodyStreamHandler()
        self.fs.setFileStreamHandler(exchange, file, sh, md, offset, length)
      end)
    end
  end

  function fileHttpHandler:receiveFile(exchange, file)
    local request = exchange:getRequest()
    local time = tonumber(request:getHeader('jls-last-modified'))
    request:setBodyStreamHandler(self.fs.getFileStreamHandler(exchange, file, time))
  end

  function fileHttpHandler:handleGetHeadFile(exchange, file)
    local md = self.fs.getFileMetadata(exchange, file)
    if md then
      if md.isDir then
        if self.allowList then
          self:handleGetDirectory(exchange, file)
        else
          HttpExchange.forbidden(exchange)
        end
      else
        self:handleGetFile(exchange, file, md)
      end
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
          self.fs.createDirectory(exchange, file) -- TODO Handle errors
        else
          self:receiveFile(exchange, file)
        end
        HttpExchange.ok(exchange)
      else
        HttpExchange.forbidden(exchange)
      end
    elseif method == HTTP_CONST.METHOD_DELETE and self.allowDelete then
      self.fs.deleteFile(exchange, file, self.allowDeleteRecursive) -- TODO Handle errors
      HttpExchange.ok(exchange)
    elseif method == 'MOVE' and self.allowCreate and self.allowDelete then
      local request = exchange:getRequest()
      local destination = request:getHeader('destination') or ''
      if string.find(destination, '://') then
        destination = Url:new(destination):getPath()
      end
      destination = Url.decodePercent(destination)
      local destPath = exchange:getContext():getArguments(destination)
      if destPath then
        local destFile = self:findFile(exchange, destPath)
        self.fs.renameFile(exchange, file, destFile)
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
    local isDirectoryPath = string.sub(path, -1) == '/'
    local filePath = isDirectoryPath and string.sub(path, 1, -2) or path
    filePath = Url.decodePercent(filePath)
    if not HttpExchange.isValidSubPath(path) then
      HttpExchange.forbidden(exchange)
      return
    end
    local readOnly = method == HTTP_CONST.METHOD_GET or method == HTTP_CONST.METHOD_HEAD
    local file = self:findFile(exchange, filePath, readOnly)
    if logger:isLoggable(logger.FINE) then
      logger:fine('method is "%s" file is "%s"', method, file:getPath())
    end
    return self:handleFile(exchange, file, isDirectoryPath)
  end

  function FileHttpHandler.guessContentType(path, def)
    local extension
    if type(path) == 'string' then
      extension = Path.extractExtension(path)
    elseif path then
      extension = path:getExtension()
    else
      extension = ''
    end
    return HttpExchange.CONTENT_TYPES[extension] or def or HttpExchange.CONTENT_TYPES.bin
  end

end)
