--[[----------------------------------------------------------------------------
RavenMark Bench -- officer-curated standby tracking.

No automatic hooks: an officer manually toggles a member's bench/active status
in the panel. Each toggle emits a "bench_assignment" record and persists the
current state in RavenMarkBenchDB.current so the board is correct after a
/reload.

Roster source: reuses RavenMark Roster's latest snapshot when that addon is
installed (per spec, roster reading is not re-implemented here); standalone,
it falls back to a minimal direct group scan so the addon still works alone.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...
local Export = LibStub("LibRavenExport-1.0")

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        units[#units + 1] = "player"
        for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
    else
        units[1] = "player"
    end
    return units
end

-- The list the panel renders: Roster's snapshot when available, else a
-- minimal fallback scan. Status always comes from our own persisted state.
function NS.GetList()
    local list = {}
    local snap = RavenMarkRosterDB and RavenMarkRosterDB.lastSnapshot
    if snap and #snap > 0 then
        for _, member in ipairs(snap) do
            list[#list + 1] = { name = member.name, class = member.class }
        end
    else
        for _, unit in ipairs(GroupUnits()) do
            local name = UnitName(unit)
            if name then
                local _, classFile = UnitClass(unit)
                list[#list + 1] = { name = name, class = classFile or "UNKNOWN" }
            end
        end
    end
    for _, entry in ipairs(list) do
        entry.status = RavenMarkBenchDB.current[entry.name] or "active"
    end
    return list
end

function NS.Toggle(name)
    local db = RavenMarkBenchDB
    local newStatus = (db.current[name] == "bench") and "active" or "bench"
    if newStatus == "active" then
        db.current[name] = nil -- active is the default; keep the table sparse
    else
        db.current[name] = newStatus
    end

    Export:GetOrCreateRaidId()
    Export:Emit("bench_assignment", {
        member = name,
        status = newStatus,
        reason = "", -- v1 has no reason input; field kept for schema stability
    }, ADDON_NAME)

    if NS.RefreshUI then NS.RefreshUI() end
    -- keep Roster's active/bench chips in sync if it's installed
    local rosterNS = _G.RavenMarkRoster_QueueSnapshot
    if rosterNS then rosterNS() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        RavenMarkBenchDB = RavenMarkBenchDB or {}
        RavenMarkBenchDB.schemaVersion = RavenMarkBenchDB.schemaVersion or 1
        RavenMarkBenchDB.records = RavenMarkBenchDB.records or {}
        RavenMarkBenchDB.current = RavenMarkBenchDB.current or {}
        RavenMarkBenchDB.ui = RavenMarkBenchDB.ui or {}
        Export:Init(RavenMarkBenchDB, ADDON_NAME)
    elseif event == "PLAYER_LOGIN" then
        NS.SetupUI()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if NS.RefreshUI then
            C_Timer.After(1.2, NS.RefreshUI) -- just after Roster's debounced snapshot
        end
    end
end)
