--[[--
Represents a thread of execution.
The thread will call a Lua function.
The function cannot share variables with the current thread, i.e. must not have upvalues.
The function will load modules using the _package_ default values, except for _path_ and _cpath_.
The function arguments and return values shall be primitive type: _string_, _number_, _boolean_ or _nil_.

@module jls.lang.Thread
@pragma nostrip
]]

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Exception = require('jls.lang.Exception')
local Promise = require('jls.lang.Promise')

local tables
do
  local status, m = pcall(require, 'jls.util.tables')
  if status then
    tables = m
  end
end

local CHUNK_MAIN = string.dump(load([[
package.path = ...
package.cpath = select(2, ...)
return require('jls.lang.Thread')._main(select(3, ...))
]], 'thread', 't'))

--- A Thread class.
-- @type Thread
return class.create(function(thread)

  --- Creates a new Thread.
  -- @tparam[opt] function fn the function to execute in this thread.
  -- The function will receive the arguments passed in the start call and may return a single value.
  -- If the returned value is a promise then the event loop is called until the promise completes.
  -- Errors if any are wrapped into exceptions.
  -- @function Thread:new
  function thread:initialize(fn)
    self:setFunction(fn)
  end

  -- Sets this Thread function.
  -- @tparam[opt] function fn the function to execute in this thread.
  function thread:setFunction(fn)
    if self.t then
      error('thread is runnning')
    end
    if type(fn) == 'function' then
      self.fn = fn
    else
      self.fn = class.emptyFunction
    end
  end

  function thread:_arg(...)
    -- check if the function has upvalues
    if logger:isLoggable(logger.FINE) then
      local name = debug and debug.getupvalue(self.fn, 2)
      if name ~= nil then
        logger:fine('Thread function upvalues (%s, ...) will be nil', name)
      end
    end
    return CHUNK_MAIN, package.path, package.cpath, string.dump(self.fn), ...
  end

  --- Starts this Thread.
  -- The arguments will be passed to the thread function.
  -- If the thread is already running then nothing is done.
  -- @param[opt] ... The thread function arguments.
  -- @treturn jls.lang.Thread this thread.
  -- @function thread:start
  thread.start = class.notImplementedFunction

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
      self.t = nil
    end
  end

end, function(Thread)

  function Thread._main(chunk, ...)
    local fn = load(chunk, nil, 'b')
    local status, v, e = Exception.pcall(fn, ...)
    if status and v == nil and e then
      status, v = false, e
    end
    if status and Promise.isPromise(v) and Promise.pawait then
      status, v = Promise.pawait(v)
    end
    local vt
    local t = type(v)
    if t ~= 'nil' and t ~= 'string' and t ~= 'number' and t ~= 'boolean' then
      if t == 'table' and tables then
        if Exception:isInstance(v) then
          v = v:toJSON()
          vt = 2
        else
          vt = 1
        end
        v = tables.stringify(v, nil, true)
      else
        vt = 0
        v = tostring(v)
      end
    end
    return status, v, vt
  end

  function Thread._apply(resolve, reject, status, value, kind)
    logger:fine('Thread function done: %s, "%s", %s', status, value, kind)
    if type(kind) == 'number' and kind > 0 and tables then
      value = tables.parse(value)
      if kind == 2 then
        value = Exception.fromJSON(value)
      end
    end
    if status then
      resolve(value)
    else
      reject(value)
    end
  end

end)