#!/usr/bin/env lua
--[[
    Regression test: removed or deprecated WoW globals are never called unguarded.

    These globals were removed (or only survive as Blizzard_Deprecated shims, which are skipped when
    the loadDeprecationFallbacks CVar is off). An unguarded call raises "attempt to call a nil value".
    Sources: Ketho/BlizzardInterfaceResources 12.1.5 GlobalAPI dump, Gethe/wow-ui-source live
    Blizzard_Deprecated*, warcraft.wiki.gg API pages (wiki.gg offline 2026-10-21; via Ketho Wiki.lua).
    A call counts as guarded when its own line or one of the 3 lines above feature-detects the name
    (`X and X(`, `if X then`, `type(X) == "function"`, `= C_Foo.Bar or X`).
]]

local ROOT = os.getenv("WN_ROOT") or "."

local DEPRECATED = {
    SendChatMessage = "C_ChatInfo.SendChatMessage",
    GetFactionInfo = "C_Reputation.GetFactionDataByIndex",
    GetNumFactions = "C_Reputation.GetNumFactions",
    GetSpellTexture = "C_Spell.GetSpellTexture",
    GetItemSpell = "C_Item.GetItemSpell",
    GetAddOnMetadata = "C_AddOns.GetAddOnMetadata",
    UseContainerItem = "C_Container.UseContainerItem",
    AddTrackedAchievement = "C_ContentTracking.StartTracking",
    RemoveTrackedAchievement = "C_ContentTracking.StopTracking",
    GetTrackedAchievements = "C_ContentTracking.GetTrackedIDs",
    IsSpellKnown = "C_SpellBook.IsSpellKnown",
    IsPlayerSpell = "C_SpellBook.IsSpellInSpellBook",
    GetNumSpecializationsForClassID = "C_SpecializationInfo.GetNumSpecializationsForClassID",
}

local function listFiles()
    local out = {}
    local p = io.popen('find "' .. ROOT .. '/Modules" "' .. ROOT .. '/Core.lua" -name "*.lua" 2>/dev/null')
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local function guarded(lines, ln, name)
    for i = math.max(1, ln - 3), ln do
        local l = lines[i]
        if l:find("%f[%w_]" .. name .. "%s+and%f[^%w_]")
            or l:find("if%s+[^\n]*%f[%w_]" .. name .. "%f[^%w_][^\n]*then")
            or l:find("type%(%s*" .. name .. "%s*%)")
            or l:find("or%s+" .. name .. "%f[^%w_]") then
            return true
        end
    end
    return false
end

local checked, failures = 0, {}
for _, path in ipairs(listFiles()) do
    local fh = io.open(path, "rb")
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("(%-%-%[(=*)%[.-%]%2%])", function(c) return (c:gsub("[^\n]", "")) end)
    src = src:gsub("%-%-[^\n]*", "")
    src = src:gsub('"[^"\n]*"', '""')
    local lines = {}
    for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    local relPath = path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", "")
    for ln = 1, #lines do
        local l = lines[ln]
        for name, replacement in pairs(DEPRECATED) do
            -- A bare global call: not a method / field (`x.Name(`, `x:Name(`) and not a local definition.
            for pre in l:gmatch("([%.:%w_]?)%f[%w_]" .. name .. "%s*%(") do
                if pre ~= "." and pre ~= ":" and not l:find("function%s+[%w_%.:]*" .. name) then
                    checked = checked + 1
                    if not guarded(lines, ln, name) then
                        failures[#failures + 1] = string.format("%s:%d  unguarded call to removed/deprecated %s (use %s)",
                            relPath, ln, name, replacement)
                    end
                end
            end
        end
    end
end

for i = 1, #failures do print("  FAIL " .. failures[i]) end
print(string.format("\nTotal Checks: %d | Failures: %d", checked, #failures))
if #failures > 0 then
    error("Deprecated API call suite failed with " .. #failures .. " failure(s).")
end
print("Deprecated API call suite: ALL TESTS PASSED.")
