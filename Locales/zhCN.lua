--[[
    Warband Nexus - Simplified Chinese Localization (简体中文)
    
    This is the zhCN locale for Chinese (Simplified) game clients.
    
    NOTE: Many strings use Blizzard's built-in GlobalStrings for automatic localization!
    Custom strings (Warband Nexus specific) are translated here.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "zhCN")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus 已加载。输入 /wn 或 /warbandnexus 打开选项。"
L["VERSION"] = GAME_VERSION_LABEL or "版本"

-- Slash Commands
L["SLASH_HELP"] = "可用命令："
L["SLASH_OPTIONS"] = "打开选项面板"
L["SLASH_SCAN"] = "扫描战团银行"
L["SLASH_SHOW"] = "显示/隐藏主窗口"
L["SLASH_DEPOSIT"] = "打开存入队列"
L["SLASH_SEARCH"] = "搜索物品"
L["KEYBINDING"] = "快捷键"
L["KEYBINDING_UNBOUND"] = "未设置"
L["KEYBINDING_PRESS_KEY"] = "请按一个键..."
L["KEYBINDING_TOOLTIP"] = "点击设置快捷键以切换 Warband Nexus。\n按 ESC 取消。"
L["KEYBINDING_CLEAR"] = "清除快捷键"
L["KEYBINDING_REPLACES"] = "该按键原本绑定为 %s — 现在用于 Warband Nexus。"
L["KEYBINDING_SAVED"] = "快捷键已保存。"
L["KEYBINDING_COMBAT"] = "战斗中无法更改快捷键。"
L["KEYBINDING_SETFAILED"] = "无法分配该按键。请尝试 Esc > 选项 > 按键设置。"
L["KEYBINDING_VERIFY_FAIL"] = "该按键仍绑定到其他操作（%s）。请打开 Esc > 选项 > 按键设置，清除冲突后再在此分配。"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "常规设置"
L["GENERAL_SETTINGS_DESC"] = "配置插件常规行为"
L["ENABLE_ADDON"] = "启用插件"
L["ENABLE_ADDON_DESC"] = "启用或禁用 Warband Nexus 功能"
L["MINIMAP_ICON"] = "显示小地图图标"
L["MINIMAP_ICON_DESC"] = "显示或隐藏小地图按钮"
L["DEBUG_MODE"] = "调试日志"
L["DEBUG_MODE_DESC"] = "在聊天框输出详细调试信息以便排查问题"
L["DEBUG_TRYCOUNTER_LOOT"] = "尝试计数战利品调试"
L["DEBUG_TRYCOUNTER_LOOT_DESC"] = "仅记录战利品流程（LOOT_OPENED、来源解析、区域回退）。声望/货币缓存日志已抑制。"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "扫描设置"
L["SCANNING_SETTINGS_DESC"] = "配置银行扫描行为"
L["AUTO_SCAN"] = "打开银行时自动扫描"
L["AUTO_SCAN_DESC"] = "打开战团银行时自动扫描"
L["SCAN_DELAY"] = "扫描节流延迟"
L["SCAN_DELAY_DESC"] = "扫描操作之间的延迟（秒）"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "存入设置"
L["DEPOSIT_SETTINGS_DESC"] = "配置物品存入行为"
L["GOLD_RESERVE"] = "金币储备"
L["GOLD_RESERVE_DESC"] = "个人背包中保留的最低金币数量（金币）"
L["AUTO_DEPOSIT_REAGENTS"] = "自动存入材料"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "打开银行时将材料加入存入队列"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "显示"
L["DISPLAY_SETTINGS_DESC"] = "自定义物品和信息的显示方式。"
L["SHOW_ITEM_LEVEL"] = "显示物品等级"
L["SHOW_ITEM_LEVEL_DESC"] = "在装备上显示物品等级"
L["SHOW_ITEM_COUNT"] = "显示物品数量"
L["SHOW_ITEM_COUNT_DESC"] = "在物品上显示堆叠数量"
L["HIGHLIGHT_QUALITY"] = "按品质高亮"
L["HIGHLIGHT_QUALITY_DESC"] = "根据物品品质添加彩色边框"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "标签页设置"
L["TAB_SETTINGS_DESC"] = "配置战团银行标签页行为"
L["IGNORED_TABS"] = "忽略的标签页"
L["IGNORED_TABS_DESC"] = "选择要从扫描和操作中排除的标签页"
L["TAB_1"] = "战团标签页 1"
L["TAB_2"] = "战团标签页 2"
L["TAB_3"] = "战团标签页 3"
L["TAB_4"] = "战团标签页 4"
L["TAB_5"] = "战团标签页 5"

-- Scanner Module
L["SCAN_STARTED"] = "正在扫描战团银行..."
L["SCAN_COMPLETE"] = "扫描完成。在 %d 个格子中发现 %d 件物品。"
L["SCAN_FAILED"] = "扫描失败：战团银行未打开。"
L["SCAN_TAB"] = "正在扫描标签页 %d..."
L["CACHE_CLEARED"] = "物品缓存已清除。"
L["CACHE_UPDATED"] = "物品缓存已更新。"

-- Banker Module
L["BANK_NOT_OPEN"] = "战团银行未打开。"
L["DEPOSIT_STARTED"] = "正在开始存入操作..."
L["DEPOSIT_COMPLETE"] = "存入完成。已转移 %d 件物品。"
L["DEPOSIT_CANCELLED"] = "存入已取消。"
L["DEPOSIT_QUEUE_EMPTY"] = "存入队列为空。"
L["DEPOSIT_QUEUE_CLEARED"] = "存入队列已清空。"
L["ITEM_QUEUED"] = "%s 已加入存入队列。"
L["ITEM_REMOVED"] = "%s 已从队列中移除。"
L["GOLD_DEPOSITED"] = "已将 %s 金币存入战团银行。"
L["INSUFFICIENT_GOLD"] = "金币不足，无法存入。"

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "无效数量。"
L["WITHDRAW_BANK_NOT_OPEN"] = "必须打开银行才能取款！"
L["WITHDRAW_IN_COMBAT"] = "战斗中无法取款。"
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "战团银行金币不足。"
L["WITHDRAWN_LABEL"] = "已取出："
L["WITHDRAW_API_UNAVAILABLE"] = "取款 API 不可用。"
L["SORT_IN_COMBAT"] = "战斗中无法整理。"

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_CATEGORY_FORMAT"] = "搜索 %s..."
L["BTN_SCAN"] = "扫描银行"
L["BTN_DEPOSIT"] = "存入队列"
L["BTN_SORT"] = "整理银行"
L["BTN_CLEAR_QUEUE"] = "清空队列"
L["BTN_DEPOSIT_ALL"] = "全部存入"
L["BTN_DEPOSIT_GOLD"] = "存入金币"
L["ENABLE_MODULE"] = "启用模块"

-- Main Tabs
L["TAB_STORAGE"] = "存储"
L["TAB_PLANS"] = "待办"
L["TAB_REPUTATIONS"] = "声望"
L["TAB_CURRENCIES"] = "货币"
L["TAB_PVE"] = "PvE"

-- Characters Tab
L["HEADER_CURRENT_CHARACTER"] = "当前角色"
L["HEADER_WARBAND_GOLD"] = "战团金币"
L["HEADER_TOTAL_GOLD"] = "总金币"
L["HEADER_REALM_GOLD"] = "服务器金币"
L["HEADER_REALM_TOTAL"] = "服务器总计"
L["CHARACTER_LAST_SEEN_FORMAT"] = "上次登录：%s"
L["CHARACTER_GOLD_FORMAT"] = "金币：%s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "本服务器所有角色的金币合计"
L["MAX_LEVEL"] = "满级"
L["YES"] = "是"
L["NO"] = "否"

-- Items Tab
L["ITEMS_HEADER"] = "银行物品"
L["ITEMS_HEADER_DESC"] = "浏览和管理你的战团银行和个人银行"
L["ITEMS_WARBAND_BANK"] = "战团银行"
L["GROUP_CONTAINER"] = "容器"

-- Storage Tab
L["STORAGE_HEADER"] = "存储浏览器"
L["STORAGE_HEADER_DESC"] = "按类型浏览所有物品"
L["STORAGE_WARBAND_BANK"] = "战团银行"
L["STORAGE_PERSONAL_BANKS"] = "个人银行"
L["STORAGE_TOTAL_SLOTS"] = "总格子数"
L["STORAGE_FREE_SLOTS"] = "空闲格子"
L["STORAGE_BAG_HEADER"] = "战团背包"
L["STORAGE_PERSONAL_HEADER"] = "个人银行"

-- Plans Tab
L["PLANS_MY_PLANS"] = "待办列表"
L["PLANS_COLLECTIONS"] = "待办清单"
L["PLANS_ADD_CUSTOM"] = "添加自定义计划"
L["PLANS_NO_RESULTS"] = "未找到结果。"
L["PLANS_ALL_COLLECTED"] = "所有物品已收集！"
L["PLANS_RECIPE_HELP"] = "右键点击背包中的配方可添加到此。"
L["COLLECTION_PLANS"] = "待办清单"
L["SEARCH_PLANS"] = "搜索计划..."
L["COMPLETED_PLANS"] = "已完成计划"
L["SHOW_COMPLETED"] = "显示已完成"
L["SHOW_COMPLETED_HELP"] = "待办与周进度：未勾选=仍进行中的计划；勾选=仅已完成的计划。浏览标签：未勾选=未收藏（开启“显示已计划”时仅限列表内）；勾选=列表上已收藏的条目（“显示已计划”仍会限制列表）。"
L["SHOW_PLANNED"] = "显示计划中"
L["SHOW_PLANNED_HELP"] = "仅浏览标签（在待办与周进度中隐藏）：勾选=仅显示你加入待办的目标。“显示已完成”关=仍缺的；开=已完成的；两项都开=该分类全部已计划；两项都关=完整未收藏浏览。"
L["NO_PLANNED_ITEMS"] = "暂无计划的 %s"
L["PLANS_ACHIEVEMENTS_EMPTY_TITLE"] = "没有可显示的成就"
L["PLANS_ACHIEVEMENTS_EMPTY_HINT"] = "从此列表将成就加入待办，或更改“显示已计划/显示已完成”。列表随扫描填充；若为空可尝试 /reload。"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_TITLE"] = "没有可显示的内容"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_DESC"] = "当前筛选下没有匹配的已计划条目。请加入待办或调整“显示已计划/显示已完成”。"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_TITLE"] = "没有已完成的待办条目"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_DESC"] = "该分类中待办尚无已收藏或已完成项。关闭“显示已完成”可查看进行中的条目。"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_TITLE"] = "没有进行中的待办条目"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_DESC"] = "该分类待办中已没有未收藏项。开启“显示已完成”查看已完成项，或从本页添加目标。"

-- Plans Categories
L["CATEGORY_MY_PLANS"] = "待办列表"
L["CATEGORY_DAILY_TASKS"] = "每周进度"
L["CATEGORY_ILLUSIONS"] = "幻象"

-- Reputation Tab
L["REP_HEADER_WARBAND"] = "战团声望"
L["REP_HEADER_CHARACTER"] = "角色声望"
L["REP_STANDING_FORMAT"] = "声望等级：%s"

-- Currency Tab
L["CURRENCY_HEADER_WARBAND"] = "战团可转移"
L["CURRENCY_HEADER_CHARACTER"] = "角色绑定"

-- PvE Tab
L["PVE_HEADER_DELVES"] = "探索"
L["PVE_HEADER_WORLD_BOSS"] = "世界首领"

-- Statistics
L["STATS_TOTAL_ITEMS"] = "物品总数"
L["STATS_TOTAL_SLOTS"] = "总格子数"
L["STATS_FREE_SLOTS"] = "空闲格子"
L["STATS_USED_SLOTS"] = "已用格子"
L["STATS_TOTAL_VALUE"] = "总价值"
L["COLLECTED"] = "已收集"
L["TOTAL"] = "总计"

-- Tooltips
L["TOOLTIP_WARBAND_BANK"] = "战团银行"
L["TOOLTIP_TAB"] = "标签页"
L["TOOLTIP_SLOT"] = "格子"
L["TOOLTIP_COUNT"] = "数量"
L["CHARACTER_INVENTORY"] = "背包"
L["CHARACTER_BANK"] = "个人银行"

-- Try Counter
L["TRY_COUNT"] = "尝试次数"
L["SET_TRY_COUNT"] = "设置尝试次数"
L["TRY_COUNT_RIGHT_CLICK_HINT"] = "右键点击以编辑尝试次数。"
L["TRY_COUNT_CLICK_HINT"] = "点击以编辑尝试次数。"
L["TRIES"] = "次"
L["COLLECTION_LIST_ATTEMPTS_FMT"] = "%d次尝试"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "设置重置周期"
L["DAILY_RESET"] = "每日重置"
L["WEEKLY_RESET"] = "每周重置"
L["NONE_DISABLE"] = "无（禁用）"
L["RESET_CYCLE_LABEL"] = "重置周期："
L["RESET_NONE"] = "无"
L["DOUBLECLICK_RESET"] = "双击重置位置"

-- Error Messages
L["ERROR_GENERIC"] = "发生错误。"
L["ERROR_API_UNAVAILABLE"] = "所需 API 不可用。"
L["ERROR_BANK_CLOSED"] = "无法执行操作：银行已关闭。"
L["ERROR_INVALID_ITEM"] = "指定的物品无效。"
L["ERROR_PROTECTED_FUNCTION"] = "战斗中无法调用受保护函数。"

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "将 %d 件物品存入战团银行？"
L["CONFIRM_CLEAR_QUEUE"] = "清空存入队列中的所有物品？"
L["CONFIRM_DEPOSIT_GOLD"] = "将 %s 金币存入战团银行？"

-- Update Notification
L["WHATS_NEW"] = "更新内容"
L["GOT_IT"] = "知道了！"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "成就点数"
L["MOUNTS_COLLECTED"] = "已收集坐骑"
L["BATTLE_PETS"] = "战斗宠物"
L["TOTAL_PETS"] = "宠物总数"
L["UNIQUE_PETS"] = "独特宠物"
L["ACCOUNT_WIDE"] = "账号通用"
L["STORAGE_OVERVIEW"] = "存储概览"
L["WARBAND_SLOTS"] = "战团格子"
L["PERSONAL_SLOTS"] = "个人格子"
L["TOTAL_FREE"] = "总空闲"
L["TOTAL_ITEMS"] = "物品总数"

-- Plans Tracker
L["WEEKLY_VAULT"] = "每周宝库"
L["CUSTOM"] = "自定义"
L["NO_PLANS_IN_CATEGORY"] = "此分类暂无计划。\n从计划标签页添加计划。"
L["SOURCE_LABEL"] = "来源："
L["ZONE_LABEL"] = "区域："
L["VENDOR_LABEL"] = "商人："
L["DROP_LABEL"] = "掉落："
L["REQUIREMENT_LABEL"] = "要求："
L["RIGHT_CLICK_REMOVE"] = "右键点击移除"
L["CLICK_TO_DISMISS"] = "点击关闭"
L["TRACKED"] = "已追踪"
L["TRACK"] = "追踪"
L["TRACK_BLIZZARD_OBJECTIVES"] = "在暴雪任务中追踪（最多 10 个）"
L["UNKNOWN"] = "未知"
L["NO_REQUIREMENTS"] = "无要求（即时完成）"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "无计划活动"
L["NO_ACTIVE_CONTENT"] = "本周没有活跃内容"
L["CLICK_TO_ADD_GOALS"] = "点击上方的坐骑、宠物或玩具浏览并添加目标！"
L["UNKNOWN_QUEST"] = "未知任务"
L["ALL_QUESTS_COMPLETE"] = "所有任务已完成！"
L["CURRENT_PROGRESS"] = "当前进度"
L["SELECT_CONTENT"] = "选择内容："
L["QUEST_TYPES"] = "任务类型："
L["WORK_IN_PROGRESS"] = "进行中"
L["RECIPE_BROWSER"] = "配方浏览器"
L["NO_RESULTS_FOUND"] = "未找到结果。"
L["TRY_ADJUSTING_SEARCH"] = "尝试调整搜索或筛选条件。"
L["NO_COLLECTED_YET"] = "暂无已收集的 %s"
L["START_COLLECTING"] = "开始收集以在此查看！"
L["ALL_COLLECTED_CATEGORY"] = "所有 %s 已收集！"
L["COLLECTED_EVERYTHING"] = "你已收集此分类中的所有物品！"
L["PROGRESS_LABEL"] = "进度："
L["REQUIREMENTS_LABEL"] = "要求："
L["INFORMATION_LABEL"] = "信息："
L["DESCRIPTION_LABEL"] = "描述："
L["REWARD_LABEL"] = "奖励："
L["DETAILS_LABEL"] = "详情："
L["COST_LABEL"] = "花费："
L["LOCATION_LABEL"] = "位置："
L["TITLE_LABEL"] = "标题："
L["COMPLETED_ALL_ACHIEVEMENTS"] = "你已完成此分类中的所有成就！"
L["DAILY_PLAN_EXISTS"] = "每日计划已存在"
L["WEEKLY_PLAN_EXISTS"] = "每周计划已存在"

-- Characters Tab (extended)
L["YOUR_CHARACTERS"] = "你的角色"
L["CHARACTERS_TRACKED_FORMAT"] = "已追踪 %d 个角色"
L["NO_CHARACTER_DATA"] = "无角色数据"
L["NO_FAVORITES"] = "暂无收藏角色。点击星标图标收藏角色。"
L["ALL_FAVORITED"] = "所有角色已收藏！"
L["UNTRACKED_CHARACTERS"] = "未追踪角色"
L["ILVL_SHORT"] = "装等"
L["ONLINE"] = "在线"
L["TIME_LESS_THAN_MINUTE"] = "< 1 分钟前"
L["TIME_MINUTES_FORMAT"] = "%d 分钟前"
L["TIME_HOURS_FORMAT"] = "%d 小时前"
L["TIME_DAYS_FORMAT"] = "%d 天前"
L["REMOVE_FROM_FAVORITES"] = "从收藏中移除"
L["ADD_TO_FAVORITES"] = "添加到收藏"
L["FAVORITES_TOOLTIP"] = "收藏角色显示在列表顶部"
L["CLICK_TO_TOGGLE"] = "点击切换"
L["UNKNOWN_PROFESSION"] = "未知专业"
L["SKILL_LABEL"] = "技能："
L["OVERALL_SKILL"] = "总体技能："
L["BONUS_SKILL"] = "加成技能："
L["KNOWLEDGE_LABEL"] = "知识："
L["SPEC_LABEL"] = "专精"
L["POINTS_SHORT"] = " 点"
L["RECIPES_KNOWN"] = "已学配方："
L["OPEN_PROFESSION_HINT"] = "打开专业窗口"
L["FOR_DETAILED_INFO"] = "查看详细信息"
L["CHARACTER_IS_TRACKED"] = "此角色正在被追踪。"
L["TRACKING_ACTIVE_DESC"] = "数据收集和更新已激活。"
L["CLICK_DISABLE_TRACKING"] = "点击禁用追踪。"
L["MUST_LOGIN_TO_CHANGE"] = "必须登录此角色才能更改追踪。"
L["TRACKING_ENABLED"] = "追踪已启用"
L["CLICK_ENABLE_TRACKING"] = "点击为此角色启用追踪。"
L["TRACKING_WILL_BEGIN"] = "数据收集将立即开始。"
L["CHARACTER_NOT_TRACKED"] = "此角色未被追踪。"
L["MUST_LOGIN_TO_ENABLE"] = "必须登录此角色才能启用追踪。"
L["ENABLE_TRACKING"] = "启用追踪"
L["TRACKING_NOT_ENABLED_TOOLTIP"] = "角色追踪已禁用。点击打开角色标签页。"
L["TRACKING_BADGE_CLICK_HINT"] = "点击更改追踪设置。"
L["TRACKING_TAB_LOCKED_TITLE"] = "角色未被追踪"
L["TRACKING_TAB_LOCKED_DESC"] = "此标签页仅适用于已追踪的角色。\n请在角色页面使用追踪图标启用追踪。"
L["OPEN_CHARACTERS_TAB"] = "打开角色"
L["DELETE_CHARACTER_TITLE"] = "删除角色？"
L["THIS_CHARACTER"] = "此角色"
L["DELETE_CHARACTER"] = "删除所选角色"
L["REMOVE_FROM_TRACKING_FORMAT"] = "将 %s 从追踪中移除"
L["CLICK_TO_DELETE"] = "点击删除"
L["CONFIRM_DELETE"] = "确定要删除 |cff00ccff%s|r？"
L["CANNOT_UNDO"] = "此操作无法撤销！"

-- Items Tab (extended)
L["PERSONAL_ITEMS"] = "个人物品"
L["ITEMS_SUBTITLE"] = "浏览你的战团银行、公会银行和个人物品"
L["ITEMS_DISABLED_TITLE"] = "战团银行物品"
L["ITEMS_LOADING"] = "正在加载背包数据"
L["GUILD_BANK_REQUIRED"] = "你必须加入公会才能访问公会银行。"
L["GUILD_JOINED_FORMAT"] = "公会已更新：%s"
L["GUILD_LEFT"] = "你已离开公会。公会银行标签页已禁用。"
L["NO_PERMISSION"] = "无权限"
L["NOT_IN_GUILD"] = "未加入公会"
L["ITEMS_SEARCH"] = "搜索物品..."
L["NEVER"] = "从未"
L["ITEM_FALLBACK_FORMAT"] = "物品 %s"
L["ITEM_LOADING_NAME"] = "加载中..."
L["TAB_FORMAT"] = "标签页 %d"
L["BAG_FORMAT"] = "背包 %d"
L["BANK_BAG_FORMAT"] = "银行背包 %d"
L["ITEM_ID_LABEL"] = "物品 ID："
L["QUALITY_TOOLTIP_LABEL"] = "品质："
L["STACK_LABEL"] = "堆叠："
L["RIGHT_CLICK_MOVE"] = "移至背包"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "拆分堆叠"
L["LEFT_CLICK_PICKUP"] = "拾取"
L["ITEMS_BANK_NOT_OPEN"] = "银行未打开"
L["SHIFT_LEFT_CLICK_LINK"] = "在聊天中链接"
L["ITEM_DEFAULT_TOOLTIP"] = "物品"
L["ITEMS_STATS_ITEMS"] = "%s 件物品"
L["ITEMS_STATS_SLOTS"] = "%s/%s 格子"
L["ITEMS_STATS_LAST"] = "上次：%s"

-- Storage Tab (extended)
L["STORAGE_DISABLED_TITLE"] = "角色存储"
L["STORAGE_SEARCH"] = "搜索存储..."

-- PvE Tab (extended)
L["PVE_TITLE"] = "PvE 进度"
L["PVE_SUBTITLE"] = "宏伟宝库、团队副本锁定与史诗钥石，覆盖你的战团"
L["PVE_COL_EARNED"] = "获得"
L["PVE_COL_OWNED"] = "拥有"
L["PVE_COL_STASHES"] = "存储"
L["PVE_COL_OWNED_VAULT"] = "拥有"
L["PVE_COL_LOOTED"] = "已拾取"
L["PVE_COL_CREST"] = "纹章"
L["PVE_CREST_ADV"] = "冒险者"
L["PVE_CREST_VET"] = "老兵"
L["PVE_CREST_CHAMP"] = "勇士"
L["PVE_CREST_HERO"] = "英雄"
L["PVE_CREST_MYTH"] = "神话"
L["PVE_COL_COFFER_SHARDS"] = "宝匣钥匙碎片"
L["PVE_COL_RESTORED_KEY"] = "修复的宝匣钥匙"
L["PVE_COL_VAULT_SLOT1"] = "宝库 1"
L["PVE_COL_VAULT_SLOT2"] = "宝库 2"
L["PVE_COL_VAULT_SLOT3"] = "宝库 3"
L["PVE_NO_CHARACTER"] = "无角色数据"
L["LV_FORMAT"] = "等级 %d"
L["ILVL_FORMAT"] = "装等 %d"
L["VAULT_WORLD"] = "世界"
L["VAULT_SLOT_FORMAT"] = "%s 栏 %d"
L["VAULT_NO_PROGRESS"] = "暂无进度"
L["VAULT_UNLOCK_FORMAT"] = "完成 %s 项活动以解锁"
L["VAULT_NEXT_TIER_FORMAT"] = "下一阶：完成 %s 获得 %d 装等"
L["VAULT_REMAINING_FORMAT"] = "剩余：%s 项活动"
L["VAULT_PROGRESS_FORMAT"] = "进度：%s / %s"
L["OVERALL_SCORE_LABEL"] = "总评分："
L["BEST_KEY_FORMAT"] = "最佳钥石：+%d"
L["SCORE_FORMAT"] = "评分：%s"
L["NOT_COMPLETED_SEASON"] = "本季未完成"
L["CURRENT_MAX_FORMAT"] = "当前：%s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "进度：%.1f%%"
L["NO_CAP_LIMIT"] = "无上限"
L["GREAT_VAULT"] = "宏伟宝库"
L["LOADING_PVE"] = "正在加载 PvE 数据..."
L["PVE_APIS_LOADING"] = "请稍候，WoW API 正在初始化..."
L["NO_VAULT_DATA"] = "无宝库数据"
L["NO_DATA"] = "无数据"
L["KEYSTONE"] = "钥石"
L["NO_KEY"] = "无钥石"
L["AFFIXES"] = "词缀"
L["NO_AFFIXES"] = "无词缀"
L["VAULT_BEST_KEY"] = "最佳钥石："
L["VAULT_SCORE"] = "评分："

-- Vault Tooltip (detailed)
L["VAULT_UNLOCKED"] = "已解锁"
L["VAULT_LOCKED"] = "未解锁"
L["VAULT_IN_PROGRESS"] = "进行中"
L["VAULT_COMPLETED_ACTIVITIES"] = "已完成"
L["VAULT_CURRENT_TIER"] = "当前阶段"
L["VAULT_CLICK_TO_OPEN"] = "点击打开宏伟宝库"
L["VAULT_REWARD"] = "奖励"
L["VAULT_REWARD_ON_UNLOCK"] = "解锁后奖励"
L["VAULT_UPGRADE_HINT"] = "升级"
L["VAULT_MAX_TIER"] = "最高等级"
L["VAULT_AT_MAX"] = "已达最高等级！"
L["VAULT_BEST_SO_FAR"] = "目前最佳"
L["VAULT_DUNGEONS"] = "地下城"
L["VAULT_BOSS_KILLS"] = "首领击杀"
L["VAULT_WORLD_ACTIVITIES"] = "世界活动"
L["VAULT_ACTIVITIES"] = "活动"
L["VAULT_REMAINING_SUFFIX"] = "剩余"
L["VAULT_COMPLETE_PREFIX"] = "完成"
L["VAULT_SLOT1_HINT"] = "此行的第一个选择"
L["VAULT_SLOT2_HINT"] = "第二个选择（更多选项！）"
L["VAULT_SLOT3_HINT"] = "第三个选择（最多选项）"
L["VAULT_CLICK_TO_OPEN"] = "点击打开宏伟宝库"
L["VAULT_IMPROVE_TO"] = "提升至"
L["VAULT_COMPLETE_ON"] = "在 %s 上完成此活动"
L["VAULT_ENCOUNTER_LIST_FORMAT"] = "%s"
L["VAULT_TOP_RUNS_FORMAT"] = "本周前 %d 次记录"
L["VAULT_DELVE_TIER_FORMAT"] = "层级 %d（%d）"
L["VAULT_REWARD_HIGHEST"] = "最高物品等级奖励"
L["VAULT_UNLOCK_REWARD"] = "解锁奖励"
L["VAULT_COMPLETE_MORE_FORMAT"] = "本周再完成 %d 个 %s 以解锁。"
L["VAULT_BASED_ON_FORMAT"] = "此奖励的物品等级将基于本周前 %d 次记录中的最低值（当前 %s）。"
L["VAULT_RAID_BASED_FORMAT"] = "奖励基于已击败的最高难度（当前 %s）。"

-- Delves Section (PvE Tab)
L["DELVES"] = "地下堡"
L["COMPANION"] = "同伴"
L["BOUNTIFUL_DELVE"] = "珍宝猎手的奖赏"
L["PVE_BOUNTY_NEED_LOGIN"] = "该角色没有保存的状态。请登录以刷新。"
L["CRACKED_KEYSTONE"] = "破裂的钥石"
L["SEASON"] = "赛季"
L["CURRENCY_LABEL_WEEKLY"] = "每周"

-- Reputation Tab (extended)
L["REP_TITLE"] = "声望概览"
L["REP_SUBTITLE"] = "追踪你战团中的阵营和名望"
L["REP_DISABLED_TITLE"] = "声望追踪"
L["REP_LOADING_TITLE"] = "正在加载声望数据"
L["REP_SEARCH"] = "搜索声望..."
L["REP_PARAGON_TITLE"] = "巅峰声望"
L["REP_REWARD_AVAILABLE"] = "奖励可用！"
L["REP_CONTINUE_EARNING"] = "继续获取声望以获得奖励"
L["REP_CYCLES_FORMAT"] = "周期：%d"
L["REP_PROGRESS_HEADER"] = "进度：%d/%d"
L["REP_PARAGON_PROGRESS"] = "巅峰进度："
L["REP_PROGRESS_COLON"] = "进度："
L["REP_CYCLES_COLON"] = "周期："
L["REP_CHARACTER_PROGRESS"] = "角色进度："
L["REP_RENOWN_FORMAT"] = "名望 %d"
L["REP_PARAGON_FORMAT"] = "巅峰（%s）"
L["REP_UNKNOWN_FACTION"] = "未知阵营"
L["REP_API_UNAVAILABLE_TITLE"] = "声望 API 不可用"
L["REP_API_UNAVAILABLE_DESC"] = "此服务器上 C_Reputation API 不可用。此功能需要 WoW 11.0+（地心之战）。"
L["REP_FOOTER_TITLE"] = "声望追踪"
L["REP_FOOTER_DESC"] = "声望在登录和变更时自动扫描。使用游戏内声望面板查看详细信息和奖励。"
L["REP_CLEARING_CACHE"] = "正在清除缓存并重新加载..."
L["REP_LOADING_DATA"] = "正在加载声望数据..."
L["REP_MAX"] = "最大"
L["REP_TIER_FORMAT"] = "第 %d 级"
L["ACCOUNT_WIDE_LABEL"] = "账号通用"
L["NO_RESULTS"] = "无结果"
L["NO_REP_MATCH"] = "没有匹配 '%s' 的声望"
L["NO_REP_DATA"] = "无声望数据"
L["REP_SCAN_TIP"] = "声望自动扫描。如无显示请尝试 /reload。"
L["ACCOUNT_WIDE_REPS_FORMAT"] = "账号通用声望（%s）"
L["NO_ACCOUNT_WIDE_REPS"] = "无账号通用声望"
L["NO_CHARACTER_REPS"] = "无角色声望"

-- Currency Tab (extended)
L["GOLD_LABEL"] = "金币"
L["CURRENCY_TITLE"] = "货币追踪"
L["CURRENCY_SUBTITLE"] = "追踪所有角色的货币"
L["CURRENCY_DISABLED_TITLE"] = "货币追踪"
L["CURRENCY_LOADING_TITLE"] = "正在加载货币数据"
L["CURRENCY_SEARCH"] = "搜索货币..."
L["CURRENCY_HIDE_EMPTY"] = "隐藏空"
L["CURRENCY_SHOW_EMPTY"] = "显示空"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "全部战团可转移"
L["CURRENCY_CHARACTER_SPECIFIC"] = "角色专属货币"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "货币转移限制"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "暴雪 API 不支持自动货币转移。请使用游戏内货币窗口手动转移战团货币。"
L["CURRENCY_UNKNOWN"] = "未知货币"

-- Plans Tab (extended)
L["REMOVE_COMPLETED_TOOLTIP"] = "从我的计划列表中移除所有已完成计划。此操作无法撤销！"
L["RECIPE_BROWSER_DESC"] = "在游戏中打开专业窗口浏览配方。\n窗口打开时插件将扫描可用配方。"
L["SOURCE_ACHIEVEMENT_FORMAT"] = "%s |cff00ff00[%s %s]|r"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s 已有活跃的每周宝库计划。可在「我的计划」分类中找到。"
L["DAILY_PLAN_EXISTS_DESC"] = "%s 已有活跃的每日任务计划。可在「日常任务」分类中找到。"
L["TRANSMOG_WIP_DESC"] = "幻化收藏追踪正在开发中。\n\n此功能将在未来更新中提供，具有更好的性能和与战团系统的集成。"
L["WEEKLY_VAULT_CARD"] = "每周宝库卡片"
L["WEEKLY_VAULT_COMPLETE"] = "每周宝库卡片 - 完成"
L["UNKNOWN_SOURCE"] = "未知来源"
L["DAILY_TASKS_PREFIX"] = "每周进度 - "
L["COMPLETE_LABEL"] = "已完成"
L["NO_FOUND_FORMAT"] = "未找到 %s"
L["PLANS_COUNT_FORMAT"] = "%d 个计划"
L["PET_BATTLE_LABEL"] = "宠物对战："
L["QUEST_LABEL"] = "任务："

-- Settings Tab
L["CURRENT_LANGUAGE"] = "当前语言："
L["LANGUAGE_TOOLTIP"] = "插件自动使用你的 WoW 游戏客户端语言。要更改，请更新你的战网设置。"
L["POPUP_DURATION"] = "弹窗持续时间"
L["NOTIFICATION_DURATION"] = "通知持续时间"
L["POPUP_POSITION"] = "弹窗位置"
L["NOTIFICATION_POSITION"] = "通知位置"
L["SET_POSITION"] = "设置位置"
L["SET_BOTH_POSITION"] = "设置两处位置"
L["DRAG_TO_POSITION"] = "拖动以设置位置\n右键确认"
L["RESET_DEFAULT"] = "重置为默认"
L["RESET_POSITION"] = "重置位置"
L["TEST_POPUP"] = "测试弹窗"
L["TEST_NOTIFICATION"] = "测试通知"
L["CUSTOM_COLOR"] = "自定义颜色"
L["OPEN_COLOR_PICKER"] = "打开颜色选择器"
L["COLOR_PICKER_TOOLTIP"] = "打开 WoW 原生颜色选择器选择自定义主题色"
L["PRESET_THEMES"] = "预设主题"
L["WARBAND_NEXUS_SETTINGS"] = "Warband Nexus 设置"
L["NO_OPTIONS"] = "无选项"
L["TAB_FILTERING"] = "标签页筛选"
L["SCROLL_SPEED"] = "滚动速度"
L["ANCHOR_FORMAT"] = "锚点：%s  |  X：%d  |  Y：%d"
L["POPUP_POSITION_MAIN"] = "主（成就、坐骑等）"
L["POPUP_POSITION_SAME_CRITERIA"] = "全部同一位置（成就、标准进度等）"
L["CRITERIA_POSITION_LABEL"] = "标准进度位置"
L["SET_POSITION_CRITERIA"] = "设置标准位置"
L["RESET_CRITERIA_BLIZZARD"] = "重置（右侧）"
L["USE_ALERTFRAME_POSITION"] = "使用 AlertFrame 位置"
L["USE_ALERTFRAME_POSITION_ACTIVE"] = "正在使用暴雪 AlertFrame 位置"
L["NOTIFICATION_GHOST_MAIN"] = "成就 / 通知"
L["NOTIFICATION_GHOST_CRITERIA"] = "标准进度"
L["SHOW_WEEKLY_PLANNER"] = "每周计划（角色）"
L["LOCK_MINIMAP_ICON"] = "锁定小地图按钮"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "在提示中显示物品"
L["AUTO_SCAN_ITEMS"] = "自动扫描物品"
L["LIVE_SYNC"] = "实时同步"
L["BACKPACK_LABEL"] = "背包"
L["REAGENT_LABEL"] = "材料"

-- Shared Widgets & Dialogs
L["MODULE_DISABLED"] = "模块已禁用"
L["LOADING"] = "加载中..."
L["PLEASE_WAIT"] = "请稍候..."
L["RESET_PREFIX"] = "重置："
L["TRANSFER_CURRENCY"] = "转移货币"
L["AMOUNT_LABEL"] = "数量："
L["TO_CHARACTER"] = "目标角色："
L["SELECT_CHARACTER"] = "选择角色..."
L["CURRENCY_TRANSFER_INFO"] = "货币窗口将自动打开。\n你需要手动右键点击货币进行转移。"
L["SAVE"] = "保存"
L["TITLE_FIELD"] = "标题："
L["DESCRIPTION_FIELD"] = "描述："
L["CREATE_CUSTOM_PLAN"] = "创建自定义计划"
L["REPORT_BUGS"] = "在 CurseForge 上报告问题或分享建议以帮助改进插件。"
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus 提供集中式界面，用于管理你的所有角色、货币、声望、物品和战团内的 PvE 进度。"
L["CHARACTERS_DESC"] = "查看所有角色的金币、等级、装等、阵营、种族、职业、专业、钥石和最后登录信息。追踪或取消追踪角色，标记收藏。"
L["ITEMS_DESC"] = "搜索和浏览所有背包、银行和战团银行中的物品。打开银行时自动扫描。通过提示显示每个角色拥有的物品。"
L["STORAGE_DESC"] = "所有角色的聚合背包视图——背包、个人银行和战团银行合而为一。"
L["PVE_DESC"] = "追踪宏伟宝库进度、下一级指标、史诗钥石评分和钥石、钥石词缀、地下城历史和所有角色的升级货币。"
L["REPUTATIONS_DESC"] = "比较所有角色的声望进度。显示账号通用与角色专属阵营，悬停提示显示每角色明细。"
L["CURRENCY_DESC"] = "按资料片查看所有货币。通过悬停提示比较各角色数量。一键隐藏空货币。"
L["PLANS_DESC"] = "追踪未收集的坐骑、宠物、玩具、成就和幻化。添加目标、查看掉落来源、监控尝试次数。通过 /wn plan 或小地图图标访问。"
L["STATISTICS_DESC"] = "查看成就点数、坐骑/宠物/玩具/幻象/头衔收藏进度、独特宠物数量和背包/银行使用统计。"

-- PvE Difficulty Names
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "第 %d 级"
L["PREPARING"] = "准备中"

-- Statistics Tab (extended)
L["ACCOUNT_STATISTICS"] = "账号统计"
L["STATISTICS_SUBTITLE"] = "收藏进度、金币和存储概览"
L["WARBAND_WEALTH"] = "战团财富"
L["WARBAND_BANK"] = "战团银行"
L["CHARACTER_OVERVIEW"] = "角色概览"
L["TOTAL_CHARACTERS"] = "总计"
L["TRACKED_CHARACTERS"] = "已追踪"
L["FACTION_SPLIT"] = "阵营"
L["MOST_PLAYED"] = "最常游玩"
L["PLAYED_DAYS"] = "天"
L["PLAYED_HOURS"] = "小时"
L["PLAYED_MINUTES"] = "分钟"
L["PLAYED_DAY"] = "天"
L["PLAYED_HOUR"] = "小时"
L["PLAYED_MINUTE"] = "分钟"
L["MORE_CHARACTERS"] = "更多角色"
L["MORE_CHARACTERS_PLURAL"] = "更多角色"

-- Information Dialog (extended)
L["WELCOME_TITLE"] = "欢迎使用 Warband Nexus！"
L["ADDON_OVERVIEW_TITLE"] = "插件概览"

-- Plans UI (extended)
L["PLANS_SUBTITLE_TEXT"] = "追踪你的每周目标和收藏"
L["ACTIVE_PLAN_FORMAT"] = "%d 个活跃计划"
L["ACTIVE_PLANS_FORMAT"] = "%d 个活跃计划"

-- Plans - Type Names
L["TYPE_RECIPE"] = "配方"
L["TYPE_ILLUSION"] = "幻象"
L["TYPE_TITLE"] = "头衔"
L["TYPE_CUSTOM"] = "自定义"

-- Plans - Source Type Labels
L["SOURCE_TYPE_TRADING_POST"] = "贸易站"
L["SOURCE_TYPE_TREASURE"] = "宝藏"
L["SOURCE_TYPE_PUZZLE"] = "谜题"
L["SOURCE_TYPE_RENOWN"] = "名望"

-- Plans - Source Text Parsing Keywords
L["PARSE_SOLD_BY"] = "出售者"
L["PARSE_CRAFTED"] = "制造"
L["PARSE_COST"] = "花费"
L["PARSE_HOLIDAY"] = "节日"
L["PARSE_RATED"] = "评级"
L["PARSE_BATTLEGROUND"] = "战场"
L["PARSE_DISCOVERY"] = "发现"
L["PARSE_CONTAINED_IN"] = "包含于"
L["PARSE_GARRISON"] = "要塞"
L["PARSE_GARRISON_BUILDING"] = "要塞建筑"
L["PARSE_STORE"] = "商店"
L["PARSE_ORDER_HALL"] = "职业大厅"
L["PARSE_COVENANT"] = "盟约"
L["PARSE_FRIENDSHIP"] = "友谊"
L["PARSE_PARAGON"] = "巅峰"
L["PARSE_MISSION"] = "任务"
L["PARSE_EXPANSION"] = "资料片"
L["PARSE_SCENARIO"] = "场景战役"
L["PARSE_CLASS_HALL"] = "职业大厅"
L["PARSE_CAMPAIGN"] = "战役"
L["PARSE_EVENT"] = "活动"
L["PARSE_SPECIAL"] = "特殊"
L["PARSE_BRAWLERS_GUILD"] = "搏击俱乐部"
L["PARSE_CHALLENGE_MODE"] = "挑战模式"
L["PARSE_MYTHIC_PLUS"] = "史诗钥石"
L["PARSE_TIMEWALKING"] = "时空漫游"
L["PARSE_ISLAND_EXPEDITION"] = "海岛探险"
L["PARSE_WARFRONT"] = "战争前线"
L["PARSE_TORGHAST"] = "托加斯特"
L["PARSE_ZERETH_MORTIS"] = "扎雷殁提斯"
L["PARSE_HIDDEN"] = "隐藏"
L["PARSE_RARE"] = "稀有"
L["PARSE_WORLD_BOSS"] = "世界首领"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "来自成就"
L["FALLBACK_UNKNOWN_PET"] = "未知宠物"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "宠物收藏"
L["FALLBACK_TOY_COLLECTION"] = "玩具收藏"
L["FALLBACK_TOY_BOX"] = "玩具箱"
L["FALLBACK_WARBAND_TOY"] = "战团玩具"
L["FALLBACK_TRANSMOG_COLLECTION"] = "幻化收藏"
L["FALLBACK_PLAYER_TITLE"] = "玩家头衔"
L["FALLBACK_ILLUSION_FORMAT"] = "幻象 %s"
L["SOURCE_ENCHANTING"] = "附魔"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "设置尝试次数：\n%s"
L["RESET_COMPLETED_CONFIRM"] = "确定要移除所有已完成计划？\n\n此操作无法撤销！"
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
L["QUEST_CAT_ASSIGNMENT"] = "指派"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "未知分类"
L["SCANNING_FORMAT"] = "正在扫描 %s"
L["CUSTOM_PLAN_SOURCE"] = "自定义计划"
L["POINTS_FORMAT"] = "%d 点"
L["SOURCE_NOT_AVAILABLE"] = "来源信息不可用"
L["SOURCE_QUEST_REWARD"] = "任务奖励"
L["PROGRESS_ON_FORMAT"] = "你的进度为 %d/%d"
L["COMPLETED_REQ_FORMAT"] = "你已完成 %d 项，共 %d 项要求"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "至暗之夜"
L["WEEKLY_RESET_LABEL"] = "每周重置"
L["CROSS_CHAR_SUMMARY"] = "角色概览"
L["QUEST_TYPE_DAILY"] = "每日任务"
L["QUEST_TYPE_DAILY_DESC"] = "来自 NPC 的常规每日任务"
L["QUEST_TYPE_WORLD"] = "世界任务"
L["QUEST_TYPE_WORLD_DESC"] = "区域范围内的世界任务"
L["QUEST_TYPE_WEEKLY"] = "每周任务"
L["QUEST_TYPE_WEEKLY_DESC"] = "每周循环任务"
L["QUEST_TYPE_ASSIGNMENTS"] = "指派任务"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "特殊指派和任务"
L["QUEST_TYPE_CONTENT_EVENTS"] = "内容事件"
L["QUEST_TYPE_CONTENT_EVENTS_DESC"] = "奖励目标、活动任务和战役风格活动"
L["QUEST_CAT_CONTENT_EVENTS"] = "内容事件"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "史诗钥石"

-- PlanCardFactory
L["FACTION_LABEL"] = "阵营："
L["FRIENDSHIP_LABEL"] = "友谊"
L["RENOWN_TYPE_LABEL"] = "名望"
L["ADD_BUTTON"] = "+ 添加"
L["ADDED_LABEL"] = "已添加"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s / %s（%s%%）"

-- Settings - General Tooltips
L["SHOW_ITEM_COUNT_TOOLTIP"] = "在存储和物品视图中显示物品堆叠数量"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "在角色标签页中显示或隐藏每周计划部分"
L["LOCK_MINIMAP_TOOLTIP"] = "锁定小地图按钮位置，无法拖动"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "在提示中显示战团和角色物品数量（WN 搜索）"
L["AUTO_SCAN_TOOLTIP"] = "打开银行或背包时自动扫描并缓存物品"
L["LIVE_SYNC_TOOLTIP"] = "银行打开时实时更新物品缓存"
L["SHOW_ILVL_TOOLTIP"] = "在物品列表中显示装备的装等徽章"
L["SCROLL_SPEED_TOOLTIP"] = "滚动速度倍数（1.0x = 每步 28 像素）"
L["UI_SCALE"] = "界面缩放"
L["UI_SCALE_TOOLTIP"] = "缩放整个插件窗口。如果窗口占用太多空间，请减小此值。"

-- Settings - Tab Filtering
L["IGNORE_WARBAND_TAB_FORMAT"] = "忽略标签页 %d"
L["IGNORE_SCAN_FORMAT"] = "从自动扫描中排除 %s"

-- Settings - Notifications
L["ENABLE_NOTIFICATIONS"] = "启用所有通知"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "主开关——禁用下方所有弹窗通知、聊天提醒和视觉效果"
L["VAULT_REMINDER"] = "每周宝库提醒"
L["VAULT_REMINDER_TOOLTIP"] = "当你有未领取的宏伟宝库奖励时，登录时显示提醒弹窗"
L["LOOT_ALERTS"] = "坐骑/宠物/玩具战利品提醒"
L["LOOT_ALERTS_TOOLTIP"] = "当新的坐骑、宠物、玩具或成就加入收藏时显示弹窗"
L["LOOT_ALERTS_MOUNT"] = "坐骑通知"
L["LOOT_ALERTS_MOUNT_TOOLTIP"] = "收集新坐骑时显示通知"
L["LOOT_ALERTS_PET"] = "宠物通知"
L["LOOT_ALERTS_PET_TOOLTIP"] = "收集新宠物时显示通知"
L["LOOT_ALERTS_TOY"] = "玩具通知"
L["LOOT_ALERTS_TOY_TOOLTIP"] = "收集新玩具时显示通知"
L["LOOT_ALERTS_TRANSMOG"] = "外观通知"
L["LOOT_ALERTS_TRANSMOG_TOOLTIP"] = "收集新护甲或武器外观时显示通知"
L["LOOT_ALERTS_ILLUSION"] = "幻象通知"
L["LOOT_ALERTS_ILLUSION_TOOLTIP"] = "收集新武器幻象时显示通知"
L["LOOT_ALERTS_TITLE"] = "头衔通知"
L["LOOT_ALERTS_TITLE_TOOLTIP"] = "获得新头衔时显示通知"
L["LOOT_ALERTS_ACHIEVEMENT"] = "成就通知"
L["LOOT_ALERTS_ACHIEVEMENT_TOOLTIP"] = "获得新成就时显示通知"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "替换成就弹窗"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "用 Warband Nexus 通知样式替换暴雪默认成就弹窗"
L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS"] = "标准进度提示"
L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS_TOOLTIP"] = "成就标准完成时显示小提示（进度 X/Y 及标准名称）。"
L["CRITERIA_PROGRESS_MSG"] = "进度"
L["CRITERIA_PROGRESS_FORMAT"] = "进度 %d/%d"
L["CRITERIA_PROGRESS_CRITERION"] = "标准"
L["ACHIEVEMENT_PROGRESS_TITLE"] = "成就进度"
L["REPUTATION_GAINS"] = "显示声望获取"
L["REPUTATION_GAINS_TOOLTIP"] = "获得阵营声望时在聊天中显示声望获取消息"
L["CURRENCY_GAINS"] = "显示货币获取"
L["CURRENCY_GAINS_TOOLTIP"] = "获得货币时在聊天中显示货币获取消息"
L["SCREEN_FLASH_EFFECT"] = "稀有掉落闪烁"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "多次尝试后终于获得收藏品时播放屏幕闪烁动画"
L["AUTO_TRY_COUNTER"] = "自动追踪掉落尝试"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "拾取 NPC、稀有、首领、钓鱼或容器时自动统计失败掉落尝试。收藏品最终掉落时在弹窗中显示总尝试次数。"
L["SETTINGS_ESC_HINT"] = "按 |cff999999ESC|r 关闭此窗口。"
L["HIDE_TRY_COUNTER_CHAT"] = "在聊天中隐藏尝试次数"
L["HIDE_TRY_COUNTER_CHAT_TOOLTIP"] = "隐藏所有尝试计数相关聊天消息（[WN-Counter]、[WN-Drops]、获得/钓起等）。计数仍在后台进行；弹窗与屏幕闪光不受影响。\n\n开启时，下方的“进入副本时列出掉落”与聊天路由相关选项将禁用。"
L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES"] = "进入副本时：在聊天中列出掉落"
L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES_TOOLTIP"] = "进入带有尝试计数收藏品的地下城或团队副本时，为每件物品输出一行 |cff9370DB[WN-Drops]|r：链接 — 所需难度（|cff00ff00绿色|r 符合，|cffff6666红色|r 不符，|cffffaa00琥珀色|r 未知）— 尝试次数或已收藏。大型副本最多 18 行外加 |cff00ccff/wn check|r。关闭则仅显示简短提示。"
L["TRYCOUNTER_INSTANCE_DROPS_TRUNCATED"] = "… 还有 |cffffccff%d|r 条 — 对首领使用 |cffffffff/wn check|r（目标或鼠标指向）。"
L["TRYCOUNTER_CHAT_ROUTE_LABEL"] = "尝试计数聊天输出"
L["TRYCOUNTER_CHAT_ROUTE_DESC"] = "尝试计数的行输出位置。默认与“拾取”相同标签页。“Warband Nexus”使用 WN_TRYCOUNTER 分组（可在聊天标签设置中选择）。“所有标签”发送到每个编号聊天窗口。"
L["TRYCOUNTER_CHAT_ROUTE_LOOT"] = "1）与拾取相同（默认）"
L["TRYCOUNTER_CHAT_ROUTE_DEDICATED"] = "2）Warband Nexus（独立过滤）"
L["TRYCOUNTER_CHAT_ROUTE_ALL_TABS"] = "3）所有标准聊天标签"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_BTN"] = "将尝试计数添加到所选聊天标签"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_TOOLTIP"] = "先点击目标聊天标签，再点此处。适合“Warband Nexus”模式。会向该标签添加 WN_TRYCOUNTER。"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_OK"] = "|cff9966ff[Warband Nexus]|r 已在所选聊天标签启用尝试计数。"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_FAIL"] = "|cffff6600[Warband Nexus]|r 无法更新聊天标签（无聊天框或 API 被阻止）。"
L["DURATION_LABEL"] = "持续时间"
L["DAYS_LABEL"] = "天"
L["WEEKS_LABEL"] = "周"
L["EXTEND_DURATION"] = "延长持续时间"

-- Settings - Position
L["DRAG_POSITION_MSG"] = "拖动绿色框以设置弹窗位置。右键确认。"
L["DRAG_BOTH_POSITION_MSG"] = "拖动以定位。右键保存与通知和标准相同的位置。"
L["POSITION_RESET_MSG"] = "弹窗位置已重置为默认（顶部居中）"
L["POSITION_SAVED_MSG"] = "弹窗位置已保存！"
L["TEST_NOTIFICATION_TITLE"] = "测试通知"
L["TEST_NOTIFICATION_MSG"] = "位置测试"
L["NOTIFICATION_DEFAULT_TITLE"] = "通知"

-- Settings - Theme & Appearance
L["THEME_APPEARANCE"] = "主题与外观"
L["COLOR_PURPLE"] = "紫色主题"
L["COLOR_PURPLE_DESC"] = "经典紫色主题（默认）"
L["COLOR_BLUE"] = "蓝色主题"
L["COLOR_BLUE_DESC"] = "冷色蓝主题"
L["COLOR_GREEN"] = "绿色主题"
L["COLOR_GREEN_DESC"] = "自然绿主题"
L["COLOR_RED"] = "红色主题"
L["COLOR_RED_DESC"] = "火焰红主题"
L["COLOR_ORANGE"] = "橙色主题"
L["COLOR_ORANGE_DESC"] = "温暖橙主题"
L["COLOR_CYAN"] = "青色主题"
L["COLOR_CYAN_DESC"] = "明亮青主题"

-- Settings - Font
L["FONT_FAMILY"] = "字体"
L["FONT_FAMILY_TOOLTIP"] = "选择插件界面使用的字体"
L["FONT_SCALE"] = "字体缩放"
L["FONT_SCALE_TOOLTIP"] = "调整所有界面元素的字体大小"
L["ANTI_ALIASING"] = "抗锯齿"
L["ANTI_ALIASING_DESC"] = "字体边缘渲染样式（影响可读性）"
L["FONT_SCALE_WARNING"] = "警告：较高的字体缩放可能导致部分界面元素文字溢出。"
L["RESOLUTION_NORMALIZATION"] = "分辨率标准化"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "根据屏幕分辨率和界面缩放调整字体大小，确保不同显示器上的物理尺寸一致"

-- Settings - Advanced
L["ADVANCED_SECTION"] = "高级"

-- Settings - Module Management
L["MODULE_MANAGEMENT"] = "模块管理"
L["MODULE_MANAGEMENT_DESC"] = "启用或禁用特定数据收集模块。禁用模块将停止其数据更新并从界面隐藏其标签页。"
L["MODULE_CURRENCIES"] = "货币"
L["MODULE_CURRENCIES_DESC"] = "追踪账号通用和角色专属货币（金币、荣誉、征服等）"
L["MODULE_REPUTATIONS"] = "声望"
L["MODULE_REPUTATIONS_DESC"] = "追踪阵营声望进度、名望等级和巅峰奖励"
L["MODULE_ITEMS"] = "物品"
L["MODULE_ITEMS_DESC"] = "追踪战团银行物品、搜索功能和物品分类"
L["MODULE_STORAGE"] = "存储"
L["MODULE_STORAGE_DESC"] = "追踪角色背包、个人银行和战团银行存储"
L["MODULE_PVE"] = "PvE"
L["MODULE_PVE_DESC"] = "追踪史诗钥石地下城、团队副本进度和每周宝库奖励"
L["MODULE_PLANS"] = "待办"
L["MODULE_PLANS_DESC"] = "追踪坐骑、宠物、玩具、成就和自定义任务的个人目标"
L["MODULE_PROFESSIONS"] = "专业"
L["MODULE_PROFESSIONS_DESC"] = "追踪专业技能、专注、知识和配方助手窗口"
L["MODULE_GEAR"] = "装备"
L["MODULE_GEAR_DESC"] = "跨角色装备管理和物品等级追踪"
L["MODULE_COLLECTIONS"] = "收藏"
L["MODULE_COLLECTIONS_DESC"] = "坐骑、宠物、玩具、幻化和收藏概览"
L["MODULE_TRY_COUNTER"] = "尝试计数器"
L["MODULE_TRY_COUNTER_DESC"] = "自动追踪NPC、Boss、钓鱼和容器的掉落尝试。禁用将停止所有计数器处理、提示和通知。"
L["PROFESSIONS_DISABLED_TITLE"] = "专业"

-- Tooltip Service
L["ITEM_LEVEL_FORMAT"] = "物品等级 %s"
L["ITEM_NUMBER_FORMAT"] = "物品 #%s"
L["CHARACTER_CURRENCIES"] = "角色货币："
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "账号通用（战团）——所有角色余额相同。"
L["YOU_MARKER"] = "（你）"
L["WN_SEARCH"] = "WN 搜索"
L["WARBAND_BANK_COLON"] = "战团银行："
L["AND_MORE_FORMAT"] = "... 还有 %d 个"

-- Notification Manager
L["COLLECTED_MOUNT_MSG"] = "你已收集坐骑"
L["COLLECTED_PET_MSG"] = "你已收集战斗宠物"
L["COLLECTED_TOY_MSG"] = "你已收集玩具"
L["COLLECTED_ILLUSION_MSG"] = "你已收集幻象"
L["COLLECTED_ITEM_MSG"] = "你获得了稀有掉落"
L["ACHIEVEMENT_COMPLETED_MSG"] = "成就已完成！"
L["HIDDEN_ACHIEVEMENT"] = "隐藏成就"
L["EARNED_TITLE_MSG"] = "你获得了头衔"
L["COMPLETED_PLAN_MSG"] = "你已完成计划"
L["DAILY_QUEST_CAT"] = "每日任务"
L["WORLD_QUEST_CAT"] = "世界任务"
L["WEEKLY_QUEST_CAT"] = "每周任务"
L["SPECIAL_ASSIGNMENT_CAT"] = "特殊指派"
L["DELVE_CAT"] = "探索"
L["WORLD_CAT"] = "世界"
L["ACTIVITY_CAT"] = "活动"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d 进度"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d 进度已完成"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "每周宝库计划 - %s"
L["ALL_SLOTS_COMPLETE"] = "所有槽位已完成！"
L["QUEST_COMPLETED_SUFFIX"] = "已完成"
L["WEEKLY_VAULT_READY"] = "每周宝库就绪！"
L["UNCLAIMED_REWARDS"] = "你有未领取的奖励"
L["NOTIFICATION_FIRST_TRY"] = "第一次尝试就获得了！"
L["NOTIFICATION_GRIND_TRIES"] = "真是辛苦！%d次尝试！"
L["NOTIFICATION_GOT_IT_AFTER"] = "经过%d次尝试后获得！"
L["NOTIFICATION_TRY_SUBTITLE"] = "%d 次尝试"
L["NOTIFICATION_TRY_SUBTITLE_FIRST"] = "首次尝试！"

-- Minimap Button
L["TOTAL_GOLD_LABEL"] = "总金币："
L["MINIMAP_CHARS_GOLD"] = "角色金币："
L["CHARACTERS_COLON"] = "角色："
L["LEFT_CLICK_TOGGLE"] = "左键：切换窗口"
L["RIGHT_CLICK_PLANS"] = "右键：打开计划"
L["MINIMAP_SHOWN_MSG"] = "小地图按钮已显示"
L["MINIMAP_HIDDEN_MSG"] = "小地图按钮已隐藏（使用 /wn minimap 显示）"
L["TOGGLE_WINDOW"] = "切换窗口"
L["SCAN_BANK_MENU"] = "扫描银行"
L["TRACKING_DISABLED_SCAN_MSG"] = "角色追踪已禁用。请在设置中启用追踪以扫描银行。"
L["SCAN_COMPLETE_MSG"] = "扫描完成！"
L["BANK_NOT_OPEN_MSG"] = "银行未打开"
L["OPTIONS_MENU"] = "选项"
L["HIDE_MINIMAP_BUTTON"] = "隐藏小地图按钮"
L["MENU_UNAVAILABLE_MSG"] = "右键菜单不可用"
L["USE_COMMANDS_MSG"] = "使用 /wn show、/wn options、/wn help"
L["MINIMAP_MORE_FORMAT"] = "... +%d更多"

-- SharedWidgets (extended)
L["MAX_BUTTON"] = "最大"
L["OPEN_AND_GUIDE"] = "打开并引导"
L["FROM_LABEL"] = "来自："
L["AVAILABLE_LABEL"] = "可用："
L["ONLINE_LABEL"] = "（在线）"
L["DATA_SOURCE_TITLE"] = "数据源信息"
L["DATA_SOURCE_USING"] = "此标签页使用："
L["DATA_SOURCE_MODERN"] = "现代缓存服务（事件驱动）"
L["DATA_SOURCE_LEGACY"] = "传统直接数据库访问"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "需要迁移到缓存服务"
L["GLOBAL_DB_VERSION"] = "全局数据库版本："

-- Information Dialog - Tab Headers
L["INFO_TAB_CHARACTERS"] = "角色"
L["INFO_TAB_ITEMS"] = "物品"
L["INFO_TAB_STORAGE"] = "存储"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "声望"
L["INFO_TAB_CURRENCY"] = "货币"
L["INFO_TAB_PLANS"] = "待办"
L["INFO_TAB_GEAR"] = "装备"
L["INFO_TAB_COLLECTIONS"] = "收藏"
L["INFO_TAB_STATISTICS"] = "统计"
L["INFO_CREDITS_SECTION_TITLE"] = "致谢与名单"
L["INFO_CREDITS_LORE_SUBTITLE"] = "特别鸣谢"
L["INFO_FEATURES_SECTION_TITLE"] = "功能概览"
L["HEADER_INFO_TOOLTIP"] = "插件说明与致谢"
L["HEADER_INFO_TOOLTIP_HINT"] = "功能与贡献者 — 名单在顶部。"
L["SUPPORTERS_TITLE"] = "支持者"
L["CONTRIBUTORS_TITLE"] = "贡献者"
L["THANK_YOU_MSG"] = "感谢使用 Warband Nexus！"

-- Information Dialog - Professions Tab
L["INFO_TAB_PROFESSIONS"] = "专业"
L["PROFESSIONS_INFO_DESC"] = "追踪所有角色的专业技能、专注、知识和专精树。包含配方助手用于材料来源。"

-- Information Dialog - Gear & Collections Tabs
L["GEAR_DESC"] = "查看已装备、升级机会、存储推荐（装绑/战团绑定）及跨角色升级候选与装等追踪。"
L["COLLECTIONS_DESC"] = "坐骑、宠物、玩具、幻化及其他收藏概览。追踪收藏进度并查找缺失物品。"

-- Command Help Strings
L["AVAILABLE_COMMANDS"] = "可用命令："
L["CMD_OPEN"] = "打开插件窗口"
L["CMD_PLANS"] = "切换待办追踪器窗口"
L["CMD_FIRSTCRAFT"] = "按资料片列出首次制作奖励配方（请先打开专业窗口）"
L["CMD_OPTIONS"] = "打开设置"
L["CMD_MINIMAP"] = "切换小地图按钮"
L["CMD_CHANGELOG"] = "显示更新日志"
L["CMD_DEBUG"] = "切换调试模式"
L["CMD_PROFILER"] = "性能分析器"
L["CMD_HELP"] = "显示此列表"
L["PLANS_NOT_AVAILABLE"] = "计划追踪不可用。"
L["MINIMAP_NOT_AVAILABLE"] = "小地图按钮模块未加载。"
L["PROFILER_NOT_LOADED"] = "分析器模块未加载。"
L["UNKNOWN_COMMAND"] = "未知命令。"
L["TYPE_HELP"] = "输入"
L["FOR_AVAILABLE_COMMANDS"] = "查看可用命令。"
L["UNKNOWN_DEBUG_CMD"] = "未知调试命令："
L["DEBUG_ENABLED"] = "调试模式已启用。"
L["DEBUG_DISABLED"] = "调试模式已禁用。"
L["CHARACTER_LABEL"] = "角色："
L["TRACK_USAGE"] = "用法：enable | disable | status"

-- Welcome Messages
L["CLICK_TO_COPY"] = "点击复制邀请链接"
L["COPIED_LABEL"] = "已复制！"
L["WELCOME_MSG_FORMAT"] = "欢迎使用 Warband Nexus v%s"
L["WELCOME_TYPE_CMD"] = "请输入"
L["WELCOME_OPEN_INTERFACE"] = "以打开界面。"
L["WELCOME_NEW_VERSION_CHAT"] = "|cffffff00更新内容：|r 可能会在聊天上方弹出窗口，或输入 |cffffff00/wn changelog|r。"
L["CONFIG_SHOW_LOGIN_CHAT"] = "在聊天中显示登录提示"
L["CONFIG_SHOW_LOGIN_CHAT_DESC"] = "开启通知时打印一行简短欢迎语。使用“系统”消息组与可见聊天标签（如 Chattynator）。更新说明窗口为独立全屏弹窗。"
L["CONFIG_HIDE_PLAYED_TIME_CHAT"] = "在聊天中隐藏游戏时间"
L["CONFIG_HIDE_PLAYED_TIME_CHAT_DESC"] = "过滤“总游戏时间”和“本等级游戏时间”等系统消息。关闭本项可再次显示（包括 /played）。"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN"] = "登录时请求游戏时间"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN_DESC"] = "开启时在后台请求 /played 以更新“游玩最多”等统计，并隐藏聊天输出。关闭则登录时不自动请求（仍可手动 /played）。"

-- What's New (changelog)
L["CHANGELOG_V256"] = "v2.5.6\n改进：\n- 装备、周计划、计划追踪与跟踪确认界面更易读服务器名；存档键仍用暴雪规范化字符串\n- 收藏品：扩展 BfA「驯服的血虱缰绳」NPC；补充宝箱与首领、多尸体拾取与尝试计数的说明\n- SplitCharacterKey +「角色名-服务器」仅在第一个连字符处拆分\n- 坐骑数据库审计：社区 DB/Mounts Lua + Wowhead/WoWDB\n\n修复：\n- 尝试计数：聊天拾取 + 共享掉落表不再丢失 CHAT 更新（如血虱）\n- 含连字符服务器（Azjol-Nerub）：规范键、GetAllCharacters 修复、统计/小地图；一次性 realm 字段迁移\n- 坐骑物品 ID：Verdant Skitterfly（192764）、红色其拉共鸣水晶（21321）\n- 跟踪对话框：GetRealmName 对秘密值防护\n\n本地化：\n- 各语言 TRY_COUNT 左键/右键提示\n\n仓库：Git 仅跟踪插件源码（Core、Modules、Locales、toc、CHANGES）\n\nCurseForge：Warband Nexus"

L["CHANGELOG_V257"] = "v2.5.7b\n改进：\n- 角色：默认排序（当前在线角色优先，等级、名称）；新档案默认；未知排序键映射为菜单首项\n- 角色：收藏/角色/未追踪中在线角色置顶；手动顺序一致\n- 尝试计数：副本难度使用 GetInstanceInfo + 进本快照（修正史诗误判普通，如麦卡贡 HK-8）\n- 尝试计数：拾取、延迟 ENC、CHAT 共用难度过滤；CHAT 与拾取窗口使用相同 encounter_ 去重键\n- 尝试计数：零可追踪时仍写入 encounter_ 键，避免延迟 ENC/CHAT 重复计数\n- 尝试计数：开放世界合并拾取按相同坐骑物品统计多模板 NPC 尸体（BfA 血虱）\n- 装备：角色选择器宽度\n\n修复：\n- 尝试计数：已因难度跳过仍增加次数\n\n本地化：SORT_MODE_DEFAULT\n\nCurseForge：Warband Nexus"

L["CHANGELOG_V258"] = "v2.5.8\n修复：\n- 尝试计数：CHAT_MSG_LOOT 在钓鱼归因路径上不再报错（CurrentUnitsHaveMobLootContext 前向声明；此前为 nil 全局）。\n\nCurseForge：Warband Nexus"

L["CHANGELOG_V259"] = [=[v2.5.9（2026-04-03）

改进
- 收藏 / 尝试计数：达萨罗之战 — Glacial Tidestorm 仅吉安娜史诗（非随机团）。G.M.O.D.：随机团吉安娜；普通/英雄/史诗大工匠（2019 热修）。显式随机团；按掉落行 statisticIds 重播统计；大工匠不计吉安娜随机团（13379）。
- CollectibleSourceDB：坐骑首领 legacyEncounters 对齐 Midnight DungeonEncounter ID。
- Git 仓库：仅插件源码（Core、Modules、Locales、toc、CHANGES、LICENSE、README）；文档与审计脚本已移除。

--- 2.5.8 ---
修复
- 尝试计数：钓鱼 CHAT_MSG_LOOT — CurrentUnitsHaveMobLootContext 前置声明（此前 nil 全局）。

--- 2.5.7 / 2.5.7b ---
热修
- 装备页：角色选择与下拉菜单。
- 关于 / 信息：致谢与贡献者。

改进
- 角色：默认排序（当前角色 → 等级高→低 → 名 A–Z）。新档案 characterSort.key = default。无效键映射菜单首项。收藏、追踪、未追踪中在线角色置顶（含手动排序）；手动种子含整区、在线优先；characterOrder 含未追踪列表；重排保持在线置顶。
- 设置：WindowManager（POPUP、与主窗共享 ESC）替代固定 FULLSCREEN_DIALOG。RefreshSettingsKeyboard 在 Show 后恢复键盘。字体重建时从 WindowManager 注销设置窗。
- WindowManager：战后恢复除 SetPropagateKeyboardInput(true) 外调用 EnableKeyboard(true)。
- 尝试计数：副本难度优先进本快照（PLAYER_ENTERING_WORLD、副本 ID），再 GetInstanceInfo，早于 ENCOUNTER_END 与 API — 修正史诗读成普通（如麦卡贡 HK-8）。difficulty 0 时 M+/API 用 ResolveLiveInstanceDifficultyID；ResolveEffectiveEncounterDifficultyID 统一过滤。
- 尝试计数：FilterDropsByDifficulty 用于拾取、延迟 ENC、CHAT_MSG_LOOT；与拾取窗相同 encounter_ 去重键。
- 尝试计数：规则后无可追踪掉落仍记录去重键（避免延迟 ENC/CHAT 重复）。
- 尝试计数：野外合并拾取按物品 ID 尸体倍率（如纳兹米尔血饕餮）。
- 尝试计数：LOOT_READY 连发不清空会话；调试追踪短时去重。
- 尝试计数：[WN-Drops] TRYCOUNTER_INSTANCE_DROPS_HEADER；链接后括号显示所需难度 — 绿/红/琥珀。

修复
- 尝试计数：已提示跳过难度后计数仍涨（拾取 vs 延迟 ENC/CHAT）。

本地化
- SORT_MODE_DEFAULT；TRYCOUNTER_INSTANCE_COLLECTIBLE_DETECTED 等。

--- 2.5.6 ---
改进
- 装备、计划、追踪、跟踪器中服务器更易读。
- 收藏：更多 BfA 血饕餮 NPC；宝箱 vs 首领备注与多尸体。
- SplitCharacterKey + 名-服首个连字符。
- 坐骑：社区 Lua DB + Wowhead/WoWDB。

修复
- 尝试计数：聊天拾取 + 共享表 — 保留 CHAT 更新。
- 连字符服务器：规范键、GetAllCharacters、stats/小地图；一次性迁移。
- 坐骑 ID：Verdant Skitterfly（192764）、红色其拉水晶（21321）。
- 对话框：GetRealmName 保护。

本地化
- TRY_COUNT 左键/右键提示。

后续
- 加强收藏与遭遇 ID 的 Midnight 校验；据团本反馈打磨尝试计数与通知。

CurseForge：Warband Nexus]=]

L["CHANGELOG_V259b"] = [=[v2.5.9b（2026-04-04）

改进
- 提示：NPC 单位提示上的收藏品掉落信息仅在目标为敌对或可攻击时显示（修复友好 delve 石等上出现错误坐骑行的问题）。对 UnitCanAttack、UnitIsDead、UnitReaction 做安全检测（Midnight 秘密值规则）。
- 打包：发行 ZIP 由 build_addon.py（Python 3.8+）生成；归档内路径使用 /，便于 Linux、macOS 与 CurseForge Linux 正确解压。

修复
- 尝试计数：更清晰区分钓鱼、专业采集与纯物体拾取；减少误计。拾取会话与 CHAT_MSG_LOOT 处理收紧。

计划界面
- 待办与周进度：“显示已计划/显示已完成”与浏览页签行为一致；成就与列表的空状态说明更清晰。

聊天
- 尝试计数：可跟随战利品页签、独立 WN_TRYCOUNTER 频道或全部页签；可将频道加入所选聊天标签。可选登录欢迎一行；可隐藏游戏时间刷屏、静默请求 /played。

本地化
- 补全各语言此前缺失的键。

CurseForge：Warband Nexus]=]

L["CHANGELOG_V2510"] = [=[v2.5.10（2026-04-04）

修复
- 提示：黄色「（已计划）」仅在尚未获得坐骑、宠物或玩具时显示。NPC/容器掉落行、产出子行与物品提示会通过收藏夹与玩具 API 判断归属（pcall 与 Midnight 秘密值规则）。数据库中标记为通用「item」的掉落也会同步收藏状态，已获得时不再显示已计划。

CurseForge：Warband Nexus]=]

L["CHANGELOG_V2511"] = [=[v2.5.11 (2026-04-07)

PvE
- 丰裕/丰裕列：每角色缓存；无快照时仅当前角色实时查询（小号显示“—”直到登录）。
- PvE 缓存中每周任务检查添加 Midnight 安全（pcall + 秘密值保护）。
- 丰裕周常标志仅用隐藏任务 86371（不再与破裂拱心石 92600 / 丰裕地窟 81514 混合）。
- 丰裕单元格提示；小号无保存状态时显示 PVE_BOUNTY_NEED_LOGIN。

收藏
- 成就页：通过 GetCategoryNumAchievements(categoryID, true) 枚举全部分类 — 修复仅显示最后获得的成就。
- 更新后全成就一次性重扫（全局 wnAchievementIncludeAllScanV1）。

尝试计数与数据
- 坐骑/宠物已收集判定、遗漏过滤、C_Timer.After 回调修复；CollectibleSourceDB 中 Lucent Hawkstrider 坐骑 ID。

计划 / 界面
- 待办/追踪：尝试次数弹窗仅左键可编辑（卡片上不再右键弹窗）。
- 信息对话框：特别感谢块（贡献者风格）。

本地化
- 致谢/特别感谢字符串；PVE_BOUNTY_NEED_LOGIN。

CurseForge: Warband Nexus]=]

L["CHANGELOG_V2512"] = [=[v2.5.12 (2026-04-12)

界面
- 通知：尝试计数聊天输出下拉菜单向下展开，不再遮盖附近复选框。路由选项固定顺序（拾取页 → Warband Nexus 过滤器 → 所有标准页）。

修复
- 设置、金币管理弹窗、计划界面中 GameTooltip:SetText 使用有效颜色 alpha（修复 Midnight “bad argument #5 to 'SetText'”）。

尝试计数
- 副本入口 [WN-Drops]：完整掉落行 vs 简短提示基于正确坐骑/可追踪逻辑，难度消息匹配仍可掉落。
- 手动掉落与 Rarity 同步：已拥有且非重复的收藏品不再增加尝试计数。

提示与收藏
- 收藏品/掉落提示及相关服务针对 Midnight 秘密值规则收紧；CollectibleSourceDB 与提示对齐当前 API。

本地化
- 各语言补全缺失键；探测聊天使用更短 [WN-TC] 格式。

后续
- 更多 Midnight API 验证；根据团本反馈打磨尝试计数与通知；进一步设置与提示优化。

CurseForge: Warband Nexus]=]

-- Confirm / Tracking Dialog
L["CONFIRM_ACTION"] = "确认操作"
L["CONFIRM"] = "确认"
L["ENABLE_TRACKING_FORMAT"] = "为 |cffffcc00%s|r 启用追踪？"
L["DISABLE_TRACKING_FORMAT"] = "为 |cffffcc00%s|r 禁用追踪？"

-- Reputation Section Headers
L["REP_SECTION_ACCOUNT_WIDE"] = "账号通用声望（%s）"
L["REP_SECTION_CHARACTER_BASED"] = "角色声望（%s）"

-- Reputation Processor Labels
L["REP_REWARD_WAITING"] = "奖励等待中"
L["REP_PARAGON_LABEL"] = "巅峰"

-- Reputation Loading States
L["REP_LOADING_PREPARING"] = "准备中..."
L["REP_LOADING_INITIALIZING"] = "初始化中..."
L["REP_LOADING_FETCHING"] = "正在获取声望数据..."
L["REP_LOADING_PROCESSING"] = "正在处理 %d 个阵营..."
L["REP_LOADING_PROCESSING_COUNT"] = "处理中...（%d/%d）"
L["REP_LOADING_SAVING"] = "正在保存到数据库..."
L["REP_LOADING_COMPLETE"] = "完成！"

-- Status / Footer
L["COMBAT_LOCKDOWN_MSG"] = "战斗中无法打开窗口。战斗结束后请重试。"
L["BANK_IS_ACTIVE"] = "银行已打开"
L["ITEMS_CACHED_FORMAT"] = "已缓存 %d 件物品"

-- Table Headers (SharedWidgets, Professions)
L["TABLE_HEADER_CHARACTER"] = "角色"
L["TABLE_HEADER_LEVEL"] = "等级"
L["TABLE_HEADER_GOLD"] = "金币"
L["TABLE_HEADER_LAST_SEEN"] = "上次登录"

-- Search / Empty States
L["NO_ITEMS_MATCH"] = "没有匹配 '%s' 的物品"
L["NO_ITEMS_MATCH_GENERIC"] = "没有匹配你搜索的物品"
L["ITEMS_SCAN_HINT"] = "物品自动扫描。如无显示请尝试 /reload。"
L["ITEMS_WARBAND_BANK_HINT"] = "打开战团银行以扫描物品（首次访问时自动扫描）"

-- Currency Transfer Steps
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "下一步："
L["CURRENCY_TRANSFER_STEP_1"] = "在货币窗口中找到 |cffffffff%s|r"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800右键点击|r它"
L["CURRENCY_TRANSFER_STEP_3"] = "选择 |cffffffff「转移至战团」|r"
L["CURRENCY_TRANSFER_STEP_4"] = "选择 |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "输入数量：|cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "货币窗口已打开！"
L["CURRENCY_TRANSFER_SECURITY"] = "（暴雪安全机制禁止自动转移）"

-- Plans UI Extra
L["ZONE_PREFIX"] = "区域："
L["ADDED"] = "已添加"
L["WEEKLY_VAULT_TRACKER"] = "每周宝库追踪"
L["DAILY_QUEST_TRACKER"] = "每日任务追踪"
L["CUSTOM_PLAN_STATUS"] = "自定义计划「%s」%s"

-- Achievement Popup
L["ACHIEVEMENT_COMPLETED"] = "已完成"
L["ACHIEVEMENT_NOT_COMPLETED"] = "未完成"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d 点"
L["ADD_PLAN"] = "添加"
L["PLANNED"] = "计划中"

-- PlanCardFactory Vault Slots
L["VAULT_SLOT_WORLD"] = "世界"
L["VAULT_SLOT_SA"] = "指派"

-- PvE Extra
L["AFFIX_TITLE_FALLBACK"] = "词缀"

-- Chat Messages
L["CHAT_REP_STANDING_LABEL"] = "当前"
L["CHAT_GAINED_PREFIX"] = "+"

-- PlansManager Messages
L["PLAN_COMPLETED"] = "计划已完成："
L["WEEKLY_VAULT_PLAN_NAME"] = "每周宝库 - %s"
L["VAULT_PLANS_RESET"] = "每周宏伟宝库计划已重置！（%d 个计划%s）"

-- Reminder System
L["SET_ALERT_TITLE"] = "设置提醒"
L["SET_ALERT"] = "设置提醒"
L["REMOVE_ALERT"] = "移除提醒"
L["ALERT_ACTIVE"] = "提醒已激活"
L["REMINDER_PREFIX"] = "提醒"
L["REMINDER_DAILY_LOGIN"] = "每日登录"
L["REMINDER_WEEKLY_RESET"] = "每周重置"
L["REMINDER_DAYS_BEFORE"] = "重置前 %d 天"
L["REMINDER_ZONE_ENTER"] = "进入 %s"
L["REMINDER_OPT_DAILY"] = "每日登录时提醒"
L["REMINDER_OPT_WEEKLY"] = "每周重置后提醒"
L["REMINDER_OPT_DAYS_BEFORE"] = "重置前 %d 天提醒"
L["REMINDER_OPT_ZONE"] = "进入来源区域时提醒"

-- Empty State Cards
L["EMPTY_CHARACTERS_TITLE"] = "未找到角色"
L["EMPTY_CHARACTERS_DESC"] = "登录你的角色以开始追踪。\n每次登录时自动收集角色数据。"
L["EMPTY_ITEMS_TITLE"] = "无物品缓存"
L["EMPTY_ITEMS_DESC"] = "打开战团银行或个人银行以扫描物品。\n首次访问时自动缓存。"
L["EMPTY_INVENTORY_TITLE"] = "背包无物品"
L["EMPTY_INVENTORY_DESC"] = "你的背包是空的。"
L["EMPTY_PERSONAL_BANK_TITLE"] = "个人银行无物品"
L["EMPTY_PERSONAL_BANK_DESC"] = "打开个人银行以扫描物品。\n首次访问时自动缓存。"
L["EMPTY_WARBAND_BANK_TITLE"] = "战团银行无物品"
L["EMPTY_WARBAND_BANK_DESC"] = "打开战团银行以扫描物品。\n首次访问时自动缓存。"
L["EMPTY_GUILD_BANK_TITLE"] = "公会银行无物品"
L["EMPTY_GUILD_BANK_DESC"] = "打开公会银行以扫描物品。\n首次访问时自动缓存。"
L["NO_SCAN"] = "未扫描"
L["EMPTY_STORAGE_TITLE"] = "无存储数据"
L["EMPTY_STORAGE_DESC"] = "打开银行或背包时扫描物品。\n访问银行以开始追踪存储。"
L["EMPTY_PLANS_TITLE"] = "暂无计划"
L["EMPTY_PLANS_DESC"] = "浏览上方的坐骑、宠物、玩具或成就\n以添加收藏目标并追踪进度。"
L["EMPTY_REPUTATION_TITLE"] = "无声望数据"
L["EMPTY_REPUTATION_DESC"] = "登录时自动扫描声望。\n登录角色以开始追踪阵营声望。"
L["EMPTY_CURRENCY_TITLE"] = "无货币数据"
L["EMPTY_CURRENCY_DESC"] = "货币在所有角色间自动追踪。\n登录角色以开始追踪货币。"
L["EMPTY_PVE_TITLE"] = "无 PvE 数据"
L["EMPTY_PVE_DESC"] = "登录角色时追踪 PvE 进度。\n宏伟宝库、史诗钥石和团队副本锁定将显示在此。"
L["EMPTY_STATISTICS_TITLE"] = "无统计可用"
L["EMPTY_STATISTICS_DESC"] = "统计从你追踪的角色收集。\n登录角色以开始收集数据。"
L["NO_ADDITIONAL_INFO"] = "无附加信息"

-- Character Tracking & Commands
L["TRACK_CHARACTER_QUESTION"] = "要追踪此角色吗？"
L["CLEANUP_NO_INACTIVE"] = "未找到不活跃角色（90+ 天）"
L["CLEANUP_REMOVED_FORMAT"] = "已移除 %d 个不活跃角色"
L["TRACKING_ENABLED_MSG"] = "角色追踪已启用！"
L["TRACKING_DISABLED_MSG"] = "角色追踪已禁用！"
L["TRACKING_DISABLED"] = "追踪已禁用（只读模式）"
L["STATUS_LABEL"] = "状态："
L["ERROR_LABEL"] = "错误："
L["ERROR_NAME_REALM_REQUIRED"] = "需要角色名和服务器"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s 已有活跃的每周计划"

-- Profiles (AceDB)
L["PROFILES"] = "配置"
L["PROFILES_DESC"] = "管理插件配置"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "未找到条件"
L["NO_REQUIREMENTS_INSTANT"] = "无要求（即时完成）"

-- Professions Tab
L["TAB_PROFESSIONS"] = "专业"
L["TAB_COLLECTIONS"] = "收藏"
L["COLLECTIONS_SUBTITLE"] = "坐骑、宠物、玩具与幻化概览"
L["COLLECTIONS_CONTENT_TITLE_ACHIEVEMENTS"] = "成就"
L["COLLECTIONS_CONTENT_SUB_ACHIEVEMENTS"] = "按类别浏览；右侧显示标准和详情。"
L["COLLECTIONS_CONTENT_TITLE_MOUNTS"] = "坐骑"
L["COLLECTIONS_CONTENT_SUB_MOUNTS"] = "按来源分组；右侧预览。"
L["COLLECTIONS_CONTENT_TITLE_PETS"] = "宠物"
L["COLLECTIONS_CONTENT_SUB_PETS"] = "按来源分组；右侧模型预览。"
L["COLLECTIONS_CONTENT_TITLE_TOYS"] = "玩具箱"
L["COLLECTIONS_CONTENT_SUB_TOYS"] = "按来源分组；右侧详情。"
L["COLLECTIONS_CONTENT_TITLE_RECENT"] = "最近获得"
L["COLLECTIONS_CONTENT_SUB_RECENT"] = "每个类别最多10条最新记录，新的在前。"
L["COLLECTIONS_SUBTAB_RECENT"] = "最近"
L["COLLECTIONS_RECENT_TAB_EMPTY"] = "尚无获得记录。新获得的坐骑、宠物、玩具和成就会显示在这里。"
L["COLLECTIONS_RECENT_SECTION_HEAD_FMT"] = "%s — 最近 %d 条"
L["COLLECTIONS_RECENT_SECTION_NONE"] = "暂无。"
L["COLLECTIONS_RECENT_SECTION_ROW"] = "%s · %s"
L["COLLECTIONS_RECENT_SEARCH_EMPTY"] = "没有匹配的条目。"
L["COLLECTIONS_RECENT_HEADER"] = "最新获得"
L["COLLECTIONS_RECENT_EMPTY"] = "你获得的物品会在此显示简短时间标记。"
L["COLLECTIONS_ACQUIRED_LABEL"] = "已记录"
L["COLLECTIONS_ACQUIRED_LINE"] = "%s：%s"
L["COLLECTIONS_RECENT_LINE"] = "%s · %s · %s"
L["COLLECTIONS_RECENT_JUST_NOW"] = "刚刚"
L["COLLECTIONS_RECENT_MINUTES_AGO"] = "%d 分钟前"
L["COLLECTIONS_RECENT_HOURS_AGO"] = "%d 小时前"
L["COLLECTIONS_RECENT_DAYS_AGO"] = "%d 天前"
L["COLLECTIONS_RECENT_SECTION_MOUNTS"] = "最近坐骑"
L["COLLECTIONS_RECENT_SECTION_PETS"] = "最近宠物"
L["COLLECTIONS_RECENT_SECTION_TOYS"] = "最近玩具"
L["COLLECTIONS_RECENT_SECTION_ACHIEVEMENTS"] = "最近成就"
L["COLLECTIONS_RECENT_SECTION_EMPTY"] = "此类别尚无最近获得。"
L["COLLECTIONS_RECENT_SECTION_LINE"] = "%s · %s"
L["COLLECTIONS_COMING_SOON_TITLE"] = "即将推出"
L["COLLECTIONS_COMING_SOON_DESC"] = "收藏概览（坐骑、宠物、玩具、幻化）将在此处提供。"
L["SELECT_MOUNT_FROM_LIST"] = "从列表选择坐骑"
L["SELECT_PET_FROM_LIST"] = "从列表选择宠物"
L["SELECT_TO_SEE_DETAILS"] = "选择 %s 以查看详情。"
L["SOURCE"] = "来源"
L["YOUR_PROFESSIONS"] = "战团专业"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s 个角色有专业"
L["PROFESSIONS_WIDE_TABLE_HINT"] = "提示：使用下方滚动条或 Shift+滚轮查看所有列。"
L["HEADER_PROFESSIONS"] = "专业概览"
L["NO_PROFESSIONS_DATA"] = "暂无专业数据。在每个角色上打开专业窗口（默认 K）以收集数据。"
L["CONCENTRATION"] = "专注"
L["KNOWLEDGE"] = "知识"
L["SKILL"] = "技能"
L["RECIPES"] = "配方"
L["UNSPENT_POINTS"] = "未使用点数"
L["UNSPENT_KNOWLEDGE_TOOLTIP"] = "未使用的知识点"
L["UNSPENT_KNOWLEDGE_COUNT"] = "%d个未使用的知识点"
L["COLLECTIBLE"] = "收藏品"
L["RECHARGE"] = "充能"
L["FULL"] = "已满"
L["PROF_OPEN_RECIPE"] = "打开"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "打开此专业的配方列表"
L["PROF_ONLY_CURRENT_CHAR"] = "仅当前角色可用"
L["NO_PROFESSION"] = "无专业"

-- Professions: Expansion filter
L["PROF_FILTER_EXPANSION"] = "资料片筛选"
L["PROF_FILTER_STRICT_NOTE"] = "仅显示本资料片所有角色的专业数据。"
L["PROF_DATA_SOURCE_NOTE"] = "在各角色打开专业窗口（K）时更新专注、知识与配方。"
L["PROF_FILTER_ALL"] = "全部"
L["PROF_FIRSTCRAFT_OPEN_WINDOW"] = "请先打开专业窗口，然后再次执行此命令。"
L["PROF_FIRSTCRAFT_NO_DATA"] = "无可用专业数据。"
L["PROF_FIRSTCRAFT_HEADER"] = "首次制作奖励配方"
L["PROF_FIRSTCRAFT_NONE"] = "没有剩余首次制作奖励的已学配方。"
L["PROF_FIRSTCRAFT_TOTAL"] = "总计"
L["PROF_FIRSTCRAFT_RECIPES"] = "个配方"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "首次制作"
L["UNIQUES"] = "独特"
L["TREATISE"] = "论文"
L["GATHERING"] = "采集"
L["CATCH_UP"] = "追赶"
L["MOXIE"] = "干劲"
L["COOLDOWNS"] = "冷却"
L["ACCESSORY_1"] = "配件 1"
L["ACCESSORY_2"] = "配件 2"
L["COLUMNS_BUTTON"] = "列"
L["ORDERS"] = "订单"

-- Professions: Tooltips & Details
L["RECIPES_COLUMN_FORMAT"] = "列显示已学 / 总计（总计含未学）"
L["LEARNED_RECIPES"] = "已学配方"
L["UNLEARNED_RECIPES"] = "未学配方"
L["LAST_SCANNED"] = "上次扫描"
L["JUST_NOW"] = "刚刚"
L["RECIPE_NO_DATA"] = "打开专业窗口，收集配方数据"
L["FIRST_CRAFT_AVAILABLE"] = "可用首次制造"
L["FIRST_CRAFT_DESC"] = "首次制造时获得加成经验的配方"
L["SKILLUP_RECIPES"] = "技能提升配方"
L["SKILLUP_DESC"] = "仍可提升技能等级的配方"
L["NO_ACTIVE_COOLDOWNS"] = "无活跃冷却"

-- Professions: Crafting Orders
L["CRAFTING_ORDERS"] = "制造订单"
L["PERSONAL_ORDERS"] = "个人订单"
L["PUBLIC_ORDERS"] = "公共订单"
L["CLAIMS_REMAINING"] = "剩余领取"
L["NO_ACTIVE_ORDERS"] = "无活跃订单"
L["ORDER_NO_DATA"] = "在制造台打开专业以扫描"

-- Professions: Equipment
L["EQUIPMENT"] = "装备"
L["TOOL"] = "工具"
L["ACCESSORY"] = "配件"
L["PROF_EQUIPMENT_HINT"] = "在此角色上打开专业技能(K)以扫描装备。"

-- Professions: Info Window
L["PROF_INFO_TOOLTIP"] = "查看专业详情"
L["PROF_INFO_NO_DATA"] = "无专业数据。\n请登录此角色并打开专业技能窗口(K)以收集数据。"
L["PROF_INFO_SKILLS"] = "资料片技能"
L["PROF_INFO_SPENT"] = "已使用"
L["PROF_INFO_TOOL"] = "工具"
L["PROF_INFO_ACC1"] = "饰品 1"
L["PROF_INFO_ACC2"] = "饰品 2"
L["PROF_INFO_KNOWN"] = "已学"
L["PROF_INFO_WEEKLY"] = "每周知识进度"
L["PROF_INFO_COOLDOWNS"] = "冷却"
L["PROF_INFO_READY"] = "就绪"
L["PROF_INFO_LAST_UPDATE"] = "上次更新"
L["PROF_INFO_UNLOCKED"] = "已解锁"
L["PROF_INFO_LOCKED"] = "已锁定"
L["PROF_INFO_UNLEARNED"] = "未学习"
L["PROF_INFO_NODES"] = "节点"
L["PROF_INFO_RANKS"] = "等级"

-- Track Item DB
L["TRACK_ITEM_DB"] = "追踪物品数据库"
L["TRACK_ITEM_DB_DESC"] = "管理要追踪的收藏品掉落。切换内置条目或添加自定义来源。"
L["MANAGE_ITEMS"] = "物品追踪"
L["SELECT_ITEM"] = "选择物品"
L["SELECT_ITEM_DESC"] = "选择要管理的收藏品。"
L["SELECT_ITEM_HINT"] = "选择上方物品以查看详情。"
L["REPEATABLE_LABEL"] = "可重复"
L["SOURCE_SINGULAR"] = "来源"
L["SOURCE_PLURAL"] = "来源"
L["UNTRACKED"] = "未追踪"
L["CUSTOM_ENTRIES"] = "自定义条目"
L["ADD_CUSTOM_DESC"] = "添加内置数据库中未包含的掉落来源，或移除现有自定义条目。"
L["CURRENT_ENTRIES_LABEL"] = "当前："
L["NO_CUSTOM_ENTRIES"] = "无自定义条目。"
L["ITEM_ID_INPUT"] = "物品 ID"
L["ITEM_ID_INPUT_DESC"] = "输入要追踪的物品 ID。"
L["LOOKUP_ITEM"] = "查询"
L["LOOKUP_ITEM_DESC"] = "从 ID 解析物品名称和类型。"
L["ITEM_LOOKUP_FAILED"] = "未找到物品。"
L["SOURCE_TYPE"] = "来源类型"
L["SOURCE_TYPE_DESC"] = "NPC 或物体。"
L["SOURCE_TYPE_NPC"] = "NPC"
L["SOURCE_TYPE_OBJECT"] = "物体"
L["SOURCE_ID"] = "来源 ID"
L["SOURCE_ID_DESC"] = "NPC ID 或物体 ID。"
L["REPEATABLE_TOGGLE"] = "可重复"
L["REPEATABLE_TOGGLE_DESC"] = "此掉落是否可在每次锁定内多次尝试。"
L["ADD_ENTRY"] = "+ 添加条目"
L["ADD_ENTRY_DESC"] = "添加此自定义掉落条目。"
L["ENTRY_ADDED"] = "自定义条目已添加。"
L["ENTRY_ADD_FAILED"] = "需要物品 ID 和来源 ID。"
L["REMOVE_ENTRY"] = "移除自定义条目"
L["REMOVE_ENTRY_DESC"] = "选择要移除的自定义条目。"
L["REMOVE_BUTTON"] = "- 移除所选"
L["REMOVE_BUTTON_DESC"] = "移除所选的自定义条目。"
L["ENTRY_REMOVED"] = "条目已移除。"
L["NPC"] = "NPC"
L["OBJECT"] = "物体"
L["SOURCE_NAME"] = "来源名称"
L["SOURCE_NAME_DESC"] = "来源的可选显示名称（如NPC或物体）。"
L["STATISTIC_IDS"] = "统计ID"
L["STATISTIC_IDS_DESC"] = "用于击杀/掉落计数的WoW统计ID（逗号分隔，可选）。"
L["MANAGE_BUILTIN"] = "管理内置条目"
L["MANAGE_BUILTIN_DESC"] = "按物品ID搜索和切换内置追踪条目。"
L["SEARCH_BUILTIN"] = "按物品ID搜索内置"
L["SEARCH_BUILTIN_DESC"] = "输入物品ID以在内置数据库中查找来源。"
L["SEARCH_BUTTON"] = "搜索"
L["CURRENTLY_UNTRACKED"] = "当前未追踪"
L["ITEM_RESOLVED"] = "物品已解析：%s（%s）"

-- Plans / Collections (parse labels and UI)
L["ACHIEVEMENT"] = "成就"
L["ADD_ITEMS_TO_PLANS"] = "将物品添加到计划中即可在此查看！"
L["CRITERIA"] = "标准"
L["CUSTOM_PLAN_COMPLETED"] = "自定义计划「%s」|cff00ff00已完成|r"
L["DESCRIPTION"] = "描述"
L["PARSE_AMOUNT"] = "数量"
L["PARSE_LOCATION"] = "位置"
L["SHOWING_X_OF_Y"] = "显示 %d/%d 个结果"
L["SOURCE_UNKNOWN"] = "未知"
L["ZONE_DROP"] = "区域掉落"
L["FISHING"] = "钓鱼"

-- Config (display names)
L["CONFIG_RECIPE_COMPANION"] = "配方助手"
L["CONFIG_RECIPE_COMPANION_DESC"] = "在专业界面旁显示配方助手窗口（按角色显示材料可用性）。"

-- Try Counter
L["TRYCOUNTER_DIFFICULTY_SKIP"] = "已跳过：%s需要%s难度（当前：%s）"
L["TRYCOUNTER_OBTAINED"] = "已获得%s！"
L["TRYCOUNTER_INCREMENT_CHAT"] = "%d 次尝试 · %s"
L["TRYCOUNTER_CHAT_ATTEMPTS_FOR_LINK"] = "%d 次尝试 · %s"
L["TRYCOUNTER_CHAT_FIRST_FOR_LINK"] = "首次尝试 · %s"
L["TRYCOUNTER_CHAT_TAG_CONTAINER"] = "容器"
L["TRYCOUNTER_CHAT_TAG_FISHING"] = "钓鱼"
L["TRYCOUNTER_CHAT_TAG_RESET"] = "计数已重置"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d 次尝试 · %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "获得 %s！尝试计数已重置。"
L["TRYCOUNTER_CAUGHT_RESET"] = "捕获 %s！尝试计数已重置。"
L["TRYCOUNTER_CAUGHT"] = "钓到 %s！"
L["TRYCOUNTER_CONTAINER_RESET"] = "从容器获得 %s！尝试计数已重置。"
L["TRYCOUNTER_CONTAINER"] = "从容器获得 %s！"
L["TRYCOUNTER_AFTER_TRIES"] = "经过 %d 次尝试"
L["TRYCOUNTER_FIRST_TRY"] = "首次尝试就成功了！"
L["TRYCOUNTER_LOCKOUT_SKIP"] = "已跳过：此 NPC 的每日/每周锁定已激活。"
L["TRYCOUNTER_INSTANCE_DROPS"] = "此副本中的收藏品掉落："
L["TRYCOUNTER_INSTANCE_ENTRY_HINT"] = "此副本有适用于你当前难度的尝试计数坐骑。对首领使用目标或鼠标指向后输入 |cffffffff/wn check|r 查看详情。"
L["TRYCOUNTER_INSTANCE_COLLECTIBLE_DETECTED"] = "检测到收藏品： "
L["TRYCOUNTER_INSTANCE_WRONG_DIFF"] = "难度不符：需要 %s（你当前为 %s）。"
L["TRYCOUNTER_INSTANCE_REQUIRES_UNVERIFIED"] = "需要 %s（无法检测当前难度）。"
L["TRYCOUNTER_COLLECTED_TAG"] = "（已收集）"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " 次尝试"
L["TRYCOUNTER_TYPE_MOUNT"] = "坐骑"
L["TRYCOUNTER_TYPE_PET"] = "宠物"
L["TRYCOUNTER_TYPE_TOY"] = "玩具"
L["TRYCOUNTER_TYPE_ITEM"] = "物品"
L["TRYCOUNTER_TRY_COUNTS"] = "尝试次数"
L["TRYCOUNTER_PROBE_ENTER"] = "进入：%s — 难度：%s"
L["TRYCOUNTER_PROBE_DB_HEADER"] = "尝试计数数据库中的坐骑来源 — 你的难度：%s"
L["TRYCOUNTER_PROBE_MOUNT_LINE"] = "%s > %s > %s > %s"
L["TRYCOUNTER_PROBE_ENC_NO_MOUNTS"] = "%s：数据库中无坐骑条目"
L["TRYCOUNTER_PROBE_JOURNAL_MISS"] = "无法解析此副本的地下城手册。"
L["TRYCOUNTER_PROBE_NO_MAPPED_BOSSES"] = "此副本没有与尝试计数数据匹配的首领。"
L["TRYCOUNTER_PROBE_STATUS_COLLECTED"] = "已收藏"
L["TRYCOUNTER_PROBE_STATUS_OBTAINABLE"] = "当前难度可获得"
L["TRYCOUNTER_PROBE_STATUS_WRONG_DIFF"] = "当前难度不可用"
L["TRYCOUNTER_PROBE_STATUS_DIFF_UNKNOWN"] = "难度未知"
L["TRYCOUNTER_PROBE_REQ_ANY"] = "任意难度"
L["TRYCOUNTER_PROBE_REQ_MYTHIC"] = "仅史诗"
L["TRYCOUNTER_PROBE_REQ_LFR"] = "仅随机团队"
L["TRYCOUNTER_PROBE_REQ_NORMAL_PLUS"] = "团队普通及以上（不含随机团队）"
L["TRYCOUNTER_PROBE_REQ_HEROIC"] = "英雄及以上（含史诗与25人英雄）"
L["TRYCOUNTER_PROBE_REQ_25H"] = "仅25人英雄"
L["TRYCOUNTER_PROBE_REQ_10N"] = "仅10人普通"
L["TRYCOUNTER_PROBE_REQ_25N"] = "仅25人普通"
L["TRYCOUNTER_PROBE_REQ_25MAN"] = "25人普通或英雄"

-- Recipe Companion
L["RECIPE_COMPANION_TITLE"] = "配方助手"
L["TOGGLE_TRACKER"] = "切换追踪"
L["SELECT_RECIPE"] = "选择配方"
L["CRAFTERS_SECTION"] = "制造者"
L["TOTAL_REAGENTS"] = "材料总数"

-- Database / Migration
L["DATABASE_UPDATED_MSG"] = "数据库已更新到新版本。"
L["DATABASE_RELOAD_REQUIRED"] = "需要重新加载以应用更改。"
L["MIGRATION_RESET_COMPLETE"] = "重置完成。所有数据将自动重新扫描。"

-- Sync / Loading
L["SYNCING_COMPLETE"] = "同步完成！"
L["SYNCING_LABEL_FORMAT"] = "WN 同步：%s"
L["SETTINGS_UI_UNAVAILABLE"] = "设置界面不可用。尝试 /wn 打开主窗口。"

-- Character Tracking Dialog
L["TRACKED_LABEL"] = "已追踪"
L["TRACKED_DETAILED_LINE1"] = "完整详细数据"
L["TRACKED_DETAILED_LINE2"] = "所有功能已启用"
L["UNTRACKED_LABEL"] = "未追踪"
L["TRACKING_BADGE_TRACKING"] = "追踪中"
L["TRACKING_BADGE_UNTRACKED"] = "未\n追踪"
L["TRACKING_BADGE_BANK"] = "银行\n活跃"
L["UNTRACKED_VIEWONLY_LINE1"] = "只读模式"
L["UNTRACKED_VIEWONLY_LINE2"] = "仅基本信息"
L["TRACKING_ENABLED_CHAT"] = "角色追踪已启用。数据收集将开始。"
L["TRACKING_DISABLED_CHAT"] = "角色追踪已禁用。以只读模式运行。"
L["ADDED_TO_FAVORITES"] = "已添加到收藏："
L["REMOVED_FROM_FAVORITES"] = "已从收藏移除："

-- Tooltip: Collectible Drop Lines
L["TOOLTIP_ATTEMPTS"] = "次尝试"
L["TOOLTIP_100_DROP"] = "100% 掉落"
L["TOOLTIP_UNKNOWN"] = "未知"
L["TOOLTIP_HOLD_SHIFT"] = "  按住 [Shift] 查看完整列表"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - 专注"
L["TOOLTIP_FULL"] = "（已满）"
L["TOOLTIP_NO_LOOT_UNTIL_RESET"] = "下次重置前无战利品"

-- SharedWidgets: UI Labels
L["NO_ITEMS_CACHED_TITLE"] = "无物品缓存"
L["SEARCH_PLACEHOLDER"] = "搜索..."
L["COMBAT_CURRENCY_ERROR"] = "战斗中无法打开货币窗口。战斗结束后重试。"
L["DB_LABEL"] = "数据库："

-- DataService: Loading Stages & Alerts
L["COLLECTING_PVE"] = "正在收集 PvE 数据"
L["PVE_PREPARING"] = "准备中"
L["PVE_GREAT_VAULT"] = "宏伟宝库"
L["PVE_MYTHIC_SCORES"] = "史诗钥石评分"
L["PVE_RAID_LOCKOUTS"] = "团队副本锁定"
L["PVE_INCOMPLETE_DATA"] = "部分数据可能不完整。稍后刷新。"
L["VAULT_SLOTS_TO_FILL"] = "需填充 %d 个宏伟宝库槽位%s"
L["VAULT_SLOT_PLURAL"] = ""
L["REP_RENOWN_NEXT"] = "名望 %d"
L["REP_TO_NEXT_FORMAT"] = "距 %s（%s）还需 %s 声望"
L["REP_FACTION_FALLBACK"] = "阵营"
L["COLLECTION_CANCELLED"] = "用户取消了收集"
L["CLEANUP_STALE_FORMAT"] = "已清理 %d 个过期角色"
L["PERSONAL_BANK"] = "个人银行"
L["WARBAND_BANK_LABEL"] = "战团银行"
L["WARBAND_BANK_TAB_FORMAT"] = "标签页 %d"
L["CURRENCY_OTHER"] = "其他"
L["ERROR_SAVING_CHARACTER"] = "保存角色时出错："

-- DataService: Reputation Standings
L["STANDING_HATED"] = "仇恨"
L["STANDING_HOSTILE"] = "敌对"
L["STANDING_UNFRIENDLY"] = "冷淡"
L["STANDING_NEUTRAL"] = "中立"
L["STANDING_FRIENDLY"] = "友好"
L["STANDING_HONORED"] = "尊敬"
L["STANDING_REVERED"] = "崇敬"
L["STANDING_EXALTED"] = "崇拜"
L["TRYCOUNTER_INCREMENT_CHAT"] = "%d 次尝试 · %s"
L["TRYCOUNTER_CHAT_ATTEMPTS_FOR_LINK"] = "%d 次尝试 · %s"
L["TRYCOUNTER_CHAT_FIRST_FOR_LINK"] = "首次尝试 · %s"
L["TRYCOUNTER_CHAT_TAG_CONTAINER"] = "容器"
L["TRYCOUNTER_CHAT_TAG_FISHING"] = "钓鱼"
L["TRYCOUNTER_CHAT_TAG_RESET"] = "计数已重置"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d 次尝试 · %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "获得 %s！尝试计数已重置。"
L["TRYCOUNTER_CAUGHT_RESET"] = "捕获 %s！尝试计数已重置。"
L["TRYCOUNTER_CAUGHT"] = "钓到 %s！"
L["TRYCOUNTER_CONTAINER_RESET"] = "从容器获得 %s！尝试计数已重置。"
L["TRYCOUNTER_CONTAINER"] = "从容器获得 %s！"
L["TRYCOUNTER_AFTER_TRIES"] = "经过 %d 次尝试"
L["TRYCOUNTER_FIRST_TRY"] = "首次尝试就成功了！"
L["TRYCOUNTER_LOCKOUT_SKIP"] = "已跳过：此 NPC 的每日/每周锁定已激活。"
L["TRYCOUNTER_INSTANCE_DROPS"] = "此副本中的收藏品掉落："
L["TRYCOUNTER_INSTANCE_COLLECTIBLE_DETECTED"] = "检测到收藏品： "
L["TRYCOUNTER_INSTANCE_WRONG_DIFF"] = "难度不符：需要 %s（你当前为 %s）。"
L["TRYCOUNTER_INSTANCE_REQUIRES_UNVERIFIED"] = "需要 %s（无法检测当前难度）。"
L["TRYCOUNTER_COLLECTED_TAG"] = "（已收集）"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " 次尝试"
L["TRYCOUNTER_TYPE_MOUNT"] = "坐骑"
L["TRYCOUNTER_TYPE_PET"] = "宠物"
L["TRYCOUNTER_TYPE_TOY"] = "玩具"
L["TRYCOUNTER_TYPE_ITEM"] = "物品"
L["TRYCOUNTER_TRY_COUNTS"] = "尝试次数"
L["TRYCOUNTER_PROBE_ENTER"] = "进入：%s — 难度：%s"
L["TRYCOUNTER_PROBE_DB_HEADER"] = "尝试计数数据库中的坐骑来源 — 你的难度：%s"
L["TRYCOUNTER_PROBE_MOUNT_LINE"] = "%s > %s > %s > %s"
L["TRYCOUNTER_PROBE_ENC_NO_MOUNTS"] = "%s：数据库中无坐骑条目"
L["TRYCOUNTER_PROBE_JOURNAL_MISS"] = "无法解析此副本的地下城手册。"
L["TRYCOUNTER_PROBE_NO_MAPPED_BOSSES"] = "此副本没有与尝试计数数据匹配的首领。"
L["TRYCOUNTER_PROBE_STATUS_COLLECTED"] = "已收藏"
L["TRYCOUNTER_PROBE_STATUS_OBTAINABLE"] = "当前难度可获得"
L["TRYCOUNTER_PROBE_STATUS_WRONG_DIFF"] = "当前难度不可用"
L["TRYCOUNTER_PROBE_STATUS_DIFF_UNKNOWN"] = "难度未知"
L["TRYCOUNTER_PROBE_REQ_ANY"] = "任意难度"
L["TRYCOUNTER_PROBE_REQ_MYTHIC"] = "仅史诗"
L["TRYCOUNTER_PROBE_REQ_LFR"] = "仅随机团队"
L["TRYCOUNTER_PROBE_REQ_NORMAL_PLUS"] = "团队普通及以上（不含随机团队）"
L["TRYCOUNTER_PROBE_REQ_HEROIC"] = "英雄及以上（含史诗与25人英雄）"
L["TRYCOUNTER_PROBE_REQ_25H"] = "仅25人英雄"
L["TRYCOUNTER_PROBE_REQ_10N"] = "仅10人普通"
L["TRYCOUNTER_PROBE_REQ_25N"] = "仅25人普通"
L["TRYCOUNTER_PROBE_REQ_25MAN"] = "25人普通或英雄"

-- Loading Tracker Labels
L["LT_CHARACTER_DATA"] = "角色数据"
L["LT_CURRENCY_CACHES"] = "货币与缓存"
L["LT_REPUTATIONS"] = "声望"
L["LT_PROFESSIONS"] = "专业"
L["LT_PVE_DATA"] = "PvE 数据"
L["LT_COLLECTIONS"] = "收藏"
L["LT_COLLECTION_DATA"] = "收藏数据"
L["LT_COLLECTION_SCAN"] = "收藏扫描"

-- Collections tab (loading & filters)
L["LOADING_COLLECTIONS"] = "正在加载收藏..."
L["SYNC_COMPLETE"] = "已同步"
L["FILTER_COLLECTED"] = "已收藏"
L["FILTER_UNCOLLECTED"] = "未收藏"
L["FILTER_SHOW_OWNED"] = "已拥有"
L["FILTER_SHOW_MISSING"] = "未拥有"

-- Config: Settings Panel
L["CONFIG_HEADER"] = "Warband Nexus"
L["CONFIG_HEADER_DESC"] = "现代战团管理和跨角色追踪。"
L["CONFIG_GENERAL"] = "常规设置"
L["CONFIG_GENERAL_DESC"] = "基本插件设置和行为选项。"
L["CONFIG_ENABLE"] = "启用插件"
L["CONFIG_ENABLE_DESC"] = "开启或关闭插件。"
L["CONFIG_MINIMAP"] = "小地图按钮"
L["CONFIG_MINIMAP_DESC"] = "在小地图上显示按钮以便快速访问。"
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "在提示中显示物品"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "在物品提示中显示战团和角色物品数量。"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN"] = "登录时请求游戏时间"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN_DESC"] = "开启时在后台请求 /played 以更新“游玩最多”等统计，并隐藏聊天输出。关闭则登录时不自动请求（仍可手动 /played）。"
L["CONFIG_MODULES"] = "模块管理"
L["CONFIG_MODULES_DESC"] = "启用或禁用各个插件模块。禁用的模块将不收集数据或显示界面标签页。"
L["CONFIG_MOD_CURRENCIES"] = "货币"
L["CONFIG_MOD_CURRENCIES_DESC"] = "追踪所有角色的货币。"
L["CONFIG_MOD_REPUTATIONS"] = "声望"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "追踪所有角色的声望。"
L["CONFIG_MOD_ITEMS"] = "物品"
L["CONFIG_MOD_ITEMS_DESC"] = "追踪背包和银行中的物品。"
L["CONFIG_MOD_STORAGE"] = "存储"
L["CONFIG_MOD_STORAGE_DESC"] = "存储标签页，用于背包和银行管理。"
L["CONFIG_MOD_PVE"] = "PvE"
L["CONFIG_MOD_PVE_DESC"] = "追踪宏伟宝库、史诗钥石和团队副本锁定。"
L["CONFIG_MOD_PLANS"] = "待办"
L["CONFIG_MOD_PLANS_DESC"] = "每周任务追踪、收藏目标和宝库进度。"
L["CONFIG_MOD_PROFESSIONS"] = "专业"
L["CONFIG_MOD_PROFESSIONS_DESC"] = "追踪专业技能、配方和专注。"
L["CONFIG_AUTOMATION"] = "自动化"
L["CONFIG_AUTOMATION_DESC"] = "控制打开战团银行时自动执行的操作。"
L["CONFIG_AUTO_OPTIMIZE"] = "自动优化数据库"
L["CONFIG_AUTO_OPTIMIZE_DESC"] = "登录时自动优化数据库以保持存储效率。"
L["CONFIG_SHOW_ITEM_COUNT"] = "显示物品数量"
L["CONFIG_SHOW_ITEM_COUNT_DESC"] = "显示物品数量提示，展示你在所有角色中拥有的每种物品数量。"
L["CONFIG_THEME_COLOR"] = "主主题色"
L["CONFIG_THEME_COLOR_DESC"] = "选择插件界面的主强调色。"
L["CONFIG_THEME_PRESETS"] = "主题预设"
L["CONFIG_THEME_APPLIED"] = "%s 主题已应用！"
L["CONFIG_THEME_RESET_DESC"] = "将所有主题色重置为默认紫色主题。"
L["CONFIG_NOTIFICATIONS"] = "通知"
L["CONFIG_NOTIFICATIONS_DESC"] = "配置显示哪些通知。"
L["CONFIG_ENABLE_NOTIFICATIONS"] = "启用通知"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "显示收藏品事件弹窗通知。"
L["CONFIG_NOTIFY_MOUNTS"] = "坐骑通知"
L["CONFIG_NOTIFY_MOUNTS_DESC"] = "学习新坐骑时显示通知。"
L["CONFIG_NOTIFY_PETS"] = "宠物通知"
L["CONFIG_NOTIFY_PETS_DESC"] = "学习新宠物时显示通知。"
L["CONFIG_NOTIFY_TOYS"] = "玩具通知"
L["CONFIG_NOTIFY_TOYS_DESC"] = "学习新玩具时显示通知。"
L["CONFIG_NOTIFY_ACHIEVEMENTS"] = "成就通知"
L["CONFIG_NOTIFY_ACHIEVEMENTS_DESC"] = "获得成就时显示通知。"
L["CONFIG_SHOW_UPDATE_NOTES"] = "再次显示更新说明"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "下次登录时显示「更新内容」窗口。"
L["CONFIG_UPDATE_NOTES_SHOWN"] = "更新通知将在下次登录时显示。"
L["CONFIG_RESET_PLANS"] = "重置已完成计划"
L["CONFIG_RESET_PLANS_CONFIRM"] = "将移除所有已完成计划。继续？"
L["CONFIG_RESET_PLANS_FORMAT"] = "已移除 %d 个已完成计划。"
L["CONFIG_NO_COMPLETED_PLANS"] = "无已完成计划可移除。"
L["CONFIG_TAB_FILTERING"] = "标签页筛选"
L["CONFIG_TAB_FILTERING_DESC"] = "选择主窗口中可见的标签页。"
L["CONFIG_CHARACTER_MGMT"] = "角色管理"
L["CONFIG_CHARACTER_MGMT_DESC"] = "管理追踪的角色并移除旧数据。"
L["CONFIG_DELETE_CHAR"] = "删除角色数据"
L["CONFIG_DELETE_CHAR_DESC"] = "永久移除所选角色的所有存储数据。"
L["CONFIG_DELETE_CONFIRM"] = "确定要永久删除此角色的所有数据？此操作无法撤销。"
L["CONFIG_DELETE_SUCCESS"] = "角色数据已删除："
L["CONFIG_DELETE_FAILED"] = "未找到角色数据。"
L["CONFIG_FONT_SCALING"] = "字体与缩放"
L["CONFIG_FONT_SCALING_DESC"] = "调整字体和大小缩放。"
L["CONFIG_FONT_FAMILY"] = "字体"
L["CONFIG_FONT_SIZE"] = "字体大小缩放"
L["CONFIG_FONT_PREVIEW"] = "预览：The quick brown fox jumps over the lazy dog"
L["CONFIG_ADVANCED"] = "高级"
L["CONFIG_ADVANCED_DESC"] = "高级设置和数据库管理。请谨慎使用！"
L["CONFIG_DEBUG_MODE"] = "调试模式"
L["CONFIG_DEBUG_MODE_DESC"] = "启用详细日志以便调试。仅在排查问题时启用。"
L["CONFIG_DEBUG_VERBOSE"] = "详细调试（缓存/扫描/提示日志）"
L["CONFIG_DEBUG_VERBOSE_DESC"] = "调试模式下同时显示货币/声望缓存、背包扫描、提示与专业日志。关闭可减少聊天刷屏。"
L["CONFIG_DB_STATS"] = "显示数据库统计"
L["CONFIG_DB_STATS_DESC"] = "显示当前数据库大小和优化统计。"
L["CONFIG_DB_OPTIMIZER_NA"] = "数据库优化器未加载"
L["CONFIG_OPTIMIZE_NOW"] = "立即优化数据库"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "运行数据库优化器以清理和压缩存储的数据。"
L["CONFIG_COMMANDS_HEADER"] = "斜杠命令"

-- Sorting
L["SORT_BY_LABEL"] = "排序："
L["SORT_MODE_DEFAULT"] = "默认顺序"
L["SORT_MODE_MANUAL"] = "手动（自定义顺序）"
L["SORT_MODE_NAME"] = "名称（A-Z）"
L["SORT_MODE_LEVEL"] = "等级（最高）"
L["SORT_MODE_ILVL"] = "装等（最高）"
L["SORT_MODE_GOLD"] = "金币（最高）"

-- Gold Management
L["GOLD_MANAGER_BTN"] = "金币目标"
L["GOLD_MANAGEMENT_TITLE"] = "金币目标"
L["GOLD_MANAGEMENT_DESC"] = "配置自动金币管理。使用 C_Bank API 在银行打开时自动执行存入和取款。"
L["GOLD_MANAGEMENT_WARNING"] = "|cff44ff44完全自动：|r 银行打开时自动执行金币存入和取款。设置目标数量，让插件管理你的金币！"
L["GOLD_MANAGEMENT_ENABLE"] = "启用金币管理"
L["GOLD_MANAGEMENT_MODE"] = "管理模式"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "仅存入"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "金币超过 X 时，超额自动存入战团银行。"
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "仅取款"
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "金币少于 X 时，差额自动从战团银行取款。"
L["GOLD_MANAGEMENT_MODE_BOTH"] = "两者"
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "自动维持角色金币恰好为 X（多则存，少则取）。"
L["GOLD_MANAGEMENT_TARGET"] = "目标金币数量"
L["GOLD_MANAGEMENT_GOLD_LABEL"] = "金币"
L["GOLD_MANAGEMENT_HELPER"] = "输入你想在此角色上保留的金币数量。打开银行时插件将自动管理你的金币。"
L["GOLD_MANAGEMENT_CHAR_ONLY"] = "仅此角色 (%s)"
L["GOLD_MANAGEMENT_CHAR_ONLY_DESC"] = "仅为此角色使用单独的金币管理设置。其他角色将使用共享配置。"
L["GOLD_MGMT_PROFILE_TITLE"] = "配置（所有角色）"
L["GOLD_MGMT_TARGET_LABEL"] = "目标"
L["GOLD_MGMT_USING_PROFILE"] = "使用配置"
L["GOLD_MGMT_MODE_SHORT_DEPOSIT"] = "存入"
L["GOLD_MGMT_MODE_SHORT_WITHDRAW"] = "取出"
L["GOLD_MGMT_MODE_SHORT_BOTH"] = "双向"
L["GOLD_MGMT_ACTIVE"] = "激活"
L["ENABLED"] = "已启用"
L["DISABLED"] = "已禁用"
L["GOLD_MANAGEMENT_NOTIFICATION_DEPOSIT"] = "存入 %s 至战团银行（你有 %s）"
L["GOLD_MANAGEMENT_NOTIFICATION_WITHDRAW"] = "从战团银行取款 %s（你有 %s）"
L["GOLD_MANAGEMENT_DEPOSITED"] = "已存入 %s 至战团银行"
L["GOLD_MANAGEMENT_WITHDRAWN"] = "已从战团银行取款 %s"
L["MONEY_LOGS_BTN"] = "金币记录"
L["MONEY_LOGS_TITLE"] = "金币记录"
L["MONEY_LOGS_SUMMARY_TITLE"] = "角色贡献"
L["MONEY_LOGS_COLUMN_NET"] = "净额"
L["MONEY_LOGS_COLUMN_TIME"] = "时间"
L["MONEY_LOGS_COLUMN_CHARACTER"] = "角色"
L["MONEY_LOGS_COLUMN_TYPE"] = "类型"
L["MONEY_LOGS_COLUMN_TOFROM"] = "来源/去向"
L["MONEY_LOGS_COLUMN_AMOUNT"] = "金额"
L["MONEY_LOGS_EMPTY"] = "暂无金币交易记录。"
L["MONEY_LOGS_DEPOSIT"] = "存入"
L["MONEY_LOGS_WITHDRAW"] = "取出"
L["MONEY_LOGS_TO_WARBAND_BANK"] = "战团银行"
L["MONEY_LOGS_FROM_WARBAND_BANK"] = "从战团银行"
L["MONEY_LOGS_RESET"] = "重置"
L["MONEY_LOGS_FILTER_ALL"] = "全部"
L["MONEY_LOGS_CHAT_DEPOSIT"] = "|cff00ff00金币记录:|r 向战团银行存入 %s"
L["MONEY_LOGS_CHAT_WITHDRAW"] = "|cffff9900金币记录:|r 从战团银行取出 %s"

-- Minimap Tooltip
L["MINIMAP_MORE_FORMAT"] = "... +%d更多"

-- Gear UI
L["GEAR_UPGRADE_CURRENCIES"] = "升级货币"
L["GEAR_CHARACTER_STATS"] = "角色属性"
L["GEAR_NO_ITEM_EQUIPPED"] = "此栏位未装备物品。"
L["GEAR_NO_PREVIEW"] = "无预览"
L["GEAR_STATS_CURRENT_ONLY"] = "属性仅对\n当前角色可用"
L["GEAR_SLOT_RING1"] = "戒指 1"
L["GEAR_SLOT_RING2"] = "戒指 2"
L["GEAR_SLOT_TRINKET1"] = "饰品 1"
L["GEAR_SLOT_TRINKET2"] = "饰品 2"
L["GEAR_UPGRADE_AVAILABLE_FORMAT"] = "可升级至 %s %d/%d%s"
L["GEAR_UPGRADES_WITH_CURRENCY_FORMAT"] = "当前货币可升级 %d次"
L["GEAR_CRESTS_GOLD_ONLY"] = "所需纹章：0（仅需金币 — 此前已达成）"
L["GEAR_UPGRADES_GOLD_ONLY_FORMAT"] = "%d次仅需金币升级（此前已达成）"
L["GEAR_NEED_MORE_CRESTS_FORMAT"] = "%s %d/%d — 需要更多纹章"
L["GEAR_CRAFTED_RECRAFT_RANGE"] = "再造范围：%d-%d（%s 黎明纹章）"
L["GEAR_CRAFTED_CREST_COST"] = "再造消耗：%d 纹章"
L["GEAR_CRAFTED_NO_CRESTS"] = "没有可用于再造的纹章"
L["GEAR_TAB_TITLE"] = "装备管理"
L["GEAR_TAB_DESC"] = "已装备、升级选项及跨角色升级候选"
L["GEAR_SECTION_EQUIPPED"] = "已装备"
L["GEAR_SECTION_RESOURCES"] = "资源"
L["GEAR_SECTION_UPGRADES"] = "升级机会"
L["GEAR_SECTION_STORAGE"] = "存储升级"
L["GEAR_SECTION_LIST"] = "所有已装备物品"
L["GEAR_UPGRADEABLE_SLOTS"] = "部位可升级"
L["GEAR_NO_UPGRADES_AVAILABLE"] = "当前资源下无可用升级"
L["GEAR_NO_UPGRADE_ITEMS"] = "无可用升级 - 所有装备已达最高等级或不支持。"
L["GEAR_UPGRADE_CURRENT_CHAR_ONLY"] = "升级信息仅对当前角色可用。"
L["GEAR_NO_STORAGE_FINDS"] = "未找到存储升级。打开银行标签页以获得更好结果。"
L["GEAR_NO_CURRENCY_DATA"] = "尚无货币数据"
L["GEAR_SEARCH_PLACEHOLDER"] = "搜索已装备物品..."
L["GEAR_NO_ITEMS_FOUND"] = "未找到匹配的已装备物品"
L["GEAR_STORAGE_BEST"] = "最佳"
L["GEAR_STORAGE_WARBOUND"] = "战团绑定"
L["GEAR_STORAGE_BOE"] = "装绑"
L["GEAR_STORAGE_UPGRADE_LINE"] = "%d → %d"
L["GEAR_STORAGE_TITLE"] = "存储升级推荐"
L["GEAR_STORAGE_DESC"] = "各部位最佳装绑 / 战团绑定升级"
L["GEAR_STORAGE_EMPTY"] = "未找到适合该角色的更好装绑 / 战团绑定升级。"

-- Characters UI
L["WOW_TOKEN_LABEL"] = "WOW代币"

-- SharedWidgets
L["FILTER_LABEL"] = FILTER or "筛选"

-- Statistics UI
L["FORMAT_BUTTON"] = "格式"

-- Professions UI
L["SHOW_ALL"] = "显示全部"

-- Social
L["DISCORD_TOOLTIP"] = "Warband Nexus Discord"

-- Collection Source Filters
L["SOURCE_OTHER"] = "其他"

-- Expansion / Content Names
L["CONTENT_KHAZ_ALGAR"] = "卡兹阿加"
L["CONTENT_DRAGON_ISLES"] = "巨龙群岛"

-- Module Disabled
L["MODULE_DISABLED_DESC_FORMAT"] = "在%s中启用以使用%s。"

-- Plans UI (extended)
L["PART_OF_FORMAT"] = "属于：%s"
L["LOCKED_WORLD_QUESTS"] = "已锁定 — 完成世界任务以解锁"
L["QUEST_ID_FORMAT"] = "任务ID：%s"

-- Stats
L["STAT_STRENGTH"] = SPELL_STAT1_NAME or "力量"
L["STAT_AGILITY"] = SPELL_STAT2_NAME or "敏捷"
L["STAT_STAMINA"] = SPELL_STAT3_NAME or "耐力"
L["STAT_INTELLECT"] = SPELL_STAT4_NAME or "智力"
L["STAT_CRITICAL_STRIKE"] = STAT_CRITICAL_STRIKE or "爆击"
L["STAT_HASTE"] = STAT_HASTE or "急速"
L["STAT_MASTERY"] = STAT_MASTERY or "精通"
L["STAT_VERSATILITY"] = STAT_VERSATILITY or "全能"

L["TRACK_ACTIVITIES"] = "追踪活动"

-- =============================================
-- Blizzard GlobalStrings (Auto-localized by WoW)
-- =============================================
L["BANK_LABEL"] = BANK or "银行"
L["BTN_CLOSE"] = CLOSE
L["BTN_REFRESH"] = REFRESH
L["BTN_SETTINGS"] = SETTINGS
L["CANCEL"] = CANCEL or "取消"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "成就"
L["ACHIEVEMENT_SERIES"] = "成就系列"
L["CHILDREN_ACHIEVEMENTS"] = "后续成就"
L["LOADING_ACHIEVEMENTS"] = "加载成就中..."
L["PARENT_ACHIEVEMENT"] = "前置成就"
L["CATEGORY_ALL"] = ALL or "全部"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "消耗品"
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "装备"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "杂项"
L["CATEGORY_MOUNTS"] = MOUNTS or "坐骑"
L["CATEGORY_PETS"] = PETS or "宠物"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "任务物品"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "材料"
L["CATEGORY_TITLES"] = TITLES or "头衔"
L["CATEGORY_TOYS"] = TOY_BOX or "玩具"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "商品"
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "幻化"
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. "货币..."
L["DELETE"] = DELETE or "删除"
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "英雄"
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "史诗"
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "普通"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "地下城"
L["ENABLE"] = ENABLE or "启用"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "未知"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "消耗品"
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "装备"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "杂项"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "专业技能"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "任务"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "材料"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "商品"
L["HEADER_CHARACTERS"] = CHARACTER or "角色"
L["HEADER_FAVORITES"] = FAVORITES or "收藏"
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "公会银行"
L["ITEMS_PLAYER_BANK"] = BANK or "个人银行"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. "物品..."
L["NONE_LABEL"] = NONE or "无"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "通知"
L["OK_BUTTON"] = OKAY or "确定"
L["PARSE_ARENA"] = ARENA or "竞技场"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "掉落"
L["PARSE_DUNGEON"] = DUNGEONS or "地下城"
L["PARSE_FACTION"] = FACTION or "阵营"
L["PARSE_RAID"] = RAID or "团队副本"
L["PARSE_REPUTATION"] = REPUTATION or "声望"
L["PARSE_ZONE"] = ZONE or "区域"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "地下城"
L["PVE_HEADER_RAIDS"] = RAIDS or "团队副本"
L["PVP_TYPE"] = PVP or "PvP"
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC
L["RAIDS_LABEL"] = RAIDS or "团队副本"
L["RAID_CAT"] = RAID or "团队副本"
L["RELOAD_UI_BUTTON"] = RELOADUI or "重载界面"
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. "声望..."
L["RESET_LABEL"] = RESET or "重置"
L["SLOT_BACK"] = INVTYPE_CLOAK or "背部"
L["SLOT_CHEST"] = INVTYPE_CHEST or "胸部"
L["SLOT_FEET"] = INVTYPE_FEET or "脚部"
L["SLOT_HANDS"] = INVTYPE_HAND or "手部"
L["SLOT_HEAD"] = INVTYPE_HEAD or "头部"
L["SLOT_LEGS"] = INVTYPE_LEGS or "腿部"
L["SLOT_MAINHAND"] = INVTYPE_WEAPONMAINHAND or "主手"
L["SLOT_OFFHAND"] = INVTYPE_WEAPONOFFHAND or "副手"
L["SLOT_SHIRT"] = INVTYPE_BODY or "衬衫"
L["SLOT_SHOULDER"] = INVTYPE_SHOULDER or "肩部"
L["SLOT_TABARD"] = INVTYPE_TABARD or "战袍"
L["SLOT_WAIST"] = INVTYPE_WAIST or "腰部"
L["SLOT_WRIST"] = INVTYPE_WRIST or "手腕"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "成就"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "制造"
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "掉落"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "游戏内商店"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "宠物对战"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "专业"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "推广活动"
L["SOURCE_TYPE_PVP"] = PVP or "PvP"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "任务"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "集换式卡牌"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "未知"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "商人"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "世界事件"
L["STATS_HEADER"] = STATISTICS or "统计"
L["TAB_CHARACTERS"] = CHARACTER or "角色"
L["TAB_CURRENCY"] = CURRENCY or "货币"
L["TAB_ITEMS"] = ITEMS or "物品"
L["TAB_GEAR"] = "装备"
L["TAB_REPUTATION"] = REPUTATION or "声望"
L["TAB_STATISTICS"] = STATISTICS or "统计"
L["TOOLTIP_CHARACTER"] = CHARACTER or "角色"
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "位置"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "成就"
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "首领掉落"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "专业"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "任务"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "商人"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "世界掉落"
L["TYPE_MOUNT"] = MOUNT or "坐骑"
L["TYPE_PET"] = PET or "宠物"
L["TYPE_TOY"] = TOY or "玩具"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "幻化"
L["VAULT_DUNGEON"] = LFG_TYPE_DUNGEON or "地下城"
L["VAULT_RAID"] = RAID or "团队副本"
L["VAULT_SLOT_DUNGEON"] = DUNGEONS or "地下城"
L["VAULT_SLOT_RAIDS"] = RAIDS or "团队副本"
-- 4.12 New Add
L["FIRSTCRAFT"] = PROFESSIONS_FIRST_CRAFT or "首次制造"

-- v2.5.9b (CHANGELOG_V259b)
L["CHANGELOG_V259b"] = [=[v2.5.9b（2026-04-04）

改进
- 提示：NPC 单位提示上的收藏品掉落信息仅在目标为敌对或可攻击时显示（修复友好 delve 石等上出现错误坐骑行的问题）。对 UnitCanAttack、UnitIsDead、UnitReaction 做安全检测（Midnight 秘密值规则）。
- 打包：发行 ZIP 由 build_addon.py（Python 3.8+）生成；归档内路径使用 /，便于 Linux、macOS 与 CurseForge Linux 正确解压。

修复
- 尝试计数：更清晰区分钓鱼、专业采集与纯物体拾取；减少误计。拾取会话与 CHAT_MSG_LOOT 处理收紧。

计划界面
- 待办与周进度：“显示已计划/显示已完成”与浏览页签行为一致；成就与列表的空状态说明更清晰。

聊天
- 尝试计数：可跟随战利品页签、独立 WN_TRYCOUNTER 频道或全部页签；可将频道加入所选聊天标签。可选登录欢迎一行；可隐藏游戏时间刷屏、静默请求 /played。

本地化
- 补全各语言此前缺失的键。

CurseForge：Warband Nexus]=]

-- v2.5.10 (CHANGELOG_V2510)
L["CHANGELOG_V2510"] = [=[v2.5.10（2026-04-04）

修复
- 提示：黄色「（已计划）」仅在尚未获得坐骑、宠物或玩具时显示。NPC/容器掉落行、产出子行与物品提示会通过收藏夹与玩具 API 判断归属（pcall 与 Midnight 秘密值规则）。数据库中标记为通用「item」的掉落也会同步收藏状态，已获得时不再显示已计划。

CurseForge：Warband Nexus]=]

-- v2.5.11 (CHANGELOG_V2511) — English notes; see enUS for detail
L["CHANGELOG_V2511"] = [=[v2.5.11 (2026-04-07)

PvE
- Trovehunter's Bounty / Bountiful column: per-character cache for each header row; live quest API only for the current character when no snapshot exists (alts show "—" until logged in).
- Midnight-safe weekly quest checks (pcall + secret guards) in PvE cache.
- Trovehunter weekly flag uses hidden quest 86371 only (removed OR with Cracked Keystone 92600 / Bountiful Delves 81514 so the column is not falsely "done").
- Bountiful cell tooltip; PVE_BOUNTY_NEED_LOGIN when an alt has no saved status yet.

Collections
- Achievements tab: full category enumeration via GetCategoryNumAchievements(categoryID, true) — fixes the list showing only the last earned achievement.
- One-time full achievement re-scan after this update (global wnAchievementIncludeAllScanV1).

Try Counter & data
- Mount/pet collected handling, missed-drop filtering, C_Timer.After callback fix; Lucent Hawkstrider mount ID in CollectibleSourceDB.

Plans / UI
- To-Do / tracker: try-count popup can be left-click only (no right-click popup on cards).
- Information dialog: Special Thanks block (Contributors-style).

Localization
- Credits / Special Thanks strings updated across locales; PVE_BOUNTY_NEED_LOGIN (enUS).

CurseForge: Warband Nexus]=]

-- v2.5.12 (CHANGELOG_V2512) — English notes; see enUS for detail
L["CHANGELOG_V2512"] = [=[v2.5.12 (2026-04-12)

UI
- Notifications: Try counter chat output dropdown opens downward with extra spacing so the open list no longer overlaps the section label or nearby checkboxes. Route options keep a fixed order (Loot tabs → Warband Nexus filter → all standard tabs).

Bug fixes
- GameTooltip:SetText in Settings, Gold Management popup, and Plans UI uses valid color alpha for Midnight clients (fixes "bad argument #5 to 'SetText'").

Try Counter
- Instance entry [WN-Drops]: full drop lines vs the short hint now use the correct mount/trackable logic so difficulty messaging matches what can still drop.
- Manual drops and Rarity sync: non-repeatable collectibles you already own no longer inflate or advance try counts.

Tooltips & collections
- Collectible/drop hints and related services tightened for Midnight secret-value rules; CollectibleSourceDB and tooltip wiring aligned with current APIs.

Localization
- Missing keys brought in line with enUS across locales; probe chat uses a shorter [WN-TC] line format.

后续计划
- More Midnight API validation; Try Counter and notifications tuned from live raids and dungeons; further settings and tooltip polish.

CurseForge: Warband Nexus]=]
L["SHOW_COMPLETED_HELP"] = "待办与周进度：未勾选=仍进行中的计划；勾选=仅已完成的计划。浏览标签：未勾选=未收藏（开启“显示已计划”时仅限列表内）；勾选=列表上已收藏的条目（“显示已计划”仍会限制列表）。"
L["SHOW_PLANNED_HELP"] = "仅浏览标签（在待办与周进度中隐藏）：勾选=仅显示你加入待办的目标。“显示已完成”关=仍缺的；开=已完成的；两项都开=该分类全部已计划；两项都关=完整未收藏浏览。"
L["PLANS_ACHIEVEMENTS_EMPTY_TITLE"] = "没有可显示的成就"
L["PLANS_ACHIEVEMENTS_EMPTY_HINT"] = "从此列表将成就加入待办，或更改“显示已计划/显示已完成”。列表随扫描填充；若为空可尝试 /reload。"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_TITLE"] = "没有可显示的内容"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_DESC"] = "当前筛选下没有匹配的已计划条目。请加入待办或调整“显示已计划/显示已完成”。"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_TITLE"] = "没有已完成的待办条目"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_DESC"] = "该分类中待办尚无已收藏或已完成项。关闭“显示已完成”可查看进行中的条目。"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_TITLE"] = "没有进行中的待办条目"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_DESC"] = "该分类待办中已没有未收藏项。开启“显示已完成”查看已完成项，或从本页添加目标。"
L["TRYCOUNTER_CHAT_ROUTE_LABEL"] = "尝试计数聊天输出"
L["TRYCOUNTER_CHAT_ROUTE_DESC"] = "尝试计数的行输出位置。默认与“拾取”相同标签页。“Warband Nexus”使用 WN_TRYCOUNTER 分组（可在聊天标签设置中选择）。“所有标签”发送到每个编号聊天窗口。"
L["TRYCOUNTER_CHAT_ROUTE_LOOT"] = "1）与拾取相同（默认）"
L["TRYCOUNTER_CHAT_ROUTE_DEDICATED"] = "2）Warband Nexus（独立过滤）"
L["TRYCOUNTER_CHAT_ROUTE_ALL_TABS"] = "3）所有标准聊天标签"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_BTN"] = "将尝试计数添加到所选聊天标签"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_TOOLTIP"] = "先点击目标聊天标签，再点此处。适合“Warband Nexus”模式。会向该标签添加 WN_TRYCOUNTER。"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_OK"] = "|cff9966ff[Warband Nexus]|r 已在所选聊天标签启用尝试计数。"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_FAIL"] = "|cffff6600[Warband Nexus]|r 无法更新聊天标签（无聊天框或 API 被阻止）。"
L["WELCOME_NEW_VERSION_CHAT"] = "|cffffff00更新内容：|r 可能会在聊天上方弹出窗口，或输入 |cffffff00/wn changelog|r。"
L["CONFIG_SHOW_LOGIN_CHAT"] = "在聊天中显示登录提示"
L["CONFIG_SHOW_LOGIN_CHAT_DESC"] = "开启通知时打印一行简短欢迎语。使用“系统”消息组与可见聊天标签（如 Chattynator）。更新说明窗口为独立全屏弹窗。"
L["CONFIG_HIDE_PLAYED_TIME_CHAT"] = "在聊天中隐藏游戏时间"
L["CONFIG_HIDE_PLAYED_TIME_CHAT_DESC"] = "过滤“总游戏时间”和“本等级游戏时间”等系统消息。关闭本项可再次显示（包括 /played）。"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN"] = "登录时请求游戏时间"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN_DESC"] = "开启时在后台请求 /played 以更新“游玩最多”等统计，并隐藏聊天输出。关闭则登录时不自动请求（仍可手动 /played）。"
L["PROFESSIONS_WIDE_TABLE_HINT"] = "提示：使用下方滚动条或 Shift+滚轮查看所有列。"

-- Keybinding globals (must be global for WoW's keybinding UI)
BINDING_HEADER_WARBANDNEXUS = "Warband Nexus"
BINDING_NAME_WARBANDNEXUS_TOGGLE = "显示/隐藏主窗口"
