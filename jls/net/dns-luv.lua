--- Provide DNS related functions.
-- @module jls.net.dns

local luvLib = require('luv')

local Promise = require('jls.lang.Promise')

--- Lookups address info for a specified hostname.
-- The result consists in a table with an "addr" field containing the IP address.
-- @tparam string node the hostname.
-- @tparam[opt] function callback an optional callback function to use in place of promise.
-- @treturn jls.lang.Promise a promise that resolves to the address informations.
local function getAddressInfo(node, callback)
  local cb, d = Promise.ensureCallback(callback)
  luvLib.getaddrinfo(node, nil, {family = 'unspec', socktype = 'stream'}, cb)
  return d
end

--- Lookups host name for a specified IP address.
-- @tparam string addr the IP Address.
-- @tparam[opt] function callback an optional callback function to use in place of promise.
-- @treturn jls.lang.Promise a promise that resolves to the host name.
local function getNameInfo(addr, callback)
  local cb, d = Promise.ensureCallback(callback)
  luvLib.getnameinfo({ip = addr}, cb)
  return d
end

return {
  getAddressInfo = getAddressInfo,
  getNameInfo = getNameInfo
}