--[[
    Loads the real Try Counter slice (Modules/TryCounterService*.lua and its data deps)
    under .github/scripts/wow_stub.lua, in WarbandNexus.toc order.

    Returns { stub, ns, WN, TC, Fns, RT }.

    Run from the repo root:  lua5.1 .github/scripts/test_try_counter_fishing.lua
]]

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."

local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

local ns = {}
local WN = {}
ns.WarbandNexus = WN

WN.db = {
    profile = {
        notifications = {
            autoTryCounter = true,
            hideTryCounterChat = false,
            tryCounterChatRoute = "loot",
        },
        modulesEnabled = { tryCounter = true },
        debugMode = false,
    },
    global = {
        tryCounts = { mount = {}, pet = {}, toy = {}, illusion = {}, item = {} },
        trackDB = {},
        characters = {},
    },
    char = {},
}

function WN:Print(msg) stub.chat[#stub.chat + 1] = msg end
function WN:SendMessage() end
function WN:RegisterMessage() end
function WN:RegisterEvent() end
function WN:ScheduleTimer(fn, delay) return _G.C_Timer.NewTimer(delay, fn) end
function WN:CancelTimer(t) if t and t.Cancel then t:Cancel() end end
function WN:RegisterTryCounterLootToastForBagDedupe() end

ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = {
    GetCharacterStorageKey = function() return "Tester-TestRealm" end,
    GetCanonicalCharacterKey = function(_, k) return k end,
    CheckAddOnLoaded = function() return false end,
}
ns.Profiler = { enabled = false, CAT = { SVC = "svc" } }

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    -- WoW tolerates a UTF-8 BOM on addon files; loadstring does not.
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

-- AceLocale stub: Locales/enUS.lua writes straight into ns.L.
local L = {}
ns.L = L
_G.LibStub = function(name)
    if name == "AceLocale-3.0" then
        return { NewLocale = function() return L end, GetLocale = function() return L end }
    end
    return nil
end
_G.GetLocale = function() return "enUS" end

-- TOC order for the Try Counter slice and everything it reads.
-- ChatIntegrationService is included on purpose: it owns the real chat routing, so the suites
-- exercise delivery end to end instead of stopping at "a line was emitted". The stub reports every
-- external addon as absent (see wow_stub: IsAddOnLoaded / C_AddOns), which is the configuration we
-- must never break -- no ElvUI, no Chattynator, no Rarity.
LoadFile("Locales/enUS.lua")
LoadFile("Modules/Constants.lua")
LoadFile("Modules/ChatIntegrationService.lua")
LoadFile("Modules/CollectibleSourceDB.lua")
LoadFile("Modules/TryCounterService_Shared.lua")
LoadFile("Modules/TryCounterService_Events.lua")
LoadFile("Modules/TryCounterService_Process.lua")
LoadFile("Modules/TryCounterService.lua")
LoadFile("Modules/TryCounterService_Loot.lua")
LoadFile("Modules/TryCounterService_Stats.lua")
LoadFile("Modules/TryCounterService_Handlers.lua")

WN:InitializeTryCounter()
stub.Advance(20)   -- drain the scheduled init work (index build, ID warmup, stat seed)
stub.Reset()

return {
    stub = stub,
    ns = ns,
    WN = WN,
    TC = ns.TryCounter,
    Fns = ns.TryCounter.Fns,
    RT = ns.TryCounter.Runtime,
}
