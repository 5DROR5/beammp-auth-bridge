-- =============================================================================
-- DescUpdater
-- Updates the server description with display names
-- License: MIT
-- =============================================================================

local M = {}
local MP, auth_names, log

local FIXED_DESC = ""
local SEPARATOR  = "^p^e____________________________________________________________________________________________________"
local TICK_MS    = 10000

local lastDesc = nil

function M.updateDesc()
    local entries = {}
    local count   = 0

    for pid, _ in pairs(MP.GetPlayers()) do
        if MP.IsPlayerConnected(pid) then
            count = count + 1
            local bname   = MP.GetPlayerName(pid)
            local display = auth_names[pid]

            if display then
                table.insert(entries, "^f" .. display)
            else
                table.insert(entries, "^2" .. bname)
            end
        end
    end

    local player_line
    if count == 0 then
        player_line = "^p^2No players online."
    else
        player_line = "^p^fOnline ^a(" .. count .. ")^f: "
                      .. table.concat(entries, " ^f\xE2\x80\xA2 ")
    end

    local newDesc = FIXED_DESC .. player_line .. SEPARATOR
    if newDesc ~= lastDesc then
        lastDesc = newDesc
        MP.Set(MP.Settings.Description, newDesc)
    end
end

function M.init(deps)
    MP         = deps.MP
    auth_names = deps.auth_names
    log        = deps.log or print

    MP.CreateEventTimer("PIT_AUTH_DescTick", TICK_MS)
    MP.RegisterEvent("PIT_AUTH_DescTick", "PIT_AUTH_DescTick")

    log("DescUpdater initialized")
end

return M
