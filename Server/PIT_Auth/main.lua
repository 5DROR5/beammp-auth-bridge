-- =============================================================================
-- PIT Auth — Server Core
-- Version: 1.0.0
-- License: MIT
-- =============================================================================

-- =============================================================================
-- CONSTANTS
-- =============================================================================

local PLUGIN  = "[PIT_Auth]"
local ROOT    = "Resources/Server/PIT_Auth"
local DB_PATH = ROOT .. "/data/accounts.json"

-- =============================================================================
-- LOGGING
-- =============================================================================

local function log(msg) print(PLUGIN .. " " .. tostring(msg)) end

-- =============================================================================
-- FILE I/O
-- =============================================================================

local function ensureDataDir()
    os.execute('mkdir "' .. ROOT .. '/data" 2>nul')
    os.execute('mkdir -p "' .. ROOT .. '/data" 2>/dev/null')
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

local function writeFile(path, s)
    local f = io.open(path, "w+")
    if not f then return false end
    local ok = pcall(f.write, f, s); f:close(); return ok
end

-- =============================================================================
-- JSON
-- =============================================================================

local function jsonEnc(t)
    if type(Util) == "table" and Util.JsonEncode then
        local ok, s = pcall(Util.JsonEncode, t)
        if ok and type(s) == "string" then return s end
    end
    return nil
end

local function jsonDec(s)
    if type(s) ~= "string" then return nil end
    if type(Util) == "table" and Util.JsonDecode then
        local ok, t = pcall(Util.JsonDecode, s)
        if ok then return t end
    end
    return nil
end

-- =============================================================================
-- STORAGE
-- =============================================================================

local store = { accounts = {} }
local dirty = false

local function loadStore()
    local s = readFile(DB_PATH)
    if not s or s == "" then log("Starting with empty store"); return end
    local t = jsonDec(s)
    if type(t) == "table" then
        store.accounts = t.accounts or {}
        local n = 0; for _ in pairs(store.accounts) do n = n + 1 end
        log(string.format("Loaded %d account(s)", n))
    end
end

local function saveStore()
    local s = jsonEnc(store)
    if not s then log("ERROR: encode failed"); return end
    local tmp = DB_PATH .. ".tmp"
    if not writeFile(tmp, s) then log("ERROR: write failed"); return end
    if FS and FS.Rename then pcall(FS.Rename, tmp, DB_PATH)
    else writeFile(DB_PATH, s) end
    dirty = false
end

-- =============================================================================
-- ACCOUNTS
-- =============================================================================

local function getAccount(username)
    return store.accounts[username]
end

local function createAccount(username, password_hash, display_name)
    if store.accounts[username] then return false end
    store.accounts[username] = {
        password_hash = password_hash,
        display_name  = display_name,
        uid           = "pit_" .. username,
        created_at    = os.time(),
    }
    dirty = true
    return true
end

-- =============================================================================
-- UTILITIES
-- =============================================================================

local function isGuest(pid)
    local ids = (MP and MP.GetPlayerIdentifiers) and MP.GetPlayerIdentifiers(pid) or {}
    local function realId(s)
        return s and s ~= "" and not s:lower():match("^guest")
    end
    return not (realId(ids.beammp) or realId(ids.steam) or realId(ids.license))
end

local function isValidUsername(s)
    return type(s) == "string" and #s >= 3 and #s <= 20 and s:match("^[%w_%-]+$")
end

local function isValidHash(s)
    return type(s) == "string" and #s == 64 and s:match("^[%x]+$")
end

local function trigger(pid, event, data)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    pcall(MP.TriggerClientEvent, pid, event, data or "")
end

local function enc(t) return jsonEnc(t) or "{}" end

-- =============================================================================
-- TRANSLATIONS
-- =============================================================================

local cached_translations = nil

local function loadTranslations()
    if cached_translations then return cached_translations end
    local s = readFile(ROOT .. "/lang/en.json")
    if s then
        local t = jsonDec(s)
        if type(t) == "table" then
            cached_translations = t
            return cached_translations
        end
    end
    cached_translations = {}
    return cached_translations
end

-- =============================================================================
-- PLAYER STATE
-- =============================================================================

local pending          = {}
local auth_names       = {}
local awaiting_welcome = {}

local function sendStatus(pid)
    trigger(pid, "PIT_AUTH_Status", enc({
        auth_required = (pending[pid] == true),
        display_name  = auth_names[pid] or "",
        translations  = loadTranslations(),
        lang          = "en",
    }))
end

function PIT_AUTH_BroadcastNames()
    local players = {}
    for pid, _ in pairs(MP.GetPlayers() or {}) do
        if MP.IsPlayerConnected(pid) then
            local bname = (MP.GetPlayerName and MP.GetPlayerName(pid)) or ("Player" .. pid)
            table.insert(players, {
                id           = pid,
                display_name = auth_names[pid] or bname,
                beammp_name  = bname,
            })
        end
    end
    if #players == 0 then return end
    local payload = enc({ players = players })
    for pid, _ in pairs(MP.GetPlayers() or {}) do
        if MP.IsPlayerConnected(pid) then
            pcall(MP.TriggerClientEvent, pid, "PIT_AUTH_NamesList", payload)
        end
    end
end

local function updatePrefix(pid)
    if not (MP and MP.TriggerClientEvent) then return end
    local bname   = (MP.GetPlayerName and MP.GetPlayerName(pid)) or ("Player" .. pid)
    local payload = enc({ playerName = bname, displayName = auth_names[pid] or bname, pid = pid })
    for id, _ in pairs(MP.GetPlayers() or {}) do
        if MP.IsPlayerConnected(id) then
            pcall(MP.TriggerClientEvent, id, "PIT_AUTH_PrefixUpdate", payload)
        end
    end
end

-- =============================================================================
-- PLAYER EVENTS
-- =============================================================================

function PIT_AUTH_OnJoin(pid)
    log("Player joined: pid=" .. pid .. " guest=" .. tostring(isGuest(pid)))
    if isGuest(pid) then
        pending[pid]          = true
        awaiting_welcome[pid] = true
        sendStatus(pid)
    end
end

function PIT_AUTH_OnLeave(pid)
    pending[pid]          = nil
    auth_names[pid]       = nil
    awaiting_welcome[pid] = nil
end

-- =============================================================================
-- WELCOME CHECKER
-- =============================================================================

function PIT_AUTH_WelcomeChecker()
    for pid, _ in pairs(awaiting_welcome) do
        if MP.IsPlayerConnected(pid) then
            sendStatus(pid)
            awaiting_welcome[pid] = nil
        end
    end
end

-- =============================================================================
-- REQUEST STATUS
-- =============================================================================

function PIT_AUTH_OnRequestStatus(pid)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    sendStatus(pid)
end

-- =============================================================================
-- AUTH HANDLER
-- =============================================================================

function PIT_AUTH_OnAuth(pid, raw)
    if not pending[pid] then return end
    local data = jsonDec(raw)
    if not data or not data.mode or not data.username or not data.hash then
        trigger(pid, "PIT_AUTH_Result", enc({ ok = false, error = "auth_invalid" }))
        return
    end

    local mode     = data.mode
    local uname    = (data.username:match("^%s*(.-)%s*$") or ""):lower()
    local udisplay = data.username:match("^%s*(.-)%s*$") or ""
    local hash     = data.hash

    if not isValidUsername(uname) then
        trigger(pid, "PIT_AUTH_Result", enc({ ok = false, error = "auth_username_invalid" }))
        return
    end
    if not isValidHash(hash) then
        trigger(pid, "PIT_AUTH_Result", enc({ ok = false, error = "auth_invalid" }))
        return
    end

    if mode == "register" then
        if not createAccount(uname, hash, udisplay) then
            trigger(pid, "PIT_AUTH_Result", enc({ ok = false, error = "auth_username_taken" }))
            return
        end
    else
        local acc = getAccount(uname)
        if not acc then
            trigger(pid, "PIT_AUTH_Result", enc({ ok = false, error = "auth_not_found" }))
            return
        end
        if acc.password_hash ~= hash then
            trigger(pid, "PIT_AUTH_Result", enc({ ok = false, error = "auth_wrong_password" }))
            return
        end
        udisplay = acc.display_name or udisplay
    end

    pending[pid]          = nil
    auth_names[pid]       = udisplay
    awaiting_welcome[pid] = nil

    trigger(pid, "PIT_AUTH_Result", enc({ ok = true, display_name = udisplay }))
    sendStatus(pid)
    updatePrefix(pid)
    PIT_AUTH_BroadcastNames()
    log(string.format("[%s] pid=%d -> '%s'", mode, pid, udisplay))
end

-- =============================================================================
-- AUTOSAVE
-- =============================================================================

function PIT_AUTH_Autosave()
    if dirty then saveStore() end
end

-- =============================================================================
-- INIT
-- =============================================================================

function PIT_AUTH_OnInit()
    log("=== PIT Auth v1.0.0 initializing ===")
    ensureDataDir()
    loadStore()
    loadTranslations()
    log("=== PIT Auth ready ===")
end

MP.RegisterEvent("onInit",                  "PIT_AUTH_OnInit")
MP.RegisterEvent("onPlayerJoining",         "PIT_AUTH_OnJoin")
MP.RegisterEvent("onPlayerDisconnect",      "PIT_AUTH_OnLeave")
MP.RegisterEvent("PIT_AUTH_Auth",           "PIT_AUTH_OnAuth")
MP.RegisterEvent("PIT_AUTH_RequestStatus",  "PIT_AUTH_OnRequestStatus")
MP.RegisterEvent("PIT_AUTH_WelcomeChecker", "PIT_AUTH_WelcomeChecker")
MP.RegisterEvent("PIT_AUTH_BroadcastNames", "PIT_AUTH_BroadcastNames")
MP.RegisterEvent("PIT_AUTH_Autosave",       "PIT_AUTH_Autosave")
MP.CreateEventTimer("PIT_AUTH_WelcomeChecker", 500)
MP.CreateEventTimer("PIT_AUTH_BroadcastNames", 500)
MP.CreateEventTimer("PIT_AUTH_Autosave",       30000)