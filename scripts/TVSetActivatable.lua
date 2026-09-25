--
-- TVSetActivatable
-- Prompts quando o jogador está perto da TV (por distância, sem trigger):
--   ACTIVATE_OBJECT  -> liga/desliga
--   TV_NEXT_CHANNEL  -> próximo canal (só com a TV ligada)
--

TVSetActivatable = {}
local TVSetActivatable_mt = Class(TVSetActivatable)

function TVSetActivatable.new(vehicle)
    local self = setmetatable({}, TVSetActivatable_mt)
    self.vehicle = vehicle
    self.activateText = ""
    self.powerEventId = nil
    self.channelEventId = nil
    return self
end

function TVSetActivatable:getIsActivatable()
    if g_localPlayer == nil or g_localPlayer.rootNode == nil then
        return false
    end
    -- Em MP, só quem tem acesso à fazenda dona pode usar
    if not g_currentMission.accessHandler:canPlayerAccess(self.vehicle) then
        return false
    end
    local px, py, pz = getWorldTranslation(g_localPlayer.rootNode)
    local spec = self.vehicle[TVSet.SPEC_NAME]
    return self:getDistance(px, py, pz) <= spec.activationRadius
end

function TVSetActivatable:getDistance(x, y, z)
    local tx, ty, tz = getWorldTranslation(self.vehicle.rootNode)
    return MathUtil.vector3Length(x - tx, y - ty, z - tz)
end

-- Fallback caso o sistema chame run() diretamente
function TVSetActivatable:run()
    self.vehicle:toggleTVPower()
end

-- Com registerCustomInput, o próprio activatable registra os inputs
-- (inclusive o ACTIVATE_OBJECT), permitindo ter mais de uma ação.
function TVSetActivatable:registerCustomInput(inputContext)
    local _, powerId = g_inputBinding:registerActionEvent(InputAction.ACTIVATE_OBJECT, self, self.onPowerAction, false, true, false, true)
    g_inputBinding:setActionEventTextPriority(powerId, GS_PRIO_VERY_HIGH)
    self.powerEventId = powerId

    local _, channelId = g_inputBinding:registerActionEvent(InputAction.TV_NEXT_CHANNEL, self, self.onChannelAction, false, true, false, true)
    g_inputBinding:setActionEventTextPriority(channelId, GS_PRIO_HIGH)
    self.channelEventId = channelId

    self:updateActionEvents()
end

function TVSetActivatable:removeCustomInput(inputContext)
    g_inputBinding:removeActionEventsByTarget(self)
    self.powerEventId = nil
    self.channelEventId = nil
end

function TVSetActivatable:onPowerAction(actionName, inputValue, callbackState, isAnalog)
    self.vehicle:toggleTVPower()
end

function TVSetActivatable:onChannelAction(actionName, inputValue, callbackState, isAnalog)
    self.vehicle:nextTVChannel()
end

function TVSetActivatable:updateActionEvents()
    local isOn = self.vehicle:getTVState()

    if isOn then
        self.activateText = g_i18n:getText("action_tvTurnOff")
    else
        self.activateText = g_i18n:getText("action_tvTurnOn")
    end

    if self.powerEventId ~= nil then
        g_inputBinding:setActionEventText(self.powerEventId, self.activateText)
    end

    if self.channelEventId ~= nil then
        local showChannel = isOn and self.vehicle:getTVNumChannels() > 1
        g_inputBinding:setActionEventActive(self.channelEventId, showChannel)
        if showChannel then
            local text = string.format(g_i18n:getText("action_tvNextChannel"),
                self.vehicle:getTVChannel(), self.vehicle:getTVNumChannels())
            g_inputBinding:setActionEventText(self.channelEventId, text)
        end
    end
end
