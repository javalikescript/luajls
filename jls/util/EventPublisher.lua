--- Allows to publish and subscribe to events.
-- @module jls.util.EventPublisher
-- @pragma nostrip

local logger = require('jls.lang.logger')
local Exception = require('jls.lang.Exception')
local List = require('jls.util.List')
local tables = require('jls.util.tables')

--- The EventPublisher class.
-- The EventPublisher provides a way to subsribe and publish events.
-- @type EventPublisher
return require('jls.lang.class').create(function(eventPublisher)

  --- Creates a new EventPublisher.
  -- @function EventPublisher:new
  -- @return a new EventPublisher
  function eventPublisher:initialize(subscriptions)
    self.eventHandlers = {}
    if type(subscriptions) == 'table' then
      self:subscribeEvents(subscriptions)
    end
  end

  function eventPublisher:subscribeEvents(subscriptions)
    for name, fn in pairs(subscriptions) do
      self:subscribeEvent(name, fn)
    end
  end

  --- Unsubscribes all the events.
  function eventPublisher:unsubscribeAllEvents()
    self.eventHandlers = {}
  end

  --- Subscribes to the specified event name with the specified function.
  -- Registers an event handler/listener.
  -- When the handler raises an error, the 'error' event is published,
  -- if there is no handler then the error is propagated.
  -- @tparam string name the event name
  -- @param handler the function to call when the event is published
  -- @return an opaque key that could be used to unsubscribe
  function eventPublisher:subscribeEvent(name, handler)
    local handlers = self.eventHandlers[name]
    if not handlers then
      handlers = {}
      self.eventHandlers[name] = handlers
    end
    local eventFn
    --if EventPublisher:isInstance(fn) then
    if type(handler) == 'table' and type(handler.publishEvent) == 'function' then
      eventFn = function(...)
        handler:publishEvent(name, ...)
      end
    elseif type(handler) == 'function' then
      if List.contains(handlers, handler) then
        eventFn = function(...)
          handler(...)
        end
      else
        eventFn = handler
      end
    else
      error('Invalid function argument')
    end
    table.insert(handlers, eventFn)
    return eventFn -- as opaque key
  end

  --- Subscribes once to the specified event name with the specified function.
  -- On the first publication, the subscription will be removed prior to call the handler.
  -- @tparam string name the event name
  -- @tparam function fn the function to call when the event is published
  -- @return an opaque key that could be used to unsubscribe
  function eventPublisher:subscribeEventOnce(name, fn)
    local key
    key = self:subscribeEvent(name, function(...)
      self:unsubscribeEvent(name, key)
      fn(...)
    end)
    return key
  end

  --- Returns the subscribed event names.
  -- @treturn table the event names
  function eventPublisher:eventNames()
    local names = tables.keys(self.eventHandlers)
    table.sort(names)
    return names
  end

  --- Returns the number of handlers for the specified event name.
  -- @tparam string name the event name
  -- @treturn number the number of handlers
  function eventPublisher:subscriptionCount(name)
    local handlers = self.eventHandlers[name]
    if handlers then
      return #handlers
    end
    return 0
  end

  --- Unsubscribes the specified event name.
  -- @tparam string name the event name
  -- @param key the subscribed key, nil to remove all handlers for the name
  function eventPublisher:unsubscribeEvent(name, key)
    local unsubscribed = false
    local handlers = self.eventHandlers[name]
    if handlers then
      if key then
        unsubscribed = List.removeFirst(handlers, key)
        if #handlers == 0 then
          self.eventHandlers[name] = nil
        end
      else
        self.eventHandlers[name] = nil
        unsubscribed = true
      end
    end
    return unsubscribed
  end

  --- Publishes the specified event name.
  -- Calls each subscribed handler for the event name in the subscription order.
  -- @tparam string name the event name
  -- @param[opt] ... the optional parameters to pass to the handler.
  -- @treturn boolean true if the event had subscriptions, false otherwise
  function eventPublisher:publishEvent(name, ...)
    local handlers = self.eventHandlers[name]
    if handlers then
      for _, handler in ipairs(handlers) do
        local status, err = Exception.pcall(handler, ...)
        if not status then
          if name == 'error' or not self:publishEvent('error', err, name) then
            logger:fine('An error occurred when handling event "%s" with handler %s: %s', name, handler, err)
            error(err)
          end
        end
      end
      return true
    end
    logger:finer('No handler for event "%s"', name)
    return false
  end

end)