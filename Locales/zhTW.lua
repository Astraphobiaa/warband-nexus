--[[
    Warband Nexus - Traditional Chinese Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "zhTW")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus 已載入。輸入 /wn 或 /warbandnexus 打開選項。"
L["VERSION"] = "版本"

-- Slash Commands
L["SLASH_HELP"] = "可用命令:"
L["SLASH_OPTIONS"] = "打開選項面板"
L["SLASH_SCAN"] = "掃描戰團銀行"
L["SLASH_SHOW"] = "顯示/隱藏主視窗"
L["SLASH_DEPOSIT"] = "打開存放佇列"
L["SLASH_SEARCH"] = "搜索物品"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "常規設置"
L["GENERAL_SETTINGS_DESC"] = "配置外掛程式的常規設置"
L["ENABLE_ADDON"] = "啟用外掛程式"
L["ENABLE_ADDON_DESC"] = "啟用或禁用Warband Nexus功能"
L["MINIMAP_ICON"] = "顯示小地圖圖示"
L["MINIMAP_ICON_DESC"] = "顯示或隱藏小地圖按鈕"
L["DEBUG_MODE"] = "調試模式"
L["DEBUG_MODE_DESC"] = "在聊天視窗中啟用調試消息"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "掃描設置"
L["SCANNING_SETTINGS_DESC"] = "配置銀行掃描行為"
L["AUTO_SCAN"] = "自動掃描銀行"
L["AUTO_SCAN_DESC"] = "在打開銀行時自動掃描戰團銀行"
L["SCAN_DELAY"] = "掃描延遲"
L["SCAN_DELAY_DESC"] = "掃描操作之間的延遲（秒）"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "存放設置"
L["DEPOSIT_SETTINGS_DESC"] = "配置物品存放行為"
L["GOLD_RESERVE"] = "保留金幣"
L["GOLD_RESERVE_DESC"] = "在個人庫存中保留的金幣數量（金幣）"
L["AUTO_DEPOSIT_REAGENTS"] = "自動存放藥劑"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "在打開銀行時自動將藥劑放入存放佇列"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "顯示設定"
L["DISPLAY_SETTINGS_DESC"] = "配置外掛程式的視覺化外觀"
L["SHOW_ITEM_LEVEL"] = "顯示物品等級"
L["SHOW_ITEM_LEVEL_DESC"] = "在裝備上顯示物品等級"
L["SHOW_ITEM_COUNT"] = "顯示物品數量"
L["SHOW_ITEM_COUNT_DESC"] = "在物品上顯示堆疊數量"
L["HIGHLIGHT_QUALITY"] = "根據品質高亮"
L["HIGHLIGHT_QUALITY_DESC"] = "根據物品品質添加彩色邊框"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "標籤設置"
L["TAB_SETTINGS_DESC"] = "配置戰團銀行標籤行為"
L["IGNORED_TABS"] = "忽略的標籤"
L["IGNORED_TABS_DESC"] = "選擇要排除在掃描和操作之外的標籤"
L["TAB_1"] = "戰團銀行標籤1"
L["TAB_2"] = "戰團銀行標籤2"
L["TAB_3"] = "戰團銀行標籤3"
L["TAB_4"] = "戰團銀行標籤4"
L["TAB_5"] = "戰團銀行標籤5"

-- Scanner Module
L["SCAN_STARTED"] = "正在掃描戰團銀行..."
L["SCAN_COMPLETE"] = "掃描完成。在 %d 個欄位中找到 %d 個物品。"
L["SCAN_FAILED"] = "掃描失敗：戰團銀行未打開。"
L["SCAN_TAB"] = "正在掃描標籤 %d..."
L["CACHE_CLEARED"] = "物品緩存已清除。"
L["CACHE_UPDATED"] = "物品緩存已更新。"

-- Banker Module
L["BANK_NOT_OPEN"] = "戰團銀行未打開。"
L["DEPOSIT_STARTED"] = "正在開始存放操作..."
L["DEPOSIT_COMPLETE"] = "存放完成。轉移了 %d 個物品。"
L["DEPOSIT_CANCELLED"] = "存放已取消。"
L["DEPOSIT_QUEUE_EMPTY"] = "存放佇列為空。"
L["DEPOSIT_QUEUE_CLEARED"] = "存放佇列已清除。"
L["ITEM_QUEUED"] = "%s 已加入存放佇列。"
L["ITEM_REMOVED"] = "%s 已從佇列中移除。"
L["GOLD_DEPOSITED"] = "已存入 %s 金幣到戰團銀行。"
L["INSUFFICIENT_GOLD"] = "金幣不足，無法存入。"

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global: SEARCH
L["BTN_SCAN"] = "掃描銀行"
L["BTN_DEPOSIT"] = "存放佇列"
L["BTN_SORT"] = "排序銀行"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global: CLOSE
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global: SETTINGS
L["BTN_REFRESH"] = REFRESH -- Blizzard Global: REFRESH (if available, fallback below)
L["BTN_CLEAR_QUEUE"] = "清除佇列"
L["BTN_DEPOSIT_ALL"] = "存放所有物品"
L["BTN_DEPOSIT_GOLD"] = "存放金幣"

-- Item Categories (Using Blizzard Globals where available)
L["CATEGORY_ALL"] = "所有物品"
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "裝備" -- Blizzard Global
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "消耗品" -- 暴雪全域變數
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "藥劑" -- Blizzard Global
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "交易商品" -- Blizzard Global
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "任務物品" -- Blizzard Global
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "雜項" -- Blizzard Global

-- Quality Filters (Using Blizzard Globals - automatically localized!)
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC -- Blizzard Global: "Poor"
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC -- Blizzard Global: "Common"
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC -- Blizzard Global: "Uncommon"
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC -- Blizzard Global: "Rare"
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC -- Blizzard Global: "Epic"
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC -- Blizzard Global: "Legendary"
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC -- Blizzard Global: "Artifact"
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC -- Blizzard Global: "Heirloom"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "統計" -- 暴雪全域變數：STATISTICS
L["STATS_TOTAL_ITEMS"] = "總物品數"
L["STATS_TOTAL_SLOTS"] = "總欄位數"
L["STATS_FREE_SLOTS"] = "空閒欄位數"
L["STATS_USED_SLOTS"] = "已用欄位數"
L["STATS_TOTAL_VALUE"] = "總價值"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "角色" -- 暴雪全域變數：CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "位置" -- 暴雪全域變數：LOCATION_COLON
L["TOOLTIP_WARBAND_BANK"] = "戰團銀行"
L["TOOLTIP_TAB"] = "標籤"
L["TOOLTIP_SLOT"] = "欄位"
L["TOOLTIP_COUNT"] = "數量"

-- Error Messages
L["ERROR_GENERIC"] = "發生錯誤。"
L["ERROR_API_UNAVAILABLE"] = "所需的 API 不可用。"
L["ERROR_BANK_CLOSED"] = "無法執行操作：銀行已關閉。"
L["ERROR_INVALID_ITEM"] = "指定的物品無效。"
L["ERROR_PROTECTED_FUNCTION"] = "無法在戰鬥中調用受保護的函數。"

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "確定將 %d 個物品放入戰團銀行？"
L["CONFIRM_CLEAR_QUEUE"] = "清除存放佇列中的所有物品？"
L["CONFIRM_DEPOSIT_GOLD"] = "確定將 %s 金幣放入戰團銀行？"

-- Profiles (AceDB)
L["PROFILES"] = "設定檔"
L["PROFILES_DESC"] = "管理外掛程式設定檔"