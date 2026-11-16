#!/usr/bin/env lua
--[[
    Regression test: WoW Forever class trainer dropped the game to 1-2 fps.

    ScanTrainerServices switches the "used" service filter on (Blizzard's trainer defaults it off)
    and back. A filter change makes the client fire TRAINER_UPDATE; EventManager rescanned on every
    TRAINER_UPDATE, so each scan armed the next one 0.3s later for as long as the trainer stayed
    open -- every turn redrawing the Blizzard list twice, walking every service and emitting
    WN_TRAINER_SKILLS_UPDATED.

    Loads the shipped Modules/EventManager.lua + Modules/TrainerService.lua under wow_stub.lua and
    drives a fake trainer whose filter setter fires TRAINER_UPDATE (both async and in-call).
]]

local passed, failed = 0, 0
local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")
table.wipe = _G.wipe

-- ---------- fake class trainer ----------
local handlers = {}
local trainer = {
    open = false,
    syncEvents = false,
    filters = { available = true, unavailable = true, used = false },   -- Blizzard defaults
    rows = {
        { name = "Healing Wave", category = "used", level = 1 },
        { name = "Lightning Bolt", category = "used", level = 1 },
        { name = "Lightning Bolt", category = "available", level = 8 },
        { name = "Earth Shock", category = "available", level = 4 },
        { name = "Lightning Shield", category = "unavailable", level = 10 },
    },
}
local fullReads, filterSets = 0, 0

local function FireTrainerUpdate()
    if not trainer.open then return end
    local fn = handlers["TRAINER_UPDATE"]
    if fn then fn("TRAINER_UPDATE") end
end

local function Visible()
    local out = {}
    for i = 1, #trainer.rows do
        local r = trainer.rows[i]
        if trainer.filters[r.category] then out[#out + 1] = r end
    end
    return out
end

UnitClass = function() return "Shaman", "SHAMAN" end
UnitLevel = function() return 8 end
IsTradeskillTrainer = function() return false end
GetNumTrainerServices = function() return trainer.open and #Visible() or 0 end
GetTrainerServiceInfo = function(i)
    local r = Visible()[i]
    if not r then return nil end
    return r.name, r.category, nil, false
end
GetTrainerServiceLevelReq = function(i)
    fullReads = fullReads + 1
    local r = Visible()[i]
    return r and r.level
end
GetTrainerServiceTypeFilter = function(name) return trainer.filters[name] end
SetTrainerServiceTypeFilter = function(name, on)
    filterSets = filterSets + 1
    trainer.filters[name] = on and true or false
    -- The client answers a filter change with TRAINER_UPDATE.
    if trainer.syncEvents then FireTrainerUpdate() else C_Timer.After(0, FireTrainerUpdate) end
end

-- ---------- addon under test ----------
local emits = 0
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg) if msg == "WN_TRAINER_SKILLS_UPDATED" then emits = emits + 1 end end,
    RegisterMessage = function() end,
    RegisterEvent = function(_, ev, fn) if type(fn) == "function" then handlers[ev] = fn end end,
    RegisterBucketEvent = function() end,
    UnregisterEvent = function() end,
    Print = function() end,
    SupportsFeature = function() return true end,
}
local ns = { WarbandNexus = WarbandNexus }
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function() return "Player-1-00000001" end,
    ResolveCharactersTableKey = function() return "Player-1-00000001" end,
}

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a"):gsub("^\239\187\191", "")
    fh:close()
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Modules/Constants.lua")
LoadFile("Modules/Utilities.lua")
LoadFile("Modules/TrainerService.lua")
LoadFile("Modules/EventManager.lua")
local okInit, initErr = pcall(WarbandNexus.InitializeEventManager, WarbandNexus)
if not okInit then error("InitializeEventManager: " .. tostring(initErr), 0) end
assert(handlers["TRAINER_UPDATE"], "TRAINER_UPDATE not registered")

local function Reset()
    fullReads, filterSets, emits = 0, 0, 0
end

local function OpenTrainer()
    trainer.open = true
    handlers["TRAINER_SHOW"]("TRAINER_SHOW")
    FireTrainerUpdate()   -- the service list arrives a moment after the frame
end

local function CloseTrainer()
    trainer.open = false
    if handlers["TRAINER_CLOSED"] then handlers["TRAINER_CLOSED"]("TRAINER_CLOSED") end
end

local ROWS = #trainer.rows

print("Opening a trainer scans once, then goes quiet (async TRAINER_UPDATE on filter change)")
do
    Reset()
    OpenTrainer()
    stub.Advance(30)   -- 30 s standing at the trainer: the old code rescanned ~100 times
    assert_eq(fullReads, ROWS, "exactly one full service walk")
    assert_eq(filterSets, 2, "one filter round-trip (used on, used off)")
    assert_eq(emits, 1, "one WN_TRAINER_SKILLS_UPDATED")
    assert_eq(trainer.filters.used, false, "player's own filter restored")
    local store = WarbandNexus:GetTrainerSkills("SHAMAN")
    assert_eq(store and #store.services, ROWS, "every rank cached, hidden 'used' rows included")
end

print("Buying a spell rescans once, then goes quiet again")
do
    Reset()
    trainer.rows[4].category = "used"   -- Earth Shock bought: drops out of the default view
    FireTrainerUpdate()
    stub.Advance(30)
    assert_eq(fullReads, ROWS, "one full walk for the purchase")
    assert_eq(emits, 1, "one emit for the purchase")
end

print("An update that changes nothing visible does not rescan")
do
    Reset()
    for _ = 1, 20 do FireTrainerUpdate(); stub.Advance(0.5) end
    stub.Advance(30)
    assert_eq(fullReads, 0, "no full walk")
    assert_eq(filterSets, 0, "filters untouched")
    assert_eq(emits, 0, "no emit")
end

print("Re-opening with nothing new scans once and emits nothing")
do
    CloseTrainer()
    Reset()
    OpenTrainer()
    stub.Advance(30)
    assert_eq(fullReads, ROWS, "one full walk per visit")
    assert_eq(emits, 0, "no emit without a real change")
end

print("Closing cancels a pending scan")
do
    CloseTrainer()
    Reset()
    trainer.open = true
    handlers["TRAINER_SHOW"]("TRAINER_SHOW")
    CloseTrainer()
    stub.Advance(30)
    assert_eq(fullReads, 0, "no scan of a closed trainer")
end

print("Same, when the client fires TRAINER_UPDATE inside the filter call")
do
    trainer.syncEvents = true
    Reset()
    OpenTrainer()
    stub.Advance(30)
    assert_eq(fullReads, ROWS, "exactly one full service walk")
    assert_eq(filterSets, 2, "one filter round-trip")
    trainer.syncEvents = false
    CloseTrainer()
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
