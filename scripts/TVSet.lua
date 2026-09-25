--
-- TVSet (specialization de veículo/objeto)
-- TV carregável com liga/desliga e troca de canais
-- (cada canal é um plano do i3d; só um fica visível por vez)
-- Autor: AnJo888
--

TVSet = {}
TVSet.MOD_NAME  = g_currentModName
TVSet.SPEC_NAME = "spec_" .. g_currentModName .. ".tvSet"
TVSet.MAX_CHANNELS = 15 -- limite do stream (4 bits)

function TVSet.prerequisitesPresent(specializations)
    return true
end

function TVSet.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("TVSet")
    schema:register(XMLValueType.BOOL,       "vehicle.tvSet#defaultOn",        "Estado inicial", false)
    schema:register(XMLValueType.INT,        "vehicle.tvSet#defaultChannel",   "Canal inicial", 1)
    schema:register(XMLValueType.FLOAT,      "vehicle.tvSet#activationRadius", "Distância de interação (m)", 1.5)
    schema:register(XMLValueType.NODE_INDEX, "vehicle.tvSet.channel(?)#node",  "Plano da imagem do canal")
    schema:setXMLSpecializationType()

    local schemaSavegame = Vehicle.xmlSchemaSavegame
    local key = string.format("vehicles.vehicle(?).%s.tvSet", g_currentModName)
    schemaSavegame:register(XMLValueType.BOOL, key .. "#isOn",    "TV ligada")
    schemaSavegame:register(XMLValueType.INT,  key .. "#channel", "Canal atual")
end

function TVSet.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "setTVState",       TVSet.setTVState)
    SpecializationUtil.registerFunction(vehicleType, "getTVState",       TVSet.getTVState)
    SpecializationUtil.registerFunction(vehicleType, "getTVChannel",     TVSet.getTVChannel)
    SpecializationUtil.registerFunction(vehicleType, "getTVNumChannels", TVSet.getTVNumChannels)
    SpecializationUtil.registerFunction(vehicleType, "toggleTVPower",    TVSet.toggleTVPower)
    SpecializationUtil.registerFunction(vehicleType, "nextTVChannel",    TVSet.nextTVChannel)
end

function TVSet.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad",        TVSet)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete",      TVSet)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream",  TVSet)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", TVSet)
end

function TVSet:onLoad(savegame)
    local spec = self[TVSet.SPEC_NAME]
    local xmlFile = self.xmlFile

    spec.channels = {}
    xmlFile:iterate("vehicle.tvSet.channel", function(_, key)
        local node = xmlFile:getValue(key .. "#node", nil, self.components, self.i3dMappings)
        if node ~= nil then
            if #spec.channels < TVSet.MAX_CHANNELS then
                table.insert(spec.channels, node)
            else
                Logging.xmlWarning(xmlFile, "TVSet: máximo de %d canais", TVSet.MAX_CHANNELS)
            end
        else
            Logging.xmlWarning(xmlFile, "TVSet: node inválido em '%s'", key)
        end
    end)

    if #spec.channels == 0 then
        Logging.xmlWarning(xmlFile, "TVSet: nenhum canal definido")
    end

    local isOn    = xmlFile:getValue("vehicle.tvSet#defaultOn", false)
    local channel = xmlFile:getValue("vehicle.tvSet#defaultChannel", 1)
    spec.activationRadius = xmlFile:getValue("vehicle.tvSet#activationRadius", 1.5)

    if savegame ~= nil and not savegame.resetVehicles then
        local key = string.format("%s.%s.tvSet", savegame.key, TVSet.MOD_NAME)
        isOn    = savegame.xmlFile:getValue(key .. "#isOn", isOn)
        channel = savegame.xmlFile:getValue(key .. "#channel", channel)
    end

    -- Sem trigger: a TV se move, então a interação usa distância até o jogador
    spec.activatable = TVSetActivatable.new(self)
    if self.isClient then
        g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
    end

    self:setTVState(isOn, channel, true)
end

function TVSet:onDelete()
    local spec = self[TVSet.SPEC_NAME]
    if spec ~= nil and spec.activatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
    end
end

function TVSet:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self[TVSet.SPEC_NAME]
    xmlFile:setValue(key .. "#isOn", spec.isOn)
    xmlFile:setValue(key .. "#channel", spec.channel)
end

-- Sincroniza o estado para clientes que entram na partida
function TVSet:onReadStream(streamId, connection)
    local isOn    = streamReadBool(streamId)
    local channel = streamReadUIntN(streamId, 4)
    self:setTVState(isOn, channel, true)
end

function TVSet:onWriteStream(streamId, connection)
    local spec = self[TVSet.SPEC_NAME]
    streamWriteBool(streamId, spec.isOn)
    streamWriteUIntN(streamId, spec.channel, 4)
end

function TVSet:getTVState()
    return self[TVSet.SPEC_NAME].isOn
end

function TVSet:getTVChannel()
    return self[TVSet.SPEC_NAME].channel
end

function TVSet:getTVNumChannels()
    return #self[TVSet.SPEC_NAME].channels
end

function TVSet:toggleTVPower()
    self:setTVState(not self:getTVState(), self:getTVChannel())
end

function TVSet:nextTVChannel()
    local num = self:getTVNumChannels()
    if num > 1 and self:getTVState() then
        self:setTVState(true, (self:getTVChannel() % num) + 1)
    end
end

function TVSet:setTVState(isOn, channel, noEventSend)
    local spec = self[TVSet.SPEC_NAME]
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
