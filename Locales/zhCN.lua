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
-- Slash Commands
L["KEYBINDING"] = "快捷键"
L["KEYBINDING_UNBOUND"] = "未设置"
L["KEYBINDING_PRESS_KEY"] = "请按一个键..."
L["KEYBINDING_TOOLTIP"] = "点击设置快捷键以切换 Warband Nexus。\n按 ESC 取消。"
L["KEYBINDING_CLEAR"] = "清除快捷键"
L["KEYBINDING_SAVED"] = "快捷键已保存。"
L["KEYBINDING_COMBAT"] = "战斗中无法更改快捷键。"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "常规设置"
L["DEBUG_MODE"] = "调试日志"
L["DEBUG_MODE_DESC"] = "在聊天框输出详细调试信息以便排查问题"
L["DEBUG_TRYCOUNTER_LOOT"] = "尝试计数战利品调试"
L["DEBUG_TRYCOUNTER_LOOT_DESC"] = "仅记录战利品流程（LOOT_OPENED、来源解析、区域回退）。声望/货币缓存日志已抑制。"

-- Options Panel - Scanning

-- Options Panel - Deposit

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "显示"
L["DISPLAY_SETTINGS_DESC"] = "自定义物品和信息的显示方式。"
L["SHOW_ITEM_COUNT"] = "显示物品数量"

-- Options Panel - Tabs

-- Scanner Module

-- Banker Module

-- Warband Bank Operations

-- UI Module
L["SEARCH_CATEGORY_FORMAT"] = "搜索 %s..."

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
-- Items Tab
L["ITEMS_HEADER"] = "银行物品"
L["ITEMS_WARBAND_BANK"] = "战团银行"

-- Storage Tab
L["STORAGE_HEADER"] = "存储浏览器"
L["STORAGE_HEADER_DESC"] = "按类型浏览所有物品"
L["STORAGE_WARBAND_BANK"] = "战团银行"

-- Plans Tab
L["COLLECTION_PLANS"] = "待办清单"
L["SEARCH_PLANS"] = "搜索计划..."
L["SHOW_COMPLETED"] = "显示已完成"
L["SHOW_COMPLETED_HELP"] = "待办与周进度：未勾选=仍进行中的计划；勾选=仅已完成的计划。浏览标签：未勾选=未收藏（开启“显示已计划”时仅限列表内）；勾选=列表上已收藏的条目（“显示已计划”仍会限制列表）。"
L["SHOW_PLANNED"] = "显示计划中"
L["SHOW_PLANNED_HELP"] = "仅浏览标签（在待办与周进度中隐藏）：勾选=仅显示你加入待办的目标。“显示已完成”关=仍缺的；开=已完成的；两项都开=该分类全部已计划；两项都关=完整未收藏浏览。"
L["PLANS_ACHIEVEMENTS_EMPTY_TITLE"] = "没有可显示的成就"
L["PLANS_ACHIEVEMENTS_EMPTY_HINT"] = "从此列表将成就加入待办，或更改“显示已计划/显示已完成”。列表随扫描填充；若为空可尝试 /reload。"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_TITLE"] = "没有可显示的内容"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_DESC"] = "当前筛选下没有匹配的已计划事项。请加入待办或调整“显示已计划/显示已完成”。"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_TITLE"] = "没有已完成的待办事项"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_DESC"] = "该分类中待办尚无已收藏或已完成项。关闭“显示已完成”可查看进行中的事项。"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_TITLE"] = "没有进行中的待办事项"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_DESC"] = "该分类待办中已没有未收藏项。开启“显示已完成”查看已完成项，或从本页添加目标。"

-- Plans Categories
L["CATEGORY_MY_PLANS"] = "待办列表"
L["CATEGORY_DAILY_TASKS"] = "每周进度"
L["CATEGORY_ILLUSIONS"] = "幻象"

-- Reputation Tab

-- Currency Tab

-- PvE Tab

-- Statistics
-- Tooltips
L["TOOLTIP_WARBAND_BANK"] = "战团银行"
L["CHARACTER_INVENTORY"] = "背包"
L["CHARACTER_BANK"] = "个人银行"

-- Try Counter
L["SET_TRY_COUNT"] = "设置尝试次数"
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

-- Error Messages

-- Confirmation Dialogs

-- Update Notification
L["WHATS_NEW"] = "更新内容"
L["GOT_IT"] = "知道了！"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "成就点数"
L["MOUNTS_COLLECTED"] = "已收集坐骑"
L["BATTLE_PETS"] = "战斗宠物"
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
L["CLICK_TO_DISMISS"] = "点击关闭"
L["TRACKED"] = "已追踪"
L["TRACK"] = "追踪"
L["TRACK_BLIZZARD_OBJECTIVES"] = "在暴雪任务中追踪（最多 10 个）"
L["NO_REQUIREMENTS"] = "无要求（即时完成）"

-- Plans UI
L["NO_ACTIVE_CONTENT"] = "本周没有活跃内容"
L["UNKNOWN_QUEST"] = "未知任务"
L["CURRENT_PROGRESS"] = "当前进度"
L["QUEST_TYPES"] = "任务类型："
L["WORK_IN_PROGRESS"] = "进行中"
L["RECIPE_BROWSER"] = "配方浏览器"
L["TRY_ADJUSTING_SEARCH"] = "尝试调整搜索或筛选条件。"
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
L["POINTS_SHORT"] = " 点"
L["TRACKING_ACTIVE_DESC"] = "数据收集和更新已激活。"
L["TRACKING_ENABLED"] = "追踪已启用"
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
L["NOT_IN_GUILD"] = "未加入公会"
L["ITEMS_SEARCH"] = "搜索物品..."
L["NEVER"] = "从未"
L["ITEM_FALLBACK_FORMAT"] = "物品 %s"
L["ITEM_LOADING_NAME"] = "加载中..."
L["TAB_FORMAT"] = "标签页 %d"
L["BAG_FORMAT"] = "背包 %d"
L["BANK_BAG_FORMAT"] = "银行背包 %d"
L["ITEM_ID_LABEL"] = "物品 ID："
L["STACK_LABEL"] = "堆叠："
L["RIGHT_CLICK_MOVE"] = "移至背包"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "拆分堆叠"
L["LEFT_CLICK_PICKUP"] = "拾取"
L["ITEMS_BANK_NOT_OPEN"] = "银行未打开"
L["SHIFT_LEFT_CLICK_LINK"] = "在聊天中链接"
L["ITEMS_STATS_ITEMS"] = "%s 件物品"
L["ITEMS_STATS_SLOTS"] = "%s/%s 格子"
L["ITEMS_STATS_LAST"] = "上次：%s"

-- Storage Tab (extended)
L["STORAGE_DISABLED_TITLE"] = "角色存储"
L["STORAGE_SEARCH"] = "搜索存储..."

-- PvE Tab (extended)
L["PVE_TITLE"] = "PvE 进度"
L["PVE_SUBTITLE"] = "宏伟宝库、团队副本锁定与史诗钥石，覆盖你的战团"
L["PVE_CREST_ADV"] = "冒险者"
L["PVE_CREST_VET"] = "老兵"
L["PVE_CREST_CHAMP"] = "勇士"
L["PVE_CREST_HERO"] = "英雄"
L["PVE_CREST_MYTH"] = "神话"
L["PVE_CREST_EXPLORER"] = "探索者"
L["PVE_COL_COFFER_SHARDS"] = "宝匣钥匙碎片"
L["PVE_COL_RESTORED_KEY"] = "修复的宝匣钥匙"
L["LV_FORMAT"] = "等级 %d"
L["ILVL_FORMAT"] = "装等 %d"
L["VAULT_WORLD"] = "世界"
L["VAULT_SLOT_FORMAT"] = "%s 栏 %d"
L["OVERALL_SCORE_LABEL"] = "总评分："
L["NOT_COMPLETED_SEASON"] = "本季未完成"
L["LOADING_PVE"] = "正在加载 PvE 数据..."
L["NO_VAULT_DATA"] = "无宝库数据"
L["NO_DATA"] = "无数据"
L["KEYSTONE"] = "钥石"
L["NO_KEY"] = "无钥石"
L["AFFIXES"] = "词缀"
L["NO_AFFIXES"] = "无词缀"
L["VAULT_BEST_KEY"] = "最佳钥石："
L["VAULT_SCORE"] = "评分："

-- Vault Tooltip (detailed)
L["VAULT_COMPLETED_ACTIVITIES"] = "已完成"
L["VAULT_CLICK_TO_OPEN"] = "点击打开宏伟宝库"
L["VAULT_REWARD"] = "奖励"
L["VAULT_DUNGEONS"] = "地下城"
L["VAULT_BOSS_KILLS"] = "首领击杀"
L["VAULT_WORLD_ACTIVITIES"] = "世界活动"
L["VAULT_ACTIVITIES"] = "活动"
L["VAULT_REMAINING_SUFFIX"] = "剩余"
L["VAULT_IMPROVE_TO"] = "提升至"
L["VAULT_COMPLETE_ON"] = "在 %s 上完成此活动"
L["VAULT_ENCOUNTER_LIST_FORMAT"] = "%s"
L["VAULT_TOP_RUNS_FORMAT"] = "本周前 %d 次记录"
L["VAULT_DELVE_TIER_FORMAT"] = "层级 %d（%d）"
L["VAULT_UNLOCK_REWARD"] = "解锁奖励"
L["VAULT_COMPLETE_MORE_FORMAT"] = "本周再完成 %d 个 %s 以解锁。"
L["VAULT_BASED_ON_FORMAT"] = "此奖励的物品等级将基于本周前 %d 次记录中的最低值（当前 %s）。"
L["VAULT_RAID_BASED_FORMAT"] = "奖励基于已击败的最高难度（当前 %s）。"

-- Delves Section (PvE Tab)
L["BOUNTIFUL_DELVE"] = "珍宝猎手的奖赏"
L["PVE_BOUNTY_NEED_LOGIN"] = "该角色没有保存的状态。请登录以刷新。"
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
L["REP_CYCLES_COLON"] = "周期："
L["REP_CHARACTER_PROGRESS"] = "角色进度："
L["REP_RENOWN_FORMAT"] = "名望 %d"
L["REP_PARAGON_FORMAT"] = "巅峰（%s）"
L["REP_UNKNOWN_FACTION"] = "未知阵营"
L["REP_API_UNAVAILABLE_TITLE"] = "声望 API 不可用"
L["REP_API_UNAVAILABLE_DESC"] = "此服务器上 C_Reputation API 不可用。此功能需要 WoW 12.0.1（Midnight）。"
L["REP_FOOTER_TITLE"] = "声望追踪"
L["REP_FOOTER_DESC"] = "声望在登录和变更时自动扫描。使用游戏内声望面板查看详细信息和奖励。"
L["REP_CLEARING_CACHE"] = "正在清除缓存并重新加载..."
L["REP_MAX"] = "最大"
L["ACCOUNT_WIDE_LABEL"] = "账号通用"
L["NO_RESULTS"] = "无结果"
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
L["PLANS_COUNT_FORMAT"] = "%d 个计划"
L["QUEST_LABEL"] = "任务："

-- Settings Tab
L["CURRENT_LANGUAGE"] = "当前语言："
L["LANGUAGE_TOOLTIP"] = "插件自动使用你的 WoW 游戏客户端语言。要更改，请更新你的战网设置。"
L["NOTIFICATION_DURATION"] = "通知持续时间"
L["NOTIFICATION_POSITION"] = "通知位置"
L["SET_POSITION"] = "设置位置"
L["SET_BOTH_POSITION"] = "设置两处位置"
L["DRAG_TO_POSITION"] = "拖动以设置位置\n右键确认"
L["RESET_DEFAULT"] = "重置为默认"
L["RESET_POSITION"] = "重置位置"
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
L["USE_ALERTFRAME_POSITION"] = "使用 AlertFrame 位置"
L["USE_ALERTFRAME_POSITION_ACTIVE"] = "正在使用暴雪 AlertFrame 位置"
L["NOTIFICATION_GHOST_MAIN"] = "成就 / 通知"
L["NOTIFICATION_GHOST_CRITERIA"] = "标准进度"
L["SHOW_WEEKLY_PLANNER"] = "每周计划（角色）"
L["LOCK_MINIMAP_ICON"] = "锁定小地图按钮"
L["BACKPACK_LABEL"] = "背包"
L["REAGENT_LABEL"] = "材料"

-- Shared Widgets & Dialogs
L["MODULE_DISABLED"] = "模块已禁用"
L["LOADING"] = "加载中..."
L["PLEASE_WAIT"] = "请稍候..."
L["RESET_PREFIX"] = "重置："
L["SAVE"] = "保存"
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

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "未知分类"
L["SCANNING_FORMAT"] = "正在扫描 %s"
L["CUSTOM_PLAN_SOURCE"] = "自定义计划"
L["POINTS_FORMAT"] = "%d 点"
L["SOURCE_NOT_AVAILABLE"] = "来源信息不可用"
L["PROGRESS_ON_FORMAT"] = "你的进度为 %d/%d"
L["COMPLETED_REQ_FORMAT"] = "你已完成 %d 项，共 %d 项要求"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "至暗之夜"
L["WEEKLY_RESET_LABEL"] = "每周重置"
L["QUEST_TYPE_WEEKLY"] = "每周任务"
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
L["ITEM_NUMBER_FORMAT"] = "物品 #%s"
L["WN_SEARCH"] = "WN 搜索"

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
L["NOTIFICATION_GOT_IT_AFTER"] = "经过%d次尝试后获得！"

-- Minimap Button
L["TOTAL_GOLD_LABEL"] = "总金币："
L["MINIMAP_CHARS_GOLD"] = "角色金币："
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





L["CHANGELOG_V2515"] = [=[v2.5.15 beta 1（2026-04-15）

测试（Beta）版本 — 欢迎反馈，稳定版发布前请勿视为最终发行。

性能
- 界面：SchedulePopulateContent 去抖（以最后一次调度为准）；OnHide 取消填充计时器；主标签切换仅一次延迟；切换中不重复刷新标签按钮；非当前标签时货币/声望仅更新角标。
- CollectionService：合并 EnsureCollectionData；ScanCollection 使用 FRAME_BUDGET_MS 协程；BuildFullCollectionData 批次预算一致。
- 公会银行与物品缓存：分块扫描；分标签原子赋值；取消/关闭时失效。
- 计划与收藏：PlansUI 双列网格 O(n) 预计算；AbortCollectionsChunkedBuilds；Core 中止与标签拆解一致。

修复
- TOC：Config.lua 在 Modules/Constants.lua 之后加载（修复 Config 初始化时 ns.Constants 为空）。
- 主框体 OnHide：取消后清空填充计时器。

本地化
- GearUI：升级轨道名称与制造/再造提示行；PVE_CREST_EXPLORER；专精专注与 Steam 风格游戏时间格式；GEAR_CRAFTED_*、STATS_PLAYED_STEAM_*、PROF_CONCENTRATION_* 多语言补全（de、fr、es、es-mx、it、pt、ru、ko、zhTW；enUS/zhCN 基线）。

CurseForge: Warband Nexus]=]

L["CHANGELOG_V261"] = [=[v2.6.1（2026-04-18）

修复
- 尝试计数：当目标或鼠标指向仍停留在附近敌方尸体上时，钓鱼尝试计数不再卡住；优先信任客户端钓鱼标记而非过期的单位上下文。

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
L["REP_LOADING_SAVING"] = "正在保存到数据库..."
L["REP_LOADING_COMPLETE"] = "完成！"

-- Status / Footer
L["COMBAT_LOCKDOWN_MSG"] = "战斗中无法打开窗口。战斗结束后请重试。"
L["BANK_IS_ACTIVE"] = "银行已打开"

-- Table Headers (SharedWidgets, Professions)

-- Search / Empty States
L["NO_ITEMS_MATCH"] = "没有匹配 '%s' 的物品"
L["NO_ITEMS_MATCH_GENERIC"] = "没有匹配你搜索的物品"
L["ITEMS_SCAN_HINT"] = "物品自动扫描。如无显示请尝试 /reload。"
L["ITEMS_WARBAND_BANK_HINT"] = "打开战团银行以扫描物品（首次访问时自动扫描）"

-- Currency Transfer Steps

-- Plans UI Extra
L["ADDED"] = "已添加"
L["WEEKLY_VAULT_TRACKER"] = "每周宝库追踪"
L["DAILY_QUEST_TRACKER"] = "每日任务追踪"

-- Achievement Popup
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
L["NO_SCAN"] = "未扫描"
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

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "未找到条件"
L["NO_REQUIREMENTS_INSTANT"] = "无要求（即时完成）"

-- Professions Tab
L["TAB_PROFESSIONS"] = "专业"
L["TAB_COLLECTIONS"] = "收藏"
L["COLLECTIONS_SUBTITLE"] = "坐骑、宠物、玩具与幻化概览"
L["COLLECTIONS_SUBTAB_RECENT"] = "最近"
L["COLLECTIONS_CONTENT_TITLE_ACHIEVEMENTS"] = "成就"
L["COLLECTIONS_CONTENT_SUB_ACHIEVEMENTS"] = "浏览和搜索你的成就。"
L["COLLECTIONS_CONTENT_TITLE_MOUNTS"] = "坐骑"
L["COLLECTIONS_CONTENT_SUB_MOUNTS"] = "战团坐骑收藏、来源和预览。"
L["COLLECTIONS_CONTENT_TITLE_PETS"] = "宠物"
L["COLLECTIONS_CONTENT_SUB_PETS"] = "账号共享的战斗宠物和伙伴。"
L["COLLECTIONS_CONTENT_TITLE_TOYS"] = "玩具"
L["COLLECTIONS_CONTENT_SUB_TOYS"] = "玩具和可使用收藏品。"
L["COLLECTIONS_CONTENT_TITLE_RECENT"] = "最近获取"
L["COLLECTIONS_CONTENT_SUB_RECENT"] = "你的账号记录的最新成就、坐骑、宠物和玩具。"
L["COLLECTIONS_RECENT_JUST_NOW"] = "刚刚"
L["COLLECTIONS_RECENT_MINUTES_AGO"] = "%d分钟前"
L["COLLECTIONS_RECENT_HOURS_AGO"] = "%d小时前"
L["COLLECTIONS_RECENT_DAYS_AGO"] = "%d天前"
L["COLLECTIONS_ACQUIRED_LABEL"] = "已记录"
L["COLLECTIONS_ACQUIRED_LINE"] = "%s：%s"
L["COLLECTIONS_RECENT_TAB_EMPTY"] = "未记录任何信息"
L["COLLECTIONS_RECENT_EMPTY"] = "未记录任何内容"
L["COLLECTIONS_RECENT_SEARCH_EMPTY"] = "没有匹配的信息"
L["COLLECTIONS_RECENT_SECTION_NONE"] = "暂无信息"
L["SELECT_MOUNT_FROM_LIST"] = "从列表选择坐骑"
L["SELECT_PET_FROM_LIST"] = "从列表选择宠物"
L["SELECT_TO_SEE_DETAILS"] = "选择 %s 以查看详情。"
L["SOURCE"] = "来源"
L["YOUR_PROFESSIONS"] = "战团专业"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s 个角色有专业"
L["PROFESSIONS_WIDE_TABLE_HINT"] = "提示：使用下方滚动条或 Shift+滚轮查看所有列。"
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
L["PROF_CONCENTRATION_FULL"] = "已满"
L["PROF_CONCENTRATION_HOURS_REMAINING"] = "%d 小时"
L["PROF_CONCENTRATION_MINUTES_REMAINING"] = "%d 分钟"
L["PROF_CONCENTRATION_DAYS_HOURS_MIN"] = "%d 天 %d 小时 %d 分钟"
L["PROF_CONCENTRATION_HOURS_MIN"] = "%d 小时 %d 分钟"
L["PROF_CONCENTRATION_MINUTES_ONLY"] = "%d 分钟"
L["PROF_OPEN_RECIPE"] = "打开"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "打开此专业的配方列表"
L["PROF_ONLY_CURRENT_CHAR"] = "仅当前角色可用"
L["NO_PROFESSION"] = "无专业"

-- Professions: Expansion filter
L["PROF_FILTER_ALL"] = "全部"
L["PROF_FIRSTCRAFT_NO_DATA"] = "无可用专业数据。"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "首次制造"
L["UNIQUES"] = "周知识"
L["TREATISE"] = "论述"
L["GATHERING"] = "采集"
L["CATCH_UP"] = "追赶"
L["MOXIE"] = "匠人"
L["COOLDOWNS"] = "冷却"
L["COLUMNS_BUTTON"] = "列"

-- Professions: Tooltips & Details

-- Professions: Crafting Orders

-- Professions: Equipment
L["EQUIPMENT"] = "装备"
L["TOOL"] = "工具"
L["ACCESSORY"] = "配件"
L["PROF_EQUIPMENT_HINT"] = "在此角色上打开专业技能(K)以扫描装备。"

-- Professions: Info Window
L["PROF_INFO_TOOLTIP"] = "查看专业详情"
L["PROF_INFO_NO_DATA"] = "无专业数据。\n请登录此角色并打开专业技能窗口(K)以收集数据。"
L["PROF_INFO_SKILLS"] = "资料片技能"
L["PROF_INFO_TOOL"] = "工具"
L["PROF_INFO_ACC1"] = "饰品 1"
L["PROF_INFO_ACC2"] = "饰品 2"
L["PROF_INFO_KNOWN"] = "已学"
L["PROF_INFO_WEEKLY"] = "每周知识进度"
L["PROF_INFO_COOLDOWNS"] = "冷却"
L["PROF_INFO_READY"] = "就绪"
L["PROF_INFO_LAST_UPDATE"] = "上次更新"
L["PROF_INFO_LOCKED"] = "已锁定"
L["PROF_INFO_UNLEARNED"] = "未学习"

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
L["TRYCOUNTER_WHAT_A_GRIND"] = "真是一场苦战！%d 次尝试（按概率现在本应约有 %d%% 获得）—— %s"
L["TRYCOUNTER_CAUGHT_RESET"] = "捕获 %s！尝试计数已重置。"
L["TRYCOUNTER_CAUGHT"] = "钓到 %s！"
L["TRYCOUNTER_CONTAINER_RESET"] = "从容器获得 %s！尝试计数已重置。"
L["TRYCOUNTER_CONTAINER"] = "从容器获得 %s！"
L["TRYCOUNTER_LOCKOUT_SKIP"] = "已跳过：此 NPC 的每日/每周锁定已激活。"
L["TRYCOUNTER_INSTANCE_ENTRY_HINT"] = "此副本有适用于你当前难度的尝试计数坐骑。对首领使用目标或鼠标指向后输入 |cffffffff/wn check|r 查看详情。"
L["TRYCOUNTER_COLLECTED_TAG"] = "（已收集）"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " 次尝试"
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
L["PERSONAL_BANK"] = "个人银行"
L["WARBAND_BANK_LABEL"] = "战团银行"
L["WARBAND_BANK_TAB_FORMAT"] = "标签页 %d"
L["CURRENCY_OTHER"] = "其他"

-- DataService: Reputation Standings
L["STANDING_HATED"] = "仇恨"
L["STANDING_HOSTILE"] = "敌对"
L["STANDING_UNFRIENDLY"] = "冷淡"
L["STANDING_NEUTRAL"] = "中立"
L["STANDING_FRIENDLY"] = "友好"
L["STANDING_HONORED"] = "尊敬"
L["STANDING_REVERED"] = "崇敬"
L["STANDING_EXALTED"] = "崇拜"

-- Loading Tracker Labels
L["LT_CHARACTER_DATA"] = "角色数据"
L["LT_CURRENCY_CACHES"] = "货币与缓存"
L["LT_REPUTATIONS"] = "声望"
L["LT_PROFESSIONS"] = "专业"
L["LT_PVE_DATA"] = "PvE 数据"
L["LT_COLLECTIONS"] = "收藏"
L["LT_COLLECTION_DATA"] = "收藏数据"

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
L["CONFIG_THEME_APPLIED"] = "%s 主题已应用！"
L["CONFIG_THEME_RESET_DESC"] = "将所有主题色重置为默认紫色主题。"
L["CONFIG_NOTIFICATIONS"] = "通知"
L["CONFIG_NOTIFICATIONS_DESC"] = "配置显示哪些通知。"
L["CONFIG_ENABLE_NOTIFICATIONS"] = "启用通知"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "显示收藏品事件弹窗通知。"
L["CONFIG_SHOW_UPDATE_NOTES"] = "再次显示更新说明"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "下次登录时显示「更新内容」窗口。"
L["CONFIG_UPDATE_NOTES_SHOWN"] = "更新通知将在下次登录时显示。"
L["CONFIG_RESET_PLANS"] = "重置已完成计划"
L["CONFIG_RESET_PLANS_FORMAT"] = "已移除 %d 个已完成计划。"
L["CONFIG_TAB_FILTERING"] = "标签页筛选"
L["CONFIG_TAB_FILTERING_DESC"] = "选择主窗口中可见的标签页。"
L["CONFIG_CHARACTER_MGMT"] = "角色管理"
L["CONFIG_CHARACTER_MGMT_DESC"] = "管理追踪的角色并移除旧数据。"
L["CONFIG_DELETE_CHAR"] = "删除角色数据"
L["CONFIG_DELETE_CHAR_DESC"] = "永久移除所选角色的所有存储数据。"
L["CONFIG_FONT_SCALING"] = "字体与缩放"
L["CONFIG_FONT_SCALING_DESC"] = "调整字体和大小缩放。"
L["CONFIG_FONT_FAMILY"] = "字体"
L["CONFIG_ADVANCED"] = "高级"
L["CONFIG_ADVANCED_DESC"] = "高级设置和数据库管理。请谨慎使用！"
L["CONFIG_DEBUG_MODE"] = "调试模式"
L["CONFIG_DEBUG_MODE_DESC"] = "启用详细日志以便调试。仅在排查问题时启用。"
L["CONFIG_DEBUG_VERBOSE"] = "详细调试（缓存/扫描/提示日志）"
L["CONFIG_DEBUG_VERBOSE_DESC"] = "调试模式下同时显示货币/声望缓存、背包扫描、提示与专业日志。关闭可减少聊天刷屏。"
L["CONFIG_DB_STATS"] = "显示数据库统计"
L["CONFIG_DB_STATS_DESC"] = "显示当前数据库大小和优化统计。"
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
L["GOLD_MANAGEMENT_ENABLE"] = "启用金币管理"
L["GOLD_MANAGEMENT_MODE"] = "管理模式"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "仅存入"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "金币超过 X 时，超额自动存入战团银行。"
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "仅取款"
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "金币少于 X 时，差额自动从战团银行取款。"
L["GOLD_MANAGEMENT_MODE_BOTH"] = "两者"
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "自动维持角色金币恰好为 X（多则存，少则取）。"
L["GOLD_MANAGEMENT_TARGET"] = "目标金币数量"
L["GOLD_MANAGEMENT_HELPER"] = "输入你想在此角色上保留的金币数量。打开银行时插件将自动管理你的金币。"
L["GOLD_MANAGEMENT_CHAR_ONLY"] = "仅此角色 (%s)"
L["GOLD_MANAGEMENT_CHAR_ONLY_DESC"] = "仅为此角色使用单独的金币管理设置。其他角色将使用共享配置。"
L["GOLD_MGMT_PROFILE_TITLE"] = "配置（所有角色）"
L["GOLD_MGMT_USING_PROFILE"] = "使用配置"
L["GOLD_MGMT_MODE_SHORT_DEPOSIT"] = "存入"
L["GOLD_MGMT_MODE_SHORT_WITHDRAW"] = "取出"
L["GOLD_MGMT_MODE_SHORT_BOTH"] = "双向"
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
L["GEAR_MISSING_ENCHANT"] = "缺少附魔"
L["GEAR_MISSING_GEM"] = "缺少宝石"
L["GEAR_UPGRADE_AVAILABLE_FORMAT"] = "可升级至 %s %d/%d%s"
L["GEAR_UPGRADES_WITH_CURRENCY_FORMAT"] = "当前货币可升级 %d次"
L["GEAR_CRESTS_GOLD_ONLY"] = "所需纹章：0（仅需金币 — 此前已达成）"
L["GEAR_UPGRADES_GOLD_ONLY_FORMAT"] = "%d次仅需金币升级（此前已达成）"
L["GEAR_NEED_MORE_CRESTS_FORMAT"] = "%s %d/%d — 需要更多纹章"
L["GEAR_CRAFTED_NO_CRESTS"] = "没有可用于再造的纹章"
L["GEAR_TRACK_CRAFTED_FALLBACK"] = "制造"
L["GEAR_CRAFTED_MAX_ILVL_LINE"] = "%s（最高装等 %d）"
L["GEAR_CRAFTED_RECAST_TO_LINE"] = "再造至 %s（装等 %d）"
L["GEAR_CRAFTED_COST_DAWNCREST"] = "消耗：%d %s 黎明纹章"
L["GEAR_CRAFTED_NEXT_TIER_CRESTS"] = "%s（装等 %d）：纹章 %d/%d（还需 %d）"
L["GEAR_TAB_TITLE"] = "装备管理"
L["GEAR_TAB_DESC"] = "已装备、升级选项及跨角色升级候选"
L["GEAR_STORAGE_WARBOUND"] = "战团绑定"
L["GEAR_STORAGE_BOE"] = "装绑"
L["GEAR_STORAGE_TITLE"] = "存储升级推荐"
L["GEAR_STORAGE_EMPTY"] = "未找到适合该角色的更好装绑 / 战团绑定升级。"

-- Characters UI
L["WOW_TOKEN_LABEL"] = "WOW代币"

-- Statistics UI
L["FORMAT_BUTTON"] = "格式"
L["STATS_PLAYED_STEAM_ZERO"] = "0 小时"
L["STATS_PLAYED_STEAM_FLOAT"] = "%.1f 小时"
L["STATS_PLAYED_STEAM_THOUSAND"] = "%d,%03d 小时"
L["STATS_PLAYED_STEAM_INT"] = "%d 小时"

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
L["TRACK_ACTIVITIES"] = "追踪活动"

L["ACHIEVEMENT_SERIES"] = "成就系列"
L["LOADING_ACHIEVEMENTS"] = "加载成就中..."
L["TAB_GEAR"] = "装备"

-- Keybinding globals (must be global for WoW's keybinding UI)
BINDING_HEADER_WARBANDNEXUS = "Warband Nexus"
BINDING_NAME_WARBANDNEXUS_TOGGLE = "显示/隐藏主窗口"

-- Blizzard GlobalStrings (Auto-localized by WoW) [parity sync]
L["BANK_LABEL"] = BANK or "Bank"
L["BTN_SETTINGS"] = SETTINGS
L["CANCEL"] = CANCEL or "Cancel"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Achievements"
L["CATEGORY_ALL"] = ALL or "All Items"
L["CATEGORY_MOUNTS"] = MOUNTS or "Mounts"
L["CATEGORY_PETS"] = PETS or "Pets"
L["CATEGORY_TITLES"] = L["TYPE_TITLE"] or TITLES or "Titles"
L["CATEGORY_TOYS"] = TOY_BOX or "Toys"
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmog"
L["DELETE"] = DELETE or "Delete"
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "Heroic"
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "Mythic"
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "Normal"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "Dungeon"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Unknown"
L["FIRSTCRAFT"] = PROFESSIONS_FIRST_CRAFT or "First Craft"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["HEADER_CHARACTERS"] = CHARACTER or "Characters"
L["HEADER_FAVORITES"] = FAVORITES or "Favorites"
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Guild Bank"
L["ITEMS_PLAYER_BANK"] = BANK or "Player Bank"
L["NONE_LABEL"] = NONE or "None"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Notifications"
L["OK_BUTTON"] = OKAY or "OK"
L["PARSE_ARENA"] = ARENA or "Arena"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Drop"
L["PARSE_DUNGEON"] = DUNGEONS or "Dungeon"
L["PARSE_FACTION"] = FACTION or "Faction"
L["PARSE_RAID"] = RAID or "Raid"
L["PARSE_REPUTATION"] = REPUTATION or "Reputation"
L["PARSE_ZONE"] = ZONE or "Zone"
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Dungeons"
L["PVE_HEADER_RAIDS"] = RAIDS or "Raids"
L["PVP_TYPE"] = PVP or "PvP"
L["RAID_CAT"] = RAID or "Raid"
L["RAIDS_LABEL"] = RAIDS or "Raids"
L["RELOAD_UI_BUTTON"] = RELOADUI or "Reload UI"
L["RESET_LABEL"] = RESET or "Reset"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["SLOT_BACK"] = INVTYPE_CLOAK or "Back"
L["SLOT_CHEST"] = INVTYPE_CHEST or "Chest"
L["SLOT_FEET"] = INVTYPE_FEET or "Feet"
L["SLOT_HANDS"] = INVTYPE_HAND or "Hands"
L["SLOT_HEAD"] = INVTYPE_HEAD or "Head"
L["SLOT_LEGS"] = INVTYPE_LEGS or "Legs"
L["SLOT_MAINHAND"] = INVTYPE_WEAPONMAINHAND or "Main Hand"
L["SLOT_OFFHAND"] = INVTYPE_WEAPONOFFHAND or "Off Hand"
L["SLOT_SHIRT"] = INVTYPE_BODY or "Shirt"
L["SLOT_SHOULDER"] = INVTYPE_SHOULDER or "Shoulder"
L["SLOT_TABARD"] = INVTYPE_TABARD or "Tabard"
L["SLOT_WAIST"] = INVTYPE_WAIST or "Waist"
L["SLOT_WRIST"] = INVTYPE_WRIST or "Wrist"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Achievement"
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Drop"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "In-Game Shop"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Pet Battle"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promotion"
L["SOURCE_TYPE_PVP"] = PVP or "PvP"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Quest"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "Trading Card Game"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "Unknown"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Vendor"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "World Event"
L["STAT_AGILITY"] = SPELL_STAT2_NAME or "Agility"
L["STAT_CRITICAL_STRIKE"] = STAT_CRITICAL_STRIKE or "Critical Strike"
L["STAT_HASTE"] = STAT_HASTE or "Haste"
L["STAT_INTELLECT"] = SPELL_STAT4_NAME or "Intellect"
L["STAT_MASTERY"] = STAT_MASTERY or "Mastery"
L["STAT_STAMINA"] = SPELL_STAT3_NAME or "Stamina"
L["STAT_STRENGTH"] = SPELL_STAT1_NAME or "Strength"
L["STAT_VERSATILITY"] = STAT_VERSATILITY or "Versatility"
L["TAB_CHARACTERS"] = CHARACTER or "Characters"
L["TAB_CURRENCY"] = CURRENCY or "Currency"
L["TAB_ITEMS"] = ITEMS or "Items"
L["TAB_REPUTATION"] = REPUTATION or "Reputation"
L["TAB_STATISTICS"] = STATISTICS or "Statistics"
L["TYPE_MOUNT"] = MOUNT or "Mount"
L["TYPE_PET"] = PET or "Pet"
L["TYPE_TOY"] = TOY or "Toy"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transmog"
L["VAULT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon"
L["VAULT_SLOT_DUNGEON"] = DUNGEONS or "Dungeons"
L["VAULT_SLOT_RAIDS"] = RAIDS or "Raids"
L["VERSION"] = GAME_VERSION_LABEL or "Version"

-- Core GlobalStrings parity
L["YES"] = YES or "Yes"
L["NO"] = NO or "No"
L["TOTAL"] = TOTAL or "Total"
L["UNKNOWN"] = UNKNOWN or "Unknown"
L["FILTER_LABEL"] = FILTER or "Filter"

-- Localization parity sync (hardcoded UI cleanup)
L["WOWHEAD_LABEL"] = "Wowhead"
L["CLICK_TO_COPY_LINK"] = "点击复制链接"
L["PLAN_CHAT_LINK_TITLE"] = "聊天链接"
L["PLAN_CHAT_LINK_HINT"] = "点击发送到聊天"
L["PLAN_CHAT_LINK_UNAVAILABLE"] = "该信息没有可用的聊天链接"
L["CLICK_FOR_WOWHEAD_LINK"] = "点击查看 Wowhead 链接"
L["PLAN_ACTION_COMPLETE"] = "完成计划"
L["PLAN_ACTION_DELETE"] = "删除计划"
L["OBJECTIVE_INDEX_FORMAT"] = "目标 %d"
L["QUEST_PROGRESS_FORMAT"] = "进度：%d/%d（%d%%）"
L["QUEST_TIME_REMAINING_FORMAT"] = "剩余 %s "
L["EVENT_GROUP_SOIREE"] = "萨瑟利尔的聚会"
L["EVENT_GROUP_ABUNDANCE"] = "丰饶"
L["EVENT_GROUP_HARANIR"] = "哈籁尼尔的传说"
L["EVENT_GROUP_STORMARION"] = "斯托玛兰突袭战"
L["QUEST_CATEGORY_DESC_WEEKLY"] = "每周目标、狩猎、火花、世界首领、地下堡"
L["QUEST_CATEGORY_DESC_WORLD"] = "区域可重复的世界任务"
L["QUEST_CATEGORY_DESC_DAILY"] = "来自NPC的每日可重复任务"
L["QUEST_CATEGORY_DESC_EVENTS"] = "奖励目标、任务和活动"
L["GEAR_NO_TRACKED_CHARACTERS_TITLE"] = "没有追踪的角色"
L["GEAR_NO_TRACKED_CHARACTERS_DESC"] = "登录一个角色以开始追踪装备。"
L["SOURCE_TYPE_CATEGORY_FORMAT"] = "类别 %d"
L["TYPE_ITEM"] = ITEM or "Item"
L["CTRL_C_LABEL"] = "Ctrl+C"
L["WOW_TOKEN_COUNT_LABEL"] = "代币"
L["NOT_AVAILABLE_SHORT"] = "N/A"
L["COLLECTION_RULE_API_NOT_AVAILABLE"] = "API不可用"
L["COLLECTION_RULE_INVALID_MOUNT"] = "无效的坐骑"
L["COLLECTION_RULE_FACTION_CLASS_RESTRICTED"] = "阵营和职业限制"

