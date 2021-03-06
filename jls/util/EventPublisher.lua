--- Provide EventPublisher class.
-- @module jls.util.EventPublisher

local logger = require('jls.lang.logger')
local TableList = require('jls.util.TableList')
local tables = require('jls.util.tables')

--- The EventPublisher class.
-- The EventPublisher provides a way subsribe and publish events.
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
  -- Registers an event handler/listener
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
      eventFn = function(...)
        fn:publishEvent(name, ...)
      end
    end
    if type(eventFn) == 'function' then
      if TableList.contains(handlers, eventFn) then
        eventFn = function(...)
          fn(...)
        end
      end
      table.insert(handlers, eventFn)
      return eventFn
    end
    return nil
  end

  function eventPublisher:subscribeEventOnce(name, fn)
    local key
    key = self:subscribeEvent(name, function(...)
      self:unsubscribeEvent(name, key)
      fn(...)
    end)
    return key
  end

  function eventPublisher:eventNames()
    local names = tables.keys(self.eventHandlers)
    table.sort(names)
    return names
  end

  function eventPublisher:subscriptionCount(name)
    local handlers = self.eventHandlers[name]
    if handlers then
      return #handlers
    end
    return 0
  end

  --- Unsubscribes the specified event name.
  -- @tparam string name the event name
  -- @param key the subscribed key
  function eventPublisher:unsubscribeEvent(name, key)
    local unsubscribed = false
    local handlers = self.eventHandlers[name]
    if handlers then
      if key then
        unsubscribed = TableList.removeFirst(handlers, key)
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
  -- Fires an event
  -- @tparam string name the event name
  -- @treturn boolean true if the event had subscriptions, false otherwise
  function eventPublisher:publishEvent(name, ...)
    local handlers = self.eventHandlers[name]
    if handlers then
      for _, handler in ipairs(handlers) do
        local status, err = pcall(handler, ...)
        if not status then
          if name == 'error' or not self:publishEvent('error', err) then
            logger:warn('An error occurs when handling event "'..tostring(name)..'" with handler '..tostring(handler)..': '..tostring(err))
            error(err)
          end
        end
      end
      return true
    else
      if logger:isLoggable(logger.FINER) then
        logger:finer('No handler for event "'..tostring(name)..'"')
      end
    end
    return false
  end

end)