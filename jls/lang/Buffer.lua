--- Represents a byte array to store temporary data.
-- @module jls.lang.Buffer
-- @pragma nostrip

local class = require('jls.lang.class')

--- The Buffer class.
-- @type Buffer
return class.create(function(buffer)

  --- Returns the size of the buffer.
  -- @return The size of the buffer
  -- @function buffer:length
  buffer.length = class.notImplementedFunction

  --- Returns the string at the specified position.
  -- @tparam[opt] number from The start position, default to 1
  -- @tparam[opt] number to The end position included, default to this buffer size
  -- @return The string at the specified position
  -- @function buffer:get
  buffer.get = class.notImplementedFunction

  --- Sets the string at the specified position.
  -- @param value The value to set in this buffer, could be a buffer or a string
  -- @tparam[opt] number offset The position in this buffer to set, default to 1
  -- @tparam[opt] number from The start position in the value, default to 1
  -- @tparam[opt] number to The end position in the value included, default to this buffer size
  -- @function buffer:set
  buffer.set = class.notImplementedFunction

  --- Returns the bytes at the specified position.
  -- @tparam[opt] number from The start position, default to 1
  -- @tparam[opt] number to The end position included, default to from
  -- @return The bytes at the specified position
  -- @function buffer:getBytes
  buffer.getBytes = class.notImplementedFunction

  --- Sets the bytes at the specified position.
  -- @tparam number at The position in this buffer to set, default to 1
  -- @param ... The bytes
  -- @function buffer:setBytes
  buffer.setBytes = class.notImplementedFunction

  --- Returns a reference for this buffer.
  -- @treturn string a reference for this buffer
  -- @function buffer:toReference
  buffer.toReference = class.notImplementedFunction

end, function(Buffer)

  local function getClassName(mode)
    if mode == 'local' then
      return require('jls.lang.BufferLocal')
    elseif mode == 'global' then
      return require('jls.lang.BufferGlobal')
    elseif mode == 'shared' then
      return require('jls.lang.BufferShared')
    end
    error('invalid buffer mode '..tostring(mode))
  end

  --- Returns a new buffer for the specified mode.  
  -- A local buffer resides in the Lua state.
  -- A global buffer resides out of the Lua state but in the Lua process.
  -- A shared buffer resides out of the Lua process but in the host.
  -- @tparam number size the size to allocate, could be a non empty string
  -- @tparam[opt] string mode the mode of buffer, defaults to local
  -- @return The new allocated buffer
  function Buffer.allocate(size, mode)
    if type(size) == 'string' then
      local b = Buffer.allocate(#size, mode)
      b:set(size)
      return b
    end
    if math.type(size) ~= 'integer' or size <= 0 then
      error('invalid size '..tostring(size))
    end
    if mode == nil then
      mode = 'local'
    end
    return getClassName(mode).allocate(size, mode)
  end

  --- Returns the buffer represented by the specified reference.
  -- @tparam string reference the reference
  -- @tparam[opt] string mode the mode of buffer
  -- @return The referenced buffer
  function Buffer.fromReference(reference, mode)
    if mode == nil then
      local status, b
      for _, m in ipairs({'local', 'global', 'shared'}) do
        status, b = pcall(Buffer.fromReference, reference, m)
        if status then
          return b
        end
      end
    end
    return getClassName(mode).fromReference(reference, mode)
  end

end)