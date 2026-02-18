--[[
    Warband Nexus - Traditional Chinese Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "zhTW")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus 已載入。輸入 /wn 或 /warbandnexus 打開選項。"
L["VERSION"] = GAME_VERSION_LABEL or "版本"

-- Slash Commands
L["SLASH_HELP"] = "可用命令:"
L["SLASH_OPTIONS"] = "打開選項面板"
L["SLASH_SCAN"] = "掃描戰團銀行"
L["SLASH_SHOW"] = "顯示/隱藏主視窗"
L["SLASH_DEPOSIT"] = "打開存放佇列"
L["SLASH_SEARCH"] = "搜尋物品"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "常規設定"
L["GENERAL_SETTINGS_DESC"] = "配置外掛程式的常規設定"
L["ENABLE_ADDON"] = "啟用外掛程式"
L["ENABLE_ADDON_DESC"] = "啟用或停用Warband Nexus功能"
L["MINIMAP_ICON"] = "顯示小地圖圖示"
L["MINIMAP_ICON_DESC"] = "顯示或隱藏小地圖按鈕"
L["DEBUG_MODE"] = "除錯模式"
L["DEBUG_MODE_DESC"] = "在聊天視窗中啟用除錯訊息"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "掃描設定"
L["SCANNING_SETTINGS_DESC"] = "配置銀行掃描行為"
L["AUTO_SCAN"] = "自動掃描銀行"
L["AUTO_SCAN_DESC"] = "在打開銀行時自動掃描戰團銀行"
L["SCAN_DELAY"] = "掃描延遲"
L["SCAN_DELAY_DESC"] = "掃描操作之間的延遲（秒）"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "存放設定"
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
L["TAB_SETTINGS"] = "標籤設定"
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
L["CACHE_CLEARED"] = "物品快取已清除。"
L["CACHE_UPDATED"] = "物品快取已更新。"

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

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "無效金額。"
L["WITHDRAW_BANK_NOT_OPEN"] = "銀行必須打開才能取款！"
L["WITHDRAW_IN_COMBAT"] = "戰鬥中無法取款。"
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "戰團銀行中金幣不足。"
L["WITHDRAWN_LABEL"] = "已取款："
L["WITHDRAW_API_UNAVAILABLE"] = "取款API不可用。"
L["SORT_IN_COMBAT"] = "戰鬥中無法排序。"

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global
L["SEARCH_CATEGORY_FORMAT"] = "搜尋%s..."
L["BTN_SCAN"] = "掃描銀行"
L["BTN_DEPOSIT"] = "存放佇列"
L["BTN_SORT"] = "排序銀行"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "清除佇列"
L["BTN_DEPOSIT_ALL"] = "存放所有物品"
L["BTN_DEPOSIT_GOLD"] = "存放金幣"
L["ENABLE"] = ENABLE or "啟用" -- Blizzard Global
L["ENABLE_MODULE"] = "啟用模組"

-- Main Tabs
L["TAB_CHARACTERS"] = CHARACTER or "角色" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "物品" -- Blizzard Global
L["TAB_STORAGE"] = "倉儲"
L["TAB_PLANS"] = "計畫"
L["TAB_REPUTATION"] = REPUTATION or "聲望" -- Blizzard Global
L["TAB_REPUTATIONS"] = "聲望"
L["TAB_CURRENCY"] = CURRENCY or "貨幣" -- Blizzard Global
L["TAB_CURRENCIES"] = "貨幣"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "統計" -- Blizzard Global

-- Item Categories (Blizzard Globals)
L["CATEGORY_ALL"] = ALL or "所有物品" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "裝備"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "消耗品"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "藥劑"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "交易商品"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "任務物品"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "雜項"

-- Quality Filters (Blizzard Globals - automatically localized)
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC

-- Characters Tab
L["HEADER_FAVORITES"] = FAVORITES or "收藏" -- Blizzard Global
L["HEADER_CHARACTERS"] = CHARACTER or "角色"
L["HEADER_CURRENT_CHARACTER"] = "目前角色"
L["HEADER_WARBAND_GOLD"] = "戰團金幣"
L["HEADER_TOTAL_GOLD"] = "總金幣"
L["HEADER_REALM_GOLD"] = "伺服器金幣"
L["HEADER_REALM_TOTAL"] = "伺服器合計"
L["CHARACTER_LAST_SEEN_FORMAT"] = "最後上線: %s"
L["CHARACTER_GOLD_FORMAT"] = "金幣: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "此伺服器所有角色的合計金幣"

-- Items Tab
L["ITEMS_HEADER"] = "銀行物品"
L["ITEMS_HEADER_DESC"] = "瀏覽和管理你的戰團銀行與個人銀行"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " 物品..."
L["ITEMS_WARBAND_BANK"] = "戰團銀行"
L["ITEMS_PLAYER_BANK"] = BANK or "個人銀行" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "公會銀行" -- Blizzard Global
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "裝備"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "消耗品"
L["GROUP_PROFESSION"] = "專業技能"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "藥劑"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "交易商品"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "任務"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "雜項"
L["GROUP_CONTAINER"] = "容器"

-- Storage Tab
L["STORAGE_HEADER"] = "倉儲瀏覽器"
L["STORAGE_HEADER_DESC"] = "按類型瀏覽所有物品"
L["STORAGE_WARBAND_BANK"] = "戰團銀行"
L["STORAGE_PERSONAL_BANKS"] = "個人銀行"
L["STORAGE_TOTAL_SLOTS"] = "總欄位"
L["STORAGE_FREE_SLOTS"] = "空閒欄位"
L["STORAGE_BAG_HEADER"] = "戰團背包"
L["STORAGE_PERSONAL_HEADER"] = "個人銀行"

-- Plans Tab
L["PLANS_MY_PLANS"] = "我的計畫"
L["PLANS_COLLECTIONS"] = "收藏計畫"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "新增自訂計畫"
L["PLANS_NO_RESULTS"] = "未找到結果。"
L["PLANS_ALL_COLLECTED"] = "所有物品已收集！"
L["PLANS_RECIPE_HELP"] = "右鍵點擊背包中的配方將其新增到此處。"
L["COLLECTION_PLANS"] = "收藏計畫"
L["SEARCH_PLANS"] = "搜尋計畫..."
L["COMPLETED_PLANS"] = "已完成的計畫"
L["SHOW_COMPLETED"] = "顯示已完成"
L["SHOW_PLANNED"] = "顯示已計劃"
L["NO_PLANNED_ITEMS"] = "暫無已計劃的%s"

-- Plans Categories (Blizzard Globals)
L["CATEGORY_MY_PLANS"] = "我的計畫"
L["CATEGORY_DAILY_TASKS"] = "每日任務"
L["CATEGORY_MOUNTS"] = MOUNTS or "坐騎" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "寵物" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "玩具" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "塑形" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "幻象"
L["CATEGORY_TITLES"] = TITLES or "頭銜"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "成就" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " 聲望..."
L["REP_HEADER_WARBAND"] = "戰團聲望"
L["REP_HEADER_CHARACTER"] = "角色聲望"
L["REP_STANDING_FORMAT"] = "等級: %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " 貨幣..."
L["CURRENCY_HEADER_WARBAND"] = "戰團可轉移"
L["CURRENCY_HEADER_CHARACTER"] = "角色綁定"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "團隊副本" -- Blizzard Global
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "地城" -- Blizzard Global
L["PVE_HEADER_DELVES"] = "地下堡"
L["PVE_HEADER_WORLD_BOSS"] = "世界首領"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "統計" -- Blizzard Global: STATISTICS
L["STATS_TOTAL_ITEMS"] = "總物品數"
L["STATS_TOTAL_SLOTS"] = "總欄位數"
L["STATS_FREE_SLOTS"] = "空閒欄位數"
L["STATS_USED_SLOTS"] = "已用欄位數"
L["STATS_TOTAL_VALUE"] = "總價值"
L["COLLECTED"] = "已收集"
L["TOTAL"] = "總計"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "角色" -- Blizzard Global: CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "位置" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "戰團銀行"
L["TOOLTIP_TAB"] = "標籤"
L["TOOLTIP_SLOT"] = "欄位"
L["TOOLTIP_COUNT"] = "數量"
L["CHARACTER_INVENTORY"] = "背包"
L["CHARACTER_BANK"] = "銀行"

-- Try Counter
L["TRY_COUNT"] = "嘗試次數"
L["SET_TRY_COUNT"] = "設定嘗試次數"
L["TRIES"] = "嘗試"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "設定重置週期"
L["DAILY_RESET"] = "每日重置"
L["WEEKLY_RESET"] = "每週重置"
L["NONE_DISABLE"] = "無 (停用)"
L["RESET_CYCLE_LABEL"] = "重置週期："
L["RESET_NONE"] = "無"
L["DOUBLECLICK_RESET"] = "雙擊重置位置"

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

-- Update Notification
L["WHATS_NEW"] = "更新內容"
L["GOT_IT"] = "知道了！"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "成就點數"
L["MOUNTS_COLLECTED"] = "已收集坐騎"
L["BATTLE_PETS"] = "戰鬥寵物"
L["ACCOUNT_WIDE"] = "帳號通用"
L["STORAGE_OVERVIEW"] = "倉儲概覽"
L["WARBAND_SLOTS"] = "戰團欄位"
L["PERSONAL_SLOTS"] = "個人欄位"
L["TOTAL_FREE"] = "總空閒"
L["TOTAL_ITEMS"] = "總物品"
L["WEEKLY_VAULT"] = "每週寶庫"
L["CUSTOM"] = "自訂"
L["NO_PLANS_IN_CATEGORY"] = "此分類中沒有計畫。\n從計畫標籤頁新增計畫。"
L["SOURCE_LABEL"] = "來源："
L["ZONE_LABEL"] = "區域："
L["VENDOR_LABEL"] = "商人："
L["DROP_LABEL"] = "掉落："
L["REQUIREMENT_LABEL"] = "需求："
L["RIGHT_CLICK_REMOVE"] = "右鍵點擊移除"
L["TRACKED"] = "已追蹤"
L["TRACK"] = "追蹤"
L["TRACK_BLIZZARD_OBJECTIVES"] = "在暴雪目標中追蹤（最多10個）"
L["UNKNOWN"] = "未知"
L["NO_REQUIREMENTS"] = "無需求（即時完成）"
L["NO_PLANNED_ACTIVITY"] = "無計畫活動"
L["CLICK_TO_ADD_GOALS"] = "點擊上方的坐騎、寵物或玩具來新增目標！"
L["UNKNOWN_QUEST"] = "未知任務"
L["ALL_QUESTS_COMPLETE"] = "所有任務已完成！"
L["CURRENT_PROGRESS"] = "目前進度"
L["SELECT_CONTENT"] = "選擇內容："
L["QUEST_TYPES"] = "任務類型："
L["WORK_IN_PROGRESS"] = "開發中"
L["RECIPE_BROWSER"] = "配方瀏覽器"
L["NO_RESULTS_FOUND"] = "未找到結果。"
L["TRY_ADJUSTING_SEARCH"] = "嘗試調整搜尋條件或篩選器。"
L["NO_COLLECTED_YET"] = "尚未收集任何%s"
L["START_COLLECTING"] = "開始收集即可在此查看！"
L["ALL_COLLECTED_CATEGORY"] = "所有%s已收集！"
L["COLLECTED_EVERYTHING"] = "您已收集此分類中的所有物品！"
L["PROGRESS_LABEL"] = "進度："
L["REQUIREMENTS_LABEL"] = "需求："
L["INFORMATION_LABEL"] = "資訊："
L["DESCRIPTION_LABEL"] = "描述："
L["REWARD_LABEL"] = "獎勵："
L["DETAILS_LABEL"] = "詳情："
L["COST_LABEL"] = "花費："
L["LOCATION_LABEL"] = "位置："
L["TITLE_LABEL"] = "頭銜："
L["COMPLETED_ALL_ACHIEVEMENTS"] = "您已完成此分類中的所有成就！"
L["DAILY_PLAN_EXISTS"] = "每日計畫已存在"
L["WEEKLY_PLAN_EXISTS"] = "每週計畫已存在"
L["GREAT_VAULT"] = "宏偉寶庫"
L["LOADING_PVE"] = "正在載入PvE資料..."
L["PVE_APIS_LOADING"] = "請稍候，WoW API正在初始化..."
L["NO_VAULT_DATA"] = "無寶庫資料"
L["NO_DATA"] = "無資料"
L["KEYSTONE"] = "鑰石"
L["NO_KEY"] = "無鑰匙"
L["AFFIXES"] = "詞綴"
L["NO_AFFIXES"] = "無詞綴"
L["ONLINE"] = "線上"
L["CONFIRM_DELETE"] = "確定要刪除 |cff00ccff%s|r 嗎？"
L["CANNOT_UNDO"] = "此操作無法撤銷！"
L["DELETE"] = DELETE or "刪除"
L["CANCEL"] = CANCEL or "取消"
L["PERSONAL_ITEMS"] = "個人物品"
L["ACCOUNT_WIDE_LABEL"] = "帳號通用"
L["NO_RESULTS"] = "無結果"
L["NO_REP_MATCH"] = "沒有與 '%s' 匹配的聲望"
L["NO_REP_DATA"] = "無聲望資料"
L["REP_SCAN_TIP"] = "聲望會自動掃描。如果沒有顯示，請嘗試 /reload。"
L["ACCOUNT_WIDE_REPS_FORMAT"] = "帳號通用聲望 (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "無帳號通用聲望"
L["NO_CHARACTER_REPS"] = "無角色聲望"
L["CURRENT_LANGUAGE"] = "目前語言："
L["LANGUAGE_TOOLTIP"] = "外掛程式自動使用WoW遊戲客戶端的語言。如需更改，請更新Battle.net設定。"
L["POPUP_DURATION"] = "彈窗持續時間"
L["POPUP_POSITION"] = "彈窗位置"
L["SET_POSITION"] = "設定位置"
L["DRAG_TO_POSITION"] = "拖曳以定位\n右鍵點擊確認"
L["RESET_DEFAULT"] = "恢復預設"
L["TEST_POPUP"] = "測試彈窗"
L["CUSTOM_COLOR"] = "自訂顏色"
L["OPEN_COLOR_PICKER"] = "打開顏色選擇器"
L["COLOR_PICKER_TOOLTIP"] = "打開WoW原生顏色選擇器以選擇自訂主題顏色"
L["PRESET_THEMES"] = "預設主題"
L["WARBAND_NEXUS_SETTINGS"] = "Warband Nexus 設定"
L["NO_OPTIONS"] = "無選項"
L["NONE_LABEL"] = NONE or "無"
L["MODULE_DISABLED"] = "模組已停用"
L["LOADING"] = "載入中..."
L["PLEASE_WAIT"] = "請稍候..."
L["RESET_PREFIX"] = "重置："
L["TRANSFER_CURRENCY"] = "轉移貨幣"
L["AMOUNT_LABEL"] = "數量："
L["TO_CHARACTER"] = "目標角色："
L["SELECT_CHARACTER"] = "選擇角色..."

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "您的角色"
L["CHARACTERS_TRACKED_FORMAT"] = "%d 個角色已追蹤"
L["NO_CHARACTER_DATA"] = "無角色資料"
L["NO_FAVORITES"] = "還沒有收藏的角色。點擊星標圖示來收藏角色。"
L["ALL_FAVORITED"] = "所有角色都已收藏！"
L["UNTRACKED_CHARACTERS"] = "未追蹤的角色"
L["ILVL_SHORT"] = "iLvl"
L["TIME_LESS_THAN_MINUTE"] = "< 1分鐘前"
L["TIME_MINUTES_FORMAT"] = "%d分鐘前"
L["TIME_HOURS_FORMAT"] = "%d小時前"
L["TIME_DAYS_FORMAT"] = "%d天前"
L["REMOVE_FROM_FAVORITES"] = "從收藏中移除"
L["ADD_TO_FAVORITES"] = "新增到收藏"
L["FAVORITES_TOOLTIP"] = "收藏的角色會顯示在列表頂部"
L["CLICK_TO_TOGGLE"] = "點擊切換"
L["UNKNOWN_PROFESSION"] = "未知專業"
L["SKILL_LABEL"] = "技能："
L["OVERALL_SKILL"] = "總體技能："
L["BONUS_SKILL"] = "獎勵技能："
L["KNOWLEDGE_LABEL"] = "知識："
L["SPEC_LABEL"] = "專精"
L["POINTS_SHORT"] = "點"
L["RECIPES_KNOWN"] = "已知配方："
L["OPEN_PROFESSION_HINT"] = "打開專業視窗"
L["FOR_DETAILED_INFO"] = "查看詳細資訊"
L["CHARACTER_IS_TRACKED"] = "此角色正在被追蹤。"
L["TRACKING_ACTIVE_DESC"] = "資料收集和更新已啟動。"
L["CLICK_DISABLE_TRACKING"] = "點擊停用追蹤。"
L["MUST_LOGIN_TO_CHANGE"] = "您必須登入此角色才能更改追蹤設定。"
L["TRACKING_ENABLED"] = "追蹤已啟用"
L["CLICK_ENABLE_TRACKING"] = "點擊為此角色啟用追蹤。"
L["TRACKING_WILL_BEGIN"] = "資料收集將立即開始。"
L["CHARACTER_NOT_TRACKED"] = "此角色未被追蹤。"
L["MUST_LOGIN_TO_ENABLE"] = "您必須登入此角色才能啟用追蹤。"
L["ENABLE_TRACKING"] = "啟用追蹤"
L["DELETE_CHARACTER_TITLE"] = "刪除角色？"
L["THIS_CHARACTER"] = "此角色"
L["DELETE_CHARACTER"] = "刪除角色"
L["REMOVE_FROM_TRACKING_FORMAT"] = "從追蹤中移除 %s"
L["CLICK_TO_DELETE"] = "點擊刪除"

-- =============================================
-- Items Tab
-- =============================================
L["ITEMS_SUBTITLE"] = "瀏覽您的戰團銀行和個人物品（銀行 + 背包）"
L["ITEMS_DISABLED_TITLE"] = "戰團銀行物品"
L["ITEMS_LOADING"] = "正在載入庫存資料"
L["GUILD_BANK_REQUIRED"] = "您必須加入公會才能存取公會銀行。"
L["ITEMS_SEARCH"] = "搜尋物品..."
L["NEVER"] = "從未"
L["ITEM_FALLBACK_FORMAT"] = "物品 %s"
L["TAB_FORMAT"] = "標籤 %d"
L["BAG_FORMAT"] = "背包 %d"
L["BANK_BAG_FORMAT"] = "銀行背包 %d"
L["ITEM_ID_LABEL"] = "物品ID："
L["QUALITY_TOOLTIP_LABEL"] = "品質："
L["STACK_LABEL"] = "堆疊："
L["RIGHT_CLICK_MOVE"] = "移動到背包"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "拆分堆疊"
L["LEFT_CLICK_PICKUP"] = "拾取"
L["ITEMS_BANK_NOT_OPEN"] = "銀行未打開"
L["SHIFT_LEFT_CLICK_LINK"] = "在聊天中連結"
L["ITEM_DEFAULT_TOOLTIP"] = "物品"
L["ITEMS_STATS_ITEMS"] = "%s 個物品"
L["ITEMS_STATS_SLOTS"] = "%s/%s 個欄位"
L["ITEMS_STATS_LAST"] = "最後：%s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "角色倉儲"
L["STORAGE_SEARCH"] = "搜尋倉儲..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "PvE進度"
L["PVE_SUBTITLE"] = "宏偉寶庫、團隊副本鎖定和傳奇鑰石+ 在您的戰團中"
L["PVE_NO_CHARACTER"] = "無角色資料"
L["LV_FORMAT"] = "等級 %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = "團隊副本"
L["VAULT_DUNGEON"] = "地城"
L["VAULT_WORLD"] = "世界"
L["VAULT_SLOT_FORMAT"] = "%s 欄位 %d"
L["VAULT_NO_PROGRESS"] = "暫無進度"
L["VAULT_UNLOCK_FORMAT"] = "完成 %s 個活動以解鎖"
L["VAULT_NEXT_TIER_FORMAT"] = "下一級：完成 %s 後獲得 %d iLvl"
L["VAULT_REMAINING_FORMAT"] = "剩餘：%s 個活動"
L["VAULT_PROGRESS_FORMAT"] = "進度：%s / %s"
L["OVERALL_SCORE_LABEL"] = "總體評分："
L["BEST_KEY_FORMAT"] = "最佳鑰匙：+%d"
L["SCORE_FORMAT"] = "評分：%s"
L["NOT_COMPLETED_SEASON"] = "本賽季未完成"
L["CURRENT_MAX_FORMAT"] = "目前：%s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "進度：%.1f%%"
L["NO_CAP_LIMIT"] = "無上限"
L["VAULT_BEST_KEY"] = "最佳鑰匙："
L["VAULT_SCORE"] = "評分："

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "聲望概覽"
L["REP_SUBTITLE"] = "追蹤您戰團中的陣營和名望"
L["REP_DISABLED_TITLE"] = "聲望追蹤"
L["REP_LOADING_TITLE"] = "正在載入聲望資料"
L["REP_SEARCH"] = "搜尋聲望..."
L["REP_PARAGON_TITLE"] = "巔峰聲望"
L["REP_REWARD_AVAILABLE"] = "獎勵可用！"
L["REP_CONTINUE_EARNING"] = "繼續獲得聲望以獲取獎勵"
L["REP_CYCLES_FORMAT"] = "週期：%d"
L["REP_PROGRESS_HEADER"] = "進度：%d/%d"
L["REP_PARAGON_PROGRESS"] = "巔峰進度："
L["REP_PROGRESS_COLON"] = "進度："
L["REP_CYCLES_COLON"] = "週期："
L["REP_CHARACTER_PROGRESS"] = "角色進度："
L["REP_RENOWN_FORMAT"] = "名望 %d"
L["REP_PARAGON_FORMAT"] = "巔峰 (%s)"
L["REP_UNKNOWN_FACTION"] = "未知陣營"
L["REP_API_UNAVAILABLE_TITLE"] = "聲望API不可用"
L["REP_API_UNAVAILABLE_DESC"] = "C_Reputation API在此伺服器上不可用。此功能需要WoW 11.0+（地心之戰）。"
L["REP_FOOTER_TITLE"] = "聲望追蹤"
L["REP_FOOTER_DESC"] = "聲望會在登入和更改時自動掃描。使用遊戲內的聲望面板查看詳細資訊和獎勵。"
L["REP_CLEARING_CACHE"] = "正在清除快取並重新載入..."
L["REP_LOADING_DATA"] = "正在載入聲望資料..."
L["REP_MAX"] = "最大"
L["REP_TIER_FORMAT"] = "等級 %d"

-- =============================================
-- Currency Tab
-- =============================================
L["GOLD_LABEL"] = "金幣"
L["CURRENCY_TITLE"] = "貨幣追蹤器"
L["CURRENCY_SUBTITLE"] = "追蹤您所有角色的貨幣"
L["CURRENCY_DISABLED_TITLE"] = "貨幣追蹤"
L["CURRENCY_LOADING_TITLE"] = "正在載入貨幣資料"
L["CURRENCY_SEARCH"] = "搜尋貨幣..."
L["CURRENCY_HIDE_EMPTY"] = "隱藏空"
L["CURRENCY_SHOW_EMPTY"] = "顯示空"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "所有戰團可轉移"
L["CURRENCY_CHARACTER_SPECIFIC"] = "角色特定貨幣"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "貨幣轉移限制"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "暴雪API不支援自動貨幣轉移。請使用遊戲內的貨幣視窗手動轉移戰團貨幣。"
L["CURRENCY_UNKNOWN"] = "未知貨幣"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "從您的「我的計畫」列表中移除所有已完成的計畫。這將刪除所有已完成的自訂計畫，並從計畫中移除已收集的坐騎/寵物/玩具。此操作無法撤銷！"
L["RECIPE_BROWSER_DESC"] = "在遊戲中打開您的專業視窗以瀏覽配方。\n當視窗打開時，外掛程式將掃描可用配方。"
L["SOURCE_ACHIEVEMENT_FORMAT"] = "來源：[成就 %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s 已有一個活躍的每週寶庫計畫。您可以在「我的計畫」分類中找到它。"
L["DAILY_PLAN_EXISTS_DESC"] = "%s 已有一個活躍的每日任務計畫。您可以在「每日任務」分類中找到它。"
L["TRANSMOG_WIP_DESC"] = "塑形收藏追蹤功能正在開發中。\n\n此功能將在未來的更新中提供，具有改進的效能和更好的戰團系統整合。"
L["WEEKLY_VAULT_CARD"] = "每週寶庫卡片"
L["WEEKLY_VAULT_COMPLETE"] = "每週寶庫卡片 - 完成"
L["UNKNOWN_SOURCE"] = "未知來源"
L["DAILY_TASKS_PREFIX"] = "每日任務 - "
L["NO_FOUND_FORMAT"] = "未找到 %s"
L["PLANS_COUNT_FORMAT"] = "%d 個計畫"
L["PET_BATTLE_LABEL"] = "寵物對戰："
L["QUEST_LABEL"] = "任務："

-- =============================================
-- Settings Tab
-- =============================================
L["TAB_FILTERING"] = "標籤篩選"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "通知"
L["SCROLL_SPEED"] = "捲動速度"
L["ANCHOR_FORMAT"] = "錨點：%s  |  X：%d  |  Y：%d"
L["SHOW_WEEKLY_PLANNER"] = "顯示每週計畫器"
L["LOCK_MINIMAP_ICON"] = "鎖定小地圖圖示"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "在滑鼠提示中顯示物品"
L["AUTO_SCAN_ITEMS"] = "自動掃描物品"
L["LIVE_SYNC"] = "即時同步"
L["BACKPACK_LABEL"] = "背包"
L["REAGENT_LABEL"] = "藥劑"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["CURRENCY_TRANSFER_INFO"] = "貨幣視窗將自動打開。\n您需要手動右鍵點擊貨幣進行轉移。"
L["OK_BUTTON"] = OKAY or "確定"
L["SAVE"] = "儲存"
L["TITLE_FIELD"] = "標題："
L["DESCRIPTION_FIELD"] = "描述："
L["CREATE_CUSTOM_PLAN"] = "建立自訂計畫"
L["REPORT_BUGS"] = "在CurseForge上回報錯誤或分享建議以幫助改進外掛程式。"
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus為管理您的所有角色、貨幣、聲望、物品和整個戰團的PvE進度提供集中介面。"
L["CHARACTERS_DESC"] = "查看所有角色的金幣、等級、裝等、陣營、種族、職業、專業、鑰石和最後遊戲時間。追蹤或取消追蹤角色，標記收藏。"
L["ITEMS_DESC"] = "在所有背包、銀行和戰團銀行中搜尋和瀏覽物品。開啟銀行時自動掃描。工具提示顯示哪些角色擁有每件物品。"
L["STORAGE_DESC"] = "所有角色的彙總庫存檢視 — 背包、個人銀行和戰團銀行合併在一個地方。"
L["PVE_DESC"] = "追蹤宏偉寶庫進度（含等級指示器）、傳奇鑰石+評分和鑰石、詞綴、副本歷史和升級貨幣，涵蓋所有角色。"
L["REPUTATIONS_DESC"] = "比較所有角色的聲望進度。顯示帳號通用和角色特定陣營，懸停工具提示可查看每個角色的詳細資訊。"
L["CURRENCY_DESC"] = "按資料片查看所有貨幣。透過懸停工具提示比較角色間數量。一鍵隱藏空貨幣。"
L["PLANS_DESC"] = "追蹤未收集的坐騎、寵物、玩具、成就和塑形。新增目標、查看掉落來源、監控嘗試次數。透過 /wn plan 或小地圖圖示存取。"
L["STATISTICS_DESC"] = "查看成就點數、坐騎/寵物/玩具/幻象/頭銜收藏進度、獨特寵物計數和背包/銀行使用統計。"

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "傳奇"
L["DIFFICULTY_HEROIC"] = "英雄"
L["DIFFICULTY_NORMAL"] = "普通"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "等級 %d"
L["PVP_TYPE"] = "PvP"
L["PREPARING"] = "準備中"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "帳號統計"
L["STATISTICS_SUBTITLE"] = "收藏進度、金幣和倉儲概覽"
L["MOST_PLAYED"] = "遊戲時間最長"
L["PLAYED_DAYS"] = "天"
L["PLAYED_HOURS"] = "小時"
L["PLAYED_MINUTES"] = "分鐘"
L["PLAYED_DAY"] = "天"
L["PLAYED_HOUR"] = "小時"
L["PLAYED_MINUTE"] = "分鐘"
L["MORE_CHARACTERS"] = "個更多角色"
L["MORE_CHARACTERS_PLURAL"] = "個更多角色"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "歡迎使用 Warband Nexus！"
L["ADDON_OVERVIEW_TITLE"] = "外掛程式概覽"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "追蹤您的收藏目標"
L["ACTIVE_PLAN_FORMAT"] = "%d 個活躍計畫"
L["ACTIVE_PLANS_FORMAT"] = "%d 個活躍計畫"
L["RESET_LABEL"] = RESET or "重置"

-- Plans - Type Names
L["TYPE_MOUNT"] = MOUNT or "坐騎"
L["TYPE_PET"] = PET or "寵物"
L["TYPE_TOY"] = TOY or "玩具"
L["TYPE_RECIPE"] = "配方"
L["TYPE_ILLUSION"] = "幻象"
L["TYPE_TITLE"] = "頭銜"
L["TYPE_CUSTOM"] = "自訂"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "塑形"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "掉落"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "任務"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "商人"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "專業"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "寵物對戰"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "成就"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "世界事件"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "促銷"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "集換式卡牌遊戲"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "遊戲內商店"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "製造"
L["SOURCE_TYPE_TRADING_POST"] = "交易站"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "未知"
L["SOURCE_TYPE_PVP"] = PVP or "PvP"
L["SOURCE_TYPE_TREASURE"] = "寶藏"
L["SOURCE_TYPE_PUZZLE"] = "謎題"
L["SOURCE_TYPE_RENOWN"] = "名望"

-- Plans - Transmog Source Labels (Blizzard TRANSMOG_SOURCE_* Globals)
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "首領掉落"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "任務"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "商人"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "世界掉落"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "成就"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "專業"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "出售"
L["PARSE_CRAFTED"] = "製造"
L["PARSE_ZONE"] = ZONE or "區域"
L["PARSE_COST"] = "費用"
L["PARSE_REPUTATION"] = REPUTATION or "聲望"
L["PARSE_FACTION"] = FACTION or "陣營"
L["PARSE_ARENA"] = ARENA or "競技場"
L["PARSE_DUNGEON"] = DUNGEONS or "地城"
L["PARSE_RAID"] = RAID or "團隊副本"
L["PARSE_HOLIDAY"] = "節日"
L["PARSE_RATED"] = "積分"
L["PARSE_BATTLEGROUND"] = "戰場"
L["PARSE_DISCOVERY"] = "發現"
L["PARSE_CONTAINED_IN"] = "包含在"
L["PARSE_GARRISON"] = "要塞"
L["PARSE_GARRISON_BUILDING"] = "要塞建築"
L["PARSE_STORE"] = "商城"
L["PARSE_ORDER_HALL"] = "職業大廳"
L["PARSE_COVENANT"] = "誓盟"
L["PARSE_FRIENDSHIP"] = "友誼"
L["PARSE_PARAGON"] = "巔峰"
L["PARSE_MISSION"] = "任務"
L["PARSE_EXPANSION"] = "資料片"
L["PARSE_SCENARIO"] = "事件戰役"
L["PARSE_CLASS_HALL"] = "職業大廳"
L["PARSE_CAMPAIGN"] = "戰役"
L["PARSE_EVENT"] = "事件"
L["PARSE_SPECIAL"] = "特殊"
L["PARSE_BRAWLERS_GUILD"] = "搏擊俱樂部"
L["PARSE_CHALLENGE_MODE"] = "挑戰模式"
L["PARSE_MYTHIC_PLUS"] = "傳奇鑰石"
L["PARSE_TIMEWALKING"] = "時光漫遊"
L["PARSE_ISLAND_EXPEDITION"] = "島嶼遠征"
L["PARSE_WARFRONT"] = "戰爭前線"
L["PARSE_TORGHAST"] = "乇乂迪斯"
L["PARSE_ZERETH_MORTIS"] = "乂銳乇爪乇殁地"
L["PARSE_HIDDEN"] = "隱藏"
L["PARSE_RARE"] = "稀有"
L["PARSE_WORLD_BOSS"] = "世界首領"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "掉落"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "來自成就"
L["FALLBACK_UNKNOWN_PET"] = "未知寵物"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "寵物收藏"
L["FALLBACK_TOY_COLLECTION"] = "玩具收藏"
L["FALLBACK_TRANSMOG_COLLECTION"] = "幻化收藏"
L["FALLBACK_PLAYER_TITLE"] = "玩家頭銜"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "未知"
L["FALLBACK_ILLUSION_FORMAT"] = "幻象 %s"
L["SOURCE_ENCHANTING"] = "附魔"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "設定嘗試次數：\n%s"
L["RESET_COMPLETED_CONFIRM"] = "您確定要移除所有已完成的計畫嗎？\n\n此操作無法撤銷！"
L["YES_RESET"] = "是，重置"
L["REMOVED_PLANS_FORMAT"] = "已移除 %d 個已完成計畫。"

-- Plans - Buttons
L["ADD_CUSTOM"] = "新增自訂"
L["ADD_VAULT"] = "新增寶庫"
L["ADD_QUEST"] = "新增任務"
L["CREATE_PLAN"] = "建立計畫"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "每日"
L["QUEST_CAT_WORLD"] = "世界"
L["QUEST_CAT_WEEKLY"] = "每週"
L["QUEST_CAT_ASSIGNMENT"] = "任務"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "未知分類"
L["SCANNING_FORMAT"] = "正在掃描 %s"
L["CUSTOM_PLAN_SOURCE"] = "自訂計畫"
L["POINTS_FORMAT"] = "%d 點"
L["SOURCE_NOT_AVAILABLE"] = "來源資訊不可用"
L["PROGRESS_ON_FORMAT"] = "您的進度為 %d/%d"
L["COMPLETED_REQ_FORMAT"] = "您已完成 %d 個總需求中的 %d 個"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "午夜"
L["CONTENT_TWW"] = "地心之戰"
L["QUEST_TYPE_DAILY"] = "每日任務"
L["QUEST_TYPE_DAILY_DESC"] = "來自NPC的常規每日任務"
L["QUEST_TYPE_WORLD"] = "世界任務"
L["QUEST_TYPE_WORLD_DESC"] = "區域範圍的世界任務"
L["QUEST_TYPE_WEEKLY"] = "每週任務"
L["QUEST_TYPE_WEEKLY_DESC"] = "每週循環任務"
L["QUEST_TYPE_ASSIGNMENTS"] = "任務"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "特殊任務和作業"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "傳奇鑰石+"
L["RAIDS_LABEL"] = "團隊副本"

-- PlanCardFactory
L["FACTION_LABEL"] = "陣營："
L["FRIENDSHIP_LABEL"] = "友誼"
L["RENOWN_TYPE_LABEL"] = "名望"
L["ADD_BUTTON"] = "+ 新增"
L["ADDED_LABEL"] = "已新增"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s / %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "在倉儲視圖中顯示物品上的堆疊數量"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "在角色標籤頁中顯示每週計畫器部分"
L["LOCK_MINIMAP_TOOLTIP"] = "鎖定小地圖圖示位置（防止拖曳）"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "在滑鼠提示中顯示戰團和角色物品數量（WN 搜尋）。"
L["AUTO_SCAN_TOOLTIP"] = "打開銀行或背包時自動掃描和快取物品"
L["LIVE_SYNC_TOOLTIP"] = "在銀行打開時即時更新物品快取"
L["SHOW_ILVL_TOOLTIP"] = "在物品列表中的裝備上顯示物品等級徽章"
L["SCROLL_SPEED_TOOLTIP"] = "捲動速度倍數（1.0x = 每步28像素）"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "從自動掃描中忽略戰團銀行標籤 %d"
L["IGNORE_SCAN_FORMAT"] = "從自動掃描中忽略 %s"
L["BANK_LABEL"] = BANK or "銀行"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "啟用通知"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "所有通知彈窗的主開關"
L["VAULT_REMINDER"] = "寶庫提醒"
L["VAULT_REMINDER_TOOLTIP"] = "當您有未領取的每週寶庫獎勵時顯示提醒"
L["LOOT_ALERTS"] = "戰利品警報"
L["LOOT_ALERTS_TOOLTIP"] = "當新的坐騎、寵物或玩具進入您的背包時顯示通知"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "隱藏暴雪成就警報"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "隱藏暴雪的預設成就彈窗，改用Warband Nexus通知"
L["REPUTATION_GAINS"] = "聲望獲得"
L["REPUTATION_GAINS_TOOLTIP"] = "當您獲得陣營聲望時顯示聊天訊息"
L["CURRENCY_GAINS"] = "貨幣獲得"
L["CURRENCY_GAINS_TOOLTIP"] = "當您獲得貨幣時顯示聊天訊息"
L["SCREEN_FLASH_EFFECT"] = "螢幕閃光效果"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "當獲得新的收藏品（坐騎、寵物、玩具等）時播放螢幕閃光效果"
L["AUTO_TRY_COUNTER"] = "自動嘗試計數器"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "在拾取NPC、稀有怪、首領、釣魚或開啟可能掉落坐騎、寵物或玩具的容器時自動追蹤嘗試次數。當收藏品未掉落時在聊天中顯示嘗試次數。"
L["DURATION_LABEL"] = "持續時間"
L["DAYS_LABEL"] = "天"
L["WEEKS_LABEL"] = "週"
L["EXTEND_DURATION"] = "延長時間"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "拖曳綠色框架以設定彈窗位置。右鍵點擊確認。"
L["POSITION_RESET_MSG"] = "彈窗位置已重置為預設（頂部居中）"
L["POSITION_SAVED_MSG"] = "彈窗位置已儲存！"
L["TEST_NOTIFICATION_TITLE"] = "測試通知"
L["TEST_NOTIFICATION_MSG"] = "位置測試"
L["NOTIFICATION_DEFAULT_TITLE"] = "通知"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "主題和外觀"
L["COLOR_PURPLE"] = "紫色"
L["COLOR_PURPLE_DESC"] = "經典紫色主題（預設）"
L["COLOR_BLUE"] = "藍色"
L["COLOR_BLUE_DESC"] = "冷藍色主題"
L["COLOR_GREEN"] = "綠色"
L["COLOR_GREEN_DESC"] = "自然綠色主題"
L["COLOR_RED"] = "紅色"
L["COLOR_RED_DESC"] = "火紅色主題"
L["COLOR_ORANGE"] = "橙色"
L["COLOR_ORANGE_DESC"] = "溫暖橙色主題"
L["COLOR_CYAN"] = "青色"
L["COLOR_CYAN_DESC"] = "明亮青色主題"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "字體族"
L["FONT_FAMILY_TOOLTIP"] = "選擇整個外掛程式UI使用的字體"
L["FONT_SCALE"] = "字體縮放"
L["FONT_SCALE_TOOLTIP"] = "調整所有UI元素的字體大小"
L["FONT_SCALE_WARNING"] = "警告：較大的字型縮放可能導致某些介面元素中的文字溢出。"
L["RESOLUTION_NORMALIZATION"] = "解析度標準化"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "根據螢幕解析度和UI縮放調整字體大小，使文字在不同顯示器上保持相同的實體大小"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "進階"

-- =============================================
-- Settings - Module Management
-- =============================================
L["MODULE_MANAGEMENT"] = "模組管理"
L["MODULE_MANAGEMENT_DESC"] = "啟用或停用特定的資料收集模組。停用模組將停止其資料更新並在介面中隱藏其分頁。"
L["MODULE_CURRENCIES"] = "貨幣"
L["MODULE_CURRENCIES_DESC"] = "追蹤帳號範圍和角色特定的貨幣（金幣、榮譽、征服等）"
L["MODULE_REPUTATIONS"] = "聲望"
L["MODULE_REPUTATIONS_DESC"] = "追蹤陣營聲望進度、名望等級和巔峰獎勵"
L["MODULE_ITEMS"] = "物品"
L["MODULE_ITEMS_DESC"] = "追蹤戰團銀行物品、搜尋功能和物品分類"
L["MODULE_STORAGE"] = "倉庫"
L["MODULE_STORAGE_DESC"] = "追蹤角色背包、個人銀行和戰團銀行存儲"
L["MODULE_PVE"] = "PvE"
L["MODULE_PVE_DESC"] = "追蹤傳奇鑰石地城、團隊副本進度和乾坤寶庫獎勵"
L["MODULE_PLANS"] = "計劃"
L["MODULE_PLANS_DESC"] = "追蹤坐騎、寵物、玩具、成就和自訂任務的個人目標"
L["MODULE_PROFESSIONS"] = "專業技能"
L["MODULE_PROFESSIONS_DESC"] = "追蹤專業技能等級、專注值、知識和配方助手視窗"
L["PROFESSIONS_DISABLED_TITLE"] = "專業技能"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "物品等級 %s"
L["ITEM_NUMBER_FORMAT"] = "物品 #%s"
L["CHARACTER_CURRENCIES"] = "角色貨幣："
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "帳號通用（戰團）— 所有角色共用同一餘額。"
L["YOU_MARKER"] = "（您）"
L["WN_SEARCH"] = "WN 搜尋"
L["WARBAND_BANK_COLON"] = "戰團銀行："
L["AND_MORE_FORMAT"] = "... 還有 %d 個"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "您已收集一個坐騎"
L["COLLECTED_PET_MSG"] = "您已收集一個戰鬥寵物"
L["COLLECTED_TOY_MSG"] = "您已收集一個玩具"
L["COLLECTED_ILLUSION_MSG"] = "您已收集一個幻象"
L["COLLECTED_ITEM_MSG"] = "您獲得了一個稀有掉落"
L["ACHIEVEMENT_COMPLETED_MSG"] = "成就已完成！"
L["EARNED_TITLE_MSG"] = "您已獲得一個頭銜"
L["COMPLETED_PLAN_MSG"] = "您已完成一個計畫"
L["DAILY_QUEST_CAT"] = "每日任務"
L["WORLD_QUEST_CAT"] = "世界任務"
L["WEEKLY_QUEST_CAT"] = "每週任務"
L["SPECIAL_ASSIGNMENT_CAT"] = "特殊任務"
L["DELVE_CAT"] = "地下堡"
L["DUNGEON_CAT"] = "地城"
L["RAID_CAT"] = "團隊副本"
L["WORLD_CAT"] = "世界"
L["ACTIVITY_CAT"] = "活動"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d 進度"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d 進度已完成"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "每週寶庫計畫 - %s"
L["ALL_SLOTS_COMPLETE"] = "所有欄位已完成！"
L["QUEST_COMPLETED_SUFFIX"] = "已完成"
L["WEEKLY_VAULT_READY"] = "每週寶庫已就緒！"
L["UNCLAIMED_REWARDS"] = "您有未領取的獎勵"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "總金幣："
L["CHARACTERS_COLON"] = "角色："
L["LEFT_CLICK_TOGGLE"] = "左鍵點擊：切換視窗"
L["RIGHT_CLICK_PLANS"] = "右鍵點擊：打開計畫"
L["MINIMAP_SHOWN_MSG"] = "小地圖按鈕已顯示"
L["MINIMAP_HIDDEN_MSG"] = "小地圖按鈕已隱藏（使用 /wn minimap 顯示）"
L["TOGGLE_WINDOW"] = "切換視窗"
L["SCAN_BANK_MENU"] = "掃描銀行"
L["TRACKING_DISABLED_SCAN_MSG"] = "角色追蹤已停用。在設定中啟用追蹤以掃描銀行。"
L["SCAN_COMPLETE_MSG"] = "掃描完成！"
L["BANK_NOT_OPEN_MSG"] = "銀行未打開"
L["OPTIONS_MENU"] = "選項"
L["HIDE_MINIMAP_BUTTON"] = "隱藏小地圖按鈕"
L["MENU_UNAVAILABLE_MSG"] = "右鍵選單不可用"
L["USE_COMMANDS_MSG"] = "使用 /wn show, /wn options, /wn help"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "最大"
L["OPEN_AND_GUIDE"] = "打開並引導"
L["FROM_LABEL"] = "來自："
L["AVAILABLE_LABEL"] = "可用："
L["ONLINE_LABEL"] = "（線上）"
L["DATA_SOURCE_TITLE"] = "資料來源資訊"
L["DATA_SOURCE_USING"] = "此標籤頁使用："
L["DATA_SOURCE_MODERN"] = "現代快取服務（事件驅動）"
L["DATA_SOURCE_LEGACY"] = "舊版直接資料庫存取"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "需要遷移到快取服務"
L["GLOBAL_DB_VERSION"] = "全域資料庫版本："

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "角色"
L["INFO_TAB_ITEMS"] = "物品"
L["INFO_TAB_STORAGE"] = "倉儲"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "聲望"
L["INFO_TAB_CURRENCY"] = "貨幣"
L["INFO_TAB_PLANS"] = "計畫"
L["INFO_TAB_STATISTICS"] = "統計"
L["SPECIAL_THANKS"] = "特別感謝"
L["SUPPORTERS_TITLE"] = "支持者"
L["THANK_YOU_MSG"] = "感謝您使用 Warband Nexus！"

-- =============================================
-- Changelog (What's New) - v2.0.0
-- =============================================
L["CHANGELOG_V200"] = "新功能：\n" ..
    "- 角色追蹤：選擇要追蹤或取消追蹤的角色。\n" ..
    "- 智慧貨幣和聲望追蹤：即時聊天通知，包含進度。\n" ..
    "- 坐騎嘗試計數器：追蹤您的掉落嘗試次數（開發中）。\n" ..
    "- 背包 + 銀行 + 戰團銀行追蹤：在所有儲存中追蹤物品。\n" ..
    "- 工具提示系統：全新的自訂工具提示框架。\n" ..
    "- 工具提示物品追蹤器：懸停查看哪些角色擁有該物品。\n" ..
    "- 計畫標籤頁：追蹤您的下一個目標 — 坐騎、寵物、玩具、成就、幻化。\n" ..
    "- 計畫視窗：透過 /wn plan 或右鍵點擊小地圖圖示快速存取。\n" ..
    "- 智慧帳戶資料追蹤：自動戰團範圍資料同步。\n" ..
    "- 本地化：支援11種語言。\n" ..
    "- 聲望和貨幣比較：懸停工具提示顯示每個角色的詳細資訊。\n" ..
    "- 通知系統：戰利品、成就和寶庫提醒。\n" ..
    "- 自訂字體系統：選擇您喜歡的字體和縮放。\n" ..
    "\n" ..
    "改進：\n" ..
    "- 角色資料：新增了陣營、種族、裝等和鑰石資訊。\n" ..
    "- 銀行介面已停用（由改進的儲存替代）。\n" ..
    "- 個人物品：追蹤您的銀行 + 背包。\n" ..
    "- 儲存：在所有角色中追蹤銀行 + 背包 + 戰團銀行。\n" ..
    "- PvE：寶庫等級指示器、地城評分/鑰石追蹤、詞綴、升級貨幣。\n" ..
    "- 聲望標籤頁：簡化檢視（移除舊篩選系統）。\n" ..
    "- 貨幣標籤頁：簡化檢視（移除舊篩選系統）。\n" ..
    "- 統計：新增了獨特寵物計數器。\n" ..
    "- 設定：修訂並重新組織。\n" ..
    "\n" ..
    "感謝您的耐心和關注。\n" ..
    "\n" ..
    "如需回報問題或分享意見回饋，請在CurseForge - Warband Nexus上留言。"

-- =============================================
-- Changelog (What's New) - v2.1.1
-- =============================================
L["CHANGELOG_V211"] = "新功能：\n" ..
    "- 成就彈窗：點擊關聯的成就條件查看詳情，包含追蹤和+新增按鈕。\n" ..
    "- 已計劃指示器：在你的計劃中的物品、坐騎、寵物、玩具和成就名稱後顯示黃色\"(已計劃)\"後綴。\n" ..
    "- 已計劃篩選器：瀏覽檢視中的新核取方塊，僅顯示已計劃的物品。\n" ..
    "- 難度感知嘗試計數器：嘗試次數現在遵循掉落難度要求（例如：弗拉克坐騎僅在英雄+難度計數）。\n" ..
    "\n" ..
    "改進：\n" ..
    "- 計劃介面：瀑布流佈局，卡片排列更緊湊，視覺間隙更少。\n" ..
    "- 計劃介面：已完成的條件不再可互動（追蹤/+新增已停用）。\n" ..
    "- 提示資訊：已收集物品顯示綠色勾選圖示（取代\"已收集\"文字）。\n" ..
    "- 嘗試計數器：劈啪碎片區域追蹤，包含17+個多恩島稀有NPC。\n" ..
    "- 嘗試計數器：雜項機械產出顯示（3坐騎、6寵物）在提示資訊中。\n" ..
    "- Midnight 12.0：難度配對的秘密值保護，確保戰鬥安全。\n" ..
    "\n" ..
    "錯誤修復：\n" ..
    "- 修復嘗試計數器在錯誤難度下遞增（例如：弗拉克在普通難度）。\n" ..
    "- 修復從瀏覽或彈窗點擊+新增後計劃不立即顯示的問題。\n" ..
    "- 修復成就彈窗點擊外部不關閉的問題。\n" ..
    "- 修復商人玩具和背包偵測寵物的通知不觸發的問題。\n" ..
    "- 修復可重複物品掉落的通知不觸發的問題。\n" ..
    "- 修復計劃標籤頁首次載入時卡片佈局間隙的問題。\n" ..
    "\n" ..
    "感謝您的持續支持！\n" ..
    "\n" ..
    "如需回報問題或分享意見回饋，請在CurseForge - Warband Nexus上留言。"

-- =============================================
-- Changelog (What's New) - v2.1.2
-- =============================================
L["CHANGELOG_V212"] = "改進：\n" ..
    "- 專業：專注度追蹤現在能正確獨立識別每個專業。\n" ..
    "- 資料完整性：在所有模組中標準化角色鍵名規範化。\n" ..
    "- 計畫：重複偵測防止重複添加相同項目。\n" ..
    "- 計畫：GetPlanByID現在同時搜尋標準和自訂計畫列表。\n" ..
    "- 貨幣：更嚴格的追蹤過濾器防止未追蹤角色出現。\n" ..
    "- 事件：節流函數在執行前設置計時器以防止重入。\n" ..
    "- 嘗試計數器：擴展難度映射（普通、10人普通、25人普通、隨機團隊）。\n" ..
    "\n" ..
    "錯誤修復：\n" ..
    "- 修復了專業之間專注度資料被覆蓋的問題（例如煉金術顯示銘文值）。\n" ..
    "- 修復了開啟不同專業視窗時專注度互換的問題。\n" ..
    "- 修復了處理程序或參數為空時事件佇列崩潰的問題。\n" ..
    "- 修復了資料庫未初始化時PvE快取清除崩潰的問題。\n" ..
    "- 修復了父框架無寬度時卡片佈局除以零的問題。\n" ..
    "\n" ..
    "清理：\n" ..
    "- 移除了未使用的金幣轉移UI程式碼和相關本地化鍵。\n" ..
    "- 移除了未使用的掃描狀態UI元素。\n" ..
    "\n" ..
    "感謝您的持續支持！\n" ..
    "\n" ..
    "如需回報問題或分享意見，請在CurseForge - Warband Nexus上留言。"

-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "確認操作"
L["CONFIRM"] = "確認"
L["ENABLE_TRACKING_FORMAT"] = "為 |cffffcc00%s|r 啟用追蹤？"
L["DISABLE_TRACKING_FORMAT"] = "為 |cffffcc00%s|r 停用追蹤？"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "帳號通用聲望 (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "角色聲望 (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "獎勵等待中"
L["REP_PARAGON_LABEL"] = "巔峰"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "準備中..."
L["REP_LOADING_INITIALIZING"] = "初始化中..."
L["REP_LOADING_FETCHING"] = "正在取得聲望資料..."
L["REP_LOADING_PROCESSING"] = "正在處理 %d 個陣營..."
L["REP_LOADING_PROCESSING_COUNT"] = "正在處理... (%d/%d)"
L["REP_LOADING_SAVING"] = "正在儲存到資料庫..."
L["REP_LOADING_COMPLETE"] = "完成！"

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "戰鬥中無法打開視窗。請在戰鬥結束後重試。"
L["BANK_IS_ACTIVE"] = "銀行已啟動"
L["ITEMS_CACHED_FORMAT"] = "%d 個物品已快取"
-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "角色"
L["TABLE_HEADER_LEVEL"] = "等級"
L["TABLE_HEADER_GOLD"] = "金幣"
L["TABLE_HEADER_LAST_SEEN"] = "最後上線"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "沒有與 '%s' 匹配的物品"
L["NO_ITEMS_MATCH_GENERIC"] = "沒有與您的搜尋匹配的物品"
L["ITEMS_SCAN_HINT"] = "物品會自動掃描。如果沒有顯示，請嘗試 /reload。"
L["ITEMS_WARBAND_BANK_HINT"] = "打開戰團銀行以掃描物品（首次存取時自動掃描）"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "下一步："
L["CURRENCY_TRANSFER_STEP_1"] = "在貨幣視窗中找到 |cffffffff%s|r"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800右鍵點擊|r 它"
L["CURRENCY_TRANSFER_STEP_3"] = "選擇 |cffffffff'轉移到戰團'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "選擇 |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "輸入金額：|cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "貨幣視窗現已打開！"
L["CURRENCY_TRANSFER_SECURITY"] = "（暴雪安全機制阻止自動轉移）"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "區域："
L["ADDED"] = "已新增"
L["WEEKLY_VAULT_TRACKER"] = "每週寶庫追蹤器"
L["DAILY_QUEST_TRACKER"] = "每日任務追蹤器"
L["CUSTOM_PLAN_STATUS"] = "自訂計畫 '%s' %s"

-- =============================================
-- Achievement Popup
-- =============================================
L["ACHIEVEMENT_COMPLETED"] = "已完成"
L["ACHIEVEMENT_NOT_COMPLETED"] = "未完成"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d 點"
L["ADD_PLAN"] = "新增"
L["PLANNED"] = "已計劃"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = "地城"
L["VAULT_SLOT_RAIDS"] = "團隊副本"
L["VAULT_SLOT_WORLD"] = "世界"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "詞綴"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_STANDING_LABEL"] = "目前"
L["CHAT_GAINED_PREFIX"] = "+"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "計畫已完成："
L["WEEKLY_VAULT_PLAN_NAME"] = "每週寶庫 - %s"
L["VAULT_PLANS_RESET"] = "每週宏偉寶庫計畫已重置！（%d 個計畫%s）"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "未找到角色"
L["EMPTY_CHARACTERS_DESC"] = "使用角色登入以開始追蹤。\n角色資料會在每次登入時自動收集。"
L["EMPTY_ITEMS_TITLE"] = "無快取物品"
L["EMPTY_ITEMS_DESC"] = "開啟戰團銀行或個人銀行來掃描物品。\n物品會在首次造訪時自動快取。"
L["EMPTY_STORAGE_TITLE"] = "無儲存資料"
L["EMPTY_STORAGE_DESC"] = "開啟銀行或背包時會掃描物品。\n造訪銀行以開始追蹤您的儲存。"
L["EMPTY_PLANS_TITLE"] = "暫無計畫"
L["EMPTY_PLANS_DESC"] = "瀏覽上方的坐騎、寵物、玩具或成就\n來新增收藏目標並追蹤進度。"
L["EMPTY_REPUTATION_TITLE"] = "無聲望資料"
L["EMPTY_REPUTATION_DESC"] = "聲望會在登入時自動掃描。\n使用角色登入以開始追蹤陣營聲望。"
L["EMPTY_CURRENCY_TITLE"] = "無貨幣資料"
L["EMPTY_CURRENCY_DESC"] = "貨幣會在所有角色間自動追蹤。\n使用角色登入以開始追蹤貨幣。"
L["EMPTY_PVE_TITLE"] = "無PvE資料"
L["EMPTY_PVE_DESC"] = "PvE進度會在角色登入時追蹤。\n宏偉寶庫、傳奇鑰石+和團本鎖定將顯示在此。"
L["EMPTY_STATISTICS_TITLE"] = "無可用統計"
L["EMPTY_STATISTICS_DESC"] = "統計資料來自您追蹤的角色。\n使用角色登入以開始收集資料。"
L["NO_ADDITIONAL_INFO"] = "無額外資訊"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "你想追蹤這個角色嗎？"
L["CLEANUP_NO_INACTIVE"] = "未找到不活躍的角色（90天以上）"
L["CLEANUP_REMOVED_FORMAT"] = "已移除 %d 個不活躍角色"
L["TRACKING_ENABLED_MSG"] = "角色追蹤已啟用！"
L["TRACKING_DISABLED_MSG"] = "角色追蹤已停用！"
L["TRACKING_ENABLED"] = "追蹤已啟用"
L["TRACKING_DISABLED"] = "追蹤已停用（唯讀模式）"
L["STATUS_LABEL"] = "狀態："
L["ERROR_LABEL"] = "錯誤："
L["ERROR_NAME_REALM_REQUIRED"] = "需要角色名稱和伺服器"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s 已有活躍的每週計劃"

-- Profiles (AceDB)
L["PROFILES"] = "設定檔"
L["PROFILES_DESC"] = "管理外掛程式設定檔"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "未找到條件"
L["NO_REQUIREMENTS_INSTANT"] = "無需求（即時完成）"

-- Statistics Tab (missing)
L["TOTAL_PETS"] = "寵物總數"

-- Items Tab (missing)
L["ITEM_LOADING_NAME"] = "載入中..."

-- Transmog Slot Names (Blizzard INVTYPE_* Globals)
L["SLOT_HEAD"] = INVTYPE_HEAD or "Head"
L["SLOT_SHOULDER"] = INVTYPE_SHOULDER or "Shoulder"
L["SLOT_BACK"] = INVTYPE_CLOAK or "Back"
L["SLOT_CHEST"] = INVTYPE_CHEST or "Chest"
L["SLOT_SHIRT"] = INVTYPE_BODY or "Shirt"
L["SLOT_TABARD"] = INVTYPE_TABARD or "Tabard"
L["SLOT_WRIST"] = INVTYPE_WRIST or "Wrist"
L["SLOT_HANDS"] = INVTYPE_HAND or "Hands"
L["SLOT_WAIST"] = INVTYPE_WAIST or "Waist"
L["SLOT_LEGS"] = INVTYPE_LEGS or "Legs"
L["SLOT_FEET"] = INVTYPE_FEET or "Feet"
L["SLOT_MAINHAND"] = INVTYPE_WEAPONMAINHAND or "Main Hand"
L["SLOT_OFFHAND"] = INVTYPE_WEAPONOFFHAND or "Off Hand"

-- =============================================
-- Professions Tab
-- =============================================
L["TAB_PROFESSIONS"] = "專業技能"
L["YOUR_PROFESSIONS"] = "戰團專業技能"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s 個角色有專業技能"
L["HEADER_PROFESSIONS"] = "專業技能概覽"
L["NO_PROFESSIONS_DATA"] = "尚無專業技能資料。在每個角色上開啟專業技能視窗（預設：K）以收集資料。"
L["CONCENTRATION"] = "專注"
L["KNOWLEDGE"] = "知識"
L["SKILL"] = "技能"
L["RECIPES"] = "配方"
L["UNSPENT_POINTS"] = "未使用點數"
L["COLLECTIBLE"] = "可收集"
L["RECHARGE"] = "充能"
L["FULL"] = "已滿"
L["PROF_OPEN_RECIPE"] = "開啟"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "開啟此專業的配方列表"
L["PROF_ONLY_CURRENT_CHAR"] = "僅目前角色可用"
L["NO_PROFESSION"] = "無專業"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "首次製作"
L["SKILL_UPS"] = "技能提升"
L["COOLDOWNS"] = "冷卻"
L["ORDERS"] = "訂單"

-- Professions: Tooltips & Details
L["LEARNED_RECIPES"] = "已學配方"
L["UNLEARNED_RECIPES"] = "未學配方"
L["LAST_SCANNED"] = "上次掃描"
L["JUST_NOW"] = "剛剛"
L["RECIPE_NO_DATA"] = "開啟專業技能視窗以收集配方資料"
L["FIRST_CRAFT_AVAILABLE"] = "可用首次製作"
L["FIRST_CRAFT_DESC"] = "首次製作時給予額外經驗的配方"
L["SKILLUP_RECIPES"] = "技能提升配方"
L["SKILLUP_DESC"] = "仍可提升技能等級的配方"
L["NO_ACTIVE_COOLDOWNS"] = "無活躍冷卻"

-- Professions: Crafting Orders
L["CRAFTING_ORDERS"] = "製造訂單"
L["PERSONAL_ORDERS"] = "個人訂單"
L["PUBLIC_ORDERS"] = "公開訂單"
L["CLAIMS_REMAINING"] = "剩餘領取"
L["NO_ACTIVE_ORDERS"] = "無活躍訂單"
L["ORDER_NO_DATA"] = "在製造台開啟專業以掃描"

-- Professions: Equipment
L["EQUIPMENT"] = "裝備"
L["TOOL"] = "工具"
L["ACCESSORY"] = "配件"

-- =============================================
-- New keys (v2.1.0)
-- =============================================
L["TOOLTIP_ATTEMPTS"] = "嘗試"
L["TOOLTIP_100_DROP"] = "100% 掉落"
L["TOOLTIP_UNKNOWN"] = "未知"
L["TOOLTIP_WARBAND_BANK"] = "戰團銀行"
L["TOOLTIP_HOLD_SHIFT"] = "  按住 [Shift] 查看完整列表"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - 專注"
L["TOOLTIP_FULL"] = "(已滿)"
L["NO_ITEMS_CACHED_TITLE"] = "無快取物品"
L["COMBAT_CURRENCY_ERROR"] = "戰鬥中無法開啟貨幣視窗。請於戰鬥結束後重試。"
L["DB_LABEL"] = "DB:"
L["COLLECTING_PVE"] = "正在收集 PvE 資料"
L["PVE_PREPARING"] = "準備中"
L["PVE_GREAT_VAULT"] = "大寶庫"
L["PVE_MYTHIC_SCORES"] = "傳奇鑰石+ 評分"
L["PVE_RAID_LOCKOUTS"] = "團隊副本鎖定"
L["PVE_INCOMPLETE_DATA"] = "部分資料可能不完整。請稍後重新整理。"
L["VAULT_SLOTS_TO_FILL"] = "需填充 %d 個大寶庫欄位%s"
L["VAULT_SLOT_PLURAL"] = ""
L["REP_RENOWN_NEXT"] = "名望 %d"
L["REP_TO_NEXT_FORMAT"] = "距離 %s 還需 %s 聲望 (%s)"
L["REP_FACTION_FALLBACK"] = "陣營"
L["COLLECTION_CANCELLED"] = "使用者已取消收集"
L["CLEANUP_STALE_FORMAT"] = "已清理 %d 個過期角色"
L["PERSONAL_BANK"] = "個人銀行"
L["WARBAND_BANK_LABEL"] = "戰團銀行"
L["WARBAND_BANK_TAB_FORMAT"] = "標籤 %d"
L["CURRENCY_OTHER"] = "其他"
L["ERROR_SAVING_CHARACTER"] = "儲存角色時發生錯誤："
L["STANDING_HATED"] = "仇恨"
L["STANDING_HOSTILE"] = "敵對"
L["STANDING_UNFRIENDLY"] = "冷淡"
L["STANDING_NEUTRAL"] = "中立"
L["STANDING_FRIENDLY"] = "友善"
L["STANDING_HONORED"] = "尊敬"
L["STANDING_REVERED"] = "崇敬"
L["STANDING_EXALTED"] = "崇拜"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%s 已嘗試 %d 次"
L["TRYCOUNTER_OBTAINED_RESET"] = "已獲得 %s！嘗試次數已重置。"
L["TRYCOUNTER_CAUGHT_RESET"] = "已捕獲 %s！嘗試次數已重置。"
L["TRYCOUNTER_CONTAINER_RESET"] = "從容器中獲得 %s！嘗試次數已重置。"
L["TRYCOUNTER_LOCKOUT_SKIP"] = "已跳過：此 NPC 有每日/每週鎖定。"
L["TRYCOUNTER_INSTANCE_DROPS"] = "此副本中的可收集掉落："
L["TRYCOUNTER_COLLECTED_TAG"] = "(已收集)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " 次嘗試"
L["TRYCOUNTER_TYPE_MOUNT"] = "坐騎"
L["TRYCOUNTER_TYPE_PET"] = "寵物"
L["TRYCOUNTER_TYPE_TOY"] = "玩具"
L["TRYCOUNTER_TYPE_ITEM"] = "物品"
L["TRYCOUNTER_TRY_COUNTS"] = "嘗試次數"
L["LT_CHARACTER_DATA"] = "角色資料"
L["LT_CURRENCY_CACHES"] = "貨幣與快取"
L["LT_REPUTATIONS"] = "聲望"
L["LT_PROFESSIONS"] = "專業技能"
L["LT_PVE_DATA"] = "PvE 資料"
L["LT_COLLECTIONS"] = "收藏"
L["CONFIG_HEADER"] = "Warband Nexus"
L["CONFIG_HEADER_DESC"] = "現代化戰團管理與跨角色追蹤。"
L["CONFIG_GENERAL"] = "常規設定"
L["CONFIG_GENERAL_DESC"] = "外掛程式的基本設定與行為選項。"
L["CONFIG_ENABLE"] = "啟用外掛程式"
L["CONFIG_ENABLE_DESC"] = "開啟或關閉外掛程式。"
L["CONFIG_MINIMAP"] = "小地圖按鈕"
L["CONFIG_MINIMAP_DESC"] = "在小地圖上顯示按鈕以便快速存取。"
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "在滑鼠提示中顯示物品"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "在物品滑鼠提示中顯示戰團和角色物品數量。"
L["CONFIG_MODULES"] = "模組管理"
L["CONFIG_MODULES_DESC"] = "啟用或停用各個外掛程式模組。停用的模組將不會收集資料或顯示介面標籤頁。"
L["CONFIG_MOD_CURRENCIES"] = "貨幣"
L["CONFIG_MOD_CURRENCIES_DESC"] = "追蹤所有角色的貨幣。"
L["CONFIG_MOD_REPUTATIONS"] = "聲望"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "追蹤所有角色的聲望。"
L["CONFIG_MOD_ITEMS"] = "物品"
L["CONFIG_MOD_ITEMS_DESC"] = "追蹤背包和銀行中的物品。"
L["CONFIG_MOD_STORAGE"] = "倉儲"
L["CONFIG_MOD_STORAGE_DESC"] = "用於背包和銀行管理的倉儲標籤頁。"
L["CONFIG_MOD_PVE"] = "PvE"
L["CONFIG_MOD_PVE_DESC"] = "追蹤大寶庫、傳奇鑰石+和團隊副本鎖定。"
L["CONFIG_MOD_PLANS"] = "計畫"
L["CONFIG_MOD_PLANS_DESC"] = "收藏計畫追蹤與完成目標。"
L["CONFIG_MOD_PROFESSIONS"] = "專業技能"
L["CONFIG_MOD_PROFESSIONS_DESC"] = "追蹤專業技能等級、配方和專注值。"
L["CONFIG_AUTOMATION"] = "自動化"
L["CONFIG_AUTOMATION_DESC"] = "控制開啟戰團銀行時自動執行的操作。"
L["CONFIG_AUTO_OPTIMIZE"] = "自動最佳化資料庫"
L["CONFIG_AUTO_OPTIMIZE_DESC"] = "登入時自動最佳化資料庫以保持儲存效率。"
L["CONFIG_SHOW_ITEM_COUNT"] = "顯示物品數量"
L["CONFIG_SHOW_ITEM_COUNT_DESC"] = "顯示物品數量滑鼠提示，展示您在所有角色中每種物品的數量。"
L["CONFIG_THEME_COLOR"] = "主主題顏色"
L["CONFIG_THEME_COLOR_DESC"] = "選擇外掛程式介面的主要強調色。"
L["CONFIG_THEME_PRESETS"] = "主題預設"
L["CONFIG_THEME_APPLIED"] = "已套用 %s 主題！"
L["CONFIG_THEME_RESET_DESC"] = "將所有主題顏色重置為預設紫色主題。"
L["CONFIG_NOTIFICATIONS"] = "通知"
L["CONFIG_NOTIFICATIONS_DESC"] = "設定顯示哪些通知。"
L["CONFIG_ENABLE_NOTIFICATIONS"] = "啟用通知"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "為收藏品事件顯示彈窗通知。"
L["CONFIG_NOTIFY_MOUNTS"] = "坐騎通知"
L["CONFIG_NOTIFY_MOUNTS_DESC"] = "學習新坐騎時顯示通知。"
L["CONFIG_NOTIFY_PETS"] = "寵物通知"
L["CONFIG_NOTIFY_PETS_DESC"] = "學習新寵物時顯示通知。"
L["CONFIG_NOTIFY_TOYS"] = "玩具通知"
L["CONFIG_NOTIFY_TOYS_DESC"] = "學習新玩具時顯示通知。"
L["CONFIG_NOTIFY_ACHIEVEMENTS"] = "成就通知"
L["CONFIG_NOTIFY_ACHIEVEMENTS_DESC"] = "獲得成就時顯示通知。"
L["CONFIG_SHOW_UPDATE_NOTES"] = "再次顯示更新說明"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "下次登入時顯示更新內容視窗。"
L["CONFIG_UPDATE_NOTES_SHOWN"] = "下次登入時將顯示更新通知。"
L["CONFIG_RESET_PLANS"] = "重置已完成計畫"
L["CONFIG_RESET_PLANS_CONFIRM"] = "這將移除所有已完成計畫。是否繼續？"
L["CONFIG_RESET_PLANS_FORMAT"] = "已移除 %d 個已完成計畫。"
L["CONFIG_NO_COMPLETED_PLANS"] = "沒有可移除的已完成計畫。"
L["CONFIG_TAB_FILTERING"] = "標籤篩選"
L["CONFIG_TAB_FILTERING_DESC"] = "選擇主視窗中顯示的標籤頁。"
L["CONFIG_CHARACTER_MGMT"] = "角色管理"
L["CONFIG_CHARACTER_MGMT_DESC"] = "管理已追蹤角色並移除舊資料。"
L["CONFIG_DELETE_CHAR"] = "刪除角色資料"
L["CONFIG_DELETE_CHAR_DESC"] = "永久移除所選角色的所有儲存資料。"
L["CONFIG_DELETE_CONFIRM"] = "確定要永久刪除此角色的所有資料嗎？此操作無法撤銷。"
L["CONFIG_DELETE_SUCCESS"] = "角色資料已刪除："
L["CONFIG_DELETE_FAILED"] = "未找到角色資料。"
L["CONFIG_FONT_SCALING"] = "字體與縮放"
L["CONFIG_FONT_SCALING_DESC"] = "調整字體族和大小縮放。"
L["CONFIG_FONT_FAMILY"] = "字體族"
L["CONFIG_FONT_SIZE"] = "字體大小縮放"
L["CONFIG_FONT_PREVIEW"] = "預覽：The quick brown fox jumps over the lazy dog"
L["CONFIG_ADVANCED"] = "進階"
L["CONFIG_ADVANCED_DESC"] = "進階設定與資料庫管理。請謹慎使用！"
L["CONFIG_DEBUG_MODE"] = "除錯模式"
L["CONFIG_DEBUG_MODE_DESC"] = "啟用詳細日誌記錄以便除錯。僅在排查問題時啟用。"
L["CONFIG_DB_STATS"] = "顯示資料庫統計"
L["CONFIG_DB_STATS_DESC"] = "顯示目前資料庫大小和最佳化統計。"
L["CONFIG_DB_OPTIMIZER_NA"] = "資料庫最佳化器未載入"
L["CONFIG_OPTIMIZE_NOW"] = "立即最佳化資料庫"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "執行資料庫最佳化器以清理和壓縮儲存的資料。"
L["CONFIG_COMMANDS_HEADER"] = "斜線命令"
L["DISPLAY_SETTINGS"] = "顯示"
L["DISPLAY_SETTINGS_DESC"] = "自訂物品和資訊的顯示方式。"
L["RESET_DEFAULT"] = "恢復預設"
L["ANTI_ALIASING"] = "抗鋸齒"

L["PROFESSIONS_INFO_DESC"] = "追蹤所有角色的專業技能、專注、知識和專精樹。包含用於尋找試劑來源的 Recipe Companion。"
L["CONTRIBUTORS_TITLE"] = "貢獻者"
L["CHANGELOG_V210"] = "新功能：\n" ..
    "- 專業技能標籤頁：追蹤所有角色的專業技能、專注、知識和專精樹。\n" ..
    "- Recipe Companion 視窗：瀏覽並追蹤 Warband Bank 中帶有試劑來源的配方。\n" ..
    "- 載入遮罩：資料同步期間的視覺進度指示器。\n" ..
    "- 持久化通知去重：收藏品通知不再在會話間重複顯示。\n" ..
    "\n" ..
    "改進：\n" ..
    "- 效能：透過時間預算初始化顯著減少了登入時的 FPS 下降。\n" ..
    "- 效能：移除了地城導覽手冊掃描以消除幀率波動。\n" ..
    "- PvE：分身角色資料現在可以正確在角色間持久化和顯示。\n" ..
    "- PvE：登出時儲存 Great Vault 資料以防止非同步資料遺失。\n" ..
    "- 貨幣：與 Blizzard 原生介面匹配的層級標題顯示（Legacy、Season 分組）。\n" ..
    "- 貨幣：更快的初始資料填充。\n" ..
    "- 通知：抑制了不可刷取物品（任務獎勵、商人物品）的提醒。\n" ..
    "- 設定：視窗現在重用框架，關閉時不再偏移主視窗。\n" ..
    "- 角色追蹤：資料收集完全取決於追蹤確認。\n" ..
    "- 角色：沒有專業的角色現在也會顯示專業行。\n" ..
    "- 介面：改進了所有顯示中的文字間距（X : Y 格式）。\n" ..
    "\n" ..
    "錯誤修復：\n" ..
    "- 修復了每次登入時對已擁有收藏品的重複拾取通知。\n" ..
    "- 修復了刪除角色後 ESC 選單被停用的問題。\n" ..
    "- 修復了使用 ESC 關閉設定時主視窗錨點偏移的問題。\n" ..
    "- 修復了 \"Most Played\" 錯誤顯示角色的問題。\n" ..
    "- 修復了分身角色不顯示 Great Vault 資料的問題。\n" ..
    "- 修復了伺服器名稱顯示時缺少空格的問題。\n" ..
    "- 修復了首次懸停時工具提示不顯示收藏品資訊的問題。\n" ..
    "\n" ..
    "感謝您的持續支持！\n" ..
    "\n" ..
    "如需報告問題或分享回饋，請在 CurseForge - Warband Nexus 上留言。"

L["ANTI_ALIASING_DESC"] = "字體邊緣渲染樣式（影響可讀性）"
