#!/usr/bin/env lua
--[[
    Regression test (static): PvE cells pick up crest / key / bounty / keystone changes.

    The PvE body's draw signature covers toolbar, columns, roster, expand state and vault, not cell
    values. A PVE_UPDATED or CURRENCY_UPDATED refresh therefore hit the fast path, which only
    re-lays out widths: crest, restored key, voidcore, bounty and keystone cells kept their old
    values until something in the signature changed. The router now marks PvE data dirty (only for
    currencies a PvE cell shows), and the next paint drops the stored signature so it takes the full
    path. Currencies the tab does not show no longer trigger a PvE repaint at all.
]]

local ROOT = os.getenv("WN_ROOT") or "."
local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a"):gsub("\r\n", "\n"):gsub("%-%-[^\n]*", "")
    fh:close()
    return src
end
local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local pve = ReadFile("Modules/UI/PvEUI.lua")
local body = ReadFile("Modules/UI/PvEUI_BodyPaint.lua")
local router = ReadFile("Modules/UI/UI_RefreshRouter.lua")

check(pve:find("function ns.PvEUI.MarkDataDirty()", 1, true) ~= nil, "PvEUI exposes MarkDataDirty")
local dirtyAt = body:find("if ns.PvEUI and ns.PvEUI._dataDirty then", 1, true)
local fastAt = body:find("if parent._pveBodyReady and parent._pveDrawSig == drawSig", 1, true)
check(dirtyAt and fastAt and dirtyAt < fastAt and body:sub(dirtyAt, fastAt):find("parent._pveDrawSig = nil", 1, true) ~= nil,
    "a dirty data flag drops the stored draw sig before the fast-path check")
check(body:find("ns.PvEUI._shownCurrencyIDs = shown", 1, true) ~= nil and body:find("shown[PVE_RESTORED_KEY_ID] = true", 1, true) ~= nil,
    "the body records which currencies its cells show")

local cur = router:match("EVENTS%.CURRENCY_UPDATED, function%(_, currencyID%)(.-)\n    end%)")
local pveBranch = cur and cur:match('currentTab == "pve" then(.-)else')
check(pveBranch and pveBranch:find("shownCur[currencyID]", 1, true) ~= nil and pveBranch:find("MarkDataDirty", 1, true) ~= nil,
    "CURRENCY_UPDATED on the PvE tab: shown currencies mark data dirty, others are ignored")
local pveUpd = router:match("EVENTS%.PVE_UPDATED, function%(.-%)(.-)\n    end%)")
check(pveUpd and pveUpd:find("MarkDataDirty", 1, true) ~= nil, "PVE_UPDATED on the PvE tab marks data dirty")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("PvE cell refresh suite failed with " .. failed .. " failure(s).")
end
print("PvE cell refresh suite: ALL TESTS PASSED.")
