--[[----------------------------------------------------------------------------
RavenMark Roster -- panel UI. Scrolling member list: class-colored bar (from
Blizzard's RAID_CLASS_COLORS, never hardcoded), name, spec/role text, and an
active/bench chip.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...

function NS.SetupUI()
    if NS.panel then return end
    local Chrome = LibStub("LibRavenChrome-1.0")
    local Dock = LibStub("LibRavenDock-1.0")

    local panel = Chrome:CreateModulePanel({
        width = 300, height = 392,
        title = "RavenMark Roster",
        footer = true,
    })
    NS.panel = panel

    local function Refresh()
        local snap = NS.state.snapshot or {}
        for i, member in ipairs(snap) do
            local row = panel:GetRow(i)
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
            if cc then
                row:SetBarColor(cc.r, cc.g, cc.b)
            else
                row:SetBarColor(0.5, 0.5, 0.5)
            end
            row:SetLabel(member.name)
            row:SetValue(member.spec or member.role or "")
            if member.status == "bench" then
                row:SetChip("BENCH", "warn")
            else
                row:SetChip("ACTIVE", "good")
            end
        end
        panel:HideRowsFrom(#snap + 1)
        panel.footer:SetText(("%d member%s"):format(#snap, #snap == 1 and "" or "s"))
        if NS.handle then NS.handle:SetBadge(#snap > 1 and #snap or nil) end
    end
    NS.RefreshUI = Refresh

    NS.handle = Dock:RegisterModule(ADDON_NAME, {
        displayName = "RavenMark Roster",
        shortLabel = "R",
        frame = panel,
        minWidth = 280,
        minHeight = 320,
        defaultSlot = "left-upper",
        collapsible = true,
        savedPosition = RavenMarkRosterDB.ui,
        badgeProvider = function()
            local snap = NS.state.snapshot
            return snap and #snap > 1 and #snap or nil
        end,
        onCollapseDraw = function(container)
            -- mini-panel content is the shortLabel+count the strip already
            -- renders; nothing extra needed for Roster
        end,
    })

    Refresh()
end

SLASH_RMROSTER1 = "/rmroster"
SlashCmdList["RMROSTER"] = function()
    if not NS.panel then return end
    if NS.handle and NS.handle:IsDocked() then
        LibStub("LibRavenDock-1.0"):ToggleModule(ADDON_NAME)
    else
        NS.panel:SetShown(not NS.panel:IsShown())
    end
end
