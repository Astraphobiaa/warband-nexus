--[[
    Warband Nexus — Chat integration (single owner)

    Warcraft wiki (ChatFrame_AddMessageEventFilter):
    - Filters run in registration order; return true to discard the message.
    - When allowing, return false, arg1, ... arg11 so the chain keeps correct args
      (returning only false can break subsequent filters / display).

    Output routing:
    - Use chatFrame:AddMessage (no RawHook on AddMessage) so ElvUI, Chattynator,
      Prat, Horizon-style chat replacements keep working.
    - Route to panels via ChatFrame_ContainsMessageGroup + messageTypeList fallback,
      matching Blizzard’s per-tab message groups (LOOT, CURRENCY, COMBAT_FACTION_CHANGE).
    - Loot-routed lines use pairs() on messageTypeList (sparse-safe) and CHAT_MSG_LOOT
      event registration so custom tabs with Item Loot match like General.
    - Try Counter chat: profile tryCounterChatRoute — loot (default), dedicated (WN_TRYCOUNTER
      in ChatTypeGroup; mirrors Loot add/remove on chat windows), or all_tabs.

    This module owns ALL addon-registered ChatFrame_AddMessageEventFilter hooks for WN:
    - CHAT_MSG_SYSTEM — hide Time Played lines (profile; default on) + legacy patterns
    - CHAT_MSG_COMBAT_FACTION_CHANGE — suppress Blizzard rep line when WN replaces it
    - CHAT_MSG_CURRENCY — debounced cache refresh + optional Blizzard suppression

    ns.ChatOutput: factory-style API for other modules (routing only).

    Chattynator: shim API.AddMessageToWindowAndTab → Messages:SetIncomingType
    (ADDON, source=WarbandNexus, tabTag=nil). If API pcall fails, DeliverBlizzardChatFallback
    still writes to DEFAULT / ChatFrame1..N so lines are not lost.

    ElvUI: try/currency/system chat lines use chatFrame:AddMessage on each matching ChatFrameN
    (same as stock UI). Only WarbandNexus:Print() still prefers DEFAULT when ElvUI is loaded.

    Mainline (Midnight): ChatFrameMixin:SystemEventHandler calls
    ChatFrameUtil.DisplayTimePlayed → AddMessage — not _G.ChatFrame_DisplayTimePlayed.
    We wrap ChatFrameUtil.DisplayTimePlayed; legacy globals kept when present.

    Chattynator TIME_PLAYED: Chattynator.API.FilterTimePlayed when hiding played time.

    AceEvent TIME_PLAYED_MSG (DataService) is separate from chat display.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local Constants = ns.Constants
local issecretvalue = issecretvalue

-- ============================================================================
-- CHAT OUTPUT (ns.ChatOutput)
-- ============================================================================

ns.ChatOutput = ns.ChatOutput or {}
local ChatOutput = ns.ChatOutput
local strupper = string.upper

---Retail often omits global GetNumChatWindows(); locals below must not call _G before this exists.
---Prefer Constants (Midnight); else legacy global; else NUM_CHAT_WINDOWS (AceTab-style).
local function GetNumChatWindows()
    local C = Constants
    if type(C) == "table" and C.ChatFrameConstants and C.ChatFrameConstants.MaxChatWindows then
        return C.ChatFrameConstants.MaxChatWindows
    end
    local g = _G.GetNumChatWindows
    if type(g) == "function" then
        return g()
    end
    return NUM_CHAT_WINDOWS or 10
end

---True if saved chat-window config lists a message group (GetChatWindowMessages return pack).
---@param winIndex number
---@param wanted string
---@return boolean
local function chatWindowIndexHasMessageGroup(winIndex, wanted)
    if type(winIndex) ~= "number" or winIndex < 1 or type(wanted) ~= "string" or wanted == "" then return false end
    local getFn = _G.GetChatWindowMessages
    if type(getFn) ~= "function" then return false end
    local wu = strupper(wanted)
    local i = 1
    while i <= 64 do
        local m = select(i, getFn(winIndex))
        if not m or m == "" then break end
        if type(m) == "string" and strupper(m) == wu then return true end
        i = i + 1
    end
    return false
end

---Must match Interface/AddOns/<this>/... (Chattynator addon filter uses this segment).
ns.CHATTYNATOR_ADDON_FOLDER = "WarbandNexus"

---Stable substring on WN-authored chat text (after color codes). Use in Chattynator
---"contains" rules; covers [WN], [WN-Currency], [WN-Reputation], [WN-TC], etc.
ns.CHAT_LINE_MARKER_PREFIX = "[WN"

---@param text string|nil
---@return boolean
function ns.IsWarbandNexusChatLine(text)
    if not text or type(text) ~= "string" then return false end
    if issecretvalue and issecretvalue(text) then return false end
    if text:find(ns.CHAT_LINE_MARKER_PREFIX, 1, true) then return true end
    if text:find("Warband Nexus", 1, true) then return true end
    return false
end

---Blizzard chat message group names (panel filter settings).
ChatOutput.MESSAGE_GROUPS = {
    LOOT = "LOOT",
    CURRENCY = "CURRENCY",
    REPUTATION = "COMBAT_FACTION_CHANGE",
    SYSTEM = "SYSTEM",
    ---Addon-registered empty group (no CHAT_MSG_*); tabs include it via AddChatWindowMessages / AddMessageGroup.
    TRYCOUNTER = "WN_TRYCOUNTER",
}

---Message group key for try-counter lines when tryCounterChatRoute == "dedicated".
local TRY_COUNTER_CHAT_GROUP = ChatOutput.MESSAGE_GROUPS.TRYCOUNTER
local tryCounterLootMirrorHooksInstalled = false

---Register empty ChatTypeGroup so AddMessageGroup / AddChatWindowMessages persist and ContainsMessageGroup works.
function ChatOutput.RegisterTryCounterChatTypeGroup()
    local g = _G.ChatTypeGroup
    if type(g) ~= "table" then return end
    if g[TRY_COUNTER_CHAT_GROUP] then return end
    g[TRY_COUNTER_CHAT_GROUP] = {}
end

---For each chat window that shows Loot, also subscribe to WN_TRYCOUNTER (dedicated mode).
function ChatOutput.EnsureTryCounterGroupOnLootWindows()
    ChatOutput.RegisterTryCounterChatTypeGroup()
    local addFn = _G.AddChatWindowMessages
    local getFn = _G.GetChatWindowMessages
    if type(addFn) ~= "function" or type(getFn) ~= "function" then return end
    local nWin = GetNumChatWindows()
    for i = 1, nWin do
        local hasLoot, hasWN = false, false
        local m = 1
        while m <= 64 do
            local v = select(m, getFn(i))
            if not v or v == "" then break end
            if v == "LOOT" then hasLoot = true end
            if v == TRY_COUNTER_CHAT_GROUP then hasWN = true end
            m = m + 1
        end
        if hasLoot and not hasWN then
            pcall(addFn, i, TRY_COUNTER_CHAT_GROUP)
        end
    end
end

function ChatOutput.InstallTryCounterLootMirrorHooks()
    if tryCounterLootMirrorHooksInstalled then return end
    if type(hooksecurefunc) ~= "function" then return end
    local origAdd = _G.AddChatWindowMessages
    local origRem = _G.RemoveChatWindowMessages
    if type(origAdd) ~= "function" or type(origRem) ~= "function" then return end
    tryCounterLootMirrorHooksInstalled = true
    hooksecurefunc("AddChatWindowMessages", function(index, group)
        if group ~= "LOOT" then return end
        local route = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile.notifications
            and WarbandNexus.db.profile.notifications.tryCounterChatRoute
        if route ~= "dedicated" then return end
        ChatOutput.RegisterTryCounterChatTypeGroup()
        pcall(origAdd, index, TRY_COUNTER_CHAT_GROUP)
    end)
    hooksecurefunc("RemoveChatWindowMessages", function(index, group)
        if group ~= "LOOT" then return end
        local route = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile.notifications
            and WarbandNexus.db.profile.notifications.tryCounterChatRoute
        if route ~= "dedicated" then return end
        pcall(origRem, index, TRY_COUNTER_CHAT_GROUP)
    end)
end

---Call when tryCounterChatRoute changes in settings (or on init).
---@param route string|nil
function ChatOutput.OnTryCounterChatRouteChanged(route)
    route = route or (WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile.notifications
        and WarbandNexus.db.profile.notifications.tryCounterChatRoute) or "loot"
    ChatOutput.RegisterTryCounterChatTypeGroup()
    if route == "dedicated" then
        ChatOutput.InstallTryCounterLootMirrorHooks()
        ChatOutput.EnsureTryCounterGroupOnLootWindows()
    end
end

---Post try-counter / WN-Drops lines; honors notifications.tryCounterChatRoute.
---@param message string
function ChatOutput.SendTryCounterMessage(message)
    if not message or type(message) ~= "string" then return end
    if issecretvalue and issecretvalue(message) then return end
    local route = "loot"
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile.notifications then
        route = WarbandNexus.db.profile.notifications.tryCounterChatRoute or "loot"
    end
    if route == "all_tabs" then
        ChatOutput.SendToAllStandardChatFrames(message)
        return
    end
    if route == "dedicated" then
        ChatOutput.RegisterTryCounterChatTypeGroup()
        ChatOutput.SendToFramesWithGroup(message, TRY_COUNTER_CHAT_GROUP)
        return
    end
    ChatOutput.SendToChatFramesMatchingLoot(message)
end

---Broadcast to every numbered ChatFrame (ignores per-tab filters). Chattynator: single-window API.
---@param message string
function ChatOutput.SendToAllStandardChatFrames(message)
    if not message or type(message) ~= "string" then return end
    if issecretvalue and issecretvalue(message) then return end
    if ChatOutput.IsChattynatorPresent() then
        ChatOutput.DeliverWithChattynatorOrFallback(message)
        return
    end
    local nWin = GetNumChatWindows()
    local sent = false
    for i = 1, nWin do
        local f = _G["ChatFrame" .. i]
        if f and f.AddMessage then
            pcall(f.AddMessage, f, message)
            sent = true
        end
    end
    if not sent then
        local fb = ChatOutput.ResolveFallbackChatFrame()
        if fb and fb.AddMessage then
            fb:AddMessage(message)
        end
    end
end

---Add WN try-counter group to the currently selected chat tab (dedicated mode setup).
---@return boolean ok
---@return string|nil err
function ChatOutput.AddTryCounterGroupToSelectedChatFrame()
    ChatOutput.RegisterTryCounterChatTypeGroup()
    local f = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if not f or type(f.AddMessageGroup) ~= "function" then
        return false, "no_chat_frame"
    end
    local ok, err = pcall(f.AddMessageGroup, f, TRY_COUNTER_CHAT_GROUP)
    if not ok then return false, tostring(err) end
    return true, nil
end

---@return boolean
function ChatOutput.IsChattynatorPresent()
    if not Utilities or not Utilities.CheckAddOnLoaded then return false end
    return Utilities:CheckAddOnLoaded("Chattynator")
end

---@return boolean
function ChatOutput.IsElvUIPresent()
    if not Utilities or not Utilities.CheckAddOnLoaded then return false end
    return Utilities:CheckAddOnLoaded("ElvUI")
end

---If true, WarbandNexus:Print picks DEFAULT_CHAT_FRAME instead of ResolveFallbackChatFrame.
---Do not use for SendToFramesWithGroup / loot routing — ElvUI tabs still map to ChatFrame1..N.
---@return boolean
function ChatOutput.ShouldRouteViaDefaultOnly()
    return ChatOutput.IsElvUIPresent()
end

---Chattynator: shim wraps API.AddMessageToWindowAndTab (upvalue addonTable on that fn) to post
---ADDON + tabTag=nil. If pcall fails, DeliverBlizzardChatFallback still prints to Blizzard frames.

---Last resort when Chattynator API fails (hidden Blizzard frames may still receive text).
---@param message string
function ChatOutput.DeliverBlizzardChatFallback(message)
    if not message or type(message) ~= "string" then return end
    if issecretvalue and issecretvalue(message) then return end
    local seen = {}
    local function tryFrame(f)
        if not f or not f.AddMessage or seen[f] then return end
        seen[f] = true
        pcall(f.AddMessage, f, message)
    end
    tryFrame(DEFAULT_CHAT_FRAME)
    tryFrame(SELECTED_CHAT_FRAME)
    local nWin = GetNumChatWindows()
    for i = 1, nWin do
        tryFrame(_G["ChatFrame" .. i])
    end
end

function WarbandNexus:EnsureChattynatorAddMessageShimInstalled()
    if self._chattynatorAddMessageShimInstalled then return end
    local api = _G.Chattynator and Chattynator.API
    if not api or type(api.AddMessageToWindowAndTab) ~= "function" then return end
    local orig = api.AddMessageToWindowAndTab
    self._chattynatorOrigAddMessageToWindowAndTab = orig
    api.AddMessageToWindowAndTab = function(wi, ti, msg, r, g, b)
        local WN = _G.WarbandNexus
        if WN and WN._wnChattynatorForceNilTabTag and type(msg) == "string" then
            WN._wnChattynatorForceNilTabTag = false
            if not (issecretvalue and issecretvalue(msg)) and debug and type(debug.getupvalue) == "function" then
                local o = WN._chattynatorOrigAddMessageToWindowAndTab
                if type(o) == "function" then
                    for i = 1, 40 do
                        local name, val = debug.getupvalue(o, i)
                        if not name then
                            break
                        end
                        if name == "addonTable" and type(val) == "table" and val.Messages
                            and type(val.Messages.SetIncomingType) == "function"
                            and type(val.Messages.AddMessage) == "function" then
                            val.Messages:SetIncomingType({
                                type = "ADDON",
                                event = "NONE",
                                source = ns.CHATTYNATOR_ADDON_FOLDER,
                                tabTag = nil,
                            })
                            val.Messages:AddMessage(msg, r, g, b)
                            return
                        end
                    end
                end
            end
        end
        return orig(wi, ti, msg, r, g, b)
    end
    self._chattynatorAddMessageShimInstalled = true
end

---@param message string
function ChatOutput.DeliverWithChattynatorOrFallback(message)
    if not message then return end
    local WN = _G.WarbandNexus
    if WN and WN.EnsureChattynatorAddMessageShimInstalled then
        WN:EnsureChattynatorAddMessageShimInstalled()
    end
    local api = _G.Chattynator and Chattynator.API
    local ok = false
    if api and type(api.AddMessageToWindowAndTab) == "function" and WN then
        WN._wnChattynatorForceNilTabTag = true
        ok = select(1, pcall(api.AddMessageToWindowAndTab, 1, 1, message, nil, nil, nil))
        WN._wnChattynatorForceNilTabTag = false
    end
    if not ok then
        ChatOutput.DeliverBlizzardChatFallback(message)
    end
end

function ChatOutput.InvalidateChattynatorAddonTableCache()
    local api = _G.Chattynator and Chattynator.API
    local WN = _G.WarbandNexus
    if api and WN and WN._chattynatorOrigAddMessageToWindowAndTab then
        api.AddMessageToWindowAndTab = WN._chattynatorOrigAddMessageToWindowAndTab
    end
    if WN then
        WN._chattynatorAddMessageShimInstalled = nil
        WN._chattynatorOrigAddMessageToWindowAndTab = nil
        WN._wnChattynatorForceNilTabTag = false
    end
end

---@param frame table|nil
---@param group string
---@return boolean
function ChatOutput.FrameHasMessageGroup(frame, group)
    if not frame or not group then return false end
    if type(frame.ContainsMessageGroup) == "function" then
        local ok, ret = pcall(frame.ContainsMessageGroup, frame, group)
        if ok and ret == true then return true end
    end
    if ChatFrame_ContainsMessageGroup then
        local ok, ret = pcall(ChatFrame_ContainsMessageGroup, frame, group)
        if ok and ret == true then return true end
    end
    local list = frame.messageTypeList
    if type(list) == "table" then
        -- Blizzard may leave holes in messageTypeList; #list stops early and misses LOOT, etc.
        for _, v in pairs(list) do
            if v == group then return true end
        end
    end
    return false
end

---True if this chat panel should show the same manual AddMessage lines as Blizzard item loot (CHAT_MSG_LOOT path).
---@param frame table|nil
---@return boolean
function ChatOutput.FrameWantsStandardLootChat(frame)
    if not frame then return false end
    if ChatOutput.FrameHasMessageGroup(frame, ChatOutput.MESSAGE_GROUPS.LOOT) then return true end
    if frame.IsEventRegistered and frame:IsEventRegistered("CHAT_MSG_LOOT") then return true end
    -- Settings UI can show Item Loot checked before the live frame’s messageTypeList updates; persisted list is authoritative.
    local id = frame.GetID and frame:GetID()
    if type(id) == "number" and id >= 1 and chatWindowIndexHasMessageGroup(id, ChatOutput.MESSAGE_GROUPS.LOOT) then
        return true
    end
    return false
end

---Like SendToFramesWithGroup(..., LOOT) but matches tabs that subscribe to CHAT_MSG_LOOT even if messageTypeList is odd.
---@param message string
function ChatOutput.SendToChatFramesMatchingLoot(message)
    if not message or type(message) ~= "string" then return end
    if issecretvalue and issecretvalue(message) then return end
    if ChatOutput.IsChattynatorPresent() then
        ChatOutput.DeliverWithChattynatorOrFallback(message)
        return
    end
    local sent = false
    local n = GetNumChatWindows()
    for i = 1, n do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.AddMessage and ChatOutput.FrameWantsStandardLootChat(frame) then
            pcall(frame.AddMessage, frame, message)
            sent = true
        end
    end
    if not sent then
        local fb = ChatOutput.ResolveFallbackChatFrame()
        if fb and fb.AddMessage then
            pcall(fb.AddMessage, fb, message)
        end
    end
end

---@param frame table|nil
---@param groups table
---@return boolean
local function frameHasAnyMessageGroup(frame, groups)
    if not frame or not groups then return false end
    for j = 1, #groups do
        if ChatOutput.FrameHasMessageGroup(frame, groups[j]) then
            return true
        end
    end
    return false
end

---When no ChatFrame has the requested message group, or DEFAULT is hidden/replaced
---(common with Chattynator / docked chat), pick a frame that can still show lines.
---@return table|nil
function ChatOutput.ResolveFallbackChatFrame()
    local function canMsg(f)
        return f and type(f.AddMessage) == "function"
    end
    local function visible(f)
        if not canMsg(f) then return false end
        if f.IsShown and not f:IsShown() then return false end
        return true
    end
    local list = {}
    local function push(f)
        if not canMsg(f) then return end
        for i = 1, #list do
            if list[i] == f then return end
        end
        list[#list + 1] = f
    end
    if type(FCF_GetSelectedChatFrame) == "function" then
        local ok, f = pcall(FCF_GetSelectedChatFrame)
        if ok then push(f) end
    end
    push(SELECTED_CHAT_FRAME)
    local nWin = GetNumChatWindows()
    for i = 1, nWin do
        push(_G["ChatFrame" .. i])
    end
    push(DEFAULT_CHAT_FRAME)
    for i = 1, #list do
        if visible(list[i]) then return list[i] end
    end
    return list[1]
end

---@param message string
---@param group string
function ChatOutput.SendToFramesWithGroup(message, group)
    if type(message) ~= "string" or type(group) ~= "string" or group == "" then return end
    if issecretvalue and issecretvalue(message) then return end
    if ChatOutput.IsChattynatorPresent() then
        ChatOutput.DeliverWithChattynatorOrFallback(message)
        return
    end
    local sent = false
    local n = GetNumChatWindows()
    for i = 1, n do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.AddMessage and ChatOutput.FrameHasMessageGroup(frame, group) then
            frame:AddMessage(message)
            sent = true
        end
    end
    if not sent then
        local fb = ChatOutput.ResolveFallbackChatFrame()
        if fb then
            fb:AddMessage(message)
        end
    end
end

---@param message string
---@param groups table
function ChatOutput.SendToFramesWithAnyGroup(message, groups)
    if type(message) ~= "string" then return end
    if issecretvalue and issecretvalue(message) then return end
    if ChatOutput.IsChattynatorPresent() then
        ChatOutput.DeliverWithChattynatorOrFallback(message)
        return
    end
    if not groups or #groups == 0 then
        local fb = ChatOutput.ResolveFallbackChatFrame()
        if fb then
            fb:AddMessage(message)
        end
        return
    end
    local sent = false
    local n = GetNumChatWindows()
    for i = 1, n do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.AddMessage and frameHasAnyMessageGroup(frame, groups) then
            frame:AddMessage(message)
            sent = true
        end
    end
    if not sent then
        local fb = ChatOutput.ResolveFallbackChatFrame()
        if fb then
            fb:AddMessage(message)
        end
    end
end

---Addon lines that should behave like system/info text (welcome, slash output).
---@param message string
function ChatOutput.SendAddonSystemLine(message)
    if not message then return end
    ChatOutput.SendToFramesWithGroup(message, ChatOutput.MESSAGE_GROUPS.SYSTEM)
end

---Currency/rep-style lines: same routing as item loot (sparse-safe list + CHAT_MSG_LOOT subscription).
ns.SendToChatFramesLootRepCurrency = function(message)
    ChatOutput.SendToChatFramesMatchingLoot(message)
end

-- ============================================================================
-- CHAT_MSG_SYSTEM — backup filter (played lines that use the event path)
-- ============================================================================

local playedTimeChatPrefixes

local function BuildPlayedTimeChatPrefixes()
    local prefixes = {}
    local seen = {}
    local function add(s)
        if not s or s == "" or seen[s] then return end
        seen[s] = true
        prefixes[#prefixes + 1] = s
    end
    local function addFromFormatKey(key)
        local g = _G[key]
        if type(g) ~= "string" or g == "" then return end
        local plain = g:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local beforeFmt = plain:match("^([^%%]+)")
        if beforeFmt and beforeFmt ~= "" then
            add(beforeFmt)
        end
    end
    addFromFormatKey("TIME_PLAYED_TOTAL")
    addFromFormatKey("TIME_PLAYED_LEVEL")
    add("Total time played")
    add("Time played this level")
    return prefixes
end

local function IsPlayedTimeSystemChatMessage(msg)
    if not msg or type(msg) ~= "string" then return false end
    if issecretvalue and issecretvalue(msg) then return false end
    if not playedTimeChatPrefixes then
        playedTimeChatPrefixes = BuildPlayedTimeChatPrefixes()
    end
    local stripped = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for i = 1, #playedTimeChatPrefixes do
        local p = playedTimeChatPrefixes[i]
        if stripped:find(p, 1, true) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- INSTALL (once)
-- ============================================================================

local playedTimeRewrapScheduled = false

local function SchedulePlayedTimeDisplayRewrap()
    if playedTimeRewrapScheduled then return end
    playedTimeRewrapScheduled = true
    C_Timer.After(0, function()
        playedTimeRewrapScheduled = false
        if WarbandNexus and WarbandNexus.RewrapPlayedTimeChatHooks then
            WarbandNexus:RewrapPlayedTimeChatHooks()
        end
    end)
end

local tconcat = table.concat

---Same shape as AceConsole:Print. Chattynator: DeliverWithChattynatorOrFallback when not explicit frame.
---@param frame table|nil
---@param addonObj table
---@param skipChattynatorAPI boolean
local function WNPrintToChatFrame(frame, addonObj, skipChattynatorAPI, ...)
    local parts = {}
    local n = 1
    parts[1] = "|cff33ff99" .. tostring(addonObj) .. "|r:"
    for i = 1, select("#", ...) do
        n = n + 1
        parts[n] = tostring(select(i, ...))
    end
    local text = tconcat(parts, " ", 1, n)
    if not skipChattynatorAPI and ns.ChatOutput and ns.ChatOutput.IsChattynatorPresent() then
        ns.ChatOutput.DeliverWithChattynatorOrFallback(text)
        return
    end
    if frame and frame.AddMessage then
        frame:AddMessage(text)
    end
end

---Prefer Chattynator API, else DEFAULT when ElvUI, else visible Blizzard frame.
function WarbandNexus:InstallChatPrintRedirect()
    if self._chatPrintRedirectInstalled then return end
    self._chatPrintRedirectInstalled = true
    if type(self.Print) ~= "function" then return end
    local basePrint = self.Print
    function WarbandNexus:Print(...)
        local first = ...
        if type(first) == "table" and first.AddMessage then
            return WNPrintToChatFrame(first, self, true, select(2, ...))
        end
        local cf = DEFAULT_CHAT_FRAME
        if ns.ChatOutput and not ns.ChatOutput.ShouldRouteViaDefaultOnly() then
            cf = ns.ChatOutput.ResolveFallbackChatFrame() or DEFAULT_CHAT_FRAME
        end
        if cf and cf.AddMessage then
            return WNPrintToChatFrame(cf, self, false, ...)
        end
        return basePrint(self, ...)
    end
end

---@return boolean
local function ShouldHidePlayedTimeInChat()
    local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not notifs or notifs.hidePlayedTimeInChat ~= false then
        return true
    end
    return false
end

---Chattynator registers TIME_PLAYED_MSG on its own Messages frame; FilterTimePlayed toggles that.
function WarbandNexus:SyncChattynatorPlayedTimeFilter()
    if not ns.ChatOutput or not ns.ChatOutput.IsChattynatorPresent() then return end
    local API = _G.Chattynator and Chattynator.API
    if not API or not API.FilterTimePlayed then return end
    pcall(API.FilterTimePlayed, ShouldHidePlayedTimeInChat())
end

---Mainline: ChatFrameMixin:SystemEventHandler → ChatFrameUtil.DisplayTimePlayed (Shared/ChatFrameUtil.lua).
function WarbandNexus:RewrapChatFrameUtil_DisplayTimePlayed()
    if not self._playedTimeDisplayHookInstalled then return end
    local util = _G.ChatFrameUtil
    if type(util) ~= "table" or type(util.DisplayTimePlayed) ~= "function" then return end
    local cur = util.DisplayTimePlayed
    if self._wnChatFrameUtilDisplayWrapper and cur == self._wnChatFrameUtilDisplayWrapper then
        return
    end
    self._wnChatFrameUtilDisplayUnderlying = cur
    if not self._wnChatFrameUtilDisplayWrapper then
        self._wnChatFrameUtilDisplayWrapper = function(chatFrame, totalTime, levelTime)
            if ShouldHidePlayedTimeInChat() then
                return
            end
            local under = WarbandNexus._wnChatFrameUtilDisplayUnderlying
            if type(under) == "function" then
                return under(chatFrame, totalTime, levelTime)
            end
        end
    end
    util.DisplayTimePlayed = self._wnChatFrameUtilDisplayWrapper
end

---Legacy global (some clients / forks); Mainline mixin calls ChatFrameUtil.DisplayTimePlayed instead.
---Returning true skips ChatFrame_DisplayTimePlayed and AddMessage entirely.
function WarbandNexus:RewrapChatFrame_SystemEventHandler()
    if not self._playedTimeDisplayHookInstalled then return end
    local cur = _G.ChatFrame_SystemEventHandler
    if type(cur) ~= "function" then return end
    if self._wnSystemEventWrapper and cur == self._wnSystemEventWrapper then
        return
    end
    self._wnSystemEventUnderlying = cur
    if not self._wnSystemEventWrapper then
        self._wnSystemEventWrapper = function(chatFrame, event, ...)
            local ev = event
            if issecretvalue and ev and issecretvalue(ev) then
                ev = nil
            end
            if ev == "TIME_PLAYED_MSG" and ShouldHidePlayedTimeInChat() then
                return true
            end
            local under = WarbandNexus._wnSystemEventUnderlying
            if type(under) == "function" then
                return under(chatFrame, event, ...)
            end
        end
    end
    _G.ChatFrame_SystemEventHandler = self._wnSystemEventWrapper
end

---Fallback: direct calls to ChatFrame_DisplayTimePlayed (bypassing system handler).
function WarbandNexus:RewrapChatFrame_DisplayTimePlayed()
    if not self._playedTimeDisplayHookInstalled then return end
    local cur = _G.ChatFrame_DisplayTimePlayed
    if type(cur) ~= "function" then return end
    if self._wnPlayedTimeWrapper and cur == self._wnPlayedTimeWrapper then
        return
    end
    self._wnPlayedTimeUnderlying = cur
    if not self._wnPlayedTimeWrapper then
        self._wnPlayedTimeWrapper = function(cfSelf, totalTime, levelTime)
            if ShouldHidePlayedTimeInChat() then
                return
            end
            local under = WarbandNexus._wnPlayedTimeUnderlying
            if type(under) == "function" then
                return under(cfSelf, totalTime, levelTime)
            end
        end
    end
    _G.ChatFrame_DisplayTimePlayed = self._wnPlayedTimeWrapper
end

function WarbandNexus:RewrapPlayedTimeChatHooks()
    self:RewrapChatFrameUtil_DisplayTimePlayed()
    self:RewrapChatFrame_SystemEventHandler()
    self:RewrapChatFrame_DisplayTimePlayed()
end

function WarbandNexus:InstallPlayedTimeDisplayHook()
    if self._playedTimeDisplayHookInstalled then return end
    self._playedTimeDisplayHookInstalled = true

    self:RewrapPlayedTimeChatHooks()

    if not self._playedTimeDisplayEventFrame then
        local ev = CreateFrame("Frame")
        self._playedTimeDisplayEventFrame = ev
        ev:RegisterEvent("ADDON_LOADED")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:SetScript("OnEvent", function(_, event, addOnName)
            if event == "ADDON_LOADED" then
                if addOnName == "Chattynator" then
                    if ns.ChatOutput and ns.ChatOutput.InvalidateChattynatorAddonTableCache then
                        ns.ChatOutput.InvalidateChattynatorAddonTableCache()
                    end
                    if WarbandNexus.SyncChattynatorPlayedTimeFilter then
                        WarbandNexus:SyncChattynatorPlayedTimeFilter()
                    end
                end
                SchedulePlayedTimeDisplayRewrap()
            elseif event == "PLAYER_ENTERING_WORLD" then
                SchedulePlayedTimeDisplayRewrap()
                if WarbandNexus.SyncChattynatorPlayedTimeFilter then
                    WarbandNexus:SyncChattynatorPlayedTimeFilter()
                end
                if ns.ChatOutput and ns.ChatOutput.OnTryCounterChatRouteChanged then
                    ns.ChatOutput.OnTryCounterChatRouteChanged()
                end
            end
        end)
    end
end

---One short welcome line per session (Chattynator / custom chat — uses SYSTEM group + visible fallback).
function WarbandNexus:PrintSessionLoginChat()
    if self._sessionLoginChatPrinted then return end
    local notifs = self.db and self.db.profile and self.db.profile.notifications
    if not notifs or not notifs.enabled or notifs.showLoginChat == false then return end
    if not ns.ChatOutput or not ns.ChatOutput.SendAddonSystemLine then return end
    self._sessionLoginChatPrinted = true
    local v = Constants and Constants.ADDON_VERSION or ""
    local L = ns.L
    local fmt = string.format
    local main = fmt((L and L["WELCOME_MSG_FORMAT"]) or "Welcome to Warband Nexus v%s", v)
    local cmdHint = fmt("%s |cffffff00/wn|r %s",
        (L and L["WELCOME_TYPE_CMD"]) or "Type",
        (L and L["WELCOME_OPEN_INTERFACE"]) or "to open the interface.")
    local line = "|cff9966ff[Warband Nexus]|r " .. main .. " " .. cmdHint
    if self.IsNewVersion and self:IsNewVersion() and notifs.showUpdateNotes then
        line = line .. " " .. ((L and L["WELCOME_NEW_VERSION_CHAT"]) or "|cffffff00What's New:|r popup may appear, or |cffffff00/wn changelog|r.")
    end
    ns.ChatOutput.SendAddonSystemLine(line)
    -- One plain sentence after GUID-backed character storage: no technical terms for players.
    local g = self.db and self.db.global
    if g and g.charactersGuidKeyedV1 and not g._wnCharacterLinkHintShown then
        g._wnCharacterLinkHintShown = true
        local hint = (L and L["CHARACTER_LINK_HINT_CHAT"])
            or "Your saved data was kept. If something looks wrong in the panel, type |cffffff00/reload|r once."
        ns.ChatOutput.SendAddonSystemLine("|cff9966ff[Warband Nexus]|r " .. hint)
    end
end

function WarbandNexus:InitializeChatIntegration()
    if self._chatIntegrationInitialized then return end
    self._chatIntegrationInitialized = true

    self:InstallChatPrintRedirect()
    self:InstallPlayedTimeDisplayHook()
    if self.SyncChattynatorPlayedTimeFilter then
        self:SyncChattynatorPlayedTimeFilter()
    end

    if not ChatFrame_AddMessageEventFilter then return end

    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg, ...)
        local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
        if IsPlayedTimeSystemChatMessage(msg) then
            if notifs and notifs.hidePlayedTimeInChat == false then
                return false, msg, ...
            end
            return true
        end
        return false, msg, ...
    end)

    ChatFrame_AddMessageEventFilter("CHAT_MSG_COMBAT_FACTION_CHANGE", function(_, _, msg, ...)
        local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
        local tracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(WarbandNexus)
        if tracked and notifs and notifs.enabled and notifs.showReputationGains then
            return true
        end
        return false, msg, ...
    end)

    ChatFrame_AddMessageEventFilter("CHAT_MSG_CURRENCY", function(_, _, msg, ...)
        if ns.CharacterService and ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            if ns.CurrencyCache and ns.CurrencyCache.OnCurrencyChatSignal then
                ns.CurrencyCache:OnCurrencyChatSignal()
            end
        end
        local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
        local tracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(WarbandNexus)
        if tracked and notifs and notifs.enabled and notifs.showCurrencyGains then
            return true
        end
        return false, msg, ...
    end)

    if ns.ChatOutput and ns.ChatOutput.OnTryCounterChatRouteChanged then
        ns.ChatOutput.OnTryCounterChatRouteChanged()
    end
end

---Settings UI / Config still call this after toggles; filters read db live.
function WarbandNexus:UpdateChatFilter()
    if not self._chatIntegrationInitialized then
        self:InitializeChatIntegration()
    end
    if self.SyncChattynatorPlayedTimeFilter then
        self:SyncChattynatorPlayedTimeFilter()
    end
end

---Backward-compatible name (was ChatFilter.lua).
function WarbandNexus:InitializeChatFilter()
    self:InitializeChatIntegration()
end
