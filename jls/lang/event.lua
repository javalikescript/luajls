local event = require('jls.lang.loader').requireOne('jls.lang.event-luv', 'jls.lang.event-')

local noLoopCheck = os.getenv('JLS_EVENT_NO_LOOP_CHECK')
if not noLoopCheck then
  local logger = require('jls.lang.logger')
  if logger:isLoggable(logger.WARN) then
    -- registering a global object to check if the event loop has been called and processed all the events.
    JLS_EVENT_GLOBAL_OBJECT = setmetatable({}, {
      __gc = function()
        if event:loopAlive() then
          logger:warn('event is alive, make sure you ran the event loop!')
        else
          logger:fine('event is not alive')
        end
      end
    })
  end
end

return event
