--[[
    Warband Nexus — notification presentation (achievement / criteria lane only)

    Binary fork (Settings: "Warband achievement popups", db.hideBlizzardAchievementAlert):
      ON  -> WN ShowModalNotification; Blizzard AddAlert intercepted; native frames hidden.
      OFF -> Native Blizzard AddAlert + alert frames only; WN achievement/criteria toasts never shown
             (WN_COLLECTIBLE_OBTAINED may still fire with suppressToast for try-counter / recent ring).

    Mount, vault, plan, reminder, and try-counter drop toasts are always WN-themed (no Blizzard lane).
]]

local ADDON_NAME, ns = ...

local NotificationPresentation = {}
ns.NotificationPresentation = NotificationPresentation

---@return table|nil db.profile.notifications
function NotificationPresentation.GetNotificationsDb()
    local addon = ns.WarbandNexus
    if not addon or not addon.db or not addon.db.profile then
        return nil
    end
    return addon.db.profile.notifications
end

---Warband achievement popups ON (WN themed earned + criteria when sub-toggles allow).
---@param db table|nil optional notifications subtable; live profile when nil
---@return boolean
function NotificationPresentation.UseWarbandAchievementPopups(db)
    db = db or NotificationPresentation.GetNotificationsDb()
    return db ~= nil and db.hideBlizzardAchievementAlert == true
end

---Criteria progress compact toast (Warband popups ON + criteria toggle).
---@param db table|nil
---@return boolean
function NotificationPresentation.UseWarbandCriteriaProgressPopups(db)
    db = db or NotificationPresentation.GetNotificationsDb()
    if not NotificationPresentation.UseWarbandAchievementPopups(db) then
        return false
    end
    return db.showCriteriaProgressNotifications ~= false
end

---Master enabled + Warband presentation + earned-achievement sub-toggle.
---@return boolean
function NotificationPresentation.CanShowWarbandAchievementEarnedToast()
    local db = NotificationPresentation.GetNotificationsDb()
    if not db or not db.enabled then
        return false
    end
    if not NotificationPresentation.UseWarbandAchievementPopups(db) then
        return false
    end
    return db.showAchievementNotifications ~= false
end

---Master enabled + Warband criteria presentation.
---@return boolean
function NotificationPresentation.CanShowWarbandCriteriaProgressToast()
    local db = NotificationPresentation.GetNotificationsDb()
    if not db or not db.enabled then
        return false
    end
    return NotificationPresentation.UseWarbandCriteriaProgressPopups(db)
end

local WarbandNexus = ns.WarbandNexus
if WarbandNexus then
    function WarbandNexus:UseWarbandAchievementPopups()
        return NotificationPresentation.UseWarbandAchievementPopups()
    end

    function WarbandNexus:UseWarbandCriteriaProgressPopups()
        return NotificationPresentation.UseWarbandCriteriaProgressPopups()
    end
end
