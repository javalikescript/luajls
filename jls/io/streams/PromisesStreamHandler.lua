local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.StreamHandler')

local END = Promise.resolve()

return require('jls.lang.class').create(StreamHandler, function(promisesStreamHandler)

  function promisesStreamHandler:initialize()
    self.list = {}
    self.promise = nil
    self.readIndex = 0
    self.writeIndex = 0
  end

  local function reject(self, reason)
    local readIndex, list = self.readIndex, self.list
    self:initialize()
    self.promise = Promise.reject(reason)
    for index = readIndex, 1, -1 do
      local promise = list[index]
      if promise and promise._apply then
        promise._apply(reason)
      else
        break
      end
    end
  end

  function promisesStreamHandler:read()
    if self.promise then
      return self.promise
    end
    self.size = 0
    local index = self.readIndex + 1
    self.readIndex = index
    local promise = self.list[index]
    if promise then
      self.list[index] = nil
      if promise == END then
        reject(self, 'ended')
      end
    else
      local apply
      promise, apply = Promise.withCallback()
      promise._apply = apply
      self.list[index] = promise
    end
    return promise
  end

  local function write(self, err, data)
    if self.promise then
      return
    end
    local index = self.writeIndex + 1
    self.writeIndex = index
    local promise = self.list[index]
    if promise then
      self.list[index] = nil
      promise._apply(err, data)
      if not (data or err) then
        reject(self, 'ended')
      end
    else
      if err then
        promise = Promise.reject(err)
      elseif data then
        promise = Promise.resolve(data)
      else
        promise = END
      end
      self.list[index] = promise
    end
  end

  function promisesStreamHandler:available()
    return self.writeIndex > self.readIndex
  end

  function promisesStreamHandler:onData(data)
    write(self, nil, data)
  end

  function promisesStreamHandler:onError(err)
    write(self, err or 'unknown error')
  end

  function promisesStreamHandler:close()
    reject(self, 'closed')
  end

end)

