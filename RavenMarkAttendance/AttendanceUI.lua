--[[----------------------------------------------------------------------------
RavenMark Attendance -- panel UI. Reverse-chronological pull list plus a
session summary strip (pulls, kills, avg presence, session duration).
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...

local function FormatDuration(seconds)
    seconds = seconds or 0
    if seconds >= 3600 then
        return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
    end
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

function NS.SetupUI()
    if NS.panel then return end
    local Chrome = LibStub("LibRavenChrome-1.0")
    local Dock = LibStub("LibRavenDock-1.0")

    local panel = Chrome:CreateModulePanel({
        width = 300, height = 392,
        title = "RavenMark Attendance",
        footer = true,
    })
    NS.panel = panel

    local function Refresh()
        local pulls = NS.state.pulls
        for i, pull in ipairs(pulls) do
            local row = panel:GetRow(i)
            local good = Chrome.Colors.good
            local danger = Chrome.Colors.danger
            if pull.result == "kill" then
                row:SetBarColor(good[1], good[2], good[3])
            else
                row:SetBarColor(danger[1], danger[2], danger[3])
            end
            row:SetLabel(("#%d %s"):format(pull.pullNumber, pull.boss or "?"))
            row:SetValue(FormatDuration(pull.durationSeconds))
            row:SetChip(pull.result == "kill" and "KILL" or "WIPE",
                pull.result == "kill" and "good" or "danger")
        end
        panel:HideRowsFrom(#pulls + 1)

        local kills, presenceSum = 0, 0
        for _, pull in ipairs(pulls) do
            if pull.result == "kill" then kills = kills + 1 end
            presenceSum = presenceSum + (pull.presentPercent or 0)
        end
        if #pulls > 0 then
            local session = NS.state.sessionStart and (GetTime() - NS.state.sessionStart) or 0
            panel.footer:SetText(("Pulls %d  |  Kills %d  |  Avg presence %d%%  |  Session %s")
                :format(#pulls, kills, math.floor(presenceSum / #pulls + 0.5), FormatDuration(session)))
        else
            panel.footer:SetText("No pulls this session.")
        end
        if NS.handle then NS.handle:SetBadge(#pulls > 0 and #pulls or nil) end
    end
    NS.RefreshUI = Refresh

    NS.handle = Dock:RegisterModule(ADDON_NAME, {
        displayName = "RavenMark Attendance",
        shortLabel = "A",
        frame = panel,
        minWidth = 280,
        minHeight = 320,
        defaultSlot = "left-lower",
        collapsible = true,
        savedPosition = RavenMarkAttendanceDB.ui,
        badgeProvider = function()
            return #NS.state.pulls > 0 and #NS.state.pulls or nil
        end,
    })

    Refresh()
end

SLASH_RMATTENDANCE1 = "/rmattendance"
SLASH_RMATTENDANCE2 = "/rmatt"
SlashCmdList["RMATTENDANCE"] = function()
    if not NS.panel then return end
    if NS.handle and NS.handle:IsDocked() then
        LibStub("LibRavenDock-1.0"):ToggleModule(ADDON_NAME)
    else
        NS.panel:SetShown(not NS.panel:IsShown())
    end
end
