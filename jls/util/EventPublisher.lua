--- Provide EventPublisher class.
-- @module jls.util.EventPublisher

local logger = require('jls.lang.logger')
local tables = require('jls.util.tables')

--- The EventPublisher class.
-- The EventPublisher provides a way subsribe and publish events.
-- @type EventPublisher
return require('jls.lang.class').create(function(eventPublisher)

  --- Creates a new EventPublisher.
  -- @function EventPublisher:new
  -- @return a new EventPublisher
  function eventPublisher:initialize()
    self.eventHandlers = {}
  end

  --- Unsubscribes all the events.
  function eventPublisher:unsubscribeAllEvents()
    self.eventHandlers = {}
  end

  --- Subscribes to the specified event name with the specified function.
  -- @tparam string name the event name
  -- @tparam function fn the function to call when the event is published
  -- @return an opaque key that could be used to unsubscribe
  function eventPublisher:subscribeEvent(name, fn)
    local handlers = self.eventHandlers[name]
    if not handlers then
      handlers = {}
      self.eventHandlers[name] = handlers
    end
    local eventFn = fn
    --if EventPublisher:isInstance(fn) then
    if type(fn) == 'table' and type(fn.publishEvent) == 'function' then
      eventFn = function()
        fn:publishEvent(name)
      end
    end
    if type(eventFn) == 'function' then
      table.insert(handlers, eventFn)
      return eventFn
    end
    return nil
  end

  --- Unsubscribes the specified event name.
  -- @tparam string name the event name
  -- @param key the subscribed key
  function eventPublisher:unsubscribeEvent(name, key)
    local handlers = self.eventHandlers[name]
    if handlers then
      tables.removeTableValue(handlers, key, true)
      if #handlers == 0 then
        self.eventHandlers[name] = nil
      end
    end
  end

  --- Publishes the specified event name.
  -- @tparam string name the event name
  function eventPublisher:publishEvent(name, ...)
    local handlers = self.eventHandlers[name]
    if handlers then
      for _, handler in ipairs(handlers) do
        handler(...)
      end
    end
  end

end)