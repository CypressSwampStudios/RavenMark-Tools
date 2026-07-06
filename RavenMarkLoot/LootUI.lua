--[[----------------------------------------------------------------------------
RavenMark Loot -- panel UI. Reverse-chronological item list. Item links carry
their own quality color codes, so the label renders with the real item color
without any guessed hex values.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...

function NS.SetupUI()
    if NS.panel then return end
    local Chrome = LibStub("LibRavenChrome-1.0")
    local Dock = LibStub("LibRavenDock-1.0")

    local panel = Chrome:CreateModulePanel({
        width = 300, height = 392,
        title = "RavenMark Loot",
        footer = true,
    })
    NS.panel = panel

    local function Refresh()
        local items = NS.state.items
        for i, entry in ipairs(items) do
            local row = panel:GetRow(i)
            local edge = Chrome.Colors.edge
            row:SetBarColor(edge[1], edge[2], edge[3], 0.5)
            row:SetLabel(entry.itemLink) -- item links carry their own quality color
            row:SetValue(entry.recipient)
            row:SetChip(nil)
        end
        panel:HideRowsFrom(#items + 1)
        panel.footer:SetText(#items > 0
            and ("%d item%s this session"):format(#items, #items == 1 and "" or "s")
            or "No loot this session.")
        if NS.handle then NS.handle:SetBadge(#items > 0 and #items or nil) end
    end
    NS.RefreshUI = Refresh

    NS.handle = Dock:RegisterModule(ADDON_NAME, {
        displayName = "RavenMark Loot",
        shortLabel = "L",
        frame = panel,
        minWidth = 280,
        minHeight = 320,
        defaultSlot = "right-upper",
        collapsible = true,
        savedPosition = RavenMarkLootDB.ui,
        badgeProvider = function()
            return #NS.state.items > 0 and #NS.state.items or nil
        end,
    })

    Refresh()
end

SLASH_RMLOOT1 = "/rmloot"
SlashCmdList["RMLOOT"] = function()
    if not NS.panel then return end
    if NS.handle and NS.handle:IsDocked() then
        LibStub("LibRavenDock-1.0"):ToggleModule(ADDON_NAME)
    else
        NS.panel:SetShown(not NS.panel:IsShown())
    end
end
