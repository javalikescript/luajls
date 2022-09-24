local jsonLib = require('lunajson')

-- https://github.com/grafi-tt/lunajson

local NULL = {}

return {
  decode = function(value)
    return jsonLib.decode(value, nil, NULL)
  end,
  encode = function(value)
    return jsonLib.encode(value, NULL)
  end,
  null = NULL,
}
