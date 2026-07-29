#!/usr/bin/env lua5.1
-- Regression: TRANSMOG_COLLECTION_UPDATED live updates must key illusions by
-- sourceID (scanner / collectionStore id), not visualID (WeaponEnchantID).
-- Mirrors OnTransmogCollectionUpdated + RemoveFromUncollected keying.

local function BuildCollectedSet(illusions, preferSource)
    local currentCollected = {}
    for i = 1, #illusions do
        local info = illusions[i]
        if info and info.isCollected then
            local id
            if preferSource then
                id = info.sourceID or info.visualID
            else
                id = info.visualID
            end
            if id then
                currentCollected[id] = info
            end
        end
    end
    return currentCollected
end

-- Minimal RemoveFromUncollected: updates store[id], never remaps visual->source.
local function RemoveFromUncollected(store, uncollected, id)
    if uncollected[id] ~= nil then
        uncollected[id] = nil
    end
    if not store[id] then
        store[id] = { id = id, collected = true }
    else
        store[id].collected = true
    end
end

local function ApplyLiveUpdate(store, uncollected, prev, current)
    local newly = {}
    for id, info in pairs(current) do
        if not prev[id] then
            RemoveFromUncollected(store, uncollected, id)
            newly[#newly + 1] = { id = id, info = info }
        end
    end
    return newly
end

local failures = 0
local function assertTrue(cond, msg)
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

-- Distinct namespaces (wiki: visualID = WeaponEnchantID, sourceID separate).
local SOURCE_ID = 138164
local VISUAL_ID = 1728
local illusionsBefore = {
    { sourceID = SOURCE_ID, visualID = VISUAL_ID, isCollected = false, name = "Test Illusion" },
}
local illusionsAfter = {
    { sourceID = SOURCE_ID, visualID = VISUAL_ID, isCollected = true, name = "Test Illusion" },
}

-- Seed store/uncollected the way the scanner does (sourceID keys).
local store = {
    [SOURCE_ID] = { id = SOURCE_ID, name = "Test Illusion", collected = false, visualID = VISUAL_ID },
}
local uncollected = {
    [SOURCE_ID] = { name = "Test Illusion" },
}

-- 1) Bug repro: visualID keying leaves source row uncollected and creates a ghost.
do
    local storeBug = {
        [SOURCE_ID] = { id = SOURCE_ID, name = "Test Illusion", collected = false, visualID = VISUAL_ID },
    }
    local uncBug = { [SOURCE_ID] = { name = "Test Illusion" } }
    local prev = BuildCollectedSet(illusionsBefore, false)
    local cur = BuildCollectedSet(illusionsAfter, false)
    local newly = ApplyLiveUpdate(storeBug, uncBug, prev, cur)
    assertTrue(#newly == 1 and newly[1].id == VISUAL_ID, "bug path must emit visualID as live id")
    assertTrue(storeBug[SOURCE_ID].collected == false, "bug path leaves sourceID row uncollected")
    assertTrue(uncBug[SOURCE_ID] ~= nil, "bug path leaves sourceID in uncollected")
    assertTrue(storeBug[VISUAL_ID] ~= nil and storeBug[VISUAL_ID].collected == true,
        "bug path creates ghost visualID collected row")
end

-- 2) Fixed path: sourceID keying updates the real row and clears uncollected.
do
    local prev = BuildCollectedSet(illusionsBefore, true)
    local cur = BuildCollectedSet(illusionsAfter, true)
    -- Seed previous as already-seen empty collected set (first event seeds; second learns).
    -- Simulate prior state with nothing collected, then learn.
    prev = {}
    local newly = ApplyLiveUpdate(store, uncollected, prev, cur)
    assertTrue(#newly == 1 and newly[1].id == SOURCE_ID, "fixed path emits sourceID as live id")
    assertTrue(store[SOURCE_ID].collected == true, "fixed path marks sourceID collected")
    assertTrue(uncollected[SOURCE_ID] == nil, "fixed path clears sourceID from uncollected")
    assertTrue(store[VISUAL_ID] == nil, "fixed path must not create a visualID ghost row")
end

-- 3) Prefer sourceID when both present; fall back to visualID only if source missing.
do
    local onlyVisual = { { visualID = 99, isCollected = true, name = "Legacy" } }
    local set = BuildCollectedSet(onlyVisual, true)
    assertTrue(set[99] ~= nil, "fallback to visualID when sourceID absent")
    local both = { { sourceID = 1, visualID = 2, isCollected = true } }
    set = BuildCollectedSet(both, true)
    assertTrue(set[1] ~= nil and set[2] == nil, "prefer sourceID over visualID")
end

if failures > 0 then
    io.stderr:write(failures .. " assertion(s) failed\n")
    os.exit(1)
end
print("OK: illusion live-update keys (sourceID) — 3 suites passed")
