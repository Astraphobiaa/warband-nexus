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
    
    local charGold = GetMoney() or 0
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
-- Uses WN_MONEY_UPDATED message (fired by EventManager.OnMoneyChanged)
-- instead of registering PLAYER_MONEY/ACCOUNT_MONEY directly.
-- Core.lua owns both events via AceEvent and routes them to OnMoneyChanged,
-- which fires WN_MONEY_UPDATED after processing.
--============================================================================

function WarbandNexus:WN_MONEY_UPDATED()
    if not WarbandNexus.bankIsOpen then return end
    PerformGoldManagement()
end

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
    self:RegisterMessage(E.MONEY_UPDATED)
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
