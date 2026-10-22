#!/usr/bin/env lua
--[[
    Regression test: locale values cannot crash string.format, and no key is defined twice.

    2026-10-22 audit:
      - koKR VAULT_BASED_ON_FORMAT had "%s ... %d" while the caller passes (number, text): the M+
        vault tooltip errored on Korean clients.
      - KEYSTONE_RATING_BOOST / CASCADE_SAVINGS_BANNER had swapped specifiers in several locales.
      - Every locale defined ~112 keys twice (the later definition silently won).
      - PvEUI_VaultGrid passed VAULT_DEAD_RUN_DESC ("... 0% vault ...") to string.format as the
        format string, and PlansTrackerWindow passed two args to the three-%s
        SOURCE_ACHIEVEMENT_FORMAT: both errored at runtime.

    Checks:
      1. no L["KEY"] assignment appears twice in one locale file;
      2. for every key whose enUS value has format specifiers, every locale has the same
         specifier sequence (a locale missing the key falls back to enUS and is fine);
      3. the two call sites above stay fixed.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return src
end

-- Locale files listed in the TOC (same set the game loads).
local locales = {}
for line in ReadFile("WarbandNexus.toc"):gmatch("[^\r\n]+") do
    local name = line:match("^Locales[/\\](%w+)%.lua%s*$")
    if name then locales[#locales + 1] = name end
end
check(#locales >= 10, "TOC lists the locale files (" .. #locales .. ")")

-- 1. Duplicate definitions.
for _, loc in ipairs(locales) do
    local seen, dups = {}, {}
    for key in ReadFile("Locales/" .. loc .. ".lua"):gmatch('\nL%["([%w_]+)"%]%s*=') do
        if seen[key] then dups[#dups + 1] = key end
        seen[key] = true
    end
    check(#dups == 0, loc .. ": keys defined twice: " .. table.concat(dups, ", ", 1, math.min(#dups, 8)))
end

-- 2. Specifier sequences. Load each locale with WoW GlobalStrings stubbed to sentinel strings.
local function LoadLocale(loc)
    local ns = { LOCALES = {} }
    local env = setmetatable({}, { __index = function(_, k)
        if _G[k] ~= nil then return _G[k] end
        if type(k) == "string" and k:match("^[A-Z][A-Z0-9_]+$") then return "G:" .. k end
    end })
    local chunk = assert(loadstring(ReadFile("Locales/" .. loc .. ".lua"), "@Locales/" .. loc .. ".lua"))
    setfenv(chunk, env)
    chunk("WarbandNexus", ns)
    return ns.LOCALES[loc] or {}
end

-- Specifiers string.format consumes; no space flag, so prose like "100% done" is not one.
local function Specs(v)
    if type(v) ~= "string" then return "" end
    local out = {}
    local s = v:gsub("%%%%", "")
    for spec in s:gmatch("%%[%-+#0]?%d*%.?%d*([sdifgxXcq])") do
        out[#out + 1] = (spec == "i") and "d" or spec
    end
    return table.concat(out)
end

local base = LoadLocale("enUS")
local mismatches = 0
for _, loc in ipairs(locales) do
    if loc ~= "enUS" then
        local t = LoadLocale(loc)
        for key, enValue in pairs(base) do
            local want = Specs(enValue)
            if want ~= "" and t[key] ~= nil and rawget(t, key) ~= nil then
                local got = Specs(t[key])
                if got ~= want then
                    mismatches = mismatches + 1
                    check(false, string.format("%s %s: specifiers %q, enUS %q", loc, key, got, want))
                end
            end
        end
    end
end
check(mismatches == 0, "all locales match enUS format specifiers")

-- 3. The two runtime call sites.
local grid = ReadFile("Modules/UI/PvEUI_VaultGrid.lua")
check(not grid:find('string.format("|cffaaaaaa" .. floorDesc', 1, true), "VAULT_DEAD_RUN_DESC is not used as a format string")
local tracker = ReadFile("Modules/UI/PlansTrackerWindow.lua")
local call = tracker:match("format%(srcFmt,([^\n]+)%)")
local _, commas = (call or ""):gsub(",", "")
check(call ~= nil and commas == 2, "SOURCE_ACHIEVEMENT_FORMAT gets three arguments")
local srcFmt = base["SOURCE_ACHIEVEMENT_FORMAT"]
check(pcall(string.format, srcFmt, "Source:", "Achievement", "123"), "SOURCE_ACHIEVEMENT_FORMAT formats with three arguments")
check(pcall(string.format, LoadLocale("koKR")["VAULT_BASED_ON_FORMAT"], 8, "+10"), "koKR VAULT_BASED_ON_FORMAT formats with (number, text)")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Locale format safety suite failed with " .. failed .. " failure(s).")
end
print("Locale format safety suite: ALL TESTS PASSED.")
