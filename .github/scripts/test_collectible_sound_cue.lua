#!/usr/bin/env lua5.1
--[[
    Collectible-obtained sound cue (Modules/NotificationManager.lua, real file under wow_stub).

    Regression: the "Achievement (default)" option resolved to SoundKit 31578 (UI_EPICLOOT_TOAST),
    so players heard the loot-won toast instead of the achievement-earned sound. The client plays
    that sound itself (no SOUNDKIT constant), so the cue must play fileDataID 569143
    (sound/spells/achievmentsound1.ogg) through PlaySoundFile -- in the toast and in the preview.

    Also pins every other option to the cue it played before, so the fix cannot drift into them.

    Run from the repo root:  lua5.1 .github/scripts/test_collectible_sound_cue.lua
]]

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."

dofile(SCRIPT_DIR .. "/wow_stub.lua")

local ACHIEVEMENT_FDID = 569143   -- sound/spells/achievmentsound1.ogg (wago.tools, 2026-11-23)
local EPICLOOT_KIT = 31578        -- SOUNDKIT.UI_EPICLOOT_TOAST (wow-ui-source SoundKitConstants)
local COMPACT_KIT = 44295
local PROGRESS_KIT = 44294
local QUEST_KIT = 23404           -- SOUNDKIT.UI_AUTO_QUEST_COMPLETE
local WN_PATH = [[Interface\AddOns\WarbandNexus\Media\Sounds\]]

-- Every play call lands here; fileWillPlay decides PlaySoundFile's willPlay return.
local plays = {}
local fileWillPlay = true
_G.PlaySoundFile = function(file, channel)
    plays[#plays + 1] = { api = "file", value = file, channel = channel }
    if fileWillPlay then return true, 1 end
    return nil
end
_G.PlaySound = function(kit, channel)
    plays[#plays + 1] = { api = "kit", value = kit, channel = channel }
    return true, 1
end
_G.SOUNDKIT = { UI_AUTO_QUEST_COMPLETE = QUEST_KIT, UI_EPICLOOT_TOAST = EPICLOOT_KIT }
_G.LibStub = function() return nil end
_G.GetLocale = function() return "enUS" end

local ns = {}
local WN = {}
ns.WarbandNexus = WN
WN.db = { profile = { notifications = {} }, global = {}, char = {} }
for _, m in ipairs({ "RegisterMessage", "UnregisterMessage", "RegisterEvent", "UnregisterEvent",
                     "SendMessage", "Print", "Debug", "ScheduleTimer", "CancelTimer" }) do
    WN[m] = function() end
end

-- NotificationManager asserts its satellites at load. This suite only exercises the sound
-- resolver, so empty tables satisfy the asserts without pulling in the toast UI.
ns.NotificationPresentation = {}
ns.NotificationToastFx = {}
ns.NotificationToastChrome = {}
ns.NotificationChangelog = {}
ns.CHANGELOG = {}
ns.NotificationAlertStack = {}
ns.CollectionNotify = {}
ns.DebugPrint = function() end

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
LoadFile("Modules/NotificationManager.lua")

local failures = 0
local function check(cond, msg)
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

local function setChoice(key, volume)
    WN.db.profile.notifications.collectibleSound = key
    WN.db.profile.notifications.collectibleSoundVolume = volume
end

local function resetPlays(willPlay)
    for i = #plays, 1, -1 do plays[i] = nil end
    fileWillPlay = willPlay ~= false
end

local function describe(p)
    if not p then return "nothing" end
    return ("%s(%s, %s)"):format(p.api, tostring(p.value), tostring(p.channel))
end

print("constants")
check(ns.Constants.NOTIFICATION_SOUND_ACHIEVEMENT_FILE == ACHIEVEMENT_FDID,
      "NOTIFICATION_SOUND_ACHIEVEMENT_FILE is 569143")
check(ns.L["COLLECTIBLE_SOUND_CELEBRATION"] == "Achievement (default)",
      "'celebration' is still the option labelled Achievement")

print("resolve: the Achievement option")
for _, key in ipairs({ "celebration", false }) do
    setChoice(key or nil)
    local kind, value = ns.ResolveCollectibleSound()
    local label = key and "'celebration'" or "unset (fresh profile)"
    check(kind == "file" and value == ACHIEVEMENT_FDID,
          ("%s resolves to file 569143 (got %s %s)"):format(label, tostring(kind), tostring(value)))
    check(value ~= EPICLOOT_KIT, label .. " no longer resolves to the loot toast kit")
end

print("resolve: every other option keeps its cue")
local expected = {
    { "compact",       "kit",  COMPACT_KIT },
    { "progress",      "kit",  PROGRESS_KIT },
    { "questComplete", "kit",  QUEST_KIT },
    { "none",          "none", nil },
    { "wnTriumph",     "file", WN_PATH .. "wn-triumph.ogg" },
    { "wnCoin",        "file", WN_PATH .. "wn-coin.ogg" },
}
for _, row in ipairs(expected) do
    setChoice(row[1], 100)
    local kind, value = ns.ResolveCollectibleSound()
    check(kind == row[2] and value == row[3],
          ("'%s' -> %s %s (got %s %s)"):format(row[1], row[2], tostring(row[3]),
                                                tostring(kind), tostring(value)))
end
setChoice("wnTriumph", 45)
local _, quiet = ns.ResolveCollectibleSound()
check(quiet == WN_PATH .. "wn-triumph-45.ogg", "shipped cue follows the volume setting (45%)")
setChoice("celebration", 45)
local _, achQuiet = ns.ResolveCollectibleSound()
check(achQuiet == ACHIEVEMENT_FDID, "volume setting does not rewrite the achievement fileDataID")

print("toast playback")
setChoice("celebration", 100)
resetPlays(true)
local _, file = ns.ResolveCollectibleSound()
ns.PlayNotificationCue({ soundFile = file }, COMPACT_KIT)
check(#plays == 1 and plays[1].api == "file" and plays[1].value == ACHIEVEMENT_FDID
      and plays[1].channel == "SFX",
      "toast plays PlaySoundFile(569143, 'SFX') and nothing else (got " .. describe(plays[1]) .. ")")

print("preview (settings play button)")
resetPlays(true)
ns.PreviewCollectibleSoundKey("celebration")
check(#plays == 1 and plays[1].api == "file" and plays[1].value == ACHIEVEMENT_FDID,
      "preview of 'celebration' plays the achievement file (got " .. describe(plays[1]) .. ")")
resetPlays(true)
ns.PreviewCollectibleSoundKey("compact")
check(#plays == 1 and plays[1].api == "kit" and plays[1].value == COMPACT_KIT,
      "preview of 'compact' still plays its kit (got " .. describe(plays[1]) .. ")")
resetPlays(true)
ns.PreviewCollectibleSoundKey("none")
check(#plays == 0, "preview of 'none' plays nothing")

print("fallback when the file will not play (muted channel / missing file)")
-- Never silent: a file that will not play falls through to a kit. The toast uses its lane default,
-- the preview the loot toast kit; both stay audible when only the file is missing.
resetPlays(false)
ns.PlayNotificationCue({ soundFile = ACHIEVEMENT_FDID }, COMPACT_KIT)
check(plays[#plays] and plays[#plays].api == "kit" and plays[#plays].value == COMPACT_KIT,
      "toast falls back to its default kit (got " .. describe(plays[#plays]) .. ")")
resetPlays(false)
ns.PreviewCollectibleSoundKey("celebration")
check(plays[#plays] and plays[#plays].api == "kit" and plays[#plays].value == EPICLOOT_KIT,
      "preview falls back to the loot toast kit (got " .. describe(plays[#plays]) .. ")")

if failures > 0 then
    io.stderr:write(("\ntest_collectible_sound_cue: %d failure(s)\n"):format(failures))
    os.exit(1)
end
print("\ntest_collectible_sound_cue: all checks passed")
