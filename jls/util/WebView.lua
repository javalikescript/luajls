--- Provide WebView class.
-- @module jls.util.WebView

local webviewLib = require('webview')
local luvLib = require('luv')

local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger') -- :getClass():new(0)

--- The WebView class.
-- @type WebView
return require('jls.lang.class').create(function(webView)

  --- Creates a new WebView.
  -- @function WebView:new
  function webView:initialize()
    self._waitPromise = nil
    self._webview = nil
    self._async = nil
    self._thread = nil
  end

  --[[--
Opens the specified URL in a new window.
@tparam string url the URL of the resource to be viewed.
@tparam[opt] string title the title of the window.
@tparam[opt] number width the width of the opened window.
@tparam[opt] number height the height of the opened window.
@tparam[opt] boolean resizable true if the opened window could be resized.
@treturn jls.lang.Promise a promise that resolves once the webview is available.
@usage
local WebView = require('jls.util.WebView')
WebView:new():open('https://www.lua.org/')
]]
  function webView:open(url, title, width, height, resizable)
    local openPromise, openCallback = Promise.createWithCallback()
    local waitPromise, waitCallback = Promise.createWithCallback()
    self._waitPromise = waitPromise
    self._async = luvLib.new_async(function(err, alive, webview)
      logger:fine('webView:open() async received')
      if alive then
        if webview then
          self._webview = webview
        end
        openCallback(nil, self)
        logger:fine('webView:open() open resolved')
        openCallback = nil
        return
      end
      self._webview = nil
      self._thread:join()
      logger:fine('webView:open() thread joined')
      luvLib.sleep(100)
      waitCallback(err)
      logger:fine('webView:open() wait resolved')
    end)
    self._thread = luvLib.new_thread(function(async, logLevel, url, title, width, height, resizable)
      local logger
      if logLevel then
        logger = require('jls.lang.logger'):getClass():new(logLevel)
      end
      local webviewLib = require('webview')
      local luvLib = require('luv')
      
      local webview = webviewLib.new(url, title, width, height, resizable)
      if logger then logger:fine('webView:open() webview created') end
      async:send(nil, true, webviewLib.lighten(webview)) -- the webview is closed
      luvLib.sleep(10)
      if logger then logger:fine('webView:open() thread looping') end
      while not webviewLib.loop(wv, true) do end
      if logger then logger:fine('webView:open() thread loop ended') end
      async:send() -- the webview is closed
      if logger then logger:fine('webView:open() thread async sent') end
      luvLib.sleep(100)
      async:close()
      if logger then logger:fine('webView:open() thread async closed') end
    end, self._async, logger:isLoggable(logger.FINE) and logger:getLevel(), url, title, width, height, resizable)
    return openPromise
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

  function webView:isAlive()
    return self._webview ~= nil
  end

  --- Waits for the webview to terminate.
  -- @treturn jls.lang.Promise a promise that resolves once the webview is closed.
  function webView:wait()
    return self._waitPromise
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
@treturn jls.lang.Promise a promise that resolves once the webview is available.
@usage
local WebView = require('jls.util.WebView')
WebView.open('https://www.lua.org/')
]]
  function WebView.open(url, title, width, height, resizable)
    return WebView:new():open(url, title, width, height, resizable)
  end

end)
