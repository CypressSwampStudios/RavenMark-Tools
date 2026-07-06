--[[----------------------------------------------------------------------------
RavenMark Core -- bootstrap, SavedVariables defaulting, slash commands.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...

local DEFAULTS = {
    schemaVersion = 1,
    global = {
        railPosition = { point = "LEFT", x = 22, y = 0 },
        railScale = 1.0,
        railLocked = false,
        snapThreshold = 40,
    },
    profiles = {},
}

local PROFILE_DEFAULTS = {
    moduleOrder = {
        "RavenMarkRoster", "RavenMarkAttendance", "RavenMarkLoot",
        "RavenMarkBench", "RavenMarkReady",
    },
    moduleState = {},
}

-- Deliberate stand-in for what AceDB would normally provide: recursively fill
-- any missing keys from the defaults without clobbering saved values.
local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
NS.CopyDefaults = CopyDefaults

local function Print(msg)
    print("|cff4fd8ffRavenMark|r " .. msg)
end
NS.Print = Print

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        RavenMarkCoreDB = CopyDefaults(RavenMarkCoreDB or {}, DEFAULTS)
        NS.db = RavenMarkCoreDB
    elseif event == "PLAYER_LOGIN" then
        -- Profile key needs the realm name, which is reliably available by
        -- PLAYER_LOGIN. Modules also register with the Dock at PLAYER_LOGIN;
        -- their ## OptionalDeps: RavenMarkCore makes Core load (and therefore
        -- register this handler) first, so the Rail exists before they do.
        local key = (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
        NS.db.profiles[key] = CopyDefaults(NS.db.profiles[key] or {}, PROFILE_DEFAULTS)
        NS.profile = NS.db.profiles[key]
        NS.BuildRail()
        NS.BuildOptions()
    end
end)

SLASH_RMCORE1 = "/rmcore"
SlashCmdList["RMCORE"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    local db = NS.db and NS.db.global
    if not db or not NS.rail then
        Print("still loading.")
        return
    end
    if cmd == "show" then
        NS.rail:Show()
    elseif cmd == "hide" then
        NS.rail:Hide()
    elseif cmd == "lock" then
        db.railLocked = true
        Print("Rail locked.")
    elseif cmd == "unlock" then
        db.railLocked = false
        Print("Rail unlocked.")
    elseif cmd == "reset" then
        db.railPosition = { point = DEFAULTS.global.railPosition.point,
                            x = DEFAULTS.global.railPosition.x,
                            y = DEFAULTS.global.railPosition.y }
        NS.ApplyRailPosition()
        Print("Rail position reset.")
    else
        Print("/rmcore show | hide | lock | unlock | reset")
    end
end
