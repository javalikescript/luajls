local luaSocketLib = require('socket')

local logger = require('jls.lang.logger')
local loader = require('jls.lang.loader')
local event = loader.requireOne('jls.lang.event-')
local List = require('jls.util.List')

local function socketToString(client)
  --local ip, port = client:getpeername()
  local status, ip, port = pcall(client.getpeername, client) -- unconnected udp fails
  if status and ip then
    return tostring(ip)..':'..tostring(port)
  end
  return string.gsub(tostring(client), '%s+', '')
end

local function emptyFunction() end

local BUFFER_SIZE = 2048

local MODE_RECV = 1
local MODE_SEND = 2

return require('jls.lang.class').create(function(selector)

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
      context.streamHandler = streamHandler
      computedMode = computedMode | MODE_RECV
    end
    if writeData and writeCallback then
      if socket.sendto then
        wf = {
          buffer = writeData,
          callback = writeCallback,
          ip = ip,
          port = port
        }
      else
        wf = {
          buffer = writeData,
          callback = writeCallback,
          length = string.len(writeData),
          position = 0
        }
      end
      table.insert(context.writet, wf)
      computedMode = computedMode | MODE_SEND
    end
    mode = mode or computedMode
    if logger:isLoggable(logger.FINEST) then
      logger:finest('selector:register('..socketToString(socket)..', '..tostring(context.mode)..'=>'..tostring(mode)..')')
      --logger:traceback()
    end
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
      --logger:finest('selector:register(), '..tostring(context)..' as '..tostring(self.contt[socket]))
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
    if logger:isLoggable(logger.FINEST) then
      logger:finest('selector:unregister('..socketToString(socket)..', '..tostring(mode)..')')
    end
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
    if logger:isLoggable(logger.FINEST) then
      logger:finest('selector:unregisterAndClose('..socketToString(socket)..')')
    end
    self:unregister(socket)
    socket:close()
  end

  function selector:close(socket, callback)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('selector:close('..socketToString(socket)..')')
    end
    local context = self.contt[socket]
    if context and context.mode & MODE_SEND == MODE_SEND then
      if logger:isLoggable(logger.FINER) then
        logger:finer('selector:close() defer to select, writet: #'..tostring(#context.writet))
        if logger:isLoggable(logger.FINEST) and #context.writet > 0 and not socket.sendto then
          local wf = context.writet[1]
          logger:finest('selector:select() to send '..tostring(wf.position)..'/'..tostring(wf.length)
            ..' buffer: "'..tostring(wf.buffer)..'"')
        end
      end
      context.closeCallback = callback or emptyFunction
    else
      self:unregisterAndClose(socket)
      if callback then
        callback()
      end
    end
  end

  function selector:isEmpty()
    local count = #self.recvt + #self.sendt
    if logger:isLoggable(logger.FINEST) then
      logger:finest('selector:isEmpty() => '..tostring(count == 0)..' ('..tostring(count)..')')
      for i, socket in ipairs(self.recvt) do
        logger:finest(' recvt['..tostring(i)..'] '..socketToString(socket))
      end
      for i, socket in ipairs(self.sendt) do
        logger:finest(' sendt['..tostring(i)..'] '..socketToString(socket))
      end
    end
    return count == 0
  end

  function selector:select(timeout)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('selector:select('..tostring(timeout)..'s) recvt: '..tostring(#self.recvt)..' sendt: '..tostring(#self.sendt))
    end
    local canrecvt, cansendt, selectErr = luaSocketLib.select(self.recvt, self.sendt, timeout)
    if selectErr then
      if logger:isLoggable(logger.FINEST) then
        logger:finest('selector:select() error "'..tostring(selectErr)..'"')
      end
      if selectErr == 'timeout' then
        return true
      end
      return nil, selectErr
    end
    if logger:isLoggable(logger.FINEST) then
      logger:finest('selector:select() canrecvt: '..tostring(#canrecvt)..' cansendt: '..tostring(#cansendt))
    end
    -- process canrecvt sockets
    for _, socket in ipairs(canrecvt) do
      local context = self.contt[socket]
      if context and context.streamHandler then
        if type(context.streamHandler) == 'function' then
          logger:finest('selector:select() accepting')
          context.streamHandler()
        else
          local size = context.streamHandler.bufferSize or BUFFER_SIZE
          logger:finest('selector:select() receiving '..tostring(size)..' on '..socketToString(socket))
          local content, recvErr, partial = socket:receive(size)
          if content then
            context.streamHandler:onData(content)
          elseif recvErr then
            if logger:isLoggable(logger.FINER) then
              logger:finer('selector:select() receive error: "'..tostring(recvErr)..'", content #'
                ..tostring(content and #content)..'", partial #'..tostring(partial and #partial))
            end
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
        if logger:isLoggable(logger.FINEST) then
          logger:finest('selector unregistered socket '..socketToString(socket)..' will be closed')
        end
        self:unregisterAndClose(socket)
      end
    end
    -- process cansendt sockets
    for _, socket in ipairs(cansendt) do
      local context = self.contt[socket]
      if context and #context.writet > 0 then
        if logger:isLoggable(logger.FINEST) then
          logger:finest('selector:select() sending on '..socketToString(socket))
        end
        local wf = context.writet[1]
        if socket.sendto then
          local sendErr
          if wf.port then
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
              if logger:isLoggable(logger.FINEST) then
                logger:finest('selector:select() on '..socketToString(socket)..', send error: '..tostring(sendErr))
              end
              wf.callback(sendErr)
            end
          else
            table.remove(context.writet, 1)
            wf.callback()
            if #context.writet == 0 then
              if context.closeCallback then
                if logger:isLoggable(logger.FINEST) then
                  logger:finest('selector close socket '..socketToString(socket))
                end
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
              if logger:isLoggable(logger.FINEST) then
                logger:finest('selector:select() on '..socketToString(socket)..', send error: '..tostring(sendErr))
              end
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
                if logger:isLoggable(logger.FINEST) then
                  logger:finest('selector close socket '..socketToString(socket))
                end
                self:unregisterAndClose(socket)
                context.closeCallback()
              else
                self:unregister(socket, MODE_SEND)
              end
            end
          end
        end
      else
        if logger:isLoggable(logger.FINEST) then
          logger:finest('selector unregistered socket '..socketToString(socket)..' will be closed')
        end
        self:unregisterAndClose(socket)
      end
    end
    return true
  end

end, function(Selector)

  Selector.socketToString = socketToString

  Selector.MODE_NONE = 0
  Selector.MODE_RECV = MODE_RECV
  Selector.MODE_SEND = MODE_SEND
  Selector.MODE_DUAL = MODE_RECV | MODE_SEND

  Selector.DEFAULT = Selector:new()

end)
