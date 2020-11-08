-- For compatibility, to remove

local dns = require('jls.net.dns')
local TcpClient = require('jls.net.TcpClient')

return {
  anyIPv4 = '0.0.0.0',
  anyIPv6 = '::',
  socketToString = TcpClient.socketToString,
  getAddressInfo = dns.getAddressInfo,
  getNameInfo = dns.getNameInfo,
  TcpServer = require('jls.net.TcpServer'),
  TcpClient = TcpClient,
  UdpSocket = require('jls.net.UdpSocket')
}
