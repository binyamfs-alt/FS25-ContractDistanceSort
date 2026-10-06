ContractDistanceSort = {}

ContractDistanceSort.MOD_NAME = g_currentModName or "FS25_ContractDistanceSort"
ContractDistanceSort.actionEventId = nil

local function logInfo(message, ...)
    Logging.info("[%s] %s", ContractDistanceSort.MOD_NAME, string.format(message, ...))
end

local function getPlayerPosition()
    if g_currentMission == nil then
        return nil, nil
    end

    local vehicle = nil
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        vehicle = g_localPlayer:getCurrentVehicle()
    end

    if vehicle ~= nil and vehicle.rootNode ~= nil then
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        return x, z, "vehicle"
    end

    if g_localPlayer ~= nil and g_localPlayer.rootNode ~= nil then
        local x, _, z = getWorldTranslation(g_localPlayer.rootNode)
        return x, z, "player"
    end

    return nil, nil
end

local function getMissionPosition(mission)
    if mission == nil then
        return nil, nil
    end

    if mission.getWorldPosition ~= nil then
        local x, z = mission:getWorldPosition()
        if x ~= nil and z ~= nil then
            return x, z
        end
    end

    if mission.field ~= nil and mission.field.getIndicatorPosition ~= nil then
        local x, z = mission.field:getIndicatorPosition()
        if x ~= nil and z ~= nil then
            return x, z
        end
    end

    return nil, nil
end

local function showMessage(textName)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            g_i18n:getText(textName)
        )
    end
end

local function getBaseTitle(title)
    -- Remove only the suffix created by this mod so sorting repeatedly does not
    -- stack distance labels on the same contract title.
    return string.gsub(title or "", " — %d+%.?%d* [^ ]+$", "")
end

local function formatDistance(distanceSquared)
    local distanceMeters = math.sqrt(distanceSquared)
    local usesImperialUnits = g_i18n:getDistance(1) < 0.8

    if usesImperialUnits then
        return string.format("%.0f yd", distanceMeters * 1.0936133)
    end

    return string.format("%.0f m", distanceMeters)
end

function ContractDistanceSort.sortActiveContracts()
    if g_currentMission == nil or g_currentMission.hud == nil or g_missionManager == nil then
        return
    end

    local playerX, playerZ, positionSource = getPlayerPosition()
    if playerX == nil then
        return
    end

    local farmId = g_currentMission:getFarmId()
    local missions = g_missionManager:getMissionsByFarmId(farmId) or {}
    local sortable = {}

    for originalIndex, mission in ipairs(missions) do
        local isDisplayedStatus = mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.FINISHED
        local isLocalFarm = mission.farmId == farmId

        if isDisplayedStatus and isLocalFarm and mission.progressBar ~= nil then
            local x, z = getMissionPosition(mission)
            if x ~= nil then
                local dx = x - playerX
                local dz = z - playerZ
                table.insert(sortable, {
                    mission = mission,
                    distanceSquared = dx * dx + dz * dz,
                    originalIndex = originalIndex,
                    title = getBaseTitle(mission.progressBar.title or g_i18n:getText("contract_title")),
                    text = mission.progressBar.text or mission.progressTitle or "",
                    progress = mission.progressBar.progress or mission.completion or 0
                })
            end
        end
    end

    if #sortable == 0 then
        showMessage("cds_noContracts")
        return
    end

    table.sort(sortable, function(a, b)
        if a.distanceSquared == b.distanceSquared then
            return a.originalIndex < b.originalIndex
        end
        return a.distanceSquared < b.distanceSquared
    end)

    -- The HUD keeps progress bars in creation order. Recreating only the mission
    -- bars changes their presentation order without reordering MissionManager data.
    for _, item in ipairs(sortable) do
        g_currentMission.hud:removeSideNotificationProgressBar(item.mission.progressBar)
        item.mission.progressBar = nil
    end

    for _, item in ipairs(sortable) do
        local progressBar = g_currentMission.hud:addSideNotificationProgressBar(
            string.format("%s — %s", item.title, formatDistance(item.distanceSquared)),
            item.text,
            item.progress
        )
        item.mission.progressBar = progressBar
        g_currentMission.hud:markSideNotificationProgressBarForDrawing(progressBar)
    end

    showMessage("cds_sortComplete")
    logInfo(
        "Sorted %d active field contracts by distance from %s position (%.1f, %.1f)",
        #sortable,
        positionSource or "unknown",
        playerX,
        playerZ
    )
end

function ContractDistanceSort.onSortAction()
    ContractDistanceSort.sortActiveContracts()
end

function ContractDistanceSort.registerActionEvents(_, controlling)
    if g_dedicatedServer ~= nil or g_inputBinding == nil then
        return
    end

    if ContractDistanceSort.actionEventId ~= nil then
        g_inputBinding:removeActionEvent(ContractDistanceSort.actionEventId)
        ContractDistanceSort.actionEventId = nil
    end

    local success, actionEventId = g_inputBinding:registerActionEvent(
        "CDS_SORT_CONTRACTS",
        ContractDistanceSort,
        ContractDistanceSort.onSortAction,
        false,
        true,
        false,
        true,
        nil,
        false
    )

    if success or controlling == "VEHICLE" then
        ContractDistanceSort.actionEventId = actionEventId
        if actionEventId ~= nil then
            g_inputBinding:setActionEventTextVisibility(actionEventId, false)
        end
    else
        Logging.warning("[%s] Could not register the sort action", ContractDistanceSort.MOD_NAME)
    end
end

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
    PlayerInputComponent.registerGlobalPlayerActionEvents,
    ContractDistanceSort.registerActionEvents
)

logInfo("Loaded")
