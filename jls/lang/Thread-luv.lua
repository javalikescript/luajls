local luvLib = require('luv')

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local ThreadBase = require('jls.lang.ThreadBase')

return class.create(ThreadBase, function(thread)

  function thread:start(...)
    if self.t then
      return self
    end
    self._endPromise = Promise:new(function(resolve, reject)
      self._async = luvLib.new_async(function(status, value)
        ThreadBase._apply(resolve, reject, status, value)
        local async, t = self._async, self.t
        self._async = nil
        self.t = nil
        if async then
          async:close()
        end
        if t then
          t:join()
        end
      end)
    end)
    self.t = luvLib.new_thread(self:_arg(self._async, ...))
    return self
  end

end, function(Thread)

  function Thread._main(chunk, async, ...)
    async:send(ThreadBase._main(chunk, ...))
  end

end)