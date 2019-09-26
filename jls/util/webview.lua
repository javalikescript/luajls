--- Provide webview.
-- @module jls.util.webview

local webviewLib = require('webview') -- to ensure that the module could be loaded
local luvLib = require('luv')
local Promise = require('jls.lang.Promise')
local logger = require('jls.lang.logger')

local webview = {}

--[[--
Opens the specified URL in a new window.
@tparam string url the URL of the resource to be viewed.
@tparam[opt] string title the title of the window.
@tparam[opt] number width the width of the opened window.
@tparam[opt] number height the height of the opened window.
@treturn jls.lang.Promise a promise that resolves once the webview window is closed.
@usage
local webview = require('jls.util.webview')
webview.open('https://en.m.wikipedia.org/wiki/Main_Page')
]]
function webview.open(url, title, width, height)
  logger:info('opening webview on '..url)
  return Promise:new(function(resolve, reject)
    local async, thread
    async = luvLib.new_async(function(err)
      logger:fine('async received')
      --luvLib.thread_join(thread)
      thread:join()
      logger:fine('thread joined')
      luvLib.sleep(100)
      if err then
        reject(err)
      else
        resolve()
      end
      logger:fine('webview.open resolved')
    end)
    thread = luvLib.new_thread(function(async, log, url, title, width, height)
      local webviewLib = require('webview')
      local luvLib = require('luv')
      if log then print('starting webview') end
      webviewLib.open(url, title, width, height)
      if log then print('webview ended') end
      async:send()
      luvLib.sleep(100)
      if log then print('async sent') end
      async:close()
      if log then print('async closed') end
    end, async, logger:isLoggable(logger.FINE), url, title, width, height)
  end)
end

return webview