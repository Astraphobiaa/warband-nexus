--[[
    Warband Nexus - Reminder Set Alert dialog helpers (no frame wiring).
    Split from ReminderSetAlertDialog.lua (Lua 5.1 local limit).
    Loaded immediately before Modules/UI/ReminderSetAlertDialog.lua.
]]

local _, ns = ...
local issecretvalue = issecretvalue

local H = {}
ns.ReminderSetAlertDialogHelpers = H

--- Positive integer from edit box; never tonumber() on secret GetText() (Midnight).
function H.SafePositiveIntFromMapEdit(edit)
    if not edit or not edit.GetText then return nil end
    local raw = edit:GetText()
    if raw == nil then return nil end
    if issecretvalue and issecretvalue(raw) then return nil end
    if raw == "" then return nil end
    local n = tonumber(raw)
    if not n or n <= 0 then return nil end
    return n
end

function H.BindCatalogMouseWheel(scrollFrame)
    if not scrollFrame or not scrollFrame.SetScript then return end
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = (ns.UI_GetScrollStep and ns.UI_GetScrollStep())
            or ((ns.UI_LAYOUT or ns.UI_SPACING or {}).SCROLL_BASE_STEP or 28)
        local cur = self:GetVerticalScroll() or 0
        local mx = self:GetVerticalScrollRange() or 0
        local nv = cur - delta * step
        if nv < 0 then nv = 0 end
        if nv > mx then nv = mx end
        self:SetVerticalScroll(nv)
    end)
end

function H.TruncatePickerLabel(str, maxLen)
    if not str then return "" end
    maxLen = maxLen or 52
    if #str <= maxLen then return str end
    return str:sub(1, maxLen - 1) .. "…"
end

function H.LocaleOr(L, key, fallback)
    if not key or key == "" then return fallback or "" end
    local v = L and L[key]
    if v and v ~= key then return v end
    return fallback or key
end

function H.ManualRowTagText(mapID)
    local UICK = ns.UIMapContentKind
    if UICK and UICK.Resolve and UICK.FormatPickerTag then
        if UICK.EnsureJournalLoaded then UICK.EnsureJournalLoaded() end
        local kind = UICK.Resolve(tonumber(mapID))
        return UICK.FormatPickerTag(kind)
    end
    local Lz = ns.L
    return (Lz and Lz["REMINDER_ZONE_CAT_TAG_ZONE"]) or "[Z]"
end
