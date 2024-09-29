local luaSocketLib = require('socket')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger'):get(...)
local loader = require('jls.lang.loader')
local event = loader.requireOne('jls.lang.event-')
local List = require('jls.util.List')

local function log(message, ...)
  if logger:isLoggable(logger.FINER) then
    local l = select('#', ...)
    local values = {...}
    for i = 1, l do
      local v = values[i]
      if type(v) == 'userdata' and type(v.getpeername) == 'function' then
        local status, ip, port = pcall(v.getpeername, v) -- unconnected udp fails
        if status and ip then
          values[i] = string.format('%s; %s:%s', v, ip, port)
        end
      end
    end
    logger:finer(message, table.unpack(values, 1, l))
  end
end

local BUFFER_SIZE = 2048

local MODE_RECV = 1
local MODE_SEND = 2

return class.create(function(selector)

  function selector:initialize()
    self.contt = {}
    self.recvt = {}
    self.sendt = {}
    self.eventTask = nil
  end

  function selector:register(socket, mode, streamHandler, writeData, writeCallback, ip, port)
    local wf
    local context = self.contt[socket]
    local computedMode = 0
    if context then
      computedMode = context.mode
    else
      context = {
        mode = 0,
        writet = {}
      }
    end
    if streamHandler then
      if not (socket.receivefrom) ~= not (ip) then
        error('missing or unexpected ip for socket')
      end
      context.streamHandler = streamHandler
      context.ip = ip
      computedMode = computedMode | MODE_RECV
    end
    if writeData then
      if not (socket.sendto) ~= not (ip and port) then
        error('missing or unexpected ip for socket')
      end
      if type(writeData) ~= 'string' then
        if type(writeData) == 'table' then
          -- we may want to insert multiple writes
          writeData = table.concat(writeData)
        else
          error('invalid write data type')
        end
      end
      wf = {
        buffer = writeData,
        callback = writeCallback or class.emptyFunction,
        ip = ip,
        port = port,
        length = #writeData,
        position = 0
      }
      table.insert(context.writet, wf)
      computedMode = computedMode | MODE_SEND
    end
    mode = mode or computedMode
    log('register(%s, %s=>%s)', socket, context.mode, mode)
    if mode == context.mode then
      return
    end
    local addMode = mode
    if context.mode > 0 then
      local keepMode = mode & context.mode
      addMode = mode ~ keepMode
      local subMode = context.mode ~ keepMode
      if subMode & MODE_RECV == MODE_RECV then
        List.removeFirst(self.recvt, socket)
      end
      if subMode & MODE_SEND == MODE_SEND then
        List.removeFirst(self.sendt, socket)
      end
    else
      self.contt[socket] = context
      socket:settimeout(0) -- do not block
    end
    if mode > 0 then
      if addMode & MODE_RECV == MODE_RECV then
        table.insert(self.recvt, socket)
      end
      if addMode & MODE_SEND == MODE_SEND then
        table.insert(self.sendt, socket)
      end
      context.mode = mode
      if not self.eventTask or not event:hasTimer(self.eventTask) then
        self.eventTask = event:setTask(function(timeoutMs)
          self:select(timeoutMs / 1000)
          return not self:isEmpty()
        end, -1)
      end
    else
      self.contt[socket] = nil
    end
    -- return a cancellable request as available with libuv
    return wf
  end

  function selector:unregister(socket, mode)
    log('unregister(%s, %s)', socket, mode)
    if mode then
      local context = self.contt[socket]
      if context then
        self:register(socket, context.mode & (0xf ~ mode))
      end
    else
      List.removeFirst(self.recvt, socket)
      List.removeFirst(self.sendt, socket)
      self.contt[socket] = nil
    end
  end

  function selector:unregisterAndClose(socket)
    log('unregisterAndClose(%s)', socket)
    self:unregister(socket)
    socket:close()
  end

  function selector:close(socket, callback)
    log('close(%s)', socket)
    local context = self.contt[socket]
    if context and context.mode & MODE_SEND == MODE_SEND then
      if logger:isLoggable(logger.FINE) then
        logger:fine('close() defer to select, writet: #%l', context.writet)
        if logger:isLoggable(logger.FINER) and #context.writet > 0 and not socket.sendto then
          local wf = context.writet[1]
          logger:finer('to send %s/%s buffer: "%s"', wf.position, wf.length, wf.buffer)
        end
      end
      context.closeCallback = callback or class.emptyFunction
    else
      self:unregisterAndClose(socket)
      if callback then
        callback()
      end
    end
  end

  function selector:isEmpty()
    local count = #self.recvt + #self.sendt
    logger:finer('isEmpty() count: %s', count)
    return count == 0
  end

  function selector:select(timeout)
    logger:finer('select(%ss) recvt: %l sendt: %l', timeout, self.recvt, self.sendt)
    local canrecvt, cansendt, selectErr = luaSocketLib.select(self.recvt, self.sendt, timeout)
    if selectErr then
      logger:finer('select error "%s"', selectErr)
      if selectErr == 'timeout' then
        return true
      end
      return nil, selectErr
    end
    logger:finer('canrecvt: %l cansendt: %l', canrecvt, cansendt)
    -- process canrecvt sockets
    for _, socket in ipairs(canrecvt) do
      local context = self.contt[socket]
      if context and context.streamHandler then
        if type(context.streamHandler) == 'function' then
          logger:finer('accepting')
          context.streamHandler()
        else
          local size = context.streamHandler.bufferSize or BUFFER_SIZE
          log('receiving %s on %s', size, socket)
          local content, recvErr, partial, addr
          if context.ip then
            content, recvErr, partial = socket:receivefrom(size)
            if content and recvErr and partial then
              addr = {ip = recvErr, port = partial}
            end
          else
            content, recvErr, partial = socket:receive(size)
          end
          if content then
            context.streamHandler:onData(content, addr)
          elseif recvErr then
            logger:fine('receive error: "%s", content #%l", partial #%l', recvErr, content, partial)
            if partial and #partial > 0 then
              context.streamHandler:onData(partial)
            else
              if recvErr == 'closed' then
                self:unregisterAndClose(socket)
                -- the connection was closed before the transmission was completed
                context.streamHandler:onData(nil)
              elseif recvErr ~= 'timeout' then
                context.streamHandler:onError(recvErr)
              end
            end
          end
        end
      else
        log('unregistered socket %s will be closed', socket)
        self:unregisterAndClose(socket)
      end
    end
    -- process cansendt sockets
    for _, socket in ipairs(cansendt) do
      local context = self.contt[socket]
      if context and #context.writet > 0 then
        log('sending on %s', socket)
        local wf = context.writet[1]
        if socket.sendto then
          local sendErr
          if wf.ip and wf.port then
            _, sendErr = socket:sendto(wf.buffer, wf.ip, wf.port)
          else
            _, sendErr = socket:send(wf.buffer)
          end
          if sendErr then
            if sendErr == 'closed' then
              self:unregisterAndClose(socket)
              -- the connection was closed before the transmission was completed
              wf.callback('closed')
            elseif sendErr ~= 'timeout' then
              log('on %s, send error: %s', socket, sendErr)
              wf.callback(sendErr)
            end
          else
            table.remove(context.writet, 1)
            wf.callback()
            if #context.writet == 0 then
              if context.closeCallback then
                log('selector close socket %s', socket)
                self:unregisterAndClose(socket)
                context.closeCallback()
              else
                self:unregister(socket, MODE_SEND)
              end
            end
          end
        else
          local i, sendErr, ierr = socket:send(wf.buffer, wf.position + 1)
          if sendErr then
            wf.position = ierr
            if sendErr == 'closed' then
              self:unregisterAndClose(socket)
              -- the connection was closed before the transmission was completed
              wf.callback('closed')
            elseif sendErr ~= 'timeout' then
              log('on %s, send error: %s', socket, sendErr)
              wf.callback(sendErr) -- TODO discard all write futures
            end
          else
            wf.position = i
          end
          if wf.length - wf.position <= 0 then
            table.remove(context.writet, 1)
            wf.callback()
            if #context.writet == 0 then
              if context.closeCallback then
                log('selector close socket %s', socket)
                self:unregisterAndClose(socket)
                context.closeCallback()
              else
                self:unregister(socket, MODE_SEND)
              end
            end
          end
        end
      else
        log('selector unregistered socket %s will be closed', socket)
        self:unregisterAndClose(socket)
      end
    end
    return true
  end

end, function(Selector)

  Selector.MODE_NONE = 0
  Selector.MODE_RECV = MODE_RECV
  Selector.MODE_SEND = MODE_SEND
  Selector.MODE_DUAL = MODE_RECV | MODE_SEND

  Selector.DEFAULT = Selector:new()

end)
