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
      self._async = luvLib.new_async(function(status, value, kind)
        ThreadBase._apply(resolve, reject, status, value, kind)
        self._async:close()
        self.t:join()
        self._async = nil
        self.t = nil
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