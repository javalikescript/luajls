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

  local function setPromise(self, value)
    self.list = nil
    self.promise = value
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
      if promise == END then
        setPromise(self, Promise.reject('ended'))
      else
        self.list[index] = nil
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
    local index = self.writeIndex + 1
    self.writeIndex = index
    local promise = self.list[index]
    if promise then
      promise._apply(err, data)
      self.list[index] = nil
      if not data and not err then
        setPromise(self, Promise.reject('ended'))
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
    for index = self.readIndex - 1, 1, -1 do
      local promise = self.list[index]
      if promise then
        promise._apply('closed')
      else
        break
      end
    end
    setPromise(self, Promise.reject('closed'))
  end

end)

