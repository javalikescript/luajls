local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local Thread = require('jls.lang.Thread')
local json = require('jls.util.json')
local smt = require('jls.util.smt')

--[[
thread worker implementation, each worker has a dedicated thread
]]

local WorkerServer = class.create(function(workerServer, _, WorkerServer)

  function workerServer:initialize()
    self.useTcp = os.getenv('WORKER_SMT_USE_TCP') ~= nil or not smt.SmtPipeServer
    logger:finer('workerServer:new() useTcp: '..tostring(self.useTcp))
    self.smtServer = nil
    if self.useTcp then
      self.smtServer = smt.SmtTcpServer:new()
    else
      self.smtServer = smt.SmtPipeServer:new()
    end
    self.workerThreadCallback = {}
    self.workers = {}
    self.started = false
    self.startPromise = nil
    function self.smtServer.onMessage(_, payload, client)
      if logger:isLoggable(logger.FINEST) then
        logger:finest('workerServer onMessage('..tostring(payload)..')')
      end
      local t = json.decode(payload)
      if t.message ~= nil then
        local worker = self.workers[client]
        if worker then
          worker:onMessage(t.message)
        end
      elseif t.workerId then
        -- new worker thread connected
        local cb = self.workerThreadCallback[t.workerId]
        self.workerThreadCallback[t.workerId] = nil
        if cb then
          cb(nil, client)
        end
      else
        logger:warn('workerServer onMessage() ignored')
      end
    end
  end

  function workerServer:bind()
    logger:finer('workerServer:bind()')
    if self.useTcp then
      -- peak an ephemeral port
      return self.smtServer:bind(nil, 0):next(function()
        self.tcpPort = self.smtServer:getTcpPort()
        if logger:isLoggable(logger.FINER) then
          logger:finer('workerServer bound on port '..tostring(self.tcpPort))
        end
      end)
    end
    -- default uniq pipe name
    return self.smtServer:bind(''):next(function()
      self.pipeName = self.smtServer:getPipeName()
      if logger:isLoggable(logger.FINER) then
        logger:finer('workerServer bound on pipe name "'..tostring(self.pipeName)..'"')
      end
    end)
  end

  function workerServer:start()
    logger:finer('workerServer:start()')
    if not self.startPromise then
      self.startPromise = self:bind()
    end
    return self.startPromise
  end

  function workerServer:stop()
    logger:finer('workerServer:stop()')
    if not self.startPromise then
      logger:finer('workerServer:stop() => not started')
      return Promise.reject()
    end
    return self.startPromise:next(function()
      logger:finer('workerServer:stop() closing clients')
      return self.smtServer:broadcastMessage(json.encode({
        close = true
      }))
    end):next(function()
      logger:finer('workerServer:stop() stopping')
      self.smtServer:close()
      self.started = false
      self.startPromise = nil
    end)
  end

  function workerServer:registerWorker(client, worker)
    self.workers[client] = worker
  end

  function workerServer:newWorkerThread(workerFn)
    local chunk = string.dump(workerFn)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('workerServer:newWorkerThread() code >>'..tostring(chunk)..'<<')
    end
    local code = "local Worker = require('jls.util.Worker-smt');"..
      "local event = require('jls.lang.event');"..
      "Worker.WorkerServer.initializeWorkerThread(load("..string.format('%q', chunk)..", nil, 'b'), ...);"..
      "event.loop()"
    local thread = Thread:new(load(code, nil, 't'))
    local workerId = tostring(thread)
    local promise, cb = Promise.createWithCallback()
    self.workerThreadCallback[workerId] = cb
    if logger:isLoggable(logger.FINER) then
      logger:finer('workerServer:newWorkerThread() "'..tostring(workerId)..'"')
    end
    thread:start(workerId, self.useTcp, self.useTcp and self.tcpPort or self.pipeName):ended():next(function()
      if logger:isLoggable(logger.FINER) then
        logger:finer('workerServer thread ended "'..tostring(workerId)..'"')
      end
      if self.workerThreadCallback[workerId] then
        self.workerThreadCallback[workerId] = nil
        cb('Worker thread ended')
      end
    end, function(err)
      self.workerThreadCallback[workerId] = nil
      cb(err)
    end)
    return promise
  end

  function WorkerServer.initializeWorkerThread(workerFn, workerId, useTcp, tcpPortOrPipeName)
    local Worker = require('jls.util.Worker-smt')
    local worker = nil
    local smtClient = useTcp and smt.SmtTcpClient:new() or smt.SmtPipeClient:new()
    function smtClient:onMessage(payload)
      if logger:isLoggable(logger.FINER) then
        if logger:isLoggable(logger.FINEST) then
          logger:finest('thread "'..tostring(workerId)..'" onMessage('..tostring(payload)..')')
        else
          logger:finer('thread "'..tostring(workerId)..'" onMessage()')
        end
      end
      local t = json.decode(payload)
      if t.message ~= nil and worker then
        worker:onMessage(t.message)
      elseif t.close then
        smtClient:close()
      end
    end
    -- we may want to avoid listening if onMessage is not overriden
    (useTcp and smtClient:connect(nil, math.floor(tcpPortOrPipeName)) or smtClient:connect(tcpPortOrPipeName)):next(function()
      if logger:isLoggable(logger.FINER) then
        logger:finer('thread "'..tostring(workerId)..'" client is connected to server')
      end
      --worker = class.makeInstance(Worker)
      worker = Worker:new()
      function worker:close()
        return smtClient:close()
      end
      workerFn(worker)
      return smtClient:postMessage(json.encode({
        workerId = workerId
      })):next(function()
        function worker:postMessage(message)
          if logger:isLoggable(logger.FINER) then
            logger:finer('thread "'..tostring(workerId)..'" worker:postMessage(?)')
          end
          return smtClient:postMessage(json.encode({
            message = message
          }))
        end
        worker:postPendingMessages()
      end)
    end, function(err)
      if logger:isLoggable(logger.FINER) then
        logger:finer('thread "'..tostring(workerId)..'" client connection error to server, '..tostring(err))
      end
    end)
  end

end)

local WORKER_SERVER = WorkerServer:new()

return class.create(function(worker, _, Worker)

  function worker:initialize(workerFn)
    logger:finer('worker:new()')
    self.pendingMessages = {}
    if type(workerFn) ~= 'function' then
      return
    end
    WORKER_SERVER:start():next(function()
      logger:finer('worker:new() server started')
      return WORKER_SERVER:newWorkerThread(workerFn)
    end):next(function(client)
      logger:finer('worker:new() worker thread client connected')
      WORKER_SERVER:registerWorker(client, self)
      function self:postMessage(message)
        logger:finer('worker:postMessage()')
        return client:postMessage(json.encode({
          message = message
        }))
      end
      function self:close()
        logger:finer('worker:close()')
        return client:postMessage(json.encode({
          close = true
        })):next(function()
          WORKER_SERVER:registerWorker(client, nil)
        end)
      end
      self:postPendingMessages()
    end):catch(function(err)
      logger:warn('worker:new() error '..tostring(err))
    end)
  end

  function worker:postPendingMessages()
    local messages = self.pendingMessages
    if not messages then
      return Promise.resolve()
    end
    self.pendingMessages = nil
    if logger:isLoggable(logger.FINER) then
      logger:finer('worker post '..tostring(#messages)..' pending messages')
    end
    local cb = self.postMessageCallback
    self.postMessagePromise = nil
    self.postMessageCallback = nil
    local promises = {}
    for _, message in ipairs(messages) do
      table.insert(promises, self:postMessage(message))
    end
    Promise.all(promises):next(function()
      if cb then
        cb()
      end
    end)
  end

  function worker:postMessage(message)
    if self.pendingMessages then
      logger:finer('worker:postMessage() add to pending messages')
      table.insert(self.pendingMessages, message)
      if not self.postMessagePromise then
        self.postMessagePromise, self.postMessageCallback = Promise.createWithCallback()
      end
      return self.postMessagePromise
    end
    return Promise.reject()
  end

  function worker:onMessage(message)
    logger:finer('worker:onMessage() not overriden')
  end

  function worker:close()
    error('Not initialized worker')
  end

  function worker:terminate()
    self:close()
  end

  function Worker.shutdown()
    WORKER_SERVER:stop()
  end

  function Worker.getWorkerServer()
    return WORKER_SERVER
  end

  Worker.WorkerServer = WorkerServer

end)
