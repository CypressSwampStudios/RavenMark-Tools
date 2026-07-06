--[[----------------------------------------------------------------------------
RavenMark Attendance -- attendance tied to the actual pull.

ENCOUNTER_START stamps the pull begin time (and mints the shared raidId if no
module has yet); ENCOUNTER_END cross-references the latest roster snapshot
(RavenMark Roster's, when installed; a direct group count otherwise) for
presence, increments the per-boss pull counter for this raidId, and emits an
"encounter" record.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...
local Export = LibStub("LibRavenExport-1.0")

NS.state = {
    current = nil,      -- in-progress encounter { name, startTime }
    pulls = {},         -- session pull list, newest first, for the panel
    sessionStart = nil, -- GetTime() of the first pull this session
}

local function PresentCount()
    local snap = RavenMarkRosterDB and RavenMarkRosterDB.lastSnapshot
    if snap and #snap > 0 then return #snap end
    return math.max(1, GetNumGroupMembers() or 1)
end

local function OnEncounterStart(encounterID, encounterName)
    Export:GetOrCreateRaidId()
    NS.state.current = { name = encounterName, startTime = GetTime() }
    NS.state.sessionStart = NS.state.sessionStart or GetTime()
end

local function OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    local current = NS.state.current
    NS.state.current = nil
    local duration = current and math.floor(GetTime() - current.startTime + 0.5) or 0

    local raidId = Export:GetOrCreateRaidId()
    local db = RavenMarkAttendanceDB
    db.pullCounters[raidId] = db.pullCounters[raidId] or {}
    local pullNumber = (db.pullCounters[raidId][encounterName] or 0) + 1
    db.pullCounters[raidId][encounterName] = pullNumber

    local presentCount = PresentCount()
    local presentPercent = 100
    if groupSize and groupSize > 0 then
        presentPercent = math.min(100, math.floor(presentCount / groupSize * 100 + 0.5))
    end

    local result = (success == 1) and "kill" or "wipe"

    Export:Emit("encounter", {
        pullNumber      = pullNumber,
        boss            = encounterName,
        result          = result,
        durationSeconds = duration,
        presentCount    = presentCount,
        presentPercent  = presentPercent,
    }, ADDON_NAME)

    table.insert(NS.state.pulls, 1, {
        pullNumber = pullNumber,
        boss = encounterName,
        result = result,
        durationSeconds = duration,
        presentPercent = presentPercent,
    })

    if NS.RefreshUI then NS.RefreshUI() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then
            RavenMarkAttendanceDB = RavenMarkAttendanceDB or {}
            RavenMarkAttendanceDB.schemaVersion = RavenMarkAttendanceDB.schemaVersion or 1
            RavenMarkAttendanceDB.records = RavenMarkAttendanceDB.records or {}
            RavenMarkAttendanceDB.pullCounters = RavenMarkAttendanceDB.pullCounters or {}
            RavenMarkAttendanceDB.ui = RavenMarkAttendanceDB.ui or {}
            Export:Init(RavenMarkAttendanceDB, ADDON_NAME)
        end
    elseif event == "PLAYER_LOGIN" then
        NS.SetupUI()
    elseif event == "ENCOUNTER_START" then
        OnEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd(...)
    end
end)
