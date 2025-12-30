--[[
    Warband Nexus - Performance Monitor Module
    Tracks performance metrics, memory usage, and operation timing
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Performance metrics
local performanceMetrics = {
    operations = {},      -- Operation timing data
    memory = {},          -- Memory snapshots
    fps = {},             -- FPS tracking
    latency = {},         -- Network latency
}

-- Configuration
local MAX_HISTORY = 100 -- Keep last 100 measurements
local MEMORY_SAMPLE_INTERVAL = 60 -- Sample memory every 60 seconds

--[[
    Start timing an operation
    @param operationName string - Operation identifier
    @return number - Start time (for manual timing)
]]
function WarbandNexus:StartTiming(operationName)
    local startTime = debugprofilestop()
    
    if not performanceMetrics.operations[operationName] then
        performanceMetrics.operations[operationName] = {
            count = 0,
            totalTime = 0,
            minTime = math.huge,
            maxTime = 0,
            history = {}
        }
    end
    
    return startTime
end

--[[
    End timing an operation
    @param operationName string - Operation identifier
    @param startTime number - Start time from StartTiming
]]
function WarbandNexus:EndTiming(operationName, startTime)
    local elapsed = debugprofilestop() - startTime
    local metrics = performanceMetrics.operations[operationName]
    
    if not metrics then return end
    
    -- Update metrics
    metrics.count = metrics.count + 1
    metrics.totalTime = metrics.totalTime + elapsed
    metrics.minTime = math.min(metrics.minTime, elapsed)
    metrics.maxTime = math.max(metrics.maxTime, elapsed)
    metrics.avgTime = metrics.totalTime / metrics.count
    
    -- Add to history
    table.insert(metrics.history, {
        time = time(),
        duration = elapsed
    })
    
    -- Trim history
    if #metrics.history > MAX_HISTORY then
        table.remove(metrics.history, 1)
    end
    
    -- Log slow operations
    if elapsed > 100 then -- > 100ms
        self:Debug(string.format("|cffff6600Slow operation:|r %s took %.0f ms", operationName, elapsed))
    end
end

--[[
    Time a function execution
    @param operationName string - Operation name
    @param func function - Function to time
    @param ... any - Function arguments
    @return any - Function return values
]]
function WarbandNexus:TimeFunction(operationName, func, ...)
    local startTime = self:StartTiming(operationName)
    local results = {func(...)}
    self:EndTiming(operationName, startTime)
    return unpack(results)
end

--[[
    Get operation timing statistics
    @param operationName string - Operation name
    @return table - Timing statistics
]]
function WarbandNexus:GetOperationStats(operationName)
    local metrics = performanceMetrics.operations[operationName]
    
    if not metrics then
        return {
            count = 0,
            avgTime = 0,
            minTime = 0,
            maxTime = 0,
            totalTime = 0
        }
    end
    
    return {
        count = metrics.count,
        avgTime = metrics.avgTime or 0,
        minTime = metrics.minTime == math.huge and 0 or metrics.minTime,
        maxTime = metrics.maxTime,
        totalTime = metrics.totalTime
    }
end

--[[
    Sample current memory usage
]]
function WarbandNexus:SampleMemory()
    UpdateAddOnMemoryUsage()
    local memory = GetAddOnMemoryUsage(ADDON_NAME)
    
    table.insert(performanceMetrics.memory, {
        time = time(),
        usage = memory
    })
    
    -- Trim history
    if #performanceMetrics.memory > MAX_HISTORY then
        table.remove(performanceMetrics.memory, 1)
    end
    
    return memory
end

--[[
    Get current memory usage
    @return number - Memory in KB
]]
function WarbandNexus:GetMemoryUsage()
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage(ADDON_NAME)
end

--[[
    Get memory statistics
    @return table - Memory stats
]]
function WarbandNexus:GetMemoryStats()
    if #performanceMetrics.memory == 0 then
        self:SampleMemory()
    end
    
    local total = 0
    local min = math.huge
    local max = 0
    local count = #performanceMetrics.memory
    
    for _, sample in ipairs(performanceMetrics.memory) do
        total = total + sample.usage
        min = math.min(min, sample.usage)
        max = math.max(max, sample.usage)
    end
    
    return {
        current = self:GetMemoryUsage(),
        average = count > 0 and (total / count) or 0,
        min = min == math.huge and 0 or min,
        max = max,
        samples = count
    }
end

--[[
    Sample current FPS
]]
function WarbandNexus:SampleFPS()
    local fps = GetFramerate()
    
    table.insert(performanceMetrics.fps, {
        time = time(),
        fps = fps
    })
    
    -- Trim history
    if #performanceMetrics.fps > MAX_HISTORY then
        table.remove(performanceMetrics.fps, 1)
    end
    
    return fps
end

--[[
    Get FPS statistics
    @return table - FPS stats
]]
function WarbandNexus:GetFPSStats()
    if #performanceMetrics.fps == 0 then
        return {
            current = GetFramerate(),
            average = 0,
            min = 0,
            max = 0
        }
    end
    
    local total = 0
    local min = math.huge
    local max = 0
    
    for _, sample in ipairs(performanceMetrics.fps) do
        total = total + sample.fps
        min = math.min(min, sample.fps)
        max = math.max(max, sample.fps)
    end
    
    local count = #performanceMetrics.fps
    
    return {
        current = GetFramerate(),
        average = total / count,
        min = min,
        max = max,
        samples = count
    }
end

--[[
    Get network latency
    @return home, world - Latency in ms
]]
function WarbandNexus:GetLatency()
    local _, _, home, world = GetNetStats()
    return home, world
end

--[[
    Sample network latency
]]
function WarbandNexus:SampleLatency()
    local home, world = self:GetLatency()
    
    table.insert(performanceMetrics.latency, {
        time = time(),
        home = home,
        world = world
    })
    
    -- Trim history
    if #performanceMetrics.latency > MAX_HISTORY then
        table.remove(performanceMetrics.latency, 1)
    end
end

--[[
    Get all performance metrics
    @return table - Complete performance data
]]
function WarbandNexus:GetPerformanceMetrics()
    return {
        operations = self:GetAllOperationStats(),
        memory = self:GetMemoryStats(),
        fps = self:GetFPSStats(),
        latency = self:GetLatencyStats()
    }
end

--[[
    Get all operation statistics
    @return table - All operation stats
]]
function WarbandNexus:GetAllOperationStats()
    local stats = {}
    
    for opName, metrics in pairs(performanceMetrics.operations) do
        stats[opName] = self:GetOperationStats(opName)
    end
    
    return stats
end

--[[
    Get latency statistics
    @return table - Latency stats
]]
function WarbandNexus:GetLatencyStats()
    if #performanceMetrics.latency == 0 then
        local home, world = self:GetLatency()
        return {
            home = {current = home, average = home, min = home, max = home},
            world = {current = world, average = world, min = world, max = world}
        }
    end
    
    local homeTotal, worldTotal = 0, 0
    local homeMin, worldMin = math.huge, math.huge
    local homeMax, worldMax = 0, 0
    
    for _, sample in ipairs(performanceMetrics.latency) do
        homeTotal = homeTotal + sample.home
        worldTotal = worldTotal + sample.world
        homeMin = math.min(homeMin, sample.home)
        worldMin = math.min(worldMin, sample.world)
        homeMax = math.max(homeMax, sample.home)
        worldMax = math.max(worldMax, sample.world)
    end
    
    local count = #performanceMetrics.latency
    local home, world = self:GetLatency()
    
    return {
        home = {
            current = home,
            average = homeTotal / count,
            min = homeMin,
            max = homeMax
        },
        world = {
            current = world,
            average = worldTotal / count,
            min = worldMin,
            max = worldMax
        }
    }
end

--[[
    Export performance report
    @return string - Formatted performance report
]]
function WarbandNexus:ExportPerformanceReport()
    local lines = {}
    
    table.insert(lines, "=== Warband Nexus Performance Report ===")
    table.insert(lines, "Generated: " .. date("%Y-%m-%d %H:%M:%S"))
    table.insert(lines, "")
    
    -- Memory
    local memStats = self:GetMemoryStats()
    table.insert(lines, "Memory Usage:")
    table.insert(lines, string.format("  Current: %.2f MB", memStats.current / 1024))
    table.insert(lines, string.format("  Average: %.2f MB", memStats.average / 1024))
    table.insert(lines, string.format("  Min: %.2f MB", memStats.min / 1024))
    table.insert(lines, string.format("  Max: %.2f MB", memStats.max / 1024))
    table.insert(lines, "")
    
    -- FPS
    local fpsStats = self:GetFPSStats()
    table.insert(lines, "Frame Rate:")
    table.insert(lines, string.format("  Current: %.1f FPS", fpsStats.current))
    table.insert(lines, string.format("  Average: %.1f FPS", fpsStats.average))
    table.insert(lines, string.format("  Min: %.1f FPS", fpsStats.min))
    table.insert(lines, string.format("  Max: %.1f FPS", fpsStats.max))
    table.insert(lines, "")
    
    -- Operations
    table.insert(lines, "Operation Timing:")
    local opStats = self:GetAllOperationStats()
    local sortedOps = {}
    for opName, stats in pairs(opStats) do
        table.insert(sortedOps, {name = opName, stats = stats})
    end
    table.sort(sortedOps, function(a, b) return a.stats.totalTime > b.stats.totalTime end)
    
    for i = 1, math.min(10, #sortedOps) do
        local op = sortedOps[i]
        table.insert(lines, string.format("  %s:", op.name))
        table.insert(lines, string.format("    Count: %d", op.stats.count))
        table.insert(lines, string.format("    Avg: %.2f ms", op.stats.avgTime))
        table.insert(lines, string.format("    Min: %.2f ms", op.stats.minTime))
        table.insert(lines, string.format("    Max: %.2f ms", op.stats.maxTime))
        table.insert(lines, string.format("    Total: %.2f ms", op.stats.totalTime))
    end
    
    return table.concat(lines, "\n")
end

--[[
    Clear performance metrics
]]
function WarbandNexus:ClearPerformanceMetrics()
    table.wipe(performanceMetrics.operations)
    table.wipe(performanceMetrics.memory)
    table.wipe(performanceMetrics.fps)
    table.wipe(performanceMetrics.latency)
end

--[[
    Initialize performance monitoring
]]
function WarbandNexus:InitializePerformanceMonitor()
    -- Sample memory periodically
    C_Timer.NewTicker(MEMORY_SAMPLE_INTERVAL, function()
        self:SampleMemory()
    end)
    
    -- Sample FPS and latency less frequently
    C_Timer.NewTicker(10, function()
        self:SampleFPS()
        self:SampleLatency()
    end)
    
    -- Initial samples
    self:SampleMemory()
    self:SampleFPS()
    self:SampleLatency()
    
    self:Debug("Performance monitor initialized")
end

--[[
    Benchmark a function
    @param name string - Benchmark name
    @param func function - Function to benchmark
    @param iterations number - Number of iterations
    @return table - Benchmark results
]]
function WarbandNexus:Benchmark(name, func, iterations)
    iterations = iterations or 1000
    
    local times = {}
    local totalTime = 0
    
    for i = 1, iterations do
        local startTime = debugprofilestop()
        func()
        local elapsed = debugprofilestop() - startTime
        table.insert(times, elapsed)
        totalTime = totalTime + elapsed
    end
    
    table.sort(times)
    
    return {
        name = name,
        iterations = iterations,
        totalTime = totalTime,
        avgTime = totalTime / iterations,
        minTime = times[1],
        maxTime = times[#times],
        medianTime = times[math.floor(#times / 2)],
        p95Time = times[math.floor(#times * 0.95)],
        p99Time = times[math.floor(#times * 0.99)]
    }
end

