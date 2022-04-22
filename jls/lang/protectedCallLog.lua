local u = _G['JLS_USE_XPCALL']
_G['JLS_USE_XPCALL'] = true
local protectedCall = require('jls.lang.protectedCall')
_G['JLS_USE_XPCALL'] = u
return protectedCall
