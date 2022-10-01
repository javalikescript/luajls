--[[--
Provide the SerialWorker class.

Allows to execute function in a single thread.

@module jls.util.SerialWorker
@pragma nostrip

@usage
  local SerialWorker = require('jls.util.SerialWorker')
local serialWorker = SerialWorker:new()

serialWorker:close()
]]

local function initWorker(w)
  local protectedCall = require('jls.lang.protectedCall')
  local json = require('jls.util.json')
  local StreamHandler = require('jls.io.StreamHandler')
  local lastFn
  function w:onMessage(message)
    local flags, payload, chunk = string.unpack('>Bs4s4', message)
    local data, fn
    if flags & 2 == 2 then
      fn = lastFn
    else
      fn = load(chunk, nil, 'b')
      lastFn = fn
    end
    if flags & 1 == 1 then
      if payload ~= 'null' then
        data = json.decode(payload) -- TODO protect or use parse
      end
    else
      data = payload
    end
    local sh
    if flags & 4 == 4 then
      sh = StreamHandler:new(function(err, sd)
        if err then
          self:postMessage(string.pack('>Bs4', 4 | 2, err))
        elseif data then
          self:postMessage(string.pack('>Bs4', 4, sd))
        end
      end)
    end
    local status, result, reason = protectedCall(fn, data, sh)
    flags = 0
    if status then
      if not result and reason then
        result = reason
        flags = 2
      end
    else
      flags = 2
    end
    if type(result) ~= 'string' then
      flags = flags | 1
      result = json.encode(result)
    end
    local response = string.pack('>Bs4', flags, result)
    return self:postMessage(response)
  end
end

local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local Worker = require('jls.util.Worker')
local json = require('jls.util.json')
local StreamHandler = require('jls.io.StreamHandler')

--- The SerialWorker class.
-- @type SerialWorker
return class.create(function(serialWorker)

  --- Creates a new SerialWorker.
  -- @function SerialWorker:new
  function serialWorker:initialize()
    self.worker = Worker:new(initWorker)
    self.worker.onMessage = function(_, response)
      self:onWorkerMessage(response)
    end
    self.workCallback = false
    self.workStreamHandler = false
    self.works = {}
  end

  function serialWorker:onWorkerMessage(message)
    local cb = self.workCallback
    if cb then
      local flags, result = string.unpack('>Bs4', message)
      if flags & 4 == 4 then
        if self.workStreamHandler then
          if flags & 2 == 2 then
            self.workStreamHandler:onError(result)
          else
            self.workStreamHandler:onData(result)
          end
        end
        return
      end
      self.workCallback = false
      self.workStreamHandler = false
      if flags & 1 == 1 then
        if result == 'null' then
          result = nil
        else
          result = json.decode(result)
        end
      end
      if flags & 2 == 2 then
        cb(result)
      else
        cb(nil, result)
      end
    end
    self:wakeup()
  end

  function serialWorker:isWorking()
    return self.workCallback
  end

  function serialWorker:wakeup()
    if not self.workCallback then
      local work = table.remove(self.works, 1)
      -- we may pause the worker if no work
      if work then
        self.workCallback = work.cb
        self.workStreamHandler = work.sh or false
        self.worker:postMessage(work.message)
      end
    end
  end

  --- Calls the specified function.
  -- @tparam function fn the function to call.
  -- @param[opt] data the function argument.
  -- @param[opt] sh a stream handler for intermediate results.
  -- @treturn jls.lang.Promise a promise that resolves once the function has been called.
  function serialWorker:call(fn, data, sh)
    local flags = 0
    local chunk
    if fn == self.lastFn then
      flags = flags | 2
    else
      chunk = string.dump(fn)
      if chunk == self.lastChunk then
        flags = flags | 2
        chunk = nil
      else
        self.lastChunk = chunk
      end
      self.lastFn = fn
    end
    local payload
    if type(data) == 'string' then
      payload = data
    else
      flags = flags | 1
      payload = json.encode(data)
    end
    if sh then
      flags = flags | 4
      sh = StreamHandler.ensureStreamHandler(sh)
    end
    local message = string.pack('>Bs4s4', flags, payload, chunk or '')
    local promise, cb = Promise.createWithCallback()
    local work = {
      message = message,
      cb = cb,
      sh = sh,
    }
    table.insert(self.works, work)
    self:wakeup()
    return promise
  end

  --- Closes this worker.
  function serialWorker:close()
    self.worker:close()
  end

end)