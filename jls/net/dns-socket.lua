local lib = require('socket').dns
local class = require('jls.lang.class')

return {
  getaddrinfo = function(node, callback)
    local addrinfo, err = lib.getaddrinfo(node)
    callback(err, addrinfo)
  end,
  getnameinfo = function(addr, callback)
    local names, err = lib.getnameinfo(addr)
    callback(err, names and names[1])
  end,
  interface_addresses = class.notImplementedFunction,
}
