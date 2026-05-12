--[[
    Warband Nexus - Gold Management Service
    Automatic gold management using C_Bank API
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L
local E = ns.Constants.EVENTS

-- Throttling
local lastActionTime = 0
local ACTION_COOLDOWN = 2

--============================================================================
-- SETTINGS RESOLUTION: per-character override → profile fallback
--============================================================================

local function GetEffectiveGoldSettings()
    if not WarbandNexus.db then return nil end
    local charSettings = WarbandNexus.db.char and WarbandNexus.db.char.goldManagement
    if charSettings and charSettings.perCharacter then
        return charSettings
    end
    return WarbandNexus.db.profile and WarbandNexus.db.profile.goldManagement
end

--============================================================================
-- CORE LOGIC
--============================================================================

local function PerformGoldManagement()
    local settings = GetEffectiveGoldSettings()
    if not settings or not settings.enabled then return end

    local dbGold = 0
    local ck = ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(WarbandNexus)
    if not ck and ns.Utilities.GetCharacterStorageKey then
        ck = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    end
    if not ck then
        ck = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    end
    local ch = ck and WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[ck]
    if ch and ns.Utilities and ns.Utilities.GetCharTotalCopper then
        dbGold = ns.Utilities:GetCharTotalCopper(ch)
    end
    local charGold = (ns.Utilities and ns.Utilities.GetLiveCharacterMoneyCopper and ns.Utilities:GetLiveCharacterMoneyCopper(dbGold)) or dbGold
    local warbandGold = (C_Bank and C_Bank.FetchDepositedMoney and C_Bank.FetchDepositedMoney(Enum.BankType.Account)) or 0
    local target = settings.targetAmount or 0
    local mode = settings.mode or "both"
    
    -- DEPOSIT
    if (mode == "deposit" or mode == "both") and charGold > target then
        local excess = charGold - target
        
        if C_Bank and C_Bank.DepositMoney then
            local now = GetTime()
            if (now - lastActionTime) < ACTION_COOLDOWN then return end
            
            local ok, err = pcall(C_Bank.DepositMoney, Enum.BankType.Account, excess)
            if ok then
                lastActionTime = now
                if WarbandNexus.LogMoneyTransactionImmediate then
                    WarbandNexus:LogMoneyTransactionImmediate("deposit", excess, charGold - excess, warbandGold + excess)
                end
            end
        end
        return
    end
    
    -- WITHDRAW
    if (mode == "withdraw" or mode == "both") and charGold < target then
        local needed = target - charGold
        
        if warbandGold < needed then return end
        
        if C_Bank and C_Bank.WithdrawMoney then
            local now = GetTime()
            if (now - lastActionTime) < ACTION_COOLDOWN then return end
            
            local ok, err = pcall(C_Bank.WithdrawMoney, Enum.BankType.Account, needed)
            if ok then
                lastActionTime = now
                if WarbandNexus.LogMoneyTransactionImmediate then
                    WarbandNexus:LogMoneyTransactionImmediate("withdraw", needed, charGold + needed, warbandGold - needed)
                end
            end
        end
    end
end

--============================================================================
-- EVENTS
-- Gold management runs once per bank open (ItemsCacheService BANKFRAME_OPENED →
-- TriggerGoldManagement), not on every PLAYER_MONEY tick — so users can move
-- gold manually for the rest of the session. WN_GOLD_MANAGEMENT_CHANGED applies
-- new settings immediately while the bank is open.
--============================================================================

function WarbandNexus:WN_GOLD_MANAGEMENT_CHANGED()
    lastActionTime = 0
    if WarbandNexus.bankIsOpen then
        PerformGoldManagement()
    end
end

--============================================================================
-- INIT
--============================================================================

function WarbandNexus:InitializeGoldManagementService()
    self:RegisterMessage(E.GOLD_MANAGEMENT_CHANGED)
end

-- Public function that can be called by ItemsCacheService
function WarbandNexus:TriggerGoldManagement()
    C_Timer.After(0.5, function()
        if not WarbandNexus.bankIsOpen then return end
        PerformGoldManagement()
    end)
end

function WarbandNexus:GetEffectiveGoldSettings()
    return GetEffectiveGoldSettings()
end
