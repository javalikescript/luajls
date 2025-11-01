local List = require('jls.util.List')
return function()
  local t = {}
  local function write(item)
    table.insert(t, item == nil and t or item)
  end
  local function reverse()
    List.reverse(t)
  end
  local function read()
    local item = table.remove(t)
    if item == t then
      return nil
    end
    return item
  end
  return write, reverse, read, t
end
