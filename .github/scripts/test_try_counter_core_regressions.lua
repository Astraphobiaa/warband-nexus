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

print("phase 4b: a failed pickpocket / gathering cast does not swallow the next kill")
local RARE, RARE_ITEM = 137202, 163573   -- Goldenmane (Stormsong Valley), loot-path eligible
local function RareCount()
    local drops = RT.npcDropDB[RARE]
    for i = 1, #drops do
        if drops[i].itemID == RARE_ITEM then
            local t, k = Fns.GetTryCountTypeAndKey(drops[i])
            return WN:GetTryCount(t, k) or 0
        end
    end
end
local killSeq = 0
local function KillRare(gap)
    stub.Advance(gap)
    stub.Reset()
    killSeq = killSeq + 1
    stub.world.mapID = 1527
    stub.world.isFishingLoot = false
    stub.world.lootSlots = { { hasItem = true, link = "|Hitem:2589::::::::::::::::|h[Linen]|h" } }
    stub.world.lootSources = { { ("Creature-0-0-0-0-%d-%012d"):format(RARE, 900 + killSeq), 1 } }
    local before = RareCount()
    stub.Fire("LOOT_READY", false)
    stub.Fire("LOOT_OPENED", false, false)
    stub.Advance(0.05)
    stub.Fire("LOOT_CLOSED")
    stub.Advance(3)
    return RareCount() - before
end
check(KillRare(30) == 1, "control: a plain rare kill counts")
stub.Fire("UNIT_SPELLCAST_SENT", "player", nil, "Cast-1", 8613)      -- Skinning
stub.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-1", 8613)
check(KillRare(2) == 1, "kill 2s after an interrupted skinning cast counts")
stub.Fire("UNIT_SPELLCAST_SENT", "player", nil, "Cast-2", 921)       -- Pick Pocket, fails silently
check(KillRare(15) == 1, "kill 15s after a pickpocket that opened no window counts")
stub.Advance(30)
stub.Fire("UNIT_SPELLCAST_SENT", "player", nil, "Cast-3", 8613)      -- Skinning that succeeds
check(KillRare(1) == 0, "skinning loot right after the cast is still skipped")

print("phase 4c: a living targeted rare is never the loot source")
local function OpenLoot(sources, gap)
    stub.Advance(gap or 30)
    stub.Reset()
    stub.world.mapID = 1527
    stub.world.isFishingLoot = false
    stub.world.lootSlots = { { hasItem = true, link = "|Hitem:2589::::::::::::::::|h[Linen]|h" } }
    stub.world.lootSources = sources
    local before = RareCount()
    stub.Fire("LOOT_READY", true)
    stub.Advance(0.05)
    stub.Fire("LOOT_CLOSED")   -- fast auto-loot: no LOOT_OPENED
    stub.Advance(3)
    return RareCount() - before
end
UNITS.target = "Creature-0-0-0-0-" .. RARE .. "-000000000301"
check(OpenLoot({ { "GameObject-0-0-0-0-310000-000000000077", 1 } }) == 0,
    "untracked chest looted with a living rare targeted: no try")
check(OpenLoot({}) == 0, "empty-source auto-loot with a living rare targeted: no try")
DEAD.target = true
check(OpenLoot({}) == 1, "empty-source auto-loot of the dead rare on target still counts")
UNITS.target, DEAD.target = nil, nil

print("phase 4d: a creature beside the bobber is never learned as a bobber")
local DRAKE_MOUNT, VOIDSTORM, TRASH = 260916, 2405, 99991
local function DrakeCount() return WN:GetTryCount("mount", DRAKE_MOUNT) or 0 end
local function Fish(sources, gap)
    stub.Advance(gap or 30)
    stub.Reset()
    stub.world.mapID = VOIDSTORM
    stub.world.isFishingLoot = true
    stub.world.lootSlots = { { hasItem = true, link = "|Hitem:6303::::::::::::::::|h[Fish]|h" } }
    stub.world.lootSources = sources
    local before = DrakeCount()
    stub.Fire("LOOT_READY", true)
    stub.Fire("LOOT_OPENED", true, false)
    stub.Advance(0.05)
    stub.Fire("LOOT_CLOSED")
    stub.Advance(5)
    return DrakeCount() - before
end
Fish({ { "GameObject-0-0-0-0-777777-000000000001", 1, "Creature-0-0-0-0-" .. TRASH .. "-000000000009", 1 } })
check(not Fns.IsFishingBobberNpcId(TRASH), "creature sharing a fishing session is not learned")
check((WN.db.global.discoveredFishingBobbers or {})[TRASH] == nil, "and is not persisted")
UNITS.target = "Creature-0-0-0-0-" .. TRASH .. "-000000000011"
DEAD.target = true
check(Fish({ { "GameObject-0-0-0-0-777777-000000000002", 1 } }) == 1,
    "catch with a dead mob on target still counts as fishing")
UNITS.target, DEAD.target = nil, nil

print("phase 4e: only a container that was really consumed counts")
local cid, cdrops
for id, data in pairs(RT.containerDropDB) do
    local d = data.drops or data
    if type(d) == "table" and #d > 0 then
        local ok = true
        for i = 1, #d do if d[i].repeatable then ok = false end end
        if ok then cid, cdrops = id, d break end
    end
end
check(cid ~= nil, "found a container with non-repeatable drops")
local function CTries()
    local t, k = Fns.GetTryCountTypeAndKey(cdrops[1])
    return WN:GetTryCount(t, k) or 0
end
local bags = {}
local origGetID, origGetInfo = C_Container.GetContainerItemID, C_Container.GetContainerItemInfo
C_Container.GetContainerItemID = function(b, sl) local e = bags[b * 100 + sl]; return e and e.id end
C_Container.GetContainerItemInfo = function(b, sl) local e = bags[b * 100 + sl]; return e and { stackCount = e.n, itemID = e.id } end
local function SetBag(slot, n)
    bags[slot] = (n and n > 0) and { id = cid, n = n } or nil
    local total = 0
    for _, e in pairs(bags) do if e.id == cid then total = total + e.n end end
    stub.world.bagCounts[cid] = total
end
local function Lock(slot) WN:OnTryCounterItemLockChanged("ITEM_LOCK_CHANGED", 0, slot) end

stub.Advance(30); stub.Reset(); bags = {}
SetBag(1, 1)
local c0 = CTries()
Lock(1); stub.Advance(0.2)
SetBag(1, nil); SetBag(2, 1)
Lock(1); Lock(2); stub.Advance(5)
check(CTries() == c0, "moving the container between slots is not an attempt (got +" .. (CTries() - c0) .. ")")

stub.Advance(30); stub.Reset(); bags = {}
SetBag(3, 1)
c0 = CTries()
Lock(3); stub.Advance(0.1); SetBag(3, nil); stub.Advance(5)
check(CTries() == c0 + 1, "silent open with no loot window counts once (got +" .. (CTries() - c0) .. ")")

stub.Advance(30); stub.Reset(); bags = {}
SetBag(4, 5)
c0 = CTries()
Lock(4); stub.Advance(0.1); SetBag(4, 4); Lock(4); stub.Advance(5)
check(CTries() == c0 + 1, "opening one of a stack of 5 counts once (got +" .. (CTries() - c0) .. ")")

stub.Advance(30); stub.Reset(); bags = {}
SetBag(5, 1)
c0 = CTries()
stub.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)   -- Merchant
Lock(5); stub.Advance(0.1); SetBag(5, nil); stub.Advance(5)
stub.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
check(CTries() == c0, "selling the container to a merchant is not an attempt (got +" .. (CTries() - c0) .. ")")

stub.Advance(30); stub.Reset(); bags = {}
SetBag(6, 1)
c0 = CTries()
Lock(6); SetBag(6, nil)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:6303::::::::::::::::|h[Junk]|h" } }
stub.world.lootSources = {}
stub.Fire("LOOT_READY", false)
stub.Fire("LOOT_OPENED", false, true)
stub.Advance(2.5)
WN:OnTryCounterChatMsgLoot("You receive loot: |cffffffff|Hitem:6303::::::::::::::::|h[Junk]|h|r", UnitName("player"))
stub.Fire("LOOT_CLOSED")
stub.Advance(5)
check(CTries() == c0 + 1, "clicking loot 2.5s into an open container window counts once (got +"
    .. (CTries() - c0) .. ")")

stub.Advance(30); stub.Reset(); bags = {}
SetBag(7, 1)
local obtainSends = 0
local origSend = WN.SendMessage
WN.SendMessage = function(self, msg, ...)
    if msg == "WN_COLLECTIBLE_OBTAINED" then obtainSends = obtainSends + 1 end
    if origSend then return origSend(self, msg, ...) end
end
local prize = cdrops[1]
Lock(7); SetBag(7, nil)
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:" .. prize.itemID .. "::::::::::::::::|h[Prize]|h" } }
stub.world.lootSources = {}
stub.Fire("LOOT_READY", false)
stub.Fire("LOOT_OPENED", false, true)
stub.Advance(0.5)
WN:OnTryCounterChatMsgLoot("You receive loot: |cffa335ee|Hitem:" .. prize.itemID
    .. "::::::::::::::::|h[Prize]|h|r", UnitName("player"))
stub.Fire("LOOT_CLOSED")
stub.Advance(5)
WN.SendMessage = origSend
local obtainLines = 0
for i = 1, #stub.chat do
    if stub.chat[i]:find("You got", 1, true) or stub.chat[i]:find("Obtained", 1, true) then obtainLines = obtainLines + 1 end
end
check(obtainLines == 1, "a container obtain is announced once (got " .. obtainLines .. ")")
check(obtainSends <= 1, "WN_COLLECTIBLE_OBTAINED sent at most once (got " .. obtainSends .. ")")
C_Container.GetContainerItemID, C_Container.GetContainerItemInfo = origGetID, origGetInfo

print("phase 5: no errors escaped any handler or timer")
check(#stub.errors == 0, "no runtime errors" .. (stub.errors[1] and (": " .. stub.errors[1]) or ""))

if failures > 0 then
    print(("FAILED: %d check(s)"):format(failures))
    os.exit(1)
end
print("all core regression checks passed")
