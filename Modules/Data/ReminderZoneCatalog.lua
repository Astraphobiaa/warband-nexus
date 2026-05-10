--[[
    Set Alert → zone picker: expansion sections grouped by live content kind (Interface 120005+).

    Classification: Modules/Data/UIMapContentKind.lua — Enum.UIMapType + Encounter Journal
    (EJ_GetInstanceForMap → EJ_GetInstanceInfo … isRaid; see warcraft.wiki.gg/API_EJ_GetInstanceForMap).
    Curated picker ids (Midnight, The War Within, Dragonflight): Modules/Data/ReminderContentIndex.lua (single source; duplicate-checked).

    Map tree: recursive C_Map.GetMapChildrenInfo under each apiRoot (depth-capped). Sections with
    pickerGroups try curated lists first; if that yields no rows but apiRoots is set, **BFS subtree**
    runs as a fallback (accurate data preferred; tree covers API/name oddities during login).

    Curated IDs merged when missing. Duplicate names collapse to one "main" uiMapID where applicable.

    Midnight / The War Within / Dragonflight / Shadowlands / BfA / Legion / WoD / MoP / Cataclysm / Wrath /
    BC / Kalimdor / Eastern Kingdoms pickerGroups are filled from ReminderContentIndex (single source).

    Midnight pickerGroups: one canonical uiMapID per location (entrance / main floor only) — no extra
    raid wings, delve upper/lower pairs, or dungeon layer duplicates in the list.

    Validation (Midnight): ids checked against live UiMap parent chain under apiRoot 2537 (Quel'Thalas);
    picker rows use C_Map.GetMapInfo at runtime — unknown ids simply omit from the list. Delve instances are
    often UIMapType.Dungeon in the client; UIMapContentKind.Resolve maps curated delve UiMapIDs to kind delve.
    Silvermoon City (2393) dungeons use parent 2393 → 2395 → 2537 (no separate region row).

    Cataclysm: no apiRoots — GetDisplayRowsForSection uses GetDisplayRowsForSectionStatic (pickerGroups only).
    Kalimdor / Eastern Kingdoms: continent apiRoots 12 / 13; picker rows include continent-local Classic
    instances only when their uiMapID is globally unique in ReminderContentIndex (see index header).

    Reminder zone_enter matching compares ReminderContentIndex.NormalizeToCanonicalPickerMap(current and saved IDs).

    Rows are filtered by walking parentMapID: must reach an apiRoot before Cosmic/World or any
    Continent not listed in apiRoots (drops cross-branch maps that share intermediate continents).
    Within each content group, rows sort large→small: shallower BFS depth from apiRoots first,
    then UIMapType scale (continent → zone → micro → …), then name.
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

---@class ReminderZoneCatalogSection
---@field localeKey string
---@field apiRoots number[]|nil Continent / hub uiMapIDs — subtree merged for API-driven lists
---@field maps number[]|nil Fallback open-world uiMapIDs
---@field instances number[]|nil Fallback dungeon & raid maps
---@field relatedMaps number[]|nil Fallback related pockets
---@field pickerGroups { headerKey: string, kindTag: string, ids: (number|{ id: number, hint: string })[] }[]|nil

local catalog = {
    sections = {
        {
            localeKey = "REMINDER_ZONE_CAT_MIDNIGHT",
            -- Quel'Thalas only (2537). pickerGroups filled from ReminderContentIndex after table build.
            apiRoots = { 2537 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_TWW",
            -- Picker rows: ReminderContentIndex (TWW). apiRoots must cover parent chains for all indexed ids.
            apiRoots = { 2248, 2214, 2215, 2255, 2339, 2371, 2346, 2396, 2369 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_DRAGONFLIGHT",
            -- Picker rows: ReminderContentIndex (Dragonflight).
            apiRoots = { 1978 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_SHADOWLANDS",
            apiRoots = { 1550 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_BFA",
            apiRoots = { 876, 875, 1355, 1462, 81, 13, 1527 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_LEGION",
            apiRoots = { 619, 13 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_WOD",
            apiRoots = { 572 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_MOP",
            apiRoots = { 424, 13 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_CATA",
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_WRATH",
            apiRoots = { 113 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_BC",
            apiRoots = { 101 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_KALIMDOR",
            apiRoots = { 12 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
        {
            localeKey = "REMINDER_ZONE_CAT_EASTERN_KINGDOMS",
            apiRoots = { 13 },
            pickerGroups = nil,
            maps = {},
            instances = {},
            relatedMaps = {},
        },
    },
}

local apiRowCache = {}

function catalog.InvalidateZoneApiCache()
    apiRowCache = {}
    if ns.UIMapContentKind and ns.UIMapContentKind.InvalidateCache then
        ns.UIMapContentKind.InvalidateCache()
    end
end

local UIMapType = Enum and Enum.UIMapType

local MAP_TREE_MAX_DEPTH = 48

local function mergeTreeDepth(depthOut, mapID, depth)
    if not depthOut then return end
    local mid = tonumber(mapID)
    if not mid then return end
    local prev = depthOut[mid]
    if not prev or depth < prev then
        depthOut[mid] = depth
    end
end

local function getParentMapId(mid)
    local id = tonumber(mid)
    if not id or id <= 0 or not C_Map or not C_Map.GetMapInfo then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if not ok or not info then return nil end
    local p = tonumber(info.parentMapID)
    if not p or p <= 0 or p == id then return nil end
    return p
end

--- Collect root + all reachable descendant map IDs (BFS), depth-limited — single-level walks miss nested dungeons.
--- Drops GetMapChildrenInfo edges whose parentMapID does not match the BFS parent (cross-branch API junk).
--- depthOut: optional min BFS depth from this invocation's root (merged across multiple roots by caller).
local function gatherDescendantIds(rootID, into, depthOut)
    if not rootID or rootID <= 0 or not C_Map or not C_Map.GetMapChildrenInfo then return end
    local rid = tonumber(rootID)
    if not rid or rid <= 0 then return end
    local queue = { rid }
    local depthAt = { [rid] = 0 }
    local qh = 1
    while qh <= #queue do
        local id = queue[qh]
        qh = qh + 1
        if id and id > 0 then
            into[id] = true
            local d = depthAt[id] or 0
            mergeTreeDepth(depthOut, id, d)
            if d < MAP_TREE_MAX_DEPTH then
                local ok, children = pcall(C_Map.GetMapChildrenInfo, id, nil, true)
                if not ok or type(children) ~= "table" then
                    ok, children = pcall(C_Map.GetMapChildrenInfo, id)
                end
                if ok and type(children) == "table" then
                    for i = 1, #children do
                        local ch = children[i]
                        local cid = ch and tonumber(ch.mapID)
                        if cid and cid > 0 and cid ~= id then
                            local pc = getParentMapId(cid)
                            local parentOk = (d == 0 and pc == rid) or (d > 0 and pc == id)
                            if parentOk then
                                local nd = d + 1
                                if depthAt[cid] == nil or nd < depthAt[cid] then
                                    depthAt[cid] = nd
                                    queue[#queue + 1] = cid
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function sortNamedEntries(entries)
    table.sort(entries, function(a, b)
        local na = (a.name or ""):lower()
        local nb = (b.name or ""):lower()
        if na ~= nb then return na < nb end
        return (a.id or 0) < (b.id or 0)
    end)
end

--- Larger map scope first: smaller BFS depth from apiRoots, then coarser UIMapType, then name.
local function mapTypeLargeToSmallRank(mt)
    if not UIMapType or not mt then return 50 end
    if mt == UIMapType.Cosmic then return -2 end
    if mt == UIMapType.World then return -1 end
    if mt == UIMapType.Continent then return 0 end
    if mt == UIMapType.Zone then return 1 end
    if mt == UIMapType.Micro then return 2 end
    if mt == UIMapType.Dungeon then return 3 end
    if mt == UIMapType.Orphan then return 4 end
    return 10
end

local function sortEntriesByHierarchyDepth(entries, depthById)
    if not entries or #entries < 2 then return end
    table.sort(entries, function(a, b)
        local da = (depthById and depthById[a.id]) or 99999
        local db = (depthById and depthById[b.id]) or 99999
        if da ~= db then return da < db end
        local ra = mapTypeLargeToSmallRank(a.mapType)
        local rb = mapTypeLargeToSmallRank(b.mapType)
        if ra ~= rb then return ra < rb end
        local na = (a.name or ""):lower()
        local nb = (b.name or ""):lower()
        if na ~= nb then return na < nb end
        return (a.id or 0) < (b.id or 0)
    end)
end

--- Walk parentMapID until a UIMapType.Zone (nil if none).
local function firstZoneAncestorMapId(fromId)
    local id = tonumber(fromId)
    if not id or id <= 0 or not C_Map or not C_Map.GetMapInfo or not UIMapType then return nil end
    local guard = 0
    while id and id > 0 and guard < 64 do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if not ok or not info then return nil end
        if info.mapType == UIMapType.Zone then
            return id
        end
        local p = tonumber(info.parentMapID)
        if not p or p <= 0 or p == id then return nil end
        id = p
        guard = guard + 1
    end
    return nil
end

--- True if walking parentMapID hits an apiRoot before Cosmic/World or any Continent not in apiRoots.
--- Stops Midnight (etc.) from listing maps that only share a higher continent / world node with the tree.
local function uiMapStructuredUnderRoots(mid, apiRoots)
    if not apiRoots or #apiRoots == 0 then return true end
    local rootSet = {}
    for i = 1, #apiRoots do
        local r = tonumber(apiRoots[i])
        if r then rootSet[r] = true end
    end
    local id = tonumber(mid)
    if not id or id <= 0 then return false end
    local seen = {}
    local guard = 0
    while id and id > 0 and guard < 96 do
        if seen[id] then return false end
        seen[id] = true
        if rootSet[id] then return true end
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if not ok or not info then return false end
        if UIMapType then
            local mt = info.mapType
            if mt == UIMapType.Cosmic or mt == UIMapType.World then
                return false
            end
            if mt == UIMapType.Continent and not rootSet[id] then
                return false
            end
        end
        local p = tonumber(info.parentMapID)
        if not p or p <= 0 or p == id then return false end
        id = p
        guard = guard + 1
    end
    return false
end

local function treeDepthToNearestRoot(mid, apiRoots)
    if not apiRoots or #apiRoots == 0 then return 0 end
    local rootSet = {}
    for i = 1, #apiRoots do
        local r = tonumber(apiRoots[i])
        if r then rootSet[r] = true end
    end
    local steps = 0
    local seen = {}
    local id = tonumber(mid)
    local guard = 0
    while id and id > 0 and guard < 96 do
        if seen[id] then return 99999 end
        seen[id] = true
        if rootSet[id] then return steps end
        local p = getParentMapId(id)
        if not p then return 99999 end
        id = p
        steps = steps + 1
        guard = guard + 1
    end
    return 99999
end

--- Must appear after treeDepthToNearestRoot (Lua 5.1 local visibility — no forward refs).
local function ensureDepthForEntries(list, depthById, apiRoots)
    if not depthById or not apiRoots or #apiRoots == 0 then return end
    for i = 1, #list do
        local id = list[i].id
        if id and depthById[id] == nil then
            depthById[id] = treeDepthToNearestRoot(id, apiRoots)
        end
    end
end

--- Cosmic/World never; Continent only when it is this section's apiRoot (e.g. Quel'Thalas hub).
local function isReasonableCollapseTarget(mapId, apiRoots)
    if not mapId or mapId <= 0 or not UIMapType then return false end
    local ok, info = pcall(C_Map.GetMapInfo, mapId)
    if not ok or not info then return false end
    local mt = info.mapType
    if mt == UIMapType.Cosmic or mt == UIMapType.World then
        return false
    end
    if mt == UIMapType.Continent then
        if apiRoots then
            for i = 1, #apiRoots do
                if tonumber(apiRoots[i]) == mapId then
                    return true
                end
            end
        end
        return false
    end
    return true
end

local function pathFromNodeToRoot(mid)
    local path = {}
    local id = tonumber(mid)
    local g = 0
    while id and id > 0 and g < 64 do
        path[#path + 1] = id
        local p = getParentMapId(id)
        if not p or p == id then break end
        id = p
        g = g + 1
    end
    return path
end

local function lcaOfTwoMapIds(a, b)
    local pa = pathFromNodeToRoot(a)
    local pb = pathFromNodeToRoot(b)
    local setB = {}
    for i = 1, #pb do
        setB[pb[i]] = true
    end
    for i = 1, #pa do
        if setB[pa[i]] then
            return pa[i]
        end
    end
    return nil
end

local function lcaOfMapIdGroup(ids)
    if not ids or #ids == 0 then return nil end
    if #ids == 1 then return ids[1] end
    local acc = ids[1]
    for i = 2, #ids do
        acc = lcaOfTwoMapIds(acc, ids[i])
        if not acc then return nil end
    end
    return acc
end

--- One picker row per display name: LCA of all duplicate uiMapIDs (covers split wings / revisit IDs),
--- else shared parent, else smallest mapID as last resort. Never pick an ID outside this section's roots.
local function chooseMainMapIdForSameNameGroup(grp, apiRoots)
    local rootsFiltered = apiRoots and #apiRoots > 0
    local function structuredOk(mid)
        if not rootsFiltered then return true end
        return uiMapStructuredUnderRoots(mid, apiRoots)
    end
    local ids = {}
    for j = 1, #grp do
        ids[#ids + 1] = grp[j].id
    end
    local lca = lcaOfMapIdGroup(ids)
    if lca and structuredOk(lca) and isReasonableCollapseTarget(lca, apiRoots) then
        return lca
    end
    local p0 = getParentMapId(grp[1].id)
    local sameParent = p0 ~= nil
    if sameParent then
        for j = 2, #grp do
            if getParentMapId(grp[j].id) ~= p0 then
                sameParent = false
                break
            end
        end
    end
    if sameParent and p0 and structuredOk(p0) and isReasonableCollapseTarget(p0, apiRoots) then
        return p0
    end
    local best = nil
    for j = 1, #ids do
        if structuredOk(ids[j]) then
            if not best or ids[j] < best then
                best = ids[j]
            end
        end
    end
    return best
end

local function collapseDuplicateNamesToSingleMainRow(entries, apiRoots)
    if not entries or #entries == 0 then return entries end
    if #entries < 2 then return entries end
    local byName = {}
    for i = 1, #entries do
        local e = entries[i]
        local k = (e.name or ""):lower()
        if k == "" then
            k = "\0id:" .. tostring(e.id)
        end
        local g = byName[k]
        if not g then
            g = {}
            byName[k] = g
        end
        g[#g + 1] = e
    end
    local keys = {}
    for k in pairs(byName) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local out = {}
    local L = ns.L
    local suffix = (L and L["REMINDER_ZONE_MAIN_MAP_SUFFIX"]) or "main map"
    for ki = 1, #keys do
        local grp = byName[keys[ki]]
        if #grp < 2 then
            out[#out + 1] = grp[1]
        else
            local mainId = chooseMainMapIdForSameNameGroup(grp, apiRoots)
            if not mainId then
                for j = 1, #grp do
                    out[#out + 1] = grp[j]
                end
            else
                local okp, pinfo = pcall(C_Map.GetMapInfo, mainId)
                if okp and pinfo and pinfo.name and pinfo.name ~= ""
                    and not (issecretvalue and issecretvalue(pinfo.name)) then
                    out[#out + 1] = {
                        id = mainId,
                        name = grp[1].name,
                        mapType = pinfo.mapType,
                        displayName = (grp[1].name or "") .. " — " .. suffix,
                    }
                else
                    for j = 1, #grp do
                        out[#out + 1] = grp[j]
                    end
                end
            end
        end
    end
    return out
end

--- Same display name for multiple uiMapIDs → disambiguate with id (rare client duplicates).
local function disambiguateDuplicateNames(entries)
    if not entries or #entries < 2 then return end
    local counts = {}
    for i = 1, #entries do
        local k = (entries[i].name or ""):lower()
        counts[k] = (counts[k] or 0) + 1
    end
    for i = 1, #entries do
        local k = (entries[i].name or ""):lower()
        if counts[k] and counts[k] > 1 then
            -- Duplicate localized names: row still shows trailing "— id" in UI; avoid repeating #id in the label.
            entries[i].displayName = entries[i].name
        end
    end
end

-- Content headers large→small: regions / overworld / pockets, then instances (see UIMapContentKind.lua).
local ORDERED_KINDS = {
    "continent", "zone", "micro", "raid", "dungeon", "delve", "scenario", "orphan", "unknown",
}

local HEADER_FOR_KIND = {
    raid = "REMINDER_ZONE_CATALOG_RAIDS",
    dungeon = "REMINDER_ZONE_CATALOG_DUNGEONS",
    delve = "REMINDER_ZONE_CATALOG_DELVES",
    zone = "REMINDER_ZONE_CATALOG_OPEN_WORLD",
    micro = "REMINDER_ZONE_CATALOG_AREAS",
    orphan = "REMINDER_ZONE_CATALOG_SCENARIOS",
    scenario = "REMINDER_ZONE_CATALOG_SCENARIOS",
    continent = "REMINDER_ZONE_CATALOG_REGIONS",
    unknown = "REMINDER_ZONE_CATALOG_OTHER",
}

local function newBuckets()
    return {
        raid = {},
        dungeon = {},
        delve = {},
        zone = {},
        micro = {},
        orphan = {},
        scenario = {},
        continent = {},
        unknown = {},
    }
end

--- Emit section headers + rows (collapse / disambiguate already applied per bucket).
local function appendDisplayRowsFromBucketsNoCollapse(buckets, depthById)
    local rows = {}
    for _, k in ipairs(ORDERED_KINDS) do
        local list = buckets[k]
        if list and #list > 0 then
            sortEntriesByHierarchyDepth(list, depthById)
            disambiguateDuplicateNames(list)
            local hk = HEADER_FOR_KIND[k]
            if hk then
                rows[#rows + 1] = { headerKey = hk }
            end
            for i = 1, #list do
                local e = list[i]
                rows[#rows + 1] = { id = e.id, kind = k, displayName = e.displayName or e.name }
            end
        end
    end
    return rows
end

--- Drop rows that slipped past BFS/collapse; strip headers that would have no rows after filter.
local function filterDisplayRowsForExpansionRoots(rows, roots)
    if not roots or #roots == 0 or not rows then return rows end
    local tmp = {}
    for i = 1, #rows do
        local r = rows[i]
        if r.headerKey then
            tmp[#tmp + 1] = r
        elseif r.id and uiMapStructuredUnderRoots(r.id, roots) then
            tmp[#tmp + 1] = r
        end
    end
    local out = {}
    local pendingHeader = nil
    for i = 1, #tmp do
        local r = tmp[i]
        if r.headerKey then
            pendingHeader = r
        elseif r.id then
            if pendingHeader then
                out[#out + 1] = pendingHeader
                pendingHeader = nil
            end
            out[#out + 1] = r
        end
    end
    return out
end

--- Fixed expansion grouping (Midnight): explicit ids + header order; optional hint disambiguates layered maps.
local function appendPickerGroupRows(rows, apiRoots, headerKey, kindTag, ids)
    if not ids or #ids == 0 or not headerKey then return end
    local bucket = {}
    for i = 1, #ids do
        local raw = ids[i]
        local mid, hint
        if type(raw) == "table" and raw.id then
            mid = tonumber(raw.id)
            hint = raw.hint
        else
            mid = tonumber(raw)
        end
        if mid and mid > 0 then
            if #apiRoots == 0 or uiMapStructuredUnderRoots(mid, apiRoots) then
                local ok, info = pcall(C_Map.GetMapInfo, mid)
                if ok and info and info.name and info.name ~= ""
                    and not (issecretvalue and issecretvalue(info.name)) then
                    local base = info.name
                    local disp = base
                    if hint and hint ~= "" then
                        disp = base .. " — " .. hint
                    end
                    local UICK = ns.UIMapContentKind
                    if UICK and UICK.EnsureJournalLoaded then UICK.EnsureJournalLoaded() end
                    local rk = nil
                    if UICK and UICK.Resolve then
                        rk = UICK.Resolve(mid, info)
                    end
                    if not rk or rk == "" then
                        rk = kindTag or "unknown"
                    end
                    bucket[#bucket + 1] = { id = mid, name = disp, kind = rk }
                end
            end
        end
    end
    if #bucket == 0 then return end
    rows[#rows + 1] = { headerKey = headerKey }
    for j = 1, #bucket do
        local e = bucket[j]
        rows[#rows + 1] = { id = e.id, kind = e.kind, displayName = e.name }
    end
end

local function buildRowsFromPickerGroups(sectionIndex)
    local sec = catalog.sections[sectionIndex]
    if not sec or not sec.pickerGroups or #sec.pickerGroups == 0 then return nil end
    if not C_Map or not C_Map.GetMapInfo then return nil end
    local roots = sec.apiRoots or {}
    local rows = {}
    for gi = 1, #sec.pickerGroups do
        local g = sec.pickerGroups[gi]
        if g and g.headerKey and g.ids then
            appendPickerGroupRows(rows, roots, g.headerKey, g.kindTag or "unknown", g.ids)
        end
    end
    return filterDisplayRowsForExpansionRoots(rows, roots)
end

--- Collapse duplicate names per preliminary bucket, then re-resolve each row's uiMapID so the
--- Encounter Journal–accurate kind matches the final ID (parent collapse can change map type).
local function finalizeCatalogBuckets(buckets, roots, depthById)
    local UICK = ns.UIMapContentKind
    local combined = {}
    for _, k in ipairs(ORDERED_KINDS) do
        local list = buckets[k]
        if list and #list > 0 then
            sortEntriesByHierarchyDepth(list, depthById)
            list = collapseDuplicateNamesToSingleMainRow(list, roots)
            ensureDepthForEntries(list, depthById, roots)
            sortEntriesByHierarchyDepth(list, depthById)
            disambiguateDuplicateNames(list)
            for i = 1, #list do
                combined[#combined + 1] = list[i]
            end
        end
    end
    local outBuckets = newBuckets()
    for i = 1, #combined do
        local e = combined[i]
        local rk = UICK.Resolve(e.id)
        if rk == "cosmic" or rk == "world" then
            rk = "unknown"
        end
        local t = outBuckets[rk]
        if t then
            t[#t + 1] = e
        end
    end
    local rows = appendDisplayRowsFromBucketsNoCollapse(outBuckets, depthById)
    return filterDisplayRowsForExpansionRoots(rows, roots)
end

local function buildApiRowsForSection(sectionIndex)
    local sec = catalog.sections[sectionIndex]
    if not sec or not sec.apiRoots or #sec.apiRoots == 0 then return nil end
    if apiRowCache[sectionIndex] then return apiRowCache[sectionIndex] end

    if sec.pickerGroups and #sec.pickerGroups > 0 then
        local custom = buildRowsFromPickerGroups(sectionIndex)
        if custom and #custom > 0 then
            apiRowCache[sectionIndex] = custom
            return custom
        end
        -- Picker empty (e.g. C_Map timing): fall through to BFS when apiRoots are configured.
    end

    if not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapChildrenInfo then return nil end

    local UICK = ns.UIMapContentKind
    if not UICK or not UICK.Resolve then return nil end
    if UICK.EnsureJournalLoaded then UICK.EnsureJournalLoaded() end

    local allIds = {}
    local depthById = {}
    for ri = 1, #sec.apiRoots do
        local rid = tonumber(sec.apiRoots[ri])
        if rid then gatherDescendantIds(rid, allIds, depthById) end
    end

    local zoneTypeInSubtree = {}
    local buckets = newBuckets()

    for mid in pairs(allIds) do
        if not uiMapStructuredUnderRoots(mid, sec.apiRoots) then
            -- Stray cross-branch links (wrong continent / shared world layer before apiRoots).
        else
        local ok, info = pcall(C_Map.GetMapInfo, mid)
        if ok and info and info.name and info.name ~= "" and not (issecretvalue and issecretvalue(info.name)) then
            if UIMapType and info.mapType == UIMapType.Zone then
                zoneTypeInSubtree[mid] = true
            end
            local mt = info.mapType
            if UIMapType and mt == UIMapType.Micro then
                local anc = firstZoneAncestorMapId(mid)
                if anc and zoneTypeInSubtree[anc] then
                    -- Redundant micro under an open-world zone row already in this subtree.
                else
                    local kind = UICK.Resolve(mid, info)
                    if kind ~= "cosmic" and kind ~= "world" then
                        local t = buckets[kind]
                        t[#t + 1] = { id = mid, name = info.name, mapType = info.mapType }
                    end
                end
            else
                local kind = UICK.Resolve(mid, info)
                if kind ~= "cosmic" and kind ~= "world" then
                    local t = buckets[kind]
                    t[#t + 1] = { id = mid, name = info.name, mapType = info.mapType }
                end
            end
        end
        end
    end

    local idsSeen = {}
    for _, k in ipairs(ORDERED_KINDS) do
        local lst = buckets[k]
        for i = 1, #lst do
            idsSeen[lst[i].id] = true
        end
    end

    if sec.instances then
        for ii = 1, #sec.instances do
            local sid = tonumber(sec.instances[ii])
            if sid and sid > 0 and not idsSeen[sid] then
                if not uiMapStructuredUnderRoots(sid, sec.apiRoots) then
                    -- Curated ID not under this expansion's roots (outdated / wrong list entry).
                else
                local ok2, info2 = pcall(C_Map.GetMapInfo, sid)
                if ok2 and info2 and info2.name and info2.name ~= ""
                    and not (issecretvalue and issecretvalue(info2.name)) then
                    local kind = UICK.Resolve(sid, info2)
                    if kind ~= "cosmic" and kind ~= "world" then
                        if depthById[sid] == nil then
                            depthById[sid] = treeDepthToNearestRoot(sid, sec.apiRoots)
                        end
                        local t = buckets[kind]
                        t[#t + 1] = { id = sid, name = info2.name, mapType = info2.mapType }
                        idsSeen[sid] = true
                    end
                end
                end
            end
        end
    end

    local roots = sec.apiRoots
    local rows = finalizeCatalogBuckets(buckets, roots, depthById)

    if #rows == 0 then return nil end
    apiRowCache[sectionIndex] = rows
    return rows
end

--- Fallback rows from curated static lists (deduped in normalizeSection).
---@return table rows
function catalog.GetDisplayRowsForSectionStatic(sectionIndex)
    local sec = catalog.sections[sectionIndex]
    if not sec then return {} end

    if sec.pickerGroups and #sec.pickerGroups > 0 then
        local custom = buildRowsFromPickerGroups(sectionIndex)
        return custom or {}
    end

    local UICK = ns.UIMapContentKind
    if not UICK or not UICK.Resolve then return {} end
    if UICK.EnsureJournalLoaded then UICK.EnsureJournalLoaded() end

    local buckets = newBuckets()
    local depthById = {}
    local seen = {}
    local roots = sec.apiRoots or {}

    local function pushId(mid)
        mid = tonumber(mid)
        if not mid or mid <= 0 or seen[mid] then return end
        if #roots > 0 and not uiMapStructuredUnderRoots(mid, roots) then return end
        seen[mid] = true
        local ok, info = pcall(C_Map.GetMapInfo, mid)
        if not ok or not info or not info.name or info.name == ""
            or (issecretvalue and issecretvalue(info.name)) then return end
        local kind = UICK.Resolve(mid, info)
        if kind == "cosmic" or kind == "world" then return end
        depthById[mid] = (#roots > 0) and treeDepthToNearestRoot(mid, roots) or 0
        local t = buckets[kind]
        t[#t + 1] = { id = mid, name = info.name, mapType = info.mapType }
    end

    if sec.maps then
        for i = 1, #sec.maps do pushId(sec.maps[i]) end
    end
    if sec.instances then
        for i = 1, #sec.instances do pushId(sec.instances[i]) end
    end
    if sec.relatedMaps then
        for i = 1, #sec.relatedMaps do pushId(sec.relatedMaps[i]) end
    end

    return finalizeCatalogBuckets(buckets, roots, depthById)
end

--- Prefer live API subtree when `apiRoots` is configured; else static lists.
---@return table rows
function catalog.GetDisplayRowsForSection(sectionIndex)
    local apiRows = buildApiRowsForSection(sectionIndex)
    if apiRows and #apiRows > 0 then return apiRows end
    return catalog.GetDisplayRowsForSectionStatic(sectionIndex)
end

--- Row pool sizing (API-driven lists can exceed static fallback counts — keep headroom without warming API cache here).
function catalog.GetMaxDisplayRowCount()
    local maxStatic = 0
    for i = 1, #catalog.sections do
        local r = catalog.GetDisplayRowsForSectionStatic(i)
        if #r > maxStatic then maxStatic = #r end
    end
    return math.max(maxStatic + 40, 560)
end

local function dedupeSorted(ids)
    local seen = {}
    local out = {}
    if not ids then return out end
    for i = 1, #ids do
        local id = tonumber(ids[i])
        if id and id > 0 and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    table.sort(out)
    return out
end

local function normalizeSection(sec)
    if not sec then return end
    sec.maps = dedupeSorted(sec.maps)
    sec.instances = dedupeSorted(sec.instances)
    sec.relatedMaps = dedupeSorted(sec.relatedMaps)
    local inOpen = {}
    for i = 1, #sec.maps do
        inOpen[sec.maps[i]] = true
    end
    if sec.instances then
        local fi = {}
        for i = 1, #sec.instances do
            local id = sec.instances[i]
            if not inOpen[id] then
                fi[#fi + 1] = id
            end
        end
        sec.instances = fi
    end
    local inPrimary = {}
    for i = 1, #sec.maps do
        inPrimary[sec.maps[i]] = true
    end
    for i = 1, #(sec.instances or {}) do
        inPrimary[sec.instances[i]] = true
    end
    if sec.relatedMaps then
        local fr = {}
        for i = 1, #sec.relatedMaps do
            local id = sec.relatedMaps[i]
            if not inPrimary[id] then
                fr[#fr + 1] = id
            end
        end
        sec.relatedMaps = fr
    end
end

for si = 1, #catalog.sections do
    normalizeSection(catalog.sections[si])
end

do
    local R = ns.ReminderContentIndex

    local function wirePickerGroups(sec, builder)
        if not sec or not R then return end
        local fn = R[builder]
        local g = fn and fn()
        if g and #g > 0 then
            sec.pickerGroups = g
        else
            sec.pickerGroups = {}
        end
    end

    if R then
        for si = 1, #catalog.sections do
            local sec = catalog.sections[si]
            local lk = sec and sec.localeKey
            if lk == "REMINDER_ZONE_CAT_MIDNIGHT" then
                wirePickerGroups(sec, "BuildMidnightPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_TWW" then
                wirePickerGroups(sec, "BuildTWWPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_DRAGONFLIGHT" then
                wirePickerGroups(sec, "BuildDragonflightPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_SHADOWLANDS" then
                wirePickerGroups(sec, "BuildShadowlandsPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_BFA" then
                wirePickerGroups(sec, "BuildBFAPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_LEGION" then
                wirePickerGroups(sec, "BuildLegionPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_WOD" then
                wirePickerGroups(sec, "BuildWoDPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_MOP" then
                wirePickerGroups(sec, "BuildMOPPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_CATA" then
                wirePickerGroups(sec, "BuildCataclysmPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_WRATH" then
                wirePickerGroups(sec, "BuildWrathPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_BC" then
                wirePickerGroups(sec, "BuildBCPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_KALIMDOR" then
                wirePickerGroups(sec, "BuildKalimdorPickerGroups")
            elseif lk == "REMINDER_ZONE_CAT_EASTERN_KINGDOMS" then
                wirePickerGroups(sec, "BuildEasternKingdomsPickerGroups")
            end
        end
    elseif ns.DebugPrint then
        ns.DebugPrint("ReminderZoneCatalog: ReminderContentIndex missing; picker groups not wired")
    end
end

ns.ReminderZoneCatalog = catalog
