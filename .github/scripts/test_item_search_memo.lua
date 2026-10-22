#!/usr/bin/env lua
--[[
    Regression test: item search matching gives the same results as before at a fraction of the cost.

    With a search active, the Storage tree pre-scan and the Items flat list lowered each item's name AND
    whole hyperlink on every redraw (3-8k items), and ITEM_METADATA_READY repeats the redraw with the same
    text. WarbandNexus:_StorageLeafItemMatchesSearch (Modules/UI/ItemsUI.lua) is now the single matcher:
    lowered names are kept for the session, a hyperlink is lowered only when the name misses, and its hit
    is kept until the search text changes.

    The matcher is extracted from the shipped file and compared against the previous inline logic
    (copied below as the reference) on a fixture; lower() calls are counted through string.lower.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local passed, failed = 0, 0
local function check(cond, msg, detail)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg .. (detail and (": " .. tostring(detail)) or "")) end
end

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    return src
end

-- Count every s:lower() (string methods resolve through the `string` table).
local lowerCalls = 0
local realLower = string.lower
string.lower = function(s) lowerCalls = lowerCalls + 1; return realLower(s) end

local function issecretvalue(v) return type(v) == "table" and v.__secret == true end
local function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

-- Reference: the matching expression used before (StorageDraw ItemMatchesSearch / flat list / leaf).
local function ReferenceMatch(item, q)
    local itemName = SafeLower(item.name)
    local linkStr = item.itemLink or item.link
    local itemLink = SafeLower(linkStr)
    return itemName:find(q, 1, true) or itemLink:find(q, 1, true)
end

local src = ReadFile("Modules/UI/ItemsUI.lua")
local s = src:find("local itemSearchMemo", 1, true)
    or src:find("function WarbandNexus:_StorageLeafItemMatchesSearch", 1, true)
local fnAt = src:find("function WarbandNexus:_StorageLeafItemMatchesSearch", 1, true)
local e = fnAt and src:find("\nend\n", fnAt, true)
assert(s and e, "_StorageLeafItemMatchesSearch not found in ItemsUI.lua")
local chunk = assert(loadstring("local WarbandNexus, issecretvalue, wipe, SafeLower = ...\n" .. src:sub(s, e + 4),
    "@ItemsUI_matcher"))
local WN = {}
chunk(WN, issecretvalue, wipe, SafeLower)
local function Match(item, q) return WN:_StorageLeafItemMatchesSearch(item, q) end

local function Link(id, name, color)
    return "|c" .. (color or "ffa335ee") .. "|Hitem:" .. id .. "::::::::80:::::|h[" .. name .. "]|h|r"
end
local secret = setmetatable({}, { __index = { __secret = true } })
local items = {
    { name = "Storm Sword", itemLink = Link(123456, "Storm Sword") },
    { name = "Healing Potion", itemLink = Link(191380, "Healing Potion", "ffffffff") },
    { name = "Swordfish Fillet", link = Link(200, "Swordfish Fillet") },
    { name = nil, itemLink = Link(77, "Unloaded Item") },
    { name = "", itemLink = Link(78, "Empty Name") },
    { name = "No Link Gem" },
    { name = "Secret Link", itemLink = secret },
    { name = "Keystone", itemLink = "|cffa335ee|Hkeystone:180653:2:15|h[Keystone: Halls]|h|r" },
    { name = "MIXED Case", itemLink = Link(4242, "MIXED Case") },
}
local queries = { "sword", "storm", "123", "4242", "item", "|h", "[", "cff", "keystone", "halls",
    "unloaded", "empty", "gem", "zzz", "mixed case", "80", ":" }

print("1. Same results as the previous matching on the fixture")
local mismatches = 0
for qi = 1, #queries do
    local q = queries[qi]
    for ii = 1, #items do
        local a, b = ReferenceMatch(items[ii], q), Match(items[ii], q)
        if (a and true or false) ~= (b and true or false) then
            mismatches = mismatches + 1
            print("    mismatch q=" .. q .. " item#" .. ii .. " ref=" .. tostring(a) .. " new=" .. tostring(b))
        end
    end
end
check(mismatches == 0, "every (query, item) pair matches the reference (" .. #queries * #items .. " pairs)", mismatches)
-- Second pass over the same pairs (memo warm, query switching back and forth) is still identical.
mismatches = 0
for qi = #queries, 1, -1 do
    for ii = 1, #items do
        local q = queries[qi]
        if (ReferenceMatch(items[ii], q) and true or false) ~= (Match(items[ii], q) and true or false) then
            mismatches = mismatches + 1
        end
    end
end
check(mismatches == 0, "warm memo, queries revisited in reverse: still identical", mismatches)

local late = { name = nil, itemLink = Link(9, "Late Name") }
local before = Match(late, "late") and true or false
late.name = "Late Name"
check(before == true and (Match(late, "late") and true or false) == true, "name resolved later: still matched")
local renamed = { name = "Alpha", itemLink = Link(10, "Alpha") }
check(not Match(renamed, "beta"), "unrelated query misses")
renamed.name, renamed.itemLink = "Beta", Link(10, "Beta")
check(Match(renamed, "beta") and true or false, "same row with a new name / link: re-evaluated, not stale")

print("2. Redraw with the same search text does not lower again")
local big = {}
for i = 1, 3000 do
    big[i] = { name = "Thing " .. i, itemLink = Link(100000 + i, "Thing " .. i) }
end
local function Redraw(q)
    local n = 0
    for i = 1, #big do if Match(big[i], q) then n = n + 1 end end
    return n
end
local firstHits = Redraw("thing 12")
lowerCalls = 0
local secondHits = Redraw("thing 12")
check(secondHits == firstHits and firstHits == 111, "redraw: same hit count", secondHits)
check(lowerCalls == 0, "redraw with the same text: no lower() calls (was 2 per item)", lowerCalls)
lowerCalls = 0
Redraw("100200")      -- itemID digits are only in the link
check(lowerCalls <= #big, "new text: at most one lower() per item (links of name misses only)", lowerCalls)

print("3. Storage tree and Items flat list use the shared matcher")
local draw = ReadFile("Modules/UI/ItemsUI_StorageDraw.lua")
local helper = draw:match("local function ItemMatchesSearch%(item%)(.-)\n    end\n")
check(helper and helper:find("_StorageLeafItemMatchesSearch", 1, true) ~= nil,
    "StorageDraw ItemMatchesSearch delegates to the shared matcher")
local flat = src:match("function WarbandNexus:BuildItemsVirtualFlatList%(.-\nend\n")
check(flat and flat:find("_StorageLeafItemMatchesSearch", 1, true) ~= nil and flat:find(":lower()", 1, true) == nil,
    "Items flat list filters through the shared matcher")

string.lower = realLower
print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Item search memo suite failed with " .. failed .. " failure(s).")
end
print("Item search memo suite: ALL TESTS PASSED.")
