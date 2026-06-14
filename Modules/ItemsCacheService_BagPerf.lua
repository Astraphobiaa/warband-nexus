--[[
    Warband Nexus - Items cache bag-update perf debug (dev / support).
    Toggle: /wn bagdebug on|off|summary|reset|spike <ms>
    Requires debug mode (/wn debug). Chat lines on spikes; trace via /wn profiler trace.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local debugprofilestop = debugprofilestop
local format = string.format
local tinsert = table.insert
local tremove = table.remove

local BP = {}
ns.ItemsCacheBagPerf = BP

BP._activeCtx = nil

local SPIKE_MS_DEFAULT = 16
local SPIKE_MS_MAX = 500
local LAST_LINES_MAX = 12

local stats = {
    bucketEvents = 0,
    hashChecks = 0,
    hashChanged = 0,
    updates = 0,
    throttled = 0,
    deferred = 0,
    cacheHits = 0,
    decompresses = 0,
    spikes = 0,
    totalMs = 0,
    maxMs = 0,
    maxBagID = nil,
    compressFlushes = 0,
    compressFlushMs = 0,
    compressFlushMaxMs = 0,
    fastPersists = 0,
    fastPersistMaxMs = 0,
    sessionDirtyMarks = 0,
    lastLines = {},
}

local function Profile()
    local addon = WarbandNexus
    if not addon or not addon.db or not addon.db.profile then return nil end
    return addon.db.profile
end

function BP.IsEnabled()
    local p = Profile()
    if p and p.debugMode == true and p.debugItemsBagPerf == true then
        return true
    end
    local P = ns.Profiler
    return P and P.IsDiagnosticsSuiteActive and P:IsDiagnosticsSuiteActive()
end

function BP.SpikeThresholdMs()
    local p = Profile()
    local ms = p and tonumber(p.debugItemsBagPerfSpikeMs)
    if not ms or ms < 1 then return SPIKE_MS_DEFAULT end
    if ms > SPIKE_MS_MAX then return SPIKE_MS_MAX end
    return ms
end

function BP.SetEnabled(on)
    local p = Profile()
    if not p then return false end
    if on and not p.debugMode then
        p.debugMode = true
    end
    p.debugItemsBagPerf = on == true
    if p.debugItemsBagPerf and (not p.debugItemsBagPerfSpikeMs or p.debugItemsBagPerfSpikeMs < 1) then
        p.debugItemsBagPerfSpikeMs = SPIKE_MS_DEFAULT
    end
    return p.debugItemsBagPerf
end

function BP.SetSpikeMs(ms)
    local p = Profile()
    if not p then return SPIKE_MS_DEFAULT end
    ms = tonumber(ms)
    if not ms or ms < 1 then ms = SPIKE_MS_DEFAULT end
    if ms > SPIKE_MS_MAX then ms = SPIKE_MS_MAX end
    p.debugItemsBagPerfSpikeMs = ms
    return ms
end

function BP.Reset()
    stats.bucketEvents = 0
    stats.hashChecks = 0
    stats.hashChanged = 0
    stats.updates = 0
    stats.throttled = 0
    stats.deferred = 0
    stats.cacheHits = 0
    stats.decompresses = 0
    stats.spikes = 0
    stats.totalMs = 0
    stats.maxMs = 0
    stats.maxBagID = nil
    stats.compressFlushes = 0
    stats.compressFlushMs = 0
    stats.compressFlushMaxMs = 0
    stats.fastPersists = 0
    stats.fastPersistMaxMs = 0
    stats.sessionDirtyMarks = 0
    wipe(stats.lastLines)
end

-- Helpers must be defined before any BP.* that calls them (Lua 5.1: no forward visibility).
local function PushLastLine(line)
    local lines = stats.lastLines
    lines[#lines + 1] = line
    while #lines > LAST_LINES_MAX do
        tremove(lines, 1)
    end
end

local function EmitTrace(line)
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine(line)
    end
end

local function EmitChat(line)
    if WarbandNexus and WarbandNexus.Print then
        WarbandNexus:Print(line)
    end
end

function BP.NoteSessionDirty(charKey, dataType)
    if not BP.IsEnabled() then return end
    stats.sessionDirtyMarks = stats.sessionDirtyMarks + 1
end

function BP.NoteBucketEvent(changedBagCount)
    if not BP.IsEnabled() then return end
    stats.bucketEvents = stats.bucketEvents + 1
end

function BP.NoteHashCheck(changed)
    if not BP.IsEnabled() then return end
    stats.hashChecks = stats.hashChecks + 1
    if changed then
        stats.hashChanged = stats.hashChanged + 1
    end
end

function BP.NoteThrottled(bagID, kind)
    if not BP.IsEnabled() then return end
    if kind == "defer" then
        stats.deferred = stats.deferred + 1
    else
        stats.throttled = stats.throttled + 1
    end
end

function BP.NoteAcquire(cacheHit)
    if not BP.IsEnabled() then return end
    if cacheHit then
        stats.cacheHits = stats.cacheHits + 1
    else
        stats.decompresses = stats.decompresses + 1
    end
end

function BP.NoteCompressFlush(totalMs, entryCount, syncAll)
    if not BP.IsEnabled() then return end
    if not totalMs or totalMs < 0 then return end
    stats.compressFlushes = stats.compressFlushes + 1
    stats.compressFlushMs = stats.compressFlushMs + totalMs
    if totalMs > stats.compressFlushMaxMs then
        stats.compressFlushMaxMs = totalMs
    end
    local spike = BP.SpikeThresholdMs()
    local tag = syncAll and "sync" or "coalesced"
    local line = format(
        "|cff9370DB[WN BagPerf]|r compress_flush %s entries=%s total=%.1fms",
        tag,
        tostring(entryCount or 0),
        totalMs
    )
    PushLastLine(line)
    EmitTrace(line)
    if totalMs >= spike then
        stats.spikes = stats.spikes + 1
        EmitChat("|cffff8800[WN BagPerf SPIKE]|r compress_flush " .. tag .. " " .. format("%.1fms", totalMs))
    end
end

function BP.NoteFastPersist(totalMs, entryCount)
    if not BP.IsEnabled() then return end
    if not totalMs or totalMs < 0 then return end
    stats.fastPersists = stats.fastPersists + 1
    if totalMs > stats.fastPersistMaxMs then
        stats.fastPersistMaxMs = totalMs
    end
    local spike = BP.SpikeThresholdMs()
    local line = format(
        "|cff9370DB[WN BagPerf]|r fast_persist entries=%s total=%.1fms (uncompressed, no LibDeflate)",
        tostring(entryCount or 0),
        totalMs
    )
    PushLastLine(line)
    EmitTrace(line)
    if totalMs >= spike then
        stats.spikes = stats.spikes + 1
        EmitChat("|cffff8800[WN BagPerf SPIKE]|r fast_persist " .. format("%.1fms", totalMs))
    end
end

function BP.SetActiveCtx(ctx)
    BP._activeCtx = ctx
end

function BP.ClearActiveCtx()
    BP._activeCtx = nil
end

function BP.BeginBagUpdate(bagID, charKey, dataType)
    if not BP.IsEnabled() then return nil end
    return {
        bagID = bagID,
        charKey = charKey,
        dataType = dataType or "bags",
        t0 = debugprofilestop(),
        phases = {},
        slotCount = 0,
    }
end

function BP.MarkPhase(ctx, name)
    if not ctx or not name or not BP.IsEnabled() then return end
    if type(ctx.phases) ~= "table" then return end
    local now = debugprofilestop()
    local prev = ctx.t0 or now
    local ms = now - prev
    ctx.phases[name] = (ctx.phases[name] or 0) + ms
    ctx.t0 = now
end

function BP.FinishBagUpdate(ctx, extra)
    if not ctx or not BP.IsEnabled() then return end
    local total = 0
    for _, ms in pairs(ctx.phases) do
        total = total + ms
    end
    stats.updates = stats.updates + 1
    stats.totalMs = stats.totalMs + total
    if total > stats.maxMs then
        stats.maxMs = total
        stats.maxBagID = ctx.bagID
    end

    local spike = BP.SpikeThresholdMs()
    local parts = {}
    local order = { "acquire", "scan", "merge", "snapshot", "summary", "save", "compress", "persist" }
    for i = 1, #order do
        local k = order[i]
        local ms = ctx.phases[k]
        if ms and ms > 0.05 then
            parts[#parts + 1] = format("%s=%.1f", k, ms)
        end
    end
    local phaseStr = (#parts > 0) and table.concat(parts, " ") or "?"
    local cacheTag = ""
    if ctx.cacheHit == true then
        cacheTag = " cache=HIT"
    elseif ctx.cacheHit == false then
        cacheTag = " cache=DECOMPRESS"
    end
    local line = format(
        "|cff9370DB[WN BagPerf]|r bag=%s %s slots=%s total=%.1fms | %s%s%s",
        tostring(ctx.bagID),
        tostring(ctx.dataType),
        tostring(ctx.slotCount or 0),
        total,
        phaseStr,
        extra and (" " .. extra) or "",
        cacheTag
    )
    PushLastLine(line)
    local P = ns.Profiler
    if P and P.AppendTraceRow then
        P:AppendTraceRow(
            "Bag",
            "bag " .. tostring(ctx.bagID),
            phaseStr,
            total,
            total >= spike and "anomaly" or "bag"
        )
    end
    if P and P.enabled and P._Record and P.SliceLabel and P.CAT then
        P:_Record(P:SliceLabel(P.CAT.SVC, "ItemsBagUpdate"), total)
    end
    if total >= spike then
        stats.spikes = stats.spikes + 1
        EmitChat("|cffff8800[WN BagPerf SPIKE]|r " .. line:gsub("|cff9370DB%[WN BagPerf%]|r ", ""))
    end
end

function BP.PrintSummary(addon)
    addon = addon or WarbandNexus
    if not addon or not addon.Print then return end
    local avg = stats.updates > 0 and (stats.totalMs / stats.updates) or 0
    addon:Print("|cff00ccff[WN BagPerf]|r summary (since last reset):")
    addon:Print(format(
        "  updates=%d spikes(>=%.0fms)=%d avg=%.1fms max=%.1fms bag=%s",
        stats.updates,
        BP.SpikeThresholdMs(),
        stats.spikes,
        avg,
        stats.maxMs,
        tostring(stats.maxBagID or "-")
    ))
    addon:Print(format(
        "  buckets=%d hash=%d changed=%d throttle=%d deferred=%d cacheHit=%d decompress=%d dirtyMarks=%d fastPersist=%d maxFast=%.1fms compressFlush=%d maxCompress=%.1fms",
        stats.bucketEvents,
        stats.hashChecks,
        stats.hashChanged,
        stats.throttled,
        stats.deferred,
        stats.cacheHits,
        stats.decompresses,
        stats.sessionDirtyMarks,
        stats.fastPersists,
        stats.fastPersistMaxMs,
        stats.compressFlushes,
        stats.compressFlushMaxMs
    ))
    local lines = stats.lastLines
    if #lines > 0 then
        addon:Print("|cff888888[WN]|r Last spikes / slow updates:")
        for i = 1, #lines do
            addon:Print("  " .. lines[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        end
    end
    if not BP.IsEnabled() then
        addon:Print("|cff888888[WN]|r Tracking OFF — |cff00ccff/wn bagdebug on|r (needs |cff00ccff/wn debug|r).")
    end
end

function BP.HandleCommand(addon, subCmd, arg3)
    addon = addon or WarbandNexus
    subCmd = subCmd and subCmd:lower() or ""
    if subCmd == "" or subCmd == "toggle" then
        local on = BP.SetEnabled(not BP.IsEnabled())
        if on then
        addon:Print("|cff00ff00[WN]|r Bag update perf debug ENABLED. Move loot or shift bag slots; expect session_dirty on hot path, fast_persist ~15s idle, compress only on /reload or logout.")
        addon:Print("|cff888888[WN]|r |cff00ccff/wn bagdebug summary|r — stats. |cff00ccff/wn profiler trace|r — full log. Spike threshold: " .. BP.SpikeThresholdMs() .. "ms.")
        else
            addon:Print("|cffff8800[WN]|r Bag update perf debug DISABLED.|r")
        end
        return
    end
    if subCmd == "on" or subCmd == "enable" then
        BP.SetEnabled(true)
        addon:Print("|cff00ff00[WN]|r Bag update perf debug ENABLED.|r")
        return
    end
    if subCmd == "off" or subCmd == "disable" then
        BP.SetEnabled(false)
        addon:Print("|cffff8800[WN]|r Bag update perf debug DISABLED.|r")
        return
    end
    if subCmd == "summary" or subCmd == "stats" then
        BP.PrintSummary(addon)
        return
    end
    if subCmd == "reset" or subCmd == "clear" then
        BP.Reset()
        addon:Print("|cff00ccff[WN]|r Bag perf counters reset.|r")
        return
    end
    if subCmd == "spike" then
        local ms = tonumber(arg3)
        if not ms then
            addon:Print("|cffff6600[WN]|r Usage: |cff00ccff/wn bagdebug spike <ms>|r (1-" .. SPIKE_MS_MAX .. ", default " .. SPIKE_MS_DEFAULT .. ")")
            return
        end
        local set = BP.SetSpikeMs(ms)
        addon:Print("|cff00ccff[WN]|r Bag perf spike threshold: " .. set .. "ms")
        return
    end
    local Stress = ns.ItemsCachePerfStress
    if Stress and Stress.HandleCommand and Stress.HandleCommand(addon, subCmd) then
        return
    end
    local spikeMs = tonumber(subCmd)
    if spikeMs then
        local set = BP.SetSpikeMs(spikeMs)
        addon:Print("|cff00ccff[WN]|r Bag perf spike threshold: " .. set .. "ms")
        return
    end
    addon:Print("|cff00ccff/wn bagdebug|r [|cff00ccffon|r|cff00ccff/off|r|cff00ccff/summary|r|cff00ccff/reset|r|cff00ccff/spike <ms>|r|cff00ccff/stress|r] — track bag compress/decompress cost.")
end
