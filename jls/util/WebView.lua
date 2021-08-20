--- Provide WebView class.
-- @module jls.util.WebView

local webviewLib = require('webview')

local class = require('jls.lang.class')
local Thread = require('jls.lang.Thread')
local logger = require('jls.lang.logger')

--- The WebView class.
-- @type WebView
return class.create(function(webView)

  --- Creates a new WebView.
  -- @tparam string url the URL of the resource to be viewed.
  -- @tparam[opt] string title the title of the window.
  -- @tparam[opt] number width the width of the opened window.
  -- @tparam[opt] number height the height of the opened window.
  -- @tparam[opt] boolean resizable true if the opened window could be resized.
  -- @function WebView:new
  function webView:initialize(url, title, width, height, resizable)
    self._webview = webviewLib.new(url, title, width, height, resizable)
  end

  --- Processes the webview event loop.
  -- This function will block.
  -- @tparam[opt] string mode the loop mode, default, once or nowait.
  function webView:loop(mode)
    if self._webview then
      local r = webviewLib.loop(self._webview, mode)
      if r ~= 0 then
        self._webview = nil
      end
      return r
    end
  end

  --- Registers the specified function to be called from the web page.
  -- The JavaScript syntax is window.external.invoke("string value");
  -- @tparam function cb The callback to register.
  function webView:callback(cb)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:callback('..tostring(cb)..')')
    end
    if self._webview then
      webviewLib.callback(self._webview, cb)
    end
  end

  --- Evaluates the specified JavaScript code in the web page.
  -- @tparam string js The JavaScript code to evaluate.
  function webView:eval(js)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:eval('..tostring(js)..')')
    end
    if self._webview then
      webviewLib.eval(self._webview, js, true)
    end
  end

  --- Sets the webview fullscreen.
  -- @tparam boolean fullscreen true to switch the webview to fullscreen.
  function webView:fullscreen(fullscreen)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:fullscreen()')
    end
    if self._webview then
      webviewLib.fullscreen(self._webview, fullscreen)
    end
  end

  --- Sets the webview title.
  -- @tparam string title The webview title to set.
  function webView:title(title)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:title('..tostring(title)..')')
    end
    if self._webview then
      webviewLib.title(self._webview, title)
    end
  end

  --- Terminates the webview.
  function webView:terminate()
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:terminate()')
    end
    if self._webview then
      webviewLib.terminate(self._webview, true)
    end
  end

end, function(WebView)

  --[[--
Opens the specified URL in a new window and returns when the window has been closed.
@tparam string url the URL of the resource to be viewed.
@tparam[opt] string title the title of the window.
@tparam[opt] number width the width of the opened window.
@tparam[opt] number height the height of the opened window.
@tparam[opt] boolean resizable true if the opened window could be resized.
@usage
local WebView = require('jls.util.WebView')
WebView.openSync('https://www.lua.org/')
]]
  function WebView.openSync(url, title, width, height, resizable)
    WebView:new(url, title, width, height, resizable):loop()
  end

  -- We need to keep a reference to the thread webview to avoid GC
  local WEBVIEW_THREAD_MAP = {}

  --[[--
Opens the specified URL in a new window.
Opening a webview in a dedicated thread may not be supported on all platform.
@tparam string url the URL of the resource to be viewed.
@tparam[opt] string title the title of the window.
@tparam[opt] number width the width of the opened window.
@tparam[opt] number height the height of the opened window.
@tparam[opt] boolean resizable true if the opened window could be resized.
@treturn jls.lang.Thread the webview started thread.
@treturn jls.util.WebView the created webview.
]]
  function WebView.open(url, title, width, height, resizable, debug)
    local webview = class.makeInstance(WebView)
    webview._webview = webviewLib.allocate(url, title, width, height, resizable, debug)
    local thread = Thread:new(function(ws)
      local wvLib = require('webview')
      local w = wvLib.fromstring(ws)
      wvLib.init(w)
      wvLib.loop(w)
    end)
    thread:start(webviewLib.asstring(webview._webview))
    WEBVIEW_THREAD_MAP[thread] = webview
    thread:ended():finally(function()
      WEBVIEW_THREAD_MAP[thread] = nil
    end)
    return thread, webview
  end

end)
