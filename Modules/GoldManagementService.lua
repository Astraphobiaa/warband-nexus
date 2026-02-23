--[[
    Warband Nexus - Gold Management Service
    Automatic gold management using C_Bank API
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- Throttling
local lastActionTime = 0
local ACTION_COOLDOWN = 2

--============================================================================
-- CORE LOGIC
--============================================================================

local function PerformGoldManagement()
    local settings = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.goldManagement
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
            end
        end
    end
end

--============================================================================
-- EVENTS
--============================================================================

function WarbandNexus:PLAYER_MONEY()
    if not WarbandNexus.bankIsOpen then return end
    PerformGoldManagement()
end

function WarbandNexus:ACCOUNT_MONEY()
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
    self:RegisterEvent("PLAYER_MONEY")
    self:RegisterEvent("ACCOUNT_MONEY")
    self:RegisterMessage("WN_GOLD_MANAGEMENT_CHANGED")
end

-- Public function that can be called by ItemsCacheService
function WarbandNexus:TriggerGoldManagement()
    C_Timer.After(0.5, function()
        if not WarbandNexus.bankIsOpen then return end
        PerformGoldManagement()
    end)
end
