--- Provide WebView class.
-- @module jls.util.WebView

local webviewLib = require('webview')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local Thread = require('jls.lang.Thread')

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
@tparam[opt] boolean debug true to enable devtools.
@usage
local WebView = require('jls.util.WebView')
WebView.openSync('https://www.lua.org/')
]]
  function WebView.openSync(url, title, width, height, resizable, debug)
    WebView:new(url, title, width, height, resizable, debug):loop()
  end

  local function readStream(stream, onMessage)
    local buffer = ''
    stream:readStart(function(err, data)
      if logger:isLoggable(logger.FINEST) then
        logger:finest('webview thread pipe read "'..tostring(err)..'", #'..tostring(data and #data))
      end
      if err then
      elseif data then
        buffer = buffer..data
        while true do
          local bufferLength = #buffer
          if bufferLength < 5 then
            break
          end
          local messageType, remainingLength, offset = string.unpack('>BI4', buffer)
          local messageLength = offset - 1 + remainingLength
          if bufferLength < messageLength then
            break
          end
          local remainingBuffer
          if bufferLength == messageLength then
            remainingBuffer = ''
          else
            remainingBuffer = string.sub(buffer, messageLength + 1)
            buffer = string.sub(buffer, 1, messageLength)
          end
          local payload = string.sub(buffer, offset)
          if logger:isLoggable(logger.FINEST) then
            logger:finest('webview thread pipe type '..tostring(messageType)..', payload "'..tostring(payload)..'"')
          end
          onMessage(messageType, payload)
          buffer = remainingBuffer
        end
        return
      end
      stream:close():next(function()
        logger:finer('webview thread client pipe closed')
      end)
    end)
  end

  local function writeStream(stream, messageType, payload)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('webview pipe sending '..tostring(messageType)..' "'..tostring(payload)..'"')
    end
    local writeCallback = false
    if logger:isLoggable(logger.FINE) then
      writeCallback = function(reason)
        if reason then
          logger:warn('webview pipe send error "'..tostring(reason)..'"')
        elseif logger:isLoggable(logger.FINEST) then
          logger:finest('webview pipe payload sent '..tostring(messageType))
        end
      end
    end
    stream:write(string.pack('>Bs4', messageType, payload or ''), writeCallback)
  end

  local function createStreamCallback(stream)
    return function(payload)
      if logger:isLoggable(logger.FINER) then
        if logger:isLoggable(logger.FINEST) then
          logger:finest('callback(#'..tostring(payload and #payload)..'"'..tostring(payload)..'")')
        else
          logger:finer('callback(#'..tostring(payload and #payload)..')')
        end
      end
      writeStream(stream, 1, payload)
    end
  end

  function WebView._threadStreamFunction(webviewAsString, inThread, streamId, useTcp)
    if event:loopAlive() then
      error('event loop is alive')
    end
    local wv = webviewLib.fromstring(webviewAsString)
    local stream, connectPromise
    if useTcp then
      local TcpClient = require('jls.net.TcpClient')
      stream = TcpClient:new()
      connectPromise = stream:connect(nil, math.tointeger(streamId))
    else
      local Pipe = require('jls.io.Pipe')
      stream = Pipe:new()
      connectPromise = stream:connect(streamId)
    end
    connectPromise:next(function()
    end, function(reason)
      logger:fine('Unable to connect WebView thread due to '..tostring(reason))
      stream = nil
    end)
    event:loop() -- wait for connection
    if not stream then
      error('Unable to connect WebView thread on "'..tostring(streamId)..'"')
    end
    if inThread then
      webviewLib.callback(wv, createStreamCallback(stream))
      webviewLib.init(wv)
      writeStream(stream, 0)
      webviewLib.loop(wv)
      writeStream(stream, 2)
      webviewLib.clean(wv)
      stream:close(false)
      event:loop()
      return
    end
    local webview = class.makeInstance(WebView)
    webview._webview = wv
    function webview:callback(cb)
      webview._cb = cb
    end
    readStream(stream, function(messageType, payload)
      if messageType == 1 then
        if webview._cb then
          webview._cb(payload)
        end
      elseif messageType == 2 then
        stream:close(false)
      elseif messageType == 3 then
        local chunk, mode, value = string.unpack('>s4s1s4', payload)
        local fn, lerr = load(chunk, nil, mode)
        if fn then
          fn(webview, value)
        else
          logger:warn('Unable to load due to "'..tostring(lerr)..'", chunk: "'..tostring(chunk)
            ..'", mode: "'..tostring(mode)..'", value: "'..tostring(value)..'"')
        end
      elseif messageType == 0 then
        -- initialized
      else
        logger:warn('webview pipe invalid message type '..tostring(messageType))
      end
    end)
    --event:setInterval(function() logger:fine('webview thread looping') end, 1000)
    event:loop()
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

  -- We need to keep a reference to the thread webview to avoid GC
  local WEBVIEW_THREAD_MAP = {}

  local function threadResult(thread, webview)
    webview._thread = thread
    WEBVIEW_THREAD_MAP[thread] = webview
    thread:ended():finally(function()
      logger:fine('webview thread ended')
      WEBVIEW_THREAD_MAP[thread] = nil
    end)
    return thread, webview
  end

  local USE_TCP = os.getenv('JLS_WEBVIEW_USE_TCP') ~= nil

  local function openThreadStream(threadMode, url, title, width, height, resizable, debug)
    if event:loopAlive() then
      error('event loop is alive')
    end
    local thread = Thread:new(function(...)
      local WV = require('jls.util.WebView')
      WV._threadStreamFunction(...)
    end)
    local wv = webviewLib.allocate(url, title, width, height, resizable, debug)
    local server, stream, streamId, bindPromise
    if USE_TCP then
      local TcpServer = require('jls.net.TcpServer')
      server = TcpServer:new()
      streamId = 0
      bindPromise = server:bind(nil, 0):next(function()
        streamId = select(2, server:getLocalName())
      end)
    else
      local Pipe = require('jls.io.Pipe')
      streamId = Pipe.normalizePipeName('WebView', true)
      server = Pipe:new()
      bindPromise = server:bind(streamId)
    end
    function server:onAccept(s)
      stream = s
      server:close(false)
      event:stop() -- thread stream connected
    end
    bindPromise:next(function()
      if logger:isLoggable(logger.FINE) then
        logger:fine('webview server bound on "'..tostring(streamId)..'"')
      end
      thread:start(webviewLib.asstring(wv), threadMode, streamId, false)
    end, function(reason)
      logger:fine('webview bind error "'..tostring(reason)..'"')
      event:stop()
    end)
    event:loop() -- wait for thread stream connection
    if not stream then
      error('Unable to connect WebView stream on "'..tostring(streamId)..'"')
    end
    return wv, thread, stream
  end

  function WebView.openInThread(url, title, width, height, resizable, debug, fn, data)
    local wv, thread, stream = openThreadStream(true, url, title, width, height, resizable, debug)
    local webview = class.makeInstance(WebView)
    webview._webview = wv
    function webview:callback(cb)
      webview._cb = cb
    end
    if fn then
      fn(webview, data)
    end
    readStream(stream, function(messageType, payload)
      if messageType == 1 then
        if webview._cb then
          webview._cb(payload)
        end
      elseif messageType == 2 then
        stream:close(false)
      elseif messageType == 0 then
        -- initialized
      else
        logger:warn('webview thread pipe invalid message type '..tostring(messageType))
      end
    end)
    webview._stream = stream
    return threadResult(thread, webview)
  end

  function WebView.openWithThread(url, title, width, height, resizable, debug, fn, data)
    local wv, _, stream = openThreadStream(false, url, title, width, height, resizable, debug)
    webviewLib.callback(wv, createStreamCallback(stream))
    webviewLib.init(wv)
    writeStream(stream, 0)
    if fn then
      writeStream(stream, 3, string.pack('>s4s1s4', string.dump(fn), 'b', data or ''))
    end
    webviewLib.loop(wv)
    writeStream(stream, 2)
    stream:close(false)
    event:loop()
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
@treturn jls.lang.Thread the webview started thread.
@treturn jls.util.WebView the created webview.
]]
  function WebView.open(url, title, width, height, resizable, debug, fn, data)
    local webview = class.makeInstance(WebView)
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
    return threadResult(thread, webview)
  end

end)
