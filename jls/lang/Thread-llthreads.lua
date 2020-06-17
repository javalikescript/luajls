local llthreadsLib = require('llthreads')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event')
local tables = require("jls.util.tables")

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
      local status, value = pcall(fn, ...)
      if status then
        if type(value) == 'table' then
          return 'table', require("jls.util.tables").stringify(value)
        end
        return nil, value
      end
      return 'error', value
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
            local ok, valueType, value = self.t:join()
            self.t = nil
            self._endPromise = nil
            if ok then
              if valueType == 'error' then
                reject(value or 'Unknown error')
              elseif valueType == 'table' then
                resolve(tables.parse(value))
              else
                resolve(value)
              end
            else
              reject('Not able to join properly')
            end
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