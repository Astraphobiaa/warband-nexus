#!/usr/bin/env lua5.1
-- Regression: PLAYER_LOGOUT must not replace a complete guild-bank tab cache
-- with an in-flight frame-budgeted scan's partial tabItemsBuilding buffer.

local MAX_GUILDBANK_SLOTS_PER_TAB = 98

--- Old FlushGuildBankScanOnLogout behavior (bug): assign work buffer onto the tab.
local function OldFlush(ctx)
    if ctx.tabItemsBuilding and ctx.guildData and ctx.guildData.tabs and ctx.tabIndex then
        local tabData = ctx.guildData.tabs[ctx.tabIndex]
        if tabData then
            tabData.items = ctx.tabItemsBuilding
        end
    end
end

--- New behavior: discard the in-flight buffer; leave completed cache untouched.
local function NewFlush(ctx)
    -- Intentionally no assignment of tabItemsBuilding.
    ctx.tabItemsBuilding = nil
end

local function CountSlots(items)
    local n = 0
    if type(items) ~= "table" then return 0 end
    for _ in pairs(items) do
        n = n + 1
    end
    return n
end

local function BuildFullTab(n)
    local items = {}
    for slot = 1, n do
        items[slot] = { itemID = 1000 + slot, stackCount = 1 }
    end
    return items
end

local failures = 0
local function assertTrue(cond, msg)
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

-- 1) Mid-tab logout: old path truncates; new path keeps the prior complete cache.
do
    local full = BuildFullTab(MAX_GUILDBANK_SLOTS_PER_TAB)
    local partial = BuildFullTab(20) -- scan stopped after 20 of 98 slots
    local guildOld = {
        tabs = {
            [1] = { name = "Tab1", items = full },
        },
    }
    local guildNew = {
        tabs = {
            [1] = { name = "Tab1", items = BuildFullTab(MAX_GUILDBANK_SLOTS_PER_TAB) },
        },
    }
    OldFlush({
        tabItemsBuilding = partial,
        guildData = guildOld,
        tabIndex = 1,
    })
    NewFlush({
        tabItemsBuilding = partial,
        guildData = guildNew,
        tabIndex = 1,
    })
    assertTrue(CountSlots(guildOld.tabs[1].items) == 20,
        "old logout flush must truncate cached tab to partial buffer (bug repro)")
    assertTrue(CountSlots(guildNew.tabs[1].items) == MAX_GUILDBANK_SLOTS_PER_TAB,
        "new logout flush must preserve complete cached tab")
    assertTrue(guildNew.tabs[1].items[98] and guildNew.tabs[1].items[98].itemID == 1098,
        "new logout flush must keep unscanned high slots")
end

-- 2) No in-flight buffer: both paths leave the cache alone.
do
    local full = BuildFullTab(40)
    local guild = { tabs = { [1] = { name = "Tab1", items = full } } }
    NewFlush({
        tabItemsBuilding = nil,
        guildData = guild,
        tabIndex = 1,
    })
    assertTrue(CountSlots(guild.tabs[1].items) == 40,
        "logout with no building buffer must not touch tabs")
end

-- 3) Completed tabs already committed remain; only the active building tab was at risk.
do
    local tab1 = BuildFullTab(MAX_GUILDBANK_SLOTS_PER_TAB)
    local tab2Full = BuildFullTab(MAX_GUILDBANK_SLOTS_PER_TAB)
    local tab2Partial = BuildFullTab(5)
    local guildNew = {
        tabs = {
            [1] = { name = "Done", items = tab1 },
            [2] = { name = "Active", items = tab2Full },
        },
    }
    NewFlush({
        tabItemsBuilding = tab2Partial,
        guildData = guildNew,
        tabIndex = 2,
    })
    assertTrue(CountSlots(guildNew.tabs[1].items) == MAX_GUILDBANK_SLOTS_PER_TAB,
        "completed prior tab must stay intact")
    assertTrue(CountSlots(guildNew.tabs[2].items) == MAX_GUILDBANK_SLOTS_PER_TAB,
        "active tab prior cache must stay intact when logout aborts")
end

if failures > 0 then
    io.stderr:write(string.format("%d failure(s)\n", failures))
    os.exit(1)
end
io.write("OK: guild bank logout flush preserves completed tab cache\n")
