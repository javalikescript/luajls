local luaSocketLib = require('socket')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event-') -- socket only work with scheduler based event
if event ~= require('jls.lang.event') then
  error('Conflicting event libraries')
end
local system = require('jls.lang.system')
local tables = require('jls.util.tables')
local streams = require('jls.io.streams')


local socketToString = function(client)
  local ip, port = client:getpeername()
  return tostring(ip)..':'..tostring(port)
end

--local BUFFER_SIZE = 2048

local MODE_RECV = 1
local MODE_SEND = 2

local Selector = class.create(function(selector)

  function selector:initialize()
    self.contt = {}
    self.recvt = {}
    self.sendt = {}
  end
  
  function selector:getMode(socket)
    local context = self.contt[socket]
    if context then
      return context.mode
    end
    return 0
  end
  
  function selector:register(socket, mode, streamHandler, writeData, writeCallback, ip, port)
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
      local wf
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
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('selector:register('..socketToString(socket)..', '..tostring(context.mode)..'=>'..tostring(mode)..')')
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
        tables.removeTableValue(self.recvt, socket, true)
      end
      if subMode & MODE_SEND == MODE_SEND then
        tables.removeTableValue(self.sendt, socket, true)
      end
    else
      self.contt[socket] = context
      socket:settimeout(0) -- do not block
      --logger:debug('selector:register(), '..tostring(context)..' as '..tostring(self.contt[socket]))
    end
    if mode > 0 then
      if addMode & MODE_RECV == MODE_RECV then
        table.insert(self.recvt, socket)
      end
      if addMode & MODE_SEND == MODE_SEND then
        table.insert(self.sendt, socket)
      end
      context.mode = mode
    else
      self.contt[socket] = nil
    end
    return
  end
  
  function selector:unregister(socket)
    tables.removeTableValue(self.recvt, socket, true)
    tables.removeTableValue(self.sendt, socket, true)
    self.contt[socket] = nil
  end
  
  function selector:unregisterAndClose(socket)
    self:unregister(socket)
    socket:close()
  end
  
  function selector:isEmpty()
    local count = #self.recvt + #self.sendt
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('selector:isEmpty() => '..tostring(count == 0)..' ('..tostring(count)..')')
    end
    return count == 0
  end
  
  function selector:select(timeout)
    logger:debug('selector:select('..tostring(timeout)..'s)')
    local selectionTime = system.currentTime()
    local canrecvt, cansendt, selectErr = luaSocketLib.select(self.recvt, self.sendt, timeout)
    if selectErr then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('selector:select() error "'..tostring(selectErr)..'"')
      end
      if selectErr == 'timeout' then
        return true
      end
      return nil, selectErr
    end
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('selector:select() canrecvt: '..tostring(#canrecvt)..' cansendt: '..tostring(#cansendt))
    end
    -- process canrecvt sockets
    for _, socket in ipairs(canrecvt) do
      local context = self.contt[socket]
      if context and context.streamHandler then
        if type(context.streamHandler) == 'function' then
          logger:debug('selector:select() accepting')
          context.streamHandler()
        else
          local size = context.streamHandler.bufferSize
          logger:debug('selector:select() receiving '..tostring(size)..' on '..socketToString(socket))
          local content, recvErr, partial = socket:receive(size)
          if content then
            context.streamHandler:onData(content)
          elseif recvErr then
            if logger:isLoggable(logger.FINER) then
              logger:finer('selector:select() receive error: '..tostring(recvErr))
            end
            if partial and #partial > 0 then
              context.streamHandler:onData(partial)
            end
            if recvErr == 'closed' then
              context.streamHandler:onData(nil)
              self:unregisterAndClose(socket)
            elseif recvErr ~= 'timeout' then
              context.streamHandler:onError(recvErr)
            end
          end
        end
      else
        if logger:isLoggable(logger.DEBUG) then
          logger:debug('selector unregistered socket '..socketToString(socket)..' will be closed')
        end
        self:unregisterAndClose(socket)
      end
    end
    -- process cansendt sockets
    for _, socket in ipairs(cansendt) do
      local context = self.contt[socket]
      if context and #context.writet > 0 then
        logger:debug('selector:select() sending on '..socketToString(socket))
        local wf = context.writet[1]
        if socket.sendto then
          local sendErr
          if wf.port then
            _, sendErr = socket:sendto(wf.buffer, wf.ip, wf.port)
          else
            _, sendErr = socket:send(wf.buffer)
          end
          if sendErr then
            wf.position = ierr
            if sendErr == 'closed' then
              self:unregisterAndClose(socket)
            elseif sendErr ~= 'timeout' then
              wf.callback(sendErr)
            end
          else
            table.remove(context.writet, 1)
            wf.callback()
            if #context.writet == 0 then
              local newMode = context.mode & MODE_RECV
              self:register(socket, newMode)
            end
          end
        else
          local i, sendErr, ierr = socket:send(wf.buffer, wf.position + 1)
          if sendErr then
            wf.position = ierr
            if sendErr == 'closed' then
              self:unregisterAndClose(socket)
            elseif sendErr ~= 'timeout' then
              wf.callback(sendErr) -- TODO discard all write futures
            end
          else
            wf.position = i
          end
          if wf.length - wf.position <= 0 then
            table.remove(context.writet, 1)
            wf.callback()
            if #context.writet == 0 then
              local newMode = context.mode & MODE_RECV
              self:register(socket, newMode)
            end
          end
        end
      else
        if logger:isLoggable(logger.DEBUG) then
          logger:debug('selector unregistered socket '..socketToString(socket)..' will be closed')
        end
        self:unregisterAndClose(socket)
      end
    end
    return true
  end
  
end)

Selector.MODE_NONE = 0
Selector.MODE_RECV = MODE_RECV
Selector.MODE_SEND = MODE_SEND
Selector.MODE_DUAL = MODE_RECV | MODE_SEND

local defaultSelector = Selector:new()


local Tcp = class.create(function(tcp)
  function tcp:initialize(tcp, selector)
    self.tcp = tcp
    self.selector = selector or defaultSelector
  end
  
  function tcp:getLocalName()
    --logger:debug('tcp:getLocalName()')
    return self.tcp:getsockname()
  end
  
  function tcp:getRemoteName()
    --logger:debug('tcp:getRemoteName()')
    return self.tcp:getPeerName()
  end
  
  function tcp:close(callback)
    logger:debug('tcp:close()')
    self.selector:register(self.tcp, 0)
    self.tcp:close()
    local cb, d = Promise.ensureCallback(callback)
    cb()
    return d
  end
end)


local TcpClient = class.create(Tcp, function(tcpClient)

  function tcpClient:connect(addr, port, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpClient:connect('..tostring(addr)..', '..tostring(port)..', ...)')
    end
    local tcp, err = luaSocketLib.connect(addr, port)
    self.tcp = tcp
    local cb, d = Promise.ensureCallback(callback)
    if err then
      cb(err)
    else
      cb(nil, self)
    end
    return d
  end

  function tcpClient:write(data, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpClient:write('..tostring(string.len(data))..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    if self.tcp then
      self.selector:register(self.tcp, nil, nil, data, cb)
    else
      cb('closed')
    end
    return d
  end

  function tcpClient:readStart(cb)
    logger:debug('tcpClient:readStart(?)')
    local stream = streams.ensureStreamHandler(cb)
    if self.tcp then
      self.selector:register(self.tcp, nil, stream)
    else
      stream:onError('closed')
    end
    return self
  end

  function tcpClient:readStop()
    logger:debug('tcpClient:readStop()')
    if self.tcp then
      local newMode = self.selector:getMode(self.tcp) & MODE_SEND
      self.selector:register(self.tcp, newMode)
    end
    return self
  end

  function tcpClient:setTcpNoDelay(on)
    logger:debug('tcpClient:setTcpNoDelay('..tostring(on)..')')
    self.tcp:setoption('tcp-nodelay', on)
    return self
  end

  function tcpClient:setKeepAlive(on, delay)
    logger:debug('tcpClient:setKeepAlive('..tostring(on)..', '..tostring(delay)..')')
    self.tcp:setoption('keepalive', on)
    return self
  end

end)


local TcpServer = class.create(Tcp, function(tcpServer)

  function tcpServer:bind(addr, port, backlog, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpServer:bind('..tostring(addr)..', '..tostring(port)..')')
    end
    --if addr == '0.0.0.0' or addr == '::' then
    --  addr = '*'
    --end
    local cb, d = Promise.ensureCallback(callback)
    local tcp, err = luaSocketLib.bind(addr, port, backlog)
    if err then
      cb(err)
      return d
    end
    tcp:settimeout(0) -- do not block
    -- TODO Bind on IPv4 and IPv6
    self.tcp = tcp
    local server = self
    self.selector:register(self.tcp, Selector.MODE_RECV, function()
      server:handleAccept()
    end)
    cb()
    return d
  end

  function tcpServer:handleAccept()
    local tcp = self:tcpAccept()
    if tcp then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('tcpServer:handleAccept() accepting '..socketToString(tcp))
      end
      local client = TcpClient:new(tcp)
      self:onAccept(client)
    else
      logger:debug('tcpServer:handleAccept() accept error')
    end
  end

  function tcpServer:tcpAccept()
    return self.tcp:accept()
  end

  function tcpServer:onAccept(client)
    client:close()
  end
end)

-- User Datagram Protocol

local UdpSocket = class.create(function(udpSocket)

  function udpSocket:initialize(nds, selector)
    self.nds = nds
    self.selector = selector or defaultSelector
  end


  function udpSocket:bind(addr, port, options)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:bind('..tostring(addr)..', '..tostring(port)..')')
    end
    if not self.nds then
      if string.find(addr, ':') then
        self.nds = luaSocketLib.udp6()
      else
        self.nds = luaSocketLib.udp4()
      end
    end
    if options and options.reuseaddr ~= nil then
      self.nds:setoption('reuseaddr', options.reuseaddr)
      --self.nds:setoption('reuseport', true)
    end
    return self.nds:setsockname(addr, port)
  end

  function udpSocket:connect(addr, port)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:connect('..tostring(addr)..', '..tostring(port)..')')
    end
    return self.nds:setpeername(addr, port)
  end

  function udpSocket:disconnect()
    return self.nds:setpeername('*')
  end

  function udpSocket:getLocalName()
    if self.nds then
      return self.nds:getsockname() -- ip, port, family
    end
  end

  function udpSocket:getPort()
    if self.nds then
      return select(2, self.nds:getsockname())
    end
  end

  function udpSocket:setBroadcast(value)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:setBroadcast('..tostring(value)..')')
    end
    return self.nds:setoption('broadcast', value)
  end

  function udpSocket:setLoopbackMode(value)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:setLoopbackMode('..tostring(value)..')')
    end
    return self.nds:setoption('ip-multicast-loop', value)
  end

  function udpSocket:setTimeToLive(value)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:setTimeToLive('..tostring(value)..')')
    end
    return self.nds:setoption('ip-multicast-ttl', value)
  end

  function udpSocket:setInterface(ifaddr)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:setInterface('..tostring(ifaddr)..')')
    end
    return self.nds:setoption('ip-multicast-if', value)
  end

  function udpSocket:joinGroup(mcastaddr, ifaddr)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:joinGroup('..tostring(mcastaddr)..', '..tostring(ifaddr)..')')
    end
    return self.nds:setoption('ip-add-membership', {multiaddr = mcastaddr, interface = ifaddr})
  end

  function udpSocket:leaveGroup(mcastaddr, ifaddr)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:leaveGroup('..tostring(mcastaddr)..', '..tostring(ifaddr)..')')
    end
    return self.nds:setoption('ip-drop-membership', {multiaddr = mcastaddr, interface = ifaddr})
  end

  function udpSocket:receiveStart(stream)
    logger:debug('udpSocket:receiveStart(?)')
    local stream = streams.ensureStreamHandler(cb)
    if self.nds then
      self.selector:register(self.nds, nil, stream)
    else
      stream:onError('closed')
    end
  end

  function udpSocket:receiveStop()
    logger:debug('udpSocket:receiveStop()')
    if self.nds then
      local newMode = self.selector:getMode(self.nds) & MODE_SEND
      self.selector:register(self.nds, newMode)
    end
  end

  function udpSocket:send(data, addr, port, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:send('..tostring(string.len(data))..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    if self.nds then
      self.selector:register(self.nds, nil, nil, data, cb, addr, port)
    else
      cb('closed')
    end
    return d
  end

  function udpSocket:close(callback)
    logger:debug('udpSocket:close()')
    local cb, d = Promise.ensureCallback(callback)
    if self.nds then
      self.nds:close()
      self.nds = nil
    end
    cb()
    return d
  end
end)

event:setTask(function()
  defaultSelector:select(15)
  return not defaultSelector:isEmpty()
end)


local function getAddressInfo(node, port, callback)
  local cb, d = Promise.ensureCallback(callback)
  cb(nil, {{
    addr = node,
    port = port
  }})
  return d
end


return {
  socketToString = socketToString,
  getAddressInfo = getAddressInfo,
  TcpServer = TcpServer,
  TcpClient = TcpClient,
  UdpSocket = UdpSocket
}