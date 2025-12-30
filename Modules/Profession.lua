--[[
    Warband Nexus - Profession Module
    Handles profession-specific logic and data management
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

--[[
    Scan all professions for current character
    This will open each profession window to collect detailed data
    @param callback function - Optional callback when scan completes
]]
function WarbandNexus:ScanProfessionData(callback)
    -- Check if in combat
    if InCombatLockdown() then
        self:Print("|cffff6600Cannot scan professions while in combat!|r")
        return
    end
    
    local success, err = pcall(function()
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if not self.db.global.characters or not self.db.global.characters[key] then
            self:Print("|cffff6600Character data not found.|r")
            return
        end
        
        local professions = self.db.global.characters[key].professions
        if not professions then
            self:Print("|cffff6600No professions found.|r")
            return
        end
        
        -- Collect profession indices to scan
        local profsToScan = {}
        
        if professions[1] then 
            table.insert(profsToScan, {index = professions[1].index, name = professions[1].name})
        end
        if professions[2] then 
            table.insert(profsToScan, {index = professions[2].index, name = professions[2].name})
        end
        
        if #profsToScan == 0 then
            self:Print("|cffff6600No primary professions to scan.|r")
            if callback then callback() end
            return
        end
        
        self:Print("|cff00ccffScanning professions...|r")
        
        -- Scan professions sequentially
        local currentIndex = 1
        local scanDelay = 0.5 -- Delay between profession opens
        
        local function scanNext()
            if currentIndex > #profsToScan then
                self:Print("|cff00ff00Profession scan complete!|r")
                if callback then callback() end
                if self.RefreshUI then
                    self:RefreshUI()
                end
                return
            end
            
            local prof = profsToScan[currentIndex]
            
            -- Open profession
            if prof.index then
                self:Print("|cff00ccffOpening " .. (prof.name or "profession") .. "...|r")
                
                -- Check if in combat
                if InCombatLockdown() then
                    self:Print("|cffff6600Cannot scan while in combat!|r")
                    if callback then callback() end
                    return
                end
                
                -- Try to open profession using C_TradeSkillUI
                local opened = false
                if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
                    opened = C_TradeSkillUI.OpenTradeSkill(prof.index)
                end
                
                -- Fallback: Try to cast profession spell
                if not opened then
                    local profInfo = {GetProfessionInfo(prof.index)}
                    if profInfo and #profInfo >= 7 then
                        local skillLine = profInfo[7] -- 7th return value is skillLine
                        if skillLine then
                            -- Try to open by skillLine
                            if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkillBySkillLineID then
                                opened = C_TradeSkillUI.OpenTradeSkillBySkillLineID(skillLine)
                            end
                        end
                    end
                end
                
                -- Wait for profession to be ready
                C_Timer.After(2.0, function()
                    if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady() then
                        local success = self:UpdateDetailedProfessionData()
                        if success then
                            self:Print("|cff00ff00✓|r " .. (prof.name or "Profession") .. " scanned")
                        else
                            self:Print("|cffff6600Failed to collect data for " .. (prof.name or "profession") .. "|r")
                        end
                    else
                        self:Print("|cffff6600Failed to scan " .. (prof.name or "profession") .. "|r")
                    end
                    
                    -- Close profession window
                    if C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill then
                        C_TradeSkillUI.CloseTradeSkill()
                    end
                    
                    -- Move to next profession
                    currentIndex = currentIndex + 1
                    C_Timer.After(0.5, scanNext)
                end)
            else
                -- Skip this profession
                currentIndex = currentIndex + 1
                scanNext()
            end
        end
        
        -- Start scanning
        scanNext()
    end)
    
    if not success then
        self:Print("|cffff6600Profession scan failed: " .. tostring(err) .. "|r")
    end
end

--[[
    Get profession icon for display
    @param professionName string - Name of the profession
    @return number - Icon texture ID
]]
function WarbandNexus:GetProfessionIcon(professionName)
    local icons = {
        ["Alchemy"] = "Interface\\Icons\\Trade_Alchemy",
        ["Blacksmithing"] = "Interface\\Icons\\Trade_BlackSmithing",
        ["Enchanting"] = "Interface\\Icons\\Trade_Engraving",
        ["Engineering"] = "Interface\\Icons\\Trade_Engineering",
        ["Herbalism"] = "Interface\\Icons\\Trade_Herbalism",
        ["Inscription"] = "Interface\\Icons\\INV_Inscription_Tradeskill01",
        ["Jewelcrafting"] = "Interface\\Icons\\INV_Misc_Gem_01",
        ["Leatherworking"] = "Interface\\Icons\\Trade_LeatherWorking",
        ["Mining"] = "Interface\\Icons\\Trade_Mining",
        ["Skinning"] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
        ["Tailoring"] = "Interface\\Icons\\Trade_Tailoring",
        ["Cooking"] = "Interface\\Icons\\INV_Misc_Food_15",
        ["Fishing"] = "Interface\\Icons\\Trade_Fishing",
        ["Archaeology"] = "Interface\\Icons\\Trade_Archaeology",
    }
    
    return icons[professionName] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

--[[
    Get profession color based on skill level
    @param rank number - Current skill rank
    @param maxRank number - Maximum skill rank
    @return r, g, b - RGB color values
]]
function WarbandNexus:GetProfessionColor(rank, maxRank)
    if not rank or not maxRank or maxRank == 0 then
        return 0.5, 0.5, 0.5 -- Gray
    end
    
    local percentage = rank / maxRank
    
    if percentage >= 1.0 then
        return 0.2, 0.9, 0.3 -- Green (maxed)
    elseif percentage >= 0.75 then
        return 0.3, 0.8, 1.0 -- Blue (high)
    elseif percentage >= 0.5 then
        return 1.0, 0.8, 0.2 -- Yellow (medium)
    elseif percentage >= 0.25 then
        return 1.0, 0.5, 0.2 -- Orange (low)
    else
        return 1.0, 0.3, 0.3 -- Red (very low)
    end
end

--[[
    Check if a profession has specialization system
    @param profession table - Profession data
    @return boolean - True if has specializations
]]
function WarbandNexus:HasProfessionSpecs(profession)
    return profession and profession.specializations and 
           profession.specializations.configID ~= nil
end

--[[
    Get total knowledge points for a profession
    @param profession table - Profession data
    @return spent, total - Spent and total knowledge points
]]
function WarbandNexus:GetProfessionKnowledge(profession)
    if not self:HasProfessionSpecs(profession) then
        return 0, 0
    end
    
    local totalSpent = 0
    local totalMax = 0
    
    if profession.specializations.specs then
        for _, spec in pairs(profession.specializations.specs) do
            totalSpent = totalSpent + (spec.knowledgeSpent or 0)
            totalMax = totalMax + (spec.knowledgeMax or 0)
        end
    end
    
    return totalSpent, totalMax
end

--[[
    Get profession summary for a character
    @param charKey string - Character key (name-realm)
    @return table - Profession summary
]]
function WarbandNexus:GetCharacterProfessionSummary(charKey)
    if not self.db.global.characters or not self.db.global.characters[charKey] then
        return nil
    end
    
    local professions = self.db.global.characters[charKey].professions
    if not professions then
        return nil
    end
    
    local summary = {
        primary = {},
        secondary = {},
        hasSpecs = false
    }
    
    -- Primary professions
    if professions[1] then
        table.insert(summary.primary, professions[1])
        if self:HasProfessionSpecs(professions[1]) then
            summary.hasSpecs = true
        end
    end
    if professions[2] then
        table.insert(summary.primary, professions[2])
        if self:HasProfessionSpecs(professions[2]) then
            summary.hasSpecs = true
        end
    end
    
    -- Secondary professions
    if professions.cooking then
        table.insert(summary.secondary, professions.cooking)
    end
    if professions.fishing then
        table.insert(summary.secondary, professions.fishing)
    end
    if professions.archaeology then
        table.insert(summary.secondary, professions.archaeology)
    end
    
    return summary
end

-- Export to namespace
ns.Profession = {
    ScanProfessionData = function(...) return WarbandNexus:ScanProfessionData(...) end,
    GetProfessionIcon = function(...) return WarbandNexus:GetProfessionIcon(...) end,
    GetProfessionColor = function(...) return WarbandNexus:GetProfessionColor(...) end,
    HasProfessionSpecs = function(...) return WarbandNexus:HasProfessionSpecs(...) end,
    GetProfessionKnowledge = function(...) return WarbandNexus:GetProfessionKnowledge(...) end,
    GetCharacterProfessionSummary = function(...) return WarbandNexus:GetCharacterProfessionSummary(...) end,
}

