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

-- Plans Categories (Blizzard Globals)
L["CATEGORY_MY_PLANS"] = "我的計畫"
L["CATEGORY_DAILY_TASKS"] = "每日任務"
L["CATEGORY_MOUNTS"] = MOUNTS or "坐騎" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "寵物" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "玩具" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "塑形" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "幻象"
L["CATEGORY_TITLES"] = "頭銜"
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
L["CHARACTERS_DESC"] = "查看您的所有角色，包括金幣、等級、專業和最後遊戲時間資訊。"
L["ITEMS_DESC"] = "在所有背包和銀行中搜尋物品。打開銀行時自動更新。"
L["STORAGE_DESC"] = "瀏覽從所有角色和銀行彙總的整個庫存。"
L["PVE_DESC"] = "追蹤所有角色的宏偉寶庫、傳奇鑰石+和團隊副本鎖定。"
L["REPUTATIONS_DESC"] = "使用智慧篩選（帳號通用 vs 角色特定）監控聲望進度。"
L["CURRENCY_DESC"] = "按資料片組織查看所有貨幣，並提供篩選選項。"
L["PLANS_DESC"] = "瀏覽和追蹤您尚未收集的坐騎、寵物、玩具、成就和塑形。"
L["STATISTICS_DESC"] = "查看成就點數、收藏進度和背包/銀行使用統計。"

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "傳奇"
L["DIFFICULTY_HEROIC"] = "英雄"
L["DIFFICULTY_NORMAL"] = "普通"
L["DIFFICULTY_LFR"] = "隨機團隊"
L["TIER_FORMAT"] = "等級 %d"
L["PVP_TYPE"] = "PvP"
L["PREPARING"] = "準備中"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "帳號統計"
L["STATISTICS_SUBTITLE"] = "收藏進度、金幣和倉儲概覽"

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
L["TYPE_MOUNT"] = "坐騎"
L["TYPE_PET"] = "寵物"
L["TYPE_TOY"] = "玩具"
L["TYPE_RECIPE"] = "配方"
L["TYPE_ILLUSION"] = "幻象"
L["TYPE_TITLE"] = "頭銜"
L["TYPE_CUSTOM"] = "自訂"
L["TYPE_TRANSMOG"] = "塑形"

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
L["RESOLUTION_NORMALIZATION"] = "解析度標準化"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "根據螢幕解析度和UI縮放調整字體大小，使文字在不同顯示器上保持相同的實體大小"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "進階"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "物品等級 %s"
L["ITEM_NUMBER_FORMAT"] = "物品 #%s"
L["CHARACTER_CURRENCIES"] = "角色貨幣："
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
L["USE_COMMANDS_MSG"] = "使用 /wn show, /wn scan, /wn config"

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
L["CHANGELOG_V200"] = "重大更新：\n" ..
    "- 戰利品和成就通知：當您獲得坐騎、寵物、玩具、幻象、頭銜和成就時收到通知\n" ..
    "- 每週寶庫提醒：當您有未領取的寶庫獎勵時顯示提示\n" ..
    "- 計畫標籤頁：組織您的目標並追蹤您想要收集的內容\n" ..
    "- 字體系統：整個外掛程式中可自訂的字體\n" ..
    "- 主題顏色：可自訂的強調色以個人化UI\n" ..
    "- UI改進：更清晰的佈局、更好的組織、搜尋和視覺優化\n" ..
    "- 聲望和貨幣獲得的聊天訊息：即時 [WN-聲望] 和 [WN-貨幣] 訊息，包含進度\n" ..
    "- 工具提示系統：整個介面中改進的工具提示\n" ..
    "- 角色追蹤：選擇要追蹤的角色\n" ..
    "- 收藏角色：在列表中為您的收藏角色新增星標\n" ..
    "\n" ..
    "次要更新：\n" ..
    "- 銀行模組已停用\n" ..
    "- 舊資料庫系統已移除（改進和錯誤修復）\n" ..
    "- 使用WN通知時隱藏暴雪成就彈窗的選項\n" ..
    "- 可設定的戰利品和成就通知位置\n" ..
    "\n" ..
    "感謝您使用 Warband Nexus！\n" ..
    "\n" ..
    "如果您想回報錯誤或留下意見回饋，可以在CurseForge - Warband Nexus上留言。"

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
-- Gold Transfer
-- =============================================
L["GOLD_TRANSFER"] = "金幣轉移"
L["GOLD_LABEL"] = "金幣"
L["SILVER_LABEL"] = "銀幣"
L["COPPER_LABEL"] = "銅幣"
L["DEPOSIT"] = "存入"
L["WITHDRAW"] = "取出"
L["DEPOSIT_TO_WARBAND"] = "存入戰團銀行"
L["WITHDRAW_FROM_WARBAND"] = "從戰團銀行取出"
L["YOUR_GOLD_FORMAT"] = "您的金幣：%s"
L["WARBAND_BANK_FORMAT"] = "戰團銀行：%s"
L["NOT_ENOUGH_GOLD"] = "可用金幣不足。"
L["ENTER_AMOUNT"] = "請輸入金額。"
L["ONLY_WARBAND_GOLD"] = "只有戰團銀行支援金幣轉移。"

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "戰鬥中無法打開視窗。請在戰鬥結束後重試。"
L["BANK_IS_ACTIVE"] = "銀行已啟動"
L["ITEMS_CACHED_FORMAT"] = "%d 個物品已快取"
L["UP_TO_DATE"] = "最新"
L["NEVER_SCANNED"] = "從未掃描"

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
L["CHAT_REP_GAIN"] = "|cffff8800[WN-聲望]|r |cff00ff00[%s]|r: 獲得 |cff00ff00+%s|r |cff00ff00(%s / %s)|r"
L["CHAT_REP_GAIN_NOMAX"] = "|cffff8800[WN-聲望]|r |cff00ff00[%s]|r: 獲得 |cff00ff00+%s|r"
L["CHAT_REP_STANDING"] = "|cffff8800[WN-聲望]|r |cff00ff00[%s]|r: 現在是 |cff%s%s|r"
L["CHAT_CUR_GAIN"] = "|cffcc66ff[WN-貨幣]|r %s: 獲得 |cff00ff00+%s|r |cff00ff00(%s / %s)|r"
L["CHAT_CUR_GAIN_NOMAX"] = "|cffcc66ff[WN-貨幣]|r %s: 獲得 |cff00ff00+%s|r |cff00ff00(%s)|r"

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
