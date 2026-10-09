#!/usr/bin/env lua5.1
--[[
    Try Counter core regressions found by the 2026-10-09 audit, driven through the REAL shipped files.

      1. File-scope state assigned above its `local` declaration leaked to _G and left the real local
         untouched (discoveryPendingTime, reverseIndicesBuilt, `_`).
      2. Lockout-quest auto-discovery never learned anything: the pending timestamp it compared was a
         different variable from the one ScheduleLockoutDiscovery wrote.
      3. RT.chatLootItemToNpc stayed bound to the empty load-time table, so CHAT_MSG_LOOT Path 2
         (direct loot, no loot window) never matched.
      4. Path 2 revived must not count without proof the NPC died.
]]

-- The stub only answers UnitGUID("player"); give the tests a target unit they can kill.
local UNITS, DEAD = {}, {}
local realDofile = dofile
dofile = function(p)
    local r = realDofile(p)
    if p:match("wow_stub%.lua$") then
        local orig = _G.UnitGUID
        _G.UnitGUID = function(u) if UNITS[u] then return UNITS[u] end return orig(u) end
        _G.UnitIsDead = function(u) return DEAD[u] == true end
    end
    return r
end

local H = dofile(".github/scripts/wow_addon_harness.lua")
dofile = realDofile
local stub, WN, Fns, RT = H.stub, H.WN, H.Fns, H.RT

local failures = 0
local function check(cond, msg)
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

print("phase 1: no file-scope state leaks to _G")
Fns.EnsureTryCounterRuntimeDbLoaded()
Fns.ScheduleLockoutDiscovery(424243)
Fns.IsMountLearnedByItemSpell(276549)
check(rawget(_G, "discoveryPendingTime") == nil, "discoveryPendingTime stays local")
check(rawget(_G, "reverseIndicesBuilt") == nil, "reverseIndicesBuilt stays local")
check(rawget(_G, "_") == nil, "global _ untouched")

-- Runtime checks only see the paths a test happens to drive; the bytecode sees every assignment.
-- luac 5.1 lists global writes as SETGLOBAL, LuaJIT as GSET. Skip (loudly) when neither tool exists.
local TRY_COUNTER_FILES = {
    "Modules/TryCounterService_Shared.lua", "Modules/TryCounterService_Events.lua",
    "Modules/TryCounterService_Process.lua", "Modules/TryCounterService.lua",
    "Modules/TryCounterService_Loot.lua", "Modules/TryCounterService_Stats.lua",
    "Modules/TryCounterService_Handlers.lua",
}
local function ListGlobalWrites(path)
    local out, pattern = "", "SETGLOBAL.-; ([%w_]+)"
    for _, luac in ipairs({ "luac5.1", "luac" }) do
        local p = io.popen(luac .. " -l -p '" .. path .. "' 2>/dev/null")
        out = p and p:read("*a") or ""
        if p then p:close() end
        if out ~= "" then break end
    end
    if out == "" then
        local p = io.popen("luajit -bl '" .. path .. "' 2>/dev/null")
        out = p and p:read("*a") or ""
        if p then p:close() end
        pattern = "GSET.-; \"([%w_]+)\""
    end
    if out == "" then return nil end
    local names = {}
    for name in out:gmatch(pattern) do names[#names + 1] = name end
    return names
end
for i = 1, #TRY_COUNTER_FILES do
    local names = ListGlobalWrites(TRY_COUNTER_FILES[i])
    if names == nil then
        print("  skip no luac/luajit to list bytecode for " .. TRY_COUNTER_FILES[i])
    else
        check(#names == 0, TRY_COUNTER_FILES[i] .. " writes no globals"
            .. (#names > 0 and (" (got " .. table.concat(names, ", ") .. ")") or ""))
    end
end

print("phase 2: lockout-quest auto-discovery learns the quest")
local claimed = Fns.GetClaimedQuestIDs()
local questID
for q = 94440, 94480 do
    if not claimed[q] then questID = q break end
end
check(questID ~= nil, "found an unclaimed quest id in a discovery range")
stub.Advance(30)
Fns.TakeDiscoverySnapshot()
Fns.ScheduleLockoutDiscovery(424244)
stub.SetQuestCompleted(questID, true)
stub.Advance(2.5)
local learned = (WN.db.global.discoveredLockoutQuests or {})[424244]
check(learned == questID, "NPC 424244 learned quest " .. tostring(questID) .. " (got " .. tostring(learned) .. ")")

print("phase 2b: a quest completed before the rare was targeted is never learned as its lockout")
-- Another rare's hidden quest flips between login and this kill. Targeting the tracked rare must
-- re-baseline, or that quest becomes the lone candidate and is persisted as this NPC's lockout.
local rareNpc
for npcID in pairs(RT.npcDropDB) do
    if npcID > 1000 and RT.tryCounterNpcEligible[npcID] and not RT.lockoutQuestsDB[npcID] then rareNpc = npcID break end
end
local strayQuest
for q = 94440, 94480 do
    if q ~= questID and not claimed[q] then strayQuest = q break end
end
check(rareNpc ~= nil and strayQuest ~= nil, "found a tracked rare without lockout and a stray quest id")
stub.Advance(60)
stub.SetQuestCompleted(strayQuest, true)
UNITS.target = "Creature-0-0-0-0-" .. rareNpc .. "-000000000007"
stub.Fire("PLAYER_TARGET_CHANGED")
UNITS.target = nil
Fns.ScheduleLockoutDiscovery(rareNpc)
stub.Advance(2.5)
check((WN.db.global.discoveredLockoutQuests or {})[rareNpc] == nil,
    "stray quest " .. strayQuest .. " not learned for NPC " .. tostring(rareNpc))

print("phase 3: chat Path 2 map is the live table")
local mapped = 0
for _, v in pairs(RT.chatLootItemToNpc) do
    if type(v) == "number" then mapped = mapped + 1 end
end
check(mapped > 0, "RT.chatLootItemToNpc has entries after init (got " .. mapped .. ")")
check(RT.chatLootItemToNpc[235910] == 234621, "Gallagio coin override reaches RT")

print("phase 4: Path 2 counts only with kill evidence")
-- A world rare (no encounter) whose mount drop has no statistic / difficulty gating.
local pickItem, pickNpc
for item, npc in pairs(RT.chatLootItemToNpc) do
    if type(npc) == "number" and not RT.npcIDToEncounterID[npc] and RT.npcDropDB[npc] then
        local d = RT.npcDropDB[npc]
        if not d.statisticIds and not d.dropDifficulty then
            for i = 1, #d do
                if d[i].itemID == item and d[i].type == "mount" and #d > 1 then pickItem, pickNpc = item, npc end
            end
        end
    end
    if pickItem then break end
end
check(pickItem ~= nil, "found a world-rare mount mapped for Path 2")

local drop, other
for i = 1, #RT.npcDropDB[pickNpc] do
    local d = RT.npcDropDB[pickNpc][i]
    if d.itemID == pickItem then drop = d else other = other or d end
end
local tcType, key = Fns.GetTryCountTypeAndKey(drop)
local oType, oKey = Fns.GetTryCountTypeAndKey(other)
local function Chat()
    stub.Advance(5)   -- past CHAT_LOOT_DEBOUNCE from any earlier commit
    stub.Reset()
    WN:OnTryCounterChatMsgLoot("You receive loot: |cffa335ee|Hitem:" .. pickItem
        .. "::::::::::::::::|h[Mount]|h|r.", UnitName("player"))
    stub.Advance(2)
    return #stub.chat
end

WN:SetTryCount(tcType, key, 7)
WN:SetTryCount(oType, oKey, 3)
local nNoKill = Chat()
check(nNoKill == 0, "no kill evidence: no chat line (got " .. nNoKill .. ")")
check(WN:GetTryCount(oType, oKey) == 3, "no kill evidence: sibling drop not counted (got "
    .. tostring(WN:GetTryCount(oType, oKey)) .. ")")

UNITS.target = "Creature-0-0-0-0-" .. pickNpc .. "-000000000042"
local nLiving = Chat()
check(nLiving == 0, "living target is not kill evidence (got " .. nLiving .. ")")

DEAD.target = true
local nDead = Chat()
check(nDead >= 1, "dead target: obtain is announced (got " .. nDead .. ")")
check((stub.chat[1] or ""):find("8 attempts", 1, true) ~= nil, "obtain line reports the 8th attempt: "
    .. tostring(stub.chat[1]))
UNITS.target, DEAD.target = nil, nil

print("phase 5: no errors escaped any handler or timer")
check(#stub.errors == 0, "no runtime errors" .. (stub.errors[1] and (": " .. stub.errors[1]) or ""))

if failures > 0 then
    print(("FAILED: %d check(s)"):format(failures))
    os.exit(1)
end
print("all core regression checks passed")
