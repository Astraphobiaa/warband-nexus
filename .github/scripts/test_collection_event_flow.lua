#!/usr/bin/env lua
--[[
    Regression test: Collections message flow (obtain, scan complete, module re-enable, ensure timeout).

    1. One new mount/pet/toy sent WN_COLLECTION_UPDATED twice: the WN_COLLECTIBLE_OBTAINED handler
       re-emits it and OnNewMount/Pet/Toy sent another. Each string-arg COLLECTION_UPDATED wiped the
       API counts cache, undoing the in-place +1 the OBTAINED payload had just applied, so the next
       Statistics/Collections read re-ran the full journal count pass.
    2. The Collections tab WN_COLLECTION_SCAN_COMPLETE listener ignored payload.category: every
       per-category / failed scan wiped all sub-tab caches and redrew synchronously, and an
       achievement scan redrew a second time off the COLLECTION_UPDATED that follows it.
    3. The bag-scan baseline was only built on PLAYER_ENTERING_WORLD while Collections was on: after
       re-enabling, bag/loot detection stayed off until the next loading screen, and a stale snapshot
       reported a mount item picked up while disabled as new.
    4. EnsureCollectionData's achievement-step listener outlived its 60 s safety timeout (a later
       achievement scan resumed the dead run), and an older run's timeout force-cleared a newer run.

    Drives the shipped CollectionService*.lua files under wow_stub.lua with an AceEvent-like message
    bus; the CollectionsUI listener block is extracted from Modules/UI/CollectionsUI.lua and run as is.
]]

local passed, failed = 0, 0
local function check(cond, msg, detail)
    if cond then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print("  FAIL " .. msg .. (detail and (": " .. tostring(detail)) or ""))
    end
end
local function assert_eq(actual, expected, msg)
    check(actual == expected, msg, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

-- ---------- AceEvent-like message bus (one handler per (target, message), synchronous) ----------
local bus, sent, busErrors = {}, {}, {}
local function RegisterMessage(target, msg, fn)
    if type(fn) == "string" then
        local name = fn
        fn = function(...) return target[name](target, ...) end
    end
    bus[msg] = bus[msg] or {}
    bus[msg][target] = fn
end
local function UnregisterMessage(target, msg)
    if bus[msg] then bus[msg][target] = nil end
end
local function SendMessage(_, msg, ...)
    sent[#sent + 1] = { msg = msg, arg = (...) }
    local list = bus[msg]
    if not list then return end
    local fns = {}
    for _, fn in pairs(list) do fns[#fns + 1] = fn end
    for i = 1, #fns do
        local ok, err = pcall(fns[i], msg, ...)
        if not ok then busErrors[#busErrors + 1] = msg .. ": " .. tostring(err) end
    end
end
local function CountSent(msg, arg)
    local n = 0
    for i = 1, #sent do
        if sent[i].msg == msg and (arg == nil or sent[i].arg == arg) then n = n + 1 end
    end
    return n
end

local ns = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = { modulesEnabled = { collections = false } }, char = {} },
    SendMessage = SendMessage,
    RegisterMessage = RegisterMessage,
    UnregisterMessage = UnregisterMessage,
    RegisterEvent = function() end,
    UnregisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
string.trim = string.trim or strtrim

-- Bag model for the bag-scan scenario (class 15 / subclass 5 = mount item; GetItemInfoInstant is bound at load).
local bags = { [0] = {} }
C_Container.GetContainerNumSlots = function(bagID) return bagID == 0 and 4 or 0 end
C_Container.GetContainerItemInfo = function(bagID, slotID)
    local id = bags[bagID] and bags[bagID][slotID]
    if not id then return nil end
    return { itemID = id, hyperlink = "|Hitem:" .. id .. ":|h[Item" .. id .. "]|h" }
end
C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, 15, 5 end
C_Item.GetItemIconByID = function(id) return 5000 + id end

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/Utilities.lua")
local function CollectionsOn() return WarbandNexus.db.profile.modulesEnabled.collections ~= false end
ns.Utilities.IsModuleEnabled = function(_, name) if name == "collections" then return CollectionsOn() end return true end
ns.Utilities.IsAnyModuleEnabled = function() return true end
ns.Utilities.GetCharacterStorageKey = function() return "Player-01" end
LoadFile("Modules/MigrationService.lua")
LoadFile("Modules/CollectionService_Materialize.lua")
LoadFile("Modules/CollectionService_NotifyDedup.lua")
LoadFile("Modules/CollectionService_Scan.lua")
LoadFile("Modules/CollectionService.lua")
LoadFile("Modules/CollectionService_Store.lua")
LoadFile("Modules/CollectionService_Events.lua")
LoadFile("Modules/CollectionService_JournalScan.lua")
LoadFile("Modules/CollectionService_Metadata.lua")
LoadFile("Modules/CollectionService_Queries.lua")
LoadFile("Modules/CollectionService_Achievements.lua")

local E = ns.Constants.EVENTS
WarbandNexus.SaveCollectionStore = function() end

-- ======================================================================
print("1. One WN_COLLECTION_UPDATED per obtained mount / pet / toy; counts cache kept in place")
-- ======================================================================
WarbandNexus.db.profile.modulesEnabled.collections = true
local mountIDsCalls = 0
C_MountJournal.GetMountIDs = function() mountIDsCalls = mountIDsCalls + 1; return { 1, 2, 3 } end
-- name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction,
-- shouldHideOnChar, isCollected, mountID, isSteadyFlight
C_MountJournal.GetMountInfoByID = function(id)
    return "Mount" .. id, 1000 + id, 2000 + id, false, true, 1, false, false, nil, false, id == 1, id, false
end
C_PetJournal.GetPetInfoByPetID = function() return 77, nil, nil, nil, nil, nil, nil, "Pet77", 3077 end
C_PetJournal.GetNumCollectedInfo = function() return 1, 3 end
C_ToyBox.GetToyInfo = function(id) return id, "Toy" .. id, 4000 + id end
C_ToyBox.GetNumToys = function() return 0 end
C_ToyBox.GetNumTotalDisplayedToys = function() return 0 end

local before = WarbandNexus:GetCollectionCountsFromAPI()
local primed = before and before.mounts and before.mounts.collected
local callsAfterPrime = mountIDsCalls
check(primed ~= nil, "counts cache primed (mount pass ran)", tostring(primed))

sent = {}
WarbandNexus:OnNewMount("NEW_MOUNT_ADDED", 2)
assert_eq(CountSent(E.COLLECTIBLE_OBTAINED), 1, "new mount: one COLLECTIBLE_OBTAINED")
assert_eq(CountSent(E.COLLECTION_UPDATED, "mount"), 1, "new mount: exactly one COLLECTION_UPDATED(mount)")
local after = WarbandNexus:GetCollectionCountsFromAPI()
assert_eq(mountIDsCalls, callsAfterPrime, "new mount: counts read after the obtain did not re-run the journal pass")
assert_eq(after and after.mounts and after.mounts.collected, (primed or 0) + 1, "new mount: cached mount count adjusted in place (+1)")

sent = {}
WarbandNexus:OnNewMount("NEW_MOUNT_ADDED", 2)
assert_eq(CountSent(E.COLLECTIBLE_OBTAINED), 0, "repeat mount (deduped): no COLLECTIBLE_OBTAINED")
assert_eq(CountSent(E.COLLECTION_UPDATED, "mount"), 1, "repeat mount (deduped): still one COLLECTION_UPDATED(mount)")

sent = {}
WarbandNexus:OnNewPet("NEW_PET_ADDED", "BattlePet-0-000000000077")
assert_eq(CountSent(E.COLLECTIBLE_OBTAINED), 1, "new pet: one COLLECTIBLE_OBTAINED")
assert_eq(CountSent(E.COLLECTION_UPDATED, "pet"), 1, "new pet: exactly one COLLECTION_UPDATED(pet)")

sent = {}
WarbandNexus:OnNewToy("NEW_TOY_ADDED", 5005)
assert_eq(CountSent(E.COLLECTIBLE_OBTAINED), 1, "new toy: one COLLECTIBLE_OBTAINED")
assert_eq(CountSent(E.COLLECTION_UPDATED, "toy"), 1, "new toy: exactly one COLLECTION_UPDATED(toy)")

-- A journal refresh (string arg from anyone else) still drops the counts cache.
local callsBefore = mountIDsCalls
WarbandNexus:SendMessage(E.COLLECTION_UPDATED, "mount")
WarbandNexus:GetCollectionCountsFromAPI()
assert_eq(mountIDsCalls, callsBefore + 1, "plain COLLECTION_UPDATED(mount) still forces a recount")

-- ======================================================================
print("2. Collections tab SCAN_COMPLETE: per-category invalidation, one coalesced redraw")
-- ======================================================================
local function ExtractListenerBlock()
    local fh = assert(io.open(ROOT .. "/Modules/UI/CollectionsUI.lua", "rb"))
    local src = fh:read("*a")
    fh:close()
    local s = src:find("    if not M.state._messageRegistered then", 1, true)
    local e = src:find("\n    return yOffset\nend", s, true)
    assert(s and e, "CollectionsUI listener block not found")
    return "local M, WarbandNexus, Constants, ns = ...\n" .. src:sub(s, e)
end
local draws = { recent = 0, mounts = 0, pets = 0, toys = 0, achievements = 0 }
local M = {
    state = { contentFrame = {}, currentSubTab = "mounts" },
    DrawRecentContent = function() draws.recent = draws.recent + 1 end,
    DrawMountsContent = function() draws.mounts = draws.mounts + 1 end,
    DrawPetsContent = function() draws.pets = draws.pets + 1 end,
    DrawToysContent = function() draws.toys = draws.toys + 1 end,
    DrawAchievementsContent = function() draws.achievements = draws.achievements + 1 end,
}
WarbandNexus.mainFrame = { IsShown = function() return true end, currentTab = "collections" }
local block = assert(loadstring(ExtractListenerBlock(), "@CollectionsUI_listeners"))
block(M, WarbandNexus, ns.Constants, ns)
check(M.state._messageRegistered == true, "listener block registered")

local function ResetDraws() for k in pairs(draws) do draws[k] = 0 end end
local function Seed()
    M.state._cachedMountsData = "m"; M.state._lastGroupedMountData = "m"; M.state._mountFlatList = "m"
    M.state._cachedPetsData = "p"; M.state._lastGroupedPetData = "p"; M.state._petFlatList = "p"
    M.state._cachedToysData = "t"; M.state._lastGroupedToyData = "t"; M.state._toyFlatList = "t"
    M.state._achGroupedCache = "a"; M.state._lastAchievementCategoryData = "a"; M.state._achFlatList = "a"
end

-- Achievement scan finishes while the Mounts sub-tab is visible.
Seed(); ResetDraws()
WarbandNexus:SendMessage(E.COLLECTION_SCAN_COMPLETE, { category = "achievement", totalAchievements = 10, elapsed = 1 })
assert_eq(draws.mounts, 0, "achievement scan: no synchronous redraw of the Mounts sub-tab")
stub.Advance(0.2)
assert_eq(draws.mounts, 0, "achievement SCAN_COMPLETE: hidden category does not redraw Mounts")
-- (the COLLECTION_UPDATED("achievement") that follows keeps its own unconditional coalesced redraw)
WarbandNexus:SendMessage(E.COLLECTION_UPDATED, "achievement")
stub.Advance(0.2)
assert_eq(M.state._cachedMountsData, "m", "achievement scan: mount caches kept")
assert_eq(M.state._cachedPetsData, "p", "achievement scan: pet caches kept")
check(M.state._achGroupedCache == nil and M.state._achFlatList == nil, "achievement scan: achievement caches dropped")

-- Same scan with the Achievements sub-tab visible: one redraw, not two.
M.state.currentSubTab = "achievements"
Seed(); ResetDraws()
WarbandNexus:SendMessage(E.COLLECTION_SCAN_COMPLETE, { category = "achievement", totalAchievements = 10, elapsed = 1 })
WarbandNexus:SendMessage(E.COLLECTION_UPDATED, "achievement")
assert_eq(draws.achievements, 0, "achievements visible: redraw is not synchronous")
stub.Advance(0.2)
assert_eq(draws.achievements, 1, "achievements visible: SCAN_COMPLETE + COLLECTION_UPDATED -> one redraw")

-- Failed achievement scan: nothing changed, keep caches; loading state still repaints once.
Seed(); ResetDraws()
WarbandNexus:SendMessage(E.COLLECTION_SCAN_COMPLETE, { category = "achievement", failed = true })
stub.Advance(0.2)
assert_eq(M.state._achGroupedCache, "a", "failed scan: achievement caches kept")
assert_eq(draws.achievements, 1, "failed scan: one repaint of the visible sub-tab")

-- Title scan: no Collections sub-tab renders it.
M.state.currentSubTab = "mounts"
Seed(); ResetDraws()
WarbandNexus:SendMessage(E.COLLECTION_SCAN_COMPLETE, { category = "title", results = {}, elapsed = 0 })
stub.Advance(0.2)
assert_eq(M.state._cachedMountsData, "m", "title scan: caches kept")
assert_eq(draws.mounts, 0, "title scan: no redraw")

-- Whole pipeline done: full invalidation + one redraw of the visible sub-tab.
Seed(); ResetDraws()
WarbandNexus:SendMessage(E.COLLECTION_SCAN_COMPLETE, { category = "all" })
stub.Advance(0.2)
check(M.state._cachedMountsData == nil and M.state._achGroupedCache == nil, "all: every sub-tab cache dropped")
assert_eq(draws.mounts, 1, "all: one redraw of the visible sub-tab")

-- ======================================================================
print("3. Bag-scan baseline rebuilt when the Collections module is re-enabled")
-- ======================================================================
local CHECK_ITEMS = { [9001] = true, [9002] = true, [9003] = true }
WarbandNexus.CheckNewCollectible = function(_, itemID)
    if CHECK_ITEMS[itemID] then return { type = "mount", id = itemID + 100, name = "BagMount" .. itemID, icon = 1 } end
    return nil
end
local function BagEventsAndSettle()
    stub.Advance(3)
    stub.Fire("BAG_UPDATE", 0)
    stub.Fire("BAG_UPDATE_DELAYED")
    stub.Advance(1)
end
local function ObtainedBagMount(itemID)
    local n = 0
    for i = 1, #sent do
        if sent[i].msg == E.COLLECTIBLE_OBTAINED and type(sent[i].arg) == "table" and sent[i].arg.id == itemID + 100 then
            n = n + 1
        end
    end
    return n
end

-- Login with the module off: PLAYER_ENTERING_WORLD builds nothing.
WarbandNexus.db.profile.modulesEnabled.collections = false
stub.Fire("PLAYER_ENTERING_WORLD", true, false)
-- Turn it on from settings, then loot a mount item.
WarbandNexus.db.profile.modulesEnabled.collections = true
WarbandNexus:SendMessage(E.MODULE_TOGGLED, "collections", true)
sent = {}
bags[0][1] = 9001
BagEventsAndSettle()
assert_eq(ObtainedBagMount(9001), 1, "enabled after login: mount item looted afterwards is detected (no loading screen needed)")

-- Next loading screen, then off -> pick up a mount item -> on.
stub.Fire("PLAYER_ENTERING_WORLD", false, false)
stub.Advance(3)
WarbandNexus.db.profile.modulesEnabled.collections = false
WarbandNexus:SendMessage(E.MODULE_TOGGLED, "collections", false)
bags[0][2] = 9002
stub.Fire("BAG_UPDATE", 0)
stub.Fire("BAG_UPDATE_DELAYED")
stub.Advance(1)
WarbandNexus.db.profile.modulesEnabled.collections = true
WarbandNexus:SendMessage(E.MODULE_TOGGLED, "collections", true)
sent = {}
BagEventsAndSettle()
assert_eq(ObtainedBagMount(9002), 0, "re-enabled: mount item picked up while disabled is not reported as new")
sent = {}
bags[0][3] = 9003
BagEventsAndSettle()
assert_eq(ObtainedBagMount(9003), 1, "re-enabled: a mount item looted afterwards is still detected")

-- ======================================================================
print("4. EnsureCollectionData: timeout drops the achievement listener; old timeouts spare newer runs")
-- ======================================================================
local titleScans, achScans = 0, 0
local achievementCompletes = false
WarbandNexus.BuildFullCollectionData = function(_, cb) if cb then cb() end end
WarbandNexus.ScanCollection = function(_, category, _, cb)
    if category == "title" then titleScans = titleScans + 1 end
    if cb then cb() end
end
WarbandNexus.ScanAchievementsAsync = function(self)
    achScans = achScans + 1
    if achievementCompletes then
        self:SendMessage(E.COLLECTION_SCAN_COMPLETE, { category = "achievement" })
    end
end
local CLS = ns.CollectionLoadingState

-- Run A: achievement scan never reports back -> 60 s timeout.
WarbandNexus:EnsureCollectionData()
stub.Advance(1)
assert_eq(achScans, 1, "run A reached the achievement step")
check(CLS.isLoading == true, "run A loading while the achievement step waits")
stub.Advance(60)
check(CLS.isLoading == false, "run A force-cleared by its timeout")
local titleBefore = titleScans
WarbandNexus:SendMessage(E.COLLECTION_SCAN_COMPLETE, { category = "achievement" })
stub.Advance(2)
assert_eq(titleScans, titleBefore, "late achievement scan does not resume the timed-out run (no title step)")

-- Run B completes quickly; run C starts 10 s later and is still waiting when B's timer fires.
achievementCompletes = true
WarbandNexus:EnsureCollectionData()
stub.Advance(2)
check(CLS.isLoading == false, "run B completed")
stub.Advance(10)
achievementCompletes = false
WarbandNexus:EnsureCollectionData()
stub.Advance(1)
check(CLS.isLoading == true, "run C waiting on its achievement step")
stub.Advance(50) -- run B's 60 s timer fires here
check(CLS.isLoading == true, "run B's stale timeout does not force-clear run C")
stub.Advance(15) -- run C's own timer
check(CLS.isLoading == false, "run C cleared by its own timeout")

check(#stub.errors == 0, "no timer/event errors", table.concat(stub.errors, " | "))

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then error(failed .. " check(s) failed") end
