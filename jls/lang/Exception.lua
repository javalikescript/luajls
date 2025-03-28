--- Represents an abnormal event.
-- An exception instance captures the error message and the associated stack.
-- @module jls.lang.Exception
-- @pragma nostrip

local class = require('jls.lang.class')

--- The Exception class.
-- @type Exception
return class.create(function(exception, _, Exception)

  local function cleanMessage(message, stack)
    if type(message) == 'string' then
      local i = string.find(message, ': ', 2, true)
      if i and i < 512 then
        local prefix = string.sub(message, 1, i + 1)
        i = string.find(stack, prefix, 16, true) -- skip "stack traceback:"
        if i and i < 512 then
          -- the prefix is available in the stack so unnecessary in the message
          return string.sub(message, #prefix + 1)
        end
      end
    end
    return message
  end

  --- Creates a new Exception.
  -- The stack is removed from the message.
  -- The stack trace and the name will be generated automatically.
  -- @param[opt] message The exception message
  -- @param[opt] cause The exception cause
  -- @tparam[opt] string stack The exception stack
  -- @function Exception:new
  function exception:initialize(message, cause, stack, name)
    if type(name) == 'string' then
      self.name = name
    end
    if type(stack) == 'string' then
      self.stack = stack
    elseif type(stack) == 'number' then
      self.stack = debug.traceback(nil, stack)
    else
      self.stack = debug.traceback(nil, 3) -- initialize is called be new, we skip both
    end
    self.cause = cause
    self.message = cleanMessage(message, self.stack)
  end

  -- TODO Remove name
  function exception:getName()
    return self.name or class.getName(self:getClass()) or 'Exception'
  end

  --- Returns the message of this exception.
  -- The message is the error object passed to the error function.
  -- @return The message of this exception possibly nil
  function exception:getMessage()
    return self.message
  end

  --- Returns the cause of this exception.
  -- @return The cause of this exception if any or nil
  function exception:getCause()
    return self.cause
  end

  --- Returns the stack of this exception.
  -- A traceback of the call stack when this exception was created and thrown
  -- @treturn string The stack of this exception
  function exception:getStackTrace()
    return self.stack
  end

  -- Throws this exception.
  function exception:throw()
    error(self, 0)
  end

  -- Returns the string representation of this exception.
  -- It includes the name, message, stack and cause.
  -- @treturn string The string representation of this exception
  function exception:toString()
    local s = self:getName()..': '..tostring(self.message)..'\n'..self.stack
    if self.cause ~= nil then
      s = s..'\nCaused by: '..tostring(self.cause)
    end
    --s = string.gsub(self.stack, '\n', '\r\n')
    return s
  end

  function exception:serialize(write)
    write(self.message)
    write(self.cause)
    write(self.stack)
    write(self.name)
  end

  function exception:deserialize(read)
    self.message = read('string|nil')
    self.cause = read('string|nil')
    self.stack = read('string|nil')
    self.name = read('string|nil')
  end

  function exception:toJSON()
    return {
      name = self:getName(),
      stack = self:getStackTrace(),
      cause = self:getCause(),
      message = self:getMessage(),
    }
  end

  function Exception.fromJSON(t)
    return Exception:new(t.message, t.cause, t.stack, t.name)
  end

  function Exception.throw(...)
    Exception:new(...):throw()
  end

  function Exception.error(message)
    error(message, 0)
  end

  function Exception:getName()
    return 'jls.lang.Exception'
  end

  --- Returns the message of the specified value if it is an exception or the specified value itself.
  -- @param e The exception or error message
  -- @return The message of the exception possibly nil
  function Exception.getMessage(e)
    if Exception:isInstance(e) then
      return e:getMessage()
    end
    return e
  end

  local function handleError(message)
    if Exception:isInstance(message) then
      return message
    end
    local stack = debug.traceback(nil, 2) -- we skip handleError
    return Exception:new(message, nil, stack)
  end

  --- Calls the specified function with the given arguments in protected mode.
  -- @tparam function fn The function to call in protected mode
  -- @param[opt] ... The arguments to call the function with
  -- @treturn boolean true if the call succeeds without errors
  -- @return The returned values of the call or the Exception in case of error
  function Exception.pcall(fn, ...)
    return xpcall(fn, handleError, ...)
  end

  local function fail(status, ...)
    if status == true then
      return ...
    end
    return nil, ...
  end

  --- Calls the specified function with the given arguments in protected mode.
  -- @tparam function fn The function to call in protected mode
  -- @param[opt] ... The arguments to call the function with
  -- @return The returned values of the call or nil plus the Exception in case of error
  function Exception.try(fn, ...)
    return fail(xpcall(fn, handleError, ...))
  end

end)