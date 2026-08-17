#!/usr/bin/env lua5.1
--[[
    The in-game What's New popup resolves its text as
    CHANGELOG_V<x><y><z> derived from ADDON_VERSION (Modules/NotificationManager_Changelog.lua).

    preflight_release.py already checks that the key exists as TEXT in all 12 locale files. What it
    cannot check is that the key actually RESOLVES at runtime for the current version -- which is the
    part that decides whether players see release notes or the "See Locales for CHANGELOG_V key"
    fallback. A version with a -beta suffix makes that derivation non-obvious, so it is asserted here.

    Also guards the two documented shipping traps: a stale previous key left behind in the locale
    tables, and a missing CurseForge footer line.
]]

local H = dofile(".github/scripts/wow_addon_harness.lua")
local ns = H.ns

local failures = 0
local function check(cond, msg)
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

local version = ns.Constants and ns.Constants.ADDON_VERSION
check(type(version) == "string" and version ~= "", "ADDON_VERSION is set: " .. tostring(version))

-- Same derivation as NotificationManager_Changelog.VersionToChangelogKey: numeric triple only,
-- so suffixes like -beta1 map onto the plain x.y.z key.
local a, b, c = tostring(version):match("^(%d+)%.(%d+)%.(%d+)")
local key = a and ("CHANGELOG_V" .. a .. b .. c) or nil
check(key ~= nil, "version yields a changelog key: " .. tostring(key))

local text = key and ns.L and ns.L[key]
check(type(text) == "string" and text ~= "",
      ("%s resolves to text at runtime (not the fallback)"):format(tostring(key)))

if type(text) == "string" then
    check(text:find("CurseForge: Warband Nexus", 1, true) ~= nil,
          "changelog text keeps the CurseForge footer line")
    local numeric = a .. "." .. b .. "." .. c
    check(text:find(numeric, 1, true) ~= nil,
          ("changelog text names the version (%s)"):format(numeric))
end

-- Exactly one changelog key may be live: old ones are dead weight shipped to every player.
local live = {}
for k in pairs(ns.L or {}) do
    if type(k) == "string" and k:match("^CHANGELOG_V%d+$") then live[#live + 1] = k end
end
table.sort(live)
check(#live == 1, ("exactly one CHANGELOG_V* key is present (found %d: %s)")
    :format(#live, table.concat(live, ", ")))
check(live[1] == key, ("the only key present is the current one (%s)"):format(tostring(key)))

if failures > 0 then
    io.stderr:write(("\ntest_release_changelog: %d failure(s)\n"):format(failures))
    os.exit(1)
end
print("\ntest_release_changelog: all checks passed")
