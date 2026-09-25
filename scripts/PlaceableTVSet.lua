--
-- PlaceableTVSet
-- TV decorativa com liga/desliga e troca de canais
-- (cada canal é um plano do i3d; só um fica visível por vez)
-- Autor: AnJo888
--

PlaceableTVSet = {}
PlaceableTVSet.MOD_NAME  = g_currentModName
PlaceableTVSet.SPEC_NAME = "spec_" .. g_currentModName .. ".tvSet"
PlaceableTVSet.MAX_CHANNELS = 15 -- limite do stream (4 bits)

function PlaceableTVSet.prerequisitesPresent(specializations)
    return true
end

function PlaceableTVSet.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "setTVState",          PlaceableTVSet.setTVState)
    SpecializationUtil.registerFunction(placeableType, "getTVState",          PlaceableTVSet.getTVState)
    SpecializationUtil.registerFunction(placeableType, "getTVChannel",        PlaceableTVSet.getTVChannel)
    SpecializationUtil.registerFunction(placeableType, "getTVNumChannels",    PlaceableTVSet.getTVNumChannels)
    SpecializationUtil.registerFunction(placeableType, "toggleTVPower",       PlaceableTVSet.toggleTVPower)
    SpecializationUtil.registerFunction(placeableType, "nextTVChannel",       PlaceableTVSet.nextTVChannel)
    SpecializationUtil.registerFunction(placeableType, "onTVTriggerCallback", PlaceableTVSet.onTVTriggerCallback)
end

function PlaceableTVSet.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad",        PlaceableTVSet)
    SpecializationUtil.registerEventListener(placeableType, "onDelete",      PlaceableTVSet)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream",  PlaceableTVSet)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream", PlaceableTVSet)
end

function PlaceableTVSet.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("TVSet")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".tvSet#triggerNode",    "Trigger de proximidade do jogador")
    schema:register(XMLValueType.BOOL,       basePath .. ".tvSet#defaultOn",      "Estado inicial", false)
    schema:register(XMLValueType.INT,        basePath .. ".tvSet#defaultChannel", "Canal inicial", 1)
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".tvSet.channel(?)#node", "Plano da imagem do canal")
    schema:setXMLSpecializationType()
end

function PlaceableTVSet.registerSavegameXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("TVSet")
    schema:register(XMLValueType.BOOL, basePath .. "#isOn",    "TV ligada")
    schema:register(XMLValueType.INT,  basePath .. "#channel", "Canal atual")
    schema:setXMLSpecializationType()
end

function PlaceableTVSet:onLoad(savegame)
    local spec = self[PlaceableTVSet.SPEC_NAME]
    local xmlFile = self.xmlFile

    spec.channels = {}
    xmlFile:iterate("placeable.tvSet.channel", function(_, key)
        local node = xmlFile:getValue(key .. "#node", nil, self.components, self.i3dMappings)
        if node ~= nil then
            if #spec.channels < PlaceableTVSet.MAX_CHANNELS then
                table.insert(spec.channels, node)
            else
                Logging.xmlWarning(xmlFile, "TVSet: máximo de %d canais", PlaceableTVSet.MAX_CHANNELS)
            end
        else
            Logging.xmlWarning(xmlFile, "TVSet: node inválido em '%s'", key)
        end
    end)

    if #spec.channels == 0 then
        Logging.xmlWarning(xmlFile, "TVSet: nenhum canal definido")
    end

    spec.triggerNode = xmlFile:getValue("placeable.tvSet#triggerNode", nil, self.components, self.i3dMappings)
    spec.isOn        = xmlFile:getValue("placeable.tvSet#defaultOn", false)
    spec.channel     = xmlFile:getValue("placeable.tvSet#defaultChannel", 1)

    spec.activatable = TVSetActivatable.new(self)

    if spec.triggerNode ~= nil then
        addTrigger(spec.triggerNode, "onTVTriggerCallback", self)
    else
        Logging.xmlWarning(xmlFile, "TVSet: triggerNode não encontrado")
    end

    self:setTVState(spec.isOn, spec.channel, true)
end

function PlaceableTVSet:onDelete()
    local spec = self[PlaceableTVSet.SPEC_NAME]
    if spec == nil then
        return
    end
    if spec.triggerNode ~= nil then
        removeTrigger(spec.triggerNode)
        spec.triggerNode = nil
    end
    if spec.activatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
    end
end

function PlaceableTVSet:loadFromXMLFile(xmlFile, key)
    local spec = self[PlaceableTVSet.SPEC_NAME]
    local isOn    = xmlFile:getValue(key .. "#isOn", spec.isOn)
    local channel = xmlFile:getValue(key .. "#channel", spec.channel)
    self:setTVState(isOn, channel, true)
end

function PlaceableTVSet:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self[PlaceableTVSet.SPEC_NAME]
    xmlFile:setValue(key .. "#isOn", spec.isOn)
    xmlFile:setValue(key .. "#channel", spec.channel)
end

-- Sincroniza o estado para clientes que entram na partida
function PlaceableTVSet:onReadStream(streamId, connection)
    local isOn    = streamReadBool(streamId)
    local channel = streamReadUIntN(streamId, 4)
    self:setTVState(isOn, channel, true)
end

function PlaceableTVSet:onWriteStream(streamId, connection)
    local spec = self[PlaceableTVSet.SPEC_NAME]
    streamWriteBool(streamId, spec.isOn)
    streamWriteUIntN(streamId, spec.channel, 4)
end

function PlaceableTVSet:getTVState()
    return self[PlaceableTVSet.SPEC_NAME].isOn
end

function PlaceableTVSet:getTVChannel()
    return self[PlaceableTVSet.SPEC_NAME].channel
end

function PlaceableTVSet:getTVNumChannels()
    return #self[PlaceableTVSet.SPEC_NAME].channels
end

function PlaceableTVSet:toggleTVPower()
    self:setTVState(not self:getTVState(), self:getTVChannel())
end

function PlaceableTVSet:nextTVChannel()
    local num = self:getTVNumChannels()
    if num > 1 and self:getTVState() then
        self:setTVState(true, (self:getTVChannel() % num) + 1)
    end
end

function PlaceableTVSet:setTVState(isOn, channel, noEventSend)
    local spec = self[PlaceableTVSet.SPEC_NAME]
    local num = #spec.channels

    channel = math.max(1, math.min(channel or 1, math.max(num, 1)))

    TVSetStateEvent.sendEvent(self, isOn, channel, noEventSend)

    spec.isOn = isOn
    spec.channel = channel

    for i, node in ipairs(spec.channels) do
        setVisibility(node, isOn and i == channel)
    end

    spec.activatable:updateActionEvents()
end

function PlaceableTVSet:onTVTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    if g_localPlayer == nil or otherId ~= g_localPlayer.rootNode then
        return
    end

    local spec = self[PlaceableTVSet.SPEC_NAME]
    if onEnter then
        g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
    elseif onLeave then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
    end
end
