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
  -- This function will block.
  -- @tparam[opt] string mode the loop mode, default, once or nowait.
  function webView:loop(mode)
    if self._webview then
      local r = webviewLib.loop(self._webview, mode)
      if r ~= 0 then
        webViewExited(self)
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

  --- Tells wether or not the webview is terminated.
  -- @treturn boolean true if the webview is alive.
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

  --[[--
Opens the specified URL in a new window.
Opening a webview in a dedicated thread may not be supported on all platform.
@tparam string url the URL of the resource to be viewed.
@tparam[opt] string title the title of the window.
@tparam[opt] number width the width of the opened window.
@tparam[opt] number height the height of the opened window.
@tparam[opt] boolean resizable true if the opened window could be resized.
@treturn jls.lang.Promise a promise that resolves once the webview is available.
]]
  function WebView.open(url, title, width, height, resizable)
    local openPromise, resolveOpen, rejectOpen = Promise.createWithCallbacks()
    local async, thread, webview
    async = luvLib.new_async(function(err, w)
      logger:fine('webView:open() async received')
      if w then
        webview = class.makeInstance(WebView)
        webViewInit(webview, webviewLib.fromstring(w))
        resolveOpen(webview)
        logger:fine('webView:open() open resolved')
        resolveOpen = nil
        return
      end
      thread:join()
      logger:fine('webView:open() thread joined')
      --luvLib.sleep(100)
      webViewExited(webview, err)
      logger:fine('webView:open() wait resolved')
      async:close()
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
      async:send(nil, webviewLib.asstring(w)) -- the webview is available
      if logger then logger:fine('webView:open() thread looping') end
      webviewLib.loop(w)
      if logger then logger:fine('webView:open() thread loop ended') end
      async:send() -- the webview is closed
      if logger then logger:fine('webView:open() thread async sent') end
      --luvLib.sleep(100)
      if logger then logger:fine('webView:open() thread async closed') end
    end, async, logger:isLoggable(logger.FINE) and logger:getLevel(), url, title, width, height, resizable)
    return openPromise
  end

end)
