--[[
    Plan type + reminder territory hints for consistent geography wording across Plans UI / tooltips.

    Uses ns.UIMapContentKind.Resolve (C_Map + EJ) — see Modules/Data/UIMapContentKind.lua.
]]

local ADDON_NAME, ns = ...
local format = string.format

ns.PlanGeography = ns.PlanGeography or {}

local GEO_LOCALE_FALLBACK = {
    weekly_vault = "Weekly Vault pools (raid · dungeon · world)",
    daily_quests = "Weekly activity / quests",
    achievement = "Achievements",
    mount = "Collections",
    pet = "Collections",
    toy = "Collections",
    transmog = "Collections",
    recipe = "Professions",
    illusion = "Collections",
    title = "Collections",
    custom = "Custom plan",
}

local GEO_LOCALE_KEY = {
    weekly_vault = "PLAN_GEO_BUCKET_WEEKLY_VAULT",
    daily_quests = "PLAN_GEO_BUCKET_WEEKLY_ACTIVITY",
    achievement = "PLAN_GEO_BUCKET_ACHIEVEMENT",
    mount = "PLAN_GEO_BUCKET_COLLECTION",
    pet = "PLAN_GEO_BUCKET_COLLECTION",
    toy = "PLAN_GEO_BUCKET_COLLECTION",
    transmog = "PLAN_GEO_BUCKET_COLLECTION",
    recipe = "PLAN_GEO_BUCKET_PROFESSION",
    illusion = "PLAN_GEO_BUCKET_COLLECTION",
    title = "PLAN_GEO_BUCKET_COLLECTION",
    custom = "PLAN_GEO_BUCKET_CUSTOM",
}

---@param planType string|nil
---@return string|nil human-readable coarse bucket (localized when available)
local function DescribePlanTypeBucket(planType)
    if not planType or planType == "" then return nil end
    local L = ns.L
    local key = GEO_LOCALE_KEY[planType]
    if key and L and L[key] then return L[key] end
    return GEO_LOCALE_FALLBACK[planType]
end

local function SortMapIDs(mapIDs)
    local out = {}
    if not mapIDs then return out end
    for mid in pairs(mapIDs) do
        local n = tonumber(mid)
        if n and n > 0 then out[#out + 1] = n end
    end
    table.sort(out)
    return out
end

---Optional second tooltip line summarizing coarse plan geography + gated zone/instance rows.
---@param plan table|nil AceDB-backed plan row
---@param tooltipLines table[] array of | { text = string } lines
function ns.PlanGeography.AppendReminderTerritoryTooltipLine(plan, tooltipLines)
    if not plan or not tooltipLines or not plan.reminder then return end

    local r = plan.reminder
    if not r.enabled then return end

    local parts = {}

    local base = DescribePlanTypeBucket(plan.type)
    if base and base ~= "" then
        parts[#parts + 1] = "|cffcfd5e0" .. base .. "|r"
    end

    if r.onZoneEnter and r.mapIDs then
        local ids = SortMapIDs(r.mapIDs)
        local UICK = ns.UIMapContentKind
        local maxShow = 2
        local shown = 0
        for i = 1, #ids do
            local summary = UICK and UICK.FormatGeographySummary and UICK.FormatGeographySummary(ids[i])
            if summary and summary ~= "" then
                parts[#parts + 1] = summary
                shown = shown + 1
                if shown >= maxShow then break end
            end
        end
        if #ids > maxShow then
            local ell = (ns.L and ns.L["PLAN_GEO_ELLIPSIS"]) or "…"
            parts[#parts + 1] = "|cffaaaaaa" .. ell .. "|r"
        end
    end

    if r.onInstanceEnter and r.instanceReminder and tonumber(r.instanceReminder.instanceID) then
        local iid = tonumber(r.instanceReminder.instanceID)
        local L = ns.L
        parts[#parts + 1] = format((L and L["PLAN_GEO_INSTANCE_GATE"]) or "Instance gate: #%s", tostring(iid))
    end

    if #parts > 0 then
        tooltipLines[#tooltipLines + 1] = {
            text = table.concat(parts, "  |  "),
        }
    end
end
