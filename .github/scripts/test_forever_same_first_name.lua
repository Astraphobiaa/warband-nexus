#!/usr/bin/env lua5.1
--[[
    WoW Forever first names are not unique on a realm: "Elementalist Vhorzen" and "Elementalist
    Ashford" share the Name-Realm key Elementalist-<realm>. The live player's row used to be found
    by that key, so the second character resolved to the FIRST one's GUID row, skipped the tracking
    prompt, and every save (name, gold, bags, currencies) overwrote the other character -- only the
    last-played character remained ("other characters' data is gone").

    Loads the shipped Constants, Capabilities, Utilities and CharacterService under wow_stub.lua
    with a Forever client and checks that a same-first-name character never resolves to another
    character's row, while the original character still resolves to its own.
]]

local loadstring = loadstring or load
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(".github/scripts/wow_stub.lua")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print("  FAIL " .. msg)
    end
end

-- Forever client: UnitName's second value is the SURNAME, not a realm.
local cur = {}
UnitGUID = function(u) if u == "player" then return cur.guid end end
UnitName = function() return cur.name, cur.surname end
GetNormalizedRealmName = function() return cur.realm end
GetRealmName = function() return cur.realm end
WOW_PROJECT_CAMELOT = 18
WOW_PROJECT_ID = 18

local ns = {}
local WN = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function() end, RegisterMessage = function() end,
    RegisterEvent = function() end, Print = function() end,
    -- ModuleManager.lua's capability gate (not loaded here).
    SupportsFeature = function(_, key) return not ns.Capabilities or ns.Capabilities:Supports(key) end,
}
ns.WarbandNexus = WN
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end,
    SliceLabel = function() return "" end }

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing " .. rel)
    local src = fh:read("*a"):gsub("^\239\187\191", "")
    fh:close()
    local chunk = assert(loadstring(src, "@" .. rel))
    local ok, err = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(err), 0) end
end

LoadFile("Locales/enUS.lua")
ns.L = (ns.LOCALES and ns.LOCALES.enUS) or {}
LoadFile("Modules/Constants.lua")
LoadFile("Modules/Capabilities.lua")
LoadFile("Modules/Utilities.lua")
LoadFile("Modules/CharacterService.lua")

local U, CS = ns.Utilities, ns.CharacterService
local chars = WN.db.global.characters
local REALM = "CAMWOWEU4Realm5PvE"
local A = "Player-6939-0000000A"
chars[A] = { name = "Elementalist", surname = "Vhorzen", realm = REALM, guid = A,
    isTracked = true, trackingConfirmed = true, lastSeen = 100, classFile = "SHAMAN", level = 15 }

local function Login(guid, name, surname, realm)
    cur.guid, cur.name, cur.surname, cur.realm = guid, name, surname, realm
    if U.InvalidateCharacterKeyIndex then U:InvalidateCharacterKeyIndex() end
end

print("Phase 1: a second character with the SAME first name on the same realm")
local C = "Player-6939-0000000C"
Login(C, "Elementalist", "Ashford", REALM)
check(CS:ResolveCharactersTableKey(WN) == nil, "new same-first-name character has no row yet (not A's)")
check(CS:ResolveSubsidiaryCharacterKey(WN) ~= A, "its bags / currencies do not resolve to A's buckets")
check(CS:IsCharacterTracked(WN) ~= true or chars[C] ~= nil, "it is not treated as tracked through A's row")

print("Phase 2: once both rows exist, a shared Name-Realm key is ambiguous, never one of them")
chars[C] = { name = "Elementalist", surname = "Ashford", realm = REALM, guid = C,
    isTracked = true, trackingConfirmed = true, lastSeen = 200 }
Login(C, "Elementalist", "Ashford", REALM)
check(CS:ResolveCharactersTableKey(WN) == C, "C resolves to its own GUID row")
Login(A, "Elementalist", "Vhorzen", REALM)
check(CS:ResolveCharactersTableKey(WN) == A, "A still resolves to its own GUID row")
check(chars[A].surname == "Vhorzen" and chars[C].surname == "Ashford", "both rows survive with their own identity")
local copies = CS:FindProbableStaleCharacterCopies(WN)
local offersC = false
for i = 1, #copies do if copies[i].key == C then offersC = true end end
check(not offersC, "the other Elementalist is not offered as a stale copy to delete")

print("Phase 3: Forever Name-Realm identity includes the surname")
Login(C, "Elementalist", "Ashford", REALM)
check(U:GetCharacterKey() == "ElementalistAshford-" .. REALM, "live key carries the surname")
local untrackedA = { name = "Elementalist", surname = "Vhorzen", realm = REALM }
local untrackedC = { name = "Elementalist", surname = "Ashford", realm = REALM }
check(U:ResolveCharacterRowKey(untrackedA) ~= U:ResolveCharacterRowKey(untrackedC),
    "two guid-less same-first-name rows keep distinct keys")
check(U:GetCharacterKey("Elementalist", REALM) == "Elementalist-" .. REALM, "no surname given: key unchanged")

print("Phase 4: a different first name is unaffected")
Login("Player-6939-0000000B", "Stormcaller", "Vhorzen", REALM)
check(CS:ResolveCharactersTableKey(WN) == nil, "unrelated new character gets its own row")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Forever same-first-name suite failed with " .. failed .. " failure(s).")
end
print("Forever same-first-name suite: ALL TESTS PASSED.")
