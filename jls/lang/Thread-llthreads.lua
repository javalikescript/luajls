local llthreadsLib = require('llthreads')

local Promise = require('jls.lang.Promise')
local loader = require('jls.lang.loader')
local event = loader.requireOne('jls.lang.event-')
local logger = require('jls.lang.logger')

local tables = loader.tryRequire('jls.util.tables')

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
    local chunkAsString = string.format('%q', string.dump(self.fn))
    local code = "return require('jls.lang.Thread')._main("..chunkAsString..", ...)"
    logger:finest('code: [[%s]]', code)
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
          end)
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

end, function(Thread)

  function Thread._main(chunk, ...)
    local fn = load(chunk, nil, 'b')
    local status, val, err = pcall(fn, ...)
    logger:finest('Thread._main() => %s', status)
    if status then
      if err then
        return 0, tostring(err)
      else
        local typ = type(val)
        if val == nil or typ == 'string' or typ == 'number' or typ == 'boolean' then
          return 1, val
        elseif typ == 'table' then
          if tables then
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
  end

end)