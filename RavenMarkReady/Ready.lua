--[[----------------------------------------------------------------------------
RavenMark Ready -- pre-pull flask/food/durability check, on demand.

Manual trigger only (the "Check Readiness" button). Deliberately NOT automatic
or per-frame: an officer clicks it right before a pull. Non-combat aura and
durability reads only.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...
local Export = LibStub("LibRavenExport-1.0")

--------------------------------------------------------------------------
-- EDIT ME: consumable buff names RavenMark Ready looks for.
--
-- Keys are exact (localized) aura names; the value just needs to be true.
-- Add or remove lines freely as tiers change -- nothing else in the addon
-- needs to change. These defaults are the last-verified retail flask names
-- plus the generic food buff; UPDATE THEM FOR THE CURRENT MIDNIGHT TIER
-- (see BUILD_NOTES.md).
--------------------------------------------------------------------------
NS.CONSUMABLE_BUFFS = {
    flask = {
        ["Flask of Alchemical Chaos"]        = true,
        ["Flask of Tempered Aggression"]     = true,
        ["Flask of Tempered Swiftness"]      = true,
        ["Flask of Tempered Mastery"]        = true,
        ["Flask of Tempered Versatility"]    = true,
        ["Flask of Saving Graces"]           = true,
    },
    food = {
        ["Well Fed"] = true,
    },
}

-- Equipment slots that carry durability (skips shirt/tabard).
local DURABILITY_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

NS.state = {
    lastResult = nil, -- { flagged = {...}, clearCount = n, total = n }
}

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

-- Iterate a unit's helpful auras across API generations: C_UnitAuras is
-- current; UnitAura is the legacy fallback for safety.
local function EachHelpfulAura(unit, fn)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local i = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not aura then break end
            fn(aura.name)
            i = i + 1
        end
    elseif UnitAura then
        local i = 1
        while true do
            local name = UnitAura(unit, i, "HELPFUL")
            if not name then break end
            fn(name)
            i = i + 1
        end
    end
end

local function PlayerMinDurabilityPercent()
    local minPct
    for _, slot in ipairs(DURABILITY_SLOTS) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not minPct or pct < minPct then minPct = pct end
        end
    end
    return minPct
end

-- Run the scan. Buff checks cover every group member in aura range;
-- durability is only readable for the player (API constraint, see
-- BUILD_NOTES.md).
function NS.RunCheck()
    local flagged = {}
    local flaggedMembers = {}
    local units = GroupUnits()

    for _, unit in ipairs(units) do
        local name = UnitName(unit)
        if name and (not UnitIsConnected or UnitIsConnected(unit)) then
            local hasFlask, hasFood = false, false
            EachHelpfulAura(unit, function(auraName)
                if NS.CONSUMABLE_BUFFS.flask[auraName] then hasFlask = true end
                if NS.CONSUMABLE_BUFFS.food[auraName] then hasFood = true end
            end)
            if not hasFlask then
                flagged[#flagged + 1] = { member = name, issue = "flask", value = "missing" }
                flaggedMembers[name] = true
            end
            if not hasFood then
                flagged[#flagged + 1] = { member = name, issue = "food", value = "missing" }
                flaggedMembers[name] = true
            end
        end
    end

    local threshold = RavenMarkReadyDB.settings.durabilityThreshold or 80
    local minPct = PlayerMinDurabilityPercent()
    if minPct and minPct < threshold then
        local playerName = UnitName("player")
        flagged[#flagged + 1] = {
            member = playerName,
            issue = "durability",
            value = math.floor(minPct + 0.5),
        }
        flaggedMembers[playerName] = true
    end

    local flaggedCount = 0
    for _ in pairs(flaggedMembers) do flaggedCount = flaggedCount + 1 end
    local clearCount = #units - flaggedCount

    Export:GetOrCreateRaidId()
    Export:Emit("readiness_check", {
        flagged = flagged,
        clearCount = clearCount,
    }, ADDON_NAME)

    NS.state.lastResult = { flagged = flagged, clearCount = clearCount, total = #units }
    if NS.RefreshUI then NS.RefreshUI() end
    return NS.state.lastResult
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        RavenMarkReadyDB = RavenMarkReadyDB or {}
        RavenMarkReadyDB.schemaVersion = RavenMarkReadyDB.schemaVersion or 1
        RavenMarkReadyDB.records = RavenMarkReadyDB.records or {}
        RavenMarkReadyDB.settings = RavenMarkReadyDB.settings or {}
        RavenMarkReadyDB.settings.durabilityThreshold = RavenMarkReadyDB.settings.durabilityThreshold or 80
        RavenMarkReadyDB.ui = RavenMarkReadyDB.ui or {}
        Export:Init(RavenMarkReadyDB, ADDON_NAME)
    elseif event == "PLAYER_LOGIN" then
        NS.SetupUI()
    end
end)
