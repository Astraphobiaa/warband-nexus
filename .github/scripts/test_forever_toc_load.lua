#!/usr/bin/env lua5.1
--[[
    WarbandNexus_Forever.toc leaves the retail-only files out (scripts/build_flavor_tocs.py). Every
    file it keeps must still LOAD without them: a kept file that indexes or asserts a symbol only an
    excluded file defines would take the whole addon down on WoW Forever at login.

    Differential load: run every Lua file of WarbandNexus.toc, then of WarbandNexus_Forever.toc, in
    TOC order, each in a fresh namespace over a permissive global stub (unknown globals resolve to an
    inert auto-object). The stub is crude, so some files fail on BOTH lists; those are environment
    noise. A file that loads under the retail TOC but fails under the Forever TOC is a missing-symbol
    dependency on a retail-only file -- that is the failure this test reports.

    Covers load time only (file chunks). Runtime entry points are guarded at the call sites and the
    capability gates keep the retail-only surfaces closed on Forever.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local loadstring = loadstring or load
local setfenv = setfenv

local function ReadToc(name)
    local fh = assert(io.open(ROOT .. "/" .. name, "rb"), "missing " .. name)
    local files = {}
    for line in fh:read("*a"):gmatch("[^\r\n]+") do
        local s = line:match("^%s*(.-)%s*$")
        if s ~= "" and not s:match("^#") and s:lower():match("%.lua$") then
            files[#files + 1] = (s:gsub("\\", "/"))
        end
    end
    fh:close()
    return files
end

-- Inert auto-object: any field, call, arithmetic or concatenation yields itself (or a neutral value).
local auto
auto = setmetatable({}, {
    __index = function() return auto end,
    __newindex = function() end,
    __call = function() return auto end,
    __concat = function() return "" end,
    __add = function() return 0 end, __sub = function() return 0 end,
    __mul = function() return 0 end, __div = function() return 0 end,
    __unm = function() return 0 end, __lt = function() return false end,
    __le = function() return false end, __len = function() return 0 end,
})

local function NewEnv()
    -- Real Lua libraries + an `auto` fallback for every WoW global; writes stay in this env.
    local env = {}
    for _, k in ipairs({ "string", "table", "math", "pairs", "ipairs", "type", "tostring", "tonumber",
        "select", "next", "pcall", "xpcall", "error", "assert", "setmetatable", "getmetatable", "rawget",
        "rawset", "rawequal", "unpack", "print", "coroutine", "os", "debug" }) do
        env[k] = _G[k]
    end
    env.unpack = env.unpack or table.unpack
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.table = setmetatable({ wipe = env.wipe }, { __index = table })
    env.strsplit = function(sep, s) local out = {} for p in tostring(s):gmatch("[^" .. sep .. "]+") do out[#out + 1] = p end return unpack(out) end
    env.format = string.format
    env.issecretvalue = function() return false end
    env._G = env
    return setmetatable(env, { __index = function() return auto end })
end

local function LoadAll(files)
    local env = NewEnv()
    -- The namespace every addon file receives; ns.WarbandNexus is a plain table so methods defined
    -- with `function WarbandNexus:Foo()` are real and later files can find them.
    local WN = setmetatable({}, { __index = function() return auto end })
    local ns = setmetatable({ WarbandNexus = WN }, { __index = function() return nil end })
    env.WarbandNexus = WN
    env.LibStub = setmetatable({}, { __call = function() return setmetatable({
        NewAddon = function() return WN end,
        GetAddon = function() return WN end,
        NewLocale = function() return nil end,
    }, { __index = function() return auto end }) end })
    local failed = {}
    for i = 1, #files do
        local rel = files[i]
        local fh = io.open(ROOT .. "/" .. rel, "rb")
        if fh then
            local src = fh:read("*a"):gsub("^\239\187\191", "")
            fh:close()
            -- 5.1: loadstring + setfenv; 5.2+: load with the env argument (dev machines).
            local chunk, err
            if setfenv then
                chunk, err = loadstring(src, "@" .. rel)
                if chunk then setfenv(chunk, env) end
            else
                chunk, err = load(src, "@" .. rel, "t", env)
            end
            if chunk then
                local ok, rerr = pcall(chunk, "WarbandNexus", ns)
                if not ok then failed[rel] = tostring(rerr) end
            else
                failed[rel] = tostring(err)
            end
        end
    end
    return failed
end

local retailFailed = LoadAll(ReadToc("WarbandNexus.toc"))
local foreverFiles = ReadToc("WarbandNexus_Forever.toc")
local foreverFailed = LoadAll(foreverFiles)

local regressions = 0
for i = 1, #foreverFiles do
    local rel = foreverFiles[i]
    if foreverFailed[rel] and not retailFailed[rel] then
        regressions = regressions + 1
        print("  FAIL " .. rel .. " loads on retail but not on Forever: " .. foreverFailed[rel])
    end
end
local noise = 0
for _ in pairs(retailFailed) do noise = noise + 1 end
print(string.format("Forever TOC load: %d files, %d Forever-only load failures (%d stub-noise files on both).",
    #foreverFiles, regressions, noise))
if regressions > 0 then
    error("Forever TOC load suite failed with " .. regressions .. " failure(s).")
end
print("Forever TOC load suite: ALL TESTS PASSED.")
