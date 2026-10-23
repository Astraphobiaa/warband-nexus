--[[
    Warband Nexus - Notification test / QA commands
    /wn notif, /wn alerttest, /wn testloot, /wn testevents, vault check, effects preview.
    Loaded after NotificationManager.lua (reuses its test helpers via ns.NotificationManagerHooks).
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local NP = ns.NotificationPresentation
local ToastChrome = ns.NotificationToastChrome
local AS = ns.NotificationAlertStack
local Constants = ns.Constants
local E = Constants.EVENTS
local issecretvalue = issecretvalue

local Hooks = ns.NotificationManagerHooks
assert(Hooks and Hooks.TestLootFireAchievementAddAlert, "NotificationManager_Tests: load NotificationManager.lua first")
local TestLootEnsureAchievementAlertUI = Hooks.TestLootEnsureAchievementAlertUI
local TestLootFireAchievementAddAlert = Hooks.TestLootFireAchievementAddAlert
local TRAVELERS_LOG_PROGRESS_ICON_ATLAS = Hooks.TRAVELERS_LOG_PROGRESS_ICON_ATLAS
local VAULT_CATEGORIES = Hooks.VAULT_CATEGORIES
local TestLootFireProgressAddAlert, TestLootResolveAchievementWithCriteria, TestLootPrintAchievementReplaceMode

--- Settings / QA: achievement + criteria-style + To-Do reminder in quick succession (same anchor stack).
local function ShowTestReminderToastModal(addon)
    if not addon or not addon.ShowModalNotification then return end
    local L = ns.L
    addon:ShowModalNotification({
        compact = true,
        planReminderToast = true,
        criteriaTitle = (L and L["REMINDER_TOAST_TITLE"]) or "To-Do",
        itemName = (L and L["TEST_STACK_REMINDER"]) or "Plan reminder (test)",
        icon = (ns.Constants and ns.Constants.REMINDER_ALERT_ATLAS) or "icon_cooldownmanager",
        playSound = false,
        autoDismiss = 4,
        titleColor = ToastChrome.ReminderAccent(),
    })
end

function WarbandNexus:PrintNotificationTestHelp()
    self:Print("|cff00ccff=== Notification test (Settings button = stack) ===|r")
    self:Print("|cff44ff44/wn alerttest|r (alias: |cff44ff44/wn testalert|r) — Achievement/criteria lanes + collectible lanes")
    self:Print("|cff44ff44/wn notif stack|r — Achievement + criteria + reminder (respects Warband achievement popups toggle)")
    self:Print("|cff44ff44/wn notif earn [id]|r — Earned toast (same handler as ACHIEVEMENT_EARNED)")
    self:Print("|cff44ff44/wn notif progress [id] [step]|r — Criteria step toast (same handler as CRITERIA_EARNED)")
    self:Print("|cff44ff44/wn notif traveler|r — Traveler's Log progress toast")
    self:Print("|cff44ff44/wn notif earned [id]|r — Live path: ACHIEVEMENT_EARNED event (CollectionService)")
    self:Print("|cff44ff44/wn notif hierarchy|r — Criteria -> sub (type 8) -> meta chain (62901 / 12918 / 40958)")
    self:Print("|cff888888Toggle Settings > Notifications > Warband achievement popups ON/OFF, then re-run.|r")
    self:Print("|cff888888Default test achievement id is 6 if omitted.|r")
end

---@return boolean ok false when master notifications toggle is off
local function EnsureNotificationTestsEnabled(addon)
    local db = addon.db and addon.db.profile and addon.db.profile.notifications
    if not db or not db.enabled then
        addon:Print("|cffff8800Enable Settings > Notifications master toggle first.|r")
        return false
    end
    return true
end

---Same pipeline as in-game when the client shows an earned achievement alert.
function WarbandNexus:TestAchievementAlertEarn(achievementID)
    if not EnsureNotificationTestsEnabled(self) then return end
    achievementID = tonumber(achievementID) or 6
    local okInfo, _, name = pcall(GetAchievementInfo, achievementID) -- 1st return is the id
    if not okInfo or not name then
        self:Print("|cffff0000Invalid achievement ID: " .. tostring(achievementID) .. "|r")
        return
    end
    TestLootPrintAchievementReplaceMode(self)
    self:Print("|cff00ccffAchievement earned:|r " .. tostring(name) .. " (ID " .. achievementID .. ")")
    local ok, err = TestLootFireAchievementAddAlert(self, achievementID, nil)
    if not ok then
        self:Print("|cffff8800Test not run: " .. tostring(err) .. "|r")
    end
end

---Same pipeline as in-game criteria progress alerts.
function WarbandNexus:TestAchievementAlertProgress(achievementID, step)
    if not EnsureNotificationTestsEnabled(self) then return end
    local preferredID = tonumber(achievementID)
    local achID, numCriteria = TestLootResolveAchievementWithCriteria(preferredID)
    if not achID then
        self:Print("|cffff0000No valid achievement with criteria found. Try: /wn notif progress 6|r")
        return
    end
    local criteriaIndex = math.min(tonumber(step) or 1, numCriteria)
    if criteriaIndex < 1 then criteriaIndex = 1 end
    local _, name = GetAchievementInfo(achID)
    TestLootPrintAchievementReplaceMode(self)
    if not NP.UseWarbandCriteriaProgressPopups() then
        self:Print("|cffff8800Criteria progress popups OFF — expect Blizzard criteria bar. Enable Settings > Criteria progress popup.|r")
    end
    self:Print("|cff00ccffCriteria progress:|r " .. tostring(name)
        .. " (ID " .. achID .. ", step " .. criteriaIndex .. "/" .. numCriteria .. ")")
    local ok, err = TestLootFireAchievementAddAlert(self, achID, criteriaIndex)
    if not ok then
        self:Print("|cffff8800Test not run: " .. tostring(err) .. "|r")
    end
end

---Fires ACHIEVEMENT_EARNED like a real completion (CollectionService handler).
function WarbandNexus:TestAchievementEarnedEvent(achievementID)
    if not EnsureNotificationTestsEnabled(self) then return end
    achievementID = tonumber(achievementID) or 6
    local okInfo, _, name = pcall(GetAchievementInfo, achievementID) -- 1st return is the id
    if not okInfo or not name then
        self:Print("|cffff0000Invalid achievement ID: " .. tostring(achievementID) .. "|r")
        return
    end
    TestLootPrintAchievementReplaceMode(self)
    self:Print("|cff00ccffACHIEVEMENT_EARNED event:|r " .. tostring(name) .. " (ID " .. achievementID .. ")")
    if self.OnAchievementEarned then
        self:OnAchievementEarned("ACHIEVEMENT_EARNED", achievementID)
    else
        self:Print("|cffff8800CollectionService handler not loaded.|r")
        return
    end
    if NP.UseWarbandAchievementPopups() then
        self:Print("|cff888888Warband popups ON: expect the WN toast immediately.|r")
    else
        self:Print("|cff888888Warband popups OFF: Blizzard alerts are native-only; a simulated event shows no Blizzard alert.|r")
    end
end

---Public slash command: /wn notif [stack|earn|progress|earned|help]
function WarbandNexus:RunNotificationSlashCommand(type, id, step)
    type = type and strlower(type) or "help"
    if type == "help" or type == "?" then
        self:PrintNotificationTestHelp()
        return
    end
    if type == "stack" then
        self:TestNotificationStack()
        return
    end
    if type == "earn" or type == "achievement" or type == "blizzard" then
        self:TestAchievementAlertEarn(id)
        return
    end
    if type == "progress" or type == "criteria" then
        self:TestAchievementAlertProgress(id, step)
        return
    end
    if type == "traveler" or type == "travelerslog" or type == "progressalert" then
        self:TestProgressAlert()
        return
    end
    if type == "earned" or type == "event" then
        self:TestAchievementEarnedEvent(id)
        return
    end
    if type == "hierarchy" or type == "chain" or type == "meta" then
        self:TestAchievementAlertHierarchy()
        return
    end
    self:Print("|cffff0000Unknown subcommand.|r")
    self:PrintNotificationTestHelp()
end

local ALERT_TEST_STEP_SEC = 0.55
local ALERT_TEST_DISMISS_SEC = 9

---Public QA: /wn alerttest — stagger every WN toast lane (no debug mode).
function WarbandNexus:TestAlertTest(sub)
    sub = sub and strlower(sub) or "all"
    if sub == "help" or sub == "?" then
        self:Print("|cff00ccff=== /wn alerttest ===|r")
        self:Print("|cff44ff44/wn alerttest|r — All toast types in one stack (unified layout)")
        self:Print("|cff8888881.|r Achievement earned — WN toast (shield + points)")
        self:Print("|cff8888882.|r Criteria step — live CriteriaAlertSystem (no points shield)")
        self:Print("|cff8888883.|r Traveler's Log — live ProgressAlertSystem")
        self:Print("|cff8888884.|r To-Do reminder — compact reminder lane")
        self:Print("|cff8888885.|r Mount — Notify collectible lane")
        self:Print("|cff8888886.|r Pet — Notify collectible lane")
        self:Print("|cff8888887.|r Toy — Notify collectible lane")
        self:Print("|cff8888888.|r Plan completed — Notify plan lane")
        self:Print("|cff8888889.|r Try-counter mount — COLLECTIBLE_OBTAINED + attempts")
        self:Print("|cff88888810.|r Vault progress — compact criteria-style (no shield)")
        self:Print("|cff44ff44/wn alerttest hierarchy|r — Criteria -> sub -> meta chain only")
        return
    end
    if sub == "hierarchy" or sub == "chain" or sub == "meta" then
        self:TestAchievementAlertHierarchy()
        return
    end
    if not EnsureNotificationTestsEnabled(self) then return end

    local L = ns.L
    local delay = 0
    local function step(after, fn)
        C_Timer.After(after, function()
            if WarbandNexus and fn then fn(WarbandNexus) end
        end)
    end

    self:Print("|cff00ccff[WN Alert Test]|r Firing live alert pipelines — watch the unified stack.")

    step(delay, function(addon)
        addon:TestAchievementAlertEarn(6)
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        addon:TestAchievementAlertProgress(nil, 1)
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        if addon.TestProgressAlert then
            addon:TestProgressAlert()
        end
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local L = ns.L
        addon:ShowModalNotification({
            compact = true,
            planReminderToast = true,
            criteriaTitle = (L and L["REMINDER_TOAST_TITLE"]) or "To-Do",
            itemName = (L and L["TEST_STACK_REMINDER"]) or "Plan reminder (test)",
            icon = (ns.Constants and ns.Constants.REMINDER_ALERT_ATLAS) or "icon_cooldownmanager",
            playSound = false,
            autoDismiss = ALERT_TEST_DISMISS_SEC,
            titleColor = ToastChrome.ReminderAccent(),
        })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local mountID = 460
        local mountName, _, icon = C_MountJournal.GetMountInfoByID(mountID)
        if mountName then
            addon:Notify("mount", mountName, icon, { playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC })
        else
            addon:Notify("mount", "Grand Black War Mammoth", "Interface\\Icons\\Ability_Mount_Mammoth_Black", {
                playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC,
            })
        end
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local speciesID = 39
        local speciesName, icon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        addon:Notify("pet", speciesName or "Mechanical Squirrel Box", icon, { playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local toyItemID = 54452
        local GetItemInfoFn = C_Item and C_Item.GetItemInfo or GetItemInfo
        local itemName, _, _, _, _, _, _, _, _, icon = GetItemInfoFn(toyItemID)
        addon:Notify("toy", itemName or "Magic Pet Mirror", icon, { playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        addon:Notify("plan", "Bloodsail Admiral", "Interface\\Icons\\INV_Scroll_11", {
            playSound = false, autoDismiss = ALERT_TEST_DISMISS_SEC,
        })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        local mountID = 418
        local mountName, _, icon = C_MountJournal.GetMountInfoByID(mountID)
        addon:SendMessage(E.COLLECTIBLE_OBTAINED, {
            type = "mount",
            id = mountID,
            name = mountName or "Armored Razzashi Raptor",
            icon = icon or "Interface\\Icons\\Ability_Mount_Raptor",
            preResetTryCount = 12,
        })
    end)
    delay = delay + ALERT_TEST_STEP_SEC

    step(delay, function(addon)
        addon:ShowModalNotification({
            compact = true,
            progressAnchor = true,
            iconAtlas = "questlog-questtypeicon-heroic",
            criteriaTitle = (L and L["TOAST_CAT_VAULT"]) or "Vault",
            itemName = (L and L["DUNGEON_CAT"]) or "Dungeon",
            titleColor = ToastChrome.CriteriaAccent(),
            playSound = false,
            autoDismiss = ALERT_TEST_DISMISS_SEC,
        })
    end)
end

function WarbandNexus:TestNotificationStack()
    local L = ns.L
    if not EnsureNotificationTestsEnabled(self) then return end
    local db = self.db.profile.notifications
    local useWarbandAchievementPopups = NP.UseWarbandAchievementPopups(db)

    if useWarbandAchievementPopups then
        self:Print("|cff00ccff[WN Notif]|r Warband achievement popups ON — earn + criteria + progress + reminder (live event handlers).")
        self:TestAchievementAlertEarn(6)
        C_Timer.After(0.12, function()
            if WarbandNexus and WarbandNexus.TestAchievementAlertProgress then
                WarbandNexus:TestAchievementAlertProgress(nil, 1)
            end
        end)
        C_Timer.After(0.24, function()
            if WarbandNexus and WarbandNexus.TestProgressAlert then
                WarbandNexus:TestProgressAlert()
            end
        end)
        C_Timer.After(0.36, function()
            ShowTestReminderToastModal(WarbandNexus)
        end)
        return
    end

    -- Blizzard's own alerts are not simulated: calling AlertSystem:AddAlert from our code taints the alert pipeline.
    self:Print("|cff00ccff[WN Notif]|r Warband achievement popups OFF — Blizzard alerts are native-only (not simulated); WN reminder only.")
    ShowTestReminderToastModal(self)
end

TestLootPrintAchievementReplaceMode = function(addon)
    if NP.UseWarbandAchievementPopups() then
        addon:Print("|cffffcc00Mode:|r Warband achievement popups ON")
    else
        addon:Print("|cffffcc00Mode:|r Warband achievement popups OFF (Blizzard alerts)")
    end
end

TestLootFireProgressAddAlert = function(addon, payload)
    TestLootEnsureAchievementAlertUI(addon)
    if addon and addon.ApplyBlizzardAchievementAlertSuppression then
        addon:ApplyBlizzardAchievementAlertSuppression()
    end
    -- None of ProgressAlertSystem / MonthlyActivitiesAlertSystem / PerksActivitiesAlertSystem exists
    -- in 12.1.5 (Blizzard_FrameXML/Mainline/AlertFrameSystems.lua); the real MonthlyActivityAlertSystem
    -- takes a perksActivityID, not this payload. The test goes straight to the WN toast (2026-10-22).
    if addon and addon.ShowGenericProgressNotification then
        local shown = addon:ShowGenericProgressNotification(payload)
        if shown then
            addon:Print("|cff44ff44WN progress toast shown|r (ProgressAlertSystem unavailable in this client).")
            return true, "direct"
        end
        return false, "toast blocked"
    end
    addon:Print("|cffff8800Progress toast blocked — enable Notifications + Warband achievement popups + Criteria progress.|r")
    return false, "no system"
end

---Same pipeline as Traveler's Log / ProgressAlertSystem alerts.
function WarbandNexus:TestProgressAlert()
    if not EnsureNotificationTestsEnabled(self) then return end
    if not NP.UseWarbandCriteriaProgressPopups() then
        self:Print("|cffff8800Criteria progress popups OFF — enable Settings > Criteria progress popup.|r")
    end
    TestLootPrintAchievementReplaceMode(self)
    local payload = {
        title = (ns.L and ns.L["TOAST_BADGE_TRAVELERS_LOG"]) or "Traveler's Log",
        text = "Void Assaults: Complete 5 Void Strikes",
        iconAtlas = TRAVELERS_LOG_PROGRESS_ICON_ATLAS,
    }
    self:Print("|cff00ccffProgress alert:|r " .. payload.title .. " - " .. payload.text)
    local ok, err = TestLootFireProgressAddAlert(self, payload)
    if ok then return end
    if err == "toast blocked" then
        self:Print("|cffff8800Progress toast blocked — check Notifications settings.|r")
        return
    end
    self:Print("|cffff8800Progress test failed: " .. tostring(err) .. "|r")
end

TestLootResolveAchievementWithCriteria = function(preferredID)
    local tryIDs = { 6, 7, 8, 11, 12, 60981, 40752 }
    if preferredID then
        tryIDs = { preferredID, 6, 7, 8, 11, 12, 60981, 40752 }
    end
    for ti = 1, #tryIDs do
        local fid = tryIDs[ti]
        local name = select(2, GetAchievementInfo(fid))
        if name and name ~= "" then
            local ok, n = pcall(GetAchievementNumCriteria, fid)
            if ok and n and n > 0 then
                return fid, n
            end
        end
    end
    return nil, 0
end

--- Wiki-backed QA chain: plain criteria -> sub-achievement (type 8) -> meta earned.
--- Fixture: Heroic: Power Creep (62901) checklist, Have a Heart (12918) row on Full Heart, Can't Lose (40958).
local HIERARCHY_FIXTURE_PLAIN_ID = 62901
local HIERARCHY_FIXTURE_SUB_ID = 12918
local HIERARCHY_FIXTURE_META_ID = 40958
local HIERARCHY_TEST_STEP_SEC = 0.65

local function TestHierarchyAchievementName(achievementID)
    if not achievementID then return nil end
    local ok, _, name = pcall(GetAchievementInfo, achievementID) -- 1st return is the id
    if issecretvalue and issecretvalue(name) then return nil end
    if not ok or not name or name == "" then return nil end
    return name
end

local function TestHierarchyFirstPlainCriteriaHint(achievementID)
    if not achievementID or not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then return nil end
    local okN, numCriteria = pcall(GetAchievementNumCriteria, achievementID)
    if not okN or not numCriteria or numCriteria < 1 then return nil end
    for i = 1, numCriteria do
        local ok, criteriaName, criteriaType = pcall(GetAchievementCriteriaInfo, achievementID, i)
        if ok then
            local ct = tonumber(criteriaType)
            if ct ~= AS.ACHIEVEMENT_CRITERIA_TYPE_LINKED then
                if not (issecretvalue and issecretvalue(criteriaName)) and criteriaName
                    and criteriaName ~= "" then
                    return criteriaName, i
                end
                return i, i
            end
        end
    end
    return 1, 1
end

local function TestHierarchyLinkedSubCriteriaHint(metaID, subID)
    if not metaID or not subID or not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then
        return "Have a Heart"
    end
    local okN, numCriteria = pcall(GetAchievementNumCriteria, metaID)
    if not okN or not numCriteria or numCriteria < 1 then
        return "Have a Heart"
    end
    for i = 1, numCriteria do
        local ok, criteriaName, criteriaType, _, _, _, _, _, assetID = -- assetID = 8th
            pcall(GetAchievementCriteriaInfo, metaID, i)
        if ok and tonumber(criteriaType) == AS.ACHIEVEMENT_CRITERIA_TYPE_LINKED then
            local linked = tonumber(assetID)
            if linked and linked == subID then
                if not (issecretvalue and issecretvalue(criteriaName)) and criteriaName
                    and criteriaName ~= "" then
                    return criteriaName
                end
                return TestHierarchyAchievementName(subID) or "Have a Heart"
            end
        end
    end
    return TestHierarchyAchievementName(subID) or "Have a Heart"
end

local function TestResolveHierarchyFixture()
    local plainID = HIERARCHY_FIXTURE_PLAIN_ID
    local subID = HIERARCHY_FIXTURE_SUB_ID
    local metaID = HIERARCHY_FIXTURE_META_ID
    local plainName = TestHierarchyAchievementName(plainID)
    local subName = TestHierarchyAchievementName(subID)
    local metaName = TestHierarchyAchievementName(metaID)
    if not plainName or not subName or not metaName then
        return nil
    end
    local plainHint, plainIndex = TestHierarchyFirstPlainCriteriaHint(plainID)
    local subHint = TestHierarchyLinkedSubCriteriaHint(metaID, subID)
    return {
        plain = { id = plainID, name = plainName, hint = plainHint, index = plainIndex },
        sub = { id = subID, name = subName, parentID = metaID, hint = subHint },
        meta = { id = metaID, name = metaName },
    }
end

--- Live handler chain: criteria progress (puansiz) -> sub earned (puanli) -> meta earned (puanli).
function WarbandNexus:TestAchievementAlertHierarchy()
    if not EnsureNotificationTestsEnabled(self) then return end
    local fix = TestResolveHierarchyFixture()
    if not fix then
        self:Print("|cffff0000Hierarchy fixture unavailable.|r")
        self:Print("|cff888888Need client data for IDs 62901, 12918, 40958 (Midnight Void Assaults + Heart of Azeroth meta).|r")
        return
    end
    TestLootPrintAchievementReplaceMode(self)
    self:Print("|cff00ccff[WN Hierarchy Test]|r Criteria -> Sub -> Meta (live handlers)")
    self:Print("|cff888888Fixture:|r " .. fix.plain.name .. " / " .. fix.sub.name .. " / " .. fix.meta.name)
    self:Print("|cff8888881.|r Criteria on |cffcccccc" .. fix.plain.name .. "|r — expect |cff00ccffAchievement Progress|r, no shield")
    self:Print("|cff8888882.|r Sub row |cffcccccc" .. tostring(fix.sub.hint) .. "|r on meta — expect |cffffff00earned|r + shield for |cffcccccc" .. fix.sub.name .. "|r")
    self:Print("|cff8888883.|r Meta |cffcccccc" .. fix.meta.name .. "|r — expect |cffffff00earned|r + shield")

    local delay = 0
    C_Timer.After(delay, function()
        if not WarbandNexus then return end
        local hint = fix.plain.hint or fix.plain.index or 1
        WarbandNexus:Print("|cff00ccff[1/3] Criteria progress|r — " .. fix.plain.name .. " / " .. tostring(hint))
        TestLootFireAchievementAddAlert(WarbandNexus, fix.plain.id, hint)
    end)
    delay = delay + HIERARCHY_TEST_STEP_SEC
    C_Timer.After(delay, function()
        if not WarbandNexus then return end
        WarbandNexus:Print("|cff00ccff[2/3] Sub-achievement earned|r — meta row " .. tostring(fix.sub.hint))
        TestLootFireAchievementAddAlert(WarbandNexus, fix.sub.parentID, fix.sub.hint)
    end)
    delay = delay + HIERARCHY_TEST_STEP_SEC
    C_Timer.After(delay, function()
        if not WarbandNexus then return end
        WarbandNexus:Print("|cff00ccff[3/3] Meta earned|r — " .. fix.meta.name)
        TestLootFireAchievementAddAlert(WarbandNexus, fix.meta.id, nil)
    end)
end

---Test loot notification system (All notification types with real data)
function WarbandNexus:TestLootNotification(type, id, step)
    if not (ns.IsDebugModeEnabled and ns.IsDebugModeEnabled()) then return end
    type = type and strlower(type) or "all"
    
    -- Show help message
    if type == "help" or type == "?" then
        if self.PrintNotificationTestHelp then
            self:PrintNotificationTestHelp()
        end
        self:Print("|cff888888Debug-only loot/plan samples:|r /wn testloot mount | pet | toy | plan | all")
        return
    end

    -- Aliases (same pipeline as earn / progress)
    if type == "blizzard" or type == "achievement" then
        type = "earn"
    elseif type == "suppress" or type == "criteria" then
        type = "progress"
    elseif type == "both" then
        self:Print("|cffff8800Use |cff44ff44/wn testloot earn|r and |cff44ff44/wn testloot progress|r separately (one alert system).|r")
        return
    end

    if type == "earn" then
        self:TestAchievementAlertEarn(id)
        return
    end

    if type == "progress" then
        self:TestAchievementAlertProgress(id, step)
        return
    end

    local delay = 0
    if type == "vaultprogress" then
        local db = self.db and self.db.profile and self.db.profile.notifications
        if not db or not db.showCriteriaProgressNotifications then
            self:Print("|cffff8800Enable Settings > Notifications > Criteria Progress Toast to see vault progress toasts.|r")
        end
        local cat = VAULT_CATEGORIES.dungeon or {name = "Dungeon", atlas = "questlog-questtypeicon-heroic"}
        self:ShowModalNotification({
            compact = true,
            progressAnchor = true,
            iconAtlas = cat.atlas,
            criteriaTitle = string.format((ns.L and ns.L["CRITERIA_PROGRESS_FORMAT"]) or "Progress %d/%d", 4, 4),
            itemName = cat.name,
            playSound = false,
            autoDismiss = 3,
        })
        self:Print("|cff00ff00Vault progress toast shown (4/4 " .. cat.name .. ")|r")
        return
    end

    -- Show mount test (Real mount ID: 460 = Grand Black War Mammoth)
    if type == "mount" or type == "all" then
        C_Timer.After(delay, function()
            local mountID = id or 460
            local mountName, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
            if mountName then
                self:Notify("mount", mountName, icon)
                self:Print("|cff00ff00Mount notification: " .. mountName .. " (ID: " .. mountID .. ")|r")
            else
                self:Print("|cffff0000Invalid mount ID: " .. mountID .. "|r")
            end
        end)
        if type == "mount" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show pet test
    if type == "pet" or type == "all" then
        C_Timer.After(delay, function()
            local speciesID = id or 39
            local speciesName, icon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            if speciesName then
                self:Notify("pet", speciesName, icon)
                self:Print("|cff00ff00Pet notification: " .. speciesName .. " (ID: " .. speciesID .. ")|r")
            else
                self:Print("|cffff0000Invalid pet species ID: " .. speciesID .. "|r")
            end
        end)
        if type == "pet" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show toy test
    if type == "toy" or type == "all" then
        C_Timer.After(delay, function()
            local toyItemID = id or 54452
            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or GetItemInfo
            local itemName, _, _, _, _, _, _, _, _, icon = GetItemInfoFn(toyItemID)
            if itemName then
                self:Notify("toy", itemName, icon)
                self:Print("|cff00ff00Toy notification: " .. itemName .. " (ID: " .. toyItemID .. ")|r")
            else
                self:Print("|cffff0000Invalid toy item ID: " .. toyItemID .. "|r")
            end
        end)
        if type == "toy" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Achievement in "all" bundle uses the same path as earn.
    if type == "all" then
        C_Timer.After(delay, function()
            local addon = WarbandNexus or self
            local achievementID = id or 60981
            TestLootFireAchievementAddAlert(addon, achievementID, nil)
            local _, achievementName = GetAchievementInfo(achievementID)
            if achievementName then
                addon:Print("|cff00ff00Achievement alert: " .. achievementName .. " (ID: " .. achievementID .. ")|r")
            end
        end)
        delay = delay + 0.5
    end

    -- Show illusion test
    if type == "illusion" or type == "all" then
        C_Timer.After(delay, function()
            self:Notify("illusion", "Illusion: Mongoose", 134400)
            self:Print("|cff00ff00Illusion notification: Illusion: Mongoose|r")
        end)
        if type == "illusion" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show title test
    if type == "title" or type == "all" then
        C_Timer.After(delay, function()
            -- Try to get a real title name (titleID 62 = "the Patient")
            local titleName = "the Patient"
            if GetTitleName then
                local rawTitle = GetTitleName(62)
                if not (issecretvalue and issecretvalue(rawTitle)) and rawTitle and rawTitle ~= "" then
                    titleName = rawTitle:gsub("^%s+", ""):gsub("%s+$", ""):gsub(",%s*$", "")
                end
            end
            self:Notify("title", titleName)
            self:Print("|cff00ff00Title notification: " .. titleName .. " (titleID: 62)|r")
        end)
        if type == "title" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show plan completion tests
    if type == "plan" or type == "all" then
        if id then
            -- Test with specific achievement ID
            C_Timer.After(delay, function()
                local _, achievementName, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
                if achievementName then
                    self:Notify("plan", achievementName, icon)
                    self:Print("|cff00ff00Plan completion: " .. achievementName .. " (ID: " .. id .. ")|r")
                else
                    self:Print("|cffff0000Invalid achievement ID: " .. id .. "|r")
                end
            end)
        else
            -- Show multiple example plans
            C_Timer.After(delay, function()
                self:Notify("plan", "Bloodsail Admiral", "Interface\\Icons\\INV_Scroll_11")
            end)
            delay = delay + 0.5
        
            C_Timer.After(delay, function()
                self:Notify("plan", "Greater Darkmoon Feast", "Interface\\Icons\\INV_Scroll_08")
            end)
            delay = delay + 0.5
        
            C_Timer.After(delay, function()
                self:Notify("plan", "Illusion: Mongoose", "Interface\\Icons\\INV_Enchant_Disenchant")
            end)
            delay = delay + 0.5
        
            C_Timer.After(delay, function()
                self:Notify("plan", "Collect All Mounts")
            end)
        end
        
        if type == "plan" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Show reputation test (2-line: Faction name, then Renown level)
    if type == "reputation" or type == "all" then
        C_Timer.After(delay, function()
            self:Notify("reputation", "The Assembly of the Deeps", nil, {
                action = "Renown 15",
            })
        end)
        if type == "reputation" then
            self:Print("|cff00ff00Test reputation notification shown!|r")
            return
        end
        delay = delay + 0.5
    end
    
    if type == "all" then
        self:Print("|cff00ff00Testing all notification types with real data!|r")
    else
        self:Print("|cffff0000Unknown notification type. Use |cffffcc00/wn notif help|r (or /wn testloot help with debug on).|r")
    end
end

---Test event-driven notification system
function WarbandNexus:TestNotificationEvents(type, id)
    if not (ns.IsDebugModeEnabled and ns.IsDebugModeEnabled()) then return end
    type = type and strlower(type) or "all"
    
    self:Print("|cff00ccff[Event Test]|r Testing notification events (type: " .. type .. ")")
    
    -- Show help message
    if type == "help" or type == "?" then
        self:Print("|cff00ccff=== Event System Test Commands ===|r")
        self:Print("|cffffcc00/wn testevents|r - Test all event types")
        self:Print("|cffffcc00/wn testevents collectible [id]|r - Test collectible event")
        self:Print("|cffffcc00/wn testevents plan [achievementID]|r - Test plan completion event")
        self:Print("|cffffcc00/wn testevents vault|r - Test vault slot event")
        self:Print("|cffffcc00/wn testevents vaultreward|r - Test vault reward available")
        self:Print("|cffffcc00/wn testevents quest|r - Test quest completion event")
        self:Print("|cffffcc00/wn testevents reputation|r - Test reputation gain event")
        self:Print("|cffffcc00/wn testevents reputation valeera|r - Test Valeera Sanguinar (delve companion) rep message")
        self:Print("|cffffcc00/wn testevents achievementfallback [id]|r - ACHIEVEMENT_EARNED handler only (WN toast)")
        self:Print("|cffffcc00/wn testevents queueflood|r - 8 plan toasts (queue drain, max 6 visible)")
        self:Print("|cff888888Examples:|r")
        self:Print("|cff888888  /wn testevents plan 60981|r")
        self:Print("|cff888888  /wn testevents collectible 460|r")
        return
    end

    -- Fire ACHIEVEMENT_EARNED handler only; expect the WN toast immediately
    if type == "achievementfallback" or type == "achfallback" then
        local achievementID = tonumber(id) or 6
        local okInfo, _, name = pcall(GetAchievementInfo, achievementID) -- 1st return is the id
        if not okInfo or not name then
            self:Print("|cffff0000Invalid achievement ID: " .. tostring(achievementID) .. "|r")
            return
        end
        if not NP.UseWarbandAchievementPopups() then
            self:Print("|cffff8800Warband achievement popups must be ON for this test.|r")
            return
        end
        self:Print("|cff00ccffAchievement fallback test:|r " .. tostring(name) .. " (ID " .. achievementID .. ")")
        if self.OnAchievementEarned then
            self:OnAchievementEarned("ACHIEVEMENT_EARNED", achievementID)
        end
        self:Print("|cff888888Expect the WN toast immediately (ACHIEVEMENT_EARNED handler).|r")
        return
    end

    -- Queue flood: 8 toasts enqueued; all should appear (6 visible, rest after dismiss)
    if type == "queueflood" or type == "queue" then
        if not self:CanShowToast("plan") then
            self:Print("|cffff8800Notifications disabled; enable master toggle first.|r")
            return
        end
        for i = 1, 8 do
            local n = i
            C_Timer.After((n - 1) * 0.08, function()
                if WarbandNexus and WarbandNexus.Notify then
                    WarbandNexus:Notify("plan", "Queue flood test " .. n, nil, {
                        playSound = false,
                        autoDismiss = 10,
                    })
                end
            end)
        end
        self:Print("|cff00ff00Queue flood: 8 plan toasts scheduled (max 6 visible at once).|r")
        return
    end
    
    local delay = 0
    
    -- Test collectible event
    if type == "collectible" or type == "all" then
        C_Timer.After(delay, function()
            local mountID = id or 460
            local mountName, _, icon = C_MountJournal.GetMountInfoByID(mountID)
            self:SendMessage(E.COLLECTIBLE_OBTAINED, {
                type = "mount",
                id = mountID,
                name = mountName or "Test Mount (Event)",
                icon = icon or "Interface\\Icons\\Ability_Mount_RidingHorse"
            })
        end)
        if type == "collectible" then
            self:Print("|cff00ff00Test collectible event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Test plan completion event
    if type == "plan" or type == "all" then
        C_Timer.After(delay, function()
            local planName, planIcon
            if id then
                -- Use real achievement data
                local _, achievementName, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
                if achievementName then
                    planName = achievementName
                    planIcon = icon
                    self:Print("|cff00ff00Plan event sent: " .. achievementName .. " (ID: " .. id .. ")|r")
                else
                    self:Print("|cffff0000Invalid achievement ID: " .. id .. "|r")
                    return
                end
            else
                planName = "Test Plan (Event)"
                planIcon = "Interface\\Icons\\INV_Misc_Note_06"
            end
            
            self:SendMessage(E.PLAN_COMPLETED, {
                planType = "achievement",
                name = planName,
                icon = planIcon
            })
        end)
        if type == "plan" then
            return
        end
        delay = delay + 0.5
    end
    
    -- Test vault slot event
    if type == "vault" or type == "all" then
        C_Timer.After(delay, function()
            self:SendMessage(E.VAULT_SLOT_COMPLETED, {
                characterName = "TestChar",
                category = "dungeon",
                slotIndex = 1,
                threshold = 4
            })
        end)
        if type == "vault" then
            self:Print("|cff00ff00Test vault slot event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Test vault reward available event
    if type == "vaultreward" or type == "all" then
        C_Timer.After(delay, function()
            self:SendMessage(E.VAULT_REWARD_AVAILABLE, {})
        end)
        if type == "vaultreward" then
            self:Print("|cff00ff00Test vault reward event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Test quest completion event
    if type == "quest" or type == "all" then
        C_Timer.After(delay, function()
            self:SendMessage(E.QUEST_COMPLETED, {
                characterName = "TestChar",
                category = "dailyQuests",
                questTitle = "Test Daily Quest"
            })
        end)
        if type == "quest" then
            self:Print("|cff00ff00Test quest event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    -- Test reputation gain event (Snapshot-Diff payload)
    if type == "reputation" or type == "all" then
        local idLower = id and strlower(tostring(id))
        -- Valeera Sanguinar (delve companion): full pipeline test if she's in rep cache
        if (type == "reputation") and (idLower == "valeera" or idLower == "sanguinar") then
            local RC = ns.ReputationCache
            local factionID = RC and RC._nameToID and (RC._nameToID["Valeera Sanguinar"] or RC._nameToID["Valeera"])
            if factionID and factionID > 0 then
                RC:SimulateReputationGain("Valeera Sanguinar", factionID, 250)
                self:Print("|cff00ff00Valeera Sanguinar rep gain simulated (full pipeline). Check chat in ~0.5s.|r")
            else
                self:Print("|cffff9900Valeera Sanguinar not in reputation cache.|r Open the |cffffcc00Reputation|r tab once (so she is loaded), then run |cffffcc00/wn testevents reputation valeera|r again.")
            end
            return
        end
        C_Timer.After(delay, function()
            self:SendMessage(E.REPUTATION_GAINED, {
                factionID = 2590,
                factionName = "The Assembly of the Deeps",
                gainAmount = 250,
                currentRep = 3500,
                maxRep = 7500,
                wasStandingUp = false,
            })
        end)
        if type == "reputation" then
            self:Print("|cff00ff00Test reputation event sent!|r")
            return
        end
        delay = delay + 0.5
    end
    
    if type == "all" then
        self:Print("|cff00ff00Testing all event types!|r")
    else
        self:Print("|cffff0000Unknown event type. Use |cffffcc00/wn testevents help|r for available options.|r")
    end
end

---Test different visual effects on notifications
function WarbandNexus:TestNotificationEffects()
    self:Print("|cff00ccff=== Testing Notification Styles ===|r")
    
    -- Test 1: Full frame glow
    self:ShowModalNotification({
        title = "Full Frame Glow",
        message = "Subtle glow around entire frame",
        icon = "Interface\\Icons\\Achievement_Quests_Completed_08",
        -- titleColor = {1.0, 0.5, 0.0}, -- Custom color override (commented to use theme)
        playSound = false,
        glowAtlas = "communitiesfinder_card_highlight",
    })
    
    -- Test 2: Top + Bottom lines
    C_Timer.After(0.3, function()
        self:ShowModalNotification({
            title = "Top & Bottom Lines",
            message = "Clean border highlighting",
            icon = "Interface\\Icons\\Achievement_Quests_Completed_08",
            -- titleColor = {1.0, 0.0, 1.0}, -- Custom color override (commented to use theme)
            playSound = false,
            glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
        })
    end)
end

---Manual test function for vault check (slash command)
function WarbandNexus:TestVaultCheck()
    self:Print("|cff00ccff=== VAULT CHECK TEST ===|r")
    
    -- Check API
    if not C_WeeklyRewards then
        self:Print("|cffff0000ERROR: C_WeeklyRewards API not found!|r")
        return
    else
        self:Print("|cff00ff00Ã¢Å“â€œ C_WeeklyRewards API available|r")
    end
    
    if not C_WeeklyRewards.HasAvailableRewards then
        self:Print("|cffff0000ERROR: HasAvailableRewards function not found!|r")
        return
    else
        self:Print("|cff00ff00Ã¢Å“â€œ HasAvailableRewards function available|r")
    end
    
    -- Check rewards and current-period/claimable APIs
    local hasRewards = C_WeeklyRewards.HasAvailableRewards()
    local isCurrent = (C_WeeklyRewards.AreRewardsForCurrentRewardPeriod and C_WeeklyRewards.AreRewardsForCurrentRewardPeriod()) or nil
    local canClaim = (C_WeeklyRewards.CanClaimRewards and C_WeeklyRewards.CanClaimRewards()) or nil
    local activities = (C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities()) or nil
    local count = activities and #activities or 0
    self:Print(string.format("HasAvailableRewards=%s | AreRewardsForCurrentRewardPeriod=%s | CanClaimRewards=%s | GetActivities count=%s",
        tostring(hasRewards), tostring(isCurrent), tostring(canClaim), tostring(count)))
    local wouldShow = self:HasUnclaimedVaultRewards()
    self:Print("HasUnclaimedVaultRewards() (would show reminder): " .. tostring(wouldShow))
    if wouldShow then
        self:Print("|cff00ff00Ã¢Å“â€œ YOU HAVE UNCLAIMED REWARDS!|r")
        self:ShowVaultReminder({})
    else
        self:Print("|cff888888Ã¢Å“â€” No unclaimed (or not current period / not claimable)|r")
    end
    
    self:Print("|cff00ccff======================|r")
end
