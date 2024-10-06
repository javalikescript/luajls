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

local CHUNK_MAIN = string.dump(function(sargs, ...)
  -- for 5.1 direct compatibility
  ---@diagnostic disable-next-line: deprecated
  local len, loadstr = string.len, loadstring or load
  local p = 1
  local path, cpath, slen = string.match(sargs, '^([^\23]*)\23([^\23]*)\23(%d+)\23', p)
  if not path then
    return false, 'corrupted args'
  end
  p = p + len(path) + 1 + len(cpath) + 1 + len(slen) + 1
  local pp = p + tonumber(slen)
  if string.byte(sargs, pp) ~= 23 then
    return false, 'corrupted args'
  end
  local chunk = string.sub(sargs, p, pp)
  p = pp + 1
  if path then
    package.path = path
  end
  if cpath then
    package.cpath = cpath
  end
  local l = len(sargs) - 5
  while p < l do
    path, slen = string.match(sargs, '^([^\23]+)\23(%d+)\23', p)
    if path then
      p = p + len(path) + 1 + len(slen) + 1
      pp = p + tonumber(slen)
      if string.byte(sargs, pp) ~= 23 then
        break
      end
      local dump = string.sub(sargs, p, pp)
      p = pp + 1
      local fn = loadstr(dump, path)
      if fn then
        package.preload[path] = fn
      else
        break
      end
    else
      break
    end
  end
  local th = require('jls.lang.Thread')
  return th._main(chunk, ...)
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
    local chunk = string.dump(self.fn)
    local targs = {}
    table.insert(targs, package.path or '')
    table.insert(targs, package.cpath or '')
    table.insert(targs, #chunk)
    table.insert(targs, chunk)
    if self.preloads then
      for name, fn in pairs(package.preload) do
        local status, dump = pcall(string.dump, fn)
        if status and dump then
          table.insert(targs, name)
          table.insert(targs, #dump)
          table.insert(targs, dump)
        end
      end
    end
    table.insert(targs, '')
    local sargs = table.concat(targs, '\23')
    logger:finer('thread %p args size is %d', self, #sargs) -- 530k for jls
    -- check if the function has upvalues
    if logger:isLoggable(logger.FINE) then
      local name = debug and debug.getupvalue(self.fn, 2)
      if name ~= nil then
        logger:fine('Thread function upvalues (%s, ...) will be nil', name)
      end
    end
    logger:finer('package path: "%s", cpath: "%s"', package.path, package.cpath)
    assert(1 + select('#', ...) <= 9, 'too many thread argument')
    return CHUNK_MAIN, sargs, ...
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
    local t = self.t
    if t then
      logger:fine('joining thread %p - %p', self, t)
      self.t = nil
      t:join()
      logger:fine('thread %p - %p joined', self, t)
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

  --- Returns the specified function without upvalues.
  -- The upvalues are replaced by their current litteral value or the corresponding required module.
  -- @tparam function fn The function to resolve
  -- @treturn function the function without upvalue
  function Thread.resolveUpValues(fn)
    local identity = true
    local lines = {'return function(...)', ''}
    for i = 1, 250 do
      local name, value = debug.getupvalue(fn, i)
      if not name then
        break
      end
      logger:finest('upvalue %d: %s', i, name)
      if name == '' or name == '?' then
        error('upvalue not available')
      end
      if name == '_ENV' then
        table.insert(lines, string.format('debug.setupvalue(f, %d, _G)', i))
      elseif value ~= nil then
        identity = false
        local tvalue = type(value)
        if tvalue == 'boolean' or tvalue == 'number' or tvalue == 'string' then
          table.insert(lines, string.format('debug.setupvalue(f, %d, %q)', i, value))
        elseif tvalue == 'table' or tvalue == 'function' or tvalue == 'userdata' then
          local found
          for n, m in pairs(package.loaded) do
            if m == value then
              table.insert(lines, string.format('debug.setupvalue(f, %d, require("%s"))', i, n))
              found = true
              break
            end
          end
          if not found then
            error('unsupported upvalue')
          end
        else
          error('unsupported upvalue type')
        end
      end
    end
    if identity then
      return fn
    end
    local chunk = string.dump(fn)
    lines[2] = string.format('local f = load(%q, nil, "b")', chunk)
    table.insert(lines, 'return f(...)')
    table.insert(lines, 'end')
    local body = table.concat(lines, '\n')
    logger:finest('resolved function with: -->%s<--', body)
    return load(body, nil, 't')()
  end

end)