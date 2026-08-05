#!/usr/bin/env lua
-- Regression probes for secret-blinded bag scans (ItemsCache + Collection baseline).
-- Run: /tmp/lua5.1 .github/scripts/test_secret_bag_scan_guards.lua

local failures = 0
local function expect(cond, msg)
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

----------------------------------------------------------------
-- 1) ItemsCache-style hash: secrets must not look like "bag emptied"
----------------------------------------------------------------
local function isSecret(v)
    return type(v) == "table" and v.__secret == true
end

local function GenerateItemHash(slots)
    local items, n, hadSecret = {}, 0, false
    for i = 1, #slots do
        local itemInfo = slots[i]
        if itemInfo then
            local id, hl = itemInfo.itemID, itemInfo.hyperlink
            if isSecret(id) or isSecret(hl) then
                hadSecret = true
            elseif hl then
                n = n + 1
                items[n] = tostring(hl) .. ":" .. tostring(itemInfo.stackCount or 1)
            end
        end
    end
    return table.concat(items, "|"), hadSecret
end

local function HasBagChanged(oldHash, slots)
    local newHash, hadSecret = GenerateItemHash(slots)
    if hadSecret then
        return false, oldHash -- keep last good hash
    end
    if newHash ~= oldHash then
        return true, newHash
    end
    return false, oldHash
end

local secretHL = setmetatable({}, { __index = { __secret = true } })
local goodHash = "item:123:1|item:456:1"
local changed, nextHash = HasBagChanged(goodHash, {
    { itemID = 1, hyperlink = secretHL, stackCount = 1 },
    { itemID = 2, hyperlink = secretHL, stackCount = 1 },
})
expect(changed == false, "secret bag must not report HasBagChanged")
expect(nextHash == goodHash, "secret bag must preserve last good hash")

changed, nextHash = HasBagChanged(goodHash, {
    { itemID = 123, hyperlink = "item:123", stackCount = 1 },
    { itemID = 456, hyperlink = "item:456", stackCount = 1 },
})
expect(changed == false, "unchanged readable bag should not report change")
expect(nextHash == goodHash, "unchanged readable bag keeps hash")

changed, nextHash = HasBagChanged(goodHash, {
    { itemID = 999, hyperlink = "item:999", stackCount = 1 },
})
expect(changed == true, "readable composition change must report change")
expect(nextHash == "item:999:1", "readable composition change updates hash")

-- Pre-fix (broken) behavior: treating secrets as absent empties the hash and looks like a wipe.
local brokenHash, _ = GenerateItemHash({
    { itemID = 1, hyperlink = secretHL, stackCount = 1 },
    { itemID = 2, hyperlink = secretHL, stackCount = 1 },
})
expect(brokenHash == "", "secret-skipped hash is empty (documents the wipe signal)")
expect(brokenHash ~= goodHash, "empty secret hash differs from last good inventory hash")

----------------------------------------------------------------
-- 2) Collection baseline: secret slots must keep previous itemIDs
----------------------------------------------------------------
local function PreserveSecretOccupiedPreviousSlots(previous, current, bagID, liveSlots)
    for slotKey, prevID in pairs(previous) do
        if current[slotKey] == nil then
            local b = tonumber(slotKey:match("^(%d+)"))
            local slotID = tonumber(slotKey:match("_(%d+)$"))
            if b == bagID and slotID and liveSlots[slotID] then
                local info = liveSlots[slotID]
                if isSecret(info.itemID) or isSecret(info.hyperlink) then
                    current[slotKey] = prevID
                end
            end
        end
    end
end

local previous = { ["0_1"] = 186642, ["0_2"] = 70000 }
local current = {} -- secret scan omitted both slots (ItemsCache snapshot behavior)
PreserveSecretOccupiedPreviousSlots(previous, current, 0, {
    [1] = { itemID = setmetatable({}, { __index = { __secret = true } }) },
    [2] = { itemID = setmetatable({}, { __index = { __secret = true } }) },
})
expect(current["0_1"] == 186642, "secret slot 0_1 preserves previous collectible itemID")
expect(current["0_2"] == 70000, "secret slot 0_2 preserves previous itemID")

-- Truly empty slot must not be preserved (item removed while secret).
current = {}
PreserveSecretOccupiedPreviousSlots(previous, current, 0, {
    [1] = { itemID = setmetatable({}, { __index = { __secret = true } }) },
    -- slot 2 empty
})
expect(current["0_1"] == 186642, "still-occupied secret slot preserved")
expect(current["0_2"] == nil, "emptied slot must drop from baseline")

-- Init deferral: secrets present => do not finalize empty baseline
local function ShouldDeferBaselineInit(slots)
    for i = 1, #slots do
        local info = slots[i]
        if info and (isSecret(info.itemID) or isSecret(info.hyperlink)) then
            return true
        end
    end
    return false
end
expect(ShouldDeferBaselineInit({ { itemID = secretHL } }) == true, "init defers when secrets present")
expect(ShouldDeferBaselineInit({ { itemID = 123 } }) == false, "init proceeds when readable")

if failures > 0 then
    io.stderr:write(string.format("%d probe(s) failed\n", failures))
    os.exit(1)
end
print("OK: secret bag scan guards")
