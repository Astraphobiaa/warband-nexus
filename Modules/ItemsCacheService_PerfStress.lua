--[[
    Warband Nexus - Items/bag/tooltip perf stress test (dev).
    Command: /wn bagdebug stress  (requires /wn debug)
    Optional trace: /wn profiler trace

    PERF AUDIT (2026-06) — remaining risks documented inline on each finding:
    | issue | severity | file | status |
    |-------|----------|------|--------|
    | SaveItemsCompressedImmediate re-invalidates summary after coalesced flush | medium | ItemsCacheService.lua | fixed: callers own pending; incremental path keeps ApplyBagDeltaToSummary |
    | DataService re-invalidates item summary on every WN_ITEMS_UPDATED | medium | DataService.lua | fixed: removed duplicate handlers |
    | BuildCharacterSummary calls GetItemsData (legacy merge + hydrate) | medium | ItemsCacheService.lua | fixed: AcquireV2BucketItemArray only |
    | compress_immediate stress row | info | ItemsCacheService_PerfStress.lua | worst-case: sync FlushPendingCompress(true); live bag moves mark session_dirty only |
    | deferred throttle N timers + N WN_ITEMS_UPDATED | medium | ItemsCacheService.lua | fixed: single ScheduleDeferredBagFlush |
    | compress spike 0.2s after loot | high | ItemsCacheService.lua | fixed: session-deferred persist (logout/leaving-world/90s idle) |
    | update_single_bag triple O(n) strip+merge+contentSig | high | ItemsCacheService.lua | fixed: merged strip into ReplaceBagInItemArray; contentSig deferred to flush |
    | stress BuildCharacterSummary inside update_single_bag timer | high | ItemsCacheService_PerfStress.lua | fixed: warm summary before timed block |
    | Collection bag scan duplicates C_Container walks parallel to ItemsCache BAG_UPDATE bucket | medium | CollectionService_Scan.lua | shares ItemsCacheBagSnapshots when fresh |
    | GetDetailedItemCountsFast coldInit marks full roster pending | medium | ItemsCacheService.lua | background drain; warm path skips sync roster rebuild |
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local debugprofilestop = debugprofilestop
local format = string.format
local issecretvalue = issecretvalue

local PS = {}
ns.ItemsCachePerfStress = PS

local BAG_ID = 0
local COL_WIDTH = 28
local DETAIL_WIDTH = 52

local function EmitTrace(line)
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine(line)
    end
end

local function EmitChat(addon, line)
    if addon and addon.Print then
        addon:Print(line)
    end
end

local function SampleItemIDFromBag(bagID)
    bagID = bagID or BAG_ID
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.itemID and not (issecretvalue and issecretvalue(info.itemID)) then
            return info.itemID
        end
    end
    return 6948
end

local function IsCollectionsEnabled()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    return db and db.modulesEnabled and db.modulesEnabled.collections ~= false
end

local function PadRight(s, width)
    s = tostring(s or "")
    if #s >= width then return s end
    return s .. string.rep(" ", width - #s)
end

local function RecordRow(rows, scenario, detail, ms, ok, err)
    rows[#rows + 1] = {
        scenario = scenario,
        detail = detail or "",
        ms = ms or 0,
        ok = ok ~= false,
        err = err,
    }
end

local function SafeTimed(rows, scenario, detail, fn)
    local t0 = debugprofilestop()
    local ok, r1, r2, r3 = pcall(fn)
    local ms = debugprofilestop() - t0
    if not ok then
        RecordRow(rows, scenario, detail, ms, false, r1)
        return nil
    end
    RecordRow(rows, scenario, detail, ms, true, nil)
    return r1, r2, r3, ms
end

function PS.PrintReport(addon, rows, extraLines)
    addon = addon or WarbandNexus
    if not addon or not addon.Print then return end

    addon:Print("|cff00ccff[WN BagPerf Stress]|r ---- ms timings ----")
    addon:Print(format(
        "  %s %s %s",
        PadRight("Scenario", COL_WIDTH),
        PadRight("Detail", DETAIL_WIDTH),
        "ms"
    ))

    local total = 0
    for i = 1, #rows do
        local row = rows[i]
        total = total + (row.ms or 0)
        local status = row.ok and "" or " |cffff0000ERR|r"
        local line = format(
            "  %s %s %6.2f%s",
            PadRight(row.scenario, COL_WIDTH),
            PadRight(row.detail, DETAIL_WIDTH),
            row.ms or 0,
            status
        )
        addon:Print(line)
        EmitTrace("|cff9370DB[WN BagPerf Stress]|r " .. line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        if not row.ok and row.err then
            addon:Print("    |cffff6600" .. tostring(row.err) .. "|r")
        end
    end

    addon:Print(format("|cff888888[WN]|r Total measured: %.2fms", total))
    if extraLines then
        for i = 1, #extraLines do
            addon:Print(extraLines[i])
        end
    end
    addon:Print("|cff888888[WN]|r Live spikes: |cff00ccff/wn bagdebug on|r + move loot — expect session_dirty, NO compress_flush within 1s. Trace: |cff00ccff/wn profiler trace|r")
end

function PS.Run(addon)
    addon = addon or WarbandNexus
    local H = ns.ItemsCacheStressHooks
    if not H then
        EmitChat(addon, "|cffff6600[WN]|r ItemsCacheStressHooks not loaded (ItemsCacheService).|r")
        return
    end

    if not ns.CharacterService or not ns.CharacterService.IsCharacterTracked
        or not ns.CharacterService:IsCharacterTracked(addon) then
        EmitChat(addon, "|cffff6600[WN]|r Character not tracked — enable tracking first.|r")
        return
    end

    local charKey = H.ResolveCharKey()
    if not charKey or (issecretvalue and issecretvalue(charKey)) then
        EmitChat(addon, "|cffff6600[WN]|r Could not resolve storage key (secret or nil).|r")
        return
    end

    local rows = {}
    local sampleItemID = SampleItemIDFromBag(BAG_ID)

    -- (f) GenerateItemHash / HasBagChanged
    SafeTimed(rows, "hash_generate", "bag " .. BAG_ID, function()
        local _, ms = H.GenerateItemHash(BAG_ID)
        return ms
    end)
    SafeTimed(rows, "hash_changed", "bag " .. BAG_ID, function()
        local changed, ms = H.HasBagChanged(BAG_ID)
        return format("%s %.2f", changed and "yes" or "no", ms)
    end)

    -- (g) ScanBag
    local scannedItems
    SafeTimed(rows, "scan_bag", "bag " .. BAG_ID, function()
        local items, ms = H.ScanBag(BAG_ID)
        scannedItems = items
        return format("slots=%d", items and #items or 0), ms
    end)

    -- (a) AcquireV2 decompress vs cache HIT
    H.ClearSessionDecompressedCache()
    SafeTimed(rows, "acquire_v2", "MISS decompress", function()
        local _, hit, ms = H.AcquireV2(charKey, "bags")
        if hit then
            error("expected cache MISS after session clear")
        end
        return ms
    end)
    SafeTimed(rows, "acquire_v2", "HIT session RAM", function()
        local _, hit, ms = H.AcquireV2(charKey, "bags")
        if not hit then
            -- v2 cache hit needs bucket.lastUpdate>0 or session-dirty RAM; empty SV may re-read DB.
            return "no-hit " .. format("%.2f", ms)
        end
        return ms
    end)

    -- (b) ReplaceBagInItemArray + UpdateSingleBag (summary warmed outside hot path)
    SafeTimed(rows, "replace_bag", "in-place merge", function()
        local allItems = select(1, H.AcquireV2(charKey, "bags"))
        if not allItems or not scannedItems then
            error("missing array for replace test")
        end
        local slotCount, ms = H.ReplaceBagInArray(allItems, BAG_ID, scannedItems)
        return format("rows=%d", slotCount or 0), ms
    end)
    H.BuildCharacterSummary(charKey, true)
    local updatePhaseDetail
    SafeTimed(rows, "update_single_bag", "bag " .. BAG_ID, function()
        if not addon.UpdateSingleBag then
            error("UpdateSingleBag missing")
        end
        H.BeginPhaseRecord()
        addon:UpdateSingleBag(charKey, BAG_ID)
        updatePhaseDetail = H.FormatPhaseLine(H.EndPhaseRecord())
    end)
    if updatePhaseDetail and rows[#rows] and rows[#rows].scenario == "update_single_bag" then
        rows[#rows].detail = "bag " .. BAG_ID .. " | " .. updatePhaseDetail
    end
    SafeTimed(rows, "update_single_bag", "warm 2nd HIT", function()
        if not addon.UpdateSingleBag then
            error("UpdateSingleBag missing")
        end
        addon:UpdateSingleBag(charKey, BAG_ID)
    end)

    -- (e) BuildCharacterSummary — warm after UpdateSingleBag incremental path
    SafeTimed(rows, "build_summary", "warm incremental", function()
        return H.BuildCharacterSummary(charKey)
    end)
    H.WipeCharacterSummary(charKey)
    H.InvalidateSummary(charKey)
    SafeTimed(rows, "build_summary", "cold full rebuild", function()
        return H.BuildCharacterSummary(charKey, true)
    end)

    -- (d) GetDetailedItemCountsFast cold + warm
    H.WipeCharacterSummary(charKey)
    H.InvalidateSummary(charKey)
    SafeTimed(rows, "tooltip_counts", "cold item " .. sampleItemID, function()
        if not addon.GetDetailedItemCountsFast then
            error("GetDetailedItemCountsFast missing")
        end
        addon:GetDetailedItemCountsFast(sampleItemID)
    end)
    local _, warmMs
    SafeTimed(rows, "tooltip_counts", "warm item " .. sampleItemID, function()
        addon:GetDetailedItemCountsFast(sampleItemID)
    end)
    if rows[#rows] and rows[#rows].scenario == "tooltip_counts" then
        warmMs = rows[#rows].ms
    end

    -- (c) Session-dirty mark + immediate compress (worst-case DB persist; not live bag-move path)
    local coalesceItems
    SafeTimed(rows, "session_dirty", "3x mark RAM", function()
        local allItems = select(1, H.AcquireV2(charKey, "bags"))
        if not allItems then
            error("no items array for dirty test")
        end
        coalesceItems = allItems
        for _ = 1, 3 do
            if addon.SaveItemsCompressed then
                addon:SaveItemsCompressed(charKey, "bags", allItems)
            end
        end
        if not H.HasSessionDirty() then
            error("expected session dirty buckets")
        end
        local n = H.SessionDirtyCount and H.SessionDirtyCount() or 0
        return format("buckets=%d", n)
    end)
    SafeTimed(rows, "compress_immediate", "flush+LibDeflate", function()
        H.FlushPendingCompress(true)
        if H.HasSessionDirty() then
            error("dirty buckets remain after sync flush")
        end
    end)
    if coalesceItems and addon.SaveItemsCompressed then
        addon:SaveItemsCompressed(charKey, "bags", coalesceItems)
        addon:SaveItemsCompressed(charKey, "bank", coalesceItems)
    end
    SafeTimed(rows, "compress_budgeted", "2 buckets async", function()
        if not H.HasSessionDirty() then
            error("expected session dirty for budgeted flush")
        end
        H.FlushPendingCompress(false)
    end)
    if coalesceItems and addon.SaveItemsCompressed then
        addon:SaveItemsCompressed(charKey, "bags", coalesceItems)
        H.ScheduleCompressCoalesce()
    end

    -- (h) Collection scan measure-only
    if IsCollectionsEnabled() then
        local CScan = ns.CollectionScan
        if CScan and CScan.MeasureBagsForCollectibles then
            SafeTimed(rows, "collection_scan", "bag " .. BAG_ID, function()
                local bagSet = { [BAG_ID] = true }
                return CScan.MeasureBagsForCollectibles(bagSet)
            end)
        else
            RecordRow(rows, "collection_scan", "module N/A", 0, false, "CollectionScan not loaded")
        end
    else
        RecordRow(rows, "collection_scan", "disabled", 0, true, nil)
    end

    -- (i) BumpGearStorageScanGeneration debounce — sync part + async verify
    local gen0 = H.GetGearStorageInvGen()
    local bumpOk = true
    local bumpErr
    for _ = 1, 5 do
        local ok, err = pcall(H.BumpGearStorageScanGeneration)
        if not ok then
            bumpOk = false
            bumpErr = err
            break
        end
    end
    local genMid = H.GetGearStorageInvGen()
    RecordRow(rows, "gear_inv_bump", "5x debounce schedule", 0, bumpOk, bumpErr)

    local extra = {}
    extra[#extra + 1] = "|cff888888[WN]|r compress_immediate = worst-case sync DB persist. Live bag moves: session_dirty only (no compress_flush within 1s)."
    if warmMs and warmMs > 1.0 then
        extra[#extra + 1] = format(
            "|cffff8800[WN]|r tooltip_counts warm %.2fms > 1ms target — check roster size or pending background drain.",
            warmMs
        )
    elseif warmMs then
        extra[#extra + 1] = format("|cff00ff00[WN]|r tooltip_counts warm %.2fms (target <1ms).", warmMs)
    end
    local warmSummaryMs
    for i = 1, #rows do
        if rows[i].scenario == "build_summary" and rows[i].detail == "warm incremental" then
            warmSummaryMs = rows[i].ms
            break
        end
    end
    if warmSummaryMs and warmSummaryMs < 2.0 then
        extra[#extra + 1] = format("|cff00ff00[WN]|r build_summary warm %.2fms (target <2ms).", warmSummaryMs)
    elseif warmSummaryMs then
        extra[#extra + 1] = format("|cffff8800[WN]|r build_summary warm %.2fms > 2ms target.", warmSummaryMs)
    end
    local updateBagMs
    for i = 1, #rows do
        if rows[i].scenario == "update_single_bag" then
            updateBagMs = rows[i].ms
            break
        end
    end
    if updateBagMs and updateBagMs < 1.0 then
        extra[#extra + 1] = format("|cff00ff00[WN]|r update_single_bag %.2fms (target <1ms cache HIT).", updateBagMs)
    elseif updateBagMs then
        extra[#extra + 1] = format("|cffff8800[WN]|r update_single_bag %.2fms > 1ms target — see phase breakdown in Detail.", updateBagMs)
    end
    extra[#extra + 1] = format(
        "|cff888888[WN]|r gear inv gen: before=%d mid=%d (debounce pending: %s)",
        gen0,
        genMid,
        (genMid == gen0) and "yes" or "no"
    )

    PS.PrintReport(addon, rows, extra)

    C_Timer.After(0.3, function()
        local genAfter = H.GetGearStorageInvGen()
        local debounced = (genAfter > gen0) and (genMid == gen0)
        local line = format(
            "|cff00ccff[WN BagPerf Stress]|r gear inv gen after 300ms: %d (%s)",
            genAfter,
            debounced and "debounced +1 OK" or "check manually"
        )
        EmitChat(addon, line)
        EmitTrace(line)
        if not debounced and genAfter == gen0 then
            EmitChat(addon, "|cffff8800[WN]|r Debounce timer may still be pending — wait and re-check ns._gearStorageInvGen.|r")
        end
    end)
end

function PS.HandleCommand(addon, subCmd)
    subCmd = subCmd and subCmd:lower() or ""
    if subCmd ~= "stress" and subCmd ~= "stresstest" and subCmd ~= "bench" then
        return false
    end
    PS.Run(addon)
    return true
end
