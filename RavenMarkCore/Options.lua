--[[----------------------------------------------------------------------------
RavenMark Core -- options panel.

Registered through the modern Settings.RegisterCanvasLayoutCategory API (native
Blizzard API, Dragonflight+). Guarded: if the Settings API surface has changed
in this client, the panel simply isn't registered and /rmcore still covers
lock/unlock/reset -- see BUILD_NOTES.md.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...

function NS.BuildOptions()
    if NS.optionsCanvas then return end
    local Chrome = LibStub("LibRavenChrome-1.0")
    local Dock = LibStub("LibRavenDock-1.0")
    local db = NS.db

    local canvas = CreateFrame("Frame")
    canvas:Hide()
    NS.optionsCanvas = canvas

    local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RavenMark")
    title:SetTextColor(0.310, 0.847, 1.0)

    local subtitle = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Raid-ops suite. The Rail docks whichever modules are installed.")
    subtitle:SetTextColor(0.494, 0.541, 0.588)

    -- Rail scale slider (built from scratch; Blizzard slider templates get
    -- renamed across expansions).
    local scaleLabel = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", 16, -72)
    scaleLabel:SetText("Rail scale")

    local slider = CreateFrame("Slider", nil, canvas, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(220, 14)
    slider:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -8)
    slider:SetMinMaxValues(0.6, 1.6)
    slider:SetValueStep(0.05)
    slider:SetObeyStepOnDrag(true)
    slider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    slider:SetBackdropColor(0.094, 0.129, 0.169, 1)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(10, 14)
    thumb:SetVertexColor(0.310, 0.847, 1.0, 1)

    local scaleValue = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("LEFT", slider, "RIGHT", 10, 0)

    slider:SetValue(db.global.railScale or 1.0)
    scaleValue:SetFormattedText("%.2f", db.global.railScale or 1.0)
    slider:SetScript("OnValueChanged", function(_, value)
        db.global.railScale = value
        scaleValue:SetFormattedText("%.2f", value)
        if NS.rail then NS.rail:SetScale(value) end
    end)

    -- Lock checkbox.
    local lock = Chrome:CreateCheckbox(canvas, "Lock Rail position", db.global.railLocked, function(checked)
        db.global.railLocked = checked
    end)
    lock:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -18)
    canvas:HookScript("OnShow", function() lock:SetChecked(db.global.railLocked) end)

    -- Reset position button.
    local reset = Chrome:CreateButton(canvas, "Reset Rail position", function()
        db.global.railPosition = { point = "LEFT", x = 22, y = 0 }
        if NS.rail then NS.ApplyRailPosition() end
    end, { width = 160, height = 22 })
    reset:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -14)

    -- Registered-module list with dock/undock toggles, rebuilt on show since
    -- modules register at their own load time.
    local listHeader = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -24)
    listHeader:SetText("Modules")

    local moduleRows = {}
    local function RefreshModuleList()
        local ids = Dock:GetModuleOrder()
        for i, id in ipairs(ids) do
            local m = Dock:GetModule(id)
            local row = moduleRows[i]
            if not row then
                row = { }
                row.label = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.label:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -(10 + (i - 1) * 26))
                row.button = Chrome:CreateButton(canvas, "", nil, { width = 76, height = 18 })
                row.button:SetPoint("LEFT", row.label, "LEFT", 220, 0)
                moduleRows[i] = row
            end
            row.label:SetText(m.opts.displayName or id)
            row.label:Show()
            row.button.label:SetText(m.docked and "Undock" or "Dock")
            row.button:SetScript("OnClick", function()
                if m.docked then
                    m.handle:RequestUndock()
                else
                    m.handle:RequestDock()
                end
                RefreshModuleList()
            end)
            row.button:Show()
        end
        for i = #ids + 1, #moduleRows do
            moduleRows[i].label:Hide()
            moduleRows[i].button:Hide()
        end
    end
    canvas:HookScript("OnShow", RefreshModuleList)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(canvas, "RavenMark")
        category.ID = "RavenMark"
        Settings.RegisterAddOnCategory(category)
        NS.settingsCategory = category
    else
        NS.Print("Settings API not found; options panel unavailable (see BUILD_NOTES.md). /rmcore still works.")
    end
end
