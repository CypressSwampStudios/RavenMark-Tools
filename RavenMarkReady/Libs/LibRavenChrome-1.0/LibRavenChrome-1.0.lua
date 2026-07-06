--[[----------------------------------------------------------------------------
LibRavenChrome-1.0
Shared visual skin for the RavenMark suite: panels, lit edges, corner-bracket
accents, color tokens, and small widget constructors (rows, chips, tabs,
buttons, checkboxes, scroll lists).

The chamfered look: WoW frames are natively rectangular and there is no
clip-path. Rather than gamble on unverified Blizzard atlas names or ship
binary art, panels keep a rectangular hitbox and suggest the chamfer with
short 45-degree corner-bracket strokes plus a gradient lit edge across the
top. That is the deliberate v1 design; true silhouette chamfering is a v2
upgrade that only touches this file once real .tga art exists.
------------------------------------------------------------------------------]]

local MAJOR, MINOR = "LibRavenChrome-1.0", 1
assert(LibStub, MAJOR .. " requires LibStub.")
local Chrome = LibStub:NewLibrary(MAJOR, MINOR)
if not Chrome then return end

local WHITE8 = "Interface\\Buttons\\WHITE8x8"

Chrome.Colors = {
    bgVoid    = { 0.031, 0.039, 0.055 },
    panel     = { 0.075, 0.102, 0.137 },
    panel2    = { 0.094, 0.129, 0.169 },
    edge      = { 0.310, 0.847, 1.0   }, -- electric blue
    chrome    = { 0.788, 0.827, 0.859 }, -- chrome silver text
    chromeDim = { 0.494, 0.541, 0.588 },
    warn      = { 1.0,   0.580, 0.322 },
    good      = { 0.361, 1.0,   0.694 },
    danger    = { 1.0,   0.361, 0.447 },
}

local function C(key)
    local c = Chrome.Colors[key] or Chrome.Colors.chrome
    return c[1], c[2], c[3]
end

------------------------------------------------------------------ panels -----

-- opts = { width, height, litEdge (bool), cornerAccents (bool), title (string) }
function Chrome:CreatePanel(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
    f:SetSize(opts.width or 300, opts.height or 200)
    f:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    local r, g, b = C("panel")
    f:SetBackdropColor(r, g, b, 0.96)
    local er, eg, eb = C("edge")
    f:SetBackdropBorderColor(er, eg, eb, 0.35)

    if opts.litEdge then
        -- 2px gradient accent bar across the top: electric blue fading to
        -- transparent. Uses the native texture gradient API, no art assets.
        local lit = f:CreateTexture(nil, "OVERLAY")
        lit:SetPoint("TOPLEFT", 1, -1)
        lit:SetPoint("TOPRIGHT", -1, -1)
        lit:SetHeight(2)
        lit:SetTexture(WHITE8)
        if lit.SetGradient and CreateColor then
            -- modern ColorMixin signature (Dragonflight+)
            lit:SetGradient("HORIZONTAL", CreateColor(er, eg, eb, 0.9), CreateColor(er, eg, eb, 0))
        else
            lit:SetColorTexture(er, eg, eb, 0.6)
        end
        f.litEdge = lit
    end

    if opts.cornerAccents then
        -- Short rotated strokes at top-left and bottom-right that read as cut
        -- corner brackets. The hitbox stays rectangular on purpose.
        for _, def in ipairs({ { "TOPLEFT", 2, -2 }, { "BOTTOMRIGHT", -2, 2 } }) do
            local t = f:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(er, eg, eb, 0.9)
            t:SetSize(12, 2)
            t:SetPoint(def[1], f, def[1], def[2], def[3])
            t:SetRotation(math.rad(45))
        end
    end

    if opts.title then
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText(opts.title)
        title:SetTextColor(C("chrome"))
        f.title = title
    end

    return f
end

-- Standard module panel: titled Chrome panel + scroll list + optional footer
-- line. Returns the panel with .scroll, .content, and (if opts.footer) .footer.
-- opts = { width, height, title, footer (bool), topInset }
function Chrome:CreateModulePanel(opts)
    opts = opts or {}
    local panel = self:CreatePanel(UIParent, {
        width = opts.width or 300, height = opts.height or 392,
        litEdge = true, cornerAccents = true, title = opts.title,
    })
    panel:Hide()

    local bottomInset = opts.footer and 26 or 8
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -(opts.topInset or 32))
    scroll:SetPoint("BOTTOMRIGHT", -28, bottomInset)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    panel.scroll, panel.content = scroll, content

    if opts.footer then
        local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        footer:SetPoint("BOTTOMLEFT", 12, 8)
        footer:SetPoint("BOTTOMRIGHT", -12, 8)
        footer:SetJustifyH("LEFT")
        footer:SetTextColor(C("chromeDim"))
        panel.footer = footer
    end

    -- lightweight reusable row pool
    local rowHeight = opts.rowHeight or 22
    panel.rows = {}
    function panel:GetRow(i)
        local row = self.rows[i]
        if not row then
            row = Chrome:CreateRow(self.content, { height = rowHeight })
            row:SetPoint("TOPLEFT", 0, -((i - 1) * (rowHeight + 2)))
            row:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
            self.rows[i] = row
        end
        row:Show()
        return row
    end
    function panel:HideRowsFrom(n)
        for i = n, #self.rows do self.rows[i]:Hide() end
        self.content:SetWidth(math.max(1, self.scroll:GetWidth()))
        self.content:SetHeight(math.max(1, (n - 1) * (rowHeight + 2)))
    end

    return panel
end

------------------------------------------------------------------ widgets ----

-- List row: optional left color bar + label + right-aligned value/chip/action.
function Chrome:CreateRow(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(opts.height or 22)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local pr, pg, pb = C("panel2")
    bg:SetColorTexture(pr, pg, pb, 0.55)

    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(3)
    row.bar:SetColorTexture(C("edge"))

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 10, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetTextColor(C("chrome"))

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", -8, 0)
    row.value:SetJustifyH("RIGHT")
    row.value:SetTextColor(C("chromeDim"))

    function row:SetBarColor(r, g, b, a)
        self.bar:SetColorTexture(r or 0.5, g or 0.5, b or 0.5, a or 0.9)
    end
    function row:SetLabel(text) self.label:SetText(text or "") end
    function row:SetValue(text) self.value:SetText(text or "") end

    function row:SetChip(text, colorKey)
        if not text then
            if self.chip then self.chip:Hide() end
            self.value:ClearAllPoints()
            self.value:SetPoint("RIGHT", -8, 0)
            return
        end
        if not self.chip then
            self.chip = Chrome:CreateChip(self, text, colorKey)
            self.chip:SetPoint("RIGHT", -6, 0)
        end
        self.chip:SetText(text, colorKey)
        self.chip:Show()
        self.value:ClearAllPoints()
        self.value:SetPoint("RIGHT", self.chip, "LEFT", -6, 0)
    end

    -- Right-aligned small button (used by Bench's toggle).
    function row:SetAction(text, onClick)
        if not self.action then
            self.action = Chrome:CreateButton(self, text, nil, { width = 62, height = 16 })
            self.action:SetPoint("RIGHT", -6, 0)
            self.value:ClearAllPoints()
            self.value:SetPoint("RIGHT", self.action, "LEFT", -6, 0)
        end
        self.action.label:SetText(text)
        self.action:SetScript("OnClick", onClick)
        self.action:Show()
    end

    return row
end

-- Small status tag.
function Chrome:CreateChip(parent, text, colorKey)
    local chip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    chip:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip.text:SetPoint("CENTER", 0, 0)

    function chip:SetText(t, key)
        local r, g, b = C(key or "chromeDim")
        self.text:SetText(t or "")
        self.text:SetTextColor(r, g, b)
        self:SetBackdropColor(r, g, b, 0.12)
        self:SetBackdropBorderColor(r, g, b, 0.45)
        self:SetSize(math.max(30, self.text:GetStringWidth() + 12), 15)
    end

    chip:SetText(text, colorKey)
    return chip
end

-- Rail tab button. opts = { shortLabel, tooltip, onClick, width, height }
function Chrome:CreateTab(parent, opts)
    opts = opts or {}
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(opts.width or 34, opts.height or 34)
    tab:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    local pr, pg, pb = C("panel2")
    tab:SetBackdropColor(pr, pg, pb, 0.95)
    local er, eg, eb = C("edge")
    tab:SetBackdropBorderColor(er, eg, eb, 0.25)

    tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.label:SetPoint("CENTER")
    tab.label:SetText(opts.shortLabel or "?")
    tab.label:SetTextColor(C("chrome"))

    tab:SetHighlightTexture(WHITE8)
    tab:GetHighlightTexture():SetVertexColor(er, eg, eb, 0.15)

    tab.badge = Chrome:CreateChip(tab, nil, "warn")
    tab.badge:SetPoint("TOPRIGHT", 7, 7)
    tab.badge:SetFrameLevel(tab:GetFrameLevel() + 2)
    tab.badge:Hide()

    function tab:SetBadge(n)
        if n and tonumber(n) and tonumber(n) > 0 then
            self.badge:SetText(tostring(n), "warn")
            self.badge:Show()
        else
            self.badge:Hide()
        end
    end
    function tab:SetActive(on)
        self:SetBackdropBorderColor(er, eg, eb, on and 0.9 or 0.25)
    end

    if opts.onClick then tab:SetScript("OnClick", opts.onClick) end
    if opts.tooltip then
        tab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(opts.tooltip)
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return tab
end

-- Plain text button in suite style.
function Chrome:CreateButton(parent, text, onClick, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(opts.width or 130, opts.height or 22)
    b:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    local pr, pg, pb = C("panel2")
    b:SetBackdropColor(pr, pg, pb, 0.95)
    local er, eg, eb = C("edge")
    b:SetBackdropBorderColor(er, eg, eb, 0.4)

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetText(text or "")
    b.label:SetTextColor(C("chrome"))

    b:SetHighlightTexture(WHITE8)
    b:GetHighlightTexture():SetVertexColor(er, eg, eb, 0.15)

    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Minimal checkbox built from scratch (no reliance on Blizzard templates,
-- which get renamed across expansions). onChange(checked) fires on click.
function Chrome:CreateCheckbox(parent, labelText, initial, onChange)
    local box = CreateFrame("Button", nil, parent, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
    local pr, pg, pb = C("panel2")
    box:SetBackdropColor(pr, pg, pb, 0.95)
    local er, eg, eb = C("edge")
    box:SetBackdropBorderColor(er, eg, eb, 0.4)

    box.mark = box:CreateTexture(nil, "OVERLAY")
    box.mark:SetPoint("TOPLEFT", 3, -3)
    box.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    box.mark:SetColorTexture(er, eg, eb, 0.9)

    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    box.label:SetText(labelText or "")
    box.label:SetTextColor(C("chrome"))

    box.checked = not not initial
    box.mark:SetShown(box.checked)

    function box:SetChecked(v)
        self.checked = not not v
        self.mark:SetShown(self.checked)
    end
    function box:GetChecked() return self.checked end

    box:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onChange then onChange(self.checked) end
    end)

    return box
end
