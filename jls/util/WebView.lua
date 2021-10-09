--- Provide WebView class.
-- @module jls.util.WebView

local webviewLib = require('webview')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local Thread = require('jls.lang.Thread')
local Channel = require('jls.util.Channel')

--- The WebView class.
-- @type WebView
return class.create(function(webView)

  --- Creates a new WebView.
  -- @tparam string url the URL of the resource to be viewed.
  -- @tparam[opt] string title the title of the window.
  -- @tparam[opt] number width the width of the opened window.
  -- @tparam[opt] number height the height of the opened window.
  -- @tparam[opt] boolean resizable true if the opened window could be resized.
  -- @tparam[opt] boolean debug true to enable devtools.
  -- @function WebView:new
  function webView:initialize(url, title, width, height, resizable, debug)
    self._webview = webviewLib.new(url, title, width, height, resizable, debug)
  end

  function webView:checkAvailable()
    if not self._webview then
      error('WebView not available')
    end
  end

  --- Processes the webview event loop.
  -- This function will block.
  -- @tparam[opt] string mode the loop mode, default, once or nowait.
  function webView:loop(mode)
    self:checkAvailable()
    local r = webviewLib.loop(self._webview, mode)
    if r ~= 0 then
      self._webview = nil
    end
    return r
  end

  --- Registers the specified function to be called from the web page.
  -- The JavaScript syntax is window.external.invoke("string value");
  -- @tparam function cb The callback to register.
  function webView:callback(cb)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:callback('..tostring(cb)..')')
    end
    self:checkAvailable()
    webviewLib.callback(self._webview, cb)
  end

  --- Evaluates the specified JavaScript code in the web page.
  -- @tparam string js The JavaScript code to evaluate.
  function webView:eval(js)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:eval('..tostring(js)..')')
    end
    self:checkAvailable()
    webviewLib.eval(self._webview, js, true)
  end

  --- Sets the webview fullscreen.
  -- @tparam boolean fullscreen true to switch the webview to fullscreen.
  function webView:fullscreen(fullscreen)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:fullscreen()')
    end
    self:checkAvailable()
    webviewLib.fullscreen(self._webview, fullscreen)
  end

  --- Sets the webview title.
  -- @tparam string title The webview title to set.
  function webView:title(title)
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:title('..tostring(title)..')')
    end
    self:checkAvailable()
    webviewLib.title(self._webview, title)
  end

  --- Terminates the webview.
  function webView:terminate()
    if logger:isLoggable(logger.FINE) then
      logger:fine('webView:terminate()')
    end
    local wv = self._webview
    if wv then
      self._webview = nil
      webviewLib.terminate(wv, true)
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
@tparam[opt] boolean debug true to enable devtools.
@usage
local WebView = require('jls.util.WebView')
WebView.openSync('https://www.lua.org/')
]]
  function WebView.openSync(url, title, width, height, resizable, debug)
    WebView:new(url, title, width, height, resizable, debug):loop()
  end

  function WebView._threadChannelOnlyFunction(webviewAsString, channelName, chunk, data)
    if event:loopAlive() then
      error('event loop is alive')
    end
    local fn, err = load(chunk, nil, 'b')
    if not fn then
      error('Unable to load chunk due to "'..tostring(err)..'"')
    end
    local channel = Channel:new()
    channel:connect(channelName):catch(function(reason)
      logger:fine('Unable to connect WebView thread due to '..tostring(reason))
      channel = nil
    end)
    event:loop() -- wait for connection
    if not channel then
      error('Unable to connect WebView thread on "'..tostring(channelName)..'"')
    end
    local webview = class.makeInstance(WebView)
    webview._channel = channel
    webview._webview = webviewLib.fromstring(webviewAsString)
    function webview:callback(cb)
      webview._cb = cb
    end
    channel:receiveStart(function(message)
      if webview._cb then
        webview._cb(message)
      end
    end)
    fn(webview, data)
    event:loop()
  end

  -- We need to keep a reference to the thread webview to avoid GC
  local WEBVIEW_THREAD_MAP = {}

  local function registerWebViewThread(thread, webview)
    webview._thread = thread
    WEBVIEW_THREAD_MAP[thread] = webview
    thread:ended():finally(function()
      logger:fine('webview thread ended')
      WEBVIEW_THREAD_MAP[thread] = nil
    end)
  end

  function WebView.openWithThread(url, title, width, height, resizable, debug, fn, data)
    if type(fn) ~= 'function' then
      error('Invalid function argument')
    end
    local wv = webviewLib.allocate(url, title, width, height, resizable, debug)
    local channelServer = Channel:new()
    local acceptPromise = channelServer:acceptAndClose()
    return channelServer:bind():next(function()
      local channelName = channelServer:getName()
      local thread = Thread:new(function(...)
        local WV = require('jls.util.WebView')
        WV._threadChannelOnlyFunction(...)
      end)
      thread:start(webviewLib.asstring(wv), channelName, string.dump(fn), data)
      return acceptPromise
    end):next(function(channel)
      webviewLib.callback(wv, function(message)
        channel:sendMessage(message, false)
      end)
      webviewLib.init(wv)
      channel:onClose():next(function()
        if wv then
          webviewLib.terminate(wv)
        end
      end)
      webviewLib.loop(wv) -- Will block
      webviewLib.clean(wv)
      wv = nil
      channel:close(false)
    end)
  end

  function WebView._threadChannelFunction(webviewAsString, channelName)
    if event:loopAlive() then
      error('event loop is alive')
    end
    local wv = webviewLib.fromstring(webviewAsString)
    local channel = Channel:new()
    channel:connect(channelName):catch(function(reason)
      logger:fine('Unable to connect WebView thread due to '..tostring(reason))
      channel = nil
    end)
    event:loop() -- wait for connection
    if not channel then
      error('Unable to connect WebView thread on "'..tostring(channelName)..'"')
    end
    webviewLib.callback(wv, function(message)
      channel:sendMessage(message, false)
    end)
    webviewLib.init(wv)
    channel:onClose():next(function()
      if wv then
        webviewLib.terminate(wv)
      end
    end)
    webviewLib.loop(wv)
    webviewLib.clean(wv)
    wv = nil
    channel:close(false)
    event:loop()
  end

  function WebView.openInThread(url, title, width, height, resizable, debug)
    local webview = class.makeInstance(WebView)
    function webview:callback(cb)
      webview._cb = cb
    end
    local channelServer = Channel:new()
    local acceptPromise = channelServer:acceptAndClose()
    return channelServer:bind():next(function()
      local channelName = channelServer:getName()
      local thread = Thread:new(function(...)
        local WV = require('jls.util.WebView')
        WV._threadChannelFunction(...)
      end)
      local wv = webviewLib.allocate(url, title, width, height, resizable, debug)
      thread:start(webviewLib.asstring(wv), channelName)
      registerWebViewThread(thread, webview)
      webview._webview = wv
      return acceptPromise
    end):next(function(channel)
      webview._channel = channel
      channel:receiveStart(function(message)
        if webview._cb then
          webview._cb(message)
        end
      end)
      --channel:onClose():next(function() webview:terminate() end)
      return webview
    end)
  end

  function WebView._threadOpenFunction(webviewAsString, chunk, data)
    local wv = webviewLib.fromstring(webviewAsString)
    local webview = class.makeInstance(WebView)
    webview._webview = wv
    webviewLib.init(wv)
    if chunk then
      local fn, err = load(chunk, nil, 'b')
      if fn then
        fn(webview, data)
      else
        error('Unable to load chunk due to "'..tostring(err)..'"')
      end
    end
    webviewLib.loop(wv)
    webviewLib.clean(wv)
  end

  --[[--
Opens the specified URL in a new window.
Opening a webview in a dedicated thread may not be supported on all platform.
@tparam string url the URL of the resource to be viewed.
@tparam[opt] string title the title of the window.
@tparam[opt] number width the width of the opened window.
@tparam[opt] number height the height of the opened window.
@tparam[opt] boolean resizable true if the opened window could be resized.
@tparam[opt] boolean debug true to enable devtools.
@tparam[opt] function fn a function to be called in the webview context.
@tparam[opt] string data the data to be passed to the function as a string.
@treturn jls.lang.Thread the webview started thread.
@treturn jls.util.WebView the created webview.
]]
  function WebView.open(url, title, width, height, resizable, debug, fn, data)
    local webview = class.makeInstance(WebView)
    function webview:callback(cb)
      error('The WebView callback is not avaible')
    end
    local wv = webviewLib.allocate(url, title, width, height, resizable, debug)
    webview._webview = wv
    local thread = Thread:new(function(...)
      local WV = require('jls.util.WebView')
      WV._threadOpenFunction(...)
    end)
    local chunk
    if type(fn) == 'function' then
      chunk = string.dump(fn)
    end
    thread:start(webviewLib.asstring(webview._webview), chunk, data)
    registerWebViewThread(thread, webview)
    return thread, webview
  end

  function WebView.toDataUrl(content)
    local data = string.gsub(content, "[ %c!#$%%&'()*+,/:;=?@%[%]]", function(c)
      return string.format('%%%02X', string.byte(c))
    end)
    return 'data:text/html,'..data
  end

end)
