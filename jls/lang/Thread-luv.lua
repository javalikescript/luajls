--- Represents a thread of execution.
-- @module jls.lang.Thread
-- @pragma nostrip

local luvLib = require('luv')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local tables = require("jls.util.tables")

--- A Thread class.
-- @type Thread
return require('jls.lang.class').create(function(thread)

  --- Creates a new Thread.
  -- @tparam[opt] function fn the function to execute in this thread.
  -- The function will receive the arguments passed in the start call.
  -- The function may return a single value.
  -- Start arguments and return values shall be primitive type: string, number, boolean or nil
  -- @function Thread:new
  function thread:initialize(fn)
    self:setFunction(fn)
  end

  local EMPTY_FUNCTION = function() end

  -- Sets this Thread function.
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
  -- If the thread is already running then nothing is done.
  -- @treturn jls.lang.Thread this thread.
  function thread:start(...)
    if self.t then
      return self
    end
    local endPromise, endCallback = Promise.createWithCallback()
    local async
    async = luvLib.new_async(function(valueType, value)
      self.t = nil
      self._endPromise = nil
      if valueType == 'error' then
        endCallback(value or 'Unknown error')
      elseif valueType == 'table' then
        endCallback(nil, tables.parse(value))
      else
        endCallback(nil, value)
      end
      async:close()
    end)
    -- check if the function has upvalues
    if logger:isLoggable(logger.FINE) then
      local name = debug and debug.getupvalue(self.fn, 2)
      if name ~= nil then
        logger:fine('Thread function upvalues ('..tostring(name)..', ...) will be nil')
      end
    end
    local chunk = string.dump(self.fn)
    local code = "local chunk = "..string.format('%q', chunk)..
    [[
      local fn = load(chunk, nil, 'b')
      local async = (...)
      local status, value = pcall(fn, select(2, ...))
      if status then
        if type(value) == 'table' then
          async:send('table', require("jls.util.tables").stringify(value))
        else
          async:send(nil, value)
        end
      else
        async:send('error', value)
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