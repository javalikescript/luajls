local luaSocketLib = require('socket')

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local TableList = require('jls.util.TableList')
local streams = require('jls.io.streams')

-- this module only work with scheduler based event
if event ~= require('jls.lang.event-') then
 error('Conflicting event libraries')
end

local socketToString = function(client)
  --local ip, port = client:getpeername()
  local status, ip, port = pcall(client.getpeername, client) -- unconnected udp fails
  if status and ip then
    return tostring(ip)..':'..tostring(port)
  end
  return string.gsub(tostring(client), '%s+', '')
end

local BUFFER_SIZE = 2048

local MODE_RECV = 1
local MODE_SEND = 2

local Selector = class.create(function(selector)

  function selector:initialize()
    self.contt = {}
    self.recvt = {}
    self.sendt = {}
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
        TableList.removeFirst(self.recvt, socket)
      end
      if subMode & MODE_SEND == MODE_SEND then
        TableList.removeFirst(self.sendt, socket)
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
      if not event:hasTask() then
        event:setTask(function()
          self:select(15)
          return not self:isEmpty()
        end)
      end
    else
      self.contt[socket] = nil
    end
    return
  end
  
  function selector:unregister(socket, mode)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('selector:unregister('..socketToString(socket)..', '..tostring(mode)..')')
    end
    if mode then
      local context = self.contt[socket]
      if context then
        self:register(socket, context.mode & (0xf ~ mode))
      end
    else
      TableList.removeFirst(self.recvt, socket)
      TableList.removeFirst(self.sendt, socket)
      self.contt[socket] = nil
    end
  end
  
  function selector:unregisterAndClose(socket)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('selector:unregisterAndClose('..socketToString(socket)..')')
    end
    self:unregister(socket)
    socket:close()
  end
  
  function selector:isEmpty()
    local count = #self.recvt + #self.sendt
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('selector:isEmpty() => '..tostring(count == 0)..' ('..tostring(count)..')')
      for i, socket in ipairs(self.recvt) do
        logger:debug(' recvt['..tostring(i)..'] '..socketToString(socket))
      end
      for i, socket in ipairs(self.sendt) do
        logger:debug(' sendt['..tostring(i)..'] '..socketToString(socket))
      end
    end
    return count == 0
  end
  
  function selector:select(timeout)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('selector:select('..tostring(timeout)..'s) recvt: '..tostring(#self.recvt)..' sendt: '..tostring(#self.sendt))
    end
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
          local size = context.streamHandler.bufferSize or BUFFER_SIZE
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
              -- the connection was closed before the transmission was completed
              wf.callback('closed')
            elseif sendErr ~= 'timeout' then
              wf.callback(sendErr)
            end
          else
            table.remove(context.writet, 1)
            wf.callback()
            if #context.writet == 0 then
              self:unregister(socket, MODE_SEND)
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
              wf.callback(sendErr) -- TODO discard all write futures
            end
          else
            wf.position = i
          end
          if wf.length - wf.position <= 0 then
            table.remove(context.writet, 1)
            wf.callback()
            if #context.writet == 0 then
              self:unregister(socket, MODE_SEND)
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

local DEFAULT_SELECTOR = Selector:new()


local Tcp = class.create(function(tcp)
  function tcp:initialize(tcp, selector)
    self.tcp = tcp
    self.selector = selector or DEFAULT_SELECTOR
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
    local tcp = self.tcp
    self.tcp = nil
    self.selector:unregisterAndClose(tcp)
    local cb, d = Promise.ensureCallback(callback)
    cb()
    return d
  end
end)


local TcpClient = class.create(Tcp, function(tcpClient)

  function tcpClient:connect(addr, port, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpClient:connect('..tostring(addr)..', '..tostring(port)..')')
    end
    local tcp, err = luaSocketLib.connect(addr, port)
    self.tcp = tcp
    local cb, d = Promise.ensureCallback(callback)
    if err then
      if logger:isLoggable(logger.DEBUG) then
        logger:debug('tcpClient:connect('..tostring(addr)..', '..tostring(port)..') error => "'..tostring(err)..'"')
      end
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
      self.selector:unregister(self.tcp, Selector.MODE_RECV)
    end
    return self
  end

  function tcpClient:setTcpNoDelay(on)
    logger:debug('tcpClient:setTcpNoDelay('..tostring(on)..')')
    return self.tcp:setoption('tcp-nodelay', on)
  end

  function tcpClient:setKeepAlive(on, delay)
    logger:debug('tcpClient:setKeepAlive('..tostring(on)..', '..tostring(delay)..')')
    return self.tcp:setoption('keepalive', on)
  end

end)


local TcpServer = class.create(Tcp, function(tcpServer, super)

  function tcpServer:bind(addr, port, backlog, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('tcpServer:bind('..tostring(addr)..', '..tostring(port)..')')
    end
    if addr == '0.0.0.0' or addr == '::' then
      addr = '*'
    end
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

  function tcpServer:close(callback)
    logger:debug('tcpServer:close()')
    super.close(self, callback)
  end

end)

-- User Datagram Protocol

local UdpSocket = class.create(function(udpSocket)

  function udpSocket:initialize(nds, selector)
    self.nds = nds
    self.selector = selector or DEFAULT_SELECTOR
  end

  local luaSocketLib_udp4 = luaSocketLib.udp4 and luaSocketLib.udp4 or luaSocketLib.udp

  function udpSocket:create(addr, options)
    if self.nds == nil then
      if addr and string.find(addr, ':') or options and options.ipv6only == true then
        self.nds = luaSocketLib.udp6()
      else
        self.nds = luaSocketLib_udp4()
      end
    end
  end

  function udpSocket:bind(addr, port, options)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:bind('..tostring(addr)..', '..tostring(port)..')')
    end
    self:create(addr, options)
    if options and options.reuseaddr ~= nil then
      local status, err = self.nds:setoption('reuseaddr', options.reuseaddr)
      if not status then
        error('Error while enabling reuse address '..tostring(err))
      end
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

  function udpSocket:receiveStart(cb)
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
      self.selector:unregister(self.nds, Selector.MODE_RECV)
    end
  end

  function udpSocket:send(data, addr, port, callback)
    if logger:isLoggable(logger.DEBUG) then
      logger:debug('udpSocket:send('..tostring(string.len(data))..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    self:create(addr)
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
      self.nds = false
    end
    cb()
    return d
  end
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