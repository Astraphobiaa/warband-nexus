--[[
    Warband Nexus - Simplified Chinese Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "zhCN")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus 已加载。输入 /wn 或 /warbandnexus 打开选项。"
L["VERSION"] = "版本"

-- Slash Commands
L["SLASH_HELP"] = "可用命令:"
L["SLASH_OPTIONS"] = "打开选项面板"
L["SLASH_SCAN"] = "扫描战团银行"
L["SLASH_SHOW"] = "显示/隐藏主窗口"
L["SLASH_DEPOSIT"] = "打开存放队列"
L["SLASH_SEARCH"] = "搜索物品"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "常规设置"
L["GENERAL_SETTINGS_DESC"] = "配置插件的常规设置"
L["ENABLE_ADDON"] = "启用插件"
L["ENABLE_ADDON_DESC"] = "启用或禁用Warband Nexus功能"
L["MINIMAP_ICON"] = "显示小地图图标"
L["MINIMAP_ICON_DESC"] = "显示或隐藏小地图按钮"
L["DEBUG_MODE"] = "调试模式"
L["DEBUG_MODE_DESC"] = "在聊天窗口中启用调试消息"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "扫描设置"
L["SCANNING_SETTINGS_DESC"] = "配置银行扫描行为"
L["AUTO_SCAN"] = "自动扫描银行"
L["AUTO_SCAN_DESC"] = "在打开银行时自动扫描战团银行"
L["SCAN_DELAY"] = "扫描延迟"
L["SCAN_DELAY_DESC"] = "扫描操作之间的延迟（秒）"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "存放设置"
L["DEPOSIT_SETTINGS_DESC"] = "配置物品存放行为"
L["GOLD_RESERVE"] = "保留金币"
L["GOLD_RESERVE_DESC"] = "在个人库存中保留的金币数量（金币）"
L["AUTO_DEPOSIT_REAGENTS"] = "自动存放药剂"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "在打开银行时自动将药剂放入存放队列"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "显示设置"
L["DISPLAY_SETTINGS_DESC"] = "配置插件的可视化外观"
L["SHOW_ITEM_LEVEL"] = "显示物品等级"
L["SHOW_ITEM_LEVEL_DESC"] = "在装备上显示物品等级"
L["SHOW_ITEM_COUNT"] = "显示物品数量"
L["SHOW_ITEM_COUNT_DESC"] = "在物品上显示堆叠数量"
L["HIGHLIGHT_QUALITY"] = "根据质量高亮"
L["HIGHLIGHT_QUALITY_DESC"] = "根据物品质量添加彩色边框"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "标签设置"
L["TAB_SETTINGS_DESC"] = "配置战团银行标签行为"
L["IGNORED_TABS"] = "忽略的标签"
L["IGNORED_TABS_DESC"] = "选择要排除在扫描和操作之外的标签"
L["TAB_1"] = "战团银行标签1"
L["TAB_2"] = "战团银行标签2"
L["TAB_3"] = "战团银行标签3"
L["TAB_4"] = "战团银行标签4"
L["TAB_5"] = "战团银行标签5"

-- Scanner Module
L["SCAN_STARTED"] = "正在扫描战团银行..."
L["SCAN_COMPLETE"] = "扫描完成。在 %d 个栏位中找到 %d 个物品。"
L["SCAN_FAILED"] = "扫描失败：战团银行未打开。"
L["SCAN_TAB"] = "正在扫描标签 %d..."
L["CACHE_CLEARED"] = "物品缓存已清除。"
L["CACHE_UPDATED"] = "物品缓存已更新。"

-- Banker Module
L["BANK_NOT_OPEN"] = "战团银行未打开。"
L["DEPOSIT_STARTED"] = "正在开始存放操作..."
L["DEPOSIT_COMPLETE"] = "存放完成。转移了 %d 个物品。"
L["DEPOSIT_CANCELLED"] = "存放已取消。"
L["DEPOSIT_QUEUE_EMPTY"] = "存放队列为空。"
L["DEPOSIT_QUEUE_CLEARED"] = "存放队列已清除。"
L["ITEM_QUEUED"] = "%s 已加入存放队列。"
L["ITEM_REMOVED"] = "%s 已从队列中移除。"
L["GOLD_DEPOSITED"] = "已存入 %s 金币到战团银行。"
L["INSUFFICIENT_GOLD"] = "金币不足，无法存入。"

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global: SEARCH
L["BTN_SCAN"] = "扫描银行"
L["BTN_DEPOSIT"] = "存放队列"
L["BTN_SORT"] = "排序银行"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global: CLOSE
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global: SETTINGS
L["BTN_REFRESH"] = REFRESH -- Blizzard Global: REFRESH (if available, fallback below)
L["BTN_CLEAR_QUEUE"] = "清除队列"
L["BTN_DEPOSIT_ALL"] = "存放所有物品"
L["BTN_DEPOSIT_GOLD"] = "存放金币"

-- Item Categories (Using Blizzard Globals where available)
L["CATEGORY_ALL"] = "所有物品"
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "装备" -- Blizzard Global
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "消耗品" -- 暴雪全局变量
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "药剂" -- Blizzard Global
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "交易商品" -- Blizzard Global
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "任务物品" -- Blizzard Global
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "杂项" -- Blizzard Global

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
L["STATS_HEADER"] = STATISTICS or "统计" -- 暴雪全局变量：STATISTICS
L["STATS_TOTAL_ITEMS"] = "总物品数"
L["STATS_TOTAL_SLOTS"] = "总栏位数"
L["STATS_FREE_SLOTS"] = "空闲栏位数"
L["STATS_USED_SLOTS"] = "已用栏位数"
L["STATS_TOTAL_VALUE"] = "总价值"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "角色" -- 暴雪全局变量：CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "位置" -- 暴雪全局变量：LOCATION_COLON
L["TOOLTIP_WARBAND_BANK"] = "战团银行"
L["TOOLTIP_TAB"] = "标签"
L["TOOLTIP_SLOT"] = "栏位"
L["TOOLTIP_COUNT"] = "数量"

-- Error Messages
L["ERROR_GENERIC"] = "发生错误。"
L["ERROR_API_UNAVAILABLE"] = "所需的 API 不可用。"
L["ERROR_BANK_CLOSED"] = "无法执行操作：银行已关闭。"
L["ERROR_INVALID_ITEM"] = "指定的物品无效。"
L["ERROR_PROTECTED_FUNCTION"] = "无法在战斗中调用受保护的函数。"

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "确定将 %d 个物品放入战团银行？"
L["CONFIRM_CLEAR_QUEUE"] = "清除存放队列中的所有物品？"
L["CONFIRM_DEPOSIT_GOLD"] = "确定将 %s 金币放入战团银行？"

-- Profiles (AceDB)
L["PROFILES"] = "配置文件"
L["PROFILES_DESC"] = "管理插件配置文件"