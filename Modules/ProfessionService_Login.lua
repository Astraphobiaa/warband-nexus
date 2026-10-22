--[[
    Warband Nexus - Profession login collectors (split from ProfessionService.lua, 2026-10-22)
    Login / reload collection of concentration, Midnight weekly knowledge and expansion professions,
    the persisted-warm checks, and the sliced per-skill-line knowledge warmup. Loaded after
    ProfessionService.lua and ProfessionService_WeeklyKnowledge.lua; uses ns.ProfessionServiceShared (PS).
]]

local ADDON_NAME, ns = ...

local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local issecretvalue = issecretvalue
local PS = ns.ProfessionServiceShared

assert(PS and PS.NotifyCollectorUpdate and PS.RefreshAllMidnightKnowledgeProgressForCharacter,
    "ProfessionService_Login.lua loaded before ProfessionService.lua / ProfessionService_WeeklyKnowledge.lua - check the TOC")

local IsCurrentCharacterTracked = PS.IsCurrentCharacterTracked
local ResolveTrackedCharactersTableKey = PS.ResolveTrackedCharactersTableKey
local SafeAPIString = PS.SafeAPIString
local EnsureSkillLineBucket = PS.EnsureSkillLineBucket
local NotifyCollectorUpdate = PS.NotifyCollectorUpdate
local CollectKnowledgeForSkillLine = PS.CollectKnowledgeForSkillLine
local CollectAllExpansionProfessions = PS.CollectAllExpansionProfessions
local SanitizeAllStoredScrappedRecipes = PS.SanitizeAllStoredScrappedRecipes
local HasWeeklyResetOccurredForTimestamp = PS.HasWeeklyResetOccurredForTimestamp
local RECURRING_WEEKLY_PROGRESS_KEYS = PS.RECURRING_WEEKLY_PROGRESS_KEYS
local RefreshAllMidnightKnowledgeProgressForCharacter = PS.RefreshAllMidnightKnowledgeProgressForCharacter

-- LOGIN-TIME CONCENTRATION COLLECTION

--[[
    Collect concentration data on login/reload.
    First tries to refresh existing data from stored currency IDs.
    Then also runs a full currency list scan to discover new concentration
    currencies (e.g. if the player learned a new profession since last login).
    Called on PLAYER_ENTERING_WORLD with a delay.
]]
function WarbandNexus:CollectConcentrationOnLogin()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if not self.db or not self.db.global then return end
    if self.IsConcentrationPersistedWarm and self:IsConcentrationPersistedWarm() then
        return
    end

    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return end

    local charData = self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end

    -- Phase 1: Refresh existing stored data from known currency IDs
    if charData.concentration then
        for slKey, concData in pairs(charData.concentration) do
            if concData.currencyID and concData.currencyID > 0 then
                local ok, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, concData.currencyID)
                -- maxQuantity 0 = currency data not loaded yet at login: writing it (with a fresh
                -- lastUpdate) zeroed the stored value and restarted the regeneration estimate.
                if ok and currInfo and (tonumber(currInfo.maxQuantity) or 0) > 0 then
                    concData.current    = currInfo.quantity or concData.current or 0
                    concData.max        = currInfo.maxQuantity
                    concData.lastUpdate = time()
                end
            end
            if concData.current == nil then concData.current = 0 end
            if concData.max == nil then concData.max = 0 end
        end
    end

    -- Phase 2: Try to discover concentration via GetConcentrationCurrencyID
    -- using stored discoveredSkillLines (collected when professions were opened)
    if C_TradeSkillUI and C_TradeSkillUI.GetConcentrationCurrencyID then
        if not charData.concentration then
            charData.concentration = {}
        end

        if charData.discoveredSkillLines then
            for profName, skillLines in pairs(charData.discoveredSkillLines) do
                for sli = 1, #skillLines do
                    local sl = skillLines[sli]
                    local slID = (type(sl) == "table" and sl.id) or sl
                    if slID and not charData.concentration[slID] then
                        local concOk, currencyID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, slID)
                        if concOk and currencyID and currencyID > 0 then
                            local currOk, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
                            if currOk and currInfo and currInfo.maxQuantity and currInfo.maxQuantity > 0 then
                                local expansionName = nil
                                if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                                    local piOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, slID)
                                    if piOk and profInfo then
                                        expansionName = SafeAPIString(profInfo.professionName)
                                            or SafeAPIString(profInfo.parentProfessionName)
                                    end
                                end
                                local concEntry = {
                                    current        = currInfo.quantity or 0,
                                    max            = currInfo.maxQuantity or 0,
                                    currencyID     = currencyID,
                                    skillLineID    = slID,
                                    professionName = profName,
                                    expansionName  = expansionName,
                                    lastUpdate     = time(),
                                }
                                charData.concentration[slID] = concEntry
                                local bucket = EnsureSkillLineBucket(charData, slID, profName, expansionName)
                                if bucket then
                                    bucket.concentration = {
                                        current = currInfo.quantity or 0,
                                        max = currInfo.maxQuantity or 0,
                                        currencyID = currencyID,
                                        lastUpdate = time(),
                                    }
                                end
                                break
                            end
                        end
                    end
                end
            end
        end

        -- Phase 2b: Fallback via GetProfessions + GetProfessionInfo (base profession skill line)
        local prof1, prof2
        if GetProfessions then prof1, prof2 = GetProfessions() end
        local profIdxPair = { prof1, prof2 }
        for ii = 1, #profIdxPair do
            local index = profIdxPair[ii]
            if index then
                -- GetProfessionInfo: name, icon, skillLevel, maxSkillLevel, numAbilities, spelloffset, skillLine
                local ok, rawName, _, _, _, _, _, skillLine = pcall(GetProfessionInfo, index)
                local name = ok and SafeAPIString(rawName) or nil
                if issecretvalue and issecretvalue(skillLine) then skillLine = nil end
                if ok and name and type(skillLine) == "number" and skillLine > 0 and not charData.concentration[skillLine] then
                    local concOk, currencyID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, skillLine)
                    if concOk and currencyID and currencyID > 0 then
                        local currOk, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
                        if currOk and currInfo and currInfo.maxQuantity and currInfo.maxQuantity > 0 then
                            local concEntry = {
                                current        = currInfo.quantity or 0,
                                max            = currInfo.maxQuantity or 0,
                                currencyID     = currencyID,
                                skillLineID    = skillLine,
                                professionName = name,
                                expansionName  = nil,
                                lastUpdate     = time(),
                            }
                            charData.concentration[skillLine] = concEntry
                            local bucket = EnsureSkillLineBucket(charData, skillLine, name, nil)
                            if bucket then
                                bucket.concentration = {
                                    current = currInfo.quantity or 0,
                                    max = currInfo.maxQuantity or 0,
                                    currencyID = currencyID,
                                    lastUpdate = time(),
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Rebuild reverse lookup map for real-time currency matching
    if self.RebuildConcentrationCurrencyMap then
        self:RebuildConcentrationCurrencyMap()
    end

    if self.SendMessage then
        self:SendMessage(E.CONCENTRATION_UPDATED, charKey)
    end
end

--[[
    Collect midnight knowledge & sweep weekly reset expiration on login/reload.
    Called from Core.lua on PLAYER_ENTERING_WORLD with a delay.
]]
function WarbandNexus:CollectMidnightKnowledgeOnLogin()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not self.db or not self.db.global or not self.db.global.characters then return end

    local anyAltSanitized = false
    local chars = self.db.global.characters
    for cKey, cData in pairs(chars) do
        if cData and cData.professionData and cData.professionData.bySkillLine then
            for slID, bucket in pairs(cData.professionData.bySkillLine) do
                if bucket and bucket.weeklyKnowledge then
                    local wk = bucket.weeklyKnowledge
                    local lastUpdate = wk.lastUpdate or 0
                    if HasWeeklyResetOccurredForTimestamp(lastUpdate) then
                        for i = 1, #RECURRING_WEEKLY_PROGRESS_KEYS do
                            local rk = RECURRING_WEEKLY_PROGRESS_KEYS[i]
                            local entry = wk[rk]
                            if entry and type(entry) == "table" and (entry.current or 0) > 0 then
                                entry.current = 0
                                anyAltSanitized = true
                            end
                        end
                    end
                end
            end
        end
        if cData and cData.professionWeeklyKnowledge then
            for slID, wk in pairs(cData.professionWeeklyKnowledge) do
                if wk then
                    local lastUpdate = wk.lastUpdate or 0
                    if HasWeeklyResetOccurredForTimestamp(lastUpdate) then
                        for i = 1, #RECURRING_WEEKLY_PROGRESS_KEYS do
                            local rk = RECURRING_WEEKLY_PROGRESS_KEYS[i]
                            local entry = wk[rk]
                            if entry and type(entry) == "table" and (entry.current or 0) > 0 then
                                entry.current = 0
                                anyAltSanitized = true
                            end
                        end
                    end
                end
            end
        end
    end

    local activeRefreshed = 0
    local charKey = ResolveTrackedCharactersTableKey()
    local charData = charKey and chars[charKey]
    if charData and IsCurrentCharacterTracked() then
        activeRefreshed = RefreshAllMidnightKnowledgeProgressForCharacter(charData)
    end

    if activeRefreshed > 0 and charKey then
        NotifyCollectorUpdate("profession", E.PROFESSION_DATA_UPDATED, charKey)
    elseif anyAltSanitized and self.SendMessage then
        self:SendMessage(E.PROFESSION_DATA_UPDATED, charKey or "all")
    end
end

--[[
    Refresh expansion sub-profession data on login from stored skillLineIDs.
    Called from Core.lua on PLAYER_ENTERING_WORLD with a delay.
]]
function WarbandNexus:CollectExpansionProfessionsOnLogin()
    pcall(SanitizeAllStoredScrappedRecipes)
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if self.IsExpansionProfessionsPersistedWarm and self:IsExpansionProfessionsPersistedWarm() then
        return
    end
    pcall(CollectAllExpansionProfessions, false)
end

---@return boolean
function WarbandNexus:IsExpansionProfessionsPersistedWarm()
    -- Never skip the login refresh: stored rows say nothing about freshness, so a warm skip froze
    -- expansion skill for alts (skill-ups made with the profession window closed were never re-read)
    -- and blocked seeding of the Midnight skill line. The refresh is a handful of cheap API reads.
    do return false end
    if not self.db or not self.db.global then return false end
    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return false end
    local charData = self.db.global.characters and self.db.global.characters[charKey]
    local DF = ns.DataFreshness
    return DF and DF.IsExpansionProfessionsWarm and DF.IsExpansionProfessionsWarm(charData) == true
end

-- LOGIN-TIME KNOWLEDGE COLLECTION

--[[
    Collect knowledge data on login/reload for all discovered professions.
    Uses stored discoveredSkillLines + C_Traits API chain (same as Blizzard's own code).
    Called from Core.lua on PLAYER_ENTERING_WORLD with a delay.
]]
--- Skip expensive C_Traits scan when every discovered skill line already has persisted knowledge.
--- Event path (TRAIT_NODE_CHANGED) uses CollectKnowledgeOnLogin({ reason = "event" }).
---@return boolean
function WarbandNexus:IsKnowledgePersistedWarm()
    if not self.db or not self.db.global then return false end
    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return false end
    local charData = self.db.global.characters and self.db.global.characters[charKey]
    local DF = ns.DataFreshness
    if DF and DF.IsKnowledgeWarmForCharacter then
        return DF.IsKnowledgeWarmForCharacter(charData) == true
    end
    return false
end

---@deprecated Use IsKnowledgePersistedWarm
function WarbandNexus:ShouldSkipKnowledgeLoginWarmup()
    return self:IsKnowledgePersistedWarm()
end

---@return boolean
function WarbandNexus:IsConcentrationPersistedWarm()
    if not self.db or not self.db.global then return false end
    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return false end
    local charData = self.db.global.characters and self.db.global.characters[charKey]
    local DF = ns.DataFreshness
    return DF and DF.IsConcentrationWarm and DF.IsConcentrationWarm(charData) == true
end

---@return boolean
function WarbandNexus:IsProfessionEquipmentPersistedWarm()
    if not self.db or not self.db.global then return false end
    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return false end
    local charData = self.db.global.characters and self.db.global.characters[charKey]
    local DF = ns.DataFreshness
    return DF and DF.IsProfessionEquipmentWarm and DF.IsProfessionEquipmentWarm(charData) == true
end

local knowledgeLoginCollectSerial = 0
local knowledgeLoginCollectQueue = {}
local knowledgeLoginCollectInFlight = false
local KNOWLEDGE_LOGIN_SLICE_GAP_SEC = 0.2

local function ApplyKnowledgeCollectResult(charData, slID, profName, expansionName, result)
    if not result or not charData then return end
    result.professionName = profName
    result.expansionName = expansionName
    if not charData.knowledgeData then
        charData.knowledgeData = {}
    end
    charData.knowledgeData[slID] = result
    local bucket = EnsureSkillLineBucket(charData, slID, profName, expansionName)
    if bucket then
        bucket.knowledge = {
            hasUnspentPoints = result.hasUnspentPoints or false,
            unspentPoints = result.unspentPoints or 0,
            spentPoints = result.spentPoints or 0,
            maxPoints = result.maxPoints or 0,
            currencyName = SafeAPIString(result.currencyName) or "",
            currencyIcon = result.currencyIcon,
            specTabs = result.specTabs,
            lastUpdate = result.lastUpdate or time(),
        }
    end
end

function WarbandNexus:CollectKnowledgeOnLogin(opts)
    opts = opts or {}
    if opts.reason ~= "event" and self.IsKnowledgePersistedWarm and self:IsKnowledgePersistedWarm() then
        return
    end
    if knowledgeLoginCollectInFlight then return end
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if not self.db or not self.db.global then return end
    if not C_ProfSpecs or not C_Traits then return end

    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return end

    local charData = self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end

    if not charData.knowledgeData then
        charData.knowledgeData = {}
    end

    if not charData.discoveredSkillLines then return end

    wipe(knowledgeLoginCollectQueue)
    local qLen = 0
    for profName, skillLines in pairs(charData.discoveredSkillLines) do
        if skillLines and #skillLines > 0 then
            for sli = 1, #skillLines do
                local sl = skillLines[sli]
                local slID = sl and (sl.id or sl)
                if slID then
                    qLen = qLen + 1
                    knowledgeLoginCollectQueue[qLen] = {
                        slID = slID,
                        profName = profName,
                        expansionName = (type(sl) == "table" and sl.name) or nil,
                    }
                end
            end
        end
    end
    if qLen == 0 then return end

    knowledgeLoginCollectInFlight = true
    knowledgeLoginCollectSerial = knowledgeLoginCollectSerial + 1
    local serial = knowledgeLoginCollectSerial
    local idx = 1
    local addon = self

    local function finishKnowledgeLoginCollect()
        knowledgeLoginCollectInFlight = false
    end

    local function collectNextSkillLine()
        if serial ~= knowledgeLoginCollectSerial then
            finishKnowledgeLoginCollect()
            return
        end
        if idx > qLen then
            finishKnowledgeLoginCollect()
            if addon.SendMessage then
                addon:SendMessage(E.KNOWLEDGE_UPDATED, charKey)
            end
            return
        end

        local entry = knowledgeLoginCollectQueue[idx]
        idx = idx + 1

        local function collectOne()
            local result = CollectKnowledgeForSkillLine(entry.slID, entry.profName)
            if result then
                ApplyKnowledgeCollectResult(charData, entry.slID, entry.profName, entry.expansionName, result)
            end
        end

        local P = ns.Profiler
        if P and P.enabled and P.RunSlice then
            P:RunSlice(P.CAT.SVC, "CollectKnowledge", collectOne)
        else
            collectOne()
        end

        if idx <= qLen then
            C_Timer.After(KNOWLEDGE_LOGIN_SLICE_GAP_SEC, collectNextSkillLine)
        else
            finishKnowledgeLoginCollect()
            if addon.SendMessage then
                addon:SendMessage(E.KNOWLEDGE_UPDATED, charKey)
            end
        end
    end

    collectNextSkillLine()
end
