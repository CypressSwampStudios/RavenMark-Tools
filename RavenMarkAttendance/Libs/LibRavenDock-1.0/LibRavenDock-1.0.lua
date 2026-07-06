--[[----------------------------------------------------------------------------
LibRavenDock-1.0
Docking/undocking, slot layout, and badges for the RavenMark suite.
Pure UI library: knows nothing about raid data.

Slot vocabulary (logical, not pixel coordinates):
  "left-upper", "left-lower", "right-upper", "right-lower"

Capacity rule: at most two panels are expanded at once (left-upper/left-lower
are the auto-assigned pair). A collapsed module is simply hidden -- it is still
represented by its tab on the Rail, so clicking that tab brings it back. There
is no separate on-screen tray; the Rail tab is the single launcher. Clicking a
tab when both slots are full expands that module and evicts the longest-docked
panel (collapsing it) to make room.

Standalone fallback: if RavenMark Core (the Rail) is not installed when
RegisterModule is called, all dock logic is skipped and the module frame
becomes an ordinary movable floating window whose position persists in the
opts.savedPosition table (a reference into the module's own SavedVariables).
The calling addon gets a working handle either way and never needs to know
which path it got.
------------------------------------------------------------------------------]]

local MAJOR, MINOR = "LibRavenDock-1.0", 4
assert(LibStub, MAJOR .. " requires LibStub.")
local Dock = LibStub:NewLibrary(MAJOR, MINOR)
if not Dock then return end

Dock.modules    = Dock.modules    or {}  -- moduleId -> module record
Dock.order      = Dock.order      or {}  -- registration order of moduleIds
Dock.callbacks  = Dock.callbacks  or {}  -- event -> { [owner] = fn }
Dock.slots      = Dock.slots      or {}  -- slot -> moduleId (expanded panels)

local DEFAULT_SNAP = 40
local MAX_EXPANDED = 2

-- Every panel docks the same way: its TOPLEFT pins near the Rail's top and it
-- grows downward. Each side (left/right of the Rail) is a column; the "lower"
-- row sits directly beneath the "upper" row on the same side, so panels never
-- overlap and every one grows in the same direction. Panel heights vary, so
-- the lower row anchors to the upper panel's frame rather than a fixed pixel
-- offset (see AnchorToSlot / RelayoutDocked).
local SLOT_ORDER = { "left-upper", "left-lower", "right-upper", "right-lower" }
local SLOT_SIDE  = {
    ["left-upper"]  = "left",  ["left-lower"]  = "left",
    ["right-upper"] = "right", ["right-lower"] = "right",
}
local UPPER_OF   = { ["left-lower"] = "left-upper", ["right-lower"] = "right-upper" }
local SIDE_X     = { left = 10, right = 330 }
local PANEL_GAP  = 8

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
-- requested/default slot, then the first free auto slot. nil means no slot is
-- free, so the caller collapses (hides) the module instead.
-- Deliberately does NOT consult the saved collapsed flag: that flag is only
-- honored at registration (restoring the login layout). An explicit dock or
-- expand request must be able to bring a collapsed module back -- consulting
-- it here made collapse a one-way door.
local function ResolveSlot(m, wanted)
    local saved = Dock.profile and Dock.profile.moduleState and Dock.profile.moduleState[m.id]
    local candidates = {}
    if saved and saved.slot and SLOT_SIDE[saved.slot] then candidates[#candidates + 1] = saved.slot end
    if wanted and SLOT_SIDE[wanted] then candidates[#candidates + 1] = wanted end
    for _, s in ipairs(SLOT_ORDER) do candidates[#candidates + 1] = s end
    for _, slot in ipairs(candidates) do
        if not Dock.slots[slot] and ExpandedCount() < MAX_EXPANDED then
            return slot
        end
    end
    return nil
end

-- Anchor one frame (a real panel, or the drag preview) to a slot: top of the
-- column pins to the Rail's top-right; the lower row pins beneath the upper
-- panel on the same side when that panel is present. Always TOPLEFT-anchored,
-- so everything grows downward.
local function AnchorToSlot(frame, slot)
    frame:ClearAllPoints()
    local side = SLOT_SIDE[slot]
    local upperSlot = UPPER_OF[slot]
    local upperId = upperSlot and Dock.slots[upperSlot]
    local upper = upperId and Dock.modules[upperId]
    if upper and upper.frame ~= frame and upper.frame:IsShown() then
        frame:SetPoint("TOPLEFT", upper.frame, "BOTTOMLEFT", 0, -PANEL_GAP)
    else
        frame:SetPoint("TOPLEFT", Dock.rail, "TOPRIGHT", SIDE_X[side], 0)
    end
end

-- Re-anchor every expanded panel. Cheap, and keeps the columns correct after
-- any dock/undock/collapse (e.g. removing an upper panel slides its lower
-- neighbor up to the top).
local function RelayoutDocked()
    if not Dock.rail then return end
    for _, slot in ipairs(SLOT_ORDER) do
        local id = Dock.slots[slot]
        if id and Dock.modules[id] then
            AnchorToSlot(Dock.modules[id].frame, slot)
        end
    end
end

---------------------------------------------------------------- dock core ----

-- Collapse = hide the panel. It stays "docked" (owned by the Rail and
-- reachable via its tab), just not shown, and frees its slot. There is no
-- visible tray; the Rail tab is the way back.
local function CollapseModule(m)
    if not Dock.rail then m.frame:Show() return end -- standalone: nothing to collapse into
    local wasExpanded = m.docked and not m.collapsed
    if m.slot and Dock.slots[m.slot] == m.id then Dock.slots[m.slot] = nil end
    m.docked, m.collapsed, m.slot = true, true, nil
    m.frame:Hide()
    RelayoutDocked()
    SaveState(m)
    if wasExpanded or not m._announcedCollapse then
        m._announcedCollapse = true
        Fire("OnCollapse", m.id)
    end
end

local function DockModule(m, slot)
    if not Dock.rail then return end
    slot = slot or ResolveSlot(m, m.opts.defaultSlot)
    -- No slot available (both expand slots full, or requested slot taken):
    -- collapse to hidden rather than force it on screen.
    if not slot or not SLOT_SIDE[slot] then return CollapseModule(m) end
    if Dock.slots[slot] and Dock.slots[slot] ~= m.id then return CollapseModule(m) end

    local wasCollapsed = m.collapsed
    if m.slot and m.slot ~= slot and Dock.slots[m.slot] == m.id then Dock.slots[m.slot] = nil end
    Dock.slots[slot] = m.id
    m.docked, m.collapsed, m.slot = true, false, slot
    m.dockTime = GetTime and GetTime() or 0
    m._announcedCollapse = false

    m.frame:Show()
    RelayoutDocked()
    SaveState(m)
    Fire("OnDock", m.id, slot)
    if wasCollapsed then Fire("OnExpand", m.id) end
end

-- Float the frame at its current on-screen position (or center) as an
-- ordinary movable window.
local function FloatModule(m)
    local wasDocked = m.slot and Dock.slots[m.slot] == m.id
    if wasDocked then
        Dock.slots[m.slot] = nil
    end
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
    if wasDocked then RelayoutDocked() end -- slide the remaining panel up
    SaveState(m)
    Fire("OnUndock", m.id)
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

-- Screen coords of a slot's TOPLEFT anchor, matching AnchorToSlot so the snap
-- preview and the eventual dock land in the same place.
local function SlotTargetTopLeft(slot)
    if not Dock.rail then return nil end
    local railRight, railTop = Dock.rail:GetRight(), Dock.rail:GetTop()
    if not railRight then return nil end
    local x = railRight + SIDE_X[SLOT_SIDE[slot]]
    local upperSlot = UPPER_OF[slot]
    local upperId = upperSlot and Dock.slots[upperSlot]
    local upper = upperId and Dock.modules[upperId]
    if upper and upper.frame:IsShown() then
        local bottom = upper.frame:GetBottom()
        if bottom then return x, bottom - PANEL_GAP end
    end
    return x, railTop
end

-- Nearest open expanded slot within the snap threshold of the dragged frame,
-- or nil. Measured TOPLEFT corner to TOPLEFT anchor in screen coordinates.
function Dock:NearestOpenSlot(frame)
    if not self.rail or not self.rail:IsShown() then return nil end
    if ExpandedCount() >= MAX_EXPANDED then return nil end
    local threshold = SnapThreshold()
    local fx, fy = frame:GetLeft(), frame:GetTop()
    if not fx then return nil end
    local best, bestDist
    for _, slot in ipairs(SLOT_ORDER) do
        if not self.slots[slot] then
            local tx, ty = SlotTargetTopLeft(slot)
            if tx then
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
            Dock.preview:SetSize(m.frame:GetWidth(), m.frame:GetHeight())
            AnchorToSlot(Dock.preview, slot)
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
            if m.docked and not m.collapsed then FloatModule(m) end
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
    Fire("OnBadge", m.id, n)
end

function Handle:SetCollapsed(collapsed)
    local m = self._m
    if m.standalone then
        m.frame:SetShown(not collapsed)
        return
    end
    if collapsed then
        CollapseModule(m)
    else
        DockModule(m)
    end
end

function Handle:IsDocked()
    return self._m.docked or false
end

function Handle:GetAnchor()
    local m = self._m
    if m.docked and m.slot and SLOT_SIDE[m.slot] and Dock.rail then
        return Dock.rail, "TOPRIGHT"
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
    DockModule(m, slot and SLOT_SIDE[slot] and slot or nil)
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
            FloatModule(m)
        elseif saved and saved.collapsed then
            -- restore last session's layout: this module stays hidden until
            -- its Rail tab is clicked
            CollapseModule(m)
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

-- Rail tab click behavior: an expanded panel collapses (hides); anything else
-- expands, evicting (collapsing) the longest-docked panel if both slots are
-- full.
function Dock:ToggleModule(moduleId)
    local m = self.modules[moduleId]
    if not m then return end
    if m.standalone then
        m.frame:SetShown(not m.frame:IsShown())
        return
    end
    if m.docked and not m.collapsed then
        CollapseModule(m)
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
            CollapseModule(self.modules[oldestId])
            slot = oldestSlot
        end
    end
    DockModule(m, slot)
end
