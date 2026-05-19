--[[
    Warband Nexus - Gear tab layout coordinator hook
    Loaded after GearUI.lua (keeps GearUI.lua under the 200 local limit per chunk).
]]

local ADDON_NAME, ns = ...

if ns.UI_LayoutCoordinator then
    local gearLiveRelayoutTimer = nil
    local gearLiveRelayoutGen = 0

    local function CancelGearLiveRelayoutTimer()
        if gearLiveRelayoutTimer and gearLiveRelayoutTimer.Cancel then
            gearLiveRelayoutTimer:Cancel()
        end
        gearLiveRelayoutTimer = nil
    end

    local function GearTabViewportRelayout(scrollChild, contentWidth, mf, chromeOnly)
        if not mf or mf.currentTab ~= "gear" then
            CancelGearLiveRelayoutTimer()
            return false
        end
        if not ns.GearUI_RelayoutGearTabViewportFill then
            return false
        end
        if chromeOnly and C_Timer and C_Timer.NewTimer then
            local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SCROLL
            local delay = (ms and ms.GEAR_LIVE_RELAYOUT_DEBOUNCE_SEC) or 0.08
            gearLiveRelayoutGen = gearLiveRelayoutGen + 1
            local gen = gearLiveRelayoutGen
            CancelGearLiveRelayoutTimer()
            gearLiveRelayoutTimer = C_Timer.NewTimer(delay, function()
                gearLiveRelayoutTimer = nil
                if gen ~= gearLiveRelayoutGen then return end
                if not mf or not mf:IsShown() or mf.currentTab ~= "gear" then return end
                ns.GearUI_RelayoutGearTabViewportFill(mf, contentWidth, { chromeOnly = true })
            end)
            return true
        end
        CancelGearLiveRelayoutTimer()
        return ns.GearUI_RelayoutGearTabViewportFill(mf, contentWidth, { chromeOnly = chromeOnly == true }) == true
    end

    local function GearTabResizeCommit(scrollChild, contentWidth, mf)
        if not mf or mf.currentTab ~= "gear" then
            return false
        end
        if ns.UI_RefreshFixedHeaderChrome then
            ns.UI_RefreshFixedHeaderChrome(mf)
        end
        if ns.UI_EnsureMainScrollLayout then
            ns.UI_EnsureMainScrollLayout()
        end
        local function runGearCommitRelayout()
            if not mf or not mf:IsShown() or mf.currentTab ~= "gear" then return end
            local ok = GearTabViewportRelayout(scrollChild, contentWidth, mf, false)
            if not ok and WarbandNexus and WarbandNexus.PopulateContent then
                WarbandNexus:PopulateContent()
                return
            end
            local host = mf._gearStorageRecHost
            local gen = ns._gearTabDrawGen or 0
            if host and host.canonKey and host.recContent and WarbandNexus.RedrawGearStorageRecommendationsOnly then
                host.recContent._gearRecForceNextPaint = true
                ns._gearStorageAllowEquipSigInvBypass = true
                WarbandNexus:RedrawGearStorageRecommendationsOnly(host.canonKey, gen, true)
                ns._gearStorageAllowEquipSigInvBypass = false
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, runGearCommitRelayout)
        else
            runGearCommitRelayout()
        end
        return true
    end

    if ns.UI_RegisterTabMinScrollWidth and ns.GearUI_GetGearTabMinScrollWidth then
        ns.UI_RegisterTabMinScrollWidth("gear", function()
            return ns.GearUI_GetGearTabMinScrollWidth()
        end)
    end

    ns.UI_LayoutCoordinator:RegisterTabAdapter("gear", {
        -- Live resize: column hosts + bottom band reflow (chromeOnly); row paint on commit.
        OnViewportWidthChanged = function(scrollChild, contentWidth, mf)
            return GearTabViewportRelayout(scrollChild, contentWidth, mf, true)
        end,
        OnViewportLayoutCommit = GearTabResizeCommit,
    })
end
