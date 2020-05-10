local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
--local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')

local function setMessageBodyFile(response, file, size)
  size = size or 2048
  if logger:isLoggable(logger.FINE) then
    logger:fine('setMessageBodyFile(?, '..file:getPath()..', '..tostring(size)..')')
  end
  function response:writeBody(stream, callback)
    if logger:isLoggable(logger.FINE) then
      logger:fine('setMessageBodyFile() "'..file:getPath()..'" => response:writeBody()')
    end
    local cb, promise = Promise.ensureCallback(callback)
    local fd, err = FileDescriptor.openSync(file) -- TODO Handle error
    if fd then
      local writeCallback
      writeCallback = function(err)
        if logger:isLoggable(logger.FINER) then
          logger:finer('setMessageBodyFile() "'..file:getPath()..'" => writeCallback('..tostring(err)..')')
        end
        if err then
          fd:closeSync()
          cb(err)
        else
          fd:read(size, nil, function(err, buffer)
            if err then
              fd:closeSync()
              cb(err)
            elseif buffer then
              if logger:isLoggable(logger.FINER) then
                logger:finer('setMessageBodyFile() "'..file:getPath()..'" => read #'..tostring(#buffer))
              end
              stream:write(buffer, writeCallback)
            else
              fd:closeSync()
              cb()
            end
          end)
        end
      end
      writeCallback()
    else
      cb(err or 'Unable to open file "'..file:getPath()..'"')
    end
    return promise
  end
  -- local body = file:readAll()
  -- if body then
  --   response:setBody(body)
  -- end
end

return setMessageBodyFile
