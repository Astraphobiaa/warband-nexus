--[[
    Warband Nexus - Simplified Chinese Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "zhCN")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus 已加载。输入 /wn 或 /warbandnexus 打开选项。"
L["VERSION"] = GAME_VERSION_LABEL or "版本"

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

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "无效金额。"
L["WITHDRAW_BANK_NOT_OPEN"] = "银行必须打开才能取款！"
L["WITHDRAW_IN_COMBAT"] = "战斗中无法取款。"
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "战团银行中金币不足。"
L["WITHDRAWN_LABEL"] = "已取款："
L["WITHDRAW_API_UNAVAILABLE"] = "取款API不可用。"
L["SORT_IN_COMBAT"] = "战斗中无法排序。"

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global
L["SEARCH_CATEGORY_FORMAT"] = "搜索%s..."
L["BTN_SCAN"] = "扫描银行"
L["BTN_DEPOSIT"] = "存放队列"
L["BTN_SORT"] = "排序银行"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "清除队列"
L["BTN_DEPOSIT_ALL"] = "存放所有物品"
L["BTN_DEPOSIT_GOLD"] = "存放金币"
L["ENABLE"] = ENABLE or "启用" -- Blizzard Global
L["ENABLE_MODULE"] = "启用模块"

-- Main Tabs
L["TAB_CHARACTERS"] = CHARACTER or "角色" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "物品" -- Blizzard Global
L["TAB_STORAGE"] = "仓储"
L["TAB_PLANS"] = "计划"
L["TAB_REPUTATION"] = REPUTATION or "声望" -- Blizzard Global
L["TAB_REPUTATIONS"] = "声望"
L["TAB_CURRENCY"] = CURRENCY or "货币" -- Blizzard Global
L["TAB_CURRENCIES"] = "货币"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "统计" -- Blizzard Global

-- Item Categories (Blizzard Globals)
L["CATEGORY_ALL"] = ALL or "所有物品" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "装备"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "消耗品"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "药剂"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "交易商品"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "任务物品"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "杂项"

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
L["HEADER_CURRENT_CHARACTER"] = "当前角色"
L["HEADER_WARBAND_GOLD"] = "战团金币"
L["HEADER_TOTAL_GOLD"] = "总金币"
L["HEADER_REALM_GOLD"] = "服务器金币"
L["HEADER_REALM_TOTAL"] = "服务器合计"
L["CHARACTER_LAST_SEEN_FORMAT"] = "最后上线: %s"
L["CHARACTER_GOLD_FORMAT"] = "金币: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "此服务器所有角色的合计金币"

-- Items Tab
L["ITEMS_HEADER"] = "银行物品"
L["ITEMS_HEADER_DESC"] = "浏览和管理你的战团银行与个人银行"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " 物品..."
L["ITEMS_WARBAND_BANK"] = "战团银行"
L["ITEMS_PLAYER_BANK"] = BANK or "个人银行" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "公会银行" -- Blizzard Global
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "装备"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "消耗品"
L["GROUP_PROFESSION"] = "专业技能"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "药剂"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "交易商品"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "任务"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "杂项"
L["GROUP_CONTAINER"] = "容器"

-- Storage Tab
L["STORAGE_HEADER"] = "仓储浏览器"
L["STORAGE_HEADER_DESC"] = "按类型浏览所有物品"
L["STORAGE_WARBAND_BANK"] = "战团银行"
L["STORAGE_PERSONAL_BANKS"] = "个人银行"
L["STORAGE_TOTAL_SLOTS"] = "总栏位"
L["STORAGE_FREE_SLOTS"] = "空闲栏位"
L["STORAGE_BAG_HEADER"] = "战团背包"
L["STORAGE_PERSONAL_HEADER"] = "个人银行"

-- Plans Tab
L["PLANS_MY_PLANS"] = "我的计划"
L["PLANS_COLLECTIONS"] = "收藏计划"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "添加自定义计划"
L["PLANS_NO_RESULTS"] = "未找到结果。"
L["PLANS_ALL_COLLECTED"] = "所有物品已收集！"
L["PLANS_RECIPE_HELP"] = "右键点击背包中的配方将其添加到此。"
L["COLLECTION_PLANS"] = "收藏计划"
L["SEARCH_PLANS"] = "搜索计划..."
L["COMPLETED_PLANS"] = "已完成的计划"
L["SHOW_COMPLETED"] = "显示已完成"

-- Plans Categories (Blizzard Globals)
L["CATEGORY_MY_PLANS"] = "我的计划"
L["CATEGORY_DAILY_TASKS"] = "每日任务"
L["CATEGORY_MOUNTS"] = MOUNTS or "坐骑" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "宠物" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "玩具" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "幻化" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "幻象"
L["CATEGORY_TITLES"] = TITLES or "头衔"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "成就" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " 声望..."
L["REP_HEADER_WARBAND"] = "战团声望"
L["REP_HEADER_CHARACTER"] = "角色声望"
L["REP_STANDING_FORMAT"] = "等级: %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " 货币..."
L["CURRENCY_HEADER_WARBAND"] = "战团可转移"
L["CURRENCY_HEADER_CHARACTER"] = "角色绑定"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "团队副本" -- Blizzard Global
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "地下城" -- Blizzard Global
L["PVE_HEADER_DELVES"] = "地下堡"
L["PVE_HEADER_WORLD_BOSS"] = "世界首领"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "统计" -- Blizzard Global: STATISTICS
L["STATS_TOTAL_ITEMS"] = "总物品数"
L["STATS_TOTAL_SLOTS"] = "总栏位数"
L["STATS_FREE_SLOTS"] = "空闲栏位数"
L["STATS_USED_SLOTS"] = "已用栏位数"
L["STATS_TOTAL_VALUE"] = "总价值"
L["COLLECTED"] = "已收集"
L["TOTAL"] = "总计"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "角色" -- Blizzard Global: CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "位置" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "战团银行"
L["TOOLTIP_TAB"] = "标签"
L["TOOLTIP_SLOT"] = "栏位"
L["TOOLTIP_COUNT"] = "数量"
L["CHARACTER_INVENTORY"] = "背包"
L["CHARACTER_BANK"] = "银行"

-- Try Counter
L["TRY_COUNT"] = "尝试次数"
L["SET_TRY_COUNT"] = "设置尝试次数"
L["TRIES"] = "尝试"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "设置重置周期"
L["DAILY_RESET"] = "每日重置"
L["WEEKLY_RESET"] = "每周重置"
L["NONE_DISABLE"] = "无 (禁用)"
L["RESET_CYCLE_LABEL"] = "重置周期："
L["RESET_NONE"] = "无"
L["DOUBLECLICK_RESET"] = "双击重置位置"

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

-- Update Notification
L["WHATS_NEW"] = "更新内容"
L["GOT_IT"] = "知道了！"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "成就点数"
L["MOUNTS_COLLECTED"] = "已收集坐骑"
L["BATTLE_PETS"] = "战斗宠物"
L["ACCOUNT_WIDE"] = "账号通用"
L["STORAGE_OVERVIEW"] = "仓储概览"
L["WARBAND_SLOTS"] = "战团栏位"
L["PERSONAL_SLOTS"] = "个人栏位"
L["TOTAL_FREE"] = "总空闲"
L["TOTAL_ITEMS"] = "总物品"
L["WEEKLY_VAULT"] = "每周宝库"
L["CUSTOM"] = "自定义"
L["NO_PLANS_IN_CATEGORY"] = "此分类中没有计划。\n从计划标签页添加计划。"
L["SOURCE_LABEL"] = "来源："
L["ZONE_LABEL"] = "区域："
L["VENDOR_LABEL"] = "商人："
L["DROP_LABEL"] = "掉落："
L["REQUIREMENT_LABEL"] = "需求："
L["RIGHT_CLICK_REMOVE"] = "右键点击移除"
L["TRACKED"] = "已追踪"
L["TRACK"] = "追踪"
L["TRACK_BLIZZARD_OBJECTIVES"] = "在暴雪目标中追踪（最多10个）"
L["UNKNOWN"] = "未知"
L["NO_REQUIREMENTS"] = "无需求（即时完成）"
L["NO_PLANNED_ACTIVITY"] = "无计划活动"
L["CLICK_TO_ADD_GOALS"] = "点击上方的坐骑、宠物或玩具来添加目标！"
L["UNKNOWN_QUEST"] = "未知任务"
L["ALL_QUESTS_COMPLETE"] = "所有任务已完成！"
L["CURRENT_PROGRESS"] = "当前进度"
L["SELECT_CONTENT"] = "选择内容："
L["QUEST_TYPES"] = "任务类型："
L["WORK_IN_PROGRESS"] = "开发中"
L["RECIPE_BROWSER"] = "配方浏览器"
L["NO_RESULTS_FOUND"] = "未找到结果。"
L["TRY_ADJUSTING_SEARCH"] = "尝试调整搜索条件或筛选器。"
L["NO_COLLECTED_YET"] = "尚未收集任何%s"
L["START_COLLECTING"] = "开始收集即可在此查看！"
L["ALL_COLLECTED_CATEGORY"] = "所有%s已收集！"
L["COLLECTED_EVERYTHING"] = "您已收集此分类中的所有物品！"
L["PROGRESS_LABEL"] = "进度："
L["REQUIREMENTS_LABEL"] = "需求："
L["INFORMATION_LABEL"] = "信息："
L["DESCRIPTION_LABEL"] = "描述："
L["REWARD_LABEL"] = "奖励："
L["DETAILS_LABEL"] = "详情："
L["COST_LABEL"] = "花费："
L["LOCATION_LABEL"] = "位置："
L["TITLE_LABEL"] = "头衔："
L["COMPLETED_ALL_ACHIEVEMENTS"] = "您已完成此分类中的所有成就！"
L["DAILY_PLAN_EXISTS"] = "每日计划已存在"
L["WEEKLY_PLAN_EXISTS"] = "每周计划已存在"
L["GREAT_VAULT"] = "宏伟宝库"
L["LOADING_PVE"] = "正在加载PvE数据..."
L["PVE_APIS_LOADING"] = "请稍候，WoW API正在初始化..."
L["NO_VAULT_DATA"] = "无宝库数据"
L["NO_DATA"] = "无数据"
L["KEYSTONE"] = "钥石"
L["NO_KEY"] = "无钥匙"
L["AFFIXES"] = "词缀"
L["NO_AFFIXES"] = "无词缀"
L["ONLINE"] = "在线"
L["CONFIRM_DELETE"] = "确定要删除 |cff00ccff%s|r 吗？"
L["CANNOT_UNDO"] = "此操作无法撤销！"
L["DELETE"] = DELETE or "删除"
L["CANCEL"] = CANCEL or "取消"
L["PERSONAL_ITEMS"] = "个人物品"
L["ACCOUNT_WIDE_LABEL"] = "账号通用"
L["NO_RESULTS"] = "无结果"
L["NO_REP_MATCH"] = "没有与 '%s' 匹配的声望"
L["NO_REP_DATA"] = "无声望数据"
L["REP_SCAN_TIP"] = "声望会自动扫描。如果没有显示，请尝试 /reload。"
L["ACCOUNT_WIDE_REPS_FORMAT"] = "账号通用声望 (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "无账号通用声望"
L["NO_CHARACTER_REPS"] = "无角色声望"
L["CURRENT_LANGUAGE"] = "当前语言："
L["LANGUAGE_TOOLTIP"] = "插件自动使用WoW游戏客户端的语言。如需更改，请更新Battle.net设置。"
L["POPUP_DURATION"] = "弹窗持续时间"
L["POPUP_POSITION"] = "弹窗位置"
L["SET_POSITION"] = "设置位置"
L["DRAG_TO_POSITION"] = "拖拽以定位\n右键点击确认"
L["RESET_DEFAULT"] = "恢复默认"
L["TEST_POPUP"] = "测试弹窗"
L["CUSTOM_COLOR"] = "自定义颜色"
L["OPEN_COLOR_PICKER"] = "打开颜色选择器"
L["COLOR_PICKER_TOOLTIP"] = "打开WoW原生颜色选择器以选择自定义主题颜色"
L["PRESET_THEMES"] = "预设主题"
L["WARBAND_NEXUS_SETTINGS"] = "Warband Nexus 设置"
L["NO_OPTIONS"] = "无选项"
L["NONE_LABEL"] = NONE or "无"
L["MODULE_DISABLED"] = "模块已禁用"
L["LOADING"] = "加载中..."
L["PLEASE_WAIT"] = "请稍候..."
L["RESET_PREFIX"] = "重置："
L["TRANSFER_CURRENCY"] = "转移货币"
L["AMOUNT_LABEL"] = "数量："
L["TO_CHARACTER"] = "目标角色："
L["SELECT_CHARACTER"] = "选择角色..."

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "您的角色"
L["CHARACTERS_TRACKED_FORMAT"] = "%d 个角色已追踪"
L["NO_CHARACTER_DATA"] = "无角色数据"
L["NO_FAVORITES"] = "还没有收藏的角色。点击星标图标来收藏角色。"
L["ALL_FAVORITED"] = "所有角色都已收藏！"
L["UNTRACKED_CHARACTERS"] = "未追踪的角色"
L["ILVL_SHORT"] = "iLvl"
L["TIME_LESS_THAN_MINUTE"] = "< 1分钟前"
L["TIME_MINUTES_FORMAT"] = "%d分钟前"
L["TIME_HOURS_FORMAT"] = "%d小时前"
L["TIME_DAYS_FORMAT"] = "%d天前"
L["REMOVE_FROM_FAVORITES"] = "从收藏中移除"
L["ADD_TO_FAVORITES"] = "添加到收藏"
L["FAVORITES_TOOLTIP"] = "收藏的角色会显示在列表顶部"
L["CLICK_TO_TOGGLE"] = "点击切换"
L["UNKNOWN_PROFESSION"] = "未知专业"
L["SKILL_LABEL"] = "技能："
L["OVERALL_SKILL"] = "总体技能："
L["BONUS_SKILL"] = "奖励技能："
L["KNOWLEDGE_LABEL"] = "知识："
L["SPEC_LABEL"] = "专精"
L["POINTS_SHORT"] = "点"
L["RECIPES_KNOWN"] = "已知配方："
L["OPEN_PROFESSION_HINT"] = "打开专业窗口"
L["FOR_DETAILED_INFO"] = "查看详细信息"
L["CHARACTER_IS_TRACKED"] = "此角色正在被追踪。"
L["TRACKING_ACTIVE_DESC"] = "数据收集和更新已激活。"
L["CLICK_DISABLE_TRACKING"] = "点击禁用追踪。"
L["MUST_LOGIN_TO_CHANGE"] = "您必须登录此角色才能更改追踪设置。"
L["TRACKING_ENABLED"] = "追踪已启用"
L["CLICK_ENABLE_TRACKING"] = "点击为此角色启用追踪。"
L["TRACKING_WILL_BEGIN"] = "数据收集将立即开始。"
L["CHARACTER_NOT_TRACKED"] = "此角色未被追踪。"
L["MUST_LOGIN_TO_ENABLE"] = "您必须登录此角色才能启用追踪。"
L["ENABLE_TRACKING"] = "启用追踪"
L["DELETE_CHARACTER_TITLE"] = "删除角色？"
L["THIS_CHARACTER"] = "此角色"
L["DELETE_CHARACTER"] = "删除角色"
L["REMOVE_FROM_TRACKING_FORMAT"] = "从追踪中移除 %s"
L["CLICK_TO_DELETE"] = "点击删除"

-- =============================================
-- Items Tab
-- =============================================
L["ITEMS_SUBTITLE"] = "浏览您的战团银行和个人物品（银行 + 背包）"
L["ITEMS_DISABLED_TITLE"] = "战团银行物品"
L["ITEMS_LOADING"] = "正在加载库存数据"
L["GUILD_BANK_REQUIRED"] = "您必须加入公会才能访问公会银行。"
L["ITEMS_SEARCH"] = "搜索物品..."
L["NEVER"] = "从未"
L["ITEM_FALLBACK_FORMAT"] = "物品 %s"
L["TAB_FORMAT"] = "标签 %d"
L["BAG_FORMAT"] = "背包 %d"
L["BANK_BAG_FORMAT"] = "银行背包 %d"
L["ITEM_ID_LABEL"] = "物品ID："
L["QUALITY_TOOLTIP_LABEL"] = "品质："
L["STACK_LABEL"] = "堆叠："
L["RIGHT_CLICK_MOVE"] = "移动到背包"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "拆分堆叠"
L["LEFT_CLICK_PICKUP"] = "拾取"
L["ITEMS_BANK_NOT_OPEN"] = "银行未打开"
L["SHIFT_LEFT_CLICK_LINK"] = "在聊天中链接"
L["ITEM_DEFAULT_TOOLTIP"] = "物品"
L["ITEMS_STATS_ITEMS"] = "%s 个物品"
L["ITEMS_STATS_SLOTS"] = "%s/%s 个栏位"
L["ITEMS_STATS_LAST"] = "最后：%s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "角色仓储"
L["STORAGE_SEARCH"] = "搜索仓储..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "PvE进度"
L["PVE_SUBTITLE"] = "宏伟宝库、团队副本锁定和史诗钥石+ 在您的战团中"
L["PVE_NO_CHARACTER"] = "无角色数据"
L["LV_FORMAT"] = "等级 %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = "团队副本"
L["VAULT_DUNGEON"] = "地下城"
L["VAULT_WORLD"] = "世界"
L["VAULT_SLOT_FORMAT"] = "%s 栏位 %d"
L["VAULT_NO_PROGRESS"] = "暂无进度"
L["VAULT_UNLOCK_FORMAT"] = "完成 %s 个活动以解锁"
L["VAULT_NEXT_TIER_FORMAT"] = "下一级：完成 %s 后获得 %d iLvl"
L["VAULT_REMAINING_FORMAT"] = "剩余：%s 个活动"
L["VAULT_PROGRESS_FORMAT"] = "进度：%s / %s"
L["OVERALL_SCORE_LABEL"] = "总体评分："
L["BEST_KEY_FORMAT"] = "最佳钥匙：+%d"
L["SCORE_FORMAT"] = "评分：%s"
L["NOT_COMPLETED_SEASON"] = "本赛季未完成"
L["CURRENT_MAX_FORMAT"] = "当前：%s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "进度：%.1f%%"
L["NO_CAP_LIMIT"] = "无上限"
L["VAULT_BEST_KEY"] = "最佳钥匙："
L["VAULT_SCORE"] = "评分："

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "声望概览"
L["REP_SUBTITLE"] = "追踪您战团中的阵营和名望"
L["REP_DISABLED_TITLE"] = "声望追踪"
L["REP_LOADING_TITLE"] = "正在加载声望数据"
L["REP_SEARCH"] = "搜索声望..."
L["REP_PARAGON_TITLE"] = "巅峰声望"
L["REP_REWARD_AVAILABLE"] = "奖励可用！"
L["REP_CONTINUE_EARNING"] = "继续获得声望以获取奖励"
L["REP_CYCLES_FORMAT"] = "周期：%d"
L["REP_PROGRESS_HEADER"] = "进度：%d/%d"
L["REP_PARAGON_PROGRESS"] = "巅峰进度："
L["REP_PROGRESS_COLON"] = "进度："
L["REP_CYCLES_COLON"] = "周期："
L["REP_CHARACTER_PROGRESS"] = "角色进度："
L["REP_RENOWN_FORMAT"] = "名望 %d"
L["REP_PARAGON_FORMAT"] = "巅峰 (%s)"
L["REP_UNKNOWN_FACTION"] = "未知阵营"
L["REP_API_UNAVAILABLE_TITLE"] = "声望API不可用"
L["REP_API_UNAVAILABLE_DESC"] = "C_Reputation API在此服务器上不可用。此功能需要WoW 11.0+（地心之战）。"
L["REP_FOOTER_TITLE"] = "声望追踪"
L["REP_FOOTER_DESC"] = "声望会在登录和更改时自动扫描。使用游戏内的声望面板查看详细信息和奖励。"
L["REP_CLEARING_CACHE"] = "正在清除缓存并重新加载..."
L["REP_LOADING_DATA"] = "正在加载声望数据..."
L["REP_MAX"] = "最大"
L["REP_TIER_FORMAT"] = "等级 %d"

-- =============================================
-- Currency Tab
-- =============================================
L["CURRENCY_TITLE"] = "货币追踪器"
L["CURRENCY_SUBTITLE"] = "追踪您所有角色的货币"
L["CURRENCY_DISABLED_TITLE"] = "货币追踪"
L["CURRENCY_LOADING_TITLE"] = "正在加载货币数据"
L["CURRENCY_SEARCH"] = "搜索货币..."
L["CURRENCY_HIDE_EMPTY"] = "隐藏空"
L["CURRENCY_SHOW_EMPTY"] = "显示空"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "所有战团可转移"
L["CURRENCY_CHARACTER_SPECIFIC"] = "角色特定货币"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "货币转移限制"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "暴雪API不支持自动货币转移。请使用游戏内的货币窗口手动转移战团货币。"
L["CURRENCY_UNKNOWN"] = "未知货币"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "从您的「我的计划」列表中移除所有已完成的计划。这将删除所有已完成的自定义计划，并从计划中移除已收集的坐骑/宠物/玩具。此操作无法撤销！"
L["RECIPE_BROWSER_DESC"] = "在游戏中打开您的专业窗口以浏览配方。\n当窗口打开时，插件将扫描可用配方。"
L["SOURCE_ACHIEVEMENT_FORMAT"] = "来源：[成就 %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s 已有一个活跃的每周宝库计划。您可以在「我的计划」分类中找到它。"
L["DAILY_PLAN_EXISTS_DESC"] = "%s 已有一个活跃的每日任务计划。您可以在「每日任务」分类中找到它。"
L["TRANSMOG_WIP_DESC"] = "幻化收藏追踪功能正在开发中。\n\n此功能将在未来的更新中提供，具有改进的性能和更好的战团系统集成。"
L["WEEKLY_VAULT_CARD"] = "每周宝库卡片"
L["WEEKLY_VAULT_COMPLETE"] = "每周宝库卡片 - 完成"
L["UNKNOWN_SOURCE"] = "未知来源"
L["DAILY_TASKS_PREFIX"] = "每日任务 - "
L["NO_FOUND_FORMAT"] = "未找到 %s"
L["PLANS_COUNT_FORMAT"] = "%d 个计划"
L["PET_BATTLE_LABEL"] = "宠物对战："
L["QUEST_LABEL"] = "任务："

-- =============================================
-- Settings Tab
-- =============================================
L["TAB_FILTERING"] = "标签筛选"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "通知"
L["SCROLL_SPEED"] = "滚动速度"
L["ANCHOR_FORMAT"] = "锚点：%s  |  X：%d  |  Y：%d"
L["SHOW_WEEKLY_PLANNER"] = "显示每周计划器"
L["LOCK_MINIMAP_ICON"] = "锁定小地图图标"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "在鼠标提示中显示物品"
L["AUTO_SCAN_ITEMS"] = "自动扫描物品"
L["LIVE_SYNC"] = "实时同步"
L["BACKPACK_LABEL"] = "背包"
L["REAGENT_LABEL"] = "药剂"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["CURRENCY_TRANSFER_INFO"] = "货币窗口将自动打开。\n您需要手动右键点击货币进行转移。"
L["OK_BUTTON"] = OKAY or "确定"
L["SAVE"] = "保存"
L["TITLE_FIELD"] = "标题："
L["DESCRIPTION_FIELD"] = "描述："
L["CREATE_CUSTOM_PLAN"] = "创建自定义计划"
L["REPORT_BUGS"] = "在CurseForge上报告错误或分享建议以帮助改进插件。"
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus为管理您的所有角色、货币、声望、物品和整个战团的PvE进度提供集中界面。"
L["CHARACTERS_DESC"] = "查看所有角色的金币、等级、装等、阵营、种族、职业、专业、钥石和最后游戏时间。追踪或取消追踪角色，标记收藏。"
L["ITEMS_DESC"] = "在所有背包、银行和战团银行中搜索和浏览物品。打开银行时自动扫描。工具提示显示哪些角色拥有每件物品。"
L["STORAGE_DESC"] = "所有角色的汇总库存视图 — 背包、个人银行和战团银行合并在一个地方。"
L["PVE_DESC"] = "追踪宏伟宝库进度（含等级指示器）、史诗钥石+评分和钥石、词缀、副本历史和升级货币，覆盖所有角色。"
L["REPUTATIONS_DESC"] = "比较所有角色的声望进度。显示账号通用和角色特定阵营，悬停工具提示可查看每个角色的详细信息。"
L["CURRENCY_DESC"] = "按资料片查看所有货币。通过悬停工具提示比较角色间数量。一键隐藏空货币。"
L["PLANS_DESC"] = "追踪未收集的坐骑、宠物、玩具、成就和幻化。添加目标、查看掉落来源、监控尝试次数。通过 /wn plan 或小地图图标访问。"
L["STATISTICS_DESC"] = "查看成就点数、坐骑/宠物/玩具/幻象/头衔收藏进度、独特宠物计数和背包/银行使用统计。"

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "史诗"
L["DIFFICULTY_HEROIC"] = "英雄"
L["DIFFICULTY_NORMAL"] = "普通"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "等级 %d"
L["PVP_TYPE"] = "PvP"
L["PREPARING"] = "准备中"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "账号统计"
L["STATISTICS_SUBTITLE"] = "收藏进度、金币和仓储概览"
L["MOST_PLAYED"] = "游戏时间最长"
L["PLAYED_DAYS"] = "天"
L["PLAYED_HOURS"] = "小时"
L["PLAYED_MINUTES"] = "分钟"
L["PLAYED_DAY"] = "天"
L["PLAYED_HOUR"] = "小时"
L["PLAYED_MINUTE"] = "分钟"
L["MORE_CHARACTERS"] = "个更多角色"
L["MORE_CHARACTERS_PLURAL"] = "个更多角色"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "欢迎使用 Warband Nexus！"
L["ADDON_OVERVIEW_TITLE"] = "插件概览"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "追踪您的收藏目标"
L["ACTIVE_PLAN_FORMAT"] = "%d 个活跃计划"
L["ACTIVE_PLANS_FORMAT"] = "%d 个活跃计划"
L["RESET_LABEL"] = RESET or "重置"

-- Plans - Type Names
L["TYPE_MOUNT"] = MOUNT or "坐骑"
L["TYPE_PET"] = PET or "宠物"
L["TYPE_TOY"] = TOY or "玩具"
L["TYPE_RECIPE"] = "配方"
L["TYPE_ILLUSION"] = "幻象"
L["TYPE_TITLE"] = "头衔"
L["TYPE_CUSTOM"] = "自定义"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "幻化"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "掉落"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "任务"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "商人"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "专业"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "宠物对战"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "成就"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "世界事件"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "促销"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "集换式卡牌游戏"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "游戏内商店"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "制造"
L["SOURCE_TYPE_TRADING_POST"] = "交易站"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "未知"
L["SOURCE_TYPE_PVP"] = PVP or "PvP"
L["SOURCE_TYPE_TREASURE"] = "宝藏"
L["SOURCE_TYPE_PUZZLE"] = "谜题"
L["SOURCE_TYPE_RENOWN"] = "名望"

-- Plans - Transmog Source Labels (Blizzard TRANSMOG_SOURCE_* Globals)
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "首领掉落"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "任务"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "商人"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "世界掉落"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "成就"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "专业"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "出售"
L["PARSE_CRAFTED"] = "制造"
L["PARSE_ZONE"] = ZONE or "区域"
L["PARSE_COST"] = "费用"
L["PARSE_REPUTATION"] = REPUTATION or "声望"
L["PARSE_FACTION"] = FACTION or "阵营"
L["PARSE_ARENA"] = ARENA or "竞技场"
L["PARSE_DUNGEON"] = DUNGEONS or "地下城"
L["PARSE_RAID"] = RAID or "团队副本"
L["PARSE_HOLIDAY"] = "节日"
L["PARSE_RATED"] = "评级"
L["PARSE_BATTLEGROUND"] = "战场"
L["PARSE_DISCOVERY"] = "发现"
L["PARSE_CONTAINED_IN"] = "包含在"
L["PARSE_GARRISON"] = "要塞"
L["PARSE_GARRISON_BUILDING"] = "要塞建筑"
L["PARSE_STORE"] = "商城"
L["PARSE_ORDER_HALL"] = "职业大厅"
L["PARSE_COVENANT"] = "盟约"
L["PARSE_FRIENDSHIP"] = "友谊"
L["PARSE_PARAGON"] = "巅峰"
L["PARSE_MISSION"] = "任务"
L["PARSE_EXPANSION"] = "资料片"
L["PARSE_SCENARIO"] = "场景战役"
L["PARSE_CLASS_HALL"] = "职业大厅"
L["PARSE_CAMPAIGN"] = "战役"
L["PARSE_EVENT"] = "事件"
L["PARSE_SPECIAL"] = "特殊"
L["PARSE_BRAWLERS_GUILD"] = "搏击俱乐部"
L["PARSE_CHALLENGE_MODE"] = "挑战模式"
L["PARSE_MYTHIC_PLUS"] = "史诗钥石"
L["PARSE_TIMEWALKING"] = "时光漫游"
L["PARSE_ISLAND_EXPEDITION"] = "岛屿远征"
L["PARSE_WARFRONT"] = "战争前线"
L["PARSE_TORGHAST"] = "托加斯特"
L["PARSE_ZERETH_MORTIS"] = "扎雷殁地"
L["PARSE_HIDDEN"] = "隐藏"
L["PARSE_RARE"] = "稀有"
L["PARSE_WORLD_BOSS"] = "世界首领"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "掉落"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "来自成就"
L["FALLBACK_UNKNOWN_PET"] = "未知宠物"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "宠物收藏"
L["FALLBACK_TOY_COLLECTION"] = "玩具收藏"
L["FALLBACK_TRANSMOG_COLLECTION"] = "幻化收藏"
L["FALLBACK_PLAYER_TITLE"] = "玩家头衔"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "未知"
L["FALLBACK_ILLUSION_FORMAT"] = "幻象 %s"
L["SOURCE_ENCHANTING"] = "附魔"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "设置尝试次数：\n%s"
L["RESET_COMPLETED_CONFIRM"] = "您确定要移除所有已完成的计划吗？\n\n此操作无法撤销！"
L["YES_RESET"] = "是，重置"
L["REMOVED_PLANS_FORMAT"] = "已移除 %d 个已完成计划。"

-- Plans - Buttons
L["ADD_CUSTOM"] = "添加自定义"
L["ADD_VAULT"] = "添加宝库"
L["ADD_QUEST"] = "添加任务"
L["CREATE_PLAN"] = "创建计划"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "每日"
L["QUEST_CAT_WORLD"] = "世界"
L["QUEST_CAT_WEEKLY"] = "每周"
L["QUEST_CAT_ASSIGNMENT"] = "任务"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "未知分类"
L["SCANNING_FORMAT"] = "正在扫描 %s"
L["CUSTOM_PLAN_SOURCE"] = "自定义计划"
L["POINTS_FORMAT"] = "%d 点"
L["SOURCE_NOT_AVAILABLE"] = "来源信息不可用"
L["PROGRESS_ON_FORMAT"] = "您的进度为 %d/%d"
L["COMPLETED_REQ_FORMAT"] = "您已完成 %d 个总需求中的 %d 个"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "午夜"
L["CONTENT_TWW"] = "地心之战"
L["QUEST_TYPE_DAILY"] = "每日任务"
L["QUEST_TYPE_DAILY_DESC"] = "来自NPC的常规每日任务"
L["QUEST_TYPE_WORLD"] = "世界任务"
L["QUEST_TYPE_WORLD_DESC"] = "区域范围的世界任务"
L["QUEST_TYPE_WEEKLY"] = "每周任务"
L["QUEST_TYPE_WEEKLY_DESC"] = "每周循环任务"
L["QUEST_TYPE_ASSIGNMENTS"] = "任务"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "特殊任务和作业"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "史诗钥石+"
L["RAIDS_LABEL"] = "团队副本"

-- PlanCardFactory
L["FACTION_LABEL"] = "阵营："
L["FRIENDSHIP_LABEL"] = "友谊"
L["RENOWN_TYPE_LABEL"] = "名望"
L["ADD_BUTTON"] = "+ 添加"
L["ADDED_LABEL"] = "已添加"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s / %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "在仓储视图中显示物品上的堆叠数量"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "在角色标签页中显示每周计划器部分"
L["LOCK_MINIMAP_TOOLTIP"] = "锁定小地图图标位置（防止拖拽）"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "在鼠标提示中显示战团和角色物品数量（WN 搜索）。"
L["AUTO_SCAN_TOOLTIP"] = "打开银行或背包时自动扫描和缓存物品"
L["LIVE_SYNC_TOOLTIP"] = "在银行打开时实时更新物品缓存"
L["SHOW_ILVL_TOOLTIP"] = "在物品列表中的装备上显示物品等级徽章"
L["SCROLL_SPEED_TOOLTIP"] = "滚动速度倍数（1.0x = 每步28像素）"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "从自动扫描中忽略战团银行标签 %d"
L["IGNORE_SCAN_FORMAT"] = "从自动扫描中忽略 %s"
L["BANK_LABEL"] = BANK or "银行"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "启用通知"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "所有通知弹窗的主开关"
L["VAULT_REMINDER"] = "宝库提醒"
L["VAULT_REMINDER_TOOLTIP"] = "当您有未领取的每周宝库奖励时显示提醒"
L["LOOT_ALERTS"] = "战利品警报"
L["LOOT_ALERTS_TOOLTIP"] = "当新的坐骑、宠物或玩具进入您的背包时显示通知"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "隐藏暴雪成就警报"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "隐藏暴雪的默认成就弹窗，改用Warband Nexus通知"
L["REPUTATION_GAINS"] = "声望获得"
L["REPUTATION_GAINS_TOOLTIP"] = "当您获得阵营声望时显示聊天消息"
L["CURRENCY_GAINS"] = "货币获得"
L["CURRENCY_GAINS_TOOLTIP"] = "当您获得货币时显示聊天消息"
L["DURATION_LABEL"] = "持续时间"
L["DAYS_LABEL"] = "天"
L["WEEKS_LABEL"] = "周"
L["EXTEND_DURATION"] = "延长时间"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "拖拽绿色框架以设置弹窗位置。右键点击确认。"
L["POSITION_RESET_MSG"] = "弹窗位置已重置为默认（顶部居中）"
L["POSITION_SAVED_MSG"] = "弹窗位置已保存！"
L["TEST_NOTIFICATION_TITLE"] = "测试通知"
L["TEST_NOTIFICATION_MSG"] = "位置测试"
L["NOTIFICATION_DEFAULT_TITLE"] = "通知"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "主题和外观"
L["COLOR_PURPLE"] = "紫色"
L["COLOR_PURPLE_DESC"] = "经典紫色主题（默认）"
L["COLOR_BLUE"] = "蓝色"
L["COLOR_BLUE_DESC"] = "冷蓝色主题"
L["COLOR_GREEN"] = "绿色"
L["COLOR_GREEN_DESC"] = "自然绿色主题"
L["COLOR_RED"] = "红色"
L["COLOR_RED_DESC"] = "火红色主题"
L["COLOR_ORANGE"] = "橙色"
L["COLOR_ORANGE_DESC"] = "温暖橙色主题"
L["COLOR_CYAN"] = "青色"
L["COLOR_CYAN_DESC"] = "明亮青色主题"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "字体族"
L["FONT_FAMILY_TOOLTIP"] = "选择整个插件UI使用的字体"
L["FONT_SCALE"] = "字体缩放"
L["FONT_SCALE_TOOLTIP"] = "调整所有UI元素的字体大小"
L["RESOLUTION_NORMALIZATION"] = "分辨率标准化"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "根据屏幕分辨率和UI缩放调整字体大小，使文本在不同显示器上保持相同的物理大小"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "高级"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "物品等级 %s"
L["ITEM_NUMBER_FORMAT"] = "物品 #%s"
L["CHARACTER_CURRENCIES"] = "角色货币："
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "账号通用（战团）— 所有角色共享同一余额。"
L["YOU_MARKER"] = "（您）"
L["WN_SEARCH"] = "WN 搜索"
L["WARBAND_BANK_COLON"] = "战团银行："
L["AND_MORE_FORMAT"] = "... 还有 %d 个"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "您已收集一个坐骑"
L["COLLECTED_PET_MSG"] = "您已收集一个战斗宠物"
L["COLLECTED_TOY_MSG"] = "您已收集一个玩具"
L["COLLECTED_ILLUSION_MSG"] = "您已收集一个幻象"
L["ACHIEVEMENT_COMPLETED_MSG"] = "成就已完成！"
L["EARNED_TITLE_MSG"] = "您已获得一个头衔"
L["COMPLETED_PLAN_MSG"] = "您已完成一个计划"
L["DAILY_QUEST_CAT"] = "每日任务"
L["WORLD_QUEST_CAT"] = "世界任务"
L["WEEKLY_QUEST_CAT"] = "每周任务"
L["SPECIAL_ASSIGNMENT_CAT"] = "特殊任务"
L["DELVE_CAT"] = "地下堡"
L["DUNGEON_CAT"] = "地下城"
L["RAID_CAT"] = "团队副本"
L["WORLD_CAT"] = "世界"
L["ACTIVITY_CAT"] = "活动"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d 进度"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d 进度已完成"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "每周宝库计划 - %s"
L["ALL_SLOTS_COMPLETE"] = "所有栏位已完成！"
L["QUEST_COMPLETED_SUFFIX"] = "已完成"
L["WEEKLY_VAULT_READY"] = "每周宝库已就绪！"
L["UNCLAIMED_REWARDS"] = "您有未领取的奖励"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "总金币："
L["CHARACTERS_COLON"] = "角色："
L["LEFT_CLICK_TOGGLE"] = "左键点击：切换窗口"
L["RIGHT_CLICK_PLANS"] = "右键点击：打开计划"
L["MINIMAP_SHOWN_MSG"] = "小地图按钮已显示"
L["MINIMAP_HIDDEN_MSG"] = "小地图按钮已隐藏（使用 /wn minimap 显示）"
L["TOGGLE_WINDOW"] = "切换窗口"
L["SCAN_BANK_MENU"] = "扫描银行"
L["TRACKING_DISABLED_SCAN_MSG"] = "角色追踪已禁用。在设置中启用追踪以扫描银行。"
L["SCAN_COMPLETE_MSG"] = "扫描完成！"
L["BANK_NOT_OPEN_MSG"] = "银行未打开"
L["OPTIONS_MENU"] = "选项"
L["HIDE_MINIMAP_BUTTON"] = "隐藏小地图按钮"
L["MENU_UNAVAILABLE_MSG"] = "右键菜单不可用"
L["USE_COMMANDS_MSG"] = "使用 /wn show, /wn scan, /wn config"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "最大"
L["OPEN_AND_GUIDE"] = "打开并引导"
L["FROM_LABEL"] = "来自："
L["AVAILABLE_LABEL"] = "可用："
L["ONLINE_LABEL"] = "（在线）"
L["DATA_SOURCE_TITLE"] = "数据源信息"
L["DATA_SOURCE_USING"] = "此标签页使用："
L["DATA_SOURCE_MODERN"] = "现代缓存服务（事件驱动）"
L["DATA_SOURCE_LEGACY"] = "旧版直接数据库访问"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "需要迁移到缓存服务"
L["GLOBAL_DB_VERSION"] = "全局数据库版本："

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "角色"
L["INFO_TAB_ITEMS"] = "物品"
L["INFO_TAB_STORAGE"] = "仓储"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "声望"
L["INFO_TAB_CURRENCY"] = "货币"
L["INFO_TAB_PLANS"] = "计划"
L["INFO_TAB_STATISTICS"] = "统计"
L["SPECIAL_THANKS"] = "特别感谢"
L["SUPPORTERS_TITLE"] = "支持者"
L["THANK_YOU_MSG"] = "感谢您使用 Warband Nexus！"

-- =============================================
-- Changelog (What's New) - v2.0.0
-- =============================================
L["CHANGELOG_V200"] = "新功能：\n" ..
    "- 角色追踪：选择要追踪或取消追踪的角色。\n" ..
    "- 智能货币和声望追踪：实时聊天通知，包含进度。\n" ..
    "- 坐骑尝试计数器：追踪您的掉落尝试次数（开发中）。\n" ..
    "- 背包 + 银行 + 战团银行追踪：在所有存储中追踪物品。\n" ..
    "- 工具提示系统：全新的自定义工具提示框架。\n" ..
    "- 工具提示物品追踪器：悬停查看哪些角色拥有该物品。\n" ..
    "- 计划标签页：追踪您的下一个目标 — 坐骑、宠物、玩具、成就、幻化。\n" ..
    "- 计划窗口：通过 /wn plan 或右键点击小地图图标快速访问。\n" ..
    "- 智能账户数据追踪：自动战团范围数据同步。\n" ..
    "- 本地化：支持11种语言。\n" ..
    "- 声望和货币比较：悬停工具提示显示每个角色的详细信息。\n" ..
    "- 通知系统：战利品、成就和宝库提醒。\n" ..
    "- 自定义字体系统：选择您喜欢的字体和缩放。\n" ..
    "\n" ..
    "改进：\n" ..
    "- 角色数据：添加了阵营、种族、装等和钥石信息。\n" ..
    "- 银行界面已禁用（由改进的存储替代）。\n" ..
    "- 个人物品：追踪您的银行 + 背包。\n" ..
    "- 存储：在所有角色中追踪银行 + 背包 + 战团银行。\n" ..
    "- PvE：宝库等级指示器、地下城评分/钥石追踪、词缀、升级货币。\n" ..
    "- 声望标签页：简化视图（移除旧筛选系统）。\n" ..
    "- 货币标签页：简化视图（移除旧筛选系统）。\n" ..
    "- 统计：添加了独特宠物计数器。\n" ..
    "- 设置：修订并重新组织。\n" ..
    "\n" ..
    "感谢您的耐心和关注。\n" ..
    "\n" ..
    "如需报告问题或分享反馈，请在CurseForge - Warband Nexus上留言。"

-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "确认操作"
L["CONFIRM"] = "确认"
L["ENABLE_TRACKING_FORMAT"] = "为 |cffffcc00%s|r 启用追踪？"
L["DISABLE_TRACKING_FORMAT"] = "为 |cffffcc00%s|r 禁用追踪？"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "账号通用声望 (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "角色声望 (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "奖励等待中"
L["REP_PARAGON_LABEL"] = "巅峰"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "准备中..."
L["REP_LOADING_INITIALIZING"] = "初始化中..."
L["REP_LOADING_FETCHING"] = "正在获取声望数据..."
L["REP_LOADING_PROCESSING"] = "正在处理 %d 个阵营..."
L["REP_LOADING_PROCESSING_COUNT"] = "正在处理... (%d/%d)"
L["REP_LOADING_SAVING"] = "正在保存到数据库..."
L["REP_LOADING_COMPLETE"] = "完成！"

-- =============================================
-- Gold Transfer
-- =============================================
L["GOLD_TRANSFER"] = "金币转移"
L["GOLD_LABEL"] = "金币"
L["SILVER_LABEL"] = "银币"
L["COPPER_LABEL"] = "铜币"
L["DEPOSIT"] = "存入"
L["WITHDRAW"] = "取出"
L["DEPOSIT_TO_WARBAND"] = "存入战团银行"
L["WITHDRAW_FROM_WARBAND"] = "从战团银行取出"
L["YOUR_GOLD_FORMAT"] = "您的金币：%s"
L["WARBAND_BANK_FORMAT"] = "战团银行：%s"
L["NOT_ENOUGH_GOLD"] = "可用金币不足。"
L["ENTER_AMOUNT"] = "请输入金额。"
L["ONLY_WARBAND_GOLD"] = "只有战团银行支持金币转移。"

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "战斗中无法打开窗口。请在战斗结束后重试。"
L["BANK_IS_ACTIVE"] = "银行已激活"
L["ITEMS_CACHED_FORMAT"] = "%d 个物品已缓存"
L["UP_TO_DATE"] = "最新"
L["NEVER_SCANNED"] = "从未扫描"

-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "角色"
L["TABLE_HEADER_LEVEL"] = "等级"
L["TABLE_HEADER_GOLD"] = "金币"
L["TABLE_HEADER_LAST_SEEN"] = "最后上线"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "没有与 '%s' 匹配的物品"
L["NO_ITEMS_MATCH_GENERIC"] = "没有与您的搜索匹配的物品"
L["ITEMS_SCAN_HINT"] = "物品会自动扫描。如果没有显示，请尝试 /reload。"
L["ITEMS_WARBAND_BANK_HINT"] = "打开战团银行以扫描物品（首次访问时自动扫描）"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "下一步："
L["CURRENCY_TRANSFER_STEP_1"] = "在货币窗口中找到 |cffffffff%s|r"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800右键点击|r 它"
L["CURRENCY_TRANSFER_STEP_3"] = "选择 |cffffffff'转移到战团'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "选择 |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "输入金额：|cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "货币窗口现已打开！"
L["CURRENCY_TRANSFER_SECURITY"] = "（暴雪安全机制阻止自动转移）"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "区域："
L["ADDED"] = "已添加"
L["WEEKLY_VAULT_TRACKER"] = "每周宝库追踪器"
L["DAILY_QUEST_TRACKER"] = "每日任务追踪器"
L["CUSTOM_PLAN_STATUS"] = "自定义计划 '%s' %s"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = "地下城"
L["VAULT_SLOT_RAIDS"] = "团队副本"
L["VAULT_SLOT_WORLD"] = "世界"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "词缀"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_STANDING_LABEL"] = "当前"
L["CHAT_GAINED_PREFIX"] = "+"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "计划已完成："
L["WEEKLY_VAULT_PLAN_NAME"] = "每周宝库 - %s"
L["VAULT_PLANS_RESET"] = "每周宏伟宝库计划已重置！（%d 个计划%s）"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "未找到角色"
L["EMPTY_CHARACTERS_DESC"] = "使用角色登录以开始追踪。\n角色数据会在每次登录时自动收集。"
L["EMPTY_ITEMS_TITLE"] = "无缓存物品"
L["EMPTY_ITEMS_DESC"] = "打开战团银行或个人银行来扫描物品。\n物品会在首次访问时自动缓存。"
L["EMPTY_STORAGE_TITLE"] = "无存储数据"
L["EMPTY_STORAGE_DESC"] = "打开银行或背包时会扫描物品。\n访问银行以开始追踪您的存储。"
L["EMPTY_PLANS_TITLE"] = "暂无计划"
L["EMPTY_PLANS_DESC"] = "浏览上方的坐骑、宠物、玩具或成就\n来添加收藏目标并追踪进度。"
L["EMPTY_REPUTATION_TITLE"] = "无声望数据"
L["EMPTY_REPUTATION_DESC"] = "声望会在登录时自动扫描。\n使用角色登录以开始追踪阵营声望。"
L["EMPTY_CURRENCY_TITLE"] = "无货币数据"
L["EMPTY_CURRENCY_DESC"] = "货币会在所有角色间自动追踪。\n使用角色登录以开始追踪货币。"
L["EMPTY_PVE_TITLE"] = "无PvE数据"
L["EMPTY_PVE_DESC"] = "PvE进度会在角色登录时追踪。\n宏伟宝库、史诗钥石+和团本锁定将显示在此。"
L["EMPTY_STATISTICS_TITLE"] = "无可用统计"
L["EMPTY_STATISTICS_DESC"] = "统计数据来自您追踪的角色。\n使用角色登录以开始收集数据。"
L["NO_ADDITIONAL_INFO"] = "无额外信息"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "你想追踪这个角色吗？"
L["CLEANUP_NO_INACTIVE"] = "未找到不活跃的角色（90天以上）"
L["CLEANUP_REMOVED_FORMAT"] = "已移除 %d 个不活跃角色"
L["TRACKING_ENABLED_MSG"] = "角色追踪已启用！"
L["TRACKING_DISABLED_MSG"] = "角色追踪已禁用！"
L["TRACKING_ENABLED"] = "追踪已启用"
L["TRACKING_DISABLED"] = "追踪已禁用（只读模式）"
L["STATUS_LABEL"] = "状态："
L["ERROR_LABEL"] = "错误："
L["ERROR_NAME_REALM_REQUIRED"] = "需要角色名称和服务器"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s 已有活跃的每周计划"

-- Profiles (AceDB)
L["PROFILES"] = "配置文件"
L["PROFILES_DESC"] = "管理插件配置文件"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "未找到条件"
L["NO_REQUIREMENTS_INSTANT"] = "无需求（即时完成）"

-- Statistics Tab (missing)
L["TOTAL_PETS"] = "宠物总数"

-- Items Tab (missing)
L["ITEM_LOADING_NAME"] = "加载中..."

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
