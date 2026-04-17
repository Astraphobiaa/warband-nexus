--[[
    Warband Nexus - Simplified Chinese Localization (ç®€ä½“ä¸­æ–‡)
    
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
L["KEYBINDING"] = "å¿«æ·é”®"
L["KEYBINDING_UNBOUND"] = "æœªè®¾ç½®"
L["KEYBINDING_PRESS_KEY"] = "è¯·æŒ‰ä¸€ä¸ªé”®..."
L["KEYBINDING_TOOLTIP"] = "ç‚¹å‡»è®¾ç½®å¿«æ·é”®ä»¥åˆ‡æ¢ Warband Nexusã€‚\næŒ‰ ESC å–æ¶ˆã€‚"
L["KEYBINDING_CLEAR"] = "æ¸…é™¤å¿«æ·é”®"
L["KEYBINDING_SAVED"] = "å¿«æ·é”®å·²ä¿å­˜ã€‚"
L["KEYBINDING_COMBAT"] = "æˆ˜æ–—ä¸­æ— æ³•æ›´æ”¹å¿«æ·é”®ã€‚"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "å¸¸è§„è®¾ç½®"
L["DEBUG_MODE"] = "è°ƒè¯•æ—¥å¿—"
L["DEBUG_MODE_DESC"] = "åœ¨èŠå¤©æ¡†è¾“å‡ºè¯¦ç»†è°ƒè¯•ä¿¡æ¯ä»¥ä¾¿æ’æŸ¥é—®é¢˜"
L["DEBUG_TRYCOUNTER_LOOT"] = "å°è¯•è®¡æ•°æˆ˜åˆ©å“è°ƒè¯•"
L["DEBUG_TRYCOUNTER_LOOT_DESC"] = "ä»…è®°å½•æˆ˜åˆ©å“æµç¨‹ï¼ˆLOOT_OPENEDã€æ¥æºè§£æã€åŒºåŸŸå›é€€ï¼‰ã€‚å£°æœ›/è´§å¸ç¼“å­˜æ—¥å¿—å·²æŠ‘åˆ¶ã€‚"

-- Options Panel - Scanning

-- Options Panel - Deposit

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "æ˜¾ç¤º"
L["DISPLAY_SETTINGS_DESC"] = "è‡ªå®šä¹‰ç‰©å“å’Œä¿¡æ¯çš„æ˜¾ç¤ºæ–¹å¼ã€‚"
L["SHOW_ITEM_COUNT"] = "æ˜¾ç¤ºç‰©å“æ•°é‡"

-- Options Panel - Tabs

-- Scanner Module

-- Banker Module

-- Warband Bank Operations

-- UI Module
L["SEARCH_CATEGORY_FORMAT"] = "æœç´¢ %s..."

-- Main Tabs
L["TAB_STORAGE"] = "å­˜å‚¨"
L["TAB_PLANS"] = "å¾…åŠ"
L["TAB_REPUTATIONS"] = "å£°æœ›"
L["TAB_CURRENCIES"] = "è´§å¸"
L["TAB_PVE"] = "PvE"

-- Characters Tab
L["HEADER_CURRENT_CHARACTER"] = "å½“å‰è§’è‰²"
L["HEADER_WARBAND_GOLD"] = "æˆ˜å›¢é‡‘å¸"
L["HEADER_TOTAL_GOLD"] = "æ€»é‡‘å¸"
-- Items Tab
L["ITEMS_HEADER"] = "é“¶è¡Œç‰©å“"
L["ITEMS_WARBAND_BANK"] = "æˆ˜å›¢é“¶è¡Œ"

-- Storage Tab
L["STORAGE_HEADER"] = "å­˜å‚¨æµè§ˆå™¨"
L["STORAGE_HEADER_DESC"] = "æŒ‰ç±»å‹æµè§ˆæ‰€æœ‰ç‰©å“"
L["STORAGE_WARBAND_BANK"] = "æˆ˜å›¢é“¶è¡Œ"

-- Plans Tab
L["COLLECTION_PLANS"] = "å¾…åŠæ¸…å•"
L["SEARCH_PLANS"] = "æœç´¢è®¡åˆ’..."
L["SHOW_COMPLETED"] = "æ˜¾ç¤ºå·²å®Œæˆ"
L["SHOW_COMPLETED_HELP"] = "å¾…åŠä¸å‘¨è¿›åº¦ï¼šæœªå‹¾é€‰=ä»è¿›è¡Œä¸­çš„è®¡åˆ’ï¼›å‹¾é€‰=ä»…å·²å®Œæˆçš„è®¡åˆ’ã€‚æµè§ˆæ ‡ç­¾ï¼šæœªå‹¾é€‰=æœªæ”¶è—ï¼ˆå¼€å¯â€œæ˜¾ç¤ºå·²è®¡åˆ’â€æ—¶ä»…é™åˆ—è¡¨å†…ï¼‰ï¼›å‹¾é€‰=åˆ—è¡¨ä¸Šå·²æ”¶è—çš„æ¡ç›®ï¼ˆâ€œæ˜¾ç¤ºå·²è®¡åˆ’â€ä»ä¼šé™åˆ¶åˆ—è¡¨ï¼‰ã€‚"
L["SHOW_PLANNED"] = "æ˜¾ç¤ºè®¡åˆ’ä¸­"
L["SHOW_PLANNED_HELP"] = "ä»…æµè§ˆæ ‡ç­¾ï¼ˆåœ¨å¾…åŠä¸å‘¨è¿›åº¦ä¸­éšè—ï¼‰ï¼šå‹¾é€‰=ä»…æ˜¾ç¤ºä½ åŠ å…¥å¾…åŠçš„ç›®æ ‡ã€‚â€œæ˜¾ç¤ºå·²å®Œæˆâ€å…³=ä»ç¼ºçš„ï¼›å¼€=å·²å®Œæˆçš„ï¼›ä¸¤é¡¹éƒ½å¼€=è¯¥åˆ†ç±»å…¨éƒ¨å·²è®¡åˆ’ï¼›ä¸¤é¡¹éƒ½å…³=å®Œæ•´æœªæ”¶è—æµè§ˆã€‚"
L["PLANS_ACHIEVEMENTS_EMPTY_TITLE"] = "æ²¡æœ‰å¯æ˜¾ç¤ºçš„æˆå°±"
L["PLANS_ACHIEVEMENTS_EMPTY_HINT"] = "ä»æ­¤åˆ—è¡¨å°†æˆå°±åŠ å…¥å¾…åŠï¼Œæˆ–æ›´æ”¹â€œæ˜¾ç¤ºå·²è®¡åˆ’/æ˜¾ç¤ºå·²å®Œæˆâ€ã€‚åˆ—è¡¨éšæ‰«æå¡«å……ï¼›è‹¥ä¸ºç©ºå¯å°è¯• /reloadã€‚"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_TITLE"] = "æ²¡æœ‰å¯æ˜¾ç¤ºçš„å†…å®¹"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_DESC"] = "å½“å‰ç­›é€‰ä¸‹æ²¡æœ‰åŒ¹é…çš„å·²è®¡åˆ’äº‹é¡¹ã€‚è¯·åŠ å…¥å¾…åŠæˆ–è°ƒæ•´â€œæ˜¾ç¤ºå·²è®¡åˆ’/æ˜¾ç¤ºå·²å®Œæˆâ€ã€‚"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_TITLE"] = "æ²¡æœ‰å·²å®Œæˆçš„å¾…åŠäº‹é¡¹"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_DESC"] = "è¯¥åˆ†ç±»ä¸­å¾…åŠå°šæ— å·²æ”¶è—æˆ–å·²å®Œæˆé¡¹ã€‚å…³é—­â€œæ˜¾ç¤ºå·²å®Œæˆâ€å¯æŸ¥çœ‹è¿›è¡Œä¸­çš„äº‹é¡¹ã€‚"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_TITLE"] = "æ²¡æœ‰è¿›è¡Œä¸­çš„å¾…åŠäº‹é¡¹"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_DESC"] = "è¯¥åˆ†ç±»å¾…åŠä¸­å·²æ²¡æœ‰æœªæ”¶è—é¡¹ã€‚å¼€å¯â€œæ˜¾ç¤ºå·²å®Œæˆâ€æŸ¥çœ‹å·²å®Œæˆé¡¹ï¼Œæˆ–ä»æœ¬é¡µæ·»åŠ ç›®æ ‡ã€‚"

-- Plans Categories
L["CATEGORY_MY_PLANS"] = "å¾…åŠåˆ—è¡¨"
L["CATEGORY_DAILY_TASKS"] = "æ¯å‘¨è¿›åº¦"
L["CATEGORY_ILLUSIONS"] = "å¹»è±¡"

-- Reputation Tab

-- Currency Tab

-- PvE Tab

-- Statistics
-- Tooltips
L["TOOLTIP_WARBAND_BANK"] = "æˆ˜å›¢é“¶è¡Œ"
L["CHARACTER_INVENTORY"] = "èƒŒåŒ…"
L["CHARACTER_BANK"] = "ä¸ªäººé“¶è¡Œ"

-- Try Counter
L["SET_TRY_COUNT"] = "è®¾ç½®å°è¯•æ¬¡æ•°"
L["TRY_COUNT_CLICK_HINT"] = "ç‚¹å‡»ä»¥ç¼–è¾‘å°è¯•æ¬¡æ•°ã€‚"
L["TRIES"] = "æ¬¡"
L["COLLECTION_LIST_ATTEMPTS_FMT"] = "%dæ¬¡å°è¯•"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "è®¾ç½®é‡ç½®å‘¨æœŸ"
L["DAILY_RESET"] = "æ¯æ—¥é‡ç½®"
L["WEEKLY_RESET"] = "æ¯å‘¨é‡ç½®"
L["NONE_DISABLE"] = "æ— ï¼ˆç¦ç”¨ï¼‰"
L["RESET_CYCLE_LABEL"] = "é‡ç½®å‘¨æœŸï¼š"
L["RESET_NONE"] = "æ— "

-- Error Messages

-- Confirmation Dialogs

-- Update Notification
L["WHATS_NEW"] = "æ›´æ–°å†…å®¹"
L["GOT_IT"] = "çŸ¥é“äº†ï¼"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "æˆå°±ç‚¹æ•°"
L["MOUNTS_COLLECTED"] = "å·²æ”¶é›†åéª‘"
L["BATTLE_PETS"] = "æˆ˜æ–—å® ç‰©"
L["UNIQUE_PETS"] = "ç‹¬ç‰¹å® ç‰©"
L["ACCOUNT_WIDE"] = "è´¦å·é€šç”¨"
L["STORAGE_OVERVIEW"] = "å­˜å‚¨æ¦‚è§ˆ"
L["WARBAND_SLOTS"] = "æˆ˜å›¢æ ¼å­"
L["PERSONAL_SLOTS"] = "ä¸ªäººæ ¼å­"
L["TOTAL_FREE"] = "æ€»ç©ºé—²"
L["TOTAL_ITEMS"] = "ç‰©å“æ€»æ•°"

-- Plans Tracker
L["WEEKLY_VAULT"] = "æ¯å‘¨å®åº“"
L["CUSTOM"] = "è‡ªå®šä¹‰"
L["NO_PLANS_IN_CATEGORY"] = "æ­¤åˆ†ç±»æš‚æ— è®¡åˆ’ã€‚\nä»è®¡åˆ’æ ‡ç­¾é¡µæ·»åŠ è®¡åˆ’ã€‚"
L["SOURCE_LABEL"] = "æ¥æºï¼š"
L["ZONE_LABEL"] = "åŒºåŸŸï¼š"
L["VENDOR_LABEL"] = "å•†äººï¼š"
L["DROP_LABEL"] = "æ‰è½ï¼š"
L["REQUIREMENT_LABEL"] = "è¦æ±‚ï¼š"
L["CLICK_TO_DISMISS"] = "ç‚¹å‡»å…³é—­"
L["TRACKED"] = "å·²è¿½è¸ª"
L["TRACK"] = "è¿½è¸ª"
L["TRACK_BLIZZARD_OBJECTIVES"] = "åœ¨æš´é›ªä»»åŠ¡ä¸­è¿½è¸ªï¼ˆæœ€å¤š 10 ä¸ªï¼‰"
L["NO_REQUIREMENTS"] = "æ— è¦æ±‚ï¼ˆå³æ—¶å®Œæˆï¼‰"

-- Plans UI
L["NO_ACTIVE_CONTENT"] = "æœ¬å‘¨æ²¡æœ‰æ´»è·ƒå†…å®¹"
L["UNKNOWN_QUEST"] = "æœªçŸ¥ä»»åŠ¡"
L["CURRENT_PROGRESS"] = "å½“å‰è¿›åº¦"
L["QUEST_TYPES"] = "ä»»åŠ¡ç±»å‹ï¼š"
L["WORK_IN_PROGRESS"] = "è¿›è¡Œä¸­"
L["RECIPE_BROWSER"] = "é…æ–¹æµè§ˆå™¨"
L["TRY_ADJUSTING_SEARCH"] = "å°è¯•è°ƒæ•´æœç´¢æˆ–ç­›é€‰æ¡ä»¶ã€‚"
L["ALL_COLLECTED_CATEGORY"] = "æ‰€æœ‰ %s å·²æ”¶é›†ï¼"
L["COLLECTED_EVERYTHING"] = "ä½ å·²æ”¶é›†æ­¤åˆ†ç±»ä¸­çš„æ‰€æœ‰ç‰©å“ï¼"
L["PROGRESS_LABEL"] = "è¿›åº¦ï¼š"
L["REQUIREMENTS_LABEL"] = "è¦æ±‚ï¼š"
L["INFORMATION_LABEL"] = "ä¿¡æ¯ï¼š"
L["DESCRIPTION_LABEL"] = "æè¿°ï¼š"
L["REWARD_LABEL"] = "å¥–åŠ±ï¼š"
L["DETAILS_LABEL"] = "è¯¦æƒ…ï¼š"
L["COST_LABEL"] = "èŠ±è´¹ï¼š"
L["LOCATION_LABEL"] = "ä½ç½®ï¼š"
L["TITLE_LABEL"] = "æ ‡é¢˜ï¼š"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "ä½ å·²å®Œæˆæ­¤åˆ†ç±»ä¸­çš„æ‰€æœ‰æˆå°±ï¼"
L["DAILY_PLAN_EXISTS"] = "æ¯æ—¥è®¡åˆ’å·²å­˜åœ¨"
L["WEEKLY_PLAN_EXISTS"] = "æ¯å‘¨è®¡åˆ’å·²å­˜åœ¨"

-- Characters Tab (extended)
L["YOUR_CHARACTERS"] = "ä½ çš„è§’è‰²"
L["CHARACTERS_TRACKED_FORMAT"] = "å·²è¿½è¸ª %d ä¸ªè§’è‰²"
L["NO_FAVORITES"] = "æš‚æ— æ”¶è—è§’è‰²ã€‚ç‚¹å‡»æ˜Ÿæ ‡å›¾æ ‡æ”¶è—è§’è‰²ã€‚"
L["ALL_FAVORITED"] = "æ‰€æœ‰è§’è‰²å·²æ”¶è—ï¼"
L["UNTRACKED_CHARACTERS"] = "æœªè¿½è¸ªè§’è‰²"
L["ILVL_SHORT"] = "è£…ç­‰"
L["ONLINE"] = "åœ¨çº¿"
L["TIME_LESS_THAN_MINUTE"] = "< 1 åˆ†é’Ÿå‰"
L["TIME_MINUTES_FORMAT"] = "%d åˆ†é’Ÿå‰"
L["TIME_HOURS_FORMAT"] = "%d å°æ—¶å‰"
L["TIME_DAYS_FORMAT"] = "%d å¤©å‰"
L["REMOVE_FROM_FAVORITES"] = "ä»æ”¶è—ä¸­ç§»é™¤"
L["ADD_TO_FAVORITES"] = "æ·»åŠ åˆ°æ”¶è—"
L["FAVORITES_TOOLTIP"] = "æ”¶è—è§’è‰²æ˜¾ç¤ºåœ¨åˆ—è¡¨é¡¶éƒ¨"
L["CLICK_TO_TOGGLE"] = "ç‚¹å‡»åˆ‡æ¢"
L["UNKNOWN_PROFESSION"] = "æœªçŸ¥ä¸“ä¸š"
L["POINTS_SHORT"] = " ç‚¹"
L["TRACKING_ACTIVE_DESC"] = "æ•°æ®æ”¶é›†å’Œæ›´æ–°å·²æ¿€æ´»ã€‚"
L["TRACKING_ENABLED"] = "è¿½è¸ªå·²å¯ç”¨"
L["TRACKING_NOT_ENABLED_TOOLTIP"] = "è§’è‰²è¿½è¸ªå·²ç¦ç”¨ã€‚ç‚¹å‡»æ‰“å¼€è§’è‰²æ ‡ç­¾é¡µã€‚"
L["TRACKING_BADGE_CLICK_HINT"] = "ç‚¹å‡»æ›´æ”¹è¿½è¸ªè®¾ç½®ã€‚"
L["TRACKING_TAB_LOCKED_TITLE"] = "è§’è‰²æœªè¢«è¿½è¸ª"
L["TRACKING_TAB_LOCKED_DESC"] = "æ­¤æ ‡ç­¾é¡µä»…é€‚ç”¨äºå·²è¿½è¸ªçš„è§’è‰²ã€‚\nè¯·åœ¨è§’è‰²é¡µé¢ä½¿ç”¨è¿½è¸ªå›¾æ ‡å¯ç”¨è¿½è¸ªã€‚"
L["OPEN_CHARACTERS_TAB"] = "æ‰“å¼€è§’è‰²"
L["DELETE_CHARACTER_TITLE"] = "åˆ é™¤è§’è‰²ï¼Ÿ"
L["THIS_CHARACTER"] = "æ­¤è§’è‰²"
L["DELETE_CHARACTER"] = "åˆ é™¤æ‰€é€‰è§’è‰²"
L["REMOVE_FROM_TRACKING_FORMAT"] = "å°† %s ä»è¿½è¸ªä¸­ç§»é™¤"
L["CLICK_TO_DELETE"] = "ç‚¹å‡»åˆ é™¤"
L["CONFIRM_DELETE"] = "ç¡®å®šè¦åˆ é™¤ |cff00ccff%s|rï¼Ÿ"
L["CANNOT_UNDO"] = "æ­¤æ“ä½œæ— æ³•æ’¤é”€ï¼"

-- Items Tab (extended)
L["PERSONAL_ITEMS"] = "ä¸ªäººç‰©å“"
L["ITEMS_SUBTITLE"] = "æµè§ˆä½ çš„æˆ˜å›¢é“¶è¡Œã€å…¬ä¼šé“¶è¡Œå’Œä¸ªäººç‰©å“"
L["ITEMS_DISABLED_TITLE"] = "æˆ˜å›¢é“¶è¡Œç‰©å“"
L["ITEMS_LOADING"] = "æ­£åœ¨åŠ è½½èƒŒåŒ…æ•°æ®"
L["GUILD_BANK_REQUIRED"] = "ä½ å¿…é¡»åŠ å…¥å…¬ä¼šæ‰èƒ½è®¿é—®å…¬ä¼šé“¶è¡Œã€‚"
L["GUILD_JOINED_FORMAT"] = "å…¬ä¼šå·²æ›´æ–°ï¼š%s"
L["GUILD_LEFT"] = "ä½ å·²ç¦»å¼€å…¬ä¼šã€‚å…¬ä¼šé“¶è¡Œæ ‡ç­¾é¡µå·²ç¦ç”¨ã€‚"
L["NOT_IN_GUILD"] = "æœªåŠ å…¥å…¬ä¼š"
L["ITEMS_SEARCH"] = "æœç´¢ç‰©å“..."
L["NEVER"] = "ä»æœª"
L["ITEM_FALLBACK_FORMAT"] = "ç‰©å“ %s"
L["ITEM_LOADING_NAME"] = "åŠ è½½ä¸­..."
L["TAB_FORMAT"] = "æ ‡ç­¾é¡µ %d"
L["BAG_FORMAT"] = "èƒŒåŒ… %d"
L["BANK_BAG_FORMAT"] = "é“¶è¡ŒèƒŒåŒ… %d"
L["ITEM_ID_LABEL"] = "ç‰©å“ IDï¼š"
L["STACK_LABEL"] = "å †å ï¼š"
L["RIGHT_CLICK_MOVE"] = "ç§»è‡³èƒŒåŒ…"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "æ‹†åˆ†å †å "
L["LEFT_CLICK_PICKUP"] = "æ‹¾å–"
L["ITEMS_BANK_NOT_OPEN"] = "é“¶è¡Œæœªæ‰“å¼€"
L["SHIFT_LEFT_CLICK_LINK"] = "åœ¨èŠå¤©ä¸­é“¾æ¥"
L["ITEMS_STATS_ITEMS"] = "%s ä»¶ç‰©å“"
L["ITEMS_STATS_SLOTS"] = "%s/%s æ ¼å­"
L["ITEMS_STATS_LAST"] = "ä¸Šæ¬¡ï¼š%s"

-- Storage Tab (extended)
L["STORAGE_DISABLED_TITLE"] = "è§’è‰²å­˜å‚¨"
L["STORAGE_SEARCH"] = "æœç´¢å­˜å‚¨..."

-- PvE Tab (extended)
L["PVE_TITLE"] = "PvE è¿›åº¦"
L["PVE_SUBTITLE"] = "å®ä¼Ÿå®åº“ã€å›¢é˜Ÿå‰¯æœ¬é”å®šä¸å²è¯—é’¥çŸ³ï¼Œè¦†ç›–ä½ çš„æˆ˜å›¢"
L["PVE_CREST_ADV"] = "å†’é™©è€…"
L["PVE_CREST_VET"] = "è€å…µ"
L["PVE_CREST_CHAMP"] = "å‹‡å£«"
L["PVE_CREST_HERO"] = "è‹±é›„"
L["PVE_CREST_MYTH"] = "ç¥è¯"
L["PVE_CREST_EXPLORER"] = "æ¢ç´¢è€…"
L["PVE_COL_COFFER_SHARDS"] = "å®åŒ£é’¥åŒ™ç¢ç‰‡"
L["PVE_COL_RESTORED_KEY"] = "ä¿®å¤çš„å®åŒ£é’¥åŒ™"
L["LV_FORMAT"] = "ç­‰çº§ %d"
L["ILVL_FORMAT"] = "è£…ç­‰ %d"
L["VAULT_WORLD"] = "ä¸–ç•Œ"
L["VAULT_SLOT_FORMAT"] = "%s æ  %d"
L["OVERALL_SCORE_LABEL"] = "æ€»è¯„åˆ†ï¼š"
L["NOT_COMPLETED_SEASON"] = "æœ¬å­£æœªå®Œæˆ"
L["LOADING_PVE"] = "æ­£åœ¨åŠ è½½ PvE æ•°æ®..."
L["NO_VAULT_DATA"] = "æ— å®åº“æ•°æ®"
L["NO_DATA"] = "æ— æ•°æ®"
L["KEYSTONE"] = "é’¥çŸ³"
L["NO_KEY"] = "æ— é’¥çŸ³"
L["AFFIXES"] = "è¯ç¼€"
L["NO_AFFIXES"] = "æ— è¯ç¼€"
L["VAULT_BEST_KEY"] = "æœ€ä½³é’¥çŸ³ï¼š"
L["VAULT_SCORE"] = "è¯„åˆ†ï¼š"

-- Vault Tooltip (detailed)
L["VAULT_COMPLETED_ACTIVITIES"] = "å·²å®Œæˆ"
L["VAULT_CLICK_TO_OPEN"] = "ç‚¹å‡»æ‰“å¼€å®ä¼Ÿå®åº“"
L["VAULT_REWARD"] = "å¥–åŠ±"
L["VAULT_DUNGEONS"] = "åœ°ä¸‹åŸ"
L["VAULT_BOSS_KILLS"] = "é¦–é¢†å‡»æ€"
L["VAULT_WORLD_ACTIVITIES"] = "ä¸–ç•Œæ´»åŠ¨"
L["VAULT_ACTIVITIES"] = "æ´»åŠ¨"
L["VAULT_REMAINING_SUFFIX"] = "å‰©ä½™"
L["VAULT_IMPROVE_TO"] = "æå‡è‡³"
L["VAULT_COMPLETE_ON"] = "åœ¨ %s ä¸Šå®Œæˆæ­¤æ´»åŠ¨"
L["VAULT_ENCOUNTER_LIST_FORMAT"] = "%s"
L["VAULT_TOP_RUNS_FORMAT"] = "æœ¬å‘¨å‰ %d æ¬¡è®°å½•"
L["VAULT_DELVE_TIER_FORMAT"] = "å±‚çº§ %dï¼ˆ%dï¼‰"
L["VAULT_UNLOCK_REWARD"] = "è§£é”å¥–åŠ±"
L["VAULT_COMPLETE_MORE_FORMAT"] = "æœ¬å‘¨å†å®Œæˆ %d ä¸ª %s ä»¥è§£é”ã€‚"
L["VAULT_BASED_ON_FORMAT"] = "æ­¤å¥–åŠ±çš„ç‰©å“ç­‰çº§å°†åŸºäºæœ¬å‘¨å‰ %d æ¬¡è®°å½•ä¸­çš„æœ€ä½å€¼ï¼ˆå½“å‰ %sï¼‰ã€‚"
L["VAULT_RAID_BASED_FORMAT"] = "å¥–åŠ±åŸºäºå·²å‡»è´¥çš„æœ€é«˜éš¾åº¦ï¼ˆå½“å‰ %sï¼‰ã€‚"

-- Delves Section (PvE Tab)
L["BOUNTIFUL_DELVE"] = "çå®çŒæ‰‹çš„å¥–èµ"
L["PVE_BOUNTY_NEED_LOGIN"] = "è¯¥è§’è‰²æ²¡æœ‰ä¿å­˜çš„çŠ¶æ€ã€‚è¯·ç™»å½•ä»¥åˆ·æ–°ã€‚"
L["SEASON"] = "èµ›å­£"
L["CURRENCY_LABEL_WEEKLY"] = "æ¯å‘¨"

-- Reputation Tab (extended)
L["REP_TITLE"] = "å£°æœ›æ¦‚è§ˆ"
L["REP_SUBTITLE"] = "è¿½è¸ªä½ æˆ˜å›¢ä¸­çš„é˜µè¥å’Œåæœ›"
L["REP_DISABLED_TITLE"] = "å£°æœ›è¿½è¸ª"
L["REP_LOADING_TITLE"] = "æ­£åœ¨åŠ è½½å£°æœ›æ•°æ®"
L["REP_SEARCH"] = "æœç´¢å£°æœ›..."
L["REP_PARAGON_TITLE"] = "å·…å³°å£°æœ›"
L["REP_REWARD_AVAILABLE"] = "å¥–åŠ±å¯ç”¨ï¼"
L["REP_CONTINUE_EARNING"] = "ç»§ç»­è·å–å£°æœ›ä»¥è·å¾—å¥–åŠ±"
L["REP_CYCLES_FORMAT"] = "å‘¨æœŸï¼š%d"
L["REP_PROGRESS_HEADER"] = "è¿›åº¦ï¼š%d/%d"
L["REP_PARAGON_PROGRESS"] = "å·…å³°è¿›åº¦ï¼š"
L["REP_CYCLES_COLON"] = "å‘¨æœŸï¼š"
L["REP_CHARACTER_PROGRESS"] = "è§’è‰²è¿›åº¦ï¼š"
L["REP_RENOWN_FORMAT"] = "åæœ› %d"
L["REP_PARAGON_FORMAT"] = "å·…å³°ï¼ˆ%sï¼‰"
L["REP_UNKNOWN_FACTION"] = "æœªçŸ¥é˜µè¥"
L["REP_API_UNAVAILABLE_TITLE"] = "å£°æœ› API ä¸å¯ç”¨"
L["REP_API_UNAVAILABLE_DESC"] = "æ­¤æœåŠ¡å™¨ä¸Š C_Reputation API ä¸å¯ç”¨ã€‚æ­¤åŠŸèƒ½éœ€è¦ WoW 12.0.1ï¼ˆMidnightï¼‰ã€‚"
L["REP_FOOTER_TITLE"] = "å£°æœ›è¿½è¸ª"
L["REP_FOOTER_DESC"] = "å£°æœ›åœ¨ç™»å½•å’Œå˜æ›´æ—¶è‡ªåŠ¨æ‰«æã€‚ä½¿ç”¨æ¸¸æˆå†…å£°æœ›é¢æ¿æŸ¥çœ‹è¯¦ç»†ä¿¡æ¯å’Œå¥–åŠ±ã€‚"
L["REP_CLEARING_CACHE"] = "æ­£åœ¨æ¸…é™¤ç¼“å­˜å¹¶é‡æ–°åŠ è½½..."
L["REP_MAX"] = "æœ€å¤§"
L["ACCOUNT_WIDE_LABEL"] = "è´¦å·é€šç”¨"
L["NO_RESULTS"] = "æ— ç»“æœ"
L["NO_ACCOUNT_WIDE_REPS"] = "æ— è´¦å·é€šç”¨å£°æœ›"
L["NO_CHARACTER_REPS"] = "æ— è§’è‰²å£°æœ›"

-- Currency Tab (extended)
L["GOLD_LABEL"] = "é‡‘å¸"
L["CURRENCY_TITLE"] = "è´§å¸è¿½è¸ª"
L["CURRENCY_SUBTITLE"] = "è¿½è¸ªæ‰€æœ‰è§’è‰²çš„è´§å¸"
L["CURRENCY_DISABLED_TITLE"] = "è´§å¸è¿½è¸ª"
L["CURRENCY_LOADING_TITLE"] = "æ­£åœ¨åŠ è½½è´§å¸æ•°æ®"
L["CURRENCY_SEARCH"] = "æœç´¢è´§å¸..."
L["CURRENCY_HIDE_EMPTY"] = "éšè—ç©º"
L["CURRENCY_SHOW_EMPTY"] = "æ˜¾ç¤ºç©º"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "å…¨éƒ¨æˆ˜å›¢å¯è½¬ç§»"
L["CURRENCY_CHARACTER_SPECIFIC"] = "è§’è‰²ä¸“å±è´§å¸"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "è´§å¸è½¬ç§»é™åˆ¶"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "æš´é›ª API ä¸æ”¯æŒè‡ªåŠ¨è´§å¸è½¬ç§»ã€‚è¯·ä½¿ç”¨æ¸¸æˆå†…è´§å¸çª—å£æ‰‹åŠ¨è½¬ç§»æˆ˜å›¢è´§å¸ã€‚"
L["CURRENCY_UNKNOWN"] = "æœªçŸ¥è´§å¸"

-- Plans Tab (extended)
L["REMOVE_COMPLETED_TOOLTIP"] = "ä»æˆ‘çš„è®¡åˆ’åˆ—è¡¨ä¸­ç§»é™¤æ‰€æœ‰å·²å®Œæˆè®¡åˆ’ã€‚æ­¤æ“ä½œæ— æ³•æ’¤é”€ï¼"
L["RECIPE_BROWSER_DESC"] = "åœ¨æ¸¸æˆä¸­æ‰“å¼€ä¸“ä¸šçª—å£æµè§ˆé…æ–¹ã€‚\nçª—å£æ‰“å¼€æ—¶æ’ä»¶å°†æ‰«æå¯ç”¨é…æ–¹ã€‚"
L["SOURCE_ACHIEVEMENT_FORMAT"] = "%s |cff00ff00[%s %s]|r"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s å·²æœ‰æ´»è·ƒçš„æ¯å‘¨å®åº“è®¡åˆ’ã€‚å¯åœ¨ã€Œæˆ‘çš„è®¡åˆ’ã€åˆ†ç±»ä¸­æ‰¾åˆ°ã€‚"
L["DAILY_PLAN_EXISTS_DESC"] = "%s å·²æœ‰æ´»è·ƒçš„æ¯æ—¥ä»»åŠ¡è®¡åˆ’ã€‚å¯åœ¨ã€Œæ—¥å¸¸ä»»åŠ¡ã€åˆ†ç±»ä¸­æ‰¾åˆ°ã€‚"
L["TRANSMOG_WIP_DESC"] = "å¹»åŒ–æ”¶è—è¿½è¸ªæ­£åœ¨å¼€å‘ä¸­ã€‚\n\næ­¤åŠŸèƒ½å°†åœ¨æœªæ¥æ›´æ–°ä¸­æä¾›ï¼Œå…·æœ‰æ›´å¥½çš„æ€§èƒ½å’Œä¸æˆ˜å›¢ç³»ç»Ÿçš„é›†æˆã€‚"
L["WEEKLY_VAULT_CARD"] = "æ¯å‘¨å®åº“å¡ç‰‡"
L["WEEKLY_VAULT_COMPLETE"] = "æ¯å‘¨å®åº“å¡ç‰‡ - å®Œæˆ"
L["UNKNOWN_SOURCE"] = "æœªçŸ¥æ¥æº"
L["DAILY_TASKS_PREFIX"] = "æ¯å‘¨è¿›åº¦ - "
L["COMPLETE_LABEL"] = "å·²å®Œæˆ"
L["PLANS_COUNT_FORMAT"] = "%d ä¸ªè®¡åˆ’"
L["QUEST_LABEL"] = "ä»»åŠ¡ï¼š"

-- Settings Tab
L["CURRENT_LANGUAGE"] = "å½“å‰è¯­è¨€ï¼š"
L["LANGUAGE_TOOLTIP"] = "æ’ä»¶è‡ªåŠ¨ä½¿ç”¨ä½ çš„ WoW æ¸¸æˆå®¢æˆ·ç«¯è¯­è¨€ã€‚è¦æ›´æ”¹ï¼Œè¯·æ›´æ–°ä½ çš„æˆ˜ç½‘è®¾ç½®ã€‚"
L["NOTIFICATION_DURATION"] = "é€šçŸ¥æŒç»­æ—¶é—´"
L["NOTIFICATION_POSITION"] = "é€šçŸ¥ä½ç½®"
L["SET_POSITION"] = "è®¾ç½®ä½ç½®"
L["SET_BOTH_POSITION"] = "è®¾ç½®ä¸¤å¤„ä½ç½®"
L["DRAG_TO_POSITION"] = "æ‹–åŠ¨ä»¥è®¾ç½®ä½ç½®\nå³é”®ç¡®è®¤"
L["RESET_DEFAULT"] = "é‡ç½®ä¸ºé»˜è®¤"
L["RESET_POSITION"] = "é‡ç½®ä½ç½®"
L["TEST_NOTIFICATION"] = "æµ‹è¯•é€šçŸ¥"
L["CUSTOM_COLOR"] = "è‡ªå®šä¹‰é¢œè‰²"
L["OPEN_COLOR_PICKER"] = "æ‰“å¼€é¢œè‰²é€‰æ‹©å™¨"
L["COLOR_PICKER_TOOLTIP"] = "æ‰“å¼€ WoW åŸç”Ÿé¢œè‰²é€‰æ‹©å™¨é€‰æ‹©è‡ªå®šä¹‰ä¸»é¢˜è‰²"
L["PRESET_THEMES"] = "é¢„è®¾ä¸»é¢˜"
L["WARBAND_NEXUS_SETTINGS"] = "Warband Nexus è®¾ç½®"
L["NO_OPTIONS"] = "æ— é€‰é¡¹"
L["TAB_FILTERING"] = "æ ‡ç­¾é¡µç­›é€‰"
L["SCROLL_SPEED"] = "æ»šåŠ¨é€Ÿåº¦"
L["ANCHOR_FORMAT"] = "é”šç‚¹ï¼š%s  |  Xï¼š%d  |  Yï¼š%d"
L["USE_ALERTFRAME_POSITION"] = "ä½¿ç”¨ AlertFrame ä½ç½®"
L["USE_ALERTFRAME_POSITION_ACTIVE"] = "æ­£åœ¨ä½¿ç”¨æš´é›ª AlertFrame ä½ç½®"
L["NOTIFICATION_GHOST_MAIN"] = "æˆå°± / é€šçŸ¥"
L["NOTIFICATION_GHOST_CRITERIA"] = "æ ‡å‡†è¿›åº¦"
L["SHOW_WEEKLY_PLANNER"] = "æ¯å‘¨è®¡åˆ’ï¼ˆè§’è‰²ï¼‰"
L["LOCK_MINIMAP_ICON"] = "é”å®šå°åœ°å›¾æŒ‰é’®"
L["BACKPACK_LABEL"] = "èƒŒåŒ…"
L["REAGENT_LABEL"] = "ææ–™"

-- Shared Widgets & Dialogs
L["MODULE_DISABLED"] = "æ¨¡å—å·²ç¦ç”¨"
L["LOADING"] = "åŠ è½½ä¸­..."
L["PLEASE_WAIT"] = "è¯·ç¨å€™..."
L["RESET_PREFIX"] = "é‡ç½®ï¼š"
L["SAVE"] = "ä¿å­˜"
L["CREATE_CUSTOM_PLAN"] = "åˆ›å»ºè‡ªå®šä¹‰è®¡åˆ’"
L["REPORT_BUGS"] = "åœ¨ CurseForge ä¸ŠæŠ¥å‘Šé—®é¢˜æˆ–åˆ†äº«å»ºè®®ä»¥å¸®åŠ©æ”¹è¿›æ’ä»¶ã€‚"
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus æä¾›é›†ä¸­å¼ç•Œé¢ï¼Œç”¨äºç®¡ç†ä½ çš„æ‰€æœ‰è§’è‰²ã€è´§å¸ã€å£°æœ›ã€ç‰©å“å’Œæˆ˜å›¢å†…çš„ PvE è¿›åº¦ã€‚"
L["CHARACTERS_DESC"] = "æŸ¥çœ‹æ‰€æœ‰è§’è‰²çš„é‡‘å¸ã€ç­‰çº§ã€è£…ç­‰ã€é˜µè¥ã€ç§æ—ã€èŒä¸šã€ä¸“ä¸šã€é’¥çŸ³å’Œæœ€åç™»å½•ä¿¡æ¯ã€‚è¿½è¸ªæˆ–å–æ¶ˆè¿½è¸ªè§’è‰²ï¼Œæ ‡è®°æ”¶è—ã€‚"
L["ITEMS_DESC"] = "æœç´¢å’Œæµè§ˆæ‰€æœ‰èƒŒåŒ…ã€é“¶è¡Œå’Œæˆ˜å›¢é“¶è¡Œä¸­çš„ç‰©å“ã€‚æ‰“å¼€é“¶è¡Œæ—¶è‡ªåŠ¨æ‰«æã€‚é€šè¿‡æç¤ºæ˜¾ç¤ºæ¯ä¸ªè§’è‰²æ‹¥æœ‰çš„ç‰©å“ã€‚"
L["STORAGE_DESC"] = "æ‰€æœ‰è§’è‰²çš„èšåˆèƒŒåŒ…è§†å›¾â€”â€”èƒŒåŒ…ã€ä¸ªäººé“¶è¡Œå’Œæˆ˜å›¢é“¶è¡Œåˆè€Œä¸ºä¸€ã€‚"
L["PVE_DESC"] = "è¿½è¸ªå®ä¼Ÿå®åº“è¿›åº¦ã€ä¸‹ä¸€çº§æŒ‡æ ‡ã€å²è¯—é’¥çŸ³è¯„åˆ†å’Œé’¥çŸ³ã€é’¥çŸ³è¯ç¼€ã€åœ°ä¸‹åŸå†å²å’Œæ‰€æœ‰è§’è‰²çš„å‡çº§è´§å¸ã€‚"
L["REPUTATIONS_DESC"] = "æ¯”è¾ƒæ‰€æœ‰è§’è‰²çš„å£°æœ›è¿›åº¦ã€‚æ˜¾ç¤ºè´¦å·é€šç”¨ä¸è§’è‰²ä¸“å±é˜µè¥ï¼Œæ‚¬åœæç¤ºæ˜¾ç¤ºæ¯è§’è‰²æ˜ç»†ã€‚"
L["CURRENCY_DESC"] = "æŒ‰èµ„æ–™ç‰‡æŸ¥çœ‹æ‰€æœ‰è´§å¸ã€‚é€šè¿‡æ‚¬åœæç¤ºæ¯”è¾ƒå„è§’è‰²æ•°é‡ã€‚ä¸€é”®éšè—ç©ºè´§å¸ã€‚"
L["PLANS_DESC"] = "è¿½è¸ªæœªæ”¶é›†çš„åéª‘ã€å® ç‰©ã€ç©å…·ã€æˆå°±å’Œå¹»åŒ–ã€‚æ·»åŠ ç›®æ ‡ã€æŸ¥çœ‹æ‰è½æ¥æºã€ç›‘æ§å°è¯•æ¬¡æ•°ã€‚é€šè¿‡ /wn plan æˆ–å°åœ°å›¾å›¾æ ‡è®¿é—®ã€‚"
L["STATISTICS_DESC"] = "æŸ¥çœ‹æˆå°±ç‚¹æ•°ã€åéª‘/å® ç‰©/ç©å…·/å¹»è±¡/å¤´è¡”æ”¶è—è¿›åº¦ã€ç‹¬ç‰¹å® ç‰©æ•°é‡å’ŒèƒŒåŒ…/é“¶è¡Œä½¿ç”¨ç»Ÿè®¡ã€‚"

-- PvE Difficulty Names
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "ç¬¬ %d çº§"
L["PREPARING"] = "å‡†å¤‡ä¸­"

-- Statistics Tab (extended)
L["ACCOUNT_STATISTICS"] = "è´¦å·ç»Ÿè®¡"
L["STATISTICS_SUBTITLE"] = "æ”¶è—è¿›åº¦ã€é‡‘å¸å’Œå­˜å‚¨æ¦‚è§ˆ"
L["WARBAND_WEALTH"] = "æˆ˜å›¢è´¢å¯Œ"
L["WARBAND_BANK"] = "æˆ˜å›¢é“¶è¡Œ"
L["MOST_PLAYED"] = "æœ€å¸¸æ¸¸ç©"
L["PLAYED_DAYS"] = "å¤©"
L["PLAYED_HOURS"] = "å°æ—¶"
L["PLAYED_MINUTES"] = "åˆ†é’Ÿ"
L["PLAYED_DAY"] = "å¤©"
L["PLAYED_HOUR"] = "å°æ—¶"
L["PLAYED_MINUTE"] = "åˆ†é’Ÿ"
L["MORE_CHARACTERS"] = "æ›´å¤šè§’è‰²"
L["MORE_CHARACTERS_PLURAL"] = "æ›´å¤šè§’è‰²"

-- Information Dialog (extended)
L["WELCOME_TITLE"] = "æ¬¢è¿ä½¿ç”¨ Warband Nexusï¼"
L["ADDON_OVERVIEW_TITLE"] = "æ’ä»¶æ¦‚è§ˆ"

-- Plans UI (extended)
L["PLANS_SUBTITLE_TEXT"] = "è¿½è¸ªä½ çš„æ¯å‘¨ç›®æ ‡å’Œæ”¶è—"
L["ACTIVE_PLAN_FORMAT"] = "%d ä¸ªæ´»è·ƒè®¡åˆ’"
L["ACTIVE_PLANS_FORMAT"] = "%d ä¸ªæ´»è·ƒè®¡åˆ’"

-- Plans - Type Names
L["TYPE_RECIPE"] = "é…æ–¹"
L["TYPE_ILLUSION"] = "å¹»è±¡"
L["TYPE_TITLE"] = "å¤´è¡”"
L["TYPE_CUSTOM"] = "è‡ªå®šä¹‰"

-- Plans - Source Type Labels
L["SOURCE_TYPE_TRADING_POST"] = "è´¸æ˜“ç«™"
L["SOURCE_TYPE_TREASURE"] = "å®è—"
L["SOURCE_TYPE_PUZZLE"] = "è°œé¢˜"
L["SOURCE_TYPE_RENOWN"] = "åæœ›"

-- Plans - Source Text Parsing Keywords
L["PARSE_SOLD_BY"] = "å‡ºå”®è€…"
L["PARSE_CRAFTED"] = "åˆ¶é€ "
L["PARSE_COST"] = "èŠ±è´¹"
L["PARSE_HOLIDAY"] = "èŠ‚æ—¥"
L["PARSE_RATED"] = "è¯„çº§"
L["PARSE_BATTLEGROUND"] = "æˆ˜åœº"
L["PARSE_DISCOVERY"] = "å‘ç°"
L["PARSE_CONTAINED_IN"] = "åŒ…å«äº"
L["PARSE_GARRISON"] = "è¦å¡"
L["PARSE_GARRISON_BUILDING"] = "è¦å¡å»ºç­‘"
L["PARSE_STORE"] = "å•†åº—"
L["PARSE_ORDER_HALL"] = "èŒä¸šå¤§å…"
L["PARSE_COVENANT"] = "ç›Ÿçº¦"
L["PARSE_FRIENDSHIP"] = "å‹è°Š"
L["PARSE_PARAGON"] = "å·…å³°"
L["PARSE_MISSION"] = "ä»»åŠ¡"
L["PARSE_EXPANSION"] = "èµ„æ–™ç‰‡"
L["PARSE_SCENARIO"] = "åœºæ™¯æˆ˜å½¹"
L["PARSE_CLASS_HALL"] = "èŒä¸šå¤§å…"
L["PARSE_CAMPAIGN"] = "æˆ˜å½¹"
L["PARSE_EVENT"] = "æ´»åŠ¨"
L["PARSE_SPECIAL"] = "ç‰¹æ®Š"
L["PARSE_BRAWLERS_GUILD"] = "æå‡»ä¿±ä¹éƒ¨"
L["PARSE_CHALLENGE_MODE"] = "æŒ‘æˆ˜æ¨¡å¼"
L["PARSE_MYTHIC_PLUS"] = "å²è¯—é’¥çŸ³"
L["PARSE_TIMEWALKING"] = "æ—¶ç©ºæ¼«æ¸¸"
L["PARSE_ISLAND_EXPEDITION"] = "æµ·å²›æ¢é™©"
L["PARSE_WARFRONT"] = "æˆ˜äº‰å‰çº¿"
L["PARSE_TORGHAST"] = "æ‰˜åŠ æ–¯ç‰¹"
L["PARSE_ZERETH_MORTIS"] = "æ‰é›·æ®ææ–¯"
L["PARSE_HIDDEN"] = "éšè—"
L["PARSE_RARE"] = "ç¨€æœ‰"
L["PARSE_WORLD_BOSS"] = "ä¸–ç•Œé¦–é¢†"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "æ¥è‡ªæˆå°±"
L["FALLBACK_UNKNOWN_PET"] = "æœªçŸ¥å® ç‰©"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "å® ç‰©æ”¶è—"
L["FALLBACK_TOY_COLLECTION"] = "ç©å…·æ”¶è—"
L["FALLBACK_TOY_BOX"] = "ç©å…·ç®±"
L["FALLBACK_WARBAND_TOY"] = "æˆ˜å›¢ç©å…·"
L["FALLBACK_TRANSMOG_COLLECTION"] = "å¹»åŒ–æ”¶è—"
L["FALLBACK_PLAYER_TITLE"] = "ç©å®¶å¤´è¡”"
L["FALLBACK_ILLUSION_FORMAT"] = "å¹»è±¡ %s"
L["SOURCE_ENCHANTING"] = "é™„é­”"

-- Plans - Dialogs
L["RESET_COMPLETED_CONFIRM"] = "ç¡®å®šè¦ç§»é™¤æ‰€æœ‰å·²å®Œæˆè®¡åˆ’ï¼Ÿ\n\næ­¤æ“ä½œæ— æ³•æ’¤é”€ï¼"
L["YES_RESET"] = "æ˜¯ï¼Œé‡ç½®"
L["REMOVED_PLANS_FORMAT"] = "å·²ç§»é™¤ %d ä¸ªå·²å®Œæˆè®¡åˆ’ã€‚"

-- Plans - Buttons
L["ADD_CUSTOM"] = "æ·»åŠ è‡ªå®šä¹‰"
L["ADD_VAULT"] = "æ·»åŠ å®åº“"
L["ADD_QUEST"] = "æ·»åŠ ä»»åŠ¡"
L["CREATE_PLAN"] = "åˆ›å»ºè®¡åˆ’"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "æ¯æ—¥"
L["QUEST_CAT_WORLD"] = "ä¸–ç•Œ"
L["QUEST_CAT_WEEKLY"] = "æ¯å‘¨"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "æœªçŸ¥åˆ†ç±»"
L["SCANNING_FORMAT"] = "æ­£åœ¨æ‰«æ %s"
L["CUSTOM_PLAN_SOURCE"] = "è‡ªå®šä¹‰è®¡åˆ’"
L["POINTS_FORMAT"] = "%d ç‚¹"
L["SOURCE_NOT_AVAILABLE"] = "æ¥æºä¿¡æ¯ä¸å¯ç”¨"
L["PROGRESS_ON_FORMAT"] = "ä½ çš„è¿›åº¦ä¸º %d/%d"
L["COMPLETED_REQ_FORMAT"] = "ä½ å·²å®Œæˆ %d é¡¹ï¼Œå…± %d é¡¹è¦æ±‚"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "è‡³æš—ä¹‹å¤œ"
L["WEEKLY_RESET_LABEL"] = "æ¯å‘¨é‡ç½®"
L["QUEST_TYPE_WEEKLY"] = "æ¯å‘¨ä»»åŠ¡"
L["QUEST_CAT_CONTENT_EVENTS"] = "å†…å®¹äº‹ä»¶"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "å²è¯—é’¥çŸ³"

-- PlanCardFactory
L["FACTION_LABEL"] = "é˜µè¥ï¼š"
L["FRIENDSHIP_LABEL"] = "å‹è°Š"
L["RENOWN_TYPE_LABEL"] = "åæœ›"
L["ADD_BUTTON"] = "+ æ·»åŠ "
L["ADDED_LABEL"] = "å·²æ·»åŠ "

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s / %sï¼ˆ%s%%ï¼‰"

-- Settings - General Tooltips
L["SHOW_ITEM_COUNT_TOOLTIP"] = "åœ¨å­˜å‚¨å’Œç‰©å“è§†å›¾ä¸­æ˜¾ç¤ºç‰©å“å †å æ•°é‡"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "åœ¨è§’è‰²æ ‡ç­¾é¡µä¸­æ˜¾ç¤ºæˆ–éšè—æ¯å‘¨è®¡åˆ’éƒ¨åˆ†"
L["LOCK_MINIMAP_TOOLTIP"] = "é”å®šå°åœ°å›¾æŒ‰é’®ä½ç½®ï¼Œæ— æ³•æ‹–åŠ¨"
L["SCROLL_SPEED_TOOLTIP"] = "æ»šåŠ¨é€Ÿåº¦å€æ•°ï¼ˆ1.0x = æ¯æ­¥ 28 åƒç´ ï¼‰"
L["UI_SCALE"] = "ç•Œé¢ç¼©æ”¾"
L["UI_SCALE_TOOLTIP"] = "ç¼©æ”¾æ•´ä¸ªæ’ä»¶çª—å£ã€‚å¦‚æœçª—å£å ç”¨å¤ªå¤šç©ºé—´ï¼Œè¯·å‡å°æ­¤å€¼ã€‚"

-- Settings - Tab Filtering
L["IGNORE_WARBAND_TAB_FORMAT"] = "å¿½ç•¥æ ‡ç­¾é¡µ %d"
L["IGNORE_SCAN_FORMAT"] = "ä»è‡ªåŠ¨æ‰«æä¸­æ’é™¤ %s"

-- Settings - Notifications
L["ENABLE_NOTIFICATIONS"] = "å¯ç”¨æ‰€æœ‰é€šçŸ¥"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "ä¸»å¼€å…³â€”â€”ç¦ç”¨ä¸‹æ–¹æ‰€æœ‰å¼¹çª—é€šçŸ¥ã€èŠå¤©æé†’å’Œè§†è§‰æ•ˆæœ"
L["VAULT_REMINDER"] = "æ¯å‘¨å®åº“æé†’"
L["VAULT_REMINDER_TOOLTIP"] = "å½“ä½ æœ‰æœªé¢†å–çš„å®ä¼Ÿå®åº“å¥–åŠ±æ—¶ï¼Œç™»å½•æ—¶æ˜¾ç¤ºæé†’å¼¹çª—"
L["LOOT_ALERTS"] = "åéª‘/å® ç‰©/ç©å…·æˆ˜åˆ©å“æé†’"
L["LOOT_ALERTS_TOOLTIP"] = "å½“æ–°çš„åéª‘ã€å® ç‰©ã€ç©å…·æˆ–æˆå°±åŠ å…¥æ”¶è—æ—¶æ˜¾ç¤ºå¼¹çª—"
L["LOOT_ALERTS_MOUNT"] = "åéª‘é€šçŸ¥"
L["LOOT_ALERTS_MOUNT_TOOLTIP"] = "æ”¶é›†æ–°åéª‘æ—¶æ˜¾ç¤ºé€šçŸ¥"
L["LOOT_ALERTS_PET"] = "å® ç‰©é€šçŸ¥"
L["LOOT_ALERTS_PET_TOOLTIP"] = "æ”¶é›†æ–°å® ç‰©æ—¶æ˜¾ç¤ºé€šçŸ¥"
L["LOOT_ALERTS_TOY"] = "ç©å…·é€šçŸ¥"
L["LOOT_ALERTS_TOY_TOOLTIP"] = "æ”¶é›†æ–°ç©å…·æ—¶æ˜¾ç¤ºé€šçŸ¥"
L["LOOT_ALERTS_TRANSMOG"] = "å¤–è§‚é€šçŸ¥"
L["LOOT_ALERTS_TRANSMOG_TOOLTIP"] = "æ”¶é›†æ–°æŠ¤ç”²æˆ–æ­¦å™¨å¤–è§‚æ—¶æ˜¾ç¤ºé€šçŸ¥"
L["LOOT_ALERTS_ILLUSION"] = "å¹»è±¡é€šçŸ¥"
L["LOOT_ALERTS_ILLUSION_TOOLTIP"] = "æ”¶é›†æ–°æ­¦å™¨å¹»è±¡æ—¶æ˜¾ç¤ºé€šçŸ¥"
L["LOOT_ALERTS_TITLE"] = "å¤´è¡”é€šçŸ¥"
L["LOOT_ALERTS_TITLE_TOOLTIP"] = "è·å¾—æ–°å¤´è¡”æ—¶æ˜¾ç¤ºé€šçŸ¥"
L["LOOT_ALERTS_ACHIEVEMENT"] = "æˆå°±é€šçŸ¥"
L["LOOT_ALERTS_ACHIEVEMENT_TOOLTIP"] = "è·å¾—æ–°æˆå°±æ—¶æ˜¾ç¤ºé€šçŸ¥"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "æ›¿æ¢æˆå°±å¼¹çª—"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "ç”¨ Warband Nexus é€šçŸ¥æ ·å¼æ›¿æ¢æš´é›ªé»˜è®¤æˆå°±å¼¹çª—"
L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS"] = "æ ‡å‡†è¿›åº¦æç¤º"
L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS_TOOLTIP"] = "æˆå°±æ ‡å‡†å®Œæˆæ—¶æ˜¾ç¤ºå°æç¤ºï¼ˆè¿›åº¦ X/Y åŠæ ‡å‡†åç§°ï¼‰ã€‚"
L["CRITERIA_PROGRESS_MSG"] = "è¿›åº¦"
L["CRITERIA_PROGRESS_FORMAT"] = "è¿›åº¦ %d/%d"
L["CRITERIA_PROGRESS_CRITERION"] = "æ ‡å‡†"
L["ACHIEVEMENT_PROGRESS_TITLE"] = "æˆå°±è¿›åº¦"
L["REPUTATION_GAINS"] = "æ˜¾ç¤ºå£°æœ›è·å–"
L["REPUTATION_GAINS_TOOLTIP"] = "è·å¾—é˜µè¥å£°æœ›æ—¶åœ¨èŠå¤©ä¸­æ˜¾ç¤ºå£°æœ›è·å–æ¶ˆæ¯"
L["CURRENCY_GAINS"] = "æ˜¾ç¤ºè´§å¸è·å–"
L["CURRENCY_GAINS_TOOLTIP"] = "è·å¾—è´§å¸æ—¶åœ¨èŠå¤©ä¸­æ˜¾ç¤ºè´§å¸è·å–æ¶ˆæ¯"
L["SCREEN_FLASH_EFFECT"] = "ç¨€æœ‰æ‰è½é—ªçƒ"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "å¤šæ¬¡å°è¯•åç»ˆäºè·å¾—æ”¶è—å“æ—¶æ’­æ”¾å±å¹•é—ªçƒåŠ¨ç”»"
L["AUTO_TRY_COUNTER"] = "è‡ªåŠ¨è¿½è¸ªæ‰è½å°è¯•"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "æ‹¾å– NPCã€ç¨€æœ‰ã€é¦–é¢†ã€é’“é±¼æˆ–å®¹å™¨æ—¶è‡ªåŠ¨ç»Ÿè®¡å¤±è´¥æ‰è½å°è¯•ã€‚æ”¶è—å“æœ€ç»ˆæ‰è½æ—¶åœ¨å¼¹çª—ä¸­æ˜¾ç¤ºæ€»å°è¯•æ¬¡æ•°ã€‚"
L["SETTINGS_ESC_HINT"] = "æŒ‰ |cff999999ESC|r å…³é—­æ­¤çª—å£ã€‚"
L["HIDE_TRY_COUNTER_CHAT"] = "åœ¨èŠå¤©ä¸­éšè—å°è¯•æ¬¡æ•°"
L["HIDE_TRY_COUNTER_CHAT_TOOLTIP"] = "éšè—æ‰€æœ‰å°è¯•è®¡æ•°ç›¸å…³èŠå¤©æ¶ˆæ¯ï¼ˆ[WN-Counter]ã€[WN-Drops]ã€è·å¾—/é’“èµ·ç­‰ï¼‰ã€‚è®¡æ•°ä»åœ¨åå°è¿›è¡Œï¼›å¼¹çª—ä¸å±å¹•é—ªå…‰ä¸å—å½±å“ã€‚\n\nå¼€å¯æ—¶ï¼Œä¸‹æ–¹çš„â€œè¿›å…¥å‰¯æœ¬æ—¶åˆ—å‡ºæ‰è½â€ä¸èŠå¤©è·¯ç”±ç›¸å…³é€‰é¡¹å°†ç¦ç”¨ã€‚"
L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES"] = "è¿›å…¥å‰¯æœ¬æ—¶ï¼šåœ¨èŠå¤©ä¸­åˆ—å‡ºæ‰è½"
L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES_TOOLTIP"] = "è¿›å…¥å¸¦æœ‰å°è¯•è®¡æ•°æ”¶è—å“çš„åœ°ä¸‹åŸæˆ–å›¢é˜Ÿå‰¯æœ¬æ—¶ï¼Œä¸ºæ¯ä»¶ç‰©å“è¾“å‡ºä¸€è¡Œ |cff9370DB[WN-Drops]|rï¼šé“¾æ¥ â€” æ‰€éœ€éš¾åº¦ï¼ˆ|cff00ff00ç»¿è‰²|r ç¬¦åˆï¼Œ|cffff6666çº¢è‰²|r ä¸ç¬¦ï¼Œ|cffffaa00ç¥ç€è‰²|r æœªçŸ¥ï¼‰â€” å°è¯•æ¬¡æ•°æˆ–å·²æ”¶è—ã€‚å¤§å‹å‰¯æœ¬æœ€å¤š 18 è¡Œå¤–åŠ  |cff00ccff/wn check|rã€‚å…³é—­åˆ™ä»…æ˜¾ç¤ºç®€çŸ­æç¤ºã€‚"
L["TRYCOUNTER_CHAT_ROUTE_LABEL"] = "å°è¯•è®¡æ•°èŠå¤©è¾“å‡º"
L["TRYCOUNTER_CHAT_ROUTE_DESC"] = "å°è¯•è®¡æ•°çš„è¡Œè¾“å‡ºä½ç½®ã€‚é»˜è®¤ä¸â€œæ‹¾å–â€ç›¸åŒæ ‡ç­¾é¡µã€‚â€œWarband Nexusâ€ä½¿ç”¨ WN_TRYCOUNTER åˆ†ç»„ï¼ˆå¯åœ¨èŠå¤©æ ‡ç­¾è®¾ç½®ä¸­é€‰æ‹©ï¼‰ã€‚â€œæ‰€æœ‰æ ‡ç­¾â€å‘é€åˆ°æ¯ä¸ªç¼–å·èŠå¤©çª—å£ã€‚"
L["TRYCOUNTER_CHAT_ROUTE_LOOT"] = "1ï¼‰ä¸æ‹¾å–ç›¸åŒï¼ˆé»˜è®¤ï¼‰"
L["TRYCOUNTER_CHAT_ROUTE_DEDICATED"] = "2ï¼‰Warband Nexusï¼ˆç‹¬ç«‹è¿‡æ»¤ï¼‰"
L["TRYCOUNTER_CHAT_ROUTE_ALL_TABS"] = "3ï¼‰æ‰€æœ‰æ ‡å‡†èŠå¤©æ ‡ç­¾"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_BTN"] = "å°†å°è¯•è®¡æ•°æ·»åŠ åˆ°æ‰€é€‰èŠå¤©æ ‡ç­¾"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_TOOLTIP"] = "å…ˆç‚¹å‡»ç›®æ ‡èŠå¤©æ ‡ç­¾ï¼Œå†ç‚¹æ­¤å¤„ã€‚é€‚åˆâ€œWarband Nexusâ€æ¨¡å¼ã€‚ä¼šå‘è¯¥æ ‡ç­¾æ·»åŠ  WN_TRYCOUNTERã€‚"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_OK"] = "|cff9966ff[Warband Nexus]|r å·²åœ¨æ‰€é€‰èŠå¤©æ ‡ç­¾å¯ç”¨å°è¯•è®¡æ•°ã€‚"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_FAIL"] = "|cffff6600[Warband Nexus]|r æ— æ³•æ›´æ–°èŠå¤©æ ‡ç­¾ï¼ˆæ— èŠå¤©æ¡†æˆ– API è¢«é˜»æ­¢ï¼‰ã€‚"
L["DURATION_LABEL"] = "æŒç»­æ—¶é—´"
L["DAYS_LABEL"] = "å¤©"
L["WEEKS_LABEL"] = "å‘¨"
L["EXTEND_DURATION"] = "å»¶é•¿æŒç»­æ—¶é—´"

-- Settings - Position
L["DRAG_POSITION_MSG"] = "æ‹–åŠ¨ç»¿è‰²æ¡†ä»¥è®¾ç½®å¼¹çª—ä½ç½®ã€‚å³é”®ç¡®è®¤ã€‚"
L["DRAG_BOTH_POSITION_MSG"] = "æ‹–åŠ¨ä»¥å®šä½ã€‚å³é”®ä¿å­˜ä¸é€šçŸ¥å’Œæ ‡å‡†ç›¸åŒçš„ä½ç½®ã€‚"
L["POSITION_RESET_MSG"] = "å¼¹çª—ä½ç½®å·²é‡ç½®ä¸ºé»˜è®¤ï¼ˆé¡¶éƒ¨å±…ä¸­ï¼‰"
L["POSITION_SAVED_MSG"] = "å¼¹çª—ä½ç½®å·²ä¿å­˜ï¼"
L["TEST_NOTIFICATION_TITLE"] = "æµ‹è¯•é€šçŸ¥"
L["TEST_NOTIFICATION_MSG"] = "ä½ç½®æµ‹è¯•"
L["NOTIFICATION_DEFAULT_TITLE"] = "é€šçŸ¥"

-- Settings - Theme & Appearance
L["THEME_APPEARANCE"] = "ä¸»é¢˜ä¸å¤–è§‚"
L["COLOR_PURPLE"] = "ç´«è‰²ä¸»é¢˜"
L["COLOR_PURPLE_DESC"] = "ç»å…¸ç´«è‰²ä¸»é¢˜ï¼ˆé»˜è®¤ï¼‰"
L["COLOR_BLUE"] = "è“è‰²ä¸»é¢˜"
L["COLOR_BLUE_DESC"] = "å†·è‰²è“ä¸»é¢˜"
L["COLOR_GREEN"] = "ç»¿è‰²ä¸»é¢˜"
L["COLOR_GREEN_DESC"] = "è‡ªç„¶ç»¿ä¸»é¢˜"
L["COLOR_RED"] = "çº¢è‰²ä¸»é¢˜"
L["COLOR_RED_DESC"] = "ç«ç„°çº¢ä¸»é¢˜"
L["COLOR_ORANGE"] = "æ©™è‰²ä¸»é¢˜"
L["COLOR_ORANGE_DESC"] = "æ¸©æš–æ©™ä¸»é¢˜"
L["COLOR_CYAN"] = "é’è‰²ä¸»é¢˜"
L["COLOR_CYAN_DESC"] = "æ˜äº®é’ä¸»é¢˜"

-- Settings - Font
L["FONT_FAMILY"] = "å­—ä½“"
L["FONT_FAMILY_TOOLTIP"] = "é€‰æ‹©æ’ä»¶ç•Œé¢ä½¿ç”¨çš„å­—ä½“"
L["FONT_SCALE"] = "å­—ä½“ç¼©æ”¾"
L["FONT_SCALE_TOOLTIP"] = "è°ƒæ•´æ‰€æœ‰ç•Œé¢å…ƒç´ çš„å­—ä½“å¤§å°"
L["ANTI_ALIASING"] = "æŠ—é”¯é½¿"
L["ANTI_ALIASING_DESC"] = "å­—ä½“è¾¹ç¼˜æ¸²æŸ“æ ·å¼ï¼ˆå½±å“å¯è¯»æ€§ï¼‰"
L["FONT_SCALE_WARNING"] = "è­¦å‘Šï¼šè¾ƒé«˜çš„å­—ä½“ç¼©æ”¾å¯èƒ½å¯¼è‡´éƒ¨åˆ†ç•Œé¢å…ƒç´ æ–‡å­—æº¢å‡ºã€‚"
L["RESOLUTION_NORMALIZATION"] = "åˆ†è¾¨ç‡æ ‡å‡†åŒ–"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "æ ¹æ®å±å¹•åˆ†è¾¨ç‡å’Œç•Œé¢ç¼©æ”¾è°ƒæ•´å­—ä½“å¤§å°ï¼Œç¡®ä¿ä¸åŒæ˜¾ç¤ºå™¨ä¸Šçš„ç‰©ç†å°ºå¯¸ä¸€è‡´"

-- Settings - Advanced
L["ADVANCED_SECTION"] = "é«˜çº§"

-- Settings - Module Management
L["MODULE_MANAGEMENT"] = "æ¨¡å—ç®¡ç†"
L["MODULE_MANAGEMENT_DESC"] = "å¯ç”¨æˆ–ç¦ç”¨ç‰¹å®šæ•°æ®æ”¶é›†æ¨¡å—ã€‚ç¦ç”¨æ¨¡å—å°†åœæ­¢å…¶æ•°æ®æ›´æ–°å¹¶ä»ç•Œé¢éšè—å…¶æ ‡ç­¾é¡µã€‚"
L["MODULE_CURRENCIES"] = "è´§å¸"
L["MODULE_CURRENCIES_DESC"] = "è¿½è¸ªè´¦å·é€šç”¨å’Œè§’è‰²ä¸“å±è´§å¸ï¼ˆé‡‘å¸ã€è£èª‰ã€å¾æœç­‰ï¼‰"
L["MODULE_REPUTATIONS"] = "å£°æœ›"
L["MODULE_REPUTATIONS_DESC"] = "è¿½è¸ªé˜µè¥å£°æœ›è¿›åº¦ã€åæœ›ç­‰çº§å’Œå·…å³°å¥–åŠ±"
L["MODULE_ITEMS"] = "ç‰©å“"
L["MODULE_ITEMS_DESC"] = "è¿½è¸ªæˆ˜å›¢é“¶è¡Œç‰©å“ã€æœç´¢åŠŸèƒ½å’Œç‰©å“åˆ†ç±»"
L["MODULE_STORAGE"] = "å­˜å‚¨"
L["MODULE_STORAGE_DESC"] = "è¿½è¸ªè§’è‰²èƒŒåŒ…ã€ä¸ªäººé“¶è¡Œå’Œæˆ˜å›¢é“¶è¡Œå­˜å‚¨"
L["MODULE_PVE"] = "PvE"
L["MODULE_PVE_DESC"] = "è¿½è¸ªå²è¯—é’¥çŸ³åœ°ä¸‹åŸã€å›¢é˜Ÿå‰¯æœ¬è¿›åº¦å’Œæ¯å‘¨å®åº“å¥–åŠ±"
L["MODULE_PLANS"] = "å¾…åŠ"
L["MODULE_PLANS_DESC"] = "è¿½è¸ªåéª‘ã€å® ç‰©ã€ç©å…·ã€æˆå°±å’Œè‡ªå®šä¹‰ä»»åŠ¡çš„ä¸ªäººç›®æ ‡"
L["MODULE_PROFESSIONS"] = "ä¸“ä¸š"
L["MODULE_PROFESSIONS_DESC"] = "è¿½è¸ªä¸“ä¸šæŠ€èƒ½ã€ä¸“æ³¨ã€çŸ¥è¯†å’Œé…æ–¹åŠ©æ‰‹çª—å£"
L["MODULE_GEAR"] = "è£…å¤‡"
L["MODULE_GEAR_DESC"] = "è·¨è§’è‰²è£…å¤‡ç®¡ç†å’Œç‰©å“ç­‰çº§è¿½è¸ª"
L["MODULE_COLLECTIONS"] = "æ”¶è—"
L["MODULE_COLLECTIONS_DESC"] = "åéª‘ã€å® ç‰©ã€ç©å…·ã€å¹»åŒ–å’Œæ”¶è—æ¦‚è§ˆ"
L["MODULE_TRY_COUNTER"] = "å°è¯•è®¡æ•°å™¨"
L["MODULE_TRY_COUNTER_DESC"] = "è‡ªåŠ¨è¿½è¸ªNPCã€Bossã€é’“é±¼å’Œå®¹å™¨çš„æ‰è½å°è¯•ã€‚ç¦ç”¨å°†åœæ­¢æ‰€æœ‰è®¡æ•°å™¨å¤„ç†ã€æç¤ºå’Œé€šçŸ¥ã€‚"
L["PROFESSIONS_DISABLED_TITLE"] = "ä¸“ä¸š"

-- Tooltip Service
L["ITEM_NUMBER_FORMAT"] = "ç‰©å“ #%s"
L["WN_SEARCH"] = "WN æœç´¢"

-- Notification Manager
L["COLLECTED_MOUNT_MSG"] = "ä½ å·²æ”¶é›†åéª‘"
L["COLLECTED_PET_MSG"] = "ä½ å·²æ”¶é›†æˆ˜æ–—å® ç‰©"
L["COLLECTED_TOY_MSG"] = "ä½ å·²æ”¶é›†ç©å…·"
L["COLLECTED_ILLUSION_MSG"] = "ä½ å·²æ”¶é›†å¹»è±¡"
L["COLLECTED_ITEM_MSG"] = "ä½ è·å¾—äº†ç¨€æœ‰æ‰è½"
L["ACHIEVEMENT_COMPLETED_MSG"] = "æˆå°±å·²å®Œæˆï¼"
L["HIDDEN_ACHIEVEMENT"] = "éšè—æˆå°±"
L["EARNED_TITLE_MSG"] = "ä½ è·å¾—äº†å¤´è¡”"
L["COMPLETED_PLAN_MSG"] = "ä½ å·²å®Œæˆè®¡åˆ’"
L["DAILY_QUEST_CAT"] = "æ¯æ—¥ä»»åŠ¡"
L["WORLD_QUEST_CAT"] = "ä¸–ç•Œä»»åŠ¡"
L["WEEKLY_QUEST_CAT"] = "æ¯å‘¨ä»»åŠ¡"
L["SPECIAL_ASSIGNMENT_CAT"] = "ç‰¹æ®ŠæŒ‡æ´¾"
L["DELVE_CAT"] = "æ¢ç´¢"
L["WORLD_CAT"] = "ä¸–ç•Œ"
L["ACTIVITY_CAT"] = "æ´»åŠ¨"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d è¿›åº¦"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d è¿›åº¦å·²å®Œæˆ"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "æ¯å‘¨å®åº“è®¡åˆ’ - %s"
L["ALL_SLOTS_COMPLETE"] = "æ‰€æœ‰æ§½ä½å·²å®Œæˆï¼"
L["QUEST_COMPLETED_SUFFIX"] = "å·²å®Œæˆ"
L["WEEKLY_VAULT_READY"] = "æ¯å‘¨å®åº“å°±ç»ªï¼"
L["UNCLAIMED_REWARDS"] = "ä½ æœ‰æœªé¢†å–çš„å¥–åŠ±"
L["NOTIFICATION_FIRST_TRY"] = "ç¬¬ä¸€æ¬¡å°è¯•å°±è·å¾—äº†ï¼"
L["NOTIFICATION_GOT_IT_AFTER"] = "ç»è¿‡%dæ¬¡å°è¯•åè·å¾—ï¼"

-- Minimap Button
L["TOTAL_GOLD_LABEL"] = "æ€»é‡‘å¸ï¼š"
L["MINIMAP_CHARS_GOLD"] = "è§’è‰²é‡‘å¸ï¼š"
L["LEFT_CLICK_TOGGLE"] = "å·¦é”®ï¼šåˆ‡æ¢çª—å£"
L["RIGHT_CLICK_PLANS"] = "å³é”®ï¼šæ‰“å¼€è®¡åˆ’"
L["MINIMAP_SHOWN_MSG"] = "å°åœ°å›¾æŒ‰é’®å·²æ˜¾ç¤º"
L["MINIMAP_HIDDEN_MSG"] = "å°åœ°å›¾æŒ‰é’®å·²éšè—ï¼ˆä½¿ç”¨ /wn minimap æ˜¾ç¤ºï¼‰"
L["TOGGLE_WINDOW"] = "åˆ‡æ¢çª—å£"
L["SCAN_BANK_MENU"] = "æ‰«æé“¶è¡Œ"
L["TRACKING_DISABLED_SCAN_MSG"] = "è§’è‰²è¿½è¸ªå·²ç¦ç”¨ã€‚è¯·åœ¨è®¾ç½®ä¸­å¯ç”¨è¿½è¸ªä»¥æ‰«æé“¶è¡Œã€‚"
L["SCAN_COMPLETE_MSG"] = "æ‰«æå®Œæˆï¼"
L["BANK_NOT_OPEN_MSG"] = "é“¶è¡Œæœªæ‰“å¼€"
L["OPTIONS_MENU"] = "é€‰é¡¹"
L["HIDE_MINIMAP_BUTTON"] = "éšè—å°åœ°å›¾æŒ‰é’®"
L["MENU_UNAVAILABLE_MSG"] = "å³é”®èœå•ä¸å¯ç”¨"
L["USE_COMMANDS_MSG"] = "ä½¿ç”¨ /wn showã€/wn optionsã€/wn help"
L["MINIMAP_MORE_FORMAT"] = "... +%dæ›´å¤š"

-- SharedWidgets (extended)
L["DATA_SOURCE_TITLE"] = "æ•°æ®æºä¿¡æ¯"
L["DATA_SOURCE_USING"] = "æ­¤æ ‡ç­¾é¡µä½¿ç”¨ï¼š"
L["DATA_SOURCE_MODERN"] = "ç°ä»£ç¼“å­˜æœåŠ¡ï¼ˆäº‹ä»¶é©±åŠ¨ï¼‰"
L["DATA_SOURCE_LEGACY"] = "ä¼ ç»Ÿç›´æ¥æ•°æ®åº“è®¿é—®"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "éœ€è¦è¿ç§»åˆ°ç¼“å­˜æœåŠ¡"
L["GLOBAL_DB_VERSION"] = "å…¨å±€æ•°æ®åº“ç‰ˆæœ¬ï¼š"

-- Information Dialog - Tab Headers
L["INFO_TAB_CHARACTERS"] = "è§’è‰²"
L["INFO_TAB_ITEMS"] = "ç‰©å“"
L["INFO_TAB_STORAGE"] = "å­˜å‚¨"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "å£°æœ›"
L["INFO_TAB_CURRENCY"] = "è´§å¸"
L["INFO_TAB_PLANS"] = "å¾…åŠ"
L["INFO_TAB_GEAR"] = "è£…å¤‡"
L["INFO_TAB_COLLECTIONS"] = "æ”¶è—"
L["INFO_TAB_STATISTICS"] = "ç»Ÿè®¡"
L["INFO_CREDITS_SECTION_TITLE"] = "è‡´è°¢ä¸åå•"
L["INFO_CREDITS_LORE_SUBTITLE"] = "ç‰¹åˆ«é¸£è°¢"
L["INFO_FEATURES_SECTION_TITLE"] = "åŠŸèƒ½æ¦‚è§ˆ"
L["HEADER_INFO_TOOLTIP"] = "æ’ä»¶è¯´æ˜ä¸è‡´è°¢"
L["HEADER_INFO_TOOLTIP_HINT"] = "åŠŸèƒ½ä¸è´¡çŒ®è€… â€” åå•åœ¨é¡¶éƒ¨ã€‚"
L["CONTRIBUTORS_TITLE"] = "è´¡çŒ®è€…"
L["THANK_YOU_MSG"] = "æ„Ÿè°¢ä½¿ç”¨ Warband Nexusï¼"

-- Information Dialog - Professions Tab
L["INFO_TAB_PROFESSIONS"] = "ä¸“ä¸š"
L["PROFESSIONS_INFO_DESC"] = "è¿½è¸ªæ‰€æœ‰è§’è‰²çš„ä¸“ä¸šæŠ€èƒ½ã€ä¸“æ³¨ã€çŸ¥è¯†å’Œä¸“ç²¾æ ‘ã€‚åŒ…å«é…æ–¹åŠ©æ‰‹ç”¨äºææ–™æ¥æºã€‚"

-- Information Dialog - Gear & Collections Tabs
L["GEAR_DESC"] = "æŸ¥çœ‹å·²è£…å¤‡ã€å‡çº§æœºä¼šã€å­˜å‚¨æ¨èï¼ˆè£…ç»‘/æˆ˜å›¢ç»‘å®šï¼‰åŠè·¨è§’è‰²å‡çº§å€™é€‰ä¸è£…ç­‰è¿½è¸ªã€‚"
L["COLLECTIONS_DESC"] = "åéª‘ã€å® ç‰©ã€ç©å…·ã€å¹»åŒ–åŠå…¶ä»–æ”¶è—æ¦‚è§ˆã€‚è¿½è¸ªæ”¶è—è¿›åº¦å¹¶æŸ¥æ‰¾ç¼ºå¤±ç‰©å“ã€‚"

-- Command Help Strings
L["AVAILABLE_COMMANDS"] = "å¯ç”¨å‘½ä»¤ï¼š"
L["CMD_OPEN"] = "æ‰“å¼€æ’ä»¶çª—å£"
L["CMD_PLANS"] = "åˆ‡æ¢å¾…åŠè¿½è¸ªå™¨çª—å£"
L["CMD_FIRSTCRAFT"] = "æŒ‰èµ„æ–™ç‰‡åˆ—å‡ºé¦–æ¬¡åˆ¶ä½œå¥–åŠ±é…æ–¹ï¼ˆè¯·å…ˆæ‰“å¼€ä¸“ä¸šçª—å£ï¼‰"
L["CMD_OPTIONS"] = "æ‰“å¼€è®¾ç½®"
L["CMD_MINIMAP"] = "åˆ‡æ¢å°åœ°å›¾æŒ‰é’®"
L["CMD_CHANGELOG"] = "æ˜¾ç¤ºæ›´æ–°æ—¥å¿—"
L["CMD_DEBUG"] = "åˆ‡æ¢è°ƒè¯•æ¨¡å¼"
L["CMD_PROFILER"] = "æ€§èƒ½åˆ†æå™¨"
L["CMD_HELP"] = "æ˜¾ç¤ºæ­¤åˆ—è¡¨"
L["PLANS_NOT_AVAILABLE"] = "è®¡åˆ’è¿½è¸ªä¸å¯ç”¨ã€‚"
L["MINIMAP_NOT_AVAILABLE"] = "å°åœ°å›¾æŒ‰é’®æ¨¡å—æœªåŠ è½½ã€‚"
L["PROFILER_NOT_LOADED"] = "åˆ†æå™¨æ¨¡å—æœªåŠ è½½ã€‚"
L["UNKNOWN_COMMAND"] = "æœªçŸ¥å‘½ä»¤ã€‚"
L["TYPE_HELP"] = "è¾“å…¥"
L["FOR_AVAILABLE_COMMANDS"] = "æŸ¥çœ‹å¯ç”¨å‘½ä»¤ã€‚"
L["UNKNOWN_DEBUG_CMD"] = "æœªçŸ¥è°ƒè¯•å‘½ä»¤ï¼š"
L["DEBUG_ENABLED"] = "è°ƒè¯•æ¨¡å¼å·²å¯ç”¨ã€‚"
L["DEBUG_DISABLED"] = "è°ƒè¯•æ¨¡å¼å·²ç¦ç”¨ã€‚"
L["CHARACTER_LABEL"] = "è§’è‰²ï¼š"
L["TRACK_USAGE"] = "ç”¨æ³•ï¼šenable | disable | status"

-- Welcome Messages
L["CLICK_TO_COPY"] = "ç‚¹å‡»å¤åˆ¶é‚€è¯·é“¾æ¥"
L["WELCOME_MSG_FORMAT"] = "æ¬¢è¿ä½¿ç”¨ Warband Nexus v%s"
L["WELCOME_TYPE_CMD"] = "è¯·è¾“å…¥"
L["WELCOME_OPEN_INTERFACE"] = "ä»¥æ‰“å¼€ç•Œé¢ã€‚"
L["WELCOME_NEW_VERSION_CHAT"] = "|cffffff00æ›´æ–°å†…å®¹ï¼š|r å¯èƒ½ä¼šåœ¨èŠå¤©ä¸Šæ–¹å¼¹å‡ºçª—å£ï¼Œæˆ–è¾“å…¥ |cffffff00/wn changelog|rã€‚"
L["CONFIG_SHOW_LOGIN_CHAT"] = "åœ¨èŠå¤©ä¸­æ˜¾ç¤ºç™»å½•æç¤º"
L["CONFIG_SHOW_LOGIN_CHAT_DESC"] = "å¼€å¯é€šçŸ¥æ—¶æ‰“å°ä¸€è¡Œç®€çŸ­æ¬¢è¿è¯­ã€‚ä½¿ç”¨â€œç³»ç»Ÿâ€æ¶ˆæ¯ç»„ä¸å¯è§èŠå¤©æ ‡ç­¾ï¼ˆå¦‚ Chattynatorï¼‰ã€‚æ›´æ–°è¯´æ˜çª—å£ä¸ºç‹¬ç«‹å…¨å±å¼¹çª—ã€‚"
L["CONFIG_HIDE_PLAYED_TIME_CHAT"] = "åœ¨èŠå¤©ä¸­éšè—æ¸¸æˆæ—¶é—´"
L["CONFIG_HIDE_PLAYED_TIME_CHAT_DESC"] = "è¿‡æ»¤â€œæ€»æ¸¸æˆæ—¶é—´â€å’Œâ€œæœ¬ç­‰çº§æ¸¸æˆæ—¶é—´â€ç­‰ç³»ç»Ÿæ¶ˆæ¯ã€‚å…³é—­æœ¬é¡¹å¯å†æ¬¡æ˜¾ç¤ºï¼ˆåŒ…æ‹¬ /playedï¼‰ã€‚"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN"] = "ç™»å½•æ—¶è¯·æ±‚æ¸¸æˆæ—¶é—´"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN_DESC"] = "å¼€å¯æ—¶åœ¨åå°è¯·æ±‚ /played ä»¥æ›´æ–°â€œæ¸¸ç©æœ€å¤šâ€ç­‰ç»Ÿè®¡ï¼Œå¹¶éšè—èŠå¤©è¾“å‡ºã€‚å…³é—­åˆ™ç™»å½•æ—¶ä¸è‡ªåŠ¨è¯·æ±‚ï¼ˆä»å¯æ‰‹åŠ¨ /playedï¼‰ã€‚"

-- What's New (changelog)


L["CHANGELOG_V258"] = "v2.5.8\nä¿®å¤ï¼š\n- å°è¯•è®¡æ•°ï¼šCHAT_MSG_LOOT åœ¨é’“é±¼å½’å› è·¯å¾„ä¸Šä¸å†æŠ¥é”™ï¼ˆCurrentUnitsHaveMobLootContext å‰å‘å£°æ˜ï¼›æ­¤å‰ä¸º nil å…¨å±€ï¼‰ã€‚\n\nCurseForgeï¼šWarband Nexus"

L["CHANGELOG_V259"] = [=[v2.5.9ï¼ˆ2026-04-03ï¼‰

æ”¹è¿›
- æ”¶è— / å°è¯•è®¡æ•°ï¼šè¾¾è¨ç½—ä¹‹æˆ˜ â€” Glacial Tidestorm ä»…å‰å®‰å¨œå²è¯—ï¼ˆééšæœºå›¢ï¼‰ã€‚G.M.O.D.ï¼šéšæœºå›¢å‰å®‰å¨œï¼›æ™®é€š/è‹±é›„/å²è¯—å¤§å·¥åŒ ï¼ˆ2019 çƒ­ä¿®ï¼‰ã€‚æ˜¾å¼éšæœºå›¢ï¼›æŒ‰æ‰è½è¡Œ statisticIds é‡æ’­ç»Ÿè®¡ï¼›å¤§å·¥åŒ ä¸è®¡å‰å®‰å¨œéšæœºå›¢ï¼ˆ13379ï¼‰ã€‚
- CollectibleSourceDBï¼šåéª‘é¦–é¢† legacyEncounters å¯¹é½ Midnight DungeonEncounter IDã€‚
- Git ä»“åº“ï¼šä»…æ’ä»¶æºç ï¼ˆCoreã€Modulesã€Localesã€tocã€CHANGESã€LICENSEã€READMEï¼‰ï¼›æ–‡æ¡£ä¸å®¡è®¡è„šæœ¬å·²ç§»é™¤ã€‚

--- 2.5.8 ---
ä¿®å¤
- å°è¯•è®¡æ•°ï¼šé’“é±¼ CHAT_MSG_LOOT â€” CurrentUnitsHaveMobLootContext å‰ç½®å£°æ˜ï¼ˆæ­¤å‰ nil å…¨å±€ï¼‰ã€‚

--- 2.5.7 / 2.5.7b ---
çƒ­ä¿®
- è£…å¤‡é¡µï¼šè§’è‰²é€‰æ‹©ä¸ä¸‹æ‹‰èœå•ã€‚
- å…³äº / ä¿¡æ¯ï¼šè‡´è°¢ä¸è´¡çŒ®è€…ã€‚

æ”¹è¿›
- è§’è‰²ï¼šé»˜è®¤æ’åºï¼ˆå½“å‰è§’è‰² â†’ ç­‰çº§é«˜â†’ä½ â†’ å Aâ€“Zï¼‰ã€‚æ–°æ¡£æ¡ˆ characterSort.key = defaultã€‚æ— æ•ˆé”®æ˜ å°„èœå•é¦–é¡¹ã€‚æ”¶è—ã€è¿½è¸ªã€æœªè¿½è¸ªä¸­åœ¨çº¿è§’è‰²ç½®é¡¶ï¼ˆå«æ‰‹åŠ¨æ’åºï¼‰ï¼›æ‰‹åŠ¨ç§å­å«æ•´åŒºã€åœ¨çº¿ä¼˜å…ˆï¼›characterOrder å«æœªè¿½è¸ªåˆ—è¡¨ï¼›é‡æ’ä¿æŒåœ¨çº¿ç½®é¡¶ã€‚
- è®¾ç½®ï¼šWindowManagerï¼ˆPOPUPã€ä¸ä¸»çª—å…±äº« ESCï¼‰æ›¿ä»£å›ºå®š FULLSCREEN_DIALOGã€‚RefreshSettingsKeyboard åœ¨ Show åæ¢å¤é”®ç›˜ã€‚å­—ä½“é‡å»ºæ—¶ä» WindowManager æ³¨é”€è®¾ç½®çª—ã€‚
- WindowManagerï¼šæˆ˜åæ¢å¤é™¤ SetPropagateKeyboardInput(true) å¤–è°ƒç”¨ EnableKeyboard(true)ã€‚
- å°è¯•è®¡æ•°ï¼šå‰¯æœ¬éš¾åº¦ä¼˜å…ˆè¿›æœ¬å¿«ç…§ï¼ˆPLAYER_ENTERING_WORLDã€å‰¯æœ¬ IDï¼‰ï¼Œå† GetInstanceInfoï¼Œæ—©äº ENCOUNTER_END ä¸ API â€” ä¿®æ­£å²è¯—è¯»æˆæ™®é€šï¼ˆå¦‚éº¦å¡è´¡ HK-8ï¼‰ã€‚difficulty 0 æ—¶ M+/API ç”¨ ResolveLiveInstanceDifficultyIDï¼›ResolveEffectiveEncounterDifficultyID ç»Ÿä¸€è¿‡æ»¤ã€‚
- å°è¯•è®¡æ•°ï¼šFilterDropsByDifficulty ç”¨äºæ‹¾å–ã€å»¶è¿Ÿ ENCã€CHAT_MSG_LOOTï¼›ä¸æ‹¾å–çª—ç›¸åŒ encounter_ å»é‡é”®ã€‚
- å°è¯•è®¡æ•°ï¼šè§„åˆ™åæ— å¯è¿½è¸ªæ‰è½ä»è®°å½•å»é‡é”®ï¼ˆé¿å…å»¶è¿Ÿ ENC/CHAT é‡å¤ï¼‰ã€‚
- å°è¯•è®¡æ•°ï¼šé‡å¤–åˆå¹¶æ‹¾å–æŒ‰ç‰©å“ ID å°¸ä½“å€ç‡ï¼ˆå¦‚çº³å…¹ç±³å°”è¡€é¥•é¤®ï¼‰ã€‚
- å°è¯•è®¡æ•°ï¼šLOOT_READY è¿å‘ä¸æ¸…ç©ºä¼šè¯ï¼›è°ƒè¯•è¿½è¸ªçŸ­æ—¶å»é‡ã€‚
- å°è¯•è®¡æ•°ï¼š[WN-Drops] TRYCOUNTER_INSTANCE_DROPS_HEADERï¼›é“¾æ¥åæ‹¬å·æ˜¾ç¤ºæ‰€éœ€éš¾åº¦ â€” ç»¿/çº¢/ç¥ç€ã€‚

ä¿®å¤
- å°è¯•è®¡æ•°ï¼šå·²æç¤ºè·³è¿‡éš¾åº¦åè®¡æ•°ä»æ¶¨ï¼ˆæ‹¾å– vs å»¶è¿Ÿ ENC/CHATï¼‰ã€‚

æœ¬åœ°åŒ–
- SORT_MODE_DEFAULTï¼›TRYCOUNTER_INSTANCE_COLLECTIBLE_DETECTED ç­‰ã€‚

--- 2.5.6 ---
æ”¹è¿›
- è£…å¤‡ã€è®¡åˆ’ã€è¿½è¸ªã€è·Ÿè¸ªå™¨ä¸­æœåŠ¡å™¨æ›´æ˜“è¯»ã€‚
- æ”¶è—ï¼šæ›´å¤š BfA è¡€é¥•é¤® NPCï¼›å®ç®± vs é¦–é¢†å¤‡æ³¨ä¸å¤šå°¸ä½“ã€‚
- SplitCharacterKey + å-æœé¦–ä¸ªè¿å­—ç¬¦ã€‚
- åéª‘ï¼šç¤¾åŒº Lua DB + Wowhead/WoWDBã€‚

ä¿®å¤
- å°è¯•è®¡æ•°ï¼šèŠå¤©æ‹¾å– + å…±äº«è¡¨ â€” ä¿ç•™ CHAT æ›´æ–°ã€‚
- è¿å­—ç¬¦æœåŠ¡å™¨ï¼šè§„èŒƒé”®ã€GetAllCharactersã€stats/å°åœ°å›¾ï¼›ä¸€æ¬¡æ€§è¿ç§»ã€‚
- åéª‘ IDï¼šVerdant Skitterflyï¼ˆ192764ï¼‰ã€çº¢è‰²å…¶æ‹‰æ°´æ™¶ï¼ˆ21321ï¼‰ã€‚
- å¯¹è¯æ¡†ï¼šGetRealmName ä¿æŠ¤ã€‚

æœ¬åœ°åŒ–
- TRY_COUNT å·¦é”®/å³é”®æç¤ºã€‚

åç»­
- åŠ å¼ºæ”¶è—ä¸é­é‡ ID çš„ Midnight æ ¡éªŒï¼›æ®å›¢æœ¬åé¦ˆæ‰“ç£¨å°è¯•è®¡æ•°ä¸é€šçŸ¥ã€‚

CurseForgeï¼šWarband Nexus]=]





L["CHANGELOG_V2515"] = [=[v2.5.15 beta 1ï¼ˆ2026-04-15ï¼‰

æµ‹è¯•ï¼ˆBetaï¼‰ç‰ˆæœ¬ â€” æ¬¢è¿åé¦ˆï¼Œç¨³å®šç‰ˆå‘å¸ƒå‰è¯·å‹¿è§†ä¸ºæœ€ç»ˆå‘è¡Œã€‚

æ€§èƒ½
- ç•Œé¢ï¼šSchedulePopulateContent å»æŠ–ï¼ˆä»¥æœ€åä¸€æ¬¡è°ƒåº¦ä¸ºå‡†ï¼‰ï¼›OnHide å–æ¶ˆå¡«å……è®¡æ—¶å™¨ï¼›ä¸»æ ‡ç­¾åˆ‡æ¢ä»…ä¸€æ¬¡å»¶è¿Ÿï¼›åˆ‡æ¢ä¸­ä¸é‡å¤åˆ·æ–°æ ‡ç­¾æŒ‰é’®ï¼›éå½“å‰æ ‡ç­¾æ—¶è´§å¸/å£°æœ›ä»…æ›´æ–°è§’æ ‡ã€‚
- CollectionServiceï¼šåˆå¹¶ EnsureCollectionDataï¼›ScanCollection ä½¿ç”¨ FRAME_BUDGET_MS åç¨‹ï¼›BuildFullCollectionData æ‰¹æ¬¡é¢„ç®—ä¸€è‡´ã€‚
- å…¬ä¼šé“¶è¡Œä¸ç‰©å“ç¼“å­˜ï¼šåˆ†å—æ‰«æï¼›åˆ†æ ‡ç­¾åŸå­èµ‹å€¼ï¼›å–æ¶ˆ/å…³é—­æ—¶å¤±æ•ˆã€‚
- è®¡åˆ’ä¸æ”¶è—ï¼šPlansUI åŒåˆ—ç½‘æ ¼ O(n) é¢„è®¡ç®—ï¼›AbortCollectionsChunkedBuildsï¼›Core ä¸­æ­¢ä¸æ ‡ç­¾æ‹†è§£ä¸€è‡´ã€‚

ä¿®å¤
- TOCï¼šConfig.lua åœ¨ Modules/Constants.lua ä¹‹ååŠ è½½ï¼ˆä¿®å¤ Config åˆå§‹åŒ–æ—¶ ns.Constants ä¸ºç©ºï¼‰ã€‚
- ä¸»æ¡†ä½“ OnHideï¼šå–æ¶ˆåæ¸…ç©ºå¡«å……è®¡æ—¶å™¨ã€‚

æœ¬åœ°åŒ–
- GearUIï¼šå‡çº§è½¨é“åç§°ä¸åˆ¶é€ /å†é€ æç¤ºè¡Œï¼›PVE_CREST_EXPLORERï¼›ä¸“ç²¾ä¸“æ³¨ä¸ Steam é£æ ¼æ¸¸æˆæ—¶é—´æ ¼å¼ï¼›GEAR_CRAFTED_*ã€STATS_PLAYED_STEAM_*ã€PROF_CONCENTRATION_* å¤šè¯­è¨€è¡¥å…¨ï¼ˆdeã€frã€esã€es-mxã€itã€ptã€ruã€koã€zhTWï¼›enUS/zhCN åŸºçº¿ï¼‰ã€‚

CurseForge: Warband Nexus]=]

-- Confirm / Tracking Dialog
L["CONFIRM_ACTION"] = "ç¡®è®¤æ“ä½œ"
L["CONFIRM"] = "ç¡®è®¤"
L["ENABLE_TRACKING_FORMAT"] = "ä¸º |cffffcc00%s|r å¯ç”¨è¿½è¸ªï¼Ÿ"
L["DISABLE_TRACKING_FORMAT"] = "ä¸º |cffffcc00%s|r ç¦ç”¨è¿½è¸ªï¼Ÿ"

-- Reputation Section Headers
L["REP_SECTION_ACCOUNT_WIDE"] = "è´¦å·é€šç”¨å£°æœ›ï¼ˆ%sï¼‰"
L["REP_SECTION_CHARACTER_BASED"] = "è§’è‰²å£°æœ›ï¼ˆ%sï¼‰"

-- Reputation Processor Labels
L["REP_REWARD_WAITING"] = "å¥–åŠ±ç­‰å¾…ä¸­"
L["REP_PARAGON_LABEL"] = "å·…å³°"

-- Reputation Loading States
L["REP_LOADING_PREPARING"] = "å‡†å¤‡ä¸­..."
L["REP_LOADING_INITIALIZING"] = "åˆå§‹åŒ–ä¸­..."
L["REP_LOADING_FETCHING"] = "æ­£åœ¨è·å–å£°æœ›æ•°æ®..."
L["REP_LOADING_PROCESSING"] = "æ­£åœ¨å¤„ç† %d ä¸ªé˜µè¥..."
L["REP_LOADING_SAVING"] = "æ­£åœ¨ä¿å­˜åˆ°æ•°æ®åº“..."
L["REP_LOADING_COMPLETE"] = "å®Œæˆï¼"

-- Status / Footer
L["COMBAT_LOCKDOWN_MSG"] = "æˆ˜æ–—ä¸­æ— æ³•æ‰“å¼€çª—å£ã€‚æˆ˜æ–—ç»“æŸåè¯·é‡è¯•ã€‚"
L["BANK_IS_ACTIVE"] = "é“¶è¡Œå·²æ‰“å¼€"

-- Table Headers (SharedWidgets, Professions)

-- Search / Empty States
L["NO_ITEMS_MATCH"] = "æ²¡æœ‰åŒ¹é… '%s' çš„ç‰©å“"
L["NO_ITEMS_MATCH_GENERIC"] = "æ²¡æœ‰åŒ¹é…ä½ æœç´¢çš„ç‰©å“"
L["ITEMS_SCAN_HINT"] = "ç‰©å“è‡ªåŠ¨æ‰«æã€‚å¦‚æ— æ˜¾ç¤ºè¯·å°è¯• /reloadã€‚"
L["ITEMS_WARBAND_BANK_HINT"] = "æ‰“å¼€æˆ˜å›¢é“¶è¡Œä»¥æ‰«æç‰©å“ï¼ˆé¦–æ¬¡è®¿é—®æ—¶è‡ªåŠ¨æ‰«æï¼‰"

-- Currency Transfer Steps

-- Plans UI Extra
L["ADDED"] = "å·²æ·»åŠ "
L["WEEKLY_VAULT_TRACKER"] = "æ¯å‘¨å®åº“è¿½è¸ª"
L["DAILY_QUEST_TRACKER"] = "æ¯æ—¥ä»»åŠ¡è¿½è¸ª"

-- Achievement Popup
L["ACHIEVEMENT_NOT_COMPLETED"] = "æœªå®Œæˆ"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d ç‚¹"
L["ADD_PLAN"] = "æ·»åŠ "
L["PLANNED"] = "è®¡åˆ’ä¸­"

-- PlanCardFactory Vault Slots
L["VAULT_SLOT_WORLD"] = "ä¸–ç•Œ"
L["VAULT_SLOT_SA"] = "æŒ‡æ´¾"

-- PvE Extra
L["AFFIX_TITLE_FALLBACK"] = "è¯ç¼€"

-- Chat Messages

-- PlansManager Messages
L["PLAN_COMPLETED"] = "è®¡åˆ’å·²å®Œæˆï¼š"
L["WEEKLY_VAULT_PLAN_NAME"] = "æ¯å‘¨å®åº“ - %s"
L["VAULT_PLANS_RESET"] = "æ¯å‘¨å®ä¼Ÿå®åº“è®¡åˆ’å·²é‡ç½®ï¼ï¼ˆ%d ä¸ªè®¡åˆ’%sï¼‰"

-- Reminder System
L["SET_ALERT_TITLE"] = "è®¾ç½®æé†’"
L["SET_ALERT"] = "è®¾ç½®æé†’"
L["REMOVE_ALERT"] = "ç§»é™¤æé†’"
L["ALERT_ACTIVE"] = "æé†’å·²æ¿€æ´»"
L["REMINDER_PREFIX"] = "æé†’"
L["REMINDER_DAILY_LOGIN"] = "æ¯æ—¥ç™»å½•"
L["REMINDER_WEEKLY_RESET"] = "æ¯å‘¨é‡ç½®"
L["REMINDER_DAYS_BEFORE"] = "é‡ç½®å‰ %d å¤©"
L["REMINDER_ZONE_ENTER"] = "è¿›å…¥ %s"
L["REMINDER_OPT_DAILY"] = "æ¯æ—¥ç™»å½•æ—¶æé†’"
L["REMINDER_OPT_WEEKLY"] = "æ¯å‘¨é‡ç½®åæé†’"
L["REMINDER_OPT_DAYS_BEFORE"] = "é‡ç½®å‰ %d å¤©æé†’"
L["REMINDER_OPT_ZONE"] = "è¿›å…¥æ¥æºåŒºåŸŸæ—¶æé†’"

-- Empty State Cards
L["NO_SCAN"] = "æœªæ‰«æ"
L["NO_ADDITIONAL_INFO"] = "æ— é™„åŠ ä¿¡æ¯"

-- Character Tracking & Commands
L["TRACK_CHARACTER_QUESTION"] = "è¦è¿½è¸ªæ­¤è§’è‰²å—ï¼Ÿ"
L["CLEANUP_NO_INACTIVE"] = "æœªæ‰¾åˆ°ä¸æ´»è·ƒè§’è‰²ï¼ˆ90+ å¤©ï¼‰"
L["CLEANUP_REMOVED_FORMAT"] = "å·²ç§»é™¤ %d ä¸ªä¸æ´»è·ƒè§’è‰²"
L["TRACKING_ENABLED_MSG"] = "è§’è‰²è¿½è¸ªå·²å¯ç”¨ï¼"
L["TRACKING_DISABLED_MSG"] = "è§’è‰²è¿½è¸ªå·²ç¦ç”¨ï¼"
L["TRACKING_DISABLED"] = "è¿½è¸ªå·²ç¦ç”¨ï¼ˆåªè¯»æ¨¡å¼ï¼‰"
L["STATUS_LABEL"] = "çŠ¶æ€ï¼š"
L["ERROR_LABEL"] = "é”™è¯¯ï¼š"
L["ERROR_NAME_REALM_REQUIRED"] = "éœ€è¦è§’è‰²åå’ŒæœåŠ¡å™¨"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s å·²æœ‰æ´»è·ƒçš„æ¯å‘¨è®¡åˆ’"

-- Profiles (AceDB)

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "æœªæ‰¾åˆ°æ¡ä»¶"
L["NO_REQUIREMENTS_INSTANT"] = "æ— è¦æ±‚ï¼ˆå³æ—¶å®Œæˆï¼‰"

-- Professions Tab
L["TAB_PROFESSIONS"] = "ä¸“ä¸š"
L["TAB_COLLECTIONS"] = "æ”¶è—"
L["COLLECTIONS_SUBTITLE"] = "åéª‘ã€å® ç‰©ã€ç©å…·ä¸å¹»åŒ–æ¦‚è§ˆ"
L["COLLECTIONS_SUBTAB_RECENT"] = "æœ€è¿‘"
L["SELECT_MOUNT_FROM_LIST"] = "ä»åˆ—è¡¨é€‰æ‹©åéª‘"
L["SELECT_PET_FROM_LIST"] = "ä»åˆ—è¡¨é€‰æ‹©å® ç‰©"
L["SELECT_TO_SEE_DETAILS"] = "é€‰æ‹© %s ä»¥æŸ¥çœ‹è¯¦æƒ…ã€‚"
L["SOURCE"] = "æ¥æº"
L["YOUR_PROFESSIONS"] = "æˆ˜å›¢ä¸“ä¸š"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s ä¸ªè§’è‰²æœ‰ä¸“ä¸š"
L["PROFESSIONS_WIDE_TABLE_HINT"] = "æç¤ºï¼šä½¿ç”¨ä¸‹æ–¹æ»šåŠ¨æ¡æˆ– Shift+æ»šè½®æŸ¥çœ‹æ‰€æœ‰åˆ—ã€‚"
L["NO_PROFESSIONS_DATA"] = "æš‚æ— ä¸“ä¸šæ•°æ®ã€‚åœ¨æ¯ä¸ªè§’è‰²ä¸Šæ‰“å¼€ä¸“ä¸šçª—å£ï¼ˆé»˜è®¤ Kï¼‰ä»¥æ”¶é›†æ•°æ®ã€‚"
L["CONCENTRATION"] = "ä¸“æ³¨"
L["KNOWLEDGE"] = "çŸ¥è¯†"
L["SKILL"] = "æŠ€èƒ½"
L["RECIPES"] = "é…æ–¹"
L["UNSPENT_POINTS"] = "æœªä½¿ç”¨ç‚¹æ•°"
L["UNSPENT_KNOWLEDGE_TOOLTIP"] = "æœªä½¿ç”¨çš„çŸ¥è¯†ç‚¹"
L["UNSPENT_KNOWLEDGE_COUNT"] = "%dä¸ªæœªä½¿ç”¨çš„çŸ¥è¯†ç‚¹"
L["COLLECTIBLE"] = "æ”¶è—å“"
L["RECHARGE"] = "å……èƒ½"
L["FULL"] = "å·²æ»¡"
L["PROF_CONCENTRATION_FULL"] = "å·²æ»¡"
L["PROF_CONCENTRATION_HOURS_REMAINING"] = "%d å°æ—¶"
L["PROF_CONCENTRATION_MINUTES_REMAINING"] = "%d åˆ†é’Ÿ"
L["PROF_CONCENTRATION_DAYS_HOURS_MIN"] = "%d å¤© %d å°æ—¶ %d åˆ†é’Ÿ"
L["PROF_CONCENTRATION_HOURS_MIN"] = "%d å°æ—¶ %d åˆ†é’Ÿ"
L["PROF_CONCENTRATION_MINUTES_ONLY"] = "%d åˆ†é’Ÿ"
L["PROF_OPEN_RECIPE"] = "æ‰“å¼€"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "æ‰“å¼€æ­¤ä¸“ä¸šçš„é…æ–¹åˆ—è¡¨"
L["PROF_ONLY_CURRENT_CHAR"] = "ä»…å½“å‰è§’è‰²å¯ç”¨"
L["NO_PROFESSION"] = "æ— ä¸“ä¸š"

-- Professions: Expansion filter
L["PROF_FILTER_ALL"] = "å…¨éƒ¨"
L["PROF_FIRSTCRAFT_NO_DATA"] = "æ— å¯ç”¨ä¸“ä¸šæ•°æ®ã€‚"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "é¦–æ¬¡åˆ¶é€ "
L["UNIQUES"] = "å‘¨çŸ¥è¯†"
L["TREATISE"] = "è®ºè¿°"
L["GATHERING"] = "é‡‡é›†"
L["CATCH_UP"] = "è¿½èµ¶"
L["MOXIE"] = "åŒ äºº"
L["COOLDOWNS"] = "å†·å´"
L["COLUMNS_BUTTON"] = "åˆ—"

-- Professions: Tooltips & Details

-- Professions: Crafting Orders

-- Professions: Equipment
L["EQUIPMENT"] = "è£…å¤‡"
L["TOOL"] = "å·¥å…·"
L["ACCESSORY"] = "é…ä»¶"
L["PROF_EQUIPMENT_HINT"] = "åœ¨æ­¤è§’è‰²ä¸Šæ‰“å¼€ä¸“ä¸šæŠ€èƒ½(K)ä»¥æ‰«æè£…å¤‡ã€‚"

-- Professions: Info Window
L["PROF_INFO_TOOLTIP"] = "æŸ¥çœ‹ä¸“ä¸šè¯¦æƒ…"
L["PROF_INFO_NO_DATA"] = "æ— ä¸“ä¸šæ•°æ®ã€‚\nè¯·ç™»å½•æ­¤è§’è‰²å¹¶æ‰“å¼€ä¸“ä¸šæŠ€èƒ½çª—å£(K)ä»¥æ”¶é›†æ•°æ®ã€‚"
L["PROF_INFO_SKILLS"] = "èµ„æ–™ç‰‡æŠ€èƒ½"
L["PROF_INFO_TOOL"] = "å·¥å…·"
L["PROF_INFO_ACC1"] = "é¥°å“ 1"
L["PROF_INFO_ACC2"] = "é¥°å“ 2"
L["PROF_INFO_KNOWN"] = "å·²å­¦"
L["PROF_INFO_WEEKLY"] = "æ¯å‘¨çŸ¥è¯†è¿›åº¦"
L["PROF_INFO_COOLDOWNS"] = "å†·å´"
L["PROF_INFO_READY"] = "å°±ç»ª"
L["PROF_INFO_LAST_UPDATE"] = "ä¸Šæ¬¡æ›´æ–°"
L["PROF_INFO_LOCKED"] = "å·²é”å®š"
L["PROF_INFO_UNLEARNED"] = "æœªå­¦ä¹ "

-- Track Item DB
L["TRACK_ITEM_DB"] = "è¿½è¸ªç‰©å“æ•°æ®åº“"
L["TRACK_ITEM_DB_DESC"] = "ç®¡ç†è¦è¿½è¸ªçš„æ”¶è—å“æ‰è½ã€‚åˆ‡æ¢å†…ç½®æ¡ç›®æˆ–æ·»åŠ è‡ªå®šä¹‰æ¥æºã€‚"
L["MANAGE_ITEMS"] = "ç‰©å“è¿½è¸ª"
L["SELECT_ITEM"] = "é€‰æ‹©ç‰©å“"
L["SELECT_ITEM_DESC"] = "é€‰æ‹©è¦ç®¡ç†çš„æ”¶è—å“ã€‚"
L["SELECT_ITEM_HINT"] = "é€‰æ‹©ä¸Šæ–¹ç‰©å“ä»¥æŸ¥çœ‹è¯¦æƒ…ã€‚"
L["REPEATABLE_LABEL"] = "å¯é‡å¤"
L["SOURCE_SINGULAR"] = "æ¥æº"
L["SOURCE_PLURAL"] = "æ¥æº"
L["UNTRACKED"] = "æœªè¿½è¸ª"
L["CUSTOM_ENTRIES"] = "è‡ªå®šä¹‰æ¡ç›®"
L["CURRENT_ENTRIES_LABEL"] = "å½“å‰ï¼š"
L["NO_CUSTOM_ENTRIES"] = "æ— è‡ªå®šä¹‰æ¡ç›®ã€‚"
L["ITEM_ID_INPUT"] = "ç‰©å“ ID"
L["ITEM_ID_INPUT_DESC"] = "è¾“å…¥è¦è¿½è¸ªçš„ç‰©å“ IDã€‚"
L["LOOKUP_ITEM"] = "æŸ¥è¯¢"
L["LOOKUP_ITEM_DESC"] = "ä» ID è§£æç‰©å“åç§°å’Œç±»å‹ã€‚"
L["ITEM_LOOKUP_FAILED"] = "æœªæ‰¾åˆ°ç‰©å“ã€‚"
L["SOURCE_TYPE"] = "æ¥æºç±»å‹"
L["SOURCE_TYPE_DESC"] = "NPC æˆ–ç‰©ä½“ã€‚"
L["SOURCE_TYPE_NPC"] = "NPC"
L["SOURCE_TYPE_OBJECT"] = "ç‰©ä½“"
L["SOURCE_ID"] = "æ¥æº ID"
L["SOURCE_ID_DESC"] = "NPC ID æˆ–ç‰©ä½“ IDã€‚"
L["REPEATABLE_TOGGLE"] = "å¯é‡å¤"
L["REPEATABLE_TOGGLE_DESC"] = "æ­¤æ‰è½æ˜¯å¦å¯åœ¨æ¯æ¬¡é”å®šå†…å¤šæ¬¡å°è¯•ã€‚"
L["ADD_ENTRY"] = "+ æ·»åŠ æ¡ç›®"
L["ADD_ENTRY_DESC"] = "æ·»åŠ æ­¤è‡ªå®šä¹‰æ‰è½æ¡ç›®ã€‚"
L["ENTRY_ADDED"] = "è‡ªå®šä¹‰æ¡ç›®å·²æ·»åŠ ã€‚"
L["ENTRY_ADD_FAILED"] = "éœ€è¦ç‰©å“ ID å’Œæ¥æº IDã€‚"
L["REMOVE_ENTRY"] = "ç§»é™¤è‡ªå®šä¹‰æ¡ç›®"
L["REMOVE_ENTRY_DESC"] = "é€‰æ‹©è¦ç§»é™¤çš„è‡ªå®šä¹‰æ¡ç›®ã€‚"
L["REMOVE_BUTTON"] = "- ç§»é™¤æ‰€é€‰"
L["REMOVE_BUTTON_DESC"] = "ç§»é™¤æ‰€é€‰çš„è‡ªå®šä¹‰æ¡ç›®ã€‚"
L["ENTRY_REMOVED"] = "æ¡ç›®å·²ç§»é™¤ã€‚"
L["SOURCE_NAME"] = "æ¥æºåç§°"
L["SOURCE_NAME_DESC"] = "æ¥æºçš„å¯é€‰æ˜¾ç¤ºåç§°ï¼ˆå¦‚NPCæˆ–ç‰©ä½“ï¼‰ã€‚"
L["STATISTIC_IDS"] = "ç»Ÿè®¡ID"
L["STATISTIC_IDS_DESC"] = "ç”¨äºå‡»æ€/æ‰è½è®¡æ•°çš„WoWç»Ÿè®¡IDï¼ˆé€—å·åˆ†éš”ï¼Œå¯é€‰ï¼‰ã€‚"
L["MANAGE_BUILTIN"] = "ç®¡ç†å†…ç½®æ¡ç›®"
L["MANAGE_BUILTIN_DESC"] = "æŒ‰ç‰©å“IDæœç´¢å’Œåˆ‡æ¢å†…ç½®è¿½è¸ªæ¡ç›®ã€‚"
L["SEARCH_BUILTIN"] = "æŒ‰ç‰©å“IDæœç´¢å†…ç½®"
L["SEARCH_BUILTIN_DESC"] = "è¾“å…¥ç‰©å“IDä»¥åœ¨å†…ç½®æ•°æ®åº“ä¸­æŸ¥æ‰¾æ¥æºã€‚"
L["SEARCH_BUTTON"] = "æœç´¢"
L["CURRENTLY_UNTRACKED"] = "å½“å‰æœªè¿½è¸ª"
L["ITEM_RESOLVED"] = "ç‰©å“å·²è§£æï¼š%sï¼ˆ%sï¼‰"

-- Plans / Collections (parse labels and UI)
L["ACHIEVEMENT"] = "æˆå°±"
L["CRITERIA"] = "æ ‡å‡†"
L["CUSTOM_PLAN_COMPLETED"] = "è‡ªå®šä¹‰è®¡åˆ’ã€Œ%sã€|cff00ff00å·²å®Œæˆ|r"
L["DESCRIPTION"] = "æè¿°"
L["PARSE_AMOUNT"] = "æ•°é‡"
L["PARSE_LOCATION"] = "ä½ç½®"
L["SHOWING_X_OF_Y"] = "æ˜¾ç¤º %d/%d ä¸ªç»“æœ"
L["SOURCE_UNKNOWN"] = "æœªçŸ¥"
L["ZONE_DROP"] = "åŒºåŸŸæ‰è½"
L["FISHING"] = "é’“é±¼"

-- Config (display names)
L["CONFIG_RECIPE_COMPANION"] = "é…æ–¹åŠ©æ‰‹"
L["CONFIG_RECIPE_COMPANION_DESC"] = "åœ¨ä¸“ä¸šç•Œé¢æ—æ˜¾ç¤ºé…æ–¹åŠ©æ‰‹çª—å£ï¼ˆæŒ‰è§’è‰²æ˜¾ç¤ºææ–™å¯ç”¨æ€§ï¼‰ã€‚"

-- Try Counter
L["TRYCOUNTER_DIFFICULTY_SKIP"] = "å·²è·³è¿‡ï¼š%séœ€è¦%séš¾åº¦ï¼ˆå½“å‰ï¼š%sï¼‰"
L["TRYCOUNTER_OBTAINED"] = "å·²è·å¾—%sï¼"
L["TRYCOUNTER_INCREMENT_CHAT"] = "%d æ¬¡å°è¯• Â· %s"
L["TRYCOUNTER_CHAT_ATTEMPTS_FOR_LINK"] = "%d æ¬¡å°è¯• Â· %s"
L["TRYCOUNTER_CHAT_FIRST_FOR_LINK"] = "é¦–æ¬¡å°è¯• Â· %s"
L["TRYCOUNTER_CHAT_TAG_CONTAINER"] = "å®¹å™¨"
L["TRYCOUNTER_CHAT_TAG_FISHING"] = "é’“é±¼"
L["TRYCOUNTER_CHAT_TAG_RESET"] = "è®¡æ•°å·²é‡ç½®"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d æ¬¡å°è¯• Â· %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "è·å¾— %sï¼å°è¯•è®¡æ•°å·²é‡ç½®ã€‚"
L["TRYCOUNTER_CAUGHT_RESET"] = "æ•è· %sï¼å°è¯•è®¡æ•°å·²é‡ç½®ã€‚"
L["TRYCOUNTER_CAUGHT"] = "é’“åˆ° %sï¼"
L["TRYCOUNTER_CONTAINER_RESET"] = "ä»å®¹å™¨è·å¾— %sï¼å°è¯•è®¡æ•°å·²é‡ç½®ã€‚"
L["TRYCOUNTER_CONTAINER"] = "ä»å®¹å™¨è·å¾— %sï¼"
L["TRYCOUNTER_LOCKOUT_SKIP"] = "å·²è·³è¿‡ï¼šæ­¤ NPC çš„æ¯æ—¥/æ¯å‘¨é”å®šå·²æ¿€æ´»ã€‚"
L["TRYCOUNTER_INSTANCE_ENTRY_HINT"] = "æ­¤å‰¯æœ¬æœ‰é€‚ç”¨äºä½ å½“å‰éš¾åº¦çš„å°è¯•è®¡æ•°åéª‘ã€‚å¯¹é¦–é¢†ä½¿ç”¨ç›®æ ‡æˆ–é¼ æ ‡æŒ‡å‘åè¾“å…¥ |cffffffff/wn check|r æŸ¥çœ‹è¯¦æƒ…ã€‚"
L["TRYCOUNTER_COLLECTED_TAG"] = "ï¼ˆå·²æ”¶é›†ï¼‰"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " æ¬¡å°è¯•"
L["TRYCOUNTER_TRY_COUNTS"] = "å°è¯•æ¬¡æ•°"
L["TRYCOUNTER_PROBE_ENTER"] = "è¿›å…¥ï¼š%s â€” éš¾åº¦ï¼š%s"
L["TRYCOUNTER_PROBE_DB_HEADER"] = "å°è¯•è®¡æ•°æ•°æ®åº“ä¸­çš„åéª‘æ¥æº â€” ä½ çš„éš¾åº¦ï¼š%s"
L["TRYCOUNTER_PROBE_MOUNT_LINE"] = "%s > %s > %s > %s"
L["TRYCOUNTER_PROBE_ENC_NO_MOUNTS"] = "%sï¼šæ•°æ®åº“ä¸­æ— åéª‘æ¡ç›®"
L["TRYCOUNTER_PROBE_JOURNAL_MISS"] = "æ— æ³•è§£ææ­¤å‰¯æœ¬çš„åœ°ä¸‹åŸæ‰‹å†Œã€‚"
L["TRYCOUNTER_PROBE_NO_MAPPED_BOSSES"] = "æ­¤å‰¯æœ¬æ²¡æœ‰ä¸å°è¯•è®¡æ•°æ•°æ®åŒ¹é…çš„é¦–é¢†ã€‚"
L["TRYCOUNTER_PROBE_STATUS_COLLECTED"] = "å·²æ”¶è—"
L["TRYCOUNTER_PROBE_STATUS_OBTAINABLE"] = "å½“å‰éš¾åº¦å¯è·å¾—"
L["TRYCOUNTER_PROBE_STATUS_WRONG_DIFF"] = "å½“å‰éš¾åº¦ä¸å¯ç”¨"
L["TRYCOUNTER_PROBE_STATUS_DIFF_UNKNOWN"] = "éš¾åº¦æœªçŸ¥"
L["TRYCOUNTER_PROBE_REQ_ANY"] = "ä»»æ„éš¾åº¦"
L["TRYCOUNTER_PROBE_REQ_MYTHIC"] = "ä»…å²è¯—"
L["TRYCOUNTER_PROBE_REQ_LFR"] = "ä»…éšæœºå›¢é˜Ÿ"
L["TRYCOUNTER_PROBE_REQ_NORMAL_PLUS"] = "å›¢é˜Ÿæ™®é€šåŠä»¥ä¸Šï¼ˆä¸å«éšæœºå›¢é˜Ÿï¼‰"
L["TRYCOUNTER_PROBE_REQ_HEROIC"] = "è‹±é›„åŠä»¥ä¸Šï¼ˆå«å²è¯—ä¸25äººè‹±é›„ï¼‰"
L["TRYCOUNTER_PROBE_REQ_25H"] = "ä»…25äººè‹±é›„"
L["TRYCOUNTER_PROBE_REQ_10N"] = "ä»…10äººæ™®é€š"
L["TRYCOUNTER_PROBE_REQ_25N"] = "ä»…25äººæ™®é€š"
L["TRYCOUNTER_PROBE_REQ_25MAN"] = "25äººæ™®é€šæˆ–è‹±é›„"

-- Recipe Companion
L["RECIPE_COMPANION_TITLE"] = "é…æ–¹åŠ©æ‰‹"
L["TOGGLE_TRACKER"] = "åˆ‡æ¢è¿½è¸ª"
L["SELECT_RECIPE"] = "é€‰æ‹©é…æ–¹"
L["CRAFTERS_SECTION"] = "åˆ¶é€ è€…"
L["TOTAL_REAGENTS"] = "ææ–™æ€»æ•°"

-- Database / Migration
L["DATABASE_UPDATED_MSG"] = "æ•°æ®åº“å·²æ›´æ–°åˆ°æ–°ç‰ˆæœ¬ã€‚"
L["DATABASE_RELOAD_REQUIRED"] = "éœ€è¦é‡æ–°åŠ è½½ä»¥åº”ç”¨æ›´æ”¹ã€‚"
L["MIGRATION_RESET_COMPLETE"] = "é‡ç½®å®Œæˆã€‚æ‰€æœ‰æ•°æ®å°†è‡ªåŠ¨é‡æ–°æ‰«æã€‚"

-- Sync / Loading
L["SYNCING_COMPLETE"] = "åŒæ­¥å®Œæˆï¼"
L["SYNCING_LABEL_FORMAT"] = "WN åŒæ­¥ï¼š%s"
L["SETTINGS_UI_UNAVAILABLE"] = "è®¾ç½®ç•Œé¢ä¸å¯ç”¨ã€‚å°è¯• /wn æ‰“å¼€ä¸»çª—å£ã€‚"

-- Character Tracking Dialog
L["TRACKED_LABEL"] = "å·²è¿½è¸ª"
L["TRACKED_DETAILED_LINE1"] = "å®Œæ•´è¯¦ç»†æ•°æ®"
L["TRACKED_DETAILED_LINE2"] = "æ‰€æœ‰åŠŸèƒ½å·²å¯ç”¨"
L["UNTRACKED_LABEL"] = "æœªè¿½è¸ª"
L["TRACKING_BADGE_TRACKING"] = "è¿½è¸ªä¸­"
L["TRACKING_BADGE_UNTRACKED"] = "æœª\nè¿½è¸ª"
L["TRACKING_BADGE_BANK"] = "é“¶è¡Œ\næ´»è·ƒ"
L["UNTRACKED_VIEWONLY_LINE1"] = "åªè¯»æ¨¡å¼"
L["UNTRACKED_VIEWONLY_LINE2"] = "ä»…åŸºæœ¬ä¿¡æ¯"
L["TRACKING_ENABLED_CHAT"] = "è§’è‰²è¿½è¸ªå·²å¯ç”¨ã€‚æ•°æ®æ”¶é›†å°†å¼€å§‹ã€‚"
L["TRACKING_DISABLED_CHAT"] = "è§’è‰²è¿½è¸ªå·²ç¦ç”¨ã€‚ä»¥åªè¯»æ¨¡å¼è¿è¡Œã€‚"
L["ADDED_TO_FAVORITES"] = "å·²æ·»åŠ åˆ°æ”¶è—ï¼š"
L["REMOVED_FROM_FAVORITES"] = "å·²ä»æ”¶è—ç§»é™¤ï¼š"

-- Tooltip: Collectible Drop Lines
L["TOOLTIP_ATTEMPTS"] = "æ¬¡å°è¯•"
L["TOOLTIP_100_DROP"] = "100% æ‰è½"
L["TOOLTIP_UNKNOWN"] = "æœªçŸ¥"
L["TOOLTIP_HOLD_SHIFT"] = "  æŒ‰ä½ [Shift] æŸ¥çœ‹å®Œæ•´åˆ—è¡¨"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - ä¸“æ³¨"
L["TOOLTIP_FULL"] = "ï¼ˆå·²æ»¡ï¼‰"
L["TOOLTIP_NO_LOOT_UNTIL_RESET"] = "ä¸‹æ¬¡é‡ç½®å‰æ— æˆ˜åˆ©å“"

-- SharedWidgets: UI Labels
L["NO_ITEMS_CACHED_TITLE"] = "æ— ç‰©å“ç¼“å­˜"
L["DB_LABEL"] = "æ•°æ®åº“ï¼š"

-- DataService: Loading Stages & Alerts
L["COLLECTING_PVE"] = "æ­£åœ¨æ”¶é›† PvE æ•°æ®"
L["PVE_PREPARING"] = "å‡†å¤‡ä¸­"
L["PVE_GREAT_VAULT"] = "å®ä¼Ÿå®åº“"
L["PVE_MYTHIC_SCORES"] = "å²è¯—é’¥çŸ³è¯„åˆ†"
L["PVE_RAID_LOCKOUTS"] = "å›¢é˜Ÿå‰¯æœ¬é”å®š"
L["PVE_INCOMPLETE_DATA"] = "éƒ¨åˆ†æ•°æ®å¯èƒ½ä¸å®Œæ•´ã€‚ç¨ååˆ·æ–°ã€‚"
L["VAULT_SLOTS_TO_FILL"] = "éœ€å¡«å…… %d ä¸ªå®ä¼Ÿå®åº“æ§½ä½%s"
L["VAULT_SLOT_PLURAL"] = ""
L["REP_RENOWN_NEXT"] = "åæœ› %d"
L["REP_TO_NEXT_FORMAT"] = "è· %sï¼ˆ%sï¼‰è¿˜éœ€ %s å£°æœ›"
L["REP_FACTION_FALLBACK"] = "é˜µè¥"
L["COLLECTION_CANCELLED"] = "ç”¨æˆ·å–æ¶ˆäº†æ”¶é›†"
L["PERSONAL_BANK"] = "ä¸ªäººé“¶è¡Œ"
L["WARBAND_BANK_LABEL"] = "æˆ˜å›¢é“¶è¡Œ"
L["WARBAND_BANK_TAB_FORMAT"] = "æ ‡ç­¾é¡µ %d"
L["CURRENCY_OTHER"] = "å…¶ä»–"

-- DataService: Reputation Standings
L["STANDING_HATED"] = "ä»‡æ¨"
L["STANDING_HOSTILE"] = "æ•Œå¯¹"
L["STANDING_UNFRIENDLY"] = "å†·æ·¡"
L["STANDING_NEUTRAL"] = "ä¸­ç«‹"
L["STANDING_FRIENDLY"] = "å‹å¥½"
L["STANDING_HONORED"] = "å°Šæ•¬"
L["STANDING_REVERED"] = "å´‡æ•¬"
L["STANDING_EXALTED"] = "å´‡æ‹œ"

-- Loading Tracker Labels
L["LT_CHARACTER_DATA"] = "è§’è‰²æ•°æ®"
L["LT_CURRENCY_CACHES"] = "è´§å¸ä¸ç¼“å­˜"
L["LT_REPUTATIONS"] = "å£°æœ›"
L["LT_PROFESSIONS"] = "ä¸“ä¸š"
L["LT_PVE_DATA"] = "PvE æ•°æ®"
L["LT_COLLECTIONS"] = "æ”¶è—"
L["LT_COLLECTION_DATA"] = "æ”¶è—æ•°æ®"

-- Collections tab (loading & filters)
L["LOADING_COLLECTIONS"] = "æ­£åœ¨åŠ è½½æ”¶è—..."
L["SYNC_COMPLETE"] = "å·²åŒæ­¥"
L["FILTER_COLLECTED"] = "å·²æ”¶è—"
L["FILTER_UNCOLLECTED"] = "æœªæ”¶è—"
L["FILTER_SHOW_OWNED"] = "å·²æ‹¥æœ‰"
L["FILTER_SHOW_MISSING"] = "æœªæ‹¥æœ‰"

-- Config: Settings Panel
L["CONFIG_HEADER"] = "Warband Nexus"
L["CONFIG_HEADER_DESC"] = "ç°ä»£æˆ˜å›¢ç®¡ç†å’Œè·¨è§’è‰²è¿½è¸ªã€‚"
L["CONFIG_GENERAL"] = "å¸¸è§„è®¾ç½®"
L["CONFIG_GENERAL_DESC"] = "åŸºæœ¬æ’ä»¶è®¾ç½®å’Œè¡Œä¸ºé€‰é¡¹ã€‚"
L["CONFIG_ENABLE"] = "å¯ç”¨æ’ä»¶"
L["CONFIG_ENABLE_DESC"] = "å¼€å¯æˆ–å…³é—­æ’ä»¶ã€‚"
L["CONFIG_MINIMAP"] = "å°åœ°å›¾æŒ‰é’®"
L["CONFIG_MINIMAP_DESC"] = "åœ¨å°åœ°å›¾ä¸Šæ˜¾ç¤ºæŒ‰é’®ä»¥ä¾¿å¿«é€Ÿè®¿é—®ã€‚"
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "åœ¨æç¤ºä¸­æ˜¾ç¤ºç‰©å“"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "åœ¨ç‰©å“æç¤ºä¸­æ˜¾ç¤ºæˆ˜å›¢å’Œè§’è‰²ç‰©å“æ•°é‡ã€‚"
L["CONFIG_MODULES"] = "æ¨¡å—ç®¡ç†"
L["CONFIG_MODULES_DESC"] = "å¯ç”¨æˆ–ç¦ç”¨å„ä¸ªæ’ä»¶æ¨¡å—ã€‚ç¦ç”¨çš„æ¨¡å—å°†ä¸æ”¶é›†æ•°æ®æˆ–æ˜¾ç¤ºç•Œé¢æ ‡ç­¾é¡µã€‚"
L["CONFIG_MOD_CURRENCIES"] = "è´§å¸"
L["CONFIG_MOD_CURRENCIES_DESC"] = "è¿½è¸ªæ‰€æœ‰è§’è‰²çš„è´§å¸ã€‚"
L["CONFIG_MOD_REPUTATIONS"] = "å£°æœ›"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "è¿½è¸ªæ‰€æœ‰è§’è‰²çš„å£°æœ›ã€‚"
L["CONFIG_MOD_ITEMS"] = "ç‰©å“"
L["CONFIG_MOD_ITEMS_DESC"] = "è¿½è¸ªèƒŒåŒ…å’Œé“¶è¡Œä¸­çš„ç‰©å“ã€‚"
L["CONFIG_MOD_STORAGE"] = "å­˜å‚¨"
L["CONFIG_MOD_STORAGE_DESC"] = "å­˜å‚¨æ ‡ç­¾é¡µï¼Œç”¨äºèƒŒåŒ…å’Œé“¶è¡Œç®¡ç†ã€‚"
L["CONFIG_MOD_PVE"] = "PvE"
L["CONFIG_MOD_PVE_DESC"] = "è¿½è¸ªå®ä¼Ÿå®åº“ã€å²è¯—é’¥çŸ³å’Œå›¢é˜Ÿå‰¯æœ¬é”å®šã€‚"
L["CONFIG_MOD_PLANS"] = "å¾…åŠ"
L["CONFIG_MOD_PLANS_DESC"] = "æ¯å‘¨ä»»åŠ¡è¿½è¸ªã€æ”¶è—ç›®æ ‡å’Œå®åº“è¿›åº¦ã€‚"
L["CONFIG_MOD_PROFESSIONS"] = "ä¸“ä¸š"
L["CONFIG_MOD_PROFESSIONS_DESC"] = "è¿½è¸ªä¸“ä¸šæŠ€èƒ½ã€é…æ–¹å’Œä¸“æ³¨ã€‚"
L["CONFIG_AUTOMATION"] = "è‡ªåŠ¨åŒ–"
L["CONFIG_AUTOMATION_DESC"] = "æ§åˆ¶æ‰“å¼€æˆ˜å›¢é“¶è¡Œæ—¶è‡ªåŠ¨æ‰§è¡Œçš„æ“ä½œã€‚"
L["CONFIG_AUTO_OPTIMIZE"] = "è‡ªåŠ¨ä¼˜åŒ–æ•°æ®åº“"
L["CONFIG_AUTO_OPTIMIZE_DESC"] = "ç™»å½•æ—¶è‡ªåŠ¨ä¼˜åŒ–æ•°æ®åº“ä»¥ä¿æŒå­˜å‚¨æ•ˆç‡ã€‚"
L["CONFIG_SHOW_ITEM_COUNT"] = "æ˜¾ç¤ºç‰©å“æ•°é‡"
L["CONFIG_SHOW_ITEM_COUNT_DESC"] = "æ˜¾ç¤ºç‰©å“æ•°é‡æç¤ºï¼Œå±•ç¤ºä½ åœ¨æ‰€æœ‰è§’è‰²ä¸­æ‹¥æœ‰çš„æ¯ç§ç‰©å“æ•°é‡ã€‚"
L["CONFIG_THEME_COLOR"] = "ä¸»ä¸»é¢˜è‰²"
L["CONFIG_THEME_COLOR_DESC"] = "é€‰æ‹©æ’ä»¶ç•Œé¢çš„ä¸»å¼ºè°ƒè‰²ã€‚"
L["CONFIG_THEME_APPLIED"] = "%s ä¸»é¢˜å·²åº”ç”¨ï¼"
L["CONFIG_THEME_RESET_DESC"] = "å°†æ‰€æœ‰ä¸»é¢˜è‰²é‡ç½®ä¸ºé»˜è®¤ç´«è‰²ä¸»é¢˜ã€‚"
L["CONFIG_NOTIFICATIONS"] = "é€šçŸ¥"
L["CONFIG_NOTIFICATIONS_DESC"] = "é…ç½®æ˜¾ç¤ºå“ªäº›é€šçŸ¥ã€‚"
L["CONFIG_ENABLE_NOTIFICATIONS"] = "å¯ç”¨é€šçŸ¥"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "æ˜¾ç¤ºæ”¶è—å“äº‹ä»¶å¼¹çª—é€šçŸ¥ã€‚"
L["CONFIG_SHOW_UPDATE_NOTES"] = "å†æ¬¡æ˜¾ç¤ºæ›´æ–°è¯´æ˜"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "ä¸‹æ¬¡ç™»å½•æ—¶æ˜¾ç¤ºã€Œæ›´æ–°å†…å®¹ã€çª—å£ã€‚"
L["CONFIG_UPDATE_NOTES_SHOWN"] = "æ›´æ–°é€šçŸ¥å°†åœ¨ä¸‹æ¬¡ç™»å½•æ—¶æ˜¾ç¤ºã€‚"
L["CONFIG_RESET_PLANS"] = "é‡ç½®å·²å®Œæˆè®¡åˆ’"
L["CONFIG_RESET_PLANS_FORMAT"] = "å·²ç§»é™¤ %d ä¸ªå·²å®Œæˆè®¡åˆ’ã€‚"
L["CONFIG_TAB_FILTERING"] = "æ ‡ç­¾é¡µç­›é€‰"
L["CONFIG_TAB_FILTERING_DESC"] = "é€‰æ‹©ä¸»çª—å£ä¸­å¯è§çš„æ ‡ç­¾é¡µã€‚"
L["CONFIG_CHARACTER_MGMT"] = "è§’è‰²ç®¡ç†"
L["CONFIG_CHARACTER_MGMT_DESC"] = "ç®¡ç†è¿½è¸ªçš„è§’è‰²å¹¶ç§»é™¤æ—§æ•°æ®ã€‚"
L["CONFIG_DELETE_CHAR"] = "åˆ é™¤è§’è‰²æ•°æ®"
L["CONFIG_DELETE_CHAR_DESC"] = "æ°¸ä¹…ç§»é™¤æ‰€é€‰è§’è‰²çš„æ‰€æœ‰å­˜å‚¨æ•°æ®ã€‚"
L["CONFIG_FONT_SCALING"] = "å­—ä½“ä¸ç¼©æ”¾"
L["CONFIG_FONT_SCALING_DESC"] = "è°ƒæ•´å­—ä½“å’Œå¤§å°ç¼©æ”¾ã€‚"
L["CONFIG_FONT_FAMILY"] = "å­—ä½“"
L["CONFIG_ADVANCED"] = "é«˜çº§"
L["CONFIG_ADVANCED_DESC"] = "é«˜çº§è®¾ç½®å’Œæ•°æ®åº“ç®¡ç†ã€‚è¯·è°¨æ…ä½¿ç”¨ï¼"
L["CONFIG_DEBUG_MODE"] = "è°ƒè¯•æ¨¡å¼"
L["CONFIG_DEBUG_MODE_DESC"] = "å¯ç”¨è¯¦ç»†æ—¥å¿—ä»¥ä¾¿è°ƒè¯•ã€‚ä»…åœ¨æ’æŸ¥é—®é¢˜æ—¶å¯ç”¨ã€‚"
L["CONFIG_DEBUG_VERBOSE"] = "è¯¦ç»†è°ƒè¯•ï¼ˆç¼“å­˜/æ‰«æ/æç¤ºæ—¥å¿—ï¼‰"
L["CONFIG_DEBUG_VERBOSE_DESC"] = "è°ƒè¯•æ¨¡å¼ä¸‹åŒæ—¶æ˜¾ç¤ºè´§å¸/å£°æœ›ç¼“å­˜ã€èƒŒåŒ…æ‰«æã€æç¤ºä¸ä¸“ä¸šæ—¥å¿—ã€‚å…³é—­å¯å‡å°‘èŠå¤©åˆ·å±ã€‚"
L["CONFIG_DB_STATS"] = "æ˜¾ç¤ºæ•°æ®åº“ç»Ÿè®¡"
L["CONFIG_DB_STATS_DESC"] = "æ˜¾ç¤ºå½“å‰æ•°æ®åº“å¤§å°å’Œä¼˜åŒ–ç»Ÿè®¡ã€‚"
L["CONFIG_OPTIMIZE_NOW"] = "ç«‹å³ä¼˜åŒ–æ•°æ®åº“"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "è¿è¡Œæ•°æ®åº“ä¼˜åŒ–å™¨ä»¥æ¸…ç†å’Œå‹ç¼©å­˜å‚¨çš„æ•°æ®ã€‚"
L["CONFIG_COMMANDS_HEADER"] = "æ–œæ å‘½ä»¤"

-- Sorting
L["SORT_BY_LABEL"] = "æ’åºï¼š"
L["SORT_MODE_DEFAULT"] = "é»˜è®¤é¡ºåº"
L["SORT_MODE_MANUAL"] = "æ‰‹åŠ¨ï¼ˆè‡ªå®šä¹‰é¡ºåºï¼‰"
L["SORT_MODE_NAME"] = "åç§°ï¼ˆA-Zï¼‰"
L["SORT_MODE_LEVEL"] = "ç­‰çº§ï¼ˆæœ€é«˜ï¼‰"
L["SORT_MODE_ILVL"] = "è£…ç­‰ï¼ˆæœ€é«˜ï¼‰"
L["SORT_MODE_GOLD"] = "é‡‘å¸ï¼ˆæœ€é«˜ï¼‰"

-- Gold Management
L["GOLD_MANAGER_BTN"] = "é‡‘å¸ç›®æ ‡"
L["GOLD_MANAGEMENT_TITLE"] = "é‡‘å¸ç›®æ ‡"
L["GOLD_MANAGEMENT_ENABLE"] = "å¯ç”¨é‡‘å¸ç®¡ç†"
L["GOLD_MANAGEMENT_MODE"] = "ç®¡ç†æ¨¡å¼"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "ä»…å­˜å…¥"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "é‡‘å¸è¶…è¿‡ X æ—¶ï¼Œè¶…é¢è‡ªåŠ¨å­˜å…¥æˆ˜å›¢é“¶è¡Œã€‚"
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "ä»…å–æ¬¾"
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "é‡‘å¸å°‘äº X æ—¶ï¼Œå·®é¢è‡ªåŠ¨ä»æˆ˜å›¢é“¶è¡Œå–æ¬¾ã€‚"
L["GOLD_MANAGEMENT_MODE_BOTH"] = "ä¸¤è€…"
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "è‡ªåŠ¨ç»´æŒè§’è‰²é‡‘å¸æ°å¥½ä¸º Xï¼ˆå¤šåˆ™å­˜ï¼Œå°‘åˆ™å–ï¼‰ã€‚"
L["GOLD_MANAGEMENT_TARGET"] = "ç›®æ ‡é‡‘å¸æ•°é‡"
L["GOLD_MANAGEMENT_HELPER"] = "è¾“å…¥ä½ æƒ³åœ¨æ­¤è§’è‰²ä¸Šä¿ç•™çš„é‡‘å¸æ•°é‡ã€‚æ‰“å¼€é“¶è¡Œæ—¶æ’ä»¶å°†è‡ªåŠ¨ç®¡ç†ä½ çš„é‡‘å¸ã€‚"
L["GOLD_MANAGEMENT_CHAR_ONLY"] = "ä»…æ­¤è§’è‰² (%s)"
L["GOLD_MANAGEMENT_CHAR_ONLY_DESC"] = "ä»…ä¸ºæ­¤è§’è‰²ä½¿ç”¨å•ç‹¬çš„é‡‘å¸ç®¡ç†è®¾ç½®ã€‚å…¶ä»–è§’è‰²å°†ä½¿ç”¨å…±äº«é…ç½®ã€‚"
L["GOLD_MGMT_PROFILE_TITLE"] = "é…ç½®ï¼ˆæ‰€æœ‰è§’è‰²ï¼‰"
L["GOLD_MGMT_USING_PROFILE"] = "ä½¿ç”¨é…ç½®"
L["GOLD_MGMT_MODE_SHORT_DEPOSIT"] = "å­˜å…¥"
L["GOLD_MGMT_MODE_SHORT_WITHDRAW"] = "å–å‡º"
L["GOLD_MGMT_MODE_SHORT_BOTH"] = "åŒå‘"
L["MONEY_LOGS_BTN"] = "é‡‘å¸è®°å½•"
L["MONEY_LOGS_TITLE"] = "é‡‘å¸è®°å½•"
L["MONEY_LOGS_SUMMARY_TITLE"] = "è§’è‰²è´¡çŒ®"
L["MONEY_LOGS_COLUMN_NET"] = "å‡€é¢"
L["MONEY_LOGS_COLUMN_TIME"] = "æ—¶é—´"
L["MONEY_LOGS_COLUMN_CHARACTER"] = "è§’è‰²"
L["MONEY_LOGS_COLUMN_TYPE"] = "ç±»å‹"
L["MONEY_LOGS_COLUMN_TOFROM"] = "æ¥æº/å»å‘"
L["MONEY_LOGS_COLUMN_AMOUNT"] = "é‡‘é¢"
L["MONEY_LOGS_EMPTY"] = "æš‚æ— é‡‘å¸äº¤æ˜“è®°å½•ã€‚"
L["MONEY_LOGS_DEPOSIT"] = "å­˜å…¥"
L["MONEY_LOGS_WITHDRAW"] = "å–å‡º"
L["MONEY_LOGS_TO_WARBAND_BANK"] = "æˆ˜å›¢é“¶è¡Œ"
L["MONEY_LOGS_FROM_WARBAND_BANK"] = "ä»æˆ˜å›¢é“¶è¡Œ"
L["MONEY_LOGS_RESET"] = "é‡ç½®"
L["MONEY_LOGS_FILTER_ALL"] = "å…¨éƒ¨"
L["MONEY_LOGS_CHAT_DEPOSIT"] = "|cff00ff00é‡‘å¸è®°å½•:|r å‘æˆ˜å›¢é“¶è¡Œå­˜å…¥ %s"
L["MONEY_LOGS_CHAT_WITHDRAW"] = "|cffff9900é‡‘å¸è®°å½•:|r ä»æˆ˜å›¢é“¶è¡Œå–å‡º %s"

-- Gear UI
L["GEAR_UPGRADE_CURRENCIES"] = "å‡çº§è´§å¸"
L["GEAR_CHARACTER_STATS"] = "è§’è‰²å±æ€§"
L["GEAR_NO_ITEM_EQUIPPED"] = "æ­¤æ ä½æœªè£…å¤‡ç‰©å“ã€‚"
L["GEAR_NO_PREVIEW"] = "æ— é¢„è§ˆ"
L["GEAR_STATS_CURRENT_ONLY"] = "å±æ€§ä»…å¯¹\nå½“å‰è§’è‰²å¯ç”¨"
L["GEAR_SLOT_RING1"] = "æˆ’æŒ‡ 1"
L["GEAR_SLOT_RING2"] = "æˆ’æŒ‡ 2"
L["GEAR_SLOT_TRINKET1"] = "é¥°å“ 1"
L["GEAR_SLOT_TRINKET2"] = "é¥°å“ 2"
L["GEAR_UPGRADE_AVAILABLE_FORMAT"] = "å¯å‡çº§è‡³ %s %d/%d%s"
L["GEAR_UPGRADES_WITH_CURRENCY_FORMAT"] = "å½“å‰è´§å¸å¯å‡çº§ %dæ¬¡"
L["GEAR_CRESTS_GOLD_ONLY"] = "æ‰€éœ€çº¹ç« ï¼š0ï¼ˆä»…éœ€é‡‘å¸ â€” æ­¤å‰å·²è¾¾æˆï¼‰"
L["GEAR_UPGRADES_GOLD_ONLY_FORMAT"] = "%dæ¬¡ä»…éœ€é‡‘å¸å‡çº§ï¼ˆæ­¤å‰å·²è¾¾æˆï¼‰"
L["GEAR_NEED_MORE_CRESTS_FORMAT"] = "%s %d/%d â€” éœ€è¦æ›´å¤šçº¹ç« "
L["GEAR_CRAFTED_NO_CRESTS"] = "æ²¡æœ‰å¯ç”¨äºå†é€ çš„çº¹ç« "
L["GEAR_TRACK_CRAFTED_FALLBACK"] = "åˆ¶é€ "
L["GEAR_CRAFTED_MAX_ILVL_LINE"] = "%sï¼ˆæœ€é«˜è£…ç­‰ %dï¼‰"
L["GEAR_CRAFTED_RECAST_TO_LINE"] = "å†é€ è‡³ %sï¼ˆè£…ç­‰ %dï¼‰"
L["GEAR_CRAFTED_COST_DAWNCREST"] = "æ¶ˆè€—ï¼š%d %s é»æ˜çº¹ç« "
L["GEAR_CRAFTED_NEXT_TIER_CRESTS"] = "%sï¼ˆè£…ç­‰ %dï¼‰ï¼šçº¹ç«  %d/%dï¼ˆè¿˜éœ€ %dï¼‰"
L["GEAR_TAB_TITLE"] = "è£…å¤‡ç®¡ç†"
L["GEAR_TAB_DESC"] = "å·²è£…å¤‡ã€å‡çº§é€‰é¡¹åŠè·¨è§’è‰²å‡çº§å€™é€‰"
L["GEAR_STORAGE_WARBOUND"] = "æˆ˜å›¢ç»‘å®š"
L["GEAR_STORAGE_BOE"] = "è£…ç»‘"
L["GEAR_STORAGE_TITLE"] = "å­˜å‚¨å‡çº§æ¨è"
L["GEAR_STORAGE_EMPTY"] = "æœªæ‰¾åˆ°é€‚åˆè¯¥è§’è‰²çš„æ›´å¥½è£…ç»‘ / æˆ˜å›¢ç»‘å®šå‡çº§ã€‚"

-- Characters UI
L["WOW_TOKEN_LABEL"] = "WOWä»£å¸"

-- Statistics UI
L["FORMAT_BUTTON"] = "æ ¼å¼"
L["STATS_PLAYED_STEAM_ZERO"] = "0 å°æ—¶"
L["STATS_PLAYED_STEAM_FLOAT"] = "%.1f å°æ—¶"
L["STATS_PLAYED_STEAM_THOUSAND"] = "%d,%03d å°æ—¶"
L["STATS_PLAYED_STEAM_INT"] = "%d å°æ—¶"

-- Professions UI
L["SHOW_ALL"] = "æ˜¾ç¤ºå…¨éƒ¨"

-- Social
L["DISCORD_TOOLTIP"] = "Warband Nexus Discord"

-- Collection Source Filters
L["SOURCE_OTHER"] = "å…¶ä»–"

-- Expansion / Content Names
L["CONTENT_KHAZ_ALGAR"] = "å¡å…¹é˜¿åŠ "
L["CONTENT_DRAGON_ISLES"] = "å·¨é¾™ç¾¤å²›"

-- Module Disabled
L["MODULE_DISABLED_DESC_FORMAT"] = "åœ¨%sä¸­å¯ç”¨ä»¥ä½¿ç”¨%sã€‚"

-- Plans UI (extended)
L["PART_OF_FORMAT"] = "å±äºï¼š%s"
L["LOCKED_WORLD_QUESTS"] = "å·²é”å®š â€” å®Œæˆä¸–ç•Œä»»åŠ¡ä»¥è§£é”"
L["QUEST_ID_FORMAT"] = "ä»»åŠ¡IDï¼š%s"

-- Stats
L["TRACK_ACTIVITIES"] = "è¿½è¸ªæ´»åŠ¨"

L["ACHIEVEMENT_SERIES"] = "æˆå°±ç³»åˆ—"
L["LOADING_ACHIEVEMENTS"] = "åŠ è½½æˆå°±ä¸­..."
L["TAB_GEAR"] = "è£…å¤‡"

-- Keybinding globals (must be global for WoW's keybinding UI)
BINDING_HEADER_WARBANDNEXUS = "Warband Nexus"
BINDING_NAME_WARBANDNEXUS_TOGGLE = "æ˜¾ç¤º/éšè—ä¸»çª—å£"

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
L["CLICK_TO_COPY_LINK"] = "Click to copy link"
L["CLICK_FOR_WOWHEAD_LINK"] = "Click for Wowhead link"
L["PLAN_ACTION_COMPLETE"] = "Complete the Plan"
L["PLAN_ACTION_DELETE"] = "Delete the Plan"
L["OBJECTIVE_INDEX_FORMAT"] = "Objective %d"
L["QUEST_PROGRESS_FORMAT"] = "Progress: %d/%d (%d%%)"
L["QUEST_TIME_REMAINING_FORMAT"] = "%s remaining"
L["EVENT_GROUP_SOIREE"] = "Saltheril's Soiree"
L["EVENT_GROUP_ABUNDANCE"] = "Abundance"
L["EVENT_GROUP_HARANIR"] = "Legends of the Haranir"
L["EVENT_GROUP_STORMARION"] = "Stormarion Assault"
L["QUEST_CATEGORY_DESC_WEEKLY"] = "Weekly objectives, hunts, sparks, world boss, delves"
L["QUEST_CATEGORY_DESC_WORLD"] = "Zone-wide repeatable world quests"
L["QUEST_CATEGORY_DESC_DAILY"] = "Daily repeatable quests from NPCs"
L["QUEST_CATEGORY_DESC_EVENTS"] = "Bonus objectives, tasks, and activities"
L["GEAR_NO_TRACKED_CHARACTERS_TITLE"] = "No tracked characters"
L["GEAR_NO_TRACKED_CHARACTERS_DESC"] = "Log in to a character to start tracking gear."
L["SOURCE_TYPE_CATEGORY_FORMAT"] = "Category %d"
L["TYPE_ITEM"] = ITEM or "Item"
L["CTRL_C_LABEL"] = "Ctrl+C"
L["WOW_TOKEN_COUNT_LABEL"] = "Tokens"
L["NOT_AVAILABLE_SHORT"] = "N/A"
L["COLLECTION_RULE_API_NOT_AVAILABLE"] = "API不可用"
L["COLLECTION_RULE_INVALID_MOUNT"] = "无效坐骑"
L["COLLECTION_RULE_FACTION_CLASS_RESTRICTED"] = "受阵营或职业限制"

