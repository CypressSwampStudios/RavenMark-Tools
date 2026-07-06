--[[----------------------------------------------------------------------------
RavenMark Roster -- live raid/group snapshots.

Hooks GROUP_ROSTER_UPDATE (debounced, since it fires in bursts) and emits a
"roster_snapshot" record per settled change. The latest snapshot is also kept
at RavenMarkRosterDB.lastSnapshot so sibling addons (Attendance, Bench) can
reuse it instead of re-implementing roster reading.

Spec note: GetSpecialization/GetSpecializationInfo only cover the player.
Other members' specs require the async INSPECT flow (NotifyInspect +
INSPECT_READY), which is rate-limited and unreliable mid-raid -- deliberately
out of v1 scope, so spec is only populated for the player. No fake data.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...
local Export = LibStub("LibRavenExport-1.0")

NS.state = { snapshot = nil }

local function PlayerSpecName()
    if GetSpecialization and GetSpecializationInfo then
        local index = GetSpecialization()
        if index then
            local _, name = GetSpecializationInfo(index)
            return name
        end
    end
    return nil
end

local function ShortName(name)
    return name and name:match("^([^%-]+)") or name
end

local function BenchStatus(name)
    -- Reads RavenMark Bench's persisted assignments when that addon is
    -- installed; defaults to active otherwise.
    local bench = RavenMarkBenchDB and RavenMarkBenchDB.current
    local status = bench and (bench[name] or bench[ShortName(name)])
    return status == "bench" and "bench" or "active"
end

function NS.BuildSnapshot()
    local members = {}
    local playerName = UnitName("player")

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, classLoc, classFile, _, _, _, _, _, combatRole = GetRaidRosterInfo(i)
            if name then
                members[#members + 1] = {
                    name   = name,
                    class  = classFile or classLoc or "UNKNOWN",
                    spec   = (ShortName(name) == playerName) and PlayerSpecName() or nil,
                    role   = (combatRole and combatRole ~= "NONE") and combatRole or nil,
                    status = BenchStatus(name),
                }
            end
        end
    else
        local units = { "player" }
        if IsInGroup() then
            for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
        end
        for _, unit in ipairs(units) do
            local name = UnitName(unit)
            if name then
                local _, classFile = UnitClass(unit)
                local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
                members[#members + 1] = {
                    name   = name,
                    class  = classFile or "UNKNOWN",
                    spec   = (unit == "player") and PlayerSpecName() or nil,
                    role   = (role and role ~= "NONE") and role or nil,
                    status = BenchStatus(name),
                }
            end
        end
    end

    return members
end

local function TakeSnapshot()
    local members = NS.BuildSnapshot()
    NS.state.snapshot = members
    RavenMarkRosterDB.lastSnapshot = members

    if IsInGroup() then
        -- whichever module snapshots first mints the shared raidId
        Export:GetOrCreateRaidId()
    end
    Export:Emit("roster_snapshot", { members = members }, ADDON_NAME)

    if NS.RefreshUI then NS.RefreshUI() end
end

local pending = false
local function QueueSnapshot()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        TakeSnapshot()
    end)
end
NS.QueueSnapshot = QueueSnapshot
-- Small cross-addon hook: Bench nudges a fresh snapshot after a toggle so the
-- active/bench chips stay in sync. Addons can't reach each other's private
-- namespaces, so this one function is exposed globally.
_G.RavenMarkRoster_QueueSnapshot = QueueSnapshot

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        RavenMarkRosterDB = RavenMarkRosterDB or {}
        RavenMarkRosterDB.schemaVersion = RavenMarkRosterDB.schemaVersion or 1
        RavenMarkRosterDB.records = RavenMarkRosterDB.records or {}
        RavenMarkRosterDB.ui = RavenMarkRosterDB.ui or {}
        Export:Init(RavenMarkRosterDB, ADDON_NAME)
    elseif event == "PLAYER_LOGIN" then
        NS.SetupUI()
        QueueSnapshot()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if RavenMarkRosterDB then QueueSnapshot() end
    end
end)
