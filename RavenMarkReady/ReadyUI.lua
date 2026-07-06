--[[----------------------------------------------------------------------------
RavenMark Ready -- panel UI. "Check Readiness" button, flagged-member list
with the specific issue, and a clear-count summary.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...

local ISSUE_LABEL = {
    flask = "no flask",
    food = "no food buff",
    durability = "low durability",
}

function NS.SetupUI()
    if NS.panel then return end
    local Chrome = LibStub("LibRavenChrome-1.0")
    local Dock = LibStub("LibRavenDock-1.0")

    local panel = Chrome:CreateModulePanel({
        width = 300, height = 392,
        title = "RavenMark Ready",
        footer = true,
        topInset = 62, -- leave room for the check button above the list
    })
    NS.panel = panel

    local checkButton = Chrome:CreateButton(panel, "Check Readiness", function()
        NS.RunCheck()
    end, { width = 130, height = 22 })
    checkButton:SetPoint("TOPLEFT", 10, -32)

    local function Refresh()
        local result = NS.state.lastResult
        local flagged = result and result.flagged or {}
        for i, entry in ipairs(flagged) do
            local row = panel:GetRow(i)
            local isDurability = entry.issue == "durability"
            local colors = isDurability and Chrome.Colors.danger or Chrome.Colors.warn
            row:SetBarColor(colors[1], colors[2], colors[3])
            row:SetLabel(entry.member)
            local valueText = ISSUE_LABEL[entry.issue] or entry.issue
            if isDurability and tonumber(entry.value) then
                valueText = valueText .. (" (%d%%)"):format(entry.value)
            end
            row:SetValue(valueText)
            row:SetChip(entry.issue:upper(), isDurability and "danger" or "warn")
        end
        panel:HideRowsFrom(#flagged + 1)

        if result then
            panel.footer:SetText(("%d clear / %d checked, %d issue%s")
                :format(result.clearCount, result.total, #flagged, #flagged == 1 and "" or "s"))
        else
            panel.footer:SetText("Not checked yet.")
        end
        if NS.handle then NS.handle:SetBadge(#flagged > 0 and #flagged or nil) end
    end
    NS.RefreshUI = Refresh

    NS.handle = Dock:RegisterModule(ADDON_NAME, {
        displayName = "RavenMark Ready",
        shortLabel = "!",
        frame = panel,
        minWidth = 280,
        minHeight = 320,
        defaultSlot = "left-lower",
        collapsible = true,
        savedPosition = RavenMarkReadyDB.ui,
        badgeProvider = function()
            local result = NS.state.lastResult
            return result and #result.flagged > 0 and #result.flagged or nil
        end,
    })

    Refresh()
end

SLASH_RMREADY1 = "/rmready"
SlashCmdList["RMREADY"] = function(msg)
    if not NS.panel then return end
    if (msg or ""):lower():match("^%s*check") then
        NS.RunCheck()
        return
    end
    if NS.handle and NS.handle:IsDocked() then
        LibStub("LibRavenDock-1.0"):ToggleModule(ADDON_NAME)
    else
        NS.panel:SetShown(not NS.panel:IsShown())
    end
end
