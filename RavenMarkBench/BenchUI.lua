--[[----------------------------------------------------------------------------
RavenMark Bench -- panel UI. Same row style as Roster, but with a bench/active
toggle button per row instead of a status-only chip.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...

function NS.SetupUI()
    if NS.panel then return end
    local Chrome = LibStub("LibRavenChrome-1.0")
    local Dock = LibStub("LibRavenDock-1.0")

    local panel = Chrome:CreateModulePanel({
        width = 300, height = 392,
        title = "RavenMark Bench",
        footer = true,
    })
    NS.panel = panel

    local function Refresh()
        local list = NS.GetList()
        local benched = 0
        for i, member in ipairs(list) do
            local row = panel:GetRow(i)
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
            if cc then
                row:SetBarColor(cc.r, cc.g, cc.b)
            else
                row:SetBarColor(0.5, 0.5, 0.5)
            end
            row:SetLabel(member.name)
            local onBench = member.status == "bench"
            if onBench then benched = benched + 1 end
            row:SetValue(onBench and "benched" or "")
            local name = member.name
            row:SetAction(onBench and "> Active" or "> Bench", function()
                NS.Toggle(name)
            end)
        end
        panel:HideRowsFrom(#list + 1)
        panel.footer:SetText(("%d on bench / %d total"):format(benched, #list))
        if NS.handle then NS.handle:SetBadge(benched > 0 and benched or nil) end
    end
    NS.RefreshUI = Refresh

    NS.handle = Dock:RegisterModule(ADDON_NAME, {
        displayName = "RavenMark Bench",
        shortLabel = "B",
        frame = panel,
        minWidth = 280,
        minHeight = 320,
        defaultSlot = "right-lower",
        collapsible = true,
        savedPosition = RavenMarkBenchDB.ui,
        badgeProvider = function()
            local n = 0
            for _ in pairs(RavenMarkBenchDB.current or {}) do n = n + 1 end
            return n > 0 and n or nil
        end,
    })

    Refresh()
end

SLASH_RMBENCH1 = "/rmbench"
SlashCmdList["RMBENCH"] = function()
    if not NS.panel then return end
    if NS.handle and NS.handle:IsDocked() then
        LibStub("LibRavenDock-1.0"):ToggleModule(ADDON_NAME)
    else
        NS.panel:SetShown(not NS.panel:IsShown())
        if NS.panel:IsShown() and NS.RefreshUI then NS.RefreshUI() end
    end
end
