--local luvLib = require('luv')
local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local StreamHandler = require('jls.io.StreamHandler')

return {
  close = function(stream, callback)
    logger:finest('close(%s)', stream)
    local cb, d = Promise.ensureCallback(callback)
    if stream then
      stream:close(cb)
    elseif cb then
      cb()
    end
    return d
  end,
  read_start = function(stream, callback)
    logger:finest('read_start(%s)', stream)
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
    logger:finer('read_start() => %s, %s', status, err)
    return status, err
  end,
  read_stop = function(stream)
    logger:finest('read_stop(%s)', stream)
    local status, err
    if stream then
      status, err = stream:read_stop()
    else
      err = 'stream not available'
    end
    logger:finer('read_stop() => %s, %s', status, err)
    return status, err
  end,
  write = function(stream, data, callback)
    logger:finest('write(%s, %s)', stream, data and #data)
    local cb, d = Promise.ensureCallback(callback)
    local req, err
    if stream then
      --if stream:is_closing() then
      --  logger:warn('write(%s) is closing', stream)
      --end
      -- write returns a cancelable request
      req, err = stream:write(data, cb)
    else
      err = 'stream not available'
    end
    if not req then
      if cb then
        cb(err or 'unknown error')
      else
        logger:warn('write(%s) fail %s', stream, err)
      end
    end
    -- TODO invert request and error?
    return d, req, err
  end,
}
