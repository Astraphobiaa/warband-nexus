--[[
    Character roster row: optional columns collapse cleanly, and retail is untouched.

    Three columns only exist where their system does -- Keystone (Mythic+), Skills (spells bought
    from a trainer) and Talents (the Forever talent tree). Each is meant to collapse to zero width
    on a client without it, with the chained offsets closing the gap; and the widths a retail
    client computes must be exactly what they were before those columns were added.

    This loads the real Modules/UI/SharedWidgets_CharRow.lua under the WoW stub and drives
    ns.UI_ComputeCharRowFlexColumns for both clients, so the arithmetic is measured rather than
    reasoned about. It also covers the shrink path, which is where a collapsed column can quietly
    come back: the flex loop writes a width for every flex key, and a disabled one must not be
    handed any.
]]

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

local failures = 0
local checks = 0
local function check(cond, label)
    checks = checks + 1
    if cond then
        print("  ok   " .. label)
    else
        failures = failures + 1
        print("  FAIL " .. label)
    end
end
local function eq(actual, expected, label)
    check(actual == expected, string.format("%s: expected %s, got %s",
        label, tostring(expected), tostring(actual)))
end

local function read(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return src
end

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end

--- Load SharedWidgets_CharRow with a namespace whose SupportsFeature answers for one client.
local function LoadForClient(caps)
    local ns = {
        WarbandNexus = {
            SupportsFeature = function(_, key)
                if caps[key] == nil then return true end
                return caps[key]
            end,
        },
        L = setmetatable({}, { __index = function(_, k) return k end }),
        UI_COLORS = { accent = { 1, 1, 1 } },
        UI_SPACING = {},
    }
    -- The module reaches for shared widget helpers that live in sibling files; a permissive
    -- metatable keeps this test about the width math rather than about load order.
    setmetatable(ns, { __index = function() return nil end })
    local chunk, err = loadstring(ReadFile("Modules/UI/SharedWidgets_CharRow.lua"), "@CharRow")
    if not chunk then error("load CharRow: " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run CharRow: " .. tostring(rerr), 0) end
    return ns
end

local RETAIL = { mythicPlus = true, trainedSpells = false, classicTalentTree = false,
    averageItemLevel = true, realmTypeTag = false }
local FOREVER = { mythicPlus = false, trainedSpells = true, classicTalentTree = true,
    averageItemLevel = false, realmTypeTag = true }

print("Phase 1: retail keeps every column it had")
do
    local ns = LoadForClient(RETAIL)
    local cols = ns.UI_CHAR_ROW_COLUMNS
    check(cols ~= nil, "UI_CHAR_ROW_COLUMNS exported")
    check(cols.skills ~= nil and cols.talents ~= nil, "skills / talents column defs exist")
    local flex = ns.UI_ComputeCharRowFlexColumns and ns.UI_ComputeCharRowFlexColumns(4000, 130)
    check(flex ~= nil, "flex widths resolve at a wide row")
    if flex then
        eq(flex.mythicKey, cols.mythicKey.width, "retail: keystone keeps its width")
        eq(flex.itemLevel, cols.itemLevel.width, "retail: item level keeps its width")
        eq(flex.skills, 0, "retail: skills column collapses")
        eq(flex.talents, 0, "retail: talents column collapses")
        eq(flex.realmType, 0, "retail: realm type column collapses")
        -- realmType sits BEFORE guild in the order, so a collapsed one must not push the
        -- columns after it to the right.
        eq(ns.UI_CharRowGetColumnOffset and ns.UI_CharRowGetColumnOffset("guild") or nil,
            nil, "offset helper stays internal")
    end
end

print("Phase 2: Forever collapses what it has no system for")
do
    local ns = LoadForClient(FOREVER)
    local cols = ns.UI_CHAR_ROW_COLUMNS
    local flex = ns.UI_ComputeCharRowFlexColumns and ns.UI_ComputeCharRowFlexColumns(4000, 130)
    if flex then
        eq(flex.mythicKey, 0, "forever: keystone collapses")
        eq(flex.skills, cols.skills.width, "forever: skills column present")
        -- The glyph is the same 39 px square the profession icons use; neither column may be
        -- narrower than it, at any row width, or the icon overlaps its neighbour.
        check(cols.skills.width >= 39 and cols.talents.width >= 39,
            "icon columns fit the 39px glyph")
        check(cols.skills.min >= 39 and cols.talents.min >= 39,
            "icon columns never shrink below the glyph")
        -- Skills sits one profession-strip gap from Talents, not a full column gap.
        eq(cols.skills.spacing, 5, "skills to talents gap matches the profession strip")
        eq(flex.talents, cols.talents.width, "forever: talents column present")
        -- Item level is NOT gated: GetAverageItemLevel misreports there, but Utilities computes
        -- the average from the equipped pieces instead, so the column stays.
        eq(flex.itemLevel, cols.itemLevel.width, "forever: item level column stays")
        eq(flex.realmType, cols.realmType.width, "forever: realm type column present")
    end
end

print("Phase 3: a collapsed column stays collapsed when the row has to shrink")
do
    -- A narrow row forces the flex pool to give width back. The loop writes a width for every
    -- flex key, so without an explicit guard a disabled column reappears here.
    for _, case in ipairs({
        { name = "retail", caps = RETAIL, zero = { "skills", "talents", "realmType" } },
        { name = "forever", caps = FOREVER, zero = { "mythicKey" } },
    }) do
        local ns = LoadForClient(case.caps)
        for _, rowW in ipairs({ 1200, 900, 700, 500, 320 }) do
            local flex = ns.UI_ComputeCharRowFlexColumns(rowW, 130)
            for _, key in ipairs(case.zero) do
                check(flex[key] == 0, string.format("%s @ %dpx: %s stays 0 (got %s)",
                    case.name, rowW, key, tostring(flex[key])))
            end
        end
    end
end

print("Phase 4: the profession strip fits its column at every count")
do
    -- Mirrors ProfIconSize in CharactersUI_Row: the paint and the resize relayout both size the
    -- squares from it, and they disagreed once -- one hardcoded 39 while the other shrank, so
    -- four professions were spaced for the big square and drawn at the small one, overlapping.
    local MAX, MIN, GAP = 39, 22, 5
    local function ProfIconSize(columnW, count)
        if not count or count < 1 then return MAX end
        local fit = math.floor((columnW - (count - 1) * GAP) / count)
        if fit >= MAX then return MAX end
        return math.max(MIN, fit)
    end
    local ns = LoadForClient(FOREVER)
    -- On this client the strip is five fixed slots, so the column is sized from the helper the
    -- row uses rather than from the static table.
    local columnW = ns.UI_CharRowProfessionColumnWidth and ns.UI_CharRowProfessionColumnWidth()
        or ns.UI_CHAR_ROW_COLUMNS.professions.width
    check(columnW >= 5 * 39 + 4 * 5, "five full-size slots fit the column: " .. tostring(columnW))
    for count = 1, 5 do
        local size = ProfIconSize(columnW, count)
        local used = count * size + (count - 1) * GAP
        check(used <= columnW, string.format("%d icon(s) at %dpx use %d of %d",
            count, size, used, columnW))
        check(size <= MAX, string.format("%d icon(s): never larger than the base square", count))
    end
    -- Four is the common Forever case: two primaries beside three secondaries would be five.
    check(ProfIconSize(columnW, 5) == MAX, "all five slots keep the full square")

    -- The slot order is a contract with the player: first primary, second primary, then the
    -- three vanilla secondaries in a fixed sequence. Read it out of the shipped source rather
    -- than restating it, so a reorder there fails here.
    local src = read("Modules/UI/CharactersUI_Row.lua")
    local block = src:match("local PROF_SLOT_ORDER = (%b{})")
    check(block ~= nil, "PROF_SLOT_ORDER found in the row source")
    if block then
        local keys = {}
        for key in block:gmatch("key = ([^,]+)") do keys[#keys + 1] = key end
        eq(#keys, 5, "exactly five slots")
        eq(keys[1], "1", "slot 1 is the first primary")
        eq(keys[2], "2", "slot 2 is the second primary")
        eq(keys[3], '"firstAid"', "slot 3 is First Aid")
        eq(keys[4], '"fishing"', "slot 4 is Fishing")
        eq(keys[5], '"cooking"', "slot 5 is Cooking")
    end
end


print(string.format("\nTotal: %d checks, %d failed", checks, failures))
if failures > 0 then
    error("char row optional column suite failed with " .. failures .. " failure(s).", 0)
end
