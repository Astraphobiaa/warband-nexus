--[[
    Warband Nexus - Profession read API (split from ProfessionService.lua, 2026-10-22)
    Public getters over persisted profession data (concentration, knowledge, crafters, craft counts),
    the /wn profession verify printout and the crafting shopping-list helper. Loaded after
    ProfessionService.lua; uses ns.ProfessionServiceShared (PS).
]]

local ADDON_NAME, ns = ...

-- 12.1.5 removed the global item/coin fallbacks; bind the namespaced APIs.
local GetItemInfo = C_Item.GetItemInfo
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local PS = ns.ProfessionServiceShared

assert(PS and PS.SafeAPIString, "ProfessionService_Queries.lua loaded before ProfessionService.lua - check the TOC")

local ResolveTrackedCharactersTableKey = PS.ResolveTrackedCharactersTableKey
local CurrentSessionCanonicalCharacterKey = PS.CurrentSessionCanonicalCharacterKey
local SafeAPIString = PS.SafeAPIString

-- PUBLIC API

--[[
    Get concentration data for all characters, grouped by profession.
    
    @return table {
        [professionName] = {
            { charKey = string, charName = string, classFile = string,
              current = number, max = number, lastUpdate = number },
            ...
        }
    }
]]
function WarbandNexus:GetAllConcentrationData()
    local result = {}

    if not self.db or not self.db.global or not self.db.global.characters then
        return result
    end

    for charKey, charData in pairs(self.db.global.characters) do
        if charData.concentration then
            local charName = charData.name or charKey
            local classFile = charData.classFile or "PRIEST"
            -- Same concentration currency can be stored under multiple skillLineIDs (duplicate rows).
            -- Deduplicate by currencyID per character; legacy rows without currencyID by profession name.
            local seenCurrency = {}
            local seenLegacyProf = {}

            for key, concData in pairs(charData.concentration) do
                local profName = (type(key) == "number" and concData.professionName) or (type(key) == "string" and key) or "Profession"
                local cid = concData.currencyID

                if cid and cid > 0 then
                    if seenCurrency[cid] then
                        -- Already listed this pool for this character
                    else
                        seenCurrency[cid] = true
                        if not result[profName] then
                            result[profName] = {}
                        end
                        local entry = {
                            charKey    = charKey,
                            charName   = charName,
                            classFile  = classFile,
                            current    = concData.current or 0,
                            max        = concData.max or 0,
                            lastUpdate = concData.lastUpdate or 0,
                            currencyID = cid,
                        }
                        result[profName][#result[profName] + 1] = entry
                    end
                else
                    if seenLegacyProf[profName] then
                        -- Duplicate legacy bucket for same profession name
                    else
                        seenLegacyProf[profName] = true
                        if not result[profName] then
                            result[profName] = {}
                        end
                        local entry = {
                            charKey    = charKey,
                            charName   = charName,
                            classFile  = classFile,
                            current    = concData.current or 0,
                            max        = concData.max or 0,
                            lastUpdate = concData.lastUpdate or 0,
                            currencyID = cid,
                        }
                        result[profName][#result[profName] + 1] = entry
                    end
                end
            end
        end
    end

    -- Sort each profession's entries by charName for consistent display
    for _, entries in pairs(result) do
        table.sort(entries, function(a, b) return a.charName < b.charName end)
    end

    return result
end

--- Get projected concentration for a character's profession in real-time.
--- In WoW, Concentration regenerates at 10 points per hour (1 point every 360 seconds).
--- @param charKey string Character key or GUID
--- @param skillLineID number|string
--- @return table|nil { current, max, projected, secondsToCap, isCapped, currencyID, professionName, lastUpdate }
function WarbandNexus:GetProjectedConcentration(charKey, skillLineID)
    if not self.db or not self.db.global or not self.db.global.characters then
        return nil
    end
    local charData = self.db.global.characters[charKey]
    if not charData or not charData.concentration then
        return nil
    end
    local concData = charData.concentration[skillLineID]
    if not concData then
        for _, cd in pairs(charData.concentration) do
            if cd.skillLineID == skillLineID or cd.professionName == skillLineID or cd.currencyID == skillLineID then
                concData = cd
                break
            end
        end
    end
    if not concData then return nil end

    local current = tonumber(concData.current) or 0
    local maxVal = tonumber(concData.max) or 1000
    if maxVal <= 0 then maxVal = 1000 end
    local lastUpdate = tonumber(concData.lastUpdate) or time()
    local elapsed = math.max(0, time() - lastUpdate)

    -- 1 point every 360 seconds (10 points per hour)
    local gained = math.floor(elapsed / 360)
    local projected = math.min(maxVal, current + gained)
    local remaining = math.max(0, maxVal - projected)
    local secondsToCap = remaining * 360
    local isCapped = (projected >= maxVal)

    return {
        current = current,
        max = maxVal,
        projected = projected,
        secondsToCap = secondsToCap,
        isCapped = isCapped,
        currencyID = concData.currencyID,
        professionName = concData.professionName,
        lastUpdate = lastUpdate,
    }
end

--- Get all crafters whose concentration is within thresholdHours of capping or already capped.
--- @param thresholdHours number|nil Default 4 hours
--- @return table list of { charKey, charName, classFile, professionName, current, projected, max, secondsToCap, isCapped }
function WarbandNexus:GetConcentrationExpiringAlerts(thresholdHours)
    local maxSeconds = (tonumber(thresholdHours) or 4) * 3600
    local list = {}
    if not self.db or not self.db.global or not self.db.global.characters then
        return list
    end

    local allConc = self:GetAllConcentrationData()
    for profName, entries in pairs(allConc) do
        for i = 1, #entries do
            local e = entries[i]
            local current = tonumber(e.current) or 0
            local maxVal = tonumber(e.max) or 1000
            if maxVal <= 0 then maxVal = 1000 end
            local lastUpdate = tonumber(e.lastUpdate) or time()
            local elapsed = math.max(0, time() - lastUpdate)
            local gained = math.floor(elapsed / 360)
            local projected = math.min(maxVal, current + gained)
            local remaining = math.max(0, maxVal - projected)
            local secondsToCap = remaining * 360
            local isCapped = (projected >= maxVal)

            if isCapped or secondsToCap <= maxSeconds then
                list[#list + 1] = {
                    charKey = e.charKey,
                    charName = e.charName,
                    classFile = e.classFile,
                    professionName = profName,
                    current = current,
                    projected = projected,
                    max = maxVal,
                    secondsToCap = secondsToCap,
                    isCapped = isCapped,
                }
            end
        end
    end

    table.sort(list, function(a, b)
        return a.secondsToCap < b.secondsToCap
    end)

    return list
end

--- Get full concentration queue across all crafters, ranked by urgency (least seconds to cap first).
--- @return table list of all tracked crafters with projected concentration and time-to-cap
function WarbandNexus:GetConcentrationQueue()
    local list = {}
    if not self.db or not self.db.global or not self.db.global.characters then
        return list
    end

    local allConc = self:GetAllConcentrationData()
    for profName, entries in pairs(allConc) do
        for i = 1, #entries do
            local e = entries[i]
            local current = tonumber(e.current) or 0
            local maxVal = tonumber(e.max) or 1000
            if maxVal <= 0 then maxVal = 1000 end
            local lastUpdate = tonumber(e.lastUpdate) or time()
            local elapsed = math.max(0, time() - lastUpdate)
            local gained = math.floor(elapsed / 360)
            local projected = math.min(maxVal, current + gained)
            local remaining = math.max(0, maxVal - projected)
            local secondsToCap = remaining * 360
            local isCapped = (projected >= maxVal)

            list[#list + 1] = {
                charKey = e.charKey,
                charName = e.charName,
                classFile = e.classFile,
                professionName = profName,
                current = current,
                projected = projected,
                max = maxVal,
                secondsToCap = secondsToCap,
                isCapped = isCapped,
            }
        end
    end

    table.sort(list, function(a, b)
        return a.secondsToCap < b.secondsToCap
    end)

    return list
end


--[[
    How many crafts are possible from materials (same math as Recipe Companion: warband bank +
    all tracked characters' bags/banks). Uses limiting required reagent slots only; optional slots skipped.
]]
function WarbandNexus:GetRecipeCraftCountFromMaterials(recipeID)
    if not recipeID or not C_TradeSkillUI then return nil end

    local function sumItemAcrossTracked(itemID)
        if not itemID or not self.GetDetailedItemCountsFast then return 0 end
        local details = self:GetDetailedItemCountsFast(itemID)
        if not details then return 0 end
        local have = details.warbandBank or 0
        local chars = details.characters
        if chars then
            for ci = 1, #chars do
                local ch = chars[ci]
                have = have + (ch.bagCount or 0) + (ch.bankCount or 0)
            end
        end
        return have
    end

    local function fromSchematic(isRecraft)
        local schOk, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, isRecraft)
        if not schOk or not schematic or not schematic.reagentSlotSchematics then
            return nil
        end
        local slots = schematic.reagentSlotSchematics
        local minCraft = math.huge
        local haveLimiting = false

        for si = 1, #slots do
            local slot = slots[si]
            if slot and slot.reagents and #slot.reagents > 0 and slot.required ~= false then
                local qtyReq = tonumber(slot.quantityRequired) or 1
                if qtyReq < 1 then qtyReq = 1 end

                local nr = #slot.reagents
                local slotCraft

                if nr > 3 then
                    local best = 0
                    for ri = 1, nr do
                        local reagent = slot.reagents[ri]
                        if reagent and reagent.itemID then
                            local have = sumItemAcrossTracked(reagent.itemID)
                            best = math.max(best, math.floor(have / qtyReq))
                        end
                    end
                    slotCraft = best
                elseif nr >= 2 then
                    local best = 0
                    for ri = 1, nr do
                        local reagent = slot.reagents[ri]
                        if reagent and reagent.itemID then
                            local have = sumItemAcrossTracked(reagent.itemID)
                            best = math.max(best, math.floor(have / qtyReq))
                        end
                    end
                    slotCraft = best
                else
                    local reagent = slot.reagents[1]
                    if reagent and reagent.itemID then
                        local have = sumItemAcrossTracked(reagent.itemID)
                        slotCraft = math.floor(have / qtyReq)
                    else
                        slotCraft = 0
                    end
                end

                if slotCraft ~= nil then
                    haveLimiting = true
                    minCraft = math.min(minCraft, slotCraft)
                end
            end
        end

        if not haveLimiting then return nil end
        if minCraft == math.huge then return 0 end
        return math.max(0, math.floor(minCraft))
    end

    local n = fromSchematic(false)
    if n ~= nil then return n end
    return fromSchematic(true)
end

--[[
    Get all characters that know a specific recipe, with their skill and concentration data.
    
    @param recipeID number - The recipe spell ID
    @return table - Array of crafter entries, sorted by skill level (descending):
    {
        {
            charKey        = string,
            charName       = string,
            classFile      = string,
            professionName = string,
            skillLevel     = number,
            maxSkillLevel  = number,
            concentration  = { current, max, lastUpdate, currencyID } or nil,
            lastScan       = number,
        },
        ...
    }
]]
function WarbandNexus:GetCraftersForRecipe(recipeID)
    local result = {}

    if not self.db or not self.db.global or not self.db.global.characters then
        return result
    end
    if not recipeID then return result end

    for charKey, charData in pairs(self.db.global.characters) do
        if charData.recipes then
            for skillLineID, profData in pairs(charData.recipes) do
                if profData.knownRecipes and profData.knownRecipes[recipeID] then
                    -- Concentration keyed by skillLineID (same as recipes); fallback legacy by professionName
                    local concEntry = nil
                    if charData.concentration then
                        concEntry = charData.concentration[skillLineID] or (profData.professionName and charData.concentration[profData.professionName])
                    end

                    -- Look up overall profession skill from charData.professions
                    -- (not the expansion-specific skill stored in profData)
                    local overallSkill, overallMaxSkill = 0, 0
                    if charData.professions then
                        for k, prof in pairs(charData.professions) do
                            if prof and prof.name == profData.professionName then
                                overallSkill = prof.skill or prof.rank or 0
                                overallMaxSkill = prof.maxSkill or prof.maxRank or 0
                                break
                            end
                        end
                    end

                    result[#result + 1] = {
                        charKey        = charKey,
                        charName       = charData.name or charKey,
                        classFile      = charData.classFile or "PRIEST",
                        professionName = profData.professionName or "",
                        skillLevel     = overallSkill,
                        maxSkillLevel  = overallMaxSkill,
                        concentration  = concEntry,
                        lastScan       = profData.lastScan or 0,
                    }
                    break -- A recipe belongs to one profession per character
                end
            end
        end
    end

    -- Sort: highest skill first; on tie, current online character first; then alphabetical
    local currentCharKey = ResolveTrackedCharactersTableKey()
    table.sort(result, function(a, b)
        if a.skillLevel ~= b.skillLevel then
            return a.skillLevel > b.skillLevel
        end
        -- Same skill: prioritize the currently online character
        local aOnline = (a.charKey == currentCharKey)
        local bOnline = (b.charKey == currentCharKey)
        if aOnline ~= bOnline then
            return aOnline
        end
        return a.charName < b.charName
    end)

    return result
end

-- TWW concentration recharge: 10 per hour, 1000 max, 100 hours full recharge
-- Rate is fixed and applies passively (server-side, online and offline)
local CONCENTRATION_PER_SECOND = 10 / 3600  -- 10 per hour → per second

--[[
    Current concentration entry for one profession on a stored character row.
    Concentration is keyed by expansion skillLineID; the highest one carrying this professionName is
    the current (Midnight) line -- same rule the Characters row uses for knowledge. Legacy rows also
    hold a profession-name key that stayed pinned to the first expansion ever recorded; it is only a
    fallback when no skillLineID entry exists.

    @param charData table - db.global.characters row
    @param profName string - Profession name as stored on charData.professions
    @return table|nil - { current, max, currencyID, skillLineID, lastUpdate, ... }
]]
function WarbandNexus:GetProfessionConcentrationEntry(charData, profName)
    local conc = charData and charData.concentration
    if type(conc) ~= "table" or not profName then return nil end
    local best, bestKey = nil, -1
    for key, entry in pairs(conc) do
        if type(key) == "number" and key > bestKey and type(entry) == "table" and entry.professionName == profName then
            best, bestKey = entry, key
        end
    end
    if best then return best end
    local legacy = conc[profName]
    return type(legacy) == "table" and legacy or nil
end

--[[
    Estimate the current concentration for a stored entry, accounting for
    passive regeneration since the snapshot was taken.
    
    @param entry table - { current, max, lastUpdate }
    @return number - Estimated current concentration (floored integer)
]]
function WarbandNexus:GetEstimatedConcentration(entry)
    if not entry or not entry.max or entry.max <= 0 then return 0 end
    local current = entry.current or 0
    if current >= entry.max then return entry.max end

    local elapsed = time() - (entry.lastUpdate or time())
    if elapsed < 0 then elapsed = 0 end

    local estimated = current + (elapsed * CONCENTRATION_PER_SECOND)
    return math.min(math.floor(estimated), entry.max)
end

--[[
    Estimate time until concentration is full for a given entry.
    
    @param entry table - Single concentration entry from GetAllConcentrationData()
    @return string - Formatted time string ("Full", "2h 13m", "1d 4h", etc.)
]]
function WarbandNexus:GetConcentrationTimeToFull(entry)
    if not entry or not entry.max or entry.max <= 0 then return "" end

    local L = ns.L
    local estimated = self:GetEstimatedConcentration(entry)
    if estimated >= entry.max then
        return (L and L["PROF_CONCENTRATION_FULL"]) or "Full"
    end

    local remainingDeficit = entry.max - estimated
    local secondsToFull = remainingDeficit / CONCENTRATION_PER_SECOND

    local totalHours = math.floor(secondsToFull / 3600)
    local totalMinutes = math.floor(secondsToFull / 60)

    if totalHours >= 1 then
        local fmt = (L and L["PROF_CONCENTRATION_HOURS_REMAINING"]) or "%d Hours"
        return string.format(fmt, totalHours)
    else
        local fmt = (L and L["PROF_CONCENTRATION_MINUTES_REMAINING"]) or "%d Min"
        return string.format(fmt, math.max(1, totalMinutes))
    end
end

--[[
    Detailed time-to-full breakdown for tooltip display.
    Returns "X Days Y Hours Z Minutes" format.

    @param entry table - Single concentration entry from GetAllConcentrationData()
    @return string - Detailed time string ("2 Days 5 Hours 13 Minutes", etc.)
]]
function WarbandNexus:GetConcentrationTimeToFullDetailed(entry)
    if not entry or not entry.max or entry.max <= 0 then return "" end

    local L = ns.L
    local estimated = self:GetEstimatedConcentration(entry)
    if estimated >= entry.max then
        return (L and L["PROF_CONCENTRATION_FULL"]) or "Full"
    end

    local remainingDeficit = entry.max - estimated
    local secondsToFull = remainingDeficit / CONCENTRATION_PER_SECOND

    local days = math.floor(secondsToFull / 86400)
    local hours = math.floor((secondsToFull % 86400) / 3600)
    local minutes = math.floor((secondsToFull % 3600) / 60)

    if days > 0 then
        local fmt = (L and L["PROF_CONCENTRATION_DAYS_HOURS_MIN"]) or "%d Days %d Hours %d Min"
        return string.format(fmt, days, hours, minutes)
    elseif hours > 0 then
        local fmt = (L and L["PROF_CONCENTRATION_HOURS_MIN"]) or "%d Hours %d Min"
        return string.format(fmt, hours, minutes)
    else
        local fmt = (L and L["PROF_CONCENTRATION_MINUTES_ONLY"]) or "%d Min"
        return string.format(fmt, math.max(1, minutes))
    end
end

-- PUBLIC API: KNOWLEDGE DATA

--[[
    Get knowledge data for a specific character and profession.
    
    @param charKey string - Character key (e.g. "Mert-Silvermoon")
    @param profName string - Profession name (e.g. "Tailoring")
    @return table|nil - Knowledge data entry or nil:
    {
        skillLineID      = number,
        hasUnspentPoints = boolean,
        unspentPoints    = number,
        spentPoints      = number,
        maxPoints        = number,
        currencyName     = string,
        currencyIcon     = number,
        specTabs         = { { tabID, name, state }, ... },
        lastUpdate       = number,
    }
]]
function WarbandNexus:GetKnowledgeData(charKey, profName)
    if not self.db or not self.db.global or not self.db.global.characters then
        return nil
    end
    if not charKey or not profName then return nil end

    local characters = self.db.global.characters
    local charData = characters[charKey]
    if not charData and ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local canon = ns.Utilities:GetCanonicalCharacterKey(charKey)
        if canon then charData = characters[canon] end
    end
    if not charData and ns.VaultCharKeysMatch then
        for k, row in pairs(characters) do
            if type(row) == "table" and ns.VaultCharKeysMatch(k, charKey) then
                charData = row
                break
            end
        end
    end
    if not charData or not charData.knowledgeData then return nil end

    -- Direct profName lookup (legacy data)
    if charData.knowledgeData[profName] then
        return charData.knowledgeData[profName]
    end
    -- Search skillLineID-keyed entries that match professionName
    for key, kd in pairs(charData.knowledgeData) do
        if type(key) == "number" and type(kd) == "table" and kd.professionName == profName then
            return kd
        end
    end
    return nil
end

--[[
    Get knowledge data for ALL characters for a specific profession.
    
    @param profName string - Profession name (e.g. "Tailoring")
    @return table - Array of entries
]]
function WarbandNexus:GetAllKnowledgeDataForProfession(profName)
    local result = {}

    if not self.db or not self.db.global or not self.db.global.characters then
        return result
    end
    if not profName then return result end

    for charKey, charData in pairs(self.db.global.characters) do
        if charData.knowledgeData then
            -- Find knowledge entry matching professionName (entries may be keyed by skillLineID or profName)
            local kd = charData.knowledgeData[profName]
            if not kd then
                for key, entry in pairs(charData.knowledgeData) do
                    if type(key) == "number" and type(entry) == "table" and entry.professionName == profName then
                        kd = entry
                        break
                    end
                end
            end
            if kd then
                result[#result + 1] = {
                    charKey          = charKey,
                    charName         = charData.name or charKey,
                    classFile        = charData.classFile or "PRIEST",
                    hasUnspentPoints = kd.hasUnspentPoints or false,
                    unspentPoints    = kd.unspentPoints or 0,
                    spentPoints      = kd.spentPoints or 0,
                    maxPoints        = kd.maxPoints or 0,
                    currencyName     = kd.currencyName or "",
                    specTabs         = kd.specTabs or {},
                    lastUpdate       = kd.lastUpdate or 0,
                }
            end
        end
    end

    -- Sort by charName for consistency
    table.sort(result, function(a, b) return a.charName < b.charName end)

    return result
end

--[[
    Print current profession stats to chat for verification.
    Call with profession window OPEN (K) to see live API-derived values and DB snapshot.
    Use: /wn profverify
]]
function WarbandNexus:PrintProfessionVerify()
    if not (ns.IsDebugModeEnabled and ns.IsDebugModeEnabled()) then return end
    if not self.Print then return end
    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then
        self:Print("|cffff6600[WN Prof Verify]|r No character key.")
        return
    end
    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData then
        self:Print("|cffff6600[WN Prof Verify]|r No character data.")
        return
    end

    local skillLineID
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionChildSkillLineID then
        local ok, slID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
        if ok and slID and slID > 0 then skillLineID = slID end
    end

    if not skillLineID then
        self:Print("|cff00ccff[WN Prof Verify]|r Open profession window (K) first, then run |cffffcc00/wn profverify|r again.")
        if charData.knowledgeData or charData.recipes then
            self:Print("|cff888888 Stored data for this character (Midnight only):|r")
            if charData.knowledgeData then
                for k, v in pairs(charData.knowledgeData) do
                    local expName = type(v) == "table" and v.expansionName
                    if type(v) == "table" and v.professionName and expName and not (issecretvalue and issecretvalue(expName)) and expName:find("Midnight", 1, true) then
                        local sp = v.spentPoints or 0
                        local mx = v.maxPoints or 0
                        self:Print("  Knowledge " .. tostring(v.professionName) .. ": " .. sp .. " / " .. (mx > 0 and mx or "--"))
                    end
                end
            end
            if charData.recipes then
                for sl, r in pairs(charData.recipes) do
                    local rExp = type(r) == "table" and r.expansionName
                    if type(r) == "table" and r.professionName and rExp and not (issecretvalue and issecretvalue(rExp)) and rExp:find("Midnight", 1, true) then
                        self:Print("  Recipes " .. tostring(r.professionName) .. ": " .. tostring(r.knownCount or 0) .. " / " .. tostring(r.totalCount or 0) .. "  First craft: " .. tostring(r.firstCraftDoneCount or 0) .. " / " .. tostring(r.firstCraftTotalCount or 0))
                    end
                end
            end
        end
        if charData.professionEquipment then
            local keys = {}
            for k in pairs(charData.professionEquipment) do if k ~= "_legacy" then keys[#keys + 1] = tostring(k) end end
            if #keys > 0 then
                self:Print("  Equipment keys: " .. table.concat(keys, ", "))
            end
        end
        return
    end

    local profName = "?"
    local expansionName = ""
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if ok and info then
            profName = SafeAPIString(info.parentProfessionName) or SafeAPIString(info.professionName) or "?"
            expansionName = SafeAPIString(info.professionName) or ""
        end
    end

    self:Print("|cff00ff00[WN Prof Verify]|r " .. profName .. " (" .. expansionName .. ") | skillLineID=" .. tostring(skillLineID))

    local kd = charData.knowledgeData and charData.knowledgeData[skillLineID]
    if kd then
        local cur = (kd.spentPoints or 0) + (kd.unspentPoints or 0)
        local max = kd.maxPoints or 0
        self:Print("  Knowledge: " .. cur .. " / " .. (max > 0 and max or "--") .. "  (spent=" .. tostring(kd.spentPoints or 0) .. ", unspent=" .. tostring(kd.unspentPoints or 0) .. ")")
    else
        self:Print("  Knowledge: no data (open this profession tab to refresh)")
    end

    local rec = charData.recipes and charData.recipes[skillLineID]
    if rec then
        self:Print("  Recipes: " .. tostring(rec.knownCount or 0) .. " / " .. tostring(rec.totalCount or 0))
        self:Print("  First craft: " .. tostring(rec.firstCraftDoneCount or 0) .. " / " .. tostring(rec.firstCraftTotalCount or 0))
        if rec.lastScan then
            self:Print("  Recipe scan age: " .. tostring(time() - rec.lastScan) .. "s")
        end
    else
        self:Print("  Recipes / First craft: no data (open this profession tab to refresh)")
    end

    local conc = charData.concentration and charData.concentration[skillLineID]
    if conc then
        self:Print("  Concentration DB: " .. tostring(conc.current or 0) .. " / " .. tostring(conc.max or 0))
        if conc.currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local ok, live = pcall(C_CurrencyInfo.GetCurrencyInfo, conc.currencyID)
            if ok and live then
                local liveQ = live.quantity or 0
                local liveM = live.maxQuantity or 0
                self:Print("  Concentration API: " .. tostring(liveQ) .. " / " .. tostring(liveM))
                if tonumber(conc.current) ~= tonumber(liveQ) or tonumber(conc.max) ~= tonumber(liveM) then
                    self:Print("|cffff9900  Concentration DB/API mismatch — open profession window and wait for collectors.|r")
                end
            end
        end
    else
        self:Print("  Concentration: no data stored for this skill line")
    end

    local pd = charData.professionData and charData.professionData.bySkillLine and charData.professionData.bySkillLine[skillLineID]
    local wk = pd and pd.weeklyKnowledge
    if wk then
        local fc = wk.firstCraft
        local uq = wk.uniques
        local wq = wk.weeklyQuest
        if fc and fc.total and fc.total > 0 then
            self:Print("  Weekly firstCraft: " .. tostring(fc.current or 0) .. " / " .. tostring(fc.total))
        end
        if uq and uq.total and uq.total > 0 then
            self:Print("  Weekly uniques: " .. tostring(uq.current or 0) .. " / " .. tostring(uq.total))
        end
        if wq and wq.total and wq.total > 0 then
            self:Print("  Weekly trainer: " .. tostring(wq.current or 0) .. " / " .. tostring(wq.total))
        end
        local cu = wk.catchUp
        if cu and cu.total and cu.total > 0 then
            self:Print("  Catch-up currency: " .. tostring(cu.current or 0) .. " / " .. tostring(cu.total))
        end
    end

    local eqByProf = charData.professionEquipment
    local eqKey = profName:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "")
    local eqData = eqByProf and (eqByProf[profName] or eqByProf[expansionName] or eqByProf[eqKey]) or nil
    if eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) then
        local parts = {}
        if eqData.tool and eqData.tool.name then parts[#parts + 1] = "Tool: " .. eqData.tool.name end
        if eqData.accessory1 and eqData.accessory1.name then parts[#parts + 1] = "Acc1: " .. eqData.accessory1.name end
        if eqData.accessory2 and eqData.accessory2.name then parts[#parts + 1] = "Acc2: " .. eqData.accessory2.name end
        self:Print("  Equipment: " .. (table.concat(parts, "  ") or "ok"))
    else
        self:Print("  Equipment: none stored (open profession (K) on this char to scan)")
    end

    self:Print("|cff888888 Compare with in-game UI to verify numbers.|r")
end

-- =========================================================================
-- CRAFTING SHOPPING LIST HELPER
-- =========================================================================

---Compute missing reagents for a recipe across character inventory and Warband Bank.
---@param recipeID number Recipe ID
---@param quantityMultiplier number|nil Number of crafts (defaults to 1)
---@param characterOnly boolean|nil Only check current character bags (ignore Warband Bank)
---@return table { recipeID = number, recipeName = string, missingReagents = table, allOwned = boolean, totalMissingItems = number }
function WarbandNexus:GetRecipeMissingReagents(recipeID, quantityMultiplier, characterOnly)
    local multiplier = math.max(1, tonumber(quantityMultiplier) or 1)
    local result = {
        recipeID = recipeID,
        recipeName = "",
        missingReagents = {},
        allOwned = true,
        totalMissingItems = 0,
    }
    if not recipeID or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then
        return result
    end

    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if not schematic then return result end

    local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
    result.recipeName = (recipeInfo and SafeAPIString(recipeInfo.name)) or ("Recipe " .. recipeID)

    local slots = schematic.reagentSlotSchematics
    if not slots then return result end

    local canonKey = CurrentSessionCanonicalCharacterKey()
    local playerName = UnitName("player")

    for si = 1, #slots do
        local slot = slots[si]
        if slot and slot.required ~= false and slot.reagents and #slot.reagents > 0 then
            local needed = (slot.quantityRequired or 1) * multiplier
            local totalHave = 0
            local primaryItem = slot.reagents[1]

            for ti = 1, #slot.reagents do
                local r = slot.reagents[ti]
                if r and r.itemID then
                    local details = self.GetDetailedItemCountsFast and self:GetDetailedItemCountsFast(r.itemID)
                    if details then
                        local wbCount = details.warbandBank or 0
                        local curBagCount = 0
                        if details.characters then
                            for ci = 1, #details.characters do
                                local ch = details.characters[ci]
                                if ch and (ch.charKey == canonKey or ch.charName == playerName) then
                                    curBagCount = curBagCount + (ch.bagCount or 0)
                                end
                            end
                        end
                        if characterOnly then
                            totalHave = totalHave + curBagCount
                        else
                            totalHave = totalHave + curBagCount + wbCount
                        end
                    else
                        local inBags = (C_Item and C_Item.GetItemCount) and C_Item.GetItemCount(r.itemID, false) or 0
                        local inBank = (C_Item and C_Item.GetItemCount) and C_Item.GetItemCount(r.itemID, true) or 0
                        if characterOnly then
                            totalHave = totalHave + inBags
                        else
                            totalHave = totalHave + inBank
                        end
                    end
                end
            end

            if totalHave < needed then
                result.allOwned = false
                local missingCount = needed - totalHave
                local itemName = (primaryItem and primaryItem.itemID and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(primaryItem.itemID))
                    or (primaryItem and primaryItem.itemID and GetItemInfo and GetItemInfo(primaryItem.itemID))
                    or ("Item " .. tostring(primaryItem and primaryItem.itemID or si))
                result.missingReagents[#result.missingReagents + 1] = {
                    itemID = primaryItem and primaryItem.itemID or 0,
                    name = itemName,
                    needed = needed,
                    have = totalHave,
                    missing = missingCount,
                }
                result.totalMissingItems = result.totalMissingItems + missingCount
            end
        end
    end

    return result
end

---Format missing reagents into a player-friendly shopping list for clipboard and chat.
---@param missingData table Output of GetRecipeMissingReagents
---@return string Formatted text
function WarbandNexus:FormatShoppingList(missingData)
    if not missingData or not missingData.missingReagents then return "" end
    local lines = {}
    local title = missingData.recipeName or "Shopping List"
    lines[#lines + 1] = "Warband Nexus: " .. title
    for i = 1, #missingData.missingReagents do
        local r = missingData.missingReagents[i]
        lines[#lines + 1] = string.format("- %dx %s", r.missing, r.name)
    end
    return table.concat(lines, "\n")
end
