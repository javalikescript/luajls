--[[--
Represents a thread of execution.
The thread will call a Lua function.
The function arguments and return values shall be primitive type: _string_, _number_, _boolean_ or _nil_.
The function cannot share variables with the current thread, i.e. must not have upvalues.
The _package_ curent values _path_, _cpath_ and _preload_ are transfered to the thread function.

@module jls.lang.Thread
@pragma nostrip
]]

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local Exception = require('jls.lang.Exception')
local Promise = require('jls.lang.Promise')

local tables
do
  local status, m = pcall(require, 'jls.util.tables')
  if status then
    tables = m
  end
end

local CHUNK_MAIN = string.dump(function(path, cpath, preloads, ...)
  if path then
    package.path = path
  end
  if cpath then
    package.cpath = cpath
  end
  if preloads then
    -- for 5.1 direct compatibility
    ---@diagnostic disable-next-line: deprecated
    local len, loadstr = string.len, loadstring or load
    local p, l = 1, len(preloads) - 5
    while p < l do
      local name, slen = string.match(preloads, '^([^%c]+)\23([1-9]%d*)\23', p)
      if name then
        p = p + len(name) + 1 + len(slen) + 1
        local pp = p + tonumber(slen)
        if string.byte(preloads, pp) ~= 23 then
          break
        end
        local chunk = string.sub(preloads, p, pp)
        p = pp + 1
        local fn = loadstr(chunk, name)
        if fn then
          package.preload[name] = fn
        else
          break
        end
      else
        break
      end
    end
  end
  local th = require('jls.lang.Thread')
  return th._main(...)
end)

--- A Thread class.
-- @type Thread
return class.create(function(thread)

  --- Creates a new Thread.
  -- @tparam[opt] function fn The function to execute in this thread.
  -- The function will receive the arguments passed in the start call and may return a single value.
  -- If the returned value is a promise then the event loop is called until the promise completes.
  -- Errors if any are wrapped into exceptions.
  -- @function Thread:new
  function thread:initialize(fn)
    self:setFunction(fn)
  end

  -- Sets this Thread function.
  -- @tparam[opt] function fn The function to execute in this thread
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

  function thread:setTransferPreload(value)
    self.preloads = value == true
    return self
  end

  function thread:_arg(...)
    -- Lua static uses package.searchers to provide bundled modules
    -- C modules will not be available
    local preloads
    if self.preloads then
      local t = {}
      for name, fn in pairs(package.preload) do
        local status, dump = pcall(string.dump, fn)
        if status and dump then
          table.insert(t, name)
          table.insert(t, #dump)
          table.insert(t, dump)
        end
      end
      if #t > 0 then
        table.insert(t, '')
        preloads = table.concat(t, '\23')
        logger:fine('preload size is %d', #preloads) -- 530k for jls
      end
    end
    -- check if the function has upvalues
    if logger:isLoggable(logger.FINE) then
      local name = debug and debug.getupvalue(self.fn, 2)
      if name ~= nil then
        logger:fine('Thread function upvalues (%s, ...) will be nil', name)
      end
    end
    return CHUNK_MAIN, package.path, package.cpath, preloads, string.dump(self.fn), ...
  end

  --- Starts this Thread.
  -- The arguments will be passed to the thread function.
  -- If the thread is already running then nothing is done.
  -- @param[opt] ... The thread function arguments
  -- @treturn jls.lang.Thread This thread
  -- @function thread:start
  thread.start = class.notImplementedFunction

  --- Returns a promise that resolves once this thread is terminated.
  -- @treturn jls.lang.Promise A promise that resolves once this thread is terminated
  function thread:ended()
    return self._endPromise or Promise.reject()
  end

  --- Returns true if this thread is alive.
  -- @treturn boolean true if this thread is alive
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
    if status and Promise.isPromise(v) then
      local eventStatus, event = pcall(require, 'jls.lang.event')
      if eventStatus then
        local p = v
        status, v = false, 'promise not fulfilled after loop'
        p:next(function(value)
          status, v = true, value
        end, function(reason)
          status, v = false, reason
        end)
        event:loop()
      else
        status, v = false, 'no event loop to fulfill promise'
      end
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