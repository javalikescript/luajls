local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local WebView = require('jls.util.WebView')
local tables = require('jls.util.tables')

local CONFIG_SCHEMA = {
  title = 'Tiny Web Browser',
  type = 'object',
  additionalProperties = false,
  properties = {
    url = {
      title = 'An URL to open, could point to a local file',
      type = 'string'
    },
    ['search-url'] = {
      title = 'The search URL',
      type = 'string',
      default = 'https://www.google.com/search?q='
    },
    webview = {
      type = 'object',
      additionalProperties = false,
      properties = {
        title = {
          title = 'The window title',
          type = 'string',
          default = 'Tiny Web Browser'
        },
        width = {
          title = 'The window width',
          type = 'integer',
          default = 1024,
          minimum = 320,
          maximum = 65535,
        },
        height = {
          title = 'The window width',
          type = 'integer',
          default = 768,
          minimum = 240,
          maximum = 65535,
        },
        resizable = {
          title = 'True to allow window size change',
          type = 'boolean',
          default = true
        },
        ['debug'] = {
          title = 'Enables the browser devtools',
          type = 'boolean',
          default = false
        },
      }
    }
  }
}

local config = tables.createArgumentTable(system.getArguments(), {
  configPath = 'config',
  emptyPath = 'url',
  helpPath = 'help',
  logPath = 'log-level',
  aliases = {
    h = 'help',
    s = 'search-url',
    t = 'webview.title',
    width = 'webview.width',
    height = 'webview.height',
    r = 'webview.resizable',
    d = 'webview.debug',
    ll = 'log-level',
  },
  schema = CONFIG_SCHEMA
})

local dataUrl = config.url
if not dataUrl then
  dataUrl = WebView.toDataUrl([[<!DOCTYPE html>
<html><body>
<input id="search" type="text" placeholder="Search or enter address" onkeypress="search(event)" style="margin-left: 20%; width: 60%;" />
<button title="Go" onclick="go()">&#x1f50d;</button>
<script>
function go() {
  var location = document.getElementById('search').value;
  try {
    new URL(location);
  } catch (e) {
    location = ']]..config['search-url']..[[' + encodeURIComponent(location);
  }
  window.location = location;
}
function search(event) {
  if (event.key === 'Enter') {
    go();
  }
}
</script>
</body></html>
]])
end

local webview = WebView:new(dataUrl, config.webview)
logger:fine('Enters WebView loop')
webview:loop()
logger:fine('WebView loop ended')
