--
-- TVSetStateEvent
-- Sincroniza liga/desliga + canal entre servidor e clientes
--

TVSetStateEvent = {}
local TVSetStateEvent_mt = Class(TVSetStateEvent, Event)

InitEventClass(TVSetStateEvent, "TVSetStateEvent")

function TVSetStateEvent.emptyNew()
    return Event.new(TVSetStateEvent_mt)
end

function TVSetStateEvent.new(object, isOn, channel)
    local self = TVSetStateEvent.emptyNew()
    self.object = object
    self.isOn = isOn
    self.channel = channel
    return self
end

function TVSetStateEvent:readStream(streamId, connection)
    self.object  = NetworkUtil.readNodeObject(streamId)
    self.isOn    = streamReadBool(streamId)
    self.channel = streamReadUIntN(streamId, 4)
    self:run(connection)
end

function TVSetStateEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.object)
    streamWriteBool(streamId, self.isOn)
    streamWriteUIntN(streamId, self.channel, 4)
end

function TVSetStateEvent:run(connection)
    -- Servidor recebeu de um cliente: repassa para os demais
    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection, self.object)
    end

    if self.object ~= nil and self.object:getIsSynchronized() then
        self.object:setTVState(self.isOn, self.channel, true)
    end
end

function TVSetStateEvent.sendEvent(object, isOn, channel, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(TVSetStateEvent.new(object, isOn, channel), nil, nil, object)
        else
            g_client:getServerConnection():sendEvent(TVSetStateEvent.new(object, isOn, channel))
        end
    end
end
