--- Represents a thread of execution.
-- @module jls.lang.Thread
-- @pragma nostrip

local luvLib = require('luv')

--export JLS_REQUIRES=\!luv
--lua -e "require('jls.lang.Thread'):new(function(...) print('Thread args', ...); require('jls.lang.system').sleep(300); return 'Thread', 'result'; end):start('John'):ended():next(function(results) print('Done', table.unpack(results)) end); print('Started'); require('jls.lang.event'):loop()"

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local CODEC_MODULE_NAME = 'jls.util.base64'
local codec = require(CODEC_MODULE_NAME)

--- A Thread class.
-- @type Thread
return require('jls.lang.class').create(function(thread)

  --- Creates a new Thread.
  -- @tparam[opt] function fn the function to execute in this thread.
  -- @function Thread:new
  function thread:initialize(fn)
    self:setFunction(fn)
  end

  local EMPTY_FUNCTION = function() end

  --- Sets this Thread function.
  -- The function will receive the arguments passed in the start call.
  -- The function may return values.
  -- Start arguments and return values shall be primitive type: string, number, boolean or nil
  -- @tparam[opt] function fn the function to execute in this thread.
  function thread:setFunction(fn)
    if type(fn) == 'function' then
      self.fn = fn
    else
      self.fn = EMPTY_FUNCTION
    end
  end

  --- Starts this Thread.
  -- The arguments will be passed to the thread function.
  -- @treturn jls.lang.Thread this thread.
  function thread:start(...)
    local endPromise, endCallback = Promise.createWithCallback()
    local async
    async = luvLib.new_async(function(err, ...)
      self.t = nil
      self._endPromise = nil
      if err then
        endCallback(err)
      else
        local count = select('#', ...)
        if count <= 0 then
          endCallback()
        elseif count == 1 then
          endCallback(nil, (...))
        else
          endCallback(nil, table.pack(...))
        end
      end
      async:close()
    end)
    local chunk = string.dump(self.fn)
    local ec = codec.encode(chunk)
    local code = "local chunk = require('"..CODEC_MODULE_NAME.."').decode('"..ec.."');"..
    [[
      local fn = load(chunk, nil, 'b')
      local async = (...)
      local results = table.pack(pcall(fn, select(2, ...)))
      local status = table.remove(results, 1)
      if status then
        async:send(nil, table.unpack(results))
      else
        async:send(results[1] or 'Error in thread')
      end
    ]]
    --logger:finest('code: [['..code..']]')
    local fn = load(code, nil, 't')
    self.t = luvLib.new_thread(fn, async, ...)
    self._endPromise = endPromise
    return self
  end

  --- Returns a promise that resolves once this thread is terminated.
  -- @treturn jls.lang.Promise a promise that resolves once this thread is terminated.
  function thread:ended()
    if self.t and self._endPromise then
      return self._endPromise
    end
    return Promise.reject()
  end

  --- Returns true if this thread is alive.
  -- @treturn boolean true if this thread is alive.
  function thread:isAlive()
    return self.t ~= nil
  end

  --- Blocks until this thread terminates.
  function thread:join()
    if self.t then
      self.t:join()
      self.t = nil
      self._endPromise = nil
    end
  end

end)