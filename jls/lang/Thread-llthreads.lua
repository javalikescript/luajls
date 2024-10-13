local llthreadsLib = require('llthreads')

local loader = require('jls.lang.loader')
local event = loader.requireOne('jls.lang.event-')

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local ThreadBase = require('jls.lang.ThreadBase')

return class.create(ThreadBase, function(thread, super)

  function thread:initialize(fn)
    super.initialize(self, fn)
    self.daemon = false
  end

  function thread:start(...)
    if self.t then
      return self
    end
    self.t = llthreadsLib.new(self:_arg(...))
    self.t:start(self.daemon, true)
    return self
  end

  function thread:ended()
    if self.t then
      if not self._endPromise then
        self._endPromise = Promise:new(function(resolve, reject)
          local t = self.t
          event:setTask(function()
            if t:alive() then
              return true
            end
            local ok, status, value = t:join()
            self._endPromise = nil
            if not ok then
              status, value = false, 'unable to join thread properly'
            end
            ThreadBase._apply(resolve, reject, status, value)
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

end)