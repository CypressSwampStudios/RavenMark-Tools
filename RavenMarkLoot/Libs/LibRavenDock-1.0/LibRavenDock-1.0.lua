--[[----------------------------------------------------------------------------
LibRavenDock-1.0
Docking/undocking, slot layout, and badges for the RavenMark suite.
Pure UI library: knows nothing about raid data.

Slot vocabulary (logical, not pixel coordinates):
  "left-upper", "left-lower", "right-upper", "right-lower", "strip"

Capacity rule: at most two panels are expanded at once (left-upper/left-lower
are the auto-assigned pair). Anything past the cap -- and any module whose
requested slot is taken -- queues into the strip (the collapsed status area
under the Rail) until a slot frees, at which point the oldest strip occupant
is promoted.

Standalone fallback: if RavenMark Core (the Rail) is not installed when
RegisterModule is called, all dock logic is skipped and the module frame
becomes an ordinary movable floating window whose position persists in the
opts.savedPosition table (a reference into the module's own SavedVariables).
The calling addon gets a working handle either way and never needs to know
which path it got.
------------------------------------------------------------------------------]]

local MAJOR, MINOR = "LibRavenDock-1.0", 2
assert(LibStub, MAJOR .. " requires LibStub.")
local Dock = LibStub:NewLibrary(MAJOR, MINOR)
if not Dock then return end

Dock.modules    = Dock.modules    or {}  -- moduleId -> module record
Dock.order      = Dock.order      or {}  -- registration order of moduleIds
Dock.callbacks  = Dock.callbacks  or {}  -- event -> { [owner] = fn }
Dock.slots      = Dock.slots      or {}  -- slot -> moduleId (expanded panels)
Dock.strip      = Dock.strip      or {}  -- array of moduleIds in the strip
Dock.stripCells = Dock.stripCells or {}  -- moduleId -> strip cell button

local DEFAULT_SNAP = 40
local MAX_EXPANDED = 2

local SLOT_POINTS = {
    ["left-upper"]  = { point = "TOPLEFT",    relPoint = "TOPRIGHT",    x = 10,  y = 0 },
    ["left-lower"]  = { point = "BOTTOMLEFT", relPoint = "BOTTOMRIGHT", x = 10,  y = 0 },
    ["right-upper"] = { point = "TOPLEFT",    relPoint = "TOPRIGHT",    x = 330, y = 0 },
    ["right-lower"] = { point = "BOTTOMLEFT", relPoint = "BOTTOMRIGHT", x = 330, y = 0 },
}
local SLOT_ORDER = { "left-upper", "left-lower", "right-upper", "right-lower" }

local function indexOf(t, v)
    for i = 1, #t do if t[i] == v then return i end end
end

---------------------------------------------------------------- callbacks ----

-- Simple pub-sub: Dock.RegisterCallback(owner, "OnDock", fn). One callback
-- per (owner, event) pair; re-registering replaces.
function Dock.RegisterCallback(owner, event, fn)
    assert(owner ~= nil and type(event) == "string" and type(fn) == "function",
        "Usage: Dock.RegisterCallback(owner, event, fn)")
    Dock.callbacks[event] = Dock.callbacks[event] or {}
    Dock.callbacks[event][owner] = fn
end

function Dock.UnregisterCallback(owner, event)
    if Dock.callbacks[event] then Dock.callbacks[event][owner] = nil end
end

local function Fire(event, ...)
    local handlers = Dock.callbacks[event]
    if not handlers then return end
    for _, fn in pairs(handlers) do
        local ok, err = pcall(fn, ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

------------------------------------------------------------------- state -----

local function ExpandedCount()
    local n = 0
    for _ in pairs(Dock.slots) do n = n + 1 end
    return n
end

local function SnapThreshold()
    local db = Dock.coreDB
    return (db and db.global and db.global.snapThreshold) or DEFAULT_SNAP
end

local function SaveState(m)
    local prof = Dock.profile
    if not prof then return end
    prof.moduleState = prof.moduleState or {}
    if m.docked then
        prof.moduleState[m.id] = { slot = m.slot, collapsed = m.collapsed }
    else
        prof.moduleState[m.id] = { collapsed = false, floating = true }
    end
end

-- Pick the slot a module should expand into: saved slot first, then the
-- requested/default slot, then the first free auto slot. nil means "strip".
-- Deliberately does NOT consult the saved collapsed flag: that flag is only
-- honored at registration (restoring the login layout). An explicit dock or
-- expand request must be able to pull a module OUT of the strip -- consulting
-- it here made collapse a one-way door.
local function ResolveSlot(m, wanted)
    local saved = Dock.profile and Dock.profile.moduleState and Dock.profile.moduleState[m.id]
    local candidates = {}
    if saved and saved.slot and SLOT_POINTS[saved.slot] then candidates[#candidates + 1] = saved.slot end
    if wanted and SLOT_POINTS[wanted] then candidates[#candidates + 1] = wanted end
    for _, s in ipairs(SLOT_ORDER) do candidates[#candidates + 1] = s end
    for _, slot in ipairs(candidates) do
        if not Dock.slots[slot] and ExpandedCount() < MAX_EXPANDED then
            return slot
        end
    end
    return nil
end

------------------------------------------------------------------- strip -----

local function EnsureStripFrame()
    if Dock.stripFrame or not Dock.rail then return end
    local Chrome = LibStub("LibRavenChrome-1.0", true)
    local f
    if Chrome then
        f = Chrome:CreatePanel(UIParent, { width = 70, height = 26, litEdge = true })
    else
        f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(70, 26)
    end
    f:SetPoint("TOPLEFT", Dock.rail, "BOTTOMLEFT", 0, -8)
    f:Hide()
    Dock.stripFrame = f
end

local function LayoutStrip()
    if not Dock.stripFrame then return end
    local shown = 0
    for i, id in ipairs(Dock.strip) do
        local m = Dock.modules[id]
        local cell = Dock.stripCells[id]
        if not cell then
            cell = CreateFrame("Button", nil, Dock.stripFrame, "BackdropTemplate")
            cell:SetSize(58, 20)
            cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            cell:SetBackdropColor(0.094, 0.129, 0.169, 0.95)
            cell:SetBackdropBorderColor(0.310, 0.847, 1.0, 0.3)
            cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell.label:SetPoint("CENTER")
            cell.moduleId = id
            cell:SetScript("OnClick", function(self) Dock:ToggleModule(self.moduleId) end)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                local mod = Dock.modules[self.moduleId]
                GameTooltip:SetText((mod.opts.displayName or self.moduleId) .. " (click to expand)")
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            Dock.stripCells[id] = cell
            -- let the module draw its own mini-panel content once, if it wants
            if m.opts.onCollapseDraw then pcall(m.opts.onCollapseDraw, cell) end
        end
        local badge = m.badge
        if not badge and m.opts.badgeProvider then
            local ok, n = pcall(m.opts.badgeProvider)
            if ok then badge = n end
        end
        cell.label:SetText((m.opts.shortLabel or "?") .. (badge and badge ~= 0 and (" " .. badge) or ""))
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", Dock.stripFrame, "LEFT", 6 + (i - 1) * 62, 0)
        cell:Show()
        shown = shown + 1
    end
    for id, cell in pairs(Dock.stripCells) do
        if not indexOf(Dock.strip, id) then cell:Hide() end
    end
    Dock.stripFrame:SetWidth(math.max(70, 12 + shown * 62))
    Dock.stripFrame:SetShown(shown > 0)
end

---------------------------------------------------------------- dock core ----

local function SendToStrip(m)
    if not Dock.rail then m.frame:Show() return end -- standalone: nothing to queue into
    local wasExpanded = m.docked and not m.collapsed
    if m.slot and Dock.slots[m.slot] == m.id then Dock.slots[m.slot] = nil end
    m.docked, m.collapsed, m.slot = true, true, "strip"
    m.frame:Hide()
    if not indexOf(Dock.strip, m.id) then Dock.strip[#Dock.strip + 1] = m.id end
    EnsureStripFrame()
    LayoutStrip()
    SaveState(m)
    if wasExpanded or not m._announcedCollapse then
        m._announcedCollapse = true
        Fire("OnCollapse", m.id)
    end
end

local function RemoveFromStrip(m)
    local i = indexOf(Dock.strip, m.id)
    if i then table.remove(Dock.strip, i) end
    LayoutStrip()
end

local function DockModule(m, slot)
    if not Dock.rail then return end
    slot = slot or ResolveSlot(m, m.opts.defaultSlot)
    if not slot or slot == "strip" then return SendToStrip(m) end
    if Dock.slots[slot] and Dock.slots[slot] ~= m.id then return SendToStrip(m) end

    local wasCollapsed = m.collapsed
    RemoveFromStrip(m)
    if m.slot and m.slot ~= slot and Dock.slots[m.slot] == m.id then Dock.slots[m.slot] = nil end
    Dock.slots[slot] = m.id
    m.docked, m.collapsed, m.slot = true, false, slot
    m.dockTime = GetTime and GetTime() or 0
    m._announcedCollapse = false

    local def = SLOT_POINTS[slot]
    local f = m.frame
    f:ClearAllPoints()
    f:SetPoint(def.point, Dock.rail, def.relPoint, def.x, def.y)
    f:Show()
    SaveState(m)
    Fire("OnDock", m.id, slot)
    if wasCollapsed then Fire("OnExpand", m.id) end
end

-- Promote the oldest strip occupant into a freed slot.
local function PromoteFromStrip(slot)
    if #Dock.strip == 0 or ExpandedCount() >= MAX_EXPANDED then return end
    local id = Dock.strip[1]
    local m = Dock.modules[id]
    if m then DockModule(m, (slot and not Dock.slots[slot]) and slot or nil) end
end

-- Float the frame at its current on-screen position (or center) as an
-- ordinary movable window.
local function FloatModule(m, skipPromote)
    local freed
    if m.slot and Dock.slots[m.slot] == m.id then
        Dock.slots[m.slot] = nil
        freed = m.slot
    end
    RemoveFromStrip(m)
    m.docked, m.collapsed, m.slot = false, false, nil

    local f = m.frame
    local left, top = f:GetLeft(), f:GetTop()
    f:ClearAllPoints()
    local pos = m.opts.savedPosition
    if pos and pos.point and not left then
        f:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    elseif left and top then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
        f:SetPoint("CENTER")
    end
    f:Show()
    SaveState(m)
    Fire("OnUndock", m.id)
    if freed and not skipPromote then PromoteFromStrip(freed) end
end

------------------------------------------------------------- drag / snap -----

local function EnsurePreview()
    if Dock.preview then return end
    local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    p:SetBackdropColor(0.310, 0.847, 1.0, 0.08)
    p:SetBackdropBorderColor(0.310, 0.847, 1.0, 0.8)
    p:SetFrameStrata("TOOLTIP")
    p:Hide()
    Dock.preview = p
end

-- Nearest open expanded slot within the snap threshold of the dragged frame,
-- or nil. Measured corner-to-corner in UIParent coordinates.
function Dock:NearestOpenSlot(frame)
    if not self.rail or not self.rail:IsShown() then return nil end
    if ExpandedCount() >= MAX_EXPANDED then return nil end
    local threshold = SnapThreshold()
    local railRight, railTop, railBottom = self.rail:GetRight(), self.rail:GetTop(), self.rail:GetBottom()
    if not railRight then return nil end
    local best, bestDist
    for _, slot in ipairs(SLOT_ORDER) do
        if not self.slots[slot] then
            local def = SLOT_POINTS[slot]
            local tx = railRight + def.x
            local ty = (def.relPoint == "TOPRIGHT") and (railTop + def.y) or (railBottom + def.y)
            local fx = frame:GetLeft()
            local fy = (def.point == "TOPLEFT") and frame:GetTop() or frame:GetBottom()
            if fx and fy then
                local d = math.sqrt((fx - tx) ^ 2 + (fy - ty) ^ 2)
                if d <= threshold and (not bestDist or d < bestDist) then
                    best, bestDist = slot, d
                end
            end
        end
    end
    return best
end

local function StartSnapWatch(m)
    EnsurePreview()
    Dock.watcher = Dock.watcher or CreateFrame("Frame")
    Dock.watcher:SetScript("OnUpdate", function()
        local slot = Dock:NearestOpenSlot(m.frame)
        Dock.pendingSlot = slot
        if slot then
            local def = SLOT_POINTS[slot]
            Dock.preview:ClearAllPoints()
            Dock.preview:SetSize(m.frame:GetWidth(), m.frame:GetHeight())
            Dock.preview:SetPoint(def.point, Dock.rail, def.relPoint, def.x, def.y)
            Dock.preview:Show()
        else
            Dock.preview:Hide()
        end
    end)
end

local function StopSnapWatch()
    if Dock.watcher then Dock.watcher:SetScript("OnUpdate", nil) end
    if Dock.preview then Dock.preview:Hide() end
end

local function SetupDraggable(m, dockAware)
    local f = m.frame
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
        if dockAware then
            if m.docked and not m.collapsed then FloatModule(m, true) end
            StartSnapWatch(m)
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if dockAware then
            StopSnapWatch()
            if Dock.pendingSlot then
                DockModule(m, Dock.pendingSlot)
                Dock.pendingSlot = nil
                return
            end
            PromoteFromStrip()
        end
        local pos = m.opts.savedPosition
        if pos then
            local point, _, _, x, y = self:GetPoint(1)
            pos.point, pos.x, pos.y = point, x, y
        end
        if dockAware then SaveState(m) end
    end)
end

------------------------------------------------------------------ handles ----

local Handle = {}
Handle.__index = Handle

function Handle:SetBadge(n)
    local m = self._m
    m.badge = n
    if m.collapsed then LayoutStrip() end
    Fire("OnBadge", m.id, n)
end

function Handle:SetCollapsed(collapsed)
    local m = self._m
    if m.standalone then
        m.frame:SetShown(not collapsed)
        return
    end
    if collapsed then
        SendToStrip(m)
    else
        DockModule(m)
    end
end

function Handle:IsDocked()
    return self._m.docked or false
end

function Handle:GetAnchor()
    local m = self._m
    if m.docked and m.slot and SLOT_POINTS[m.slot] and Dock.rail then
        return Dock.rail, SLOT_POINTS[m.slot].relPoint
    end
    local point = m.frame:GetPoint(1)
    return UIParent, point or "CENTER"
end

function Handle:RequestUndock()
    local m = self._m
    if m.standalone or not m.docked then return end
    FloatModule(m)
end

function Handle:RequestDock(slot)
    local m = self._m
    if m.standalone then return end -- no Rail in this environment; nothing to dock to
    DockModule(m, slot and SLOT_POINTS[slot] and slot or nil)
end

--------------------------------------------------------------- public API ----

-- Called by RavenMark Core once the Rail frame exists. `coreDB` supplies
-- snapThreshold; `profile` is the per-character table where slot/collapsed
-- state persists.
function Dock:AttachRail(railFrame, coreDB, profile)
    self.rail = railFrame
    self.coreDB = coreDB
    self.profile = profile
    railFrame:HookScript("OnShow", function() Fire("OnRailShown") end)
    railFrame:HookScript("OnHide", function() Fire("OnRailHidden") end)
    EnsureStripFrame()
end

function Dock:HasRail()
    return self.rail ~= nil
end

-- opts = { displayName, shortLabel, icon, frame, minWidth, minHeight,
--          defaultSlot, collapsible, onCollapseDraw(container),
--          badgeProvider(), savedPosition (table ref for floating position) }
function Dock:RegisterModule(moduleId, opts)
    assert(type(moduleId) == "string" and type(opts) == "table" and opts.frame,
        "Usage: Dock:RegisterModule(moduleId, opts) with opts.frame")
    assert(not self.modules[moduleId], "Module already registered: " .. moduleId)

    local m = {
        id = moduleId,
        opts = opts,
        frame = opts.frame,
        docked = false,
        collapsed = false,
        slot = nil,
    }
    if opts.minWidth or opts.minHeight then
        local w, h = m.frame:GetSize()
        m.frame:SetSize(math.max(w or 0, opts.minWidth or 0), math.max(h or 0, opts.minHeight or 0))
    end

    self.modules[moduleId] = m
    self.order[#self.order + 1] = moduleId

    local handle = setmetatable({ _m = m }, Handle)
    m.handle = handle

    if self.rail then
        SetupDraggable(m, true)
        local saved = self.profile and self.profile.moduleState and self.profile.moduleState[moduleId]
        if saved and saved.floating then
            FloatModule(m, true)
        elseif saved and saved.collapsed then
            -- restore last session's layout: this module stays in the strip
            SendToStrip(m)
        else
            DockModule(m, ResolveSlot(m, opts.defaultSlot))
        end
    else
        -- Standalone fallback: ordinary movable floating window, hidden until
        -- the module's slash command (or code) shows it.
        m.standalone = true
        SetupDraggable(m, false)
        local pos = opts.savedPosition
        m.frame:ClearAllPoints()
        if pos and pos.point then
            m.frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
        else
            m.frame:SetPoint("CENTER")
        end
    end

    Fire("OnModuleRegistered", moduleId)
    return handle
end

function Dock:GetModule(moduleId)
    return self.modules[moduleId]
end

function Dock:GetModuleOrder()
    local out = {}
    for i, id in ipairs(self.order) do out[i] = id end
    return out
end

-- Rail tab / strip cell click behavior: expanded -> strip; anything else ->
-- try to expand, evicting the longest-docked panel if both slots are full.
function Dock:ToggleModule(moduleId)
    local m = self.modules[moduleId]
    if not m then return end
    if m.standalone then
        m.frame:SetShown(not m.frame:IsShown())
        return
    end
    if m.docked and not m.collapsed then
        SendToStrip(m)
        return
    end
    local slot = ResolveSlot(m, m.opts.defaultSlot)
    if not slot and ExpandedCount() >= MAX_EXPANDED then
        local oldestId, oldestTime, oldestSlot
        for s, id in pairs(self.slots) do
            local mm = self.modules[id]
            local t = mm and mm.dockTime or 0
            if not oldestTime or t < oldestTime then
                oldestTime, oldestId, oldestSlot = t, id, s
            end
        end
        if oldestId then
            SendToStrip(self.modules[oldestId])
            slot = oldestSlot
        end
    end
    DockModule(m, slot)
end
