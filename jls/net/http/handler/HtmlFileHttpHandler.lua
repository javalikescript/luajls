--- Provide a simple HTML HTTP handler to browse files.
-- Based on the file handler, see @{FileHttpHandler}.
-- @module jls.net.http.handler.HtmlFileHttpHandler
-- @pragma nostrip

local StringBuffer = require('jls.lang.StringBuffer')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local Url = require('jls.net.Url')
local Date = require('jls.util.Date')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')

local DIRECTORY_STYLE = [[<style>
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
</style>
]]

local DROP_STYLE = [[<style>
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
</style>
]]

local COMMON_SCRIPT = [[
<script>
function stopEvent(e) {
  e.preventDefault();
  e.stopPropagation();
} 
function showMessage(text) {
  document.body.innerHTML = '<p>' + text + '</p>';
} 
</script>
]]

local DELETE_SCRIPT = [[
<script>
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
</script>
]]

local RENAME_SCRIPT = [[
<script>
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
</script>
]]

local PUT_SCRIPT = [[
<input type="file" multiple onchange="putFiles(this.files)" />
<script>
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
if (window.File && window.FileReader && window.FileList && window.Blob) {
  document.addEventListener("dragover", stopEvent);
  document.addEventListener("drop", function(e) {
    stopEvent(e);
    putFiles(e.dataTransfer.files);
  });
  document.querySelector("input[type=file]").style.display = "none";
}
</script>
]]

--- A HtmlFileHttpHandler class.
-- @type HtmlFileHttpHandler
return require('jls.lang.class').create(FileHttpHandler, function(htmlFileHttpHandler, super)

  function htmlFileHttpHandler:appendFileHtmlBody(buffer, file)
    buffer:append('<a href="', Url.encodeURIComponent(file.link or file.name))
    if file.isDir then
      buffer:append('/')
    end
    buffer:append('" title="')
    local sep = ''
    if file.time then
      buffer:append(Date.iso(file.time, true))
      sep = ' '
    end
    if file.size then
      buffer:append(sep, file.size, ' bytes')
    end
    buffer:append('" class="')
    if file.isDir then
      buffer:append('dir')
    else
      buffer:append('file')
    end
    buffer:append('">', file.name, '</a>\n')
  end

  function htmlFileHttpHandler:appendDirectoryHtmlBody(exchange, buffer, files)
    local path = self:getPath(exchange)
    if path ~= '' then
      buffer:append('<a href=".." class="dir">..</a><br/>\n')
    end
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
    if self.allowCreate or self.allowDelete then
      buffer:append(COMMON_SCRIPT)
      if self.allowCreate then
        buffer:append(PUT_SCRIPT)
      end
      if self.allowDelete then
        buffer:append(DELETE_SCRIPT)
      end
      if self.allowCreate and self.allowDelete then
        buffer:append(RENAME_SCRIPT)
      end
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
    local files = self.fs.listFileMetadata(exchange, dir)
    local buffer = StringBuffer:new()
    buffer:append('<!DOCTYPE html><html><head><meta charset="UTF-8" />\n')
    buffer:append('<meta name="viewport" content="width=device-width, initial-scale=1" />\n')
    buffer:append(DIRECTORY_STYLE)
    local bodyAtttributes = ''
    if self.allowCreate then
      buffer:append(DROP_STYLE)
      bodyAtttributes = ' class="drop" title="Drop files to upload"'
    end
    buffer:append('</head><body', bodyAtttributes, '>\n')
    self:appendDirectoryHtmlBody(exchange, buffer, files)
    buffer:append('</body></html>\n')
    local response = exchange:getResponse()
    response:setContentType(HttpExchange.CONTENT_TYPES.html)
    response:setCacheControl(false)
    response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
    response:setBody(buffer:toString())
  end

end)
