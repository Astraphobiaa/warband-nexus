--[[
    Warband Nexus - Traditional Chinese Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "zhTW")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus 已載入。輸入 /wn 或 /warbandnexus 查看選項。"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "一般設定"
L["ENABLE_ADDON"] = "啟用插件"
L["MINIMAP_ICON"] = "顯示小地圖圖示"
L["DEBUG_MODE"] = "除錯模式"

-- Scanner Module
L["SCAN_STARTED"] = "正在掃描戰團銀行..."
L["SCAN_COMPLETE"] = "掃描完成。在 %d 個格子中找到 %d 個物品。"
L["SCAN_FAILED"] = "掃描失敗：戰團銀行未開啟。"

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = "搜尋物品..."
L["BTN_SCAN"] = "掃描銀行"
L["BTN_DEPOSIT"] = "存放佇列"
L["BTN_SORT"] = "整理銀行"
L["BTN_CLOSE"] = "關閉"
L["BTN_SETTINGS"] = "設定"



