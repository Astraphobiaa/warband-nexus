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
L["ADDON_LOADED"] = "Warband Nexus å·²åŠ è½½ã€‚è¾“å…¥ /wn æˆ– /warbandnexus æ‰“å¼€é€‰é¡¹ã€‚"
-- Slash Commands
L["SLASH_HELP"] = "å¯ç”¨å‘½ä»¤ï¼š"
L["SLASH_OPTIONS"] = "æ‰“å¼€é€‰é¡¹é¢æ¿"
L["SLASH_SCAN"] = "æ‰«ææˆ˜å›¢é“¶è¡Œ"
L["SLASH_SHOW"] = "æ˜¾ç¤º/éšè—ä¸»çª—å£"
L["SLASH_DEPOSIT"] = "æ‰“å¼€å­˜å…¥é˜Ÿåˆ—"
L["SLASH_SEARCH"] = "æœç´¢ç‰©å“"
L["KEYBINDING"] = "å¿«æ·é”®"
L["KEYBINDING_UNBOUND"] = "æœªè®¾ç½®"
L["KEYBINDING_PRESS_KEY"] = "è¯·æŒ‰ä¸€ä¸ªé”®..."
L["KEYBINDING_TOOLTIP"] = "ç‚¹å‡»è®¾ç½®å¿«æ·é”®ä»¥åˆ‡æ¢ Warband Nexusã€‚\næŒ‰ ESC å–æ¶ˆã€‚"
L["KEYBINDING_CLEAR"] = "æ¸…é™¤å¿«æ·é”®"
L["KEYBINDING_REPLACES"] = "è¯¥æŒ‰é”®åŸæœ¬ç»‘å®šä¸º %s â€” ç°åœ¨ç”¨äº Warband Nexusã€‚"
L["KEYBINDING_SAVED"] = "å¿«æ·é”®å·²ä¿å­˜ã€‚"
L["KEYBINDING_COMBAT"] = "æˆ˜æ–—ä¸­æ— æ³•æ›´æ”¹å¿«æ·é”®ã€‚"
L["KEYBINDING_SETFAILED"] = "æ— æ³•åˆ†é…è¯¥æŒ‰é”®ã€‚è¯·å°è¯• Esc > é€‰é¡¹ > æŒ‰é”®è®¾ç½®ã€‚"
L["KEYBINDING_VERIFY_FAIL"] = "è¯¥æŒ‰é”®ä»ç»‘å®šåˆ°å…¶ä»–æ“ä½œï¼ˆ%sï¼‰ã€‚è¯·æ‰“å¼€ Esc > é€‰é¡¹ > æŒ‰é”®è®¾ç½®ï¼Œæ¸…é™¤å†²çªåå†åœ¨æ­¤åˆ†é…ã€‚"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "å¸¸è§„è®¾ç½®"
L["GENERAL_SETTINGS_DESC"] = "é…ç½®æ’ä»¶å¸¸è§„è®¾ç½®"
L["ENABLE_ADDON"] = "å¯ç”¨æ’ä»¶"
L["ENABLE_ADDON_DESC"] = "å¯ç”¨æˆ–ç¦ç”¨ Warband Nexus åŠŸèƒ½"
L["MINIMAP_ICON"] = "æ˜¾ç¤ºå°åœ°å›¾å›¾æ ‡"
L["MINIMAP_ICON_DESC"] = "æ˜¾ç¤ºæˆ–éšè—å°åœ°å›¾æŒ‰é’®"
L["DEBUG_MODE"] = "è°ƒè¯•æ—¥å¿—"
L["DEBUG_MODE_DESC"] = "åœ¨èŠå¤©æ¡†è¾“å‡ºè¯¦ç»†è°ƒè¯•ä¿¡æ¯ä»¥ä¾¿æ’æŸ¥é—®é¢˜"
L["DEBUG_TRYCOUNTER_LOOT"] = "å°è¯•è®¡æ•°æˆ˜åˆ©å“è°ƒè¯•"
L["DEBUG_TRYCOUNTER_LOOT_DESC"] = "ä»…è®°å½•æˆ˜åˆ©å“æµç¨‹ï¼ˆLOOT_OPENEDã€æ¥æºè§£æã€åŒºåŸŸå›é€€ï¼‰ã€‚å£°æœ›/è´§å¸ç¼“å­˜æ—¥å¿—å·²æŠ‘åˆ¶ã€‚"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "æ‰«æè®¾ç½®"
L["SCANNING_SETTINGS_DESC"] = "é…ç½®é“¶è¡Œæ‰«æè¡Œä¸º"
L["AUTO_SCAN"] = "æ‰“å¼€é“¶è¡Œæ—¶è‡ªåŠ¨æ‰«æ"
L["AUTO_SCAN_DESC"] = "æ‰“å¼€æˆ˜å›¢é“¶è¡Œæ—¶è‡ªåŠ¨æ‰«æ"
L["SCAN_DELAY"] = "æ‰«æèŠ‚æµå»¶è¿Ÿ"
L["SCAN_DELAY_DESC"] = "æ‰«ææ“ä½œä¹‹é—´çš„å»¶è¿Ÿï¼ˆç§’ï¼‰"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "å­˜å…¥è®¾ç½®"
L["DEPOSIT_SETTINGS_DESC"] = "é…ç½®ç‰©å“å­˜å…¥è¡Œä¸º"
L["GOLD_RESERVE"] = "é‡‘å¸å‚¨å¤‡"
L["GOLD_RESERVE_DESC"] = "ä¸ªäººèƒŒåŒ…ä¸­ä¿ç•™çš„æœ€ä½é‡‘å¸æ•°é‡ï¼ˆé‡‘å¸ï¼‰"
L["AUTO_DEPOSIT_REAGENTS"] = "è‡ªåŠ¨å­˜å…¥ææ–™"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "æ‰“å¼€é“¶è¡Œæ—¶å°†ææ–™åŠ å…¥å­˜å…¥é˜Ÿåˆ—"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "æ˜¾ç¤º"
L["DISPLAY_SETTINGS_DESC"] = "è‡ªå®šä¹‰ç‰©å“å’Œä¿¡æ¯çš„æ˜¾ç¤ºæ–¹å¼ã€‚"
L["SHOW_ITEM_LEVEL"] = "æ˜¾ç¤ºç‰©å“ç­‰çº§"
L["SHOW_ITEM_LEVEL_DESC"] = "åœ¨è£…å¤‡ä¸Šæ˜¾ç¤ºç‰©å“ç­‰çº§"
L["SHOW_ITEM_COUNT"] = "æ˜¾ç¤ºç‰©å“æ•°é‡"
L["SHOW_ITEM_COUNT_DESC"] = "åœ¨ç‰©å“ä¸Šæ˜¾ç¤ºå †å æ•°é‡"
L["HIGHLIGHT_QUALITY"] = "æŒ‰å“è´¨é«˜äº®"
L["HIGHLIGHT_QUALITY_DESC"] = "æ ¹æ®ç‰©å“å“è´¨æ·»åŠ å½©è‰²è¾¹æ¡†"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "æ ‡ç­¾é¡µè®¾ç½®"
L["TAB_SETTINGS_DESC"] = "é…ç½®æˆ˜å›¢é“¶è¡Œæ ‡ç­¾é¡µè¡Œä¸º"
L["IGNORED_TABS"] = "å¿½ç•¥çš„æ ‡ç­¾é¡µ"
L["IGNORED_TABS_DESC"] = "é€‰æ‹©è¦ä»æ‰«æå’Œæ“ä½œä¸­æ’é™¤çš„æ ‡ç­¾é¡µ"
L["TAB_1"] = "æˆ˜å›¢æ ‡ç­¾é¡µ 1"
L["TAB_2"] = "æˆ˜å›¢æ ‡ç­¾é¡µ 2"
L["TAB_3"] = "æˆ˜å›¢æ ‡ç­¾é¡µ 3"
L["TAB_4"] = "æˆ˜å›¢æ ‡ç­¾é¡µ 4"
L["TAB_5"] = "æˆ˜å›¢æ ‡ç­¾é¡µ 5"

-- Scanner Module
L["SCAN_STARTED"] = "æ­£åœ¨æ‰«ææˆ˜å›¢é“¶è¡Œ..."
L["SCAN_COMPLETE"] = "æ‰«æå®Œæˆã€‚åœ¨ %d ä¸ªæ ¼å­ä¸­å‘ç° %d ä»¶ç‰©å“ã€‚"
L["SCAN_FAILED"] = "æ‰«æå¤±è´¥ï¼šæˆ˜å›¢é“¶è¡Œæœªæ‰“å¼€ã€‚"
L["SCAN_TAB"] = "æ­£åœ¨æ‰«ææ ‡ç­¾é¡µ %d..."
L["CACHE_CLEARED"] = "ç‰©å“ç¼“å­˜å·²æ¸…é™¤ã€‚"
L["CACHE_UPDATED"] = "ç‰©å“ç¼“å­˜å·²æ›´æ–°ã€‚"

-- Banker Module
L["BANK_NOT_OPEN"] = "æˆ˜å›¢é“¶è¡Œæœªæ‰“å¼€ã€‚"
L["DEPOSIT_STARTED"] = "æ­£åœ¨å¼€å§‹å­˜å…¥æ“ä½œ..."
L["DEPOSIT_COMPLETE"] = "å­˜å…¥å®Œæˆã€‚å·²è½¬ç§» %d ä»¶ç‰©å“ã€‚"
L["DEPOSIT_CANCELLED"] = "å­˜å…¥å·²å–æ¶ˆã€‚"
L["DEPOSIT_QUEUE_EMPTY"] = "å­˜å…¥é˜Ÿåˆ—ä¸ºç©ºã€‚"
L["DEPOSIT_QUEUE_CLEARED"] = "å­˜å…¥é˜Ÿåˆ—å·²æ¸…ç©ºã€‚"
L["ITEM_QUEUED"] = "%s å·²åŠ å…¥å­˜å…¥é˜Ÿåˆ—ã€‚"
L["ITEM_REMOVED"] = "%s å·²ä»é˜Ÿåˆ—ä¸­ç§»é™¤ã€‚"
L["GOLD_DEPOSITED"] = "å·²å°† %s é‡‘å¸å­˜å…¥æˆ˜å›¢é“¶è¡Œã€‚"
L["INSUFFICIENT_GOLD"] = "é‡‘å¸ä¸è¶³ï¼Œæ— æ³•å­˜å…¥ã€‚"

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "æ— æ•ˆæ•°é‡ã€‚"
L["WITHDRAW_BANK_NOT_OPEN"] = "å¿…é¡»æ‰“å¼€é“¶è¡Œæ‰èƒ½å–æ¬¾ï¼"
L["WITHDRAW_IN_COMBAT"] = "æˆ˜æ–—ä¸­æ— æ³•å–æ¬¾ã€‚"
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "æˆ˜å›¢é“¶è¡Œé‡‘å¸ä¸è¶³ã€‚"
L["WITHDRAWN_LABEL"] = "å·²å–å‡ºï¼š"
L["WITHDRAW_API_UNAVAILABLE"] = "å–æ¬¾ API ä¸å¯ç”¨ã€‚"
L["SORT_IN_COMBAT"] = "æˆ˜æ–—ä¸­æ— æ³•æ•´ç†ã€‚"

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_CATEGORY_FORMAT"] = "æœç´¢ %s..."
L["BTN_SCAN"] = "æ‰«æé“¶è¡Œ"
L["BTN_DEPOSIT"] = "å­˜å…¥é˜Ÿåˆ—"
L["BTN_SORT"] = "æ•´ç†é“¶è¡Œ"
L["BTN_CLEAR_QUEUE"] = "æ¸…ç©ºé˜Ÿåˆ—"
L["BTN_DEPOSIT_ALL"] = "å…¨éƒ¨å­˜å…¥"
L["BTN_DEPOSIT_GOLD"] = "å­˜å…¥é‡‘å¸"
L["ENABLE_MODULE"] = "å¯ç”¨æ¨¡å—"

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
L["HEADER_REALM_GOLD"] = "æœåŠ¡å™¨é‡‘å¸"
L["HEADER_REALM_TOTAL"] = "æœåŠ¡å™¨æ€»è®¡"
L["CHARACTER_LAST_SEEN_FORMAT"] = "ä¸Šæ¬¡ç™»å½•ï¼š%s"
L["CHARACTER_GOLD_FORMAT"] = "é‡‘å¸ï¼š%s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "æœ¬æœåŠ¡å™¨æ‰€æœ‰è§’è‰²çš„é‡‘å¸åˆè®¡"
L["MAX_LEVEL"] = "æ»¡çº§"
-- Items Tab
L["ITEMS_HEADER"] = "é“¶è¡Œç‰©å“"
L["ITEMS_HEADER_DESC"] = "æµè§ˆå’Œç®¡ç†ä½ çš„æˆ˜å›¢é“¶è¡Œå’Œä¸ªäººé“¶è¡Œ"
L["ITEMS_WARBAND_BANK"] = "æˆ˜å›¢é“¶è¡Œ"
L["GROUP_CONTAINER"] = "å®¹å™¨"

-- Storage Tab
L["STORAGE_HEADER"] = "å­˜å‚¨æµè§ˆå™¨"
L["STORAGE_HEADER_DESC"] = "æŒ‰ç±»å‹æµè§ˆæ‰€æœ‰ç‰©å“"
L["STORAGE_WARBAND_BANK"] = "æˆ˜å›¢é“¶è¡Œ"
L["STORAGE_PERSONAL_BANKS"] = "ä¸ªäººé“¶è¡Œ"
L["STORAGE_TOTAL_SLOTS"] = "æ€»æ ¼å­æ•°"
L["STORAGE_FREE_SLOTS"] = "ç©ºé—²æ ¼å­"
L["STORAGE_BAG_HEADER"] = "æˆ˜å›¢èƒŒåŒ…"
L["STORAGE_PERSONAL_HEADER"] = "ä¸ªäººé“¶è¡Œ"

-- Plans Tab
L["PLANS_MY_PLANS"] = "å¾…åŠåˆ—è¡¨"
L["PLANS_COLLECTIONS"] = "å¾…åŠæ¸…å•"
L["PLANS_ADD_CUSTOM"] = "æ·»åŠ è‡ªå®šä¹‰è®¡åˆ’"
L["PLANS_NO_RESULTS"] = "æœªæ‰¾åˆ°ç»“æœã€‚"
L["PLANS_ALL_COLLECTED"] = "æ‰€æœ‰ç‰©å“å·²æ”¶é›†ï¼"
L["PLANS_RECIPE_HELP"] = "å³é”®ç‚¹å‡»èƒŒåŒ…ä¸­çš„é…æ–¹å¯æ·»åŠ åˆ°æ­¤ã€‚"
L["COLLECTION_PLANS"] = "å¾…åŠæ¸…å•"
L["SEARCH_PLANS"] = "æœç´¢è®¡åˆ’..."
L["COMPLETED_PLANS"] = "å·²å®Œæˆè®¡åˆ’"
L["SHOW_COMPLETED"] = "æ˜¾ç¤ºå·²å®Œæˆ"
L["SHOW_COMPLETED_HELP"] = "å¾…åŠä¸å‘¨è¿›åº¦ï¼šæœªå‹¾é€‰=ä»è¿›è¡Œä¸­çš„è®¡åˆ’ï¼›å‹¾é€‰=ä»…å·²å®Œæˆçš„è®¡åˆ’ã€‚æµè§ˆæ ‡ç­¾ï¼šæœªå‹¾é€‰=æœªæ”¶è—ï¼ˆå¼€å¯â€œæ˜¾ç¤ºå·²è®¡åˆ’â€æ—¶ä»…é™åˆ—è¡¨å†…ï¼‰ï¼›å‹¾é€‰=åˆ—è¡¨ä¸Šå·²æ”¶è—çš„æ¡ç›®ï¼ˆâ€œæ˜¾ç¤ºå·²è®¡åˆ’â€ä»ä¼šé™åˆ¶åˆ—è¡¨ï¼‰ã€‚"
L["SHOW_PLANNED"] = "æ˜¾ç¤ºè®¡åˆ’ä¸­"
L["SHOW_PLANNED_HELP"] = "ä»…æµè§ˆæ ‡ç­¾ï¼ˆåœ¨å¾…åŠä¸å‘¨è¿›åº¦ä¸­éšè—ï¼‰ï¼šå‹¾é€‰=ä»…æ˜¾ç¤ºä½ åŠ å…¥å¾…åŠçš„ç›®æ ‡ã€‚â€œæ˜¾ç¤ºå·²å®Œæˆâ€å…³=ä»ç¼ºçš„ï¼›å¼€=å·²å®Œæˆçš„ï¼›ä¸¤é¡¹éƒ½å¼€=è¯¥åˆ†ç±»å…¨éƒ¨å·²è®¡åˆ’ï¼›ä¸¤é¡¹éƒ½å…³=å®Œæ•´æœªæ”¶è—æµè§ˆã€‚"
L["NO_PLANNED_ITEMS"] = "æš‚æ— è®¡åˆ’çš„ %s"
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
L["REP_HEADER_WARBAND"] = "æˆ˜å›¢å£°æœ›"
L["REP_HEADER_CHARACTER"] = "è§’è‰²å£°æœ›"
L["REP_STANDING_FORMAT"] = "å£°æœ›ç­‰çº§ï¼š%s"

-- Currency Tab
L["CURRENCY_HEADER_WARBAND"] = "æˆ˜å›¢å¯è½¬ç§»"
L["CURRENCY_HEADER_CHARACTER"] = "è§’è‰²ç»‘å®š"

-- PvE Tab
L["PVE_HEADER_DELVES"] = "æ¢ç´¢"
L["PVE_HEADER_WORLD_BOSS"] = "ä¸–ç•Œé¦–é¢†"

-- Statistics
L["STATS_TOTAL_ITEMS"] = "ç‰©å“æ€»æ•°"
L["STATS_TOTAL_SLOTS"] = "æ€»æ ¼å­æ•°"
L["STATS_FREE_SLOTS"] = "ç©ºé—²æ ¼å­"
L["STATS_USED_SLOTS"] = "å·²ç”¨æ ¼å­"
L["STATS_TOTAL_VALUE"] = "æ€»ä»·å€¼"
L["COLLECTED"] = "å·²æ”¶é›†"
-- Tooltips
L["TOOLTIP_WARBAND_BANK"] = "æˆ˜å›¢é“¶è¡Œ"
L["TOOLTIP_TAB"] = "æ ‡ç­¾é¡µ"
L["TOOLTIP_SLOT"] = "æ ¼å­"
L["TOOLTIP_COUNT"] = "æ•°é‡"
L["CHARACTER_INVENTORY"] = "èƒŒåŒ…"
L["CHARACTER_BANK"] = "ä¸ªäººé“¶è¡Œ"

-- Try Counter
L["TRY_COUNT"] = "å°è¯•æ¬¡æ•°"
L["SET_TRY_COUNT"] = "è®¾ç½®å°è¯•æ¬¡æ•°"
L["TRY_COUNT_RIGHT_CLICK_HINT"] = "å³é”®ç‚¹å‡»ä»¥ç¼–è¾‘å°è¯•æ¬¡æ•°ã€‚"
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
L["DOUBLECLICK_RESET"] = "åŒå‡»é‡ç½®ä½ç½®"

-- Error Messages
L["ERROR_GENERIC"] = "å‘ç”Ÿé”™è¯¯ã€‚"
L["ERROR_API_UNAVAILABLE"] = "æ‰€éœ€ API ä¸å¯ç”¨ã€‚"
L["ERROR_BANK_CLOSED"] = "æ— æ³•æ‰§è¡Œæ“ä½œï¼šé“¶è¡Œå·²å…³é—­ã€‚"
L["ERROR_INVALID_ITEM"] = "æŒ‡å®šçš„ç‰©å“æ— æ•ˆã€‚"
L["ERROR_PROTECTED_FUNCTION"] = "æˆ˜æ–—ä¸­æ— æ³•è°ƒç”¨å—ä¿æŠ¤å‡½æ•°ã€‚"

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "å°† %d ä»¶ç‰©å“å­˜å…¥æˆ˜å›¢é“¶è¡Œï¼Ÿ"
L["CONFIRM_CLEAR_QUEUE"] = "æ¸…ç©ºå­˜å…¥é˜Ÿåˆ—ä¸­çš„æ‰€æœ‰ç‰©å“ï¼Ÿ"
L["CONFIRM_DEPOSIT_GOLD"] = "å°† %s é‡‘å¸å­˜å…¥æˆ˜å›¢é“¶è¡Œï¼Ÿ"

-- Update Notification
L["WHATS_NEW"] = "æ›´æ–°å†…å®¹"
L["GOT_IT"] = "çŸ¥é“äº†ï¼"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "æˆå°±ç‚¹æ•°"
L["MOUNTS_COLLECTED"] = "å·²æ”¶é›†åéª‘"
L["BATTLE_PETS"] = "æˆ˜æ–—å® ç‰©"
L["TOTAL_PETS"] = "å® ç‰©æ€»æ•°"
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
L["RIGHT_CLICK_REMOVE"] = "å³é”®ç‚¹å‡»ç§»é™¤"
L["CLICK_TO_DISMISS"] = "ç‚¹å‡»å…³é—­"
L["TRACKED"] = "å·²è¿½è¸ª"
L["TRACK"] = "è¿½è¸ª"
L["TRACK_BLIZZARD_OBJECTIVES"] = "åœ¨æš´é›ªä»»åŠ¡ä¸­è¿½è¸ªï¼ˆæœ€å¤š 10 ä¸ªï¼‰"
L["NO_REQUIREMENTS"] = "æ— è¦æ±‚ï¼ˆå³æ—¶å®Œæˆï¼‰"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "æ— è®¡åˆ’æ´»åŠ¨"
L["NO_ACTIVE_CONTENT"] = "æœ¬å‘¨æ²¡æœ‰æ´»è·ƒå†…å®¹"
L["CLICK_TO_ADD_GOALS"] = "ç‚¹å‡»ä¸Šæ–¹çš„åéª‘ã€å® ç‰©æˆ–ç©å…·æµè§ˆå¹¶æ·»åŠ ç›®æ ‡ï¼"
L["UNKNOWN_QUEST"] = "æœªçŸ¥ä»»åŠ¡"
L["ALL_QUESTS_COMPLETE"] = "æ‰€æœ‰ä»»åŠ¡å·²å®Œæˆï¼"
L["CURRENT_PROGRESS"] = "å½“å‰è¿›åº¦"
L["SELECT_CONTENT"] = "é€‰æ‹©å†…å®¹ï¼š"
L["QUEST_TYPES"] = "ä»»åŠ¡ç±»å‹ï¼š"
L["WORK_IN_PROGRESS"] = "è¿›è¡Œä¸­"
L["RECIPE_BROWSER"] = "é…æ–¹æµè§ˆå™¨"
L["NO_RESULTS_FOUND"] = "æœªæ‰¾åˆ°ç»“æœã€‚"
L["TRY_ADJUSTING_SEARCH"] = "å°è¯•è°ƒæ•´æœç´¢æˆ–ç­›é€‰æ¡ä»¶ã€‚"
L["NO_COLLECTED_YET"] = "æš‚æ— å·²æ”¶é›†çš„ %s"
L["START_COLLECTING"] = "å¼€å§‹æ”¶é›†ä»¥åœ¨æ­¤æŸ¥çœ‹ï¼"
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
L["NO_CHARACTER_DATA"] = "æ— è§’è‰²æ•°æ®"
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
L["SKILL_LABEL"] = "æŠ€èƒ½ï¼š"
L["OVERALL_SKILL"] = "æ€»ä½“æŠ€èƒ½ï¼š"
L["BONUS_SKILL"] = "åŠ æˆæŠ€èƒ½ï¼š"
L["KNOWLEDGE_LABEL"] = "çŸ¥è¯†ï¼š"
L["SPEC_LABEL"] = "ä¸“ç²¾"
L["POINTS_SHORT"] = " ç‚¹"
L["RECIPES_KNOWN"] = "å·²å­¦é…æ–¹ï¼š"
L["OPEN_PROFESSION_HINT"] = "æ‰“å¼€ä¸“ä¸šçª—å£"
L["FOR_DETAILED_INFO"] = "æŸ¥çœ‹è¯¦ç»†ä¿¡æ¯"
L["CHARACTER_IS_TRACKED"] = "æ­¤è§’è‰²æ­£åœ¨è¢«è¿½è¸ªã€‚"
L["TRACKING_ACTIVE_DESC"] = "æ•°æ®æ”¶é›†å’Œæ›´æ–°å·²æ¿€æ´»ã€‚"
L["CLICK_DISABLE_TRACKING"] = "ç‚¹å‡»ç¦ç”¨è¿½è¸ªã€‚"
L["MUST_LOGIN_TO_CHANGE"] = "å¿…é¡»ç™»å½•æ­¤è§’è‰²æ‰èƒ½æ›´æ”¹è¿½è¸ªã€‚"
L["TRACKING_ENABLED"] = "è¿½è¸ªå·²å¯ç”¨"
L["CLICK_ENABLE_TRACKING"] = "ç‚¹å‡»ä¸ºæ­¤è§’è‰²å¯ç”¨è¿½è¸ªã€‚"
L["TRACKING_WILL_BEGIN"] = "æ•°æ®æ”¶é›†å°†ç«‹å³å¼€å§‹ã€‚"
L["CHARACTER_NOT_TRACKED"] = "æ­¤è§’è‰²æœªè¢«è¿½è¸ªã€‚"
L["MUST_LOGIN_TO_ENABLE"] = "å¿…é¡»ç™»å½•æ­¤è§’è‰²æ‰èƒ½å¯ç”¨è¿½è¸ªã€‚"
L["ENABLE_TRACKING"] = "å¯ç”¨è¿½è¸ª"
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
L["NO_PERMISSION"] = "æ— æƒé™"
L["NOT_IN_GUILD"] = "æœªåŠ å…¥å…¬ä¼š"
L["ITEMS_SEARCH"] = "æœç´¢ç‰©å“..."
L["NEVER"] = "ä»æœª"
L["ITEM_FALLBACK_FORMAT"] = "ç‰©å“ %s"
L["ITEM_LOADING_NAME"] = "åŠ è½½ä¸­..."
L["TAB_FORMAT"] = "æ ‡ç­¾é¡µ %d"
L["BAG_FORMAT"] = "èƒŒåŒ… %d"
L["BANK_BAG_FORMAT"] = "é“¶è¡ŒèƒŒåŒ… %d"
L["ITEM_ID_LABEL"] = "ç‰©å“ IDï¼š"
L["QUALITY_TOOLTIP_LABEL"] = "å“è´¨ï¼š"
L["STACK_LABEL"] = "å †å ï¼š"
L["RIGHT_CLICK_MOVE"] = "ç§»è‡³èƒŒåŒ…"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "æ‹†åˆ†å †å "
L["LEFT_CLICK_PICKUP"] = "æ‹¾å–"
L["ITEMS_BANK_NOT_OPEN"] = "é“¶è¡Œæœªæ‰“å¼€"
L["SHIFT_LEFT_CLICK_LINK"] = "åœ¨èŠå¤©ä¸­é“¾æ¥"
L["ITEM_DEFAULT_TOOLTIP"] = "ç‰©å“"
L["ITEMS_STATS_ITEMS"] = "%s ä»¶ç‰©å“"
L["ITEMS_STATS_SLOTS"] = "%s/%s æ ¼å­"
L["ITEMS_STATS_LAST"] = "ä¸Šæ¬¡ï¼š%s"

-- Storage Tab (extended)
L["STORAGE_DISABLED_TITLE"] = "è§’è‰²å­˜å‚¨"
L["STORAGE_SEARCH"] = "æœç´¢å­˜å‚¨..."

-- PvE Tab (extended)
L["PVE_TITLE"] = "PvE è¿›åº¦"
L["PVE_SUBTITLE"] = "å®ä¼Ÿå®åº“ã€å›¢é˜Ÿå‰¯æœ¬é”å®šä¸å²è¯—é’¥çŸ³ï¼Œè¦†ç›–ä½ çš„æˆ˜å›¢"
L["PVE_COL_EARNED"] = "è·å¾—"
L["PVE_COL_OWNED"] = "æ‹¥æœ‰"
L["PVE_COL_STASHES"] = "å­˜å‚¨"
L["PVE_COL_OWNED_VAULT"] = "æ‹¥æœ‰"
L["PVE_COL_LOOTED"] = "å·²æ‹¾å–"
L["PVE_COL_CREST"] = "çº¹ç« "
L["PVE_CREST_ADV"] = "å†’é™©è€…"
L["PVE_CREST_VET"] = "è€å…µ"
L["PVE_CREST_CHAMP"] = "å‹‡å£«"
L["PVE_CREST_HERO"] = "è‹±é›„"
L["PVE_CREST_MYTH"] = "ç¥è¯"
L["PVE_CREST_EXPLORER"] = "æ¢ç´¢è€…"
L["PVE_COL_COFFER_SHARDS"] = "å®åŒ£é’¥åŒ™ç¢ç‰‡"
L["PVE_COL_RESTORED_KEY"] = "ä¿®å¤çš„å®åŒ£é’¥åŒ™"
L["PVE_COL_VAULT_SLOT1"] = "å®åº“ 1"
L["PVE_COL_VAULT_SLOT2"] = "å®åº“ 2"
L["PVE_COL_VAULT_SLOT3"] = "å®åº“ 3"
L["PVE_NO_CHARACTER"] = "æ— è§’è‰²æ•°æ®"
L["LV_FORMAT"] = "ç­‰çº§ %d"
L["ILVL_FORMAT"] = "è£…ç­‰ %d"
L["VAULT_WORLD"] = "ä¸–ç•Œ"
L["VAULT_SLOT_FORMAT"] = "%s æ  %d"
L["VAULT_NO_PROGRESS"] = "æš‚æ— è¿›åº¦"
L["VAULT_UNLOCK_FORMAT"] = "å®Œæˆ %s é¡¹æ´»åŠ¨ä»¥è§£é”"
L["VAULT_NEXT_TIER_FORMAT"] = "ä¸‹ä¸€é˜¶ï¼šå®Œæˆ %s è·å¾— %d è£…ç­‰"
L["VAULT_REMAINING_FORMAT"] = "å‰©ä½™ï¼š%s é¡¹æ´»åŠ¨"
L["VAULT_PROGRESS_FORMAT"] = "è¿›åº¦ï¼š%s / %s"
L["OVERALL_SCORE_LABEL"] = "æ€»è¯„åˆ†ï¼š"
L["BEST_KEY_FORMAT"] = "æœ€ä½³é’¥çŸ³ï¼š+%d"
L["SCORE_FORMAT"] = "è¯„åˆ†ï¼š%s"
L["NOT_COMPLETED_SEASON"] = "æœ¬å­£æœªå®Œæˆ"
L["CURRENT_MAX_FORMAT"] = "å½“å‰ï¼š%s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "è¿›åº¦ï¼š%.1f%%"
L["NO_CAP_LIMIT"] = "æ— ä¸Šé™"
L["GREAT_VAULT"] = "å®ä¼Ÿå®åº“"
L["LOADING_PVE"] = "æ­£åœ¨åŠ è½½ PvE æ•°æ®..."
L["PVE_APIS_LOADING"] = "è¯·ç¨å€™ï¼ŒWoW API æ­£åœ¨åˆå§‹åŒ–..."
L["NO_VAULT_DATA"] = "æ— å®åº“æ•°æ®"
L["NO_DATA"] = "æ— æ•°æ®"
L["KEYSTONE"] = "é’¥çŸ³"
L["NO_KEY"] = "æ— é’¥çŸ³"
L["AFFIXES"] = "è¯ç¼€"
L["NO_AFFIXES"] = "æ— è¯ç¼€"
L["VAULT_BEST_KEY"] = "æœ€ä½³é’¥çŸ³ï¼š"
L["VAULT_SCORE"] = "è¯„åˆ†ï¼š"

-- Vault Tooltip (detailed)
L["VAULT_UNLOCKED"] = "å·²è§£é”"
L["VAULT_LOCKED"] = "æœªè§£é”"
L["VAULT_IN_PROGRESS"] = "è¿›è¡Œä¸­"
L["VAULT_COMPLETED_ACTIVITIES"] = "å·²å®Œæˆ"
L["VAULT_CURRENT_TIER"] = "å½“å‰é˜¶æ®µ"
L["VAULT_CLICK_TO_OPEN"] = "ç‚¹å‡»æ‰“å¼€å®ä¼Ÿå®åº“"
L["VAULT_REWARD"] = "å¥–åŠ±"
L["VAULT_REWARD_ON_UNLOCK"] = "è§£é”åå¥–åŠ±"
L["VAULT_UPGRADE_HINT"] = "å‡çº§"
L["VAULT_MAX_TIER"] = "æœ€é«˜ç­‰çº§"
L["VAULT_AT_MAX"] = "å·²è¾¾æœ€é«˜ç­‰çº§ï¼"
L["VAULT_BEST_SO_FAR"] = "ç›®å‰æœ€ä½³"
L["VAULT_DUNGEONS"] = "åœ°ä¸‹åŸ"
L["VAULT_BOSS_KILLS"] = "é¦–é¢†å‡»æ€"
L["VAULT_WORLD_ACTIVITIES"] = "ä¸–ç•Œæ´»åŠ¨"
L["VAULT_ACTIVITIES"] = "æ´»åŠ¨"
L["VAULT_REMAINING_SUFFIX"] = "å‰©ä½™"
L["VAULT_COMPLETE_PREFIX"] = "å®Œæˆ"
L["VAULT_SLOT1_HINT"] = "æ­¤è¡Œçš„ç¬¬ä¸€ä¸ªé€‰æ‹©"
L["VAULT_SLOT2_HINT"] = "ç¬¬äºŒä¸ªé€‰æ‹©ï¼ˆæ›´å¤šé€‰é¡¹ï¼ï¼‰"
L["VAULT_SLOT3_HINT"] = "ç¬¬ä¸‰ä¸ªé€‰æ‹©ï¼ˆæœ€å¤šé€‰é¡¹ï¼‰"
L["VAULT_IMPROVE_TO"] = "æå‡è‡³"
L["VAULT_COMPLETE_ON"] = "åœ¨ %s ä¸Šå®Œæˆæ­¤æ´»åŠ¨"
L["VAULT_ENCOUNTER_LIST_FORMAT"] = "%s"
L["VAULT_TOP_RUNS_FORMAT"] = "æœ¬å‘¨å‰ %d æ¬¡è®°å½•"
L["VAULT_DELVE_TIER_FORMAT"] = "å±‚çº§ %dï¼ˆ%dï¼‰"
L["VAULT_REWARD_HIGHEST"] = "æœ€é«˜ç‰©å“ç­‰çº§å¥–åŠ±"
L["VAULT_UNLOCK_REWARD"] = "è§£é”å¥–åŠ±"
L["VAULT_COMPLETE_MORE_FORMAT"] = "æœ¬å‘¨å†å®Œæˆ %d ä¸ª %s ä»¥è§£é”ã€‚"
L["VAULT_BASED_ON_FORMAT"] = "æ­¤å¥–åŠ±çš„ç‰©å“ç­‰çº§å°†åŸºäºæœ¬å‘¨å‰ %d æ¬¡è®°å½•ä¸­çš„æœ€ä½å€¼ï¼ˆå½“å‰ %sï¼‰ã€‚"
L["VAULT_RAID_BASED_FORMAT"] = "å¥–åŠ±åŸºäºå·²å‡»è´¥çš„æœ€é«˜éš¾åº¦ï¼ˆå½“å‰ %sï¼‰ã€‚"

-- Delves Section (PvE Tab)
L["DELVES"] = "åœ°ä¸‹å ¡"
L["COMPANION"] = "åŒä¼´"
L["BOUNTIFUL_DELVE"] = "çå®çŒæ‰‹çš„å¥–èµ"
L["PVE_BOUNTY_NEED_LOGIN"] = "è¯¥è§’è‰²æ²¡æœ‰ä¿å­˜çš„çŠ¶æ€ã€‚è¯·ç™»å½•ä»¥åˆ·æ–°ã€‚"
L["CRACKED_KEYSTONE"] = "ç ´è£‚çš„é’¥çŸ³"
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
L["REP_PROGRESS_COLON"] = "è¿›åº¦ï¼š"
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
L["REP_LOADING_DATA"] = "æ­£åœ¨åŠ è½½å£°æœ›æ•°æ®..."
L["REP_MAX"] = "æœ€å¤§"
L["REP_TIER_FORMAT"] = "ç¬¬ %d çº§"
L["ACCOUNT_WIDE_LABEL"] = "è´¦å·é€šç”¨"
L["NO_RESULTS"] = "æ— ç»“æœ"
L["NO_REP_MATCH"] = "æ²¡æœ‰åŒ¹é… '%s' çš„å£°æœ›"
L["NO_REP_DATA"] = "æ— å£°æœ›æ•°æ®"
L["REP_SCAN_TIP"] = "å£°æœ›è‡ªåŠ¨æ‰«æã€‚å¦‚æ— æ˜¾ç¤ºè¯·å°è¯• /reloadã€‚"
L["ACCOUNT_WIDE_REPS_FORMAT"] = "è´¦å·é€šç”¨å£°æœ›ï¼ˆ%sï¼‰"
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
L["NO_FOUND_FORMAT"] = "æœªæ‰¾åˆ° %s"
L["PLANS_COUNT_FORMAT"] = "%d ä¸ªè®¡åˆ’"
L["PET_BATTLE_LABEL"] = "å® ç‰©å¯¹æˆ˜ï¼š"
L["QUEST_LABEL"] = "ä»»åŠ¡ï¼š"

-- Settings Tab
L["CURRENT_LANGUAGE"] = "å½“å‰è¯­è¨€ï¼š"
L["LANGUAGE_TOOLTIP"] = "æ’ä»¶è‡ªåŠ¨ä½¿ç”¨ä½ çš„ WoW æ¸¸æˆå®¢æˆ·ç«¯è¯­è¨€ã€‚è¦æ›´æ”¹ï¼Œè¯·æ›´æ–°ä½ çš„æˆ˜ç½‘è®¾ç½®ã€‚"
L["POPUP_DURATION"] = "å¼¹çª—æŒç»­æ—¶é—´"
L["NOTIFICATION_DURATION"] = "é€šçŸ¥æŒç»­æ—¶é—´"
L["POPUP_POSITION"] = "å¼¹çª—ä½ç½®"
L["NOTIFICATION_POSITION"] = "é€šçŸ¥ä½ç½®"
L["SET_POSITION"] = "è®¾ç½®ä½ç½®"
L["SET_BOTH_POSITION"] = "è®¾ç½®ä¸¤å¤„ä½ç½®"
L["DRAG_TO_POSITION"] = "æ‹–åŠ¨ä»¥è®¾ç½®ä½ç½®\nå³é”®ç¡®è®¤"
L["RESET_DEFAULT"] = "é‡ç½®ä¸ºé»˜è®¤"
L["RESET_POSITION"] = "é‡ç½®ä½ç½®"
L["TEST_POPUP"] = "æµ‹è¯•å¼¹çª—"
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
L["POPUP_POSITION_MAIN"] = "ä¸»ï¼ˆæˆå°±ã€åéª‘ç­‰ï¼‰"
L["POPUP_POSITION_SAME_CRITERIA"] = "å…¨éƒ¨åŒä¸€ä½ç½®ï¼ˆæˆå°±ã€æ ‡å‡†è¿›åº¦ç­‰ï¼‰"
L["CRITERIA_POSITION_LABEL"] = "æ ‡å‡†è¿›åº¦ä½ç½®"
L["SET_POSITION_CRITERIA"] = "è®¾ç½®æ ‡å‡†ä½ç½®"
L["RESET_CRITERIA_BLIZZARD"] = "é‡ç½®ï¼ˆå³ä¾§ï¼‰"
L["USE_ALERTFRAME_POSITION"] = "ä½¿ç”¨ AlertFrame ä½ç½®"
L["USE_ALERTFRAME_POSITION_ACTIVE"] = "æ­£åœ¨ä½¿ç”¨æš´é›ª AlertFrame ä½ç½®"
L["NOTIFICATION_GHOST_MAIN"] = "æˆå°± / é€šçŸ¥"
L["NOTIFICATION_GHOST_CRITERIA"] = "æ ‡å‡†è¿›åº¦"
L["SHOW_WEEKLY_PLANNER"] = "æ¯å‘¨è®¡åˆ’ï¼ˆè§’è‰²ï¼‰"
L["LOCK_MINIMAP_ICON"] = "é”å®šå°åœ°å›¾æŒ‰é’®"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "åœ¨æç¤ºä¸­æ˜¾ç¤ºç‰©å“"
L["AUTO_SCAN_ITEMS"] = "è‡ªåŠ¨æ‰«æç‰©å“"
L["LIVE_SYNC"] = "å®æ—¶åŒæ­¥"
L["BACKPACK_LABEL"] = "èƒŒåŒ…"
L["REAGENT_LABEL"] = "ææ–™"

-- Shared Widgets & Dialogs
L["MODULE_DISABLED"] = "æ¨¡å—å·²ç¦ç”¨"
L["LOADING"] = "åŠ è½½ä¸­..."
L["PLEASE_WAIT"] = "è¯·ç¨å€™..."
L["RESET_PREFIX"] = "é‡ç½®ï¼š"
L["TRANSFER_CURRENCY"] = "è½¬ç§»è´§å¸"
L["AMOUNT_LABEL"] = "æ•°é‡ï¼š"
L["TO_CHARACTER"] = "ç›®æ ‡è§’è‰²ï¼š"
L["SELECT_CHARACTER"] = "é€‰æ‹©è§’è‰²..."
L["CURRENCY_TRANSFER_INFO"] = "è´§å¸çª—å£å°†è‡ªåŠ¨æ‰“å¼€ã€‚\nä½ éœ€è¦æ‰‹åŠ¨å³é”®ç‚¹å‡»è´§å¸è¿›è¡Œè½¬ç§»ã€‚"
L["SAVE"] = "ä¿å­˜"
L["TITLE_FIELD"] = "æ ‡é¢˜ï¼š"
L["DESCRIPTION_FIELD"] = "æè¿°ï¼š"
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
L["CHARACTER_OVERVIEW"] = "è§’è‰²æ¦‚è§ˆ"
L["TOTAL_CHARACTERS"] = "æ€»è®¡"
L["TRACKED_CHARACTERS"] = "å·²è¿½è¸ª"
L["FACTION_SPLIT"] = "é˜µè¥"
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
L["SET_TRY_COUNT_TEXT"] = "è®¾ç½®å°è¯•æ¬¡æ•°ï¼š\n%s"
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
L["QUEST_CAT_ASSIGNMENT"] = "æŒ‡æ´¾"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "æœªçŸ¥åˆ†ç±»"
L["SCANNING_FORMAT"] = "æ­£åœ¨æ‰«æ %s"
L["CUSTOM_PLAN_SOURCE"] = "è‡ªå®šä¹‰è®¡åˆ’"
L["POINTS_FORMAT"] = "%d ç‚¹"
L["SOURCE_NOT_AVAILABLE"] = "æ¥æºä¿¡æ¯ä¸å¯ç”¨"
L["SOURCE_QUEST_REWARD"] = "ä»»åŠ¡å¥–åŠ±"
L["PROGRESS_ON_FORMAT"] = "ä½ çš„è¿›åº¦ä¸º %d/%d"
L["COMPLETED_REQ_FORMAT"] = "ä½ å·²å®Œæˆ %d é¡¹ï¼Œå…± %d é¡¹è¦æ±‚"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "è‡³æš—ä¹‹å¤œ"
L["WEEKLY_RESET_LABEL"] = "æ¯å‘¨é‡ç½®"
L["CROSS_CHAR_SUMMARY"] = "è§’è‰²æ¦‚è§ˆ"
L["QUEST_TYPE_DAILY"] = "æ¯æ—¥ä»»åŠ¡"
L["QUEST_TYPE_DAILY_DESC"] = "æ¥è‡ª NPC çš„å¸¸è§„æ¯æ—¥ä»»åŠ¡"
L["QUEST_TYPE_WORLD"] = "ä¸–ç•Œä»»åŠ¡"
L["QUEST_TYPE_WORLD_DESC"] = "åŒºåŸŸèŒƒå›´å†…çš„ä¸–ç•Œä»»åŠ¡"
L["QUEST_TYPE_WEEKLY"] = "æ¯å‘¨ä»»åŠ¡"
L["QUEST_TYPE_WEEKLY_DESC"] = "æ¯å‘¨å¾ªç¯ä»»åŠ¡"
L["QUEST_TYPE_ASSIGNMENTS"] = "æŒ‡æ´¾ä»»åŠ¡"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "ç‰¹æ®ŠæŒ‡æ´¾å’Œä»»åŠ¡"
L["QUEST_TYPE_CONTENT_EVENTS"] = "å†…å®¹äº‹ä»¶"
L["QUEST_TYPE_CONTENT_EVENTS_DESC"] = "å¥–åŠ±ç›®æ ‡ã€æ´»åŠ¨ä»»åŠ¡å’Œæˆ˜å½¹é£æ ¼æ´»åŠ¨"
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
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "åœ¨æç¤ºä¸­æ˜¾ç¤ºæˆ˜å›¢å’Œè§’è‰²ç‰©å“æ•°é‡ï¼ˆWN æœç´¢ï¼‰"
L["AUTO_SCAN_TOOLTIP"] = "æ‰“å¼€é“¶è¡Œæˆ–èƒŒåŒ…æ—¶è‡ªåŠ¨æ‰«æå¹¶ç¼“å­˜ç‰©å“"
L["LIVE_SYNC_TOOLTIP"] = "é“¶è¡Œæ‰“å¼€æ—¶å®æ—¶æ›´æ–°ç‰©å“ç¼“å­˜"
L["SHOW_ILVL_TOOLTIP"] = "åœ¨ç‰©å“åˆ—è¡¨ä¸­æ˜¾ç¤ºè£…å¤‡çš„è£…ç­‰å¾½ç« "
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
L["TRYCOUNTER_INSTANCE_DROPS_TRUNCATED"] = "â€¦ è¿˜æœ‰ |cffffccff%d|r æ¡ â€” å¯¹é¦–é¢†ä½¿ç”¨ |cffffffff/wn check|rï¼ˆç›®æ ‡æˆ–é¼ æ ‡æŒ‡å‘ï¼‰ã€‚"
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
L["ITEM_LEVEL_FORMAT"] = "ç‰©å“ç­‰çº§ %s"
L["ITEM_NUMBER_FORMAT"] = "ç‰©å“ #%s"
L["CHARACTER_CURRENCIES"] = "è§’è‰²è´§å¸ï¼š"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "è´¦å·é€šç”¨ï¼ˆæˆ˜å›¢ï¼‰â€”â€”æ‰€æœ‰è§’è‰²ä½™é¢ç›¸åŒã€‚"
L["YOU_MARKER"] = "ï¼ˆä½ ï¼‰"
L["WN_SEARCH"] = "WN æœç´¢"
L["WARBAND_BANK_COLON"] = "æˆ˜å›¢é“¶è¡Œï¼š"
L["AND_MORE_FORMAT"] = "... è¿˜æœ‰ %d ä¸ª"

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
L["NOTIFICATION_GRIND_TRIES"] = "çœŸæ˜¯è¾›è‹¦ï¼%dæ¬¡å°è¯•ï¼"
L["NOTIFICATION_GOT_IT_AFTER"] = "ç»è¿‡%dæ¬¡å°è¯•åè·å¾—ï¼"
L["NOTIFICATION_TRY_SUBTITLE"] = "%d æ¬¡å°è¯•"
L["NOTIFICATION_TRY_SUBTITLE_FIRST"] = "é¦–æ¬¡å°è¯•ï¼"

-- Minimap Button
L["TOTAL_GOLD_LABEL"] = "æ€»é‡‘å¸ï¼š"
L["MINIMAP_CHARS_GOLD"] = "è§’è‰²é‡‘å¸ï¼š"
L["CHARACTERS_COLON"] = "è§’è‰²ï¼š"
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
L["MAX_BUTTON"] = "æœ€å¤§"
L["OPEN_AND_GUIDE"] = "æ‰“å¼€å¹¶å¼•å¯¼"
L["FROM_LABEL"] = "æ¥è‡ªï¼š"
L["AVAILABLE_LABEL"] = "å¯ç”¨ï¼š"
L["ONLINE_LABEL"] = "ï¼ˆåœ¨çº¿ï¼‰"
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
L["SUPPORTERS_TITLE"] = "æ”¯æŒè€…"
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
L["COPIED_LABEL"] = "å·²å¤åˆ¶ï¼"
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
L["CHANGELOG_V256"] = "v2.5.6\næ”¹è¿›ï¼š\n- è£…å¤‡ã€å‘¨è®¡åˆ’ã€è®¡åˆ’è¿½è¸ªä¸è·Ÿè¸ªç¡®è®¤ç•Œé¢æ›´æ˜“è¯»æœåŠ¡å™¨åï¼›å­˜æ¡£é”®ä»ç”¨æš´é›ªè§„èŒƒåŒ–å­—ç¬¦ä¸²\n- æ”¶è—å“ï¼šæ‰©å±• BfAã€Œé©¯æœçš„è¡€è™±ç¼°ç»³ã€NPCï¼›è¡¥å……å®ç®±ä¸é¦–é¢†ã€å¤šå°¸ä½“æ‹¾å–ä¸å°è¯•è®¡æ•°çš„è¯´æ˜\n- SplitCharacterKey +ã€Œè§’è‰²å-æœåŠ¡å™¨ã€ä»…åœ¨ç¬¬ä¸€ä¸ªè¿å­—ç¬¦å¤„æ‹†åˆ†\n- åéª‘æ•°æ®åº“å®¡è®¡ï¼šç¤¾åŒº DB/Mounts Lua + Wowhead/WoWDB\n\nä¿®å¤ï¼š\n- å°è¯•è®¡æ•°ï¼šèŠå¤©æ‹¾å– + å…±äº«æ‰è½è¡¨ä¸å†ä¸¢å¤± CHAT æ›´æ–°ï¼ˆå¦‚è¡€è™±ï¼‰\n- å«è¿å­—ç¬¦æœåŠ¡å™¨ï¼ˆAzjol-Nerubï¼‰ï¼šè§„èŒƒé”®ã€GetAllCharacters ä¿®å¤ã€ç»Ÿè®¡/å°åœ°å›¾ï¼›ä¸€æ¬¡æ€§ realm å­—æ®µè¿ç§»\n- åéª‘ç‰©å“ IDï¼šVerdant Skitterflyï¼ˆ192764ï¼‰ã€çº¢è‰²å…¶æ‹‰å…±é¸£æ°´æ™¶ï¼ˆ21321ï¼‰\n- è·Ÿè¸ªå¯¹è¯æ¡†ï¼šGetRealmName å¯¹ç§˜å¯†å€¼é˜²æŠ¤\n\næœ¬åœ°åŒ–ï¼š\n- å„è¯­è¨€ TRY_COUNT å·¦é”®/å³é”®æç¤º\n\nä»“åº“ï¼šGit ä»…è·Ÿè¸ªæ’ä»¶æºç ï¼ˆCoreã€Modulesã€Localesã€tocã€CHANGESï¼‰\n\nCurseForgeï¼šWarband Nexus"

L["CHANGELOG_V257"] = "v2.5.7b\næ”¹è¿›ï¼š\n- è§’è‰²ï¼šé»˜è®¤æ’åºï¼ˆå½“å‰åœ¨çº¿è§’è‰²ä¼˜å…ˆï¼Œç­‰çº§ã€åç§°ï¼‰ï¼›æ–°æ¡£æ¡ˆé»˜è®¤ï¼›æœªçŸ¥æ’åºé”®æ˜ å°„ä¸ºèœå•é¦–é¡¹\n- è§’è‰²ï¼šæ”¶è—/è§’è‰²/æœªè¿½è¸ªä¸­åœ¨çº¿è§’è‰²ç½®é¡¶ï¼›æ‰‹åŠ¨é¡ºåºä¸€è‡´\n- å°è¯•è®¡æ•°ï¼šå‰¯æœ¬éš¾åº¦ä½¿ç”¨ GetInstanceInfo + è¿›æœ¬å¿«ç…§ï¼ˆä¿®æ­£å²è¯—è¯¯åˆ¤æ™®é€šï¼Œå¦‚éº¦å¡è´¡ HK-8ï¼‰\n- å°è¯•è®¡æ•°ï¼šæ‹¾å–ã€å»¶è¿Ÿ ENCã€CHAT å…±ç”¨éš¾åº¦è¿‡æ»¤ï¼›CHAT ä¸æ‹¾å–çª—å£ä½¿ç”¨ç›¸åŒ encounter_ å»é‡é”®\n- å°è¯•è®¡æ•°ï¼šé›¶å¯è¿½è¸ªæ—¶ä»å†™å…¥ encounter_ é”®ï¼Œé¿å…å»¶è¿Ÿ ENC/CHAT é‡å¤è®¡æ•°\n- å°è¯•è®¡æ•°ï¼šå¼€æ”¾ä¸–ç•Œåˆå¹¶æ‹¾å–æŒ‰ç›¸åŒåéª‘ç‰©å“ç»Ÿè®¡å¤šæ¨¡æ¿ NPC å°¸ä½“ï¼ˆBfA è¡€è™±ï¼‰\n- è£…å¤‡ï¼šè§’è‰²é€‰æ‹©å™¨å®½åº¦\n\nä¿®å¤ï¼š\n- å°è¯•è®¡æ•°ï¼šå·²å› éš¾åº¦è·³è¿‡ä»å¢åŠ æ¬¡æ•°\n\næœ¬åœ°åŒ–ï¼šSORT_MODE_DEFAULT\n\nCurseForgeï¼šWarband Nexus"

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

L["CHANGELOG_V259b"] = [=[v2.5.9bï¼ˆ2026-04-04ï¼‰

æ”¹è¿›
- æç¤ºï¼šNPC å•ä½æç¤ºä¸Šçš„æ”¶è—å“æ‰è½ä¿¡æ¯ä»…åœ¨ç›®æ ‡ä¸ºæ•Œå¯¹æˆ–å¯æ”»å‡»æ—¶æ˜¾ç¤ºï¼ˆä¿®å¤å‹å¥½ delve çŸ³ç­‰ä¸Šå‡ºç°é”™è¯¯åéª‘è¡Œçš„é—®é¢˜ï¼‰ã€‚å¯¹ UnitCanAttackã€UnitIsDeadã€UnitReaction åšå®‰å…¨æ£€æµ‹ï¼ˆMidnight ç§˜å¯†å€¼è§„åˆ™ï¼‰ã€‚
- æ‰“åŒ…ï¼šå‘è¡Œ ZIP ç”± build_addon.pyï¼ˆPython 3.8+ï¼‰ç”Ÿæˆï¼›å½’æ¡£å†…è·¯å¾„ä½¿ç”¨ /ï¼Œä¾¿äº Linuxã€macOS ä¸ CurseForge Linux æ­£ç¡®è§£å‹ã€‚

ä¿®å¤
- å°è¯•è®¡æ•°ï¼šæ›´æ¸…æ™°åŒºåˆ†é’“é±¼ã€ä¸“ä¸šé‡‡é›†ä¸çº¯ç‰©ä½“æ‹¾å–ï¼›å‡å°‘è¯¯è®¡ã€‚æ‹¾å–ä¼šè¯ä¸ CHAT_MSG_LOOT å¤„ç†æ”¶ç´§ã€‚

è®¡åˆ’ç•Œé¢
- å¾…åŠä¸å‘¨è¿›åº¦ï¼šâ€œæ˜¾ç¤ºå·²è®¡åˆ’/æ˜¾ç¤ºå·²å®Œæˆâ€ä¸æµè§ˆé¡µç­¾è¡Œä¸ºä¸€è‡´ï¼›æˆå°±ä¸åˆ—è¡¨çš„ç©ºçŠ¶æ€è¯´æ˜æ›´æ¸…æ™°ã€‚

èŠå¤©
- å°è¯•è®¡æ•°ï¼šå¯è·Ÿéšæˆ˜åˆ©å“é¡µç­¾ã€ç‹¬ç«‹ WN_TRYCOUNTER é¢‘é“æˆ–å…¨éƒ¨é¡µç­¾ï¼›å¯å°†é¢‘é“åŠ å…¥æ‰€é€‰èŠå¤©æ ‡ç­¾ã€‚å¯é€‰ç™»å½•æ¬¢è¿ä¸€è¡Œï¼›å¯éšè—æ¸¸æˆæ—¶é—´åˆ·å±ã€é™é»˜è¯·æ±‚ /playedã€‚

æœ¬åœ°åŒ–
- è¡¥å…¨å„è¯­è¨€æ­¤å‰ç¼ºå¤±çš„é”®ã€‚

CurseForgeï¼šWarband Nexus]=]

L["CHANGELOG_V2510"] = [=[v2.5.10ï¼ˆ2026-04-04ï¼‰

ä¿®å¤
- æç¤ºï¼šé»„è‰²ã€Œï¼ˆå·²è®¡åˆ’ï¼‰ã€ä»…åœ¨å°šæœªè·å¾—åéª‘ã€å® ç‰©æˆ–ç©å…·æ—¶æ˜¾ç¤ºã€‚NPC/å®¹å™¨æ‰è½è¡Œã€äº§å‡ºå­è¡Œä¸ç‰©å“æç¤ºä¼šé€šè¿‡æ”¶è—å¤¹ä¸ç©å…· API åˆ¤æ–­å½’å±ï¼ˆpcall ä¸ Midnight ç§˜å¯†å€¼è§„åˆ™ï¼‰ã€‚æ•°æ®åº“ä¸­æ ‡è®°ä¸ºé€šç”¨ã€Œitemã€çš„æ‰è½ä¹Ÿä¼šåŒæ­¥æ”¶è—çŠ¶æ€ï¼Œå·²è·å¾—æ—¶ä¸å†æ˜¾ç¤ºå·²è®¡åˆ’ã€‚

CurseForgeï¼šWarband Nexus]=]

L["CHANGELOG_V2511"] = [=[v2.5.11 (2026-04-07)

PvE
- ä¸°è£•/ä¸°è£•åˆ—ï¼šæ¯è§’è‰²ç¼“å­˜ï¼›æ— å¿«ç…§æ—¶ä»…å½“å‰è§’è‰²å®æ—¶æŸ¥è¯¢ï¼ˆå°å·æ˜¾ç¤ºâ€œâ€”â€ç›´åˆ°ç™»å½•ï¼‰ã€‚
- PvE ç¼“å­˜ä¸­æ¯å‘¨ä»»åŠ¡æ£€æŸ¥æ·»åŠ  Midnight å®‰å…¨ï¼ˆpcall + ç§˜å¯†å€¼ä¿æŠ¤ï¼‰ã€‚
- ä¸°è£•å‘¨å¸¸æ ‡å¿—ä»…ç”¨éšè—ä»»åŠ¡ 86371ï¼ˆä¸å†ä¸ç ´è£‚æ‹±å¿ƒçŸ³ 92600 / ä¸°è£•åœ°çªŸ 81514 æ··åˆï¼‰ã€‚
- ä¸°è£•å•å…ƒæ ¼æç¤ºï¼›å°å·æ— ä¿å­˜çŠ¶æ€æ—¶æ˜¾ç¤º PVE_BOUNTY_NEED_LOGINã€‚

æ”¶è—
- æˆå°±é¡µï¼šé€šè¿‡ GetCategoryNumAchievements(categoryID, true) æšä¸¾å…¨éƒ¨åˆ†ç±» â€” ä¿®å¤ä»…æ˜¾ç¤ºæœ€åè·å¾—çš„æˆå°±ã€‚
- æ›´æ–°åå…¨æˆå°±ä¸€æ¬¡æ€§é‡æ‰«ï¼ˆå…¨å±€ wnAchievementIncludeAllScanV1ï¼‰ã€‚

å°è¯•è®¡æ•°ä¸æ•°æ®
- åéª‘/å® ç‰©å·²æ”¶é›†åˆ¤å®šã€é—æ¼è¿‡æ»¤ã€C_Timer.After å›è°ƒä¿®å¤ï¼›CollectibleSourceDB ä¸­ Lucent Hawkstrider åéª‘ IDã€‚

è®¡åˆ’ / ç•Œé¢
- å¾…åŠ/è¿½è¸ªï¼šå°è¯•æ¬¡æ•°å¼¹çª—ä»…å·¦é”®å¯ç¼–è¾‘ï¼ˆå¡ç‰‡ä¸Šä¸å†å³é”®å¼¹çª—ï¼‰ã€‚
- ä¿¡æ¯å¯¹è¯æ¡†ï¼šç‰¹åˆ«æ„Ÿè°¢å—ï¼ˆè´¡çŒ®è€…é£æ ¼ï¼‰ã€‚

æœ¬åœ°åŒ–
- è‡´è°¢/ç‰¹åˆ«æ„Ÿè°¢å­—ç¬¦ä¸²ï¼›PVE_BOUNTY_NEED_LOGINã€‚

CurseForge: Warband Nexus]=]

L["CHANGELOG_V2512"] = [=[v2.5.12 (2026-04-12)

ç•Œé¢
- é€šçŸ¥ï¼šå°è¯•è®¡æ•°èŠå¤©è¾“å‡ºä¸‹æ‹‰èœå•å‘ä¸‹å±•å¼€ï¼Œä¸å†é®ç›–é™„è¿‘å¤é€‰æ¡†ã€‚è·¯ç”±é€‰é¡¹å›ºå®šé¡ºåºï¼ˆæ‹¾å–é¡µ â†’ Warband Nexus è¿‡æ»¤å™¨ â†’ æ‰€æœ‰æ ‡å‡†é¡µï¼‰ã€‚

ä¿®å¤
- è®¾ç½®ã€é‡‘å¸ç®¡ç†å¼¹çª—ã€è®¡åˆ’ç•Œé¢ä¸­ GameTooltip:SetText ä½¿ç”¨æœ‰æ•ˆé¢œè‰² alphaï¼ˆä¿®å¤ Midnight â€œbad argument #5 to 'SetText'â€ï¼‰ã€‚

å°è¯•è®¡æ•°
- å‰¯æœ¬å…¥å£ [WN-Drops]ï¼šå®Œæ•´æ‰è½è¡Œ vs ç®€çŸ­æç¤ºåŸºäºæ­£ç¡®åéª‘/å¯è¿½è¸ªé€»è¾‘ï¼Œéš¾åº¦æ¶ˆæ¯åŒ¹é…ä»å¯æ‰è½ã€‚
- æ‰‹åŠ¨æ‰è½ä¸ Rarity åŒæ­¥ï¼šå·²æ‹¥æœ‰ä¸”éé‡å¤çš„æ”¶è—å“ä¸å†å¢åŠ å°è¯•è®¡æ•°ã€‚

æç¤ºä¸æ”¶è—
- æ”¶è—å“/æ‰è½æç¤ºåŠç›¸å…³æœåŠ¡é’ˆå¯¹ Midnight ç§˜å¯†å€¼è§„åˆ™æ”¶ç´§ï¼›CollectibleSourceDB ä¸æç¤ºå¯¹é½å½“å‰ APIã€‚

æœ¬åœ°åŒ–
- å„è¯­è¨€è¡¥å…¨ç¼ºå¤±é”®ï¼›æ¢æµ‹èŠå¤©ä½¿ç”¨æ›´çŸ­ [WN-TC] æ ¼å¼ã€‚

åç»­
- æ›´å¤š Midnight API éªŒè¯ï¼›æ ¹æ®å›¢æœ¬åé¦ˆæ‰“ç£¨å°è¯•è®¡æ•°ä¸é€šçŸ¥ï¼›è¿›ä¸€æ­¥è®¾ç½®ä¸æç¤ºä¼˜åŒ–ã€‚

CurseForge: Warband Nexus]=]

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
L["REP_LOADING_PROCESSING_COUNT"] = "å¤„ç†ä¸­...ï¼ˆ%d/%dï¼‰"
L["REP_LOADING_SAVING"] = "æ­£åœ¨ä¿å­˜åˆ°æ•°æ®åº“..."
L["REP_LOADING_COMPLETE"] = "å®Œæˆï¼"

-- Status / Footer
L["COMBAT_LOCKDOWN_MSG"] = "æˆ˜æ–—ä¸­æ— æ³•æ‰“å¼€çª—å£ã€‚æˆ˜æ–—ç»“æŸåè¯·é‡è¯•ã€‚"
L["BANK_IS_ACTIVE"] = "é“¶è¡Œå·²æ‰“å¼€"
L["ITEMS_CACHED_FORMAT"] = "å·²ç¼“å­˜ %d ä»¶ç‰©å“"

-- Table Headers (SharedWidgets, Professions)
L["TABLE_HEADER_CHARACTER"] = "è§’è‰²"
L["TABLE_HEADER_LEVEL"] = "ç­‰çº§"
L["TABLE_HEADER_GOLD"] = "é‡‘å¸"
L["TABLE_HEADER_LAST_SEEN"] = "ä¸Šæ¬¡ç™»å½•"

-- Search / Empty States
L["NO_ITEMS_MATCH"] = "æ²¡æœ‰åŒ¹é… '%s' çš„ç‰©å“"
L["NO_ITEMS_MATCH_GENERIC"] = "æ²¡æœ‰åŒ¹é…ä½ æœç´¢çš„ç‰©å“"
L["ITEMS_SCAN_HINT"] = "ç‰©å“è‡ªåŠ¨æ‰«æã€‚å¦‚æ— æ˜¾ç¤ºè¯·å°è¯• /reloadã€‚"
L["ITEMS_WARBAND_BANK_HINT"] = "æ‰“å¼€æˆ˜å›¢é“¶è¡Œä»¥æ‰«æç‰©å“ï¼ˆé¦–æ¬¡è®¿é—®æ—¶è‡ªåŠ¨æ‰«æï¼‰"

-- Currency Transfer Steps
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "ä¸‹ä¸€æ­¥ï¼š"
L["CURRENCY_TRANSFER_STEP_1"] = "åœ¨è´§å¸çª—å£ä¸­æ‰¾åˆ° |cffffffff%s|r"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800å³é”®ç‚¹å‡»|rå®ƒ"
L["CURRENCY_TRANSFER_STEP_3"] = "é€‰æ‹© |cffffffffã€Œè½¬ç§»è‡³æˆ˜å›¢ã€|r"
L["CURRENCY_TRANSFER_STEP_4"] = "é€‰æ‹© |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "è¾“å…¥æ•°é‡ï¼š|cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "è´§å¸çª—å£å·²æ‰“å¼€ï¼"
L["CURRENCY_TRANSFER_SECURITY"] = "ï¼ˆæš´é›ªå®‰å…¨æœºåˆ¶ç¦æ­¢è‡ªåŠ¨è½¬ç§»ï¼‰"

-- Plans UI Extra
L["ZONE_PREFIX"] = "åŒºåŸŸï¼š"
L["ADDED"] = "å·²æ·»åŠ "
L["WEEKLY_VAULT_TRACKER"] = "æ¯å‘¨å®åº“è¿½è¸ª"
L["DAILY_QUEST_TRACKER"] = "æ¯æ—¥ä»»åŠ¡è¿½è¸ª"
L["CUSTOM_PLAN_STATUS"] = "è‡ªå®šä¹‰è®¡åˆ’ã€Œ%sã€%s"

-- Achievement Popup
L["ACHIEVEMENT_COMPLETED"] = "å·²å®Œæˆ"
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
L["CHAT_REP_STANDING_LABEL"] = "å½“å‰"
L["CHAT_GAINED_PREFIX"] = "+"

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
L["EMPTY_CHARACTERS_TITLE"] = "æœªæ‰¾åˆ°è§’è‰²"
L["EMPTY_CHARACTERS_DESC"] = "ç™»å½•ä½ çš„è§’è‰²ä»¥å¼€å§‹è¿½è¸ªã€‚\næ¯æ¬¡ç™»å½•æ—¶è‡ªåŠ¨æ”¶é›†è§’è‰²æ•°æ®ã€‚"
L["EMPTY_ITEMS_TITLE"] = "æ— ç‰©å“ç¼“å­˜"
L["EMPTY_ITEMS_DESC"] = "æ‰“å¼€æˆ˜å›¢é“¶è¡Œæˆ–ä¸ªäººé“¶è¡Œä»¥æ‰«æç‰©å“ã€‚\né¦–æ¬¡è®¿é—®æ—¶è‡ªåŠ¨ç¼“å­˜ã€‚"
L["EMPTY_INVENTORY_TITLE"] = "èƒŒåŒ…æ— ç‰©å“"
L["EMPTY_INVENTORY_DESC"] = "ä½ çš„èƒŒåŒ…æ˜¯ç©ºçš„ã€‚"
L["EMPTY_PERSONAL_BANK_TITLE"] = "ä¸ªäººé“¶è¡Œæ— ç‰©å“"
L["EMPTY_PERSONAL_BANK_DESC"] = "æ‰“å¼€ä¸ªäººé“¶è¡Œä»¥æ‰«æç‰©å“ã€‚\né¦–æ¬¡è®¿é—®æ—¶è‡ªåŠ¨ç¼“å­˜ã€‚"
L["EMPTY_WARBAND_BANK_TITLE"] = "æˆ˜å›¢é“¶è¡Œæ— ç‰©å“"
L["EMPTY_WARBAND_BANK_DESC"] = "æ‰“å¼€æˆ˜å›¢é“¶è¡Œä»¥æ‰«æç‰©å“ã€‚\né¦–æ¬¡è®¿é—®æ—¶è‡ªåŠ¨ç¼“å­˜ã€‚"
L["EMPTY_GUILD_BANK_TITLE"] = "å…¬ä¼šé“¶è¡Œæ— ç‰©å“"
L["EMPTY_GUILD_BANK_DESC"] = "æ‰“å¼€å…¬ä¼šé“¶è¡Œä»¥æ‰«æç‰©å“ã€‚\né¦–æ¬¡è®¿é—®æ—¶è‡ªåŠ¨ç¼“å­˜ã€‚"
L["NO_SCAN"] = "æœªæ‰«æ"
L["EMPTY_STORAGE_TITLE"] = "æ— å­˜å‚¨æ•°æ®"
L["EMPTY_STORAGE_DESC"] = "æ‰“å¼€é“¶è¡Œæˆ–èƒŒåŒ…æ—¶æ‰«æç‰©å“ã€‚\nè®¿é—®é“¶è¡Œä»¥å¼€å§‹è¿½è¸ªå­˜å‚¨ã€‚"
L["EMPTY_PLANS_TITLE"] = "æš‚æ— è®¡åˆ’"
L["EMPTY_PLANS_DESC"] = "æµè§ˆä¸Šæ–¹çš„åéª‘ã€å® ç‰©ã€ç©å…·æˆ–æˆå°±\nä»¥æ·»åŠ æ”¶è—ç›®æ ‡å¹¶è¿½è¸ªè¿›åº¦ã€‚"
L["EMPTY_REPUTATION_TITLE"] = "æ— å£°æœ›æ•°æ®"
L["EMPTY_REPUTATION_DESC"] = "ç™»å½•æ—¶è‡ªåŠ¨æ‰«æå£°æœ›ã€‚\nç™»å½•è§’è‰²ä»¥å¼€å§‹è¿½è¸ªé˜µè¥å£°æœ›ã€‚"
L["EMPTY_CURRENCY_TITLE"] = "æ— è´§å¸æ•°æ®"
L["EMPTY_CURRENCY_DESC"] = "è´§å¸åœ¨æ‰€æœ‰è§’è‰²é—´è‡ªåŠ¨è¿½è¸ªã€‚\nç™»å½•è§’è‰²ä»¥å¼€å§‹è¿½è¸ªè´§å¸ã€‚"
L["EMPTY_PVE_TITLE"] = "æ—  PvE æ•°æ®"
L["EMPTY_PVE_DESC"] = "ç™»å½•è§’è‰²æ—¶è¿½è¸ª PvE è¿›åº¦ã€‚\nå®ä¼Ÿå®åº“ã€å²è¯—é’¥çŸ³å’Œå›¢é˜Ÿå‰¯æœ¬é”å®šå°†æ˜¾ç¤ºåœ¨æ­¤ã€‚"
L["EMPTY_STATISTICS_TITLE"] = "æ— ç»Ÿè®¡å¯ç”¨"
L["EMPTY_STATISTICS_DESC"] = "ç»Ÿè®¡ä»ä½ è¿½è¸ªçš„è§’è‰²æ”¶é›†ã€‚\nç™»å½•è§’è‰²ä»¥å¼€å§‹æ”¶é›†æ•°æ®ã€‚"
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
L["PROFILES"] = "é…ç½®"
L["PROFILES_DESC"] = "ç®¡ç†æ’ä»¶é…ç½®"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "æœªæ‰¾åˆ°æ¡ä»¶"
L["NO_REQUIREMENTS_INSTANT"] = "æ— è¦æ±‚ï¼ˆå³æ—¶å®Œæˆï¼‰"

-- Professions Tab
L["TAB_PROFESSIONS"] = "ä¸“ä¸š"
L["TAB_COLLECTIONS"] = "æ”¶è—"
L["COLLECTIONS_SUBTITLE"] = "åéª‘ã€å® ç‰©ã€ç©å…·ä¸å¹»åŒ–æ¦‚è§ˆ"
L["COLLECTIONS_CONTENT_TITLE_ACHIEVEMENTS"] = "æˆå°±"
L["COLLECTIONS_CONTENT_SUB_ACHIEVEMENTS"] = "æŒ‰ç±»åˆ«æµè§ˆï¼›å³ä¾§æ˜¾ç¤ºæ ‡å‡†å’Œè¯¦æƒ…ã€‚"
L["COLLECTIONS_CONTENT_TITLE_MOUNTS"] = "åéª‘"
L["COLLECTIONS_CONTENT_SUB_MOUNTS"] = "æŒ‰æ¥æºåˆ†ç»„ï¼›å³ä¾§é¢„è§ˆã€‚"
L["COLLECTIONS_CONTENT_TITLE_PETS"] = "å® ç‰©"
L["COLLECTIONS_CONTENT_SUB_PETS"] = "æŒ‰æ¥æºåˆ†ç»„ï¼›å³ä¾§æ¨¡å‹é¢„è§ˆã€‚"
L["COLLECTIONS_CONTENT_TITLE_TOYS"] = "ç©å…·ç®±"
L["COLLECTIONS_CONTENT_SUB_TOYS"] = "æŒ‰æ¥æºåˆ†ç»„ï¼›å³ä¾§è¯¦æƒ…ã€‚"
L["COLLECTIONS_CONTENT_TITLE_RECENT"] = "æœ€è¿‘è·å¾—"
L["COLLECTIONS_CONTENT_SUB_RECENT"] = "æ¯ä¸ªç±»åˆ«æœ€å¤š10æ¡æœ€æ–°è®°å½•ï¼Œæ–°çš„åœ¨å‰ã€‚"
L["COLLECTIONS_SUBTAB_RECENT"] = "æœ€è¿‘"
L["COLLECTIONS_RECENT_TAB_EMPTY"] = "å°šæ— è·å¾—è®°å½•ã€‚æ–°è·å¾—çš„åéª‘ã€å® ç‰©ã€ç©å…·å’Œæˆå°±ä¼šæ˜¾ç¤ºåœ¨è¿™é‡Œã€‚"
L["COLLECTIONS_RECENT_SECTION_HEAD_FMT"] = "%s â€” æœ€è¿‘ %d æ¡"
L["COLLECTIONS_RECENT_SECTION_NONE"] = "æš‚æ— ã€‚"
L["COLLECTIONS_RECENT_SECTION_ROW"] = "%s Â· %s"
L["COLLECTIONS_RECENT_SEARCH_EMPTY"] = "æ²¡æœ‰åŒ¹é…çš„æ¡ç›®ã€‚"
L["COLLECTIONS_RECENT_HEADER"] = "æœ€æ–°è·å¾—"
L["COLLECTIONS_RECENT_EMPTY"] = "ä½ è·å¾—çš„ç‰©å“ä¼šåœ¨æ­¤æ˜¾ç¤ºç®€çŸ­æ—¶é—´æ ‡è®°ã€‚"
L["COLLECTIONS_ACQUIRED_LABEL"] = "å·²è®°å½•"
L["COLLECTIONS_ACQUIRED_LINE"] = "%sï¼š%s"
L["COLLECTIONS_RECENT_LINE"] = "%s Â· %s Â· %s"
L["COLLECTIONS_RECENT_JUST_NOW"] = "åˆšåˆš"
L["COLLECTIONS_RECENT_MINUTES_AGO"] = "%d åˆ†é’Ÿå‰"
L["COLLECTIONS_RECENT_HOURS_AGO"] = "%d å°æ—¶å‰"
L["COLLECTIONS_RECENT_DAYS_AGO"] = "%d å¤©å‰"
L["COLLECTIONS_RECENT_SECTION_MOUNTS"] = "æœ€è¿‘åéª‘"
L["COLLECTIONS_RECENT_SECTION_PETS"] = "æœ€è¿‘å® ç‰©"
L["COLLECTIONS_RECENT_SECTION_TOYS"] = "æœ€è¿‘ç©å…·"
L["COLLECTIONS_RECENT_SECTION_ACHIEVEMENTS"] = "æœ€è¿‘æˆå°±"
L["COLLECTIONS_RECENT_SECTION_EMPTY"] = "æ­¤ç±»åˆ«å°šæ— æœ€è¿‘è·å¾—ã€‚"
L["COLLECTIONS_RECENT_SECTION_LINE"] = "%s Â· %s"
L["COLLECTIONS_COMING_SOON_TITLE"] = "å³å°†æ¨å‡º"
L["COLLECTIONS_COMING_SOON_DESC"] = "æ”¶è—æ¦‚è§ˆï¼ˆåéª‘ã€å® ç‰©ã€ç©å…·ã€å¹»åŒ–ï¼‰å°†åœ¨æ­¤å¤„æä¾›ã€‚"
L["SELECT_MOUNT_FROM_LIST"] = "ä»åˆ—è¡¨é€‰æ‹©åéª‘"
L["SELECT_PET_FROM_LIST"] = "ä»åˆ—è¡¨é€‰æ‹©å® ç‰©"
L["SELECT_TO_SEE_DETAILS"] = "é€‰æ‹© %s ä»¥æŸ¥çœ‹è¯¦æƒ…ã€‚"
L["SOURCE"] = "æ¥æº"
L["YOUR_PROFESSIONS"] = "æˆ˜å›¢ä¸“ä¸š"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s ä¸ªè§’è‰²æœ‰ä¸“ä¸š"
L["PROFESSIONS_WIDE_TABLE_HINT"] = "æç¤ºï¼šä½¿ç”¨ä¸‹æ–¹æ»šåŠ¨æ¡æˆ– Shift+æ»šè½®æŸ¥çœ‹æ‰€æœ‰åˆ—ã€‚"
L["HEADER_PROFESSIONS"] = "ä¸“ä¸šæ¦‚è§ˆ"
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
L["PROF_FILTER_EXPANSION"] = "èµ„æ–™ç‰‡ç­›é€‰"
L["PROF_FILTER_STRICT_NOTE"] = "ä»…æ˜¾ç¤ºæœ¬èµ„æ–™ç‰‡æ‰€æœ‰è§’è‰²çš„ä¸“ä¸šæ•°æ®ã€‚"
L["PROF_DATA_SOURCE_NOTE"] = "åœ¨å„è§’è‰²æ‰“å¼€ä¸“ä¸šçª—å£ï¼ˆKï¼‰æ—¶æ›´æ–°ä¸“æ³¨ã€çŸ¥è¯†ä¸é…æ–¹ã€‚"
L["PROF_FILTER_ALL"] = "å…¨éƒ¨"
L["PROF_FIRSTCRAFT_OPEN_WINDOW"] = "è¯·å…ˆæ‰“å¼€ä¸“ä¸šçª—å£ï¼Œç„¶åå†æ¬¡æ‰§è¡Œæ­¤å‘½ä»¤ã€‚"
L["PROF_FIRSTCRAFT_NO_DATA"] = "æ— å¯ç”¨ä¸“ä¸šæ•°æ®ã€‚"
L["PROF_FIRSTCRAFT_HEADER"] = "é¦–æ¬¡åˆ¶é€ å¥–åŠ±é…æ–¹"
L["PROF_FIRSTCRAFT_NONE"] = "æ²¡æœ‰å‰©ä½™é¦–æ¬¡åˆ¶é€ å¥–åŠ±çš„å·²å­¦é…æ–¹ã€‚"
L["PROF_FIRSTCRAFT_TOTAL"] = "æ€»è®¡"
L["PROF_FIRSTCRAFT_RECIPES"] = "ä¸ªé…æ–¹"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "é¦–æ¬¡åˆ¶é€ "
L["UNIQUES"] = "å‘¨çŸ¥è¯†"
L["TREATISE"] = "è®ºè¿°"
L["GATHERING"] = "é‡‡é›†"
L["CATCH_UP"] = "è¿½èµ¶"
L["MOXIE"] = "åŒ äºº"
L["COOLDOWNS"] = "å†·å´"
L["ACCESSORY_1"] = "é…é¥° 1"
L["ACCESSORY_2"] = "é…é¥° 2"
L["COLUMNS_BUTTON"] = "åˆ—"
L["ORDERS"] = "è®¢å•"

-- Professions: Tooltips & Details
L["RECIPES_COLUMN_FORMAT"] = "åˆ—æ˜¾ç¤ºå·²å­¦ / æ€»è®¡ï¼ˆæ€»è®¡å«æœªå­¦ï¼‰"
L["LEARNED_RECIPES"] = "å·²å­¦é…æ–¹"
L["UNLEARNED_RECIPES"] = "æœªå­¦é…æ–¹"
L["LAST_SCANNED"] = "ä¸Šæ¬¡æ‰«æ"
L["JUST_NOW"] = "åˆšåˆš"
L["RECIPE_NO_DATA"] = "æ‰“å¼€ä¸“ä¸šçª—å£ï¼Œæ”¶é›†é…æ–¹æ•°æ®"
L["FIRST_CRAFT_AVAILABLE"] = "å¯ç”¨é¦–æ¬¡åˆ¶é€ "
L["FIRST_CRAFT_DESC"] = "é¦–æ¬¡åˆ¶é€ æ—¶è·å¾—åŠ æˆç»éªŒçš„é…æ–¹"
L["SKILLUP_RECIPES"] = "æŠ€èƒ½æå‡é…æ–¹"
L["SKILLUP_DESC"] = "ä»å¯æå‡æŠ€èƒ½ç­‰çº§çš„é…æ–¹"
L["NO_ACTIVE_COOLDOWNS"] = "æ— æ´»è·ƒå†·å´"

-- Professions: Crafting Orders
L["CRAFTING_ORDERS"] = "åˆ¶é€ è®¢å•"
L["PERSONAL_ORDERS"] = "ä¸ªäººè®¢å•"
L["PUBLIC_ORDERS"] = "å…¬å…±è®¢å•"
L["CLAIMS_REMAINING"] = "å‰©ä½™é¢†å–"
L["NO_ACTIVE_ORDERS"] = "æ— æ´»è·ƒè®¢å•"
L["ORDER_NO_DATA"] = "åœ¨åˆ¶é€ å°æ‰“å¼€ä¸“ä¸šä»¥æ‰«æ"

-- Professions: Equipment
L["EQUIPMENT"] = "è£…å¤‡"
L["TOOL"] = "å·¥å…·"
L["ACCESSORY"] = "é…ä»¶"
L["PROF_EQUIPMENT_HINT"] = "åœ¨æ­¤è§’è‰²ä¸Šæ‰“å¼€ä¸“ä¸šæŠ€èƒ½(K)ä»¥æ‰«æè£…å¤‡ã€‚"

-- Professions: Info Window
L["PROF_INFO_TOOLTIP"] = "æŸ¥çœ‹ä¸“ä¸šè¯¦æƒ…"
L["PROF_INFO_NO_DATA"] = "æ— ä¸“ä¸šæ•°æ®ã€‚\nè¯·ç™»å½•æ­¤è§’è‰²å¹¶æ‰“å¼€ä¸“ä¸šæŠ€èƒ½çª—å£(K)ä»¥æ”¶é›†æ•°æ®ã€‚"
L["PROF_INFO_SKILLS"] = "èµ„æ–™ç‰‡æŠ€èƒ½"
L["PROF_INFO_SPENT"] = "å·²ä½¿ç”¨"
L["PROF_INFO_TOOL"] = "å·¥å…·"
L["PROF_INFO_ACC1"] = "é¥°å“ 1"
L["PROF_INFO_ACC2"] = "é¥°å“ 2"
L["PROF_INFO_KNOWN"] = "å·²å­¦"
L["PROF_INFO_WEEKLY"] = "æ¯å‘¨çŸ¥è¯†è¿›åº¦"
L["PROF_INFO_COOLDOWNS"] = "å†·å´"
L["PROF_INFO_READY"] = "å°±ç»ª"
L["PROF_INFO_LAST_UPDATE"] = "ä¸Šæ¬¡æ›´æ–°"
L["PROF_INFO_UNLOCKED"] = "å·²è§£é”"
L["PROF_INFO_LOCKED"] = "å·²é”å®š"
L["PROF_INFO_UNLEARNED"] = "æœªå­¦ä¹ "
L["PROF_INFO_NODES"] = "èŠ‚ç‚¹"
L["PROF_INFO_RANKS"] = "ç­‰çº§"

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
L["ADD_CUSTOM_DESC"] = "æ·»åŠ å†…ç½®æ•°æ®åº“ä¸­æœªåŒ…å«çš„æ‰è½æ¥æºï¼Œæˆ–ç§»é™¤ç°æœ‰è‡ªå®šä¹‰æ¡ç›®ã€‚"
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
L["NPC"] = "NPC"
L["OBJECT"] = "ç‰©ä½“"
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
L["ADD_ITEMS_TO_PLANS"] = "å°†ç‰©å“æ·»åŠ åˆ°è®¡åˆ’ä¸­å³å¯åœ¨æ­¤æŸ¥çœ‹ï¼"
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
L["TRYCOUNTER_AFTER_TRIES"] = "ç»è¿‡ %d æ¬¡å°è¯•"
L["TRYCOUNTER_FIRST_TRY"] = "é¦–æ¬¡å°è¯•å°±æˆåŠŸäº†ï¼"
L["TRYCOUNTER_LOCKOUT_SKIP"] = "å·²è·³è¿‡ï¼šæ­¤ NPC çš„æ¯æ—¥/æ¯å‘¨é”å®šå·²æ¿€æ´»ã€‚"
L["TRYCOUNTER_INSTANCE_DROPS"] = "æ­¤å‰¯æœ¬ä¸­çš„æ”¶è—å“æ‰è½ï¼š"
L["TRYCOUNTER_INSTANCE_ENTRY_HINT"] = "æ­¤å‰¯æœ¬æœ‰é€‚ç”¨äºä½ å½“å‰éš¾åº¦çš„å°è¯•è®¡æ•°åéª‘ã€‚å¯¹é¦–é¢†ä½¿ç”¨ç›®æ ‡æˆ–é¼ æ ‡æŒ‡å‘åè¾“å…¥ |cffffffff/wn check|r æŸ¥çœ‹è¯¦æƒ…ã€‚"
L["TRYCOUNTER_INSTANCE_COLLECTIBLE_DETECTED"] = "æ£€æµ‹åˆ°æ”¶è—å“ï¼š "
L["TRYCOUNTER_INSTANCE_WRONG_DIFF"] = "éš¾åº¦ä¸ç¬¦ï¼šéœ€è¦ %sï¼ˆä½ å½“å‰ä¸º %sï¼‰ã€‚"
L["TRYCOUNTER_INSTANCE_REQUIRES_UNVERIFIED"] = "éœ€è¦ %sï¼ˆæ— æ³•æ£€æµ‹å½“å‰éš¾åº¦ï¼‰ã€‚"
L["TRYCOUNTER_COLLECTED_TAG"] = "ï¼ˆå·²æ”¶é›†ï¼‰"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " æ¬¡å°è¯•"
L["TRYCOUNTER_TYPE_MOUNT"] = "åéª‘"
L["TRYCOUNTER_TYPE_PET"] = "å® ç‰©"
L["TRYCOUNTER_TYPE_TOY"] = "ç©å…·"
L["TRYCOUNTER_TYPE_ITEM"] = "ç‰©å“"
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
L["COMBAT_CURRENCY_ERROR"] = "æˆ˜æ–—ä¸­æ— æ³•æ‰“å¼€è´§å¸çª—å£ã€‚æˆ˜æ–—ç»“æŸåé‡è¯•ã€‚"
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
L["CLEANUP_STALE_FORMAT"] = "å·²æ¸…ç† %d ä¸ªè¿‡æœŸè§’è‰²"
L["PERSONAL_BANK"] = "ä¸ªäººé“¶è¡Œ"
L["WARBAND_BANK_LABEL"] = "æˆ˜å›¢é“¶è¡Œ"
L["WARBAND_BANK_TAB_FORMAT"] = "æ ‡ç­¾é¡µ %d"
L["CURRENCY_OTHER"] = "å…¶ä»–"
L["ERROR_SAVING_CHARACTER"] = "ä¿å­˜è§’è‰²æ—¶å‡ºé”™ï¼š"

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
L["LT_COLLECTION_SCAN"] = "æ”¶è—æ‰«æ"

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
L["CONFIG_THEME_PRESETS"] = "ä¸»é¢˜é¢„è®¾"
L["CONFIG_THEME_APPLIED"] = "%s ä¸»é¢˜å·²åº”ç”¨ï¼"
L["CONFIG_THEME_RESET_DESC"] = "å°†æ‰€æœ‰ä¸»é¢˜è‰²é‡ç½®ä¸ºé»˜è®¤ç´«è‰²ä¸»é¢˜ã€‚"
L["CONFIG_NOTIFICATIONS"] = "é€šçŸ¥"
L["CONFIG_NOTIFICATIONS_DESC"] = "é…ç½®æ˜¾ç¤ºå“ªäº›é€šçŸ¥ã€‚"
L["CONFIG_ENABLE_NOTIFICATIONS"] = "å¯ç”¨é€šçŸ¥"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "æ˜¾ç¤ºæ”¶è—å“äº‹ä»¶å¼¹çª—é€šçŸ¥ã€‚"
L["CONFIG_NOTIFY_MOUNTS"] = "åéª‘é€šçŸ¥"
L["CONFIG_NOTIFY_MOUNTS_DESC"] = "å­¦ä¹ æ–°åéª‘æ—¶æ˜¾ç¤ºé€šçŸ¥ã€‚"
L["CONFIG_NOTIFY_PETS"] = "å® ç‰©é€šçŸ¥"
L["CONFIG_NOTIFY_PETS_DESC"] = "å­¦ä¹ æ–°å® ç‰©æ—¶æ˜¾ç¤ºé€šçŸ¥ã€‚"
L["CONFIG_NOTIFY_TOYS"] = "ç©å…·é€šçŸ¥"
L["CONFIG_NOTIFY_TOYS_DESC"] = "å­¦ä¹ æ–°ç©å…·æ—¶æ˜¾ç¤ºé€šçŸ¥ã€‚"
L["CONFIG_NOTIFY_ACHIEVEMENTS"] = "æˆå°±é€šçŸ¥"
L["CONFIG_NOTIFY_ACHIEVEMENTS_DESC"] = "è·å¾—æˆå°±æ—¶æ˜¾ç¤ºé€šçŸ¥ã€‚"
L["CONFIG_SHOW_UPDATE_NOTES"] = "å†æ¬¡æ˜¾ç¤ºæ›´æ–°è¯´æ˜"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "ä¸‹æ¬¡ç™»å½•æ—¶æ˜¾ç¤ºã€Œæ›´æ–°å†…å®¹ã€çª—å£ã€‚"
L["CONFIG_UPDATE_NOTES_SHOWN"] = "æ›´æ–°é€šçŸ¥å°†åœ¨ä¸‹æ¬¡ç™»å½•æ—¶æ˜¾ç¤ºã€‚"
L["CONFIG_RESET_PLANS"] = "é‡ç½®å·²å®Œæˆè®¡åˆ’"
L["CONFIG_RESET_PLANS_CONFIRM"] = "å°†ç§»é™¤æ‰€æœ‰å·²å®Œæˆè®¡åˆ’ã€‚ç»§ç»­ï¼Ÿ"
L["CONFIG_RESET_PLANS_FORMAT"] = "å·²ç§»é™¤ %d ä¸ªå·²å®Œæˆè®¡åˆ’ã€‚"
L["CONFIG_NO_COMPLETED_PLANS"] = "æ— å·²å®Œæˆè®¡åˆ’å¯ç§»é™¤ã€‚"
L["CONFIG_TAB_FILTERING"] = "æ ‡ç­¾é¡µç­›é€‰"
L["CONFIG_TAB_FILTERING_DESC"] = "é€‰æ‹©ä¸»çª—å£ä¸­å¯è§çš„æ ‡ç­¾é¡µã€‚"
L["CONFIG_CHARACTER_MGMT"] = "è§’è‰²ç®¡ç†"
L["CONFIG_CHARACTER_MGMT_DESC"] = "ç®¡ç†è¿½è¸ªçš„è§’è‰²å¹¶ç§»é™¤æ—§æ•°æ®ã€‚"
L["CONFIG_DELETE_CHAR"] = "åˆ é™¤è§’è‰²æ•°æ®"
L["CONFIG_DELETE_CHAR_DESC"] = "æ°¸ä¹…ç§»é™¤æ‰€é€‰è§’è‰²çš„æ‰€æœ‰å­˜å‚¨æ•°æ®ã€‚"
L["CONFIG_DELETE_CONFIRM"] = "ç¡®å®šè¦æ°¸ä¹…åˆ é™¤æ­¤è§’è‰²çš„æ‰€æœ‰æ•°æ®ï¼Ÿæ­¤æ“ä½œæ— æ³•æ’¤é”€ã€‚"
L["CONFIG_DELETE_SUCCESS"] = "è§’è‰²æ•°æ®å·²åˆ é™¤ï¼š"
L["CONFIG_DELETE_FAILED"] = "æœªæ‰¾åˆ°è§’è‰²æ•°æ®ã€‚"
L["CONFIG_FONT_SCALING"] = "å­—ä½“ä¸ç¼©æ”¾"
L["CONFIG_FONT_SCALING_DESC"] = "è°ƒæ•´å­—ä½“å’Œå¤§å°ç¼©æ”¾ã€‚"
L["CONFIG_FONT_FAMILY"] = "å­—ä½“"
L["CONFIG_FONT_SIZE"] = "å­—ä½“å¤§å°ç¼©æ”¾"
L["CONFIG_FONT_PREVIEW"] = "é¢„è§ˆï¼šThe quick brown fox jumps over the lazy dog"
L["CONFIG_ADVANCED"] = "é«˜çº§"
L["CONFIG_ADVANCED_DESC"] = "é«˜çº§è®¾ç½®å’Œæ•°æ®åº“ç®¡ç†ã€‚è¯·è°¨æ…ä½¿ç”¨ï¼"
L["CONFIG_DEBUG_MODE"] = "è°ƒè¯•æ¨¡å¼"
L["CONFIG_DEBUG_MODE_DESC"] = "å¯ç”¨è¯¦ç»†æ—¥å¿—ä»¥ä¾¿è°ƒè¯•ã€‚ä»…åœ¨æ’æŸ¥é—®é¢˜æ—¶å¯ç”¨ã€‚"
L["CONFIG_DEBUG_VERBOSE"] = "è¯¦ç»†è°ƒè¯•ï¼ˆç¼“å­˜/æ‰«æ/æç¤ºæ—¥å¿—ï¼‰"
L["CONFIG_DEBUG_VERBOSE_DESC"] = "è°ƒè¯•æ¨¡å¼ä¸‹åŒæ—¶æ˜¾ç¤ºè´§å¸/å£°æœ›ç¼“å­˜ã€èƒŒåŒ…æ‰«æã€æç¤ºä¸ä¸“ä¸šæ—¥å¿—ã€‚å…³é—­å¯å‡å°‘èŠå¤©åˆ·å±ã€‚"
L["CONFIG_DB_STATS"] = "æ˜¾ç¤ºæ•°æ®åº“ç»Ÿè®¡"
L["CONFIG_DB_STATS_DESC"] = "æ˜¾ç¤ºå½“å‰æ•°æ®åº“å¤§å°å’Œä¼˜åŒ–ç»Ÿè®¡ã€‚"
L["CONFIG_DB_OPTIMIZER_NA"] = "æ•°æ®åº“ä¼˜åŒ–å™¨æœªåŠ è½½"
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
L["GOLD_MANAGEMENT_DESC"] = "é…ç½®è‡ªåŠ¨é‡‘å¸ç®¡ç†ã€‚ä½¿ç”¨ C_Bank API åœ¨é“¶è¡Œæ‰“å¼€æ—¶è‡ªåŠ¨æ‰§è¡Œå­˜å…¥å’Œå–æ¬¾ã€‚"
L["GOLD_MANAGEMENT_WARNING"] = "|cff44ff44å®Œå…¨è‡ªåŠ¨ï¼š|r é“¶è¡Œæ‰“å¼€æ—¶è‡ªåŠ¨æ‰§è¡Œé‡‘å¸å­˜å…¥å’Œå–æ¬¾ã€‚è®¾ç½®ç›®æ ‡æ•°é‡ï¼Œè®©æ’ä»¶ç®¡ç†ä½ çš„é‡‘å¸ï¼"
L["GOLD_MANAGEMENT_ENABLE"] = "å¯ç”¨é‡‘å¸ç®¡ç†"
L["GOLD_MANAGEMENT_MODE"] = "ç®¡ç†æ¨¡å¼"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "ä»…å­˜å…¥"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "é‡‘å¸è¶…è¿‡ X æ—¶ï¼Œè¶…é¢è‡ªåŠ¨å­˜å…¥æˆ˜å›¢é“¶è¡Œã€‚"
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "ä»…å–æ¬¾"
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "é‡‘å¸å°‘äº X æ—¶ï¼Œå·®é¢è‡ªåŠ¨ä»æˆ˜å›¢é“¶è¡Œå–æ¬¾ã€‚"
L["GOLD_MANAGEMENT_MODE_BOTH"] = "ä¸¤è€…"
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "è‡ªåŠ¨ç»´æŒè§’è‰²é‡‘å¸æ°å¥½ä¸º Xï¼ˆå¤šåˆ™å­˜ï¼Œå°‘åˆ™å–ï¼‰ã€‚"
L["GOLD_MANAGEMENT_TARGET"] = "ç›®æ ‡é‡‘å¸æ•°é‡"
L["GOLD_MANAGEMENT_GOLD_LABEL"] = "é‡‘å¸"
L["GOLD_MANAGEMENT_HELPER"] = "è¾“å…¥ä½ æƒ³åœ¨æ­¤è§’è‰²ä¸Šä¿ç•™çš„é‡‘å¸æ•°é‡ã€‚æ‰“å¼€é“¶è¡Œæ—¶æ’ä»¶å°†è‡ªåŠ¨ç®¡ç†ä½ çš„é‡‘å¸ã€‚"
L["GOLD_MANAGEMENT_CHAR_ONLY"] = "ä»…æ­¤è§’è‰² (%s)"
L["GOLD_MANAGEMENT_CHAR_ONLY_DESC"] = "ä»…ä¸ºæ­¤è§’è‰²ä½¿ç”¨å•ç‹¬çš„é‡‘å¸ç®¡ç†è®¾ç½®ã€‚å…¶ä»–è§’è‰²å°†ä½¿ç”¨å…±äº«é…ç½®ã€‚"
L["GOLD_MGMT_PROFILE_TITLE"] = "é…ç½®ï¼ˆæ‰€æœ‰è§’è‰²ï¼‰"
L["GOLD_MGMT_TARGET_LABEL"] = "ç›®æ ‡"
L["GOLD_MGMT_USING_PROFILE"] = "ä½¿ç”¨é…ç½®"
L["GOLD_MGMT_MODE_SHORT_DEPOSIT"] = "å­˜å…¥"
L["GOLD_MGMT_MODE_SHORT_WITHDRAW"] = "å–å‡º"
L["GOLD_MGMT_MODE_SHORT_BOTH"] = "åŒå‘"
L["GOLD_MGMT_ACTIVE"] = "æ¿€æ´»"
L["ENABLED"] = "å·²å¯ç”¨"
L["DISABLED"] = "å·²ç¦ç”¨"
L["GOLD_MANAGEMENT_NOTIFICATION_DEPOSIT"] = "å­˜å…¥ %s è‡³æˆ˜å›¢é“¶è¡Œï¼ˆä½ æœ‰ %sï¼‰"
L["GOLD_MANAGEMENT_NOTIFICATION_WITHDRAW"] = "ä»æˆ˜å›¢é“¶è¡Œå–æ¬¾ %sï¼ˆä½ æœ‰ %sï¼‰"
L["GOLD_MANAGEMENT_DEPOSITED"] = "å·²å­˜å…¥ %s è‡³æˆ˜å›¢é“¶è¡Œ"
L["GOLD_MANAGEMENT_WITHDRAWN"] = "å·²ä»æˆ˜å›¢é“¶è¡Œå–æ¬¾ %s"
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
L["GEAR_CRAFTED_RECRAFT_RANGE"] = "å†é€ èŒƒå›´ï¼š%d-%dï¼ˆ%s é»æ˜çº¹ç« ï¼‰"
L["GEAR_CRAFTED_CREST_COST"] = "å†é€ æ¶ˆè€—ï¼š%d çº¹ç« "
L["GEAR_CRAFTED_NO_CRESTS"] = "æ²¡æœ‰å¯ç”¨äºå†é€ çš„çº¹ç« "
L["GEAR_TRACK_CRAFTED_FALLBACK"] = "åˆ¶é€ "
L["GEAR_CRAFTED_MAX_ILVL_LINE"] = "%sï¼ˆæœ€é«˜è£…ç­‰ %dï¼‰"
L["GEAR_CRAFTED_RECAST_TO_LINE"] = "å†é€ è‡³ %sï¼ˆè£…ç­‰ %dï¼‰"
L["GEAR_CRAFTED_COST_DAWNCREST"] = "æ¶ˆè€—ï¼š%d %s é»æ˜çº¹ç« "
L["GEAR_CRAFTED_NEXT_TIER_CRESTS"] = "%sï¼ˆè£…ç­‰ %dï¼‰ï¼šçº¹ç«  %d/%dï¼ˆè¿˜éœ€ %dï¼‰"
L["GEAR_TAB_TITLE"] = "è£…å¤‡ç®¡ç†"
L["GEAR_TAB_DESC"] = "å·²è£…å¤‡ã€å‡çº§é€‰é¡¹åŠè·¨è§’è‰²å‡çº§å€™é€‰"
L["GEAR_SECTION_EQUIPPED"] = "å·²è£…å¤‡"
L["GEAR_SECTION_RESOURCES"] = "èµ„æº"
L["GEAR_SECTION_UPGRADES"] = "å‡çº§æœºä¼š"
L["GEAR_SECTION_STORAGE"] = "å­˜å‚¨å‡çº§"
L["GEAR_SECTION_LIST"] = "æ‰€æœ‰å·²è£…å¤‡ç‰©å“"
L["GEAR_UPGRADEABLE_SLOTS"] = "éƒ¨ä½å¯å‡çº§"
L["GEAR_NO_UPGRADES_AVAILABLE"] = "å½“å‰èµ„æºä¸‹æ— å¯ç”¨å‡çº§"
L["GEAR_NO_UPGRADE_ITEMS"] = "æ— å¯ç”¨å‡çº§ - æ‰€æœ‰è£…å¤‡å·²è¾¾æœ€é«˜ç­‰çº§æˆ–ä¸æ”¯æŒã€‚"
L["GEAR_UPGRADE_CURRENT_CHAR_ONLY"] = "å‡çº§ä¿¡æ¯ä»…å¯¹å½“å‰è§’è‰²å¯ç”¨ã€‚"
L["GEAR_NO_STORAGE_FINDS"] = "æœªæ‰¾åˆ°å­˜å‚¨å‡çº§ã€‚æ‰“å¼€é“¶è¡Œæ ‡ç­¾é¡µä»¥è·å¾—æ›´å¥½ç»“æœã€‚"
L["GEAR_NO_CURRENCY_DATA"] = "å°šæ— è´§å¸æ•°æ®"
L["GEAR_SEARCH_PLACEHOLDER"] = "æœç´¢å·²è£…å¤‡ç‰©å“..."
L["GEAR_NO_ITEMS_FOUND"] = "æœªæ‰¾åˆ°åŒ¹é…çš„å·²è£…å¤‡ç‰©å“"
L["GEAR_STORAGE_BEST"] = "æœ€ä½³"
L["GEAR_STORAGE_WARBOUND"] = "æˆ˜å›¢ç»‘å®š"
L["GEAR_STORAGE_BOE"] = "è£…ç»‘"
L["GEAR_STORAGE_UPGRADE_LINE"] = "%d â†’ %d"
L["GEAR_STORAGE_TITLE"] = "å­˜å‚¨å‡çº§æ¨è"
L["GEAR_STORAGE_DESC"] = "å„éƒ¨ä½æœ€ä½³è£…ç»‘ / æˆ˜å›¢ç»‘å®šå‡çº§"
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
L["CHILDREN_ACHIEVEMENTS"] = "åç»­æˆå°±"
L["LOADING_ACHIEVEMENTS"] = "åŠ è½½æˆå°±ä¸­..."
L["PARENT_ACHIEVEMENT"] = "å‰ç½®æˆå°±"
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. "è´§å¸..."
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. "ç‰©å“..."
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. "å£°æœ›..."
L["TAB_GEAR"] = "è£…å¤‡"

-- Keybinding globals (must be global for WoW's keybinding UI)
BINDING_HEADER_WARBANDNEXUS = "Warband Nexus"
BINDING_NAME_WARBANDNEXUS_TOGGLE = "æ˜¾ç¤º/éšè—ä¸»çª—å£"

-- Blizzard GlobalStrings (Auto-localized by WoW) [parity sync]
L["BANK_LABEL"] = BANK or "Bank"
L["BTN_CLOSE"] = CLOSE
L["BTN_REFRESH"] = REFRESH
L["BTN_SETTINGS"] = SETTINGS
L["CANCEL"] = CANCEL or "Cancel"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Achievements"
L["CATEGORY_ALL"] = ALL or "All Items"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumables"
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipment"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"
L["CATEGORY_MOUNTS"] = MOUNTS or "Mounts"
L["CATEGORY_PETS"] = PETS or "Pets"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quest Items"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagents"
L["CATEGORY_TITLES"] = L["TYPE_TITLE"] or TITLES or "Titles"
L["CATEGORY_TOYS"] = TOY_BOX or "Toys"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Trade Goods"
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmog"
L["DELETE"] = DELETE or "Delete"
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "Heroic"
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "Mythic"
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "Normal"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "Dungeon"
L["ENABLE"] = ENABLE or "Enable"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Unknown"
L["FIRSTCRAFT"] = PROFESSIONS_FIRST_CRAFT or "First Craft"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumables"
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipment"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quest"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagents"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Trade Goods"
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
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Dungeons"
L["PVE_HEADER_RAIDS"] = RAIDS or "Raids"
L["PVP_TYPE"] = PVP or "PvP"
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC
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
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "Crafted"
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
L["STATS_HEADER"] = STATISTICS or "Statistics"
L["TAB_CHARACTERS"] = CHARACTER or "Characters"
L["TAB_CURRENCY"] = CURRENCY or "Currency"
L["TAB_ITEMS"] = ITEMS or "Items"
L["TAB_REPUTATION"] = REPUTATION or "Reputation"
L["TAB_STATISTICS"] = STATISTICS or "Statistics"
L["TOOLTIP_CHARACTER"] = CHARACTER or "Character"
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Location"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Achievement"
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Boss Drop"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Profession"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Quest"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Vendor"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "World Drop"
L["TYPE_MOUNT"] = MOUNT or "Mount"
L["TYPE_PET"] = PET or "Pet"
L["TYPE_TOY"] = TOY or "Toy"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transmog"
L["VAULT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon"
L["VAULT_RAID"] = RAID or "Raid"
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

