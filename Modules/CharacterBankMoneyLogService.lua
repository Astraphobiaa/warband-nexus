--[[
    Warband Nexus - Character Bank Money Log Service
    Tracks deposit/withdraw transactions between character and Warband bank.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local MAX_LOG_ENTRIES = 500
local PROCESS_DELAY = 0.05
local DEFER_RECHECK_SEC = 0.15
local DEFER_RECHECK_MAX = 5
local FINAL_FLUSH_DELAY = 0.1
local IMMEDIATE_SUPPRESS_SEC = 1.5

-- Unique AceEvent handler identity (do not use addon object directly)
local MoneyLogEvents = {}

local function GetCurrentCharKey()
    if not ns.Utilities or not ns.Utilities.GetCharacterKey then
        return nil
    end
    return ns.Utilities:GetCharacterKey()
end

local function GetWarbandMoney()
    if not C_Bank or not C_Bank.FetchDepositedMoney or not Enum or not Enum.BankType then
        return 0
    end
    local ok, amount = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    if ok and type(amount) == "number" then
        return amount
    end
    return 0
end

local function EnsureLogStorage()
    if not WarbandNexus.db or not WarbandNexus.db.global then
        return nil
    end
    local logs = WarbandNexus.db.global.characterBankMoneyLogs
    if not logs then
        WarbandNexus.db.global.characterBankMoneyLogs = {}
        return WarbandNexus.db.global.characterBankMoneyLogs
    end
    -- Migrate old per-character format to account-wide array (no numeric indices = old hash)
    if type(logs) == "table" and next(logs) and logs[1] == nil then
        local migrated = {}
        for _, entries in pairs(logs) do
            if type(entries) == "table" then
                for i = 1, #entries do
                    migrated[#migrated + 1] = entries[i]
                end
            end
        end
        WarbandNexus.db.global.characterBankMoneyLogs = migrated
        return migrated
    end
    return logs
end

local function PushLogEntry(charKey, entry)
    if not charKey or not entry then
        return
    end

    local logs = EnsureLogStorage()
    if not logs then
        return
    end

    logs[#logs + 1] = entry

    if WarbandNexus.Print then
        local amountStr = GetCoinTextureString(entry.amount or 0)
        if entry.type == "deposit" then
            WarbandNexus:Print(string.format((ns.L and ns.L["MONEY_LOGS_CHAT_DEPOSIT"]) or "|cff00ff00Money Log:|r Deposited %s to Warband Bank", amountStr))
        else
            WarbandNexus:Print(string.format((ns.L and ns.L["MONEY_LOGS_CHAT_WITHDRAW"]) or "|cffff9900Money Log:|r Withdrew %s from Warband Bank", amountStr))
        end
    end

    local totalLogs = #logs
    if totalLogs > MAX_LOG_ENTRIES then
        local trimmed = {}
        for i = totalLogs - MAX_LOG_ENTRIES + 1, totalLogs do
            trimmed[#trimmed + 1] = logs[i]
        end
        wipe(logs)
        for i = 1, #trimmed do
            logs[i] = trimmed[i]
        end
    end
end

local function SaveSnapshot(charMoney, warbandMoney)
    WarbandNexus._moneyLogLastChar = charMoney
    WarbandNexus._moneyLogLastWarband = warbandMoney
end

local function ClearImmediateLogMarker()
    WarbandNexus._moneyLogImmediateAt = nil
    WarbandNexus._moneyLogImmediateAmount = nil
    WarbandNexus._moneyLogImmediateType = nil
end

--- Returns true if we should skip logging because the same tx was just logged via LogMoneyTransactionImmediate.
local function ShouldSuppressDuplicateImmediate(txType, amount)
    local at = WarbandNexus._moneyLogImmediateAt
    if not at or (GetTime() - at) > IMMEDIATE_SUPPRESS_SEC then
        return false
    end
    if WarbandNexus._moneyLogImmediateType ~= txType then
        return false
    end
    if WarbandNexus._moneyLogImmediateAmount ~= amount then
        return false
    end
    return true
end

local function BuildTransactionEntry(charDelta, warbandDelta)
    local txType = nil
    local amount = 0

    if charDelta < 0 and warbandDelta > 0 then
        txType = "deposit"
        amount = math.min(-charDelta, warbandDelta)
    elseif charDelta > 0 and warbandDelta < 0 then
        txType = "withdraw"
        amount = math.min(charDelta, -warbandDelta)
    end

    if not txType or amount <= 0 then
        return nil
    end

    local _, classFile = UnitClass("player")
    local charKey = GetCurrentCharKey()

    return {
        timestamp = time(),
        type = txType,
        amount = amount,
        character = charKey,
        classFile = classFile,
    }
end

local function ProcessMoneyChange()
    WarbandNexus._moneyLogProcessPending = false

    if not WarbandNexus.bankIsOpen then
        return
    end

    local charKey = GetCurrentCharKey()
    if not charKey then
        return
    end

    local charMoney = GetMoney() or 0
    local warbandMoney = GetWarbandMoney()

    if type(WarbandNexus._moneyLogLastChar) ~= "number" or type(WarbandNexus._moneyLogLastWarband) ~= "number" then
        SaveSnapshot(charMoney, warbandMoney)
        return
    end

    local charDelta = charMoney - WarbandNexus._moneyLogLastChar
    local warbandDelta = warbandMoney - WarbandNexus._moneyLogLastWarband

    -- Both sides must have updated. If only one side changed (e.g. FetchDepositedMoney
    -- updates after PLAYER_MONEY), defer and re-check up to DEFER_RECHECK_MAX times.
    local partialDeposit = (charDelta < 0 and warbandDelta == 0)
    local partialWithdraw = (charDelta == 0 and warbandDelta < 0) or (charDelta > 0 and warbandDelta == 0)
    if partialDeposit or partialWithdraw then
        local deferCount = (WarbandNexus._moneyLogDeferCount or 0) + 1
        WarbandNexus._moneyLogDeferCount = deferCount
        if deferCount <= DEFER_RECHECK_MAX then
            C_Timer.After(DEFER_RECHECK_SEC, ProcessMoneyChange)
        else
            WarbandNexus._moneyLogDeferCount = nil
            -- Fallback: FetchDepositedMoney may never update in some clients; log from single-side delta
            local amount = 0
            local txType = nil
            if charDelta < 0 then
                txType = "deposit"
                amount = -charDelta
            elseif charDelta > 0 then
                txType = "withdraw"
                amount = charDelta
            elseif warbandDelta < 0 then
                txType = "withdraw"
                amount = -warbandDelta
            end
            if txType and amount > 0 then
                local _, classFile = UnitClass("player")
                local entry = {
                    timestamp = time(),
                    type = txType,
                    amount = amount,
                    character = charKey,
                    classFile = classFile,
                }
                if ShouldSuppressDuplicateImmediate(txType, amount) then
                    SaveSnapshot(charMoney, warbandMoney)
                    ClearImmediateLogMarker()
                    return
                end
                PushLogEntry(charKey, entry)
                if WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage("WN_CHARACTER_BANK_MONEY_LOG_UPDATED", charKey)
                end
            end
            SaveSnapshot(charMoney, warbandMoney)
        end
        return
    end

    WarbandNexus._moneyLogDeferCount = nil
    SaveSnapshot(charMoney, warbandMoney)

    if charDelta == 0 and warbandDelta == 0 then
        return
    end

    local entry = BuildTransactionEntry(charDelta, warbandDelta)
    if not entry then
        return
    end

    if ShouldSuppressDuplicateImmediate(entry.type, entry.amount) then
        SaveSnapshot(charMoney, warbandMoney)
        ClearImmediateLogMarker()
        return
    end

    PushLogEntry(charKey, entry)

    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_CHARACTER_BANK_MONEY_LOG_UPDATED", charKey)
    end
end

local function ScheduleMoneyProcessing()
    if not WarbandNexus.bankIsOpen then
        return
    end
    if WarbandNexus._moneyLogProcessPending then
        return
    end
    WarbandNexus._moneyLogProcessPending = true
    C_Timer.After(PROCESS_DELAY, ProcessMoneyChange)
end

--- Called when addon performs automatic deposit/withdraw (e.g. Gold Management).
--- Logs immediately and updates snapshot so event-based detection does not double-log.
---@param txType "deposit"|"withdraw"
---@param amountCopper number Amount in copper
---@param expectedCharMoney number|nil After-transfer character copper (prevents double-log from events)
---@param expectedWarbandMoney number|nil After-transfer warband copper
function WarbandNexus:LogMoneyTransactionImmediate(txType, amountCopper, expectedCharMoney, expectedWarbandMoney)
    if not txType or (txType ~= "deposit" and txType ~= "withdraw") or not amountCopper or amountCopper <= 0 then
        return
    end
    local charKey = GetCurrentCharKey()
    if not charKey then return end
    local _, classFile = UnitClass("player")
    local entry = {
        timestamp = time(),
        type = txType,
        amount = amountCopper,
        character = charKey,
        classFile = classFile,
    }
    PushLogEntry(charKey, entry)
    if self.SendMessage then
        self:SendMessage("WN_CHARACTER_BANK_MONEY_LOG_UPDATED", charKey)
    end
    WarbandNexus._moneyLogImmediateAt = GetTime()
    WarbandNexus._moneyLogImmediateAmount = amountCopper
    WarbandNexus._moneyLogImmediateType = txType
    -- Update snapshot so ProcessMoneyChange (PLAYER_MONEY/ACCOUNT_MONEY) sees no delta and does not double-log
    if type(expectedCharMoney) == "number" and type(expectedWarbandMoney) == "number" then
        SaveSnapshot(expectedCharMoney, expectedWarbandMoney)
    else
        C_Timer.After(0, function()
            SaveSnapshot(GetMoney() or 0, GetWarbandMoney())
        end)
    end
end

function WarbandNexus:GetCharacterBankMoneyLogs(charKey)
    local logs = EnsureLogStorage()
    if not logs or type(logs) ~= "table" then
        return {}
    end
    return logs
end

--- Get per-character contribution summary: deposit total, withdraw total, net (deposit - withdraw).
--- @return table Array of { charKey, classFile, deposit, withdraw, net } sorted by net descending
function WarbandNexus:GetCharacterBankMoneyLogSummary()
    local logs = EnsureLogStorage()
    if not logs or type(logs) ~= "table" then
        return {}
    end
    local byChar = {}
    for i = 1, #logs do
        local e = logs[i]
        if e and e.character then
            local ck = e.character
            if not byChar[ck] then
                byChar[ck] = { charKey = ck, classFile = e.classFile, deposit = 0, withdraw = 0 }
            end
            local amt = e.amount or 0
            if e.type == "deposit" then
                byChar[ck].deposit = byChar[ck].deposit + amt
            elseif e.type == "withdraw" then
                byChar[ck].withdraw = byChar[ck].withdraw + amt
            end
        end
    end
    local out = {}
    for _, v in pairs(byChar) do
        v.net = v.deposit - v.withdraw
        out[#out + 1] = v
    end
    table.sort(out, function(a, b) return a.net > b.net end)
    return out
end

---Clear all money log entries (account-wide).
---@param charKey string|nil Ignored; kept for API compatibility.
function WarbandNexus:ClearCharacterBankMoneyLogs(charKey)
    local logs = EnsureLogStorage()
    if not logs then
        return
    end
    for i = #logs, 1, -1 do
        logs[i] = nil
    end
    if self.SendMessage then
        self:SendMessage("WN_CHARACTER_BANK_MONEY_LOG_UPDATED", nil)
    end
end

function WarbandNexus:InitializeCharacterBankMoneyLogService()
    WarbandNexus.RegisterEvent(MoneyLogEvents, "BANKFRAME_OPENED", function()
        SaveSnapshot(GetMoney() or 0, GetWarbandMoney())
    end)

    WarbandNexus.RegisterEvent(MoneyLogEvents, "BANKFRAME_CLOSED", function()
        -- Capture snapshot before clearing so final flush can log any unreported transfer
        local lastChar = WarbandNexus._moneyLogLastChar
        local lastWarband = WarbandNexus._moneyLogLastWarband
        WarbandNexus._moneyLogLastChar = nil
        WarbandNexus._moneyLogLastWarband = nil
        WarbandNexus._moneyLogProcessPending = false
        WarbandNexus._moneyLogDeferCount = nil
        ClearImmediateLogMarker()

        -- One-shot after a short delay: log any remaining delta (bank just closed, APIs may still be valid)
        if type(lastChar) == "number" or type(lastWarband) == "number" then
            C_Timer.After(FINAL_FLUSH_DELAY, function()
                local charKey = GetCurrentCharKey()
                if not charKey then return end
                local charMoney = GetMoney() or 0
                local warbandMoney = GetWarbandMoney()
                local charDelta = charMoney - (lastChar or charMoney)
                local warbandDelta = warbandMoney - (lastWarband or warbandMoney)
                local entry = BuildTransactionEntry(charDelta, warbandDelta)
                if entry then
                    PushLogEntry(charKey, entry)
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage("WN_CHARACTER_BANK_MONEY_LOG_UPDATED", charKey)
                    end
                else
                    -- Single-side fallback if both sides didn't update in time
                    local amount, txType = 0, nil
                    if charDelta < 0 then
                        txType = "deposit"
                        amount = -charDelta
                    elseif charDelta > 0 then
                        txType = "withdraw"
                        amount = charDelta
                    elseif warbandDelta < 0 then
                        txType = "withdraw"
                        amount = -warbandDelta
                    elseif warbandDelta > 0 then
                        txType = "deposit"
                        amount = warbandDelta
                    end
                    if txType and amount > 0 then
                        local _, classFile = UnitClass("player")
                        local e = {
                            timestamp = time(),
                            type = txType,
                            amount = amount,
                            character = charKey,
                            classFile = classFile,
                        }
                        PushLogEntry(charKey, e)
                        if WarbandNexus.SendMessage then
                            WarbandNexus:SendMessage("WN_CHARACTER_BANK_MONEY_LOG_UPDATED", charKey)
                        end
                    end
                end
            end)
        end
    end)

    WarbandNexus.RegisterEvent(MoneyLogEvents, "PLAYER_MONEY", ScheduleMoneyProcessing)
    WarbandNexus.RegisterEvent(MoneyLogEvents, "ACCOUNT_MONEY", ScheduleMoneyProcessing)
end

