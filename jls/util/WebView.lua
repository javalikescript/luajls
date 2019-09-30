--- Provide WebView class.
-- @module jls.util.WebView

local webviewLib = require('webview')
local luvLib = require('jls.lang.loader').tryRequire('luv')

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')

function webViewInit(webView, w)
  webView._exitPromise, webView._exitCallback = Promise.createWithCallback()
  webView._webview = w
end

function webViewExited(webView, err)
  webView._webview = nil
  webView._exitCallback(err)
end

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
    webViewInit(self, webviewLib.new(url, title, width, height, resizable))
  end

  --- Processes the webview event loop.
  -- @tparam[opt] boolean blocking true to blockt.
  -- @tparam[opt] boolean wait true to wait the webview to terminate.
  function webView:loop(blocking, wait)
    if self._webview then
      local r = webviewLib.loop(self._webview, blocking, wait)
      if r ~= 0 then
        webViewExited(self)
      end
      return r
    end
  end

  --- Registers a function that could be called from the web page.
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

  --- Evaluates the JavaScript code in the web page.
  -- @tparam string js The JavaScript code to evaluate.
  function webView:eval(js)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:eval('..tostring(js)..')')
    end
    if self._webview then
      webviewLib.eval(self._webview, js, true)
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

  --- Tells wether or not the webview is terminated.
  function webView:isAlive()
    return self._webview ~= nil
  end

  --- Waits for the webview to terminate.
  -- @treturn jls.lang.Promise a promise that resolves once the webview is closed.
  function webView:wait()
    return self._exitPromise
  end

end, function(WebView)

  --[[--
Opens the specified URL in a new window.
@function WebView.open
@tparam string url the URL of the resource to be viewed.
@tparam[opt] string title the title of the window.
@tparam[opt] number width the width of the opened window.
@tparam[opt] number height the height of the opened window.
@tparam[opt] boolean resizable true if the opened window could be resized.
@usage
local WebView = require('jls.util.WebView')
WebView.open('https://www.lua.org/')
]]
  function WebView.open(url, title, width, height, resizable)
    WebView:new(url, title, width, height, resizable):loop(true, true)
  end

  --[[--
Opens the specified URL in a new window using a dedicated thread.
@function WebView.open
@tparam string url the URL of the resource to be viewed.
@tparam[opt] string title the title of the window.
@tparam[opt] number width the width of the opened window.
@tparam[opt] number height the height of the opened window.
@tparam[opt] boolean resizable true if the opened window could be resized.
@treturn jls.lang.Promise a promise that resolves once the webview is available.
@usage
local WebView = require('jls.util.WebView')
WebView.open('https://www.lua.org/')
]]
  function WebView.openInThread(url, title, width, height, resizable)
    local openPromise, resolveOpen, rejectOpen = Promise.createWithCallbacks()
    local thread, webview
    local async = luvLib.new_async(function(err, w)
      logger:fine('webView:open() async received')
      if w then
        --webview = WebView:new(w)
        webview = class.makeInstance(WebView)
        webViewInit(webview, w)
        resolveOpen(webview)
        logger:fine('webView:open() open resolved')
        resolveOpen = nil
        return
      end
      thread:join()
      logger:fine('webView:open() thread joined')
      luvLib.sleep(100)
      webViewExited(webview, err)
      logger:fine('webView:open() wait resolved')
    end)
    thread = luvLib.new_thread(function(async, logLevel, url, title, width, height, resizable)
      local logger
      if logLevel then
        logger = require('jls.lang.logger'):getClass():new(logLevel)
      end
      local webviewLib = require('webview')
      local luvLib = require('luv')
      local w = webviewLib.new(url, title, width, height, resizable)
      if logger then logger:fine('webView:open() webview created') end
      async:send(nil, webviewLib.lighten(w)) -- the webview is closed
      luvLib.sleep(10)
      if logger then logger:fine('webView:open() thread looping') end
      webviewLib.loop(w, true, true)
      if logger then logger:fine('webView:open() thread loop ended') end
      async:send() -- the webview is closed
      if logger then logger:fine('webView:open() thread async sent') end
      luvLib.sleep(100)
      async:close()
      if logger then logger:fine('webView:open() thread async closed') end
    end, async, logger:isLoggable(logger.FINE) and logger:getLevel(), url, title, width, height, resizable)
    return openPromise
  end

end)
