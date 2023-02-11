-- Deprecated, to remove
local WebSocket = require('jls.net.http.WebSocket')
return {
  CONST = WebSocket.CONST,
  UpgradeHandler = WebSocket.UpgradeHandler,
  WebSocketUpgradeHandler = WebSocket.UpgradeHandler,
  WebSocket = WebSocket,
  randomChars = WebSocket.randomChars,
  generateMask = WebSocket.generateMask,
  applyMask = WebSocket.applyMask,
}
