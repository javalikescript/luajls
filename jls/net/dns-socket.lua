local luaSocketLib = require('socket')

local Promise = require('jls.lang.Promise')

local function getAddressInfo(node, callback)
  local cb, d = Promise.ensureCallback(callback)
  local addrinfo, err = luaSocketLib.dns.getaddrinfo(node);
  cb(err, addrinfo)
  return d
end

local function getNameInfo(addr, callback)
  local cb, d = Promise.ensureCallback(callback)
  local names, err = luaSocketLib.dns.getnameinfo(addr)
  cb(err, names and names[1])
  return d
end

return {
  getAddressInfo = getAddressInfo,
  getNameInfo = getNameInfo
}
