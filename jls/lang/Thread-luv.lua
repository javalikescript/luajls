--- Represents a thread of execution.
-- @module jls.lang.Thread
-- @pragma nostrip

local luvLib = require('luv')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')

local tables = require('jls.lang.loader').tryRequire('jls.util.tables')

--- A Thread class.
-- @type Thread
return require('jls.lang.class').create(function(thread)

  --- Creates a new Thread.
  -- @tparam[opt] function fn the function to execute in this thread.
  -- The function will receive the arguments passed in the start call and may return a single value.
  -- Start arguments and return values shall be primitive type: string, number, boolean or nil
  -- The function cannot share variables with the current thread, must not have upvalues.
  -- @function Thread:new
  function thread:initialize(fn)
    self:setFunction(fn)
  end

  local EMPTY_FUNCTION = function() end

  -- Sets this Thread function.
  -- @tparam[opt] function fn the function to execute in this thread.
  function thread:setFunction(fn)
    if self.t then
      error('thread is runnning')
    end
    if type(fn) == 'function' then
      self.fn = fn
    else
      self.fn = EMPTY_FUNCTION
    end
  end

  --- Starts this Thread.
  -- The arguments will be passed to the thread function.
  -- If the thread is already running then nothing is done.
  -- @param[opt] ... The thread function arguments.
  -- @treturn jls.lang.Thread this thread.
  function thread:start(...)
    if self.t then
      return self
    end
    local endPromise, endCallback = Promise.createWithCallback()
    self._endPromise = endPromise
    self._async = luvLib.new_async(function(reason, value, tableValue)
      if logger:isLoggable(logger.FINE) then
        logger:fine('Thread function done: '..tostring(reason)..', "'..tostring(value)..'"')
      end
      if tableValue == true and tables then
        value = tables.parse(value)
      end
      endCallback(reason, value)
      self._async:close()
      self.t:join()
      self._async = nil
      self.t = nil
    end)
    -- check if the function has upvalues
    if logger:isLoggable(logger.FINE) then
      local name = debug and debug.getupvalue(self.fn, 2)
      if name ~= nil then
        logger:fine('Thread function upvalues ('..tostring(name)..', ...) will be nil')
      end
    end
    local chunkAsString = string.format('%q', string.dump(self.fn))
    local code = "require('jls.lang.Thread')._main("..chunkAsString..", ...)"
    --logger:finest('code: [['..code..']]')
    local chunk = string.dump(load(code, nil, 't'))
    self.t = luvLib.new_thread(chunk, self._async, ...)
    return self
  end

  --- Returns a promise that resolves once this thread is terminated.
  -- @treturn jls.lang.Promise a promise that resolves once this thread is terminated.
  function thread:ended()
    return self._endPromise or Promise.reject()
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
    end
  end

end, function(Thread)

  function Thread._main(chunk, ...)
    local fn = load(chunk, nil, 'b')
    local async = (...)
    local status, val, err = pcall(fn, select(2, ...))
    if status then
      if err then
        async:send(tostring(err))
      else
        local typ = type(val)
        if val == nil or typ == 'string' or typ == 'number' or typ == 'boolean' then
          async:send(nil, val)
        elseif typ == 'table' then
          if tables then
            async:send(nil, tables.stringify(val), true)
          else
            async:send(tostring(tables))
          end
        else
          async:send('Invalid thread function return type '..typ)
        end
      end
    else
      async:send(val or 'Unknown error in thread')
    end
  end

end)