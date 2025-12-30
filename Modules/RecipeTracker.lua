--[[
    Warband Nexus - Recipe Tracker Module
    Tracks learned recipes and profession knowledge for all characters
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

--[[
    Collect learned recipes for currently open profession
    @param professionID number - The profession skill line ID
    @return table - Recipe data
]]
function WarbandNexus:CollectLearnedRecipes(professionID)
    local success, recipes = pcall(function()
        if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady() then
            return {}
        end
        
        local learnedRecipeIDs = {}
        
        -- Get all recipes
        local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
        if not recipeIDs then return {} end
        
        for _, recipeID in ipairs(recipeIDs) do
            local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
            
            if recipeInfo and recipeInfo.learned then
                table.insert(learnedRecipeIDs, recipeID)
            end
        end
        
        -- Convert to bitfield for efficient storage
        local bitfield = self:SetLearnedRecipes(professionID, learnedRecipeIDs)
        
        return {
            bitfield = bitfield,
            count = #learnedRecipeIDs,
            lastUpdated = time()
        }
    end)
    
    if not success then
        return {bitfield = "", count = 0, lastUpdated = 0}
    end
    
    return recipes
end

--[[
    Get learned recipe IDs from bitfield
    @param professionData table - Profession data with recipes
    @return table - Array of learned recipe IDs
]]
function WarbandNexus:GetLearnedRecipeIDs(professionData)
    if not professionData or not professionData.recipes or not professionData.recipes.bitfield then
        return {}
    end
    
    return self:GetLearnedRecipes(professionData.recipes.bitfield)
end

--[[
    Check if a specific recipe is learned
    @param professionData table - Profession data
    @param recipeID number - Recipe ID to check
    @return boolean - True if learned
]]
function WarbandNexus:IsRecipeLearnedByID(professionData, recipeID)
    if not professionData or not professionData.recipes or not professionData.recipes.bitfield then
        return false
    end
    
    return self:IsRecipeLearned(professionData.recipes.bitfield, recipeID)
end

--[[
    Get recipe requirements (reagents)
    @param recipeID number - Recipe ID
    @return table - Reagent info
]]
function WarbandNexus:GetRecipeRequirements(recipeID)
    local success, reagents = pcall(function()
        if not C_TradeSkillUI then
            return {}
        end
        
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
        if not schematic then return {} end
        
        local reagentList = {}
        if schematic.reagentSlotSchematics then
            for _, slotSchematic in ipairs(schematic.reagentSlotSchematics) do
                for _, reagent in ipairs(slotSchematic.reagents) do
                    table.insert(reagentList, {
                        itemID = reagent.itemID,
                        quantity = slotSchematic.quantityRequired or 1,
                        name = C_Item.GetItemNameByID(reagent.itemID) or "Unknown"
                    })
                end
            end
        end
        
        return reagentList
    end)
    
    if not success then
        return {}
    end
    
    return reagents
end

--[[
    Count total learned recipes for a profession
    @param professionData table - Profession data
    @return number - Recipe count
]]
function WarbandNexus:GetRecipeCount(professionData)
    if not professionData or not professionData.recipes then
        return 0
    end
    
    return professionData.recipes.count or 0
end

--[[
    Update recipe data for currently open profession
    Should be called when profession window is open
]]
function WarbandNexus:UpdateProfessionRecipes()
    local success = pcall(function()
        if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady() then
            return
        end
        
        local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo()
        if not baseInfo or not baseInfo.professionID then return end
        
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if not self.db.global.characters[key] then return end
        if not self.db.global.characters[key].professions then return end
        
        local professions = self.db.global.characters[key].professions
        
        -- Find matching profession
        local targetProf = nil
        for i = 1, 2 do
            if professions[i] and professions[i].skillLine == baseInfo.professionID then
                targetProf = professions[i]
                break
            end
        end
        
        if targetProf then
            -- Collect and store recipe data (as bitfield)
            targetProf.recipes = self:CollectLearnedRecipes(baseInfo.professionID)
            
            self:Debug(string.format("Stored %d recipes as bitfield (%d bytes)",
                targetProf.recipes.count or 0,
                #(targetProf.recipes.bitfield or "")))
            
            -- Invalidate cache
            if self.InvalidateCharacterCache then
                self:InvalidateCharacterCache()
            end
        end
    end)
    
    return success
end

-- Export to namespace
ns.RecipeTracker = {
    CollectLearnedRecipes = function(...) return WarbandNexus:CollectLearnedRecipes(...) end,
    GetRecipesByCategory = function(...) return WarbandNexus:GetRecipesByCategory(...) end,
    GetRecipeRequirements = function(...) return WarbandNexus:GetRecipeRequirements(...) end,
    GetRecipeCounts = function(...) return WarbandNexus:GetRecipeCounts(...) end,
    UpdateProfessionRecipes = function(...) return WarbandNexus:UpdateProfessionRecipes(...) end,
}

