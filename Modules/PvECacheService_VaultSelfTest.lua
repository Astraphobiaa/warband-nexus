--[[
    Warband Nexus - Great Vault claim refresh smoke test (/wn vault test).
    Stages synthetic claimable state (no real vault reward required), runs the
    same cache + badge refresh path as a real claim, then restores SavedVariables.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local format = string.format
local time = time

local function getCharKey()
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey then
        local k = CS:ResolveSubsidiaryCharacterKey(WarbandNexus, nil)
        if k and ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            return ns.Utilities:GetCanonicalCharacterKey(k) or k
        end
        if k then return k end
    end
    if ns.Utilities and ns.Utilities.GetCharacterStorageKey then
        local raw = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
        if raw and ns.Utilities.GetCanonicalCharacterKey then
            return ns.Utilities:GetCanonicalCharacterKey(raw) or raw
        end
        return raw
    end
    return nil
end

local function snapshotRewardRow(charKey)
    local pve = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache
    local rewards = pve and pve.greatVault and pve.greatVault.rewards
    local row = rewards and rewards[charKey]
    if not row then return nil end
    return {
        hasAvailableRewards = row.hasAvailableRewards,
        lastUpdate = row.lastUpdate,
        claimedAt = row.claimedAt,
        claimedResetTime = row.claimedResetTime,
    }
end

local function writeRewardRow(charKey, data)
    local pve = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache
    if not pve then return end
    pve.greatVault = pve.greatVault or {}
    pve.greatVault.rewards = pve.greatVault.rewards or {}
    pve.greatVault.rewards[charKey] = data
end

local function restoreRewardRow(charKey, snap)
    local pve = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache
    if not pve or not pve.greatVault or not pve.greatVault.rewards then return end
    if snap then
        pve.greatVault.rewards[charKey] = snap
    else
        pve.greatVault.rewards[charKey] = nil
    end
end

local function countReady()
    local VB = ns.VaultButton
    return (VB and VB.CountReady and VB.CountReady()) or 0
end

local function badgeCount()
    local S = ns.VaultButton and ns.VaultButton.state
    if not S or not S.badge or not S.badge:IsShown() then return 0 end
    return tonumber(S.badge:GetText()) or 0
end

local function clearTestOverride()
    ns._vaultSelfTestOverridePending = nil
end

function WarbandNexus:RunVaultClaimSelfTest()
    local pass, fail = 0, 0
    local function linePass(label)
        pass = pass + 1
        self:Print("|cff00ff00[WN-Vault-Test] PASS|r " .. label)
    end
    local function lineFail(label, detail)
        fail = fail + 1
        local tail = detail and (": " .. tostring(detail)) or ""
        self:Print("|cffff0000[WN-Vault-Test] FAIL|r " .. label .. tail)
    end

    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        self:Print("|cffff6600[WN-Vault-Test]|r Character not tracked — enable tracking first.")
        return
    end

    local charKey = getCharKey()
    if not charKey then
        lineFail("resolve character key")
        return
    end

    local snap = snapshotRewardRow(charKey)
    clearTestOverride()
    local readyBefore = countReady()
    local badgeBefore = badgeCount()

    local ok, err = pcall(function()
        writeRewardRow(charKey, {
            hasAvailableRewards = true,
            lastUpdate = time(),
            claimedAt = nil,
            claimedResetTime = nil,
        })
        ns._vaultSelfTestOverridePending = true
        if ns.PvE_ClearVaultStatusScratch then
            ns.PvE_ClearVaultStatusScratch()
        end
        if self.NotifyVaultEasyAccessRefresh then
            self:NotifyVaultEasyAccessRefresh()
        end

        if not (ns.CharHasClaimableVaultReward and ns.CharHasClaimableVaultReward(charKey)) then
            error("CharHasClaimableVaultReward not true after staging")
        end
        local readyStaged = countReady()
        if readyStaged < readyBefore + 1 and readyBefore == 0 then
            error("CountReady did not increase after staging")
        end
        linePass("staged synthetic claimable vault")

        ns._vaultSelfTestOverridePending = false
        if self.RefreshVaultClaimState then
            self:RefreshVaultClaimState(charKey)
        else
            error("RefreshVaultClaimState missing")
        end

        if ns.CharHasClaimableVaultReward and ns.CharHasClaimableVaultReward(charKey) then
            error("still claimable after RefreshVaultClaimState")
        end
        if ns.PvE_ClearVaultStatusScratch then
            ns.PvE_ClearVaultStatusScratch()
        end
        local vs = self.GetVaultStatusForChar and self:GetVaultStatusForChar(charKey)
        if not vs or vs.isReady then
            error("GetVaultStatusForChar still ready")
        end
        if not vs.claimedThisWeek then
            error("claimedThisWeek not set after simulated claim")
        end
        local readyAfter = countReady()
        local badgeAfter = badgeCount()
        if readyStaged > readyBefore and readyAfter >= readyStaged then
            error(format("ready count still %d (was %d staged)", readyAfter, readyStaged))
        end
        if readyStaged > readyBefore and badgeAfter > 0 and badgeAfter >= math.max(badgeBefore, 1) then
            error(format("badge still %d after claim", badgeAfter))
        end
        linePass("claim refresh cleared badge + status cache")
    end)

    clearTestOverride()
    restoreRewardRow(charKey, snap)
    if ns.PvE_ClearVaultStatusScratch then
        ns.PvE_ClearVaultStatusScratch()
    end
    if self.NotifyVaultEasyAccessRefresh then
        self:NotifyVaultEasyAccessRefresh()
    end
    if self.SavePvECache then
        self:SavePvECache()
    end

    if not ok then
        lineFail("smoke test", err)
    end

    self:Print(format("|cff00ccff[WN-Vault-Test]|r Done: %d passed, %d failed", pass, fail))
end

---Visual sandbox: fake vault ready without a real chest (/wn vault simulate ready).
function WarbandNexus:SimulateVaultReadyForTest()
    if ns._vaultSimSnapshot then
        self:Print("|cffff6600[WN]|r Simulation already active. Use |cff00ccff/wn vault simulate clear|r first.")
        return
    end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        self:Print("|cffff6600[WN]|r Character not tracked.")
        return
    end
    local charKey = getCharKey()
    if not charKey then return end

    ns._vaultSimSnapshot = snapshotRewardRow(charKey)
    writeRewardRow(charKey, {
        hasAvailableRewards = true,
        lastUpdate = time(),
        claimedAt = nil,
        claimedResetTime = nil,
    })
    ns._vaultSelfTestOverridePending = true
    if ns.PvE_ClearVaultStatusScratch then
        ns.PvE_ClearVaultStatusScratch()
    end
    if self.NotifyVaultEasyAccessRefresh then
        self:NotifyVaultEasyAccessRefresh()
    end
    if self.SendMessage and ns.Constants and ns.Constants.EVENTS and ns.Constants.EVENTS.PVE_UPDATED then
        self:SendMessage(ns.Constants.EVENTS.PVE_UPDATED)
    end
    if self.SendMessage and ns.Constants and ns.Constants.EVENTS and ns.Constants.EVENTS.VAULT_REWARD_AVAILABLE then
        self:SendMessage(ns.Constants.EVENTS.VAULT_REWARD_AVAILABLE, {
            charKey = charKey,
            claimable = true,
        })
    end
    self:Print("|cff00ccff[WN]|r Vault simulation ON — Easy Access badge should show 1.")
    self:Print("|cff888888Claim test:|r |cff00ccff/wn vault simulate claim|r  |  Clear: |cff00ccff/wn vault simulate clear|r")
end

function WarbandNexus:SimulateVaultClaimForTest()
    if not ns._vaultSimSnapshot then
        self:Print("|cffff6600[WN]|r No simulation active. Use |cff00ccff/wn vault simulate ready|r first.")
        return
    end
    local charKey = getCharKey()
    if not charKey then return end

    ns._vaultSelfTestOverridePending = false
    if self.RefreshVaultClaimState then
        self:RefreshVaultClaimState(charKey)
    end
    self:Print("|cff00ccff[WN]|r Simulated claim — badge should clear. Use |cff00ccff/wn vault simulate clear|r to restore your real cache row.")
end

function WarbandNexus:ClearVaultSimulationForTest()
    local charKey = getCharKey()
    if ns._vaultSimSnapshot and charKey then
        restoreRewardRow(charKey, ns._vaultSimSnapshot)
    end
    ns._vaultSimSnapshot = nil
    clearTestOverride()
    if ns.PvE_ClearVaultStatusScratch then
        ns.PvE_ClearVaultStatusScratch()
    end
    if self.NotifyVaultEasyAccessRefresh then
        self:NotifyVaultEasyAccessRefresh()
    end
    if self.SendMessage and ns.Constants and ns.Constants.EVENTS and ns.Constants.EVENTS.PVE_UPDATED then
        self:SendMessage(ns.Constants.EVENTS.PVE_UPDATED)
    end
    if self.SavePvECache then
        self:SavePvECache()
    end
    self:Print("|cff00ccff[WN]|r Vault simulation cleared; cache row restored.")
end
