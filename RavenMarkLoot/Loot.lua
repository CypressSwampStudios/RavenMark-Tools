--[[----------------------------------------------------------------------------
RavenMark Loot -- loot event log. Item, recipient, source. No DKP math.

Two capture paths, deduplicated against each other:
  1. CHAT_MSG_LOOT, parsed with Lua patterns generated from Blizzard's own
     LOOT_ITEM* global strings (locale-safe: the client localizes the globals
     and the patterns are derived from whatever they contain at runtime).
  2. ENCOUNTER_LOOT_RECEIVED for personal loot from encounters. If this event
     name has changed in 12.0.7, the register call is pcall-guarded and the
     chat path still covers everything -- see BUILD_NOTES.md.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...
local Export = LibStub("LibRavenExport-1.0")

NS.state = {
    items = {},            -- session item list, newest first, for the panel
    currentEncounter = nil,
    recent = {},           -- dedupe map: "recipient::itemLink" -> GetTime()
}

local DEDUPE_WINDOW = 5 -- seconds

-- Convert a Blizzard global string ("%s receives loot: %s.") into an anchored
-- Lua pattern with (.+) captures. Handles positional forms like %1$s too.
local function GlobalStringToPattern(gs)
    if type(gs) ~= "string" then return nil end
    gs = gs:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1") -- escape magic chars
    gs = gs:gsub("%%%%%d+%%%$s", "(.+)")                 -- %1$s .. %n$s
    gs = gs:gsub("%%%%%d+%%%$d", "(%%d+)")               -- %1$d .. %n$d
    gs = gs:gsub("%%%%s", "(.+)")                        -- %s
    gs = gs:gsub("%%%%d", "(%%d+)")                      -- %d
    return "^" .. gs .. "$"
end

-- Most-specific first so the "x%d" multiple variants win over the plain ones.
local PATTERNS = {}
local function AddPattern(gs, selfLoot)
    local pat = GlobalStringToPattern(gs)
    if pat then PATTERNS[#PATTERNS + 1] = { pat = pat, selfLoot = selfLoot } end
end
AddPattern(LOOT_ITEM_MULTIPLE, false)      -- "%s receives loot: %sx%d."
AddPattern(LOOT_ITEM_SELF_MULTIPLE, true)  -- "You receive loot: %sx%d."
AddPattern(LOOT_ITEM, false)               -- "%s receives loot: %s."
AddPattern(LOOT_ITEM_SELF, true)           -- "You receive loot: %s."

local function CurrentSource()
    if NS.state.currentEncounter then return NS.state.currentEncounter end
    local instanceName = GetInstanceInfo and GetInstanceInfo() or nil
    return instanceName or "world"
end

local function CurrentLootMode()
    if GetLootMethod then
        local ok, method = pcall(GetLootMethod)
        if ok and method then return method end
    end
    return "personal"
end

local function RecordLoot(recipient, itemLink)
    if not recipient or not itemLink then return end

    local key = recipient .. "::" .. itemLink
    local now = GetTime()
    if NS.state.recent[key] and (now - NS.state.recent[key]) < DEDUPE_WINDOW then
        return
    end
    NS.state.recent[key] = now

    local source = CurrentSource()
    Export:Emit("loot_event", {
        itemLink  = itemLink,
        recipient = recipient,
        source    = source,
        lootMode  = CurrentLootMode(),
    }, ADDON_NAME)

    table.insert(NS.state.items, 1, {
        itemLink = itemLink,
        recipient = recipient,
        source = source,
    })
    if #NS.state.items > 200 then table.remove(NS.state.items) end

    if NS.RefreshUI then NS.RefreshUI() end
end

local function OnLootMessage(msg)
    for _, entry in ipairs(PATTERNS) do
        local a, b = msg:match(entry.pat)
        if a then
            local recipient, itemLink
            if entry.selfLoot then
                recipient, itemLink = UnitName("player"), a
            else
                recipient, itemLink = a, b
            end
            -- only log actual item links, not currency/reputation lines
            if itemLink and itemLink:find("|Hitem:", 1, true) then
                RecordLoot(recipient, itemLink)
            end
            return
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
-- Guarded: if the personal-loot event name changed in this client, don't take
-- the whole addon down -- the chat path still works.
pcall(eventFrame.RegisterEvent, eventFrame, "ENCOUNTER_LOOT_RECEIVED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            RavenMarkLootDB = RavenMarkLootDB or {}
            RavenMarkLootDB.schemaVersion = RavenMarkLootDB.schemaVersion or 1
            RavenMarkLootDB.records = RavenMarkLootDB.records or {}
            RavenMarkLootDB.ui = RavenMarkLootDB.ui or {}
            Export:Init(RavenMarkLootDB, ADDON_NAME)
        end
    elseif event == "PLAYER_LOGIN" then
        NS.SetupUI()
    elseif event == "CHAT_MSG_LOOT" then
        local msg = ...
        if IsInGroup() then OnLootMessage(msg) end
    elseif event == "ENCOUNTER_START" then
        local _, encounterName = ...
        NS.state.currentEncounter = encounterName
    elseif event == "ENCOUNTER_END" then
        -- keep the boss name as loot source briefly; personal loot lands
        -- right after the kill
        local _, encounterName = ...
        NS.state.currentEncounter = encounterName
        C_Timer.After(30, function()
            if NS.state.currentEncounter == encounterName then
                NS.state.currentEncounter = nil
            end
        end)
    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        local _, _, itemLink, _, playerName = ...
        RecordLoot(playerName, itemLink)
    end
end)
