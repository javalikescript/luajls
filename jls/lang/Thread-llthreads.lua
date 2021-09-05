local llthreadsLib = require('llthreads')

local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event')

local tables = require('jls.lang.loader').tryRequire('jls.util.tables')

-- this module only work with scheduler based event
if event ~= require('jls.lang.event-') then
  error('Conflicting event libraries')
end

return require('jls.lang.class').create(function(thread)

  function thread:initialize(fn)
    self.daemon = false
    self:setFunction(fn)
  end

  local EMPTY_FUNCTION = function() end

  function thread:setFunction(fn)
    if type(fn) == 'function' then
      self.fn = fn
    else
      self.fn = EMPTY_FUNCTION
    end
  end

  function thread:start(...)
    if self.t then
      return self
    end
    local chunk = string.dump(self.fn)
    local code = "local chunk = "..string.format('%q', chunk)..
    [[
      local fn = load(chunk, nil, 'b')
      local status, val, err = pcall(fn, ...)
      if status then
        if err then
          return 0, tostring(err)
        else
          local typ = type(val)
          if val == nil or typ == 'string' or typ == 'number' or typ == 'boolean' then
            return 1, val
          elseif typ == 'table' then
            local tablesRequired, tables = pcall(require, 'jls.util.tables')
            if tablesRequired then
              return 2, tables.stringify(val)
            else
              return 0, tostring(tables)
            end
          else
            return 0, 'Invalid thread function return type '..typ
          end
        end
      else
        return 0, val or 'Unknown error in thread'
      end
    ]]
    --logger:finest('code: [['..code..']]')
    self.t = llthreadsLib.new(code, ...)
    self.t:start(self.daemon, true)
    return self
  end

  function thread:ended()
    if self.t then
      if not self._endPromise then
        self._endPromise = Promise:new(function(resolve, reject)
          event:setTask(function()
            if self.t:alive() then
              return true
            end
            local ok, state, value = self.t:join()
            self._endPromise = nil
            if ok then
              if state == 1 then
                resolve(value)
              elseif state == 2 and tables then
                resolve(tables.parse(value))
              else
                reject(value)
              end
            else
              reject('Not able to join thread properly')
            end
            self.t = nil
            return false
          end, 500)
        end)
      end
      return self._endPromise
    end
    return Promise.reject()
  end

  function thread:isAlive()
    return self.t and self.t:alive() or false
  end

  function thread:join()
    if self.t then
      self.t:join()
      self.t = nil
    end
  end

end)