local lib = require('luv')

return {
  getaddrinfo = function(node, callback)
    lib.getaddrinfo(node, nil, {family = 'unspec', socktype = 'stream'}, callback)
  end,
  getnameinfo = function(addr, callback)
    lib.getnameinfo({ip = addr}, callback)
  end,
  interface_addresses = lib.interface_addresses,
}
