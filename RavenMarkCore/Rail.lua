--[[----------------------------------------------------------------------------
RavenMark Core -- the Rail: the always-on dock shell. One Chrome tab per
registered module, with badges. Draggable when unlocked; position persists.
------------------------------------------------------------------------------]]

local ADDON_NAME, NS = ...

local TAB_SIZE, TAB_GAP, TAB_TOP = 34, 6, 10

function NS.ApplyRailPosition()
    local pos = NS.db.global.railPosition
    NS.rail:ClearAllPoints()
    NS.rail:SetPoint(pos.point or "LEFT", UIParent, pos.point or "LEFT", pos.x or 0, pos.y or 0)
end

function NS.BuildRail()
    if NS.rail then return end
    local Chrome = LibStub("LibRavenChrome-1.0")
    local Dock = LibStub("LibRavenDock-1.0")
    local db = NS.db

    local rail = Chrome:CreatePanel(UIParent, {
        width = 44, height = 260, litEdge = true, cornerAccents = true,
    })
    rail:SetFrameStrata("MEDIUM")
    rail:SetScale(db.global.railScale or 1.0)
    NS.rail = rail
    NS.ApplyRailPosition()

    rail:SetMovable(true)
    rail:EnableMouse(true)
    rail:SetClampedToScreen(true)
    rail:RegisterForDrag("LeftButton")
    rail:SetScript("OnDragStart", function(self)
        if not db.global.railLocked then self:StartMoving() end
    end)
    rail:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        db.global.railPosition = { point = point, x = x, y = y }
    end)

    Dock:AttachRail(rail, db, NS.profile)

    NS.tabs = {}

    local function OrderedModuleIds()
        local ids = Dock:GetModuleOrder()
        local rank = {}
        for i, id in ipairs(NS.profile.moduleOrder or {}) do rank[id] = i end
        table.sort(ids, function(a, b)
            return (rank[a] or 99) < (rank[b] or 99)
        end)
        return ids
    end

    local function RefreshTabs()
        local Dock = LibStub("LibRavenDock-1.0")
        local ids = OrderedModuleIds()
        for i, id in ipairs(ids) do
            local m = Dock:GetModule(id)
            local tab = NS.tabs[i]
            if not tab then
                tab = Chrome:CreateTab(rail, {
                    width = TAB_SIZE, height = TAB_SIZE,
                    onClick = function(self) Dock:ToggleModule(self.moduleId) end,
                })
                tab:SetPoint("TOP", rail, "TOP", 0, -(TAB_TOP + (i - 1) * (TAB_SIZE + TAB_GAP)))
                NS.tabs[i] = tab
            end
            tab.moduleId = id
            tab.label:SetText(m.opts.shortLabel or "?")
            tab:SetActive(m.docked and not m.collapsed)
            tab:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(m.opts.displayName or id)
                GameTooltip:Show()
            end)
            tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tab:Show()
        end
        for i = #ids + 1, #NS.tabs do NS.tabs[i]:Hide() end
        rail:SetHeight(math.max(120, TAB_TOP * 2 + #ids * (TAB_SIZE + TAB_GAP) - TAB_GAP))
    end
    NS.RefreshTabs = RefreshTabs

    local function RefreshBadges()
        local Dock = LibStub("LibRavenDock-1.0")
        for _, tab in ipairs(NS.tabs) do
            if tab:IsShown() and tab.moduleId then
                local m = Dock:GetModule(tab.moduleId)
                if m then
                    local badge = m.badge
                    if badge == nil and m.opts.badgeProvider then
                        local ok, n = pcall(m.opts.badgeProvider)
                        if ok then badge = n end
                    end
                    tab:SetBadge(badge)
                end
            end
        end
    end

    Dock.RegisterCallback(NS, "OnModuleRegistered", RefreshTabs)
    Dock.RegisterCallback(NS, "OnDock", RefreshTabs)
    Dock.RegisterCallback(NS, "OnUndock", RefreshTabs)
    Dock.RegisterCallback(NS, "OnCollapse", RefreshTabs)
    Dock.RegisterCallback(NS, "OnExpand", RefreshTabs)
    Dock.RegisterCallback(NS, "OnBadge", function() RefreshBadges() end)

    C_Timer.NewTicker(5, RefreshBadges)
    RefreshTabs()
end
