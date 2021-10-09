--local luvLib = require('luv')
local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.streams.StreamHandler')

return {
  close = function(stream, callback)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('luv.close('..tostring(stream)..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    if stream then
      stream:close(cb)
    elseif cb then
      cb()
    end
    return d
  end,
  read_start = function(stream, callback)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('luv.read_start('..tostring(stream)..')')
    end
    local cb = StreamHandler.ensureCallback(callback)
    local status, err
    if stream then
      status, err = stream:read_start(cb)
    else
      err = 'stream not available'
    end
    if not status then
      cb(err or 'unknown error')
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('luv.read_start() => '..tostring(status)..', '..tostring(err))
    end
    return status, err
  end,
  read_stop = function(stream)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('luv.read_stop('..tostring(stream)..')')
    end
    local status, err
    if stream then
      status, err = stream:read_stop()
    else
      err = 'stream not available'
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('luv.read_stop() => '..tostring(status)..', '..tostring(err))
    end
    return status, err
  end,
  write = function(stream, data, callback)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('luv.write('..tostring(stream)..', '..tostring(string.len(data))..')')
    end
    local cb, d = Promise.ensureCallback(callback)
    local req, err
    if stream then
      -- write returns a cancelable request
      req, err = stream:write(data, cb)
    else
      err = 'stream not available'
    end
    if not req and cb then
      cb(err or 'unknown error')
    end
    return d, req, err
  end,
}
