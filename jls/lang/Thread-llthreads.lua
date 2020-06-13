local llthreadsLib = require('llthreads')

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event')
local CODEC_MODULE_NAME = 'jls.util.base64'
local codec = require(CODEC_MODULE_NAME)

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
    local chunk = string.dump(self.fn)
    local ec = codec.encode(chunk)
    local code = "local chunk = require('"..CODEC_MODULE_NAME.."').decode('"..ec.."');"..
    [[
      local fn = load(chunk, nil, 'b')
      local results = table.pack(pcall(fn, ...))
      local status = table.remove(results, 1)
      if status then
        return nil, table.unpack(results)
      end
      return results[1] or 'Error in thread'
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
            local results = table.pack(self.t:join())
            local ok = table.remove(results, 1)
            local err = table.remove(results, 1)
            self.t = nil
            self._endPromise = nil
            if ok then
              if err then
                reject(err)
              else
                if #results <= 0 then
                  resolve()
                elseif #results == 1 then
                  resolve(results[1])
                else
                  resolve(results)
                end
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