--- Provide a simple HTML HTTP handler to browse files.
-- Based on the file handler, see @{FileHttpHandler}.
-- @module jls.net.http.handler.HtmlFileHttpHandler
-- @pragma nostrip

local StringBuffer = require('jls.lang.StringBuffer')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local Url = require('jls.net.Url')
local Date = require('jls.util.Date')
local MessageDigest = require('jls.util.MessageDigest')
local Codec = require('jls.util.Codec')
local base64 = Codec.getInstance('base64', 'safe', false)

local STYLE = [[
body {
  font-family: system-ui, sans-serif;
}
a {
  text-decoration: none;
  color: inherit;
}
a.file:hover, a.dir:hover {
  text-decoration: underline;
}
a.dir {
  font-weight: bold;
}
a.action {
  padding-left: 0.1rem;
  padding-right: 0.1rem;
  border-radius: 0.3rem;
  border: 1px dotted transparent;
}
a.action:hover {
  border-color: unset;
}
div.file > a.action {
  display: none;
}
div.file:hover > a.action {
  display: initial;
}
span.actions {
  right: 1rem;
  top: 1rem;
  position: absolute;
  z-index: +1;
}
.drop:before {
  z-index: -1;
  content: '\21d1';
  font-size: 6rem;
  text-decoration: underline;
  line-height: 6rem;
  text-align: center;
  position: absolute;
  left: calc(50% - 3rem);
  top: calc(50% - 3rem);
  opacity: 0.1;
}
]]

local SCRIPT = [[
function stopEvent(e) {
  e.preventDefault();
  e.stopPropagation();
}
function showMessage(text) {
  document.body.innerHTML = '<p>' + text + '</p>';
}
function delFile(e) {
  var target = e.target;
  var filename;
  do {
    filename = target.getAttribute('href');
    target = target.previousElementSibling;
  } while ((filename === '#') && target);
  if (e.shiftKey || window.confirm('Delete file "' + decodeURIComponent(filename) + '"?')) {
    showMessage('deleting...');
    fetch(filename, {
      credentials: "same-origin",
      method: "DELETE"
    }).then(function() {
      window.location.reload();
    });
  }
  stopEvent(e);
}
function renameFile(e) {
  var target = e.target;
  var filename;
  do {
    filename = target.getAttribute('href');
    target = target.previousElementSibling;
  } while ((filename === '#') && target);
  var oldname = decodeURIComponent(filename).replace(/\/$/, '');
  var newname = window.prompt('Enter the new name for "' + oldname + '"?', oldname)
  if (newname) {
    showMessage('renaming...');
    fetch(filename, {
      credentials: "same-origin",
      method: "MOVE",
      headers: {
        "destination": window.location.pathname + newname
      }
    }).then(function() {
      window.location.reload();
    });
  }
  stopEvent(e);
}
function createDir(name) {
  if (typeof name === 'string' && name && name.indexOf('/') === -1) {
    fetch(name + '/', {
      credentials: "same-origin",
      method: "PUT"
    }).then(function() {
      window.location.reload();
    });
  }
}
function askDir(e) {
  createDir(window.prompt('Enter the folder name?'));
  stopEvent(e);
}
function putFiles(files) {
  if (files && files.length > 0) {
    files = Array.prototype.slice.call(files);
    showMessage('upload in progress...');
    var count = 0;
    Promise.all(files.map(function(file) {
      return fetch(file.name, {
        credentials: "same-origin",
        method: "PUT",
        headers: {
          "jls-last-modified": file.lastModified
        },
        body: file
      }).then(function() {
        count++;
        showMessage('' + count + '/' + files.length + ' files uploaded...');
      });
    })).then(function() {
      window.location.reload();
    });
  }
}
function browseFiles(e) {
  stopEvent(e);
  document.getElementsByName("files-upload")[0].click();
}
function enableDrag() {
  if (window.File && window.FileReader && window.FileList && window.Blob) {
    document.addEventListener("dragover", stopEvent);
    document.addEventListener("drop", function(e) {
      stopEvent(e);
      putFiles(e.dataTransfer.files);
    });
    var body = document.getElementsByTagName('body')[0];
    body.className = 'drop';
    body.title = 'Drop files to upload';
  }
}
]]

local SLIDE_STYLE = [[
html {
  height: 100%;
}
body {
  height: 100%;
  margin: 0;
  display: block;
  overflow: hidden;
}
body > div {
  height: 1.5rem;
  text-align: center;
}
body > iframe {
  width: 100%;
  height: calc(100% - 1.5rem);
  border: 0;
}
]]

local SLIDE_SCRIPT = [[
var names = ["about:blank"];
var index = 0;
function show(e,d) {
  index = (index + names.length + d) % names.length;
  var frame = document.getElementsByName('iframe')[0];
  var name = names[index];
  frame.src = name;
  document.title = '' + (index + 1) + '/' + names.length + ' - ' + decodeURIComponent(name);
  if (e) {
    stopEvent(e);
  }
}
function adjust() {
  var frame = document.getElementsByName('iframe')[0];
  var doc = frame.contentDocument || frame.contentWindow.document;
  var img = doc && doc.getElementsByTagName('img')[0];
  if (img) {
    img.style.maxWidth = '100%';
    img.style.maxHeight = '100%';
  }
}
]]

--- A HtmlFileHttpHandler class.
-- @type HtmlFileHttpHandler
return require('jls.lang.class').create(FileHttpHandler, function(htmlFileHttpHandler, super)

  function htmlFileHttpHandler:initialize(...)
    super.initialize(self, ...)
    self.queryMap = {
      ['script.js'] = SCRIPT,
      ['style.css'] = STYLE,
      ['slide-script.js'] = SLIDE_SCRIPT,
      ['slide-style.css'] = SLIDE_STYLE,
    }
    self.queryPath = {}
    self.minSlide = 1
  end

  function htmlFileHttpHandler:getQuery(name)
    return self.queryMap[name]
  end

  function htmlFileHttpHandler:setQuery(name, content)
    self.queryPath[name] = nil
    self.queryMap[name] = content
  end

  function htmlFileHttpHandler:getQueryPath(name)
    local path = self.queryPath[name]
    if not path then
      local content = self.queryMap[name]
      if content then
        local md = MessageDigest.getInstance('SHA-1')
        md:update(content)
        path = string.format('!%s!%s', base64:encode(md:digest()), name)
        path = Url.encodeURI(path)
        self.queryPath[name] = path
      else
        return name
      end
    end
    return path
  end

  function htmlFileHttpHandler:appendFileHtmlBody(buffer, md)
    buffer:append('<a href="', Url.encodeURIComponent(md.link or md.name))
    if md.isDir then
      buffer:append('/')
    end
    buffer:append('" title="')
    local sep = ''
    if md.time then
      buffer:append(Date.iso(md.time, true))
      sep = ' '
    end
    if md.size then
      buffer:append(sep, md.size, ' bytes')
    end
    buffer:append('" class="')
    if md.isDir then
      buffer:append('dir')
    else
      buffer:append('file')
    end
    buffer:append('">', md.name, '</a>\n')
  end

  local function isViewable(file)
    if file.isDir or file.link then
      return false
    end
    local m = FileHttpHandler.guessContentType(file.name, '')
    local t = string.match(m, '^([^/]+)/')
    return t == 'image' or t == 'video' or t == 'text'
  end

  local function countViewables(files)
    local n = 0
    for _, file in ipairs(files) do
      if isViewable(file) then
        n = n + 1
      end
    end
    return n
  end

  function htmlFileHttpHandler:appendDirectoryHtmlActions(exchange, buffer, files)
    if self.allowCreate then
      buffer:append('<a href="#" title="Choose files to upload" class="action" onclick="browseFiles(event)">&#x2795;</a>\n')
      buffer:append('<a href="#" title="Create a folder" class="action" onclick="askDir(event)">&#x1F4C2;</a>\n')
    end
    if self.minSlide == 0 or countViewables(files) >= self.minSlide then
      buffer:append('<a href="?d=slide" title="Show" class="action">&#x1f441;</a>\n')
    end
  end

  function htmlFileHttpHandler:appendDirectoryHtmlBody(exchange, buffer, files)
    local path = self:getPath(exchange)
    if path ~= '' then
      buffer:append('<a href=".." class="dir">..</a><br/>\n')
    end
    buffer:append('<span class="actions">\n')
    self:appendDirectoryHtmlActions(exchange, buffer, files)
    buffer:append('</span>\n')
    for _, file in ipairs(files) do
      buffer:append('<div class="file">\n')
      self:appendFileHtmlBody(buffer, file)
      if self.allowCreate and self.allowDelete then
        buffer:append('<a href="#" title="Rename" class="action" onclick="renameFile(event)">&#x270E;</a>\n')
      end
      if self.allowDelete then
        buffer:append('<a href="#" title="Delete" class="action" onclick="delFile(event)">&#x2715;</a>\n')
      end
      buffer:append('</div>\n')
    end
    if self.allowCreate then
      buffer:append('<input type="file" multiple name="files-upload" onchange="putFiles(this.files)" style="display: none;"/>\n')
      buffer:append('<script>enableDrag();</script>\n')
    end
    return buffer
  end

  function htmlFileHttpHandler:appendDirectoryHtmlSlideBody(exchange, buffer, files)
    buffer:append([[<div>
<a href="#" title="Previous" class="action" onclick="show(event,-1)">&#x2190;</a>
<a href="#" title="Next" class="action" onclick="show(event,1)">&#x2192;</a>
<a href="#" title="Close" class="action" onclick="window.location = window.location.pathname" style="right: 1rem; position: absolute;">&#x2715;</a>
</div>
<iframe name="iframe" src="about:blank" onload="adjust()"></iframe></body>
]])
    local list = {}
    for _, file in ipairs(files) do
      if isViewable(file) then
        table.insert(list, Url.encodeURIComponent(file.name))
      end
    end
    if #list > 0 then
      buffer:append('<script>\nnames = ["')
      buffer:append(table.concat(list, '","'))
      buffer:append('"];\nshow(undefined,0);\n</script>\n')
    end
    return buffer
  end

  function htmlFileHttpHandler:handleGetDirectory(exchange, dir)
    local request = exchange:getRequest()
    local acceptHdr = HTTP_CONST.HEADER_ACCEPT
    if not request:hasHeaderValue(acceptHdr, HttpExchange.CONTENT_TYPES.html) and
        (request:hasHeaderValue(acceptHdr, HttpExchange.CONTENT_TYPES.json) or
        request:hasHeaderValue(acceptHdr, HttpExchange.CONTENT_TYPES.txt)) then
      return super.handleGetDirectory(self, exchange, dir)
    end
    local files = self:listFileMetadata(exchange, dir)
    local basePath = exchange:getContext():getBasePath()
    local buffer = StringBuffer:new()
    buffer:append('<!DOCTYPE html><html><head><meta charset="UTF-8" />\n')
    buffer:append('<meta name="viewport" content="width=device-width, initial-scale=1" />\n')
    buffer:append('<link href="', basePath, self:getQueryPath('style.css'), '" rel="stylesheet" />\n')
    buffer:append('<script src="', basePath, self:getQueryPath('script.js'), '" type="text/javascript" charset="utf-8"></script>\n')
    if exchange:getRequest():getSearchParam('d') == 'slide' then
      buffer:append('<link href="', basePath, self:getQueryPath('slide-style.css'), '" rel="stylesheet" />\n')
      buffer:append('<script src="', basePath, self:getQueryPath('slide-script.js'), '" type="text/javascript" charset="utf-8"></script>\n')
      buffer:append('</head><body>\n')
      self:appendDirectoryHtmlSlideBody(exchange, buffer, files)
    else
      buffer:append('</head><body>\n')
      self:appendDirectoryHtmlBody(exchange, buffer, files)
    end
    buffer:append('</body></html>\n')
    local response = exchange:getResponse()
    response:setContentType(HttpExchange.CONTENT_TYPES.html)
    response:setCacheControl(false)
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setBody(buffer:toString())
  end

  function htmlFileHttpHandler:handle(exchange)
    local method = exchange:getRequestMethod()
    if method == HTTP_CONST.METHOD_GET or method == HTTP_CONST.METHOD_HEAD then
      local query = string.match(exchange:getRequestPath(), '^![%w%-_]+!(.+)$')
      if query then
        local content = self.queryMap[query]
        if content then
          local response = exchange:getResponse()
          response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
          response:setContentType(self:getContentType(query))
          response:setCacheControl(43200)
          response:setContentLength(#content)
          if method == HTTP_CONST.METHOD_GET then
            response:setBody(content)
          end
          return
        end
      end
    end
    return super.handle(self, exchange)
  end

end)
