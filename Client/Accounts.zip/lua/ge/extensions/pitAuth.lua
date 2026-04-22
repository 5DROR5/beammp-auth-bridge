-- =============================================================================
-- PIT Auth — Client Extension
-- Version: 1.0.0
-- License: MIT
-- =============================================================================

-- =============================================================================
-- CONSTANTS
-- =============================================================================

local M      = {}
local PLUGIN = "[PIT_Auth]"

-- =============================================================================
-- LOGGING
-- =============================================================================

local function log(msg) print(PLUGIN .. " " .. tostring(msg)) end

-- =============================================================================
-- STATE
-- =============================================================================

local registered          = false
local retry_acc           = 0
local pendingLayout       = nil
local layoutForced        = false
local pendingNamesRequest = nil
local displayNames        = {}

log("Extension file loaded")

-- =============================================================================
-- HELPERS
-- =============================================================================

local function guiTrigger(event, data)
    if type(guihooks) == "table" and type(guihooks.trigger) == "function" then
        guihooks.trigger(event, data)
    end
end

local function decodePayload(payload)
    if type(payload) == "string" then
        local ok, decoded = pcall(jsonDecode, payload)
        return ok and decoded or nil
    end
    return payload
end

local function requestStatus()
    if type(TriggerServerEvent) == "function" then
        log("Requesting status from server")
        TriggerServerEvent("PIT_AUTH_RequestStatus", "")
    end
end

local function requestNamesBroadcast()
    if type(TriggerServerEvent) == "function" then
        log("Requesting names broadcast from server")
        TriggerServerEvent("PIT_AUTH_BroadcastNames", "")
    end
end

-- =============================================================================
-- VEHICLE NAMES
-- =============================================================================

local function applyCustomName(beammpName, displayName)
    pcall(function()
        if not (extensions and extensions.MPVehicleGE
                and extensions.MPVehicleGE.getVehicles) then return end
        local vehs = extensions.MPVehicleGE.getVehicles()
        if not vehs then return end
        for _, v in pairs(vehs) do
            local ok, owner = pcall(function() return v:getOwner() end)
            if ok and owner and owner.name == beammpName then
                v.customName = displayName
            end
        end
    end)
end

-- =============================================================================
-- EVENT REGISTRATION
-- =============================================================================

local function tryRegister()
    if registered then return end
    if type(AddEventHandler) ~= "function" then return end

    AddEventHandler("PIT_AUTH_Status", function(payload)
        log("PIT_AUTH_Status received")
        local data = decodePayload(payload)
        if type(data) ~= "table" then return end
        guiTrigger("PIT_AUTH_Status", data)
    end)

    AddEventHandler("PIT_AUTH_Result", function(payload)
        log("PIT_AUTH_Result received")
        local data = decodePayload(payload)
        if type(data) ~= "table" then return end
        if data.ok then
            pcall(function()
                if core_gamestate and core_gamestate.setGameState then
                    core_gamestate.setGameState('multiplayer', 'multiplayer', 'multiplayer')
                end
            end)
        end
        guiTrigger("PIT_AUTH_Result", data)
    end)

    AddEventHandler("PIT_AUTH_PrefixUpdate", function(payload)
        local data = decodePayload(payload)
        if type(data) ~= "table" then return end

        local playerName  = tostring(data.playerName  or "")
        local displayName = tostring(data.displayName or "")
        if playerName == "" then return end

        applyCustomName(playerName, displayName)

        pcall(function()
            if type(MPVehicleGE) == "table" then
                if type(MPVehicleGE.setPlayerNickPrefix) == "function" then
                    MPVehicleGE.setPlayerNickPrefix(playerName, "pit_auth_name", "")
                end
                if type(MPVehicleGE.setPlayerNickSuffix) == "function" then
                    MPVehicleGE.setPlayerNickSuffix(playerName, "pit_auth_suffix", "")
                end
            end
        end)

        displayNames[playerName] = displayName
        guiTrigger("PIT_DisplayNames", displayNames)
    end)

    AddEventHandler("PIT_AUTH_NamesList", function(payload)
        local data = decodePayload(payload)
        if type(data) ~= "table" or not data.players then return end

        for _, player in ipairs(data.players) do
            local bname = tostring(player.beammp_name  or "")
            local dname = tostring(player.display_name or "")
            if bname ~= "" and dname ~= "" then
                applyCustomName(bname, dname)
                displayNames[bname] = dname
            end
        end

        guiTrigger("PIT_DisplayNames",      displayNames)
        guiTrigger("PlayerList_CustomData", data)
    end)

    registered = true
    log("Event handlers registered")
    requestStatus()
end

-- =============================================================================
-- EXTENSION LIFECYCLE
-- =============================================================================

M.onInit = function()
    setExtensionUnloadMode(M, "manual")
end

M.onExtensionLoaded = function()
    registered = false
    tryRegister()
end

M.onWorldReadyState = function(newState)
    if newState == 2 and not layoutForced then
        pendingLayout = 0.2
        layoutForced  = true
    end
end

M.onUpdate = function(dt)
    if pendingLayout then
        pendingLayout = pendingLayout - dt
        if pendingLayout <= 0 then
            pendingLayout = nil
            local inMP = MPCoreNetwork
                and type(MPCoreNetwork.isMPSession) == "function"
                and MPCoreNetwork.isMPSession()
            if inMP and core_gamestate and core_gamestate.setGameState then
                log("Forcing Accounts layout")
                pcall(function()
                    core_gamestate.setGameState('multiplayer', 'Accounts', 'multiplayer')
                end)
                pendingNamesRequest = 0.5
            end
        end
    end

    if pendingNamesRequest then
        pendingNamesRequest = pendingNamesRequest - dt
        if pendingNamesRequest <= 0 then
            pendingNamesRequest = nil
            log("Requesting names broadcast after layout reload")
            requestNamesBroadcast()
        end
    end

    if not registered then
        retry_acc = retry_acc + dt
        if retry_acc >= 1.0 then
            retry_acc = 0
            tryRegister()
        end
    end
end

tryRegister()

return M