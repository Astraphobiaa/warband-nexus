--[[
    Warband Nexus - Korean Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "koKR")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus가 로드되었습니다. 옵션을 보려면 /wn 또는 /warbandnexus를 입력하세요."
L["VERSION"] = GAME_VERSION_LABEL or "버전"

-- Slash Commands
L["SLASH_HELP"] = "사용 가능한 명령어:"
L["SLASH_OPTIONS"] = "옵션 패널 열기"
L["SLASH_SCAN"] = "전쟁부대 은행 스캔"
L["SLASH_SHOW"] = "메인 창 표시/숨기기"
L["SLASH_DEPOSIT"] = "입금 대기열 열기"
L["SLASH_SEARCH"] = "아이템 검색"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "일반 설정"
L["GENERAL_SETTINGS_DESC"] = "애드온의 일반적인 동작 설정"
L["ENABLE_ADDON"] = "애드온 활성화"
L["ENABLE_ADDON_DESC"] = "Warband Nexus 기능 활성화 또는 비활성화"
L["MINIMAP_ICON"] = "미니맵 아이콘 표시"
L["MINIMAP_ICON_DESC"] = "미니맵 버튼 표시 또는 숨기기"
L["DEBUG_MODE"] = "디버그 모드"
L["DEBUG_MODE_DESC"] = "채팅에 디버그 메시지 활성화"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "스캔 설정"
L["SCANNING_SETTINGS_DESC"] = "은행 스캔 동작 설정"
L["AUTO_SCAN"] = "은행 열 때 자동 스캔"
L["AUTO_SCAN_DESC"] = "은행을 열 때 자동으로 전쟁부대 은행 스캔"
L["SCAN_DELAY"] = "스캔 지연"
L["SCAN_DELAY_DESC"] = "스캔 작업 사이의 지연 시간 (초)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "입금 설정"
L["DEPOSIT_SETTINGS_DESC"] = "아이템 입금 동작 설정"
L["GOLD_RESERVE"] = "골드 예비금"
L["GOLD_RESERVE_DESC"] = "개인 인벤토리에 보관할 최소 골드 (골드 단위)"
L["AUTO_DEPOSIT_REAGENTS"] = "시약 자동 입금"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "은행을 열 때 시약을 입금 대기열에 추가"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "표시 설정"
L["DISPLAY_SETTINGS_DESC"] = "시각적 외관 설정"
L["SHOW_ITEM_LEVEL"] = "아이템 레벨 표시"
L["SHOW_ITEM_LEVEL_DESC"] = "장비에 아이템 레벨 표시"
L["SHOW_ITEM_COUNT"] = "아이템 수량 표시"
L["SHOW_ITEM_COUNT_DESC"] = "아이템에 스택 수량 표시"
L["HIGHLIGHT_QUALITY"] = "품질별 강조"
L["HIGHLIGHT_QUALITY_DESC"] = "아이템 품질에 따라 색상 테두리 추가"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "탭 설정"
L["TAB_SETTINGS_DESC"] = "전쟁부대 은행 탭 동작 설정"
L["IGNORED_TABS"] = "무시할 탭"
L["IGNORED_TABS_DESC"] = "스캔 및 작업에서 제외할 탭 선택"
L["TAB_1"] = "전쟁부대 탭 1"
L["TAB_2"] = "전쟁부대 탭 2"
L["TAB_3"] = "전쟁부대 탭 3"
L["TAB_4"] = "전쟁부대 탭 4"
L["TAB_5"] = "전쟁부대 탭 5"

-- Scanner Module
L["SCAN_STARTED"] = "전쟁부대 은행을 스캔하는 중..."
L["SCAN_COMPLETE"] = "스캔 완료. %d개의 슬롯에서 %d개의 아이템을 찾았습니다."
L["SCAN_FAILED"] = "스캔 실패: 전쟁부대 은행이 열려 있지 않습니다."
L["SCAN_TAB"] = "탭 %d 스캔 중..."
L["CACHE_CLEARED"] = "아이템 캐시가 삭제되었습니다."
L["CACHE_UPDATED"] = "아이템 캐시가 업데이트되었습니다."

-- Banker Module
L["BANK_NOT_OPEN"] = "전쟁부대 은행이 열려 있지 않습니다."
L["DEPOSIT_STARTED"] = "입금 작업 시작..."
L["DEPOSIT_COMPLETE"] = "입금 완료. %d개의 아이템이 이전되었습니다."
L["DEPOSIT_CANCELLED"] = "입금이 취소되었습니다."
L["DEPOSIT_QUEUE_EMPTY"] = "입금 대기열이 비어 있습니다."
L["DEPOSIT_QUEUE_CLEARED"] = "입금 대기열이 비워졌습니다."
L["ITEM_QUEUED"] = "%s이(가) 입금 대기열에 추가되었습니다."
L["ITEM_REMOVED"] = "%s이(가) 대기열에서 제거되었습니다."
L["GOLD_DEPOSITED"] = "%s 골드가 전쟁부대 은행에 입금되었습니다."
L["INSUFFICIENT_GOLD"] = "입금할 골드가 부족합니다."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "잘못된 금액입니다."
L["WITHDRAW_BANK_NOT_OPEN"] = "출금하려면 은행을 열어야 합니다!"
L["WITHDRAW_IN_COMBAT"] = "전투 중에는 출금할 수 없습니다."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "전쟁부대 은행에 골드가 부족합니다."
L["WITHDRAWN_LABEL"] = "출금:"
L["WITHDRAW_API_UNAVAILABLE"] = "출금 API를 사용할 수 없습니다."
L["SORT_IN_COMBAT"] = "전투 중에는 정렬할 수 없습니다."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global
L["SEARCH_CATEGORY_FORMAT"] = "%s 검색..."
L["BTN_SCAN"] = "은행 스캔"
L["BTN_DEPOSIT"] = "입금 대기열"
L["BTN_SORT"] = "은행 정렬"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "대기열 비우기"
L["BTN_DEPOSIT_ALL"] = "전부 입금"
L["BTN_DEPOSIT_GOLD"] = "골드 입금"
L["ENABLE"] = ENABLE or "활성화" -- Blizzard Global
L["ENABLE_MODULE"] = "모듈 활성화"

-- Main Tabs (Blizzard Globals where available)
L["TAB_CHARACTERS"] = CHARACTER or "캐릭터" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "아이템" -- Blizzard Global
L["TAB_STORAGE"] = "보관함"
L["TAB_PLANS"] = "계획"
L["TAB_REPUTATION"] = REPUTATION or "평판" -- Blizzard Global
L["TAB_REPUTATIONS"] = "평판"
L["TAB_CURRENCY"] = CURRENCY or "화폐" -- Blizzard Global
L["TAB_CURRENCIES"] = "화폐"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "통계" -- Blizzard Global

-- Item Categories (Using Blizzard Globals where available)
L["CATEGORY_ALL"] = ALL or "모든 아이템" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "장비" -- Blizzard Global
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "소비용품" -- Blizzard Global
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "시약" -- Blizzard Global
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "거래 용품" -- Blizzard Global
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "퀘스트 아이템" -- Blizzard Global
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "기타" -- Blizzard Global

-- Quality Filters (Using Blizzard Globals - automatically localized!)
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC -- Blizzard Global: "Poor"
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC -- Blizzard Global: "Common"
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC -- Blizzard Global: "Uncommon"
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC -- Blizzard Global: "Rare"
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC -- Blizzard Global: "Epic"
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC -- Blizzard Global: "Legendary"
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC -- Blizzard Global: "Artifact"
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC -- Blizzard Global: "Heirloom"

-- Characters Tab
L["HEADER_FAVORITES"] = FAVORITES or "즐겨찾기" -- Blizzard Global
L["HEADER_CHARACTERS"] = CHARACTER or "캐릭터"
L["HEADER_CURRENT_CHARACTER"] = "현재 캐릭터"
L["HEADER_WARBAND_GOLD"] = "전쟁부대 골드"
L["HEADER_TOTAL_GOLD"] = "총 골드"
L["HEADER_REALM_GOLD"] = "서버 골드"
L["HEADER_REALM_TOTAL"] = "서버 합계"
L["CHARACTER_LAST_SEEN_FORMAT"] = "마지막 접속: %s"
L["CHARACTER_GOLD_FORMAT"] = "골드: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "이 서버의 모든 캐릭터의 합산 골드"

-- Items Tab
L["ITEMS_HEADER"] = "은행 아이템"
L["ITEMS_HEADER_DESC"] = "전쟁부대 은행과 개인 은행을 탐색하고 관리"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " 아이템..."
L["ITEMS_WARBAND_BANK"] = "전쟁부대 은행"
L["ITEMS_PLAYER_BANK"] = BANK or "개인 은행" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "길드 은행" -- Blizzard Global
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "장비"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "소비용품"
L["GROUP_PROFESSION"] = "전문 기술"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "시약"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "거래 용품"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "퀘스트"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "기타"
L["GROUP_CONTAINER"] = "용기"

-- Storage Tab
L["STORAGE_HEADER"] = "보관함 브라우저"
L["STORAGE_HEADER_DESC"] = "유형별로 정리된 모든 아이템 탐색"
L["STORAGE_WARBAND_BANK"] = "전쟁부대 은행"
L["STORAGE_PERSONAL_BANKS"] = "개인 은행"
L["STORAGE_TOTAL_SLOTS"] = "총 슬롯"
L["STORAGE_FREE_SLOTS"] = "빈 슬롯"
L["STORAGE_BAG_HEADER"] = "전쟁부대 가방"
L["STORAGE_PERSONAL_HEADER"] = "개인 은행"

-- Plans Tab
L["PLANS_MY_PLANS"] = "내 계획"
L["PLANS_COLLECTIONS"] = "수집 계획"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "사용자 정의 계획 추가"
L["PLANS_NO_RESULTS"] = "결과를 찾을 수 없습니다."
L["PLANS_ALL_COLLECTED"] = "모든 아이템을 수집했습니다!"
L["PLANS_RECIPE_HELP"] = "인벤토리의 제조법을 우클릭하여 여기에 추가하세요."
L["COLLECTION_PLANS"] = "수집 계획"
L["SEARCH_PLANS"] = "계획 검색..."
L["COMPLETED_PLANS"] = "완료된 계획"
L["SHOW_COMPLETED"] = "완료 표시"

-- Plans Categories (Blizzard Globals where available)
L["CATEGORY_MY_PLANS"] = "내 계획"
L["CATEGORY_DAILY_TASKS"] = "일일 과제"
L["CATEGORY_MOUNTS"] = MOUNTS or "탈것" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "애완동물" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "장난감" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "형상변환" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "환영"
L["CATEGORY_TITLES"] = "칭호"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "업적" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " 평판..."
L["REP_HEADER_WARBAND"] = "전쟁부대 평판"
L["REP_HEADER_CHARACTER"] = "캐릭터 평판"
L["REP_STANDING_FORMAT"] = "등급: %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " 화폐..."
L["CURRENCY_HEADER_WARBAND"] = "전쟁부대 전송 가능"
L["CURRENCY_HEADER_CHARACTER"] = "캐릭터 귀속"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "공격대" -- Blizzard Global
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "던전" -- Blizzard Global
L["PVE_HEADER_DELVES"] = "탐험"
L["PVE_HEADER_WORLD_BOSS"] = "월드 보스"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "통계" -- Blizzard Global: STATISTICS
L["STATS_TOTAL_ITEMS"] = "총 아이템"
L["STATS_TOTAL_SLOTS"] = "총 슬롯"
L["STATS_FREE_SLOTS"] = "빈 슬롯"
L["STATS_USED_SLOTS"] = "사용된 슬롯"
L["STATS_TOTAL_VALUE"] = "총 가치"
L["COLLECTED"] = "수집됨"
L["TOTAL"] = "합계"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "캐릭터" -- Blizzard Global: CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "위치" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "전쟁부대 은행"
L["TOOLTIP_TAB"] = "탭"
L["TOOLTIP_SLOT"] = "슬롯"
L["TOOLTIP_COUNT"] = "수량"
L["CHARACTER_INVENTORY"] = "가방"
L["CHARACTER_BANK"] = "은행"

-- Try Counter
L["TRY_COUNT"] = "시도 횟수"
L["SET_TRY_COUNT"] = "시도 횟수 설정"
L["TRIES"] = "시도"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "초기화 주기 설정"
L["DAILY_RESET"] = "일일 초기화"
L["WEEKLY_RESET"] = "주간 초기화"
L["NONE_DISABLE"] = "없음 (비활성화)"
L["RESET_CYCLE_LABEL"] = "초기화 주기:"
L["RESET_NONE"] = "없음"
L["DOUBLECLICK_RESET"] = "더블클릭으로 위치 초기화"

-- Error Messages
L["ERROR_GENERIC"] = "오류가 발생했습니다."
L["ERROR_API_UNAVAILABLE"] = "필요한 API를 사용할 수 없습니다."
L["ERROR_BANK_CLOSED"] = "작업을 수행할 수 없습니다: 은행이 닫혀 있습니다."
L["ERROR_INVALID_ITEM"] = "지정된 아이템이 올바르지 않습니다."
L["ERROR_PROTECTED_FUNCTION"] = "전투 중에는 보호된 함수를 호출할 수 없습니다."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "%d개의 아이템을 전쟁부대 은행에 입금하시겠습니까?"
L["CONFIRM_CLEAR_QUEUE"] = "입금 대기열의 모든 아이템을 제거하시겠습니까?"
L["CONFIRM_DEPOSIT_GOLD"] = "%s 골드를 전쟁부대 은행에 입금하시겠습니까?"

-- Update Notification
L["WHATS_NEW"] = "새로운 소식"
L["GOT_IT"] = "확인!"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "업적 점수"
L["MOUNTS_COLLECTED"] = "수집한 탈것"
L["BATTLE_PETS"] = "전투 애완동물"
L["ACCOUNT_WIDE"] = "계정 전체"
L["STORAGE_OVERVIEW"] = "보관함 개요"
L["WARBAND_SLOTS"] = "전쟁부대 슬롯"
L["PERSONAL_SLOTS"] = "개인 슬롯"
L["TOTAL_FREE"] = "총 여유"
L["TOTAL_ITEMS"] = "총 아이템"

-- Plans Tracker Window
L["WEEKLY_VAULT"] = "주간 금고"
L["CUSTOM"] = "사용자 정의"
L["NO_PLANS_IN_CATEGORY"] = "이 카테고리에 계획이 없습니다.\n계획 탭에서 계획을 추가하세요."
L["SOURCE_LABEL"] = "출처:"
L["ZONE_LABEL"] = "지역:"
L["VENDOR_LABEL"] = "상인:"
L["DROP_LABEL"] = "전리품:"
L["REQUIREMENT_LABEL"] = "요구사항:"
L["RIGHT_CLICK_REMOVE"] = "우클릭으로 제거"
L["TRACKED"] = "추적 중"
L["TRACK"] = "추적"
L["TRACK_BLIZZARD_OBJECTIVES"] = "블리자드 목표에 추적 (최대 10)"
L["UNKNOWN"] = "알 수 없음"
L["NO_REQUIREMENTS"] = "요구사항 없음 (즉시 완료)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "계획된 활동 없음"
L["CLICK_TO_ADD_GOALS"] = "위의 탈것, 애완동물 또는 장난감을 클릭하여 목표를 추가하세요!"
L["UNKNOWN_QUEST"] = "알 수 없는 퀘스트"
L["ALL_QUESTS_COMPLETE"] = "모든 퀘스트 완료!"
L["CURRENT_PROGRESS"] = "현재 진행도"
L["SELECT_CONTENT"] = "콘텐츠 선택:"
L["QUEST_TYPES"] = "퀘스트 유형:"
L["WORK_IN_PROGRESS"] = "개발 중"
L["RECIPE_BROWSER"] = "제조법 브라우저"
L["NO_RESULTS_FOUND"] = "결과를 찾을 수 없습니다."
L["TRY_ADJUSTING_SEARCH"] = "검색어나 필터를 조정해 보세요."
L["NO_COLLECTED_YET"] = "아직 수집한 %s이 없습니다"
L["START_COLLECTING"] = "수집을 시작하면 여기에 표시됩니다!"
L["ALL_COLLECTED_CATEGORY"] = "모든 %s을 수집했습니다!"
L["COLLECTED_EVERYTHING"] = "이 카테고리의 모든 것을 수집했습니다!"
L["PROGRESS_LABEL"] = "진행도:"
L["REQUIREMENTS_LABEL"] = "요구사항:"
L["INFORMATION_LABEL"] = "정보:"
L["DESCRIPTION_LABEL"] = "설명:"
L["REWARD_LABEL"] = "보상:"
L["DETAILS_LABEL"] = "세부사항:"
L["COST_LABEL"] = "비용:"
L["LOCATION_LABEL"] = "위치:"
L["TITLE_LABEL"] = "칭호:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "이 카테고리의 모든 업적을 이미 완료했습니다!"
L["DAILY_PLAN_EXISTS"] = "일일 계획이 이미 존재합니다"
L["WEEKLY_PLAN_EXISTS"] = "주간 계획이 이미 존재합니다"

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "내 캐릭터"
L["CHARACTERS_TRACKED_FORMAT"] = "%d개 캐릭터 추적 중"
L["NO_CHARACTER_DATA"] = "캐릭터 데이터 없음"
L["NO_FAVORITES"] = "즐겨찾기 캐릭터가 없습니다. 별 아이콘을 클릭하여 캐릭터를 즐겨찾기에 추가하세요."
L["ALL_FAVORITED"] = "모든 캐릭터가 즐겨찾기에 추가되었습니다!"
L["UNTRACKED_CHARACTERS"] = "추적하지 않는 캐릭터"
L["ILVL_SHORT"] = "아템레벨"
L["ONLINE"] = "온라인"
L["TIME_LESS_THAN_MINUTE"] = "< 1분 전"
L["TIME_MINUTES_FORMAT"] = "%d분 전"
L["TIME_HOURS_FORMAT"] = "%d시간 전"
L["TIME_DAYS_FORMAT"] = "%d일 전"
L["REMOVE_FROM_FAVORITES"] = "즐겨찾기에서 제거"
L["ADD_TO_FAVORITES"] = "즐겨찾기에 추가"
L["FAVORITES_TOOLTIP"] = "즐겨찾기 캐릭터는 목록 상단에 표시됩니다"
L["CLICK_TO_TOGGLE"] = "클릭하여 전환"
L["UNKNOWN_PROFESSION"] = "알 수 없는 전문 기술"
L["SKILL_LABEL"] = "기술:"
L["OVERALL_SKILL"] = "전체 기술:"
L["BONUS_SKILL"] = "보너스 기술:"
L["KNOWLEDGE_LABEL"] = "지식:"
L["SPEC_LABEL"] = "전문화"
L["POINTS_SHORT"] = "점"
L["RECIPES_KNOWN"] = "알고 있는 제조법:"
L["OPEN_PROFESSION_HINT"] = "전문 기술 창 열기"
L["FOR_DETAILED_INFO"] = "자세한 정보를 보려면"
L["CHARACTER_IS_TRACKED"] = "이 캐릭터는 추적 중입니다."
L["TRACKING_ACTIVE_DESC"] = "데이터 수집 및 업데이트가 활성화되어 있습니다."
L["CLICK_DISABLE_TRACKING"] = "클릭하여 추적 비활성화"
L["MUST_LOGIN_TO_CHANGE"] = "추적 설정을 변경하려면 이 캐릭터로 로그인해야 합니다."
L["TRACKING_ENABLED"] = "추적 활성화됨"
L["CLICK_ENABLE_TRACKING"] = "클릭하여 이 캐릭터의 추적 활성화"
L["TRACKING_WILL_BEGIN"] = "데이터 수집이 즉시 시작됩니다."
L["CHARACTER_NOT_TRACKED"] = "이 캐릭터는 추적되지 않습니다."
L["MUST_LOGIN_TO_ENABLE"] = "추적을 활성화하려면 이 캐릭터로 로그인해야 합니다."
L["ENABLE_TRACKING"] = "추적 활성화"
L["DELETE_CHARACTER_TITLE"] = "캐릭터 삭제?"
L["THIS_CHARACTER"] = "이 캐릭터"
L["DELETE_CHARACTER"] = "캐릭터 삭제"
L["REMOVE_FROM_TRACKING_FORMAT"] = "%s 추적에서 제거"
L["CLICK_TO_DELETE"] = "클릭하여 삭제"
L["CONFIRM_DELETE"] = "|cff00ccff%s|r을(를) 정말 삭제하시겠습니까?"
L["CANNOT_UNDO"] = "이 작업은 되돌릴 수 없습니다!"
L["DELETE"] = DELETE or "삭제"
L["CANCEL"] = CANCEL or "취소"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "개인 아이템"
L["ITEMS_SUBTITLE"] = "전쟁부대 은행과 개인 아이템(은행 + 인벤토리) 탐색"
L["ITEMS_DISABLED_TITLE"] = "전쟁부대 은행 아이템"
L["ITEMS_LOADING"] = "인벤토리 데이터 로딩 중"
L["GUILD_BANK_REQUIRED"] = "길드 은행에 접근하려면 길드에 가입해야 합니다."
L["ITEMS_SEARCH"] = "아이템 검색..."
L["NEVER"] = "없음"
L["ITEM_FALLBACK_FORMAT"] = "아이템 %s"
L["TAB_FORMAT"] = "탭 %d"
L["BAG_FORMAT"] = "가방 %d"
L["BANK_BAG_FORMAT"] = "은행 가방 %d"
L["ITEM_ID_LABEL"] = "아이템 ID:"
L["QUALITY_TOOLTIP_LABEL"] = "품질:"
L["STACK_LABEL"] = "스택:"
L["RIGHT_CLICK_MOVE"] = "가방으로 이동"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "스택 분할"
L["LEFT_CLICK_PICKUP"] = "집기"
L["ITEMS_BANK_NOT_OPEN"] = "은행이 열려 있지 않음"
L["SHIFT_LEFT_CLICK_LINK"] = "채팅에 링크"
L["ITEM_DEFAULT_TOOLTIP"] = "아이템"
L["ITEMS_STATS_ITEMS"] = "%s개 아이템"
L["ITEMS_STATS_SLOTS"] = "%s/%s 슬롯"
L["ITEMS_STATS_LAST"] = "마지막: %s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "캐릭터 보관함"
L["STORAGE_SEARCH"] = "보관함 검색..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "PvE 진행도"
L["PVE_SUBTITLE"] = "전쟁부대 전체의 대금고, 공격대 잠금 및 신화+"
L["PVE_NO_CHARACTER"] = "캐릭터 데이터 없음"
L["LV_FORMAT"] = "레벨 %d"
L["ILVL_FORMAT"] = "아템레벨 %d"
L["VAULT_RAID"] = "공격대"
L["VAULT_DUNGEON"] = "던전"
L["VAULT_WORLD"] = "월드"
L["VAULT_SLOT_FORMAT"] = "%s 슬롯 %d"
L["VAULT_NO_PROGRESS"] = "아직 진행도 없음"
L["VAULT_UNLOCK_FORMAT"] = "%s개 활동 완료하여 잠금 해제"
L["VAULT_NEXT_TIER_FORMAT"] = "다음 등급: %s 완료 시 %d 아이템레벨"
L["VAULT_REMAINING_FORMAT"] = "남은 활동: %s"
L["VAULT_PROGRESS_FORMAT"] = "진행도: %s / %s"
L["OVERALL_SCORE_LABEL"] = "전체 점수:"
L["BEST_KEY_FORMAT"] = "최고 쐐기돌: +%d"
L["SCORE_FORMAT"] = "점수: %s"
L["NOT_COMPLETED_SEASON"] = "이번 시즌 미완료"
L["CURRENT_MAX_FORMAT"] = "현재: %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "진행도: %.1f%%"
L["NO_CAP_LIMIT"] = "상한 없음"
L["GREAT_VAULT"] = "대금고"
L["LOADING_PVE"] = "PvE 데이터 로딩 중..."
L["PVE_APIS_LOADING"] = "잠시만 기다려 주세요, WoW API가 초기화 중입니다..."
L["NO_VAULT_DATA"] = "금고 데이터 없음"
L["NO_DATA"] = "데이터 없음"
L["KEYSTONE"] = "쐐기돌"
L["NO_KEY"] = "열쇠 없음"
L["AFFIXES"] = "속성"
L["NO_AFFIXES"] = "속성 없음"
L["VAULT_BEST_KEY"] = "최고 쐐기돌:"
L["VAULT_SCORE"] = "점수:"

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "평판 개요"
L["REP_SUBTITLE"] = "전쟁부대의 세력과 명성 추적"
L["REP_DISABLED_TITLE"] = "평판 추적"
L["REP_LOADING_TITLE"] = "평판 데이터 로딩 중"
L["REP_SEARCH"] = "평판 검색..."
L["REP_PARAGON_TITLE"] = "완벽 평판"
L["REP_REWARD_AVAILABLE"] = "보상 사용 가능!"
L["REP_CONTINUE_EARNING"] = "보상을 위해 평판 획득 계속"
L["REP_CYCLES_FORMAT"] = "주기: %d"
L["REP_PROGRESS_HEADER"] = "진행도: %d/%d"
L["REP_PARAGON_PROGRESS"] = "완벽 진행도:"
L["REP_PROGRESS_COLON"] = "진행도:"
L["REP_CYCLES_COLON"] = "주기:"
L["REP_CHARACTER_PROGRESS"] = "캐릭터 진행도:"
L["REP_RENOWN_FORMAT"] = "명성 %d"
L["REP_PARAGON_FORMAT"] = "완벽 (%s)"
L["REP_UNKNOWN_FACTION"] = "알 수 없는 세력"
L["REP_API_UNAVAILABLE_TITLE"] = "평판 API 사용 불가"
L["REP_API_UNAVAILABLE_DESC"] = "C_Reputation API가 이 서버에서 사용할 수 없습니다. 이 기능은 WoW 11.0+(The War Within)이 필요합니다."
L["REP_FOOTER_TITLE"] = "평판 추적"
L["REP_FOOTER_DESC"] = "평판은 로그인 시와 변경 시 자동으로 스캔됩니다. 자세한 정보와 보상을 보려면 게임 내 평판 패널을 사용하세요."
L["REP_CLEARING_CACHE"] = "캐시 삭제 및 다시 로딩 중..."
L["REP_LOADING_DATA"] = "평판 데이터 로딩 중..."
L["REP_MAX"] = "최대"
L["REP_TIER_FORMAT"] = "등급 %d"
L["ACCOUNT_WIDE_LABEL"] = "계정 전체"
L["NO_RESULTS"] = "결과 없음"
L["NO_REP_MATCH"] = "'%s'에 일치하는 평판이 없습니다"
L["NO_REP_DATA"] = "평판 데이터가 없습니다"
L["REP_SCAN_TIP"] = "평판은 자동으로 스캔됩니다. 아무것도 나타나지 않으면 /reload를 시도하세요."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "계정 전체 평판 (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "계정 전체 평판 없음"
L["NO_CHARACTER_REPS"] = "캐릭터 기반 평판 없음"

-- =============================================
-- Currency Tab
-- =============================================
L["CURRENCY_TITLE"] = "화폐 추적기"
L["CURRENCY_SUBTITLE"] = "모든 캐릭터의 화폐 추적"
L["CURRENCY_DISABLED_TITLE"] = "화폐 추적"
L["CURRENCY_LOADING_TITLE"] = "화폐 데이터 로딩 중"
L["CURRENCY_SEARCH"] = "화폐 검색..."
L["CURRENCY_HIDE_EMPTY"] = "비어 있음 숨기기"
L["CURRENCY_SHOW_EMPTY"] = "비어 있음 표시"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "모든 전쟁부대 전송 가능"
L["CURRENCY_CHARACTER_SPECIFIC"] = "캐릭터 전용 화폐"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "화폐 전송 제한"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "Blizzard API는 자동 화폐 전송을 지원하지 않습니다. 전쟁부대 화폐를 수동으로 전송하려면 게임 내 화폐 창을 사용하세요."
L["CURRENCY_UNKNOWN"] = "알 수 없는 화폐"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "내 계획 목록에서 완료된 모든 계획을 제거합니다. 완료된 모든 사용자 정의 계획을 삭제하고 완료된 탈것/애완동물/장난감을 계획에서 제거합니다. 이 작업은 되돌릴 수 없습니다!"
L["RECIPE_BROWSER_DESC"] = "게임 내 전문 기술 창을 열어 제조법을 탐색하세요.\n창이 열려 있을 때 애드온이 사용 가능한 제조법을 스캔합니다."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "출처: [업적 %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s은(는) 이미 활성 주간 금고 계획이 있습니다. '내 계획' 카테고리에서 찾을 수 있습니다."
L["DAILY_PLAN_EXISTS_DESC"] = "%s은(는) 이미 활성 일일 퀘스트 계획이 있습니다. '일일 과제' 카테고리에서 찾을 수 있습니다."
L["TRANSMOG_WIP_DESC"] = "형상변환 수집 추적은 현재 개발 중입니다.\n\n이 기능은 향후 업데이트에서 개선된 성능과 전쟁부대 시스템과의 더 나은 통합으로 제공될 예정입니다."
L["WEEKLY_VAULT_CARD"] = "주간 금고 카드"
L["WEEKLY_VAULT_COMPLETE"] = "주간 금고 카드 - 완료"
L["UNKNOWN_SOURCE"] = "알 수 없는 출처"
L["DAILY_TASKS_PREFIX"] = "일일 과제 - "
L["NO_FOUND_FORMAT"] = "%s을(를) 찾을 수 없습니다"
L["PLANS_COUNT_FORMAT"] = "%d개 계획"
L["PET_BATTLE_LABEL"] = "애완동물 전투:"
L["QUEST_LABEL"] = "퀘스트:"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "현재 언어:"
L["LANGUAGE_TOOLTIP"] = "애드온은 WoW 게임 클라이언트의 언어를 자동으로 사용합니다. 변경하려면 Battle.net 설정을 업데이트하세요."
L["POPUP_DURATION"] = "팝업 지속시간"
L["POPUP_POSITION"] = "팝업 위치"
L["SET_POSITION"] = "위치 설정"
L["DRAG_TO_POSITION"] = "드래그하여 위치 지정\n우클릭으로 확인"
L["RESET_DEFAULT"] = "기본값 복원"
L["TEST_POPUP"] = "팝업 테스트"
L["CUSTOM_COLOR"] = "사용자 정의 색상"
L["OPEN_COLOR_PICKER"] = "색상 선택기 열기"
L["COLOR_PICKER_TOOLTIP"] = "WoW의 기본 색상 선택기를 열어 사용자 정의 테마 색상을 선택합니다"
L["PRESET_THEMES"] = "프리셋 테마"
L["WARBAND_NEXUS_SETTINGS"] = "Warband Nexus 설정"
L["NO_OPTIONS"] = "옵션 없음"
L["NONE_LABEL"] = NONE or "없음"
L["TAB_FILTERING"] = "탭 필터링"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "알림"
L["SCROLL_SPEED"] = "스크롤 속도"
L["ANCHOR_FORMAT"] = "앵커: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "주간 계획기 표시"
L["LOCK_MINIMAP_ICON"] = "미니맵 아이콘 잠금"
L["AUTO_SCAN_ITEMS"] = "아이템 자동 스캔"
L["LIVE_SYNC"] = "실시간 동기화"
L["BACKPACK_LABEL"] = "가방"
L["REAGENT_LABEL"] = "시약"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "모듈 비활성화됨"
L["LOADING"] = "로딩 중..."
L["PLEASE_WAIT"] = "잠시만 기다려 주세요..."
L["RESET_PREFIX"] = "초기화:"
L["TRANSFER_CURRENCY"] = "화폐 전송"
L["AMOUNT_LABEL"] = "수량:"
L["TO_CHARACTER"] = "대상 캐릭터:"
L["SELECT_CHARACTER"] = "캐릭터 선택..."
L["CURRENCY_TRANSFER_INFO"] = "화폐 창이 자동으로 열립니다.\n화폐를 수동으로 우클릭하여 전송해야 합니다."
L["OK_BUTTON"] = OKAY or "확인"
L["SAVE"] = "저장"
L["TITLE_FIELD"] = "제목:"
L["DESCRIPTION_FIELD"] = "설명:"
L["CREATE_CUSTOM_PLAN"] = "사용자 정의 계획 만들기"
L["REPORT_BUGS"] = "CurseForge에서 버그를 신고하거나 제안을 공유하여 애드온 개선에 도움을 주세요."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus는 전체 전쟁부대의 모든 캐릭터, 화폐, 평판, 아이템 및 PvE 진행도를 관리하는 중앙 인터페이스를 제공합니다."
L["CHARACTERS_DESC"] = "골드, 레벨, 전문 기술 및 마지막 플레이 정보가 포함된 모든 캐릭터를 봅니다."
L["ITEMS_DESC"] = "모든 가방과 은행에서 아이템을 검색합니다. 은행을 열 때 자동으로 업데이트됩니다."
L["STORAGE_DESC"] = "모든 캐릭터와 은행에서 집계된 전체 인벤토리를 탐색합니다."
L["PVE_DESC"] = "모든 캐릭터의 대금고, 신화+ 쐐기돌 및 공격대 잠금을 추적합니다."
L["REPUTATIONS_DESC"] = "스마트 필터링(계정 전체 vs 캐릭터별)으로 평판 진행도를 모니터링합니다."
L["CURRENCY_DESC"] = "필터 옵션과 함께 확장팩별로 정리된 모든 화폐를 봅니다."
L["PLANS_DESC"] = "아직 수집하지 않은 탈것, 애완동물, 장난감, 업적 및 형상변환을 탐색하고 추적합니다."
L["STATISTICS_DESC"] = "업적 점수, 수집 진행도 및 가방/은행 사용 통계를 봅니다."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "신화"
L["DIFFICULTY_HEROIC"] = "영웅"
L["DIFFICULTY_NORMAL"] = "일반"
L["DIFFICULTY_LFR"] = "공찾"
L["TIER_FORMAT"] = "등급 %d"
L["PVP_TYPE"] = "PvP"
L["PREPARING"] = "준비 중"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "계정 통계"
L["STATISTICS_SUBTITLE"] = "수집 진행도, 골드 및 보관함 개요"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "Warband Nexus에 오신 것을 환영합니다!"
L["ADDON_OVERVIEW_TITLE"] = "애드온 개요"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "수집 목표 추적"
L["ACTIVE_PLAN_FORMAT"] = "%d개 활성 계획"
L["ACTIVE_PLANS_FORMAT"] = "%d개 활성 계획"
L["RESET_LABEL"] = RESET or "초기화"

-- Plans - Type Names
L["TYPE_MOUNT"] = "탈것"
L["TYPE_PET"] = "애완동물"
L["TYPE_TOY"] = "장난감"
L["TYPE_RECIPE"] = "제조법"
L["TYPE_ILLUSION"] = "환영"
L["TYPE_TITLE"] = "칭호"
L["TYPE_CUSTOM"] = "사용자 정의"
L["TYPE_TRANSMOG"] = "형상변환"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "시도 횟수 설정:\n%s"
L["RESET_COMPLETED_CONFIRM"] = "완료된 모든 계획을 제거하시겠습니까?\n\n이 작업은 되돌릴 수 없습니다!"
L["YES_RESET"] = "예, 초기화"
L["REMOVED_PLANS_FORMAT"] = "%d개 완료된 계획을 제거했습니다."

-- Plans - Buttons
L["ADD_CUSTOM"] = "사용자 정의 추가"
L["ADD_VAULT"] = "금고 추가"
L["ADD_QUEST"] = "퀘스트 추가"
L["CREATE_PLAN"] = "계획 만들기"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "일일"
L["QUEST_CAT_WORLD"] = "월드"
L["QUEST_CAT_WEEKLY"] = "주간"
L["QUEST_CAT_ASSIGNMENT"] = "과제"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "알 수 없는 카테고리"
L["SCANNING_FORMAT"] = "%s 스캔 중"
L["CUSTOM_PLAN_SOURCE"] = "사용자 정의 계획"
L["POINTS_FORMAT"] = "%d점"
L["SOURCE_NOT_AVAILABLE"] = "출처 정보 없음"
L["PROGRESS_ON_FORMAT"] = "진행도 %d/%d"
L["COMPLETED_REQ_FORMAT"] = "총 요구사항 %d개 중 %d개 완료"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "미드나이트"
L["CONTENT_TWW"] = "The War Within"
L["QUEST_TYPE_DAILY"] = "일일 퀘스트"
L["QUEST_TYPE_DAILY_DESC"] = "NPC의 일반 일일 퀘스트"
L["QUEST_TYPE_WORLD"] = "월드 퀘스트"
L["QUEST_TYPE_WORLD_DESC"] = "지역 전체 월드 퀘스트"
L["QUEST_TYPE_WEEKLY"] = "주간 퀘스트"
L["QUEST_TYPE_WEEKLY_DESC"] = "주간 반복 퀘스트"
L["QUEST_TYPE_ASSIGNMENTS"] = "과제"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "특별 과제 및 작업"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "신화+"
L["RAIDS_LABEL"] = "공격대"

-- PlanCardFactory
L["FACTION_LABEL"] = "세력:"
L["FRIENDSHIP_LABEL"] = "우정"
L["RENOWN_TYPE_LABEL"] = "명성"
L["ADD_BUTTON"] = "+ 추가"
L["ADDED_LABEL"] = "추가됨"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s / %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "보관함 보기에 아이템의 스택 수량 표시"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "캐릭터 탭에 주간 계획기 섹션 표시"
L["LOCK_MINIMAP_TOOLTIP"] = "미니맵 아이콘을 고정합니다(드래그 방지)"
L["AUTO_SCAN_TOOLTIP"] = "은행이나 가방을 열 때 자동으로 아이템을 스캔하고 캐시합니다"
L["LIVE_SYNC_TOOLTIP"] = "은행이 열려 있는 동안 실시간으로 아이템 캐시를 업데이트합니다"
L["SHOW_ILVL_TOOLTIP"] = "아이템 목록의 장비에 아이템 레벨 배지 표시"
L["SCROLL_SPEED_TOOLTIP"] = "스크롤 속도 배율 (1.0x = 단계당 28px)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "자동 스캔에서 전쟁부대 은행 탭 %d 무시"
L["IGNORE_SCAN_FORMAT"] = "자동 스캔에서 %s 무시"
L["BANK_LABEL"] = BANK or "은행"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "알림 활성화"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "모든 알림 팝업의 마스터 토글"
L["VAULT_REMINDER"] = "금고 알림"
L["VAULT_REMINDER_TOOLTIP"] = "받지 않은 주간 금고 보상이 있을 때 알림 표시"
L["LOOT_ALERTS"] = "전리품 알림"
L["LOOT_ALERTS_TOOLTIP"] = "새로운 탈것, 애완동물 또는 장난감이 가방에 들어올 때 알림 표시"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "블리자드 업적 알림 숨기기"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "WN 알림을 사용할 때 블리자드의 기본 업적 팝업 숨기기"
L["REPUTATION_GAINS"] = "평판 획득"
L["REPUTATION_GAINS_TOOLTIP"] = "세력 평판을 획득할 때 채팅 메시지 표시"
L["CURRENCY_GAINS"] = "화폐 획득"
L["CURRENCY_GAINS_TOOLTIP"] = "화폐를 획득할 때 채팅 메시지 표시"
L["DURATION_LABEL"] = "지속시간"
L["DAYS_LABEL"] = "일"
L["WEEKS_LABEL"] = "주"
L["EXTEND_DURATION"] = "기간 연장"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "초록색 프레임을 드래그하여 팝업 위치를 설정합니다. 우클릭하여 확인합니다."
L["POSITION_RESET_MSG"] = "팝업 위치가 기본값(상단 중앙)으로 초기화되었습니다"
L["POSITION_SAVED_MSG"] = "팝업 위치가 저장되었습니다!"
L["TEST_NOTIFICATION_TITLE"] = "테스트 알림"
L["TEST_NOTIFICATION_MSG"] = "위치 테스트"
L["NOTIFICATION_DEFAULT_TITLE"] = "알림"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "테마 및 외관"
L["COLOR_PURPLE"] = "보라색"
L["COLOR_PURPLE_DESC"] = "클래식 보라색 테마(기본값)"
L["COLOR_BLUE"] = "파란색"
L["COLOR_BLUE_DESC"] = "시원한 파란색 테마"
L["COLOR_GREEN"] = "초록색"
L["COLOR_GREEN_DESC"] = "자연 초록색 테마"
L["COLOR_RED"] = "빨간색"
L["COLOR_RED_DESC"] = "불타는 빨간색 테마"
L["COLOR_ORANGE"] = "주황색"
L["COLOR_ORANGE_DESC"] = "따뜻한 주황색 테마"
L["COLOR_CYAN"] = "청록색"
L["COLOR_CYAN_DESC"] = "밝은 청록색 테마"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "글꼴 패밀리"
L["FONT_FAMILY_TOOLTIP"] = "애드온 전체 UI에서 사용할 글꼴 선택"
L["FONT_SCALE"] = "글꼴 크기"
L["FONT_SCALE_TOOLTIP"] = "모든 UI 요소의 글꼴 크기 조정"
L["RESOLUTION_NORMALIZATION"] = "해상도 정규화"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "화면 해상도 및 UI 크기에 따라 글꼴 크기를 조정하여 다른 모니터에서도 텍스트가 동일한 물리적 크기를 유지하도록 합니다"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "고급"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "아이템 레벨 %s"
L["ITEM_NUMBER_FORMAT"] = "아이템 #%s"
L["CHARACTER_CURRENCIES"] = "캐릭터 화폐:"
L["YOU_MARKER"] = "(당신)"
L["WN_SEARCH"] = "WN 검색"
L["WARBAND_BANK_COLON"] = "전쟁부대 은행:"
L["AND_MORE_FORMAT"] = "... 및 %d개 더"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "탈것을 수집했습니다"
L["COLLECTED_PET_MSG"] = "전투 애완동물을 수집했습니다"
L["COLLECTED_TOY_MSG"] = "장난감을 수집했습니다"
L["COLLECTED_ILLUSION_MSG"] = "환영을 수집했습니다"
L["ACHIEVEMENT_COMPLETED_MSG"] = "업적 완료!"
L["EARNED_TITLE_MSG"] = "칭호를 획득했습니다"
L["COMPLETED_PLAN_MSG"] = "계획을 완료했습니다"
L["DAILY_QUEST_CAT"] = "일일 퀘스트"
L["WORLD_QUEST_CAT"] = "월드 퀘스트"
L["WEEKLY_QUEST_CAT"] = "주간 퀘스트"
L["SPECIAL_ASSIGNMENT_CAT"] = "특별 과제"
L["DELVE_CAT"] = "탐험"
L["DUNGEON_CAT"] = "던전"
L["RAID_CAT"] = "공격대"
L["WORLD_CAT"] = "월드"
L["ACTIVITY_CAT"] = "활동"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d 진행도"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d 진행도 완료"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "주간 금고 계획 - %s"
L["ALL_SLOTS_COMPLETE"] = "모든 슬롯 완료!"
L["QUEST_COMPLETED_SUFFIX"] = "완료"
L["WEEKLY_VAULT_READY"] = "주간 금고 준비 완료!"
L["UNCLAIMED_REWARDS"] = "받지 않은 보상이 있습니다"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "총 골드:"
L["CHARACTERS_COLON"] = "캐릭터:"
L["LEFT_CLICK_TOGGLE"] = "좌클릭: 창 표시/숨기기"
L["RIGHT_CLICK_PLANS"] = "우클릭: 계획 열기"
L["MINIMAP_SHOWN_MSG"] = "미니맵 버튼 표시됨"
L["MINIMAP_HIDDEN_MSG"] = "미니맵 버튼 숨김 (표시하려면 /wn minimap 사용)"
L["TOGGLE_WINDOW"] = "창 전환"
L["SCAN_BANK_MENU"] = "은행 스캔"
L["TRACKING_DISABLED_SCAN_MSG"] = "캐릭터 추적이 비활성화되어 있습니다. 은행을 스캔하려면 설정에서 추적을 활성화하세요."
L["SCAN_COMPLETE_MSG"] = "스캔 완료!"
L["BANK_NOT_OPEN_MSG"] = "은행이 열려 있지 않습니다"
L["OPTIONS_MENU"] = "옵션"
L["HIDE_MINIMAP_BUTTON"] = "미니맵 버튼 숨기기"
L["MENU_UNAVAILABLE_MSG"] = "우클릭 메뉴 사용 불가"
L["USE_COMMANDS_MSG"] = "/wn show, /wn scan, /wn config 명령어 사용"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "최대"
L["OPEN_AND_GUIDE"] = "열기 및 안내"
L["FROM_LABEL"] = "출처:"
L["AVAILABLE_LABEL"] = "사용 가능:"
L["ONLINE_LABEL"] = "(온라인)"
L["DATA_SOURCE_TITLE"] = "데이터 소스 정보"
L["DATA_SOURCE_USING"] = "이 탭은 다음을 사용 중입니다:"
L["DATA_SOURCE_MODERN"] = "최신 캐시 서비스(이벤트 기반)"
L["DATA_SOURCE_LEGACY"] = "레거시 직접 DB 접근"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "캐시 서비스로 마이그레이션 필요"
L["GLOBAL_DB_VERSION"] = "전역 DB 버전:"

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "캐릭터"
L["INFO_TAB_ITEMS"] = "아이템"
L["INFO_TAB_STORAGE"] = "보관함"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "평판"
L["INFO_TAB_CURRENCY"] = "화폐"
L["INFO_TAB_PLANS"] = "계획"
L["INFO_TAB_STATISTICS"] = "통계"
L["SPECIAL_THANKS"] = "특별 감사"
L["SUPPORTERS_TITLE"] = "후원자"
L["THANK_YOU_MSG"] = "Warband Nexus를 사용해 주셔서 감사합니다!"

-- =============================================
-- Changelog (What's New) - v2.0.0
-- =============================================
L["CHANGELOG_V200"] = "주요 업데이트:\n" ..
    "- 전리품 및 업적 알림: 탈것, 애완동물, 장난감, 환영, 칭호 및 업적을 획득할 때 알림을 받습니다\n" ..
    "- 주간 금고 알림: 받지 않은 금고 보상이 있을 때 토스트 알림\n" ..
    "- 계획 탭: 목표를 정리하고 다음에 수집할 항목을 추적합니다\n" ..
    "- 글꼴 시스템: 애드온 전체에서 사용자 정의 가능한 글꼴\n" ..
    "- 테마 색상: UI를 개인화하기 위한 사용자 정의 강조 색상\n" ..
    "- UI 개선: 더 깔끔한 레이아웃, 더 나은 구성, 검색 및 시각적 다듬기\n" ..
    "- 평판 및 화폐 획득 채팅 메시지: 진행도가 포함된 실시간 [WN-평판] 및 [WN-화폐] 메시지\n" ..
    "- 툴팁 시스템: 인터페이스 전체의 개선된 툴팁\n" ..
    "- 캐릭터 추적: 추적할 캐릭터 선택\n" ..
    "- 즐겨찾기 캐릭터: 목록에서 즐겨찾기 캐릭터에 별표 표시\n" ..
    "\n" ..
    "소규모 업데이트:\n" ..
    "- 은행 모듈 비활성화\n" ..
    "- 이전 데이터베이스 시스템 제거(개선 및 버그 수정)\n" ..
    "- WN 알림을 사용할 때 블리자드의 업적 팝업 숨기기 옵션\n" ..
    "- 전리품 및 업적 토스트 알림의 구성 가능한 위치\n" ..
    "\n" ..
    "Warband Nexus를 사용해 주셔서 감사합니다!\n" ..
    "\n" ..
    "버그를 신고하거나 피드백을 남기고 싶으시면 CurseForge - Warband Nexus에 댓글을 남겨주세요."

-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "작업 확인"
L["CONFIRM"] = "확인"
L["ENABLE_TRACKING_FORMAT"] = "|cffffcc00%s|r의 추적을 활성화하시겠습니까?"
L["DISABLE_TRACKING_FORMAT"] = "|cffffcc00%s|r의 추적을 비활성화하시겠습니까?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "계정 전체 평판 (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "캐릭터 기반 평판 (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "보상 대기 중"
L["REP_PARAGON_LABEL"] = "완벽"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "준비 중..."
L["REP_LOADING_INITIALIZING"] = "초기화 중..."
L["REP_LOADING_FETCHING"] = "평판 데이터 가져오는 중..."
L["REP_LOADING_PROCESSING"] = "%d개 세력 처리 중..."
L["REP_LOADING_PROCESSING_COUNT"] = "처리 중... (%d/%d)"
L["REP_LOADING_SAVING"] = "데이터베이스에 저장 중..."
L["REP_LOADING_COMPLETE"] = "완료!"

-- =============================================
-- Gold Transfer
-- =============================================
L["GOLD_TRANSFER"] = "골드 전송"
L["GOLD_LABEL"] = "골드"
L["SILVER_LABEL"] = "은화"
L["COPPER_LABEL"] = "동화"
L["DEPOSIT"] = "입금"
L["WITHDRAW"] = "출금"
L["DEPOSIT_TO_WARBAND"] = "전쟁부대 은행에 입금"
L["WITHDRAW_FROM_WARBAND"] = "전쟁부대 은행에서 출금"
L["YOUR_GOLD_FORMAT"] = "보유 골드: %s"
L["WARBAND_BANK_FORMAT"] = "전쟁부대 은행: %s"
L["NOT_ENOUGH_GOLD"] = "사용 가능한 골드가 부족합니다."
L["ENTER_AMOUNT"] = "금액을 입력하세요."
L["ONLY_WARBAND_GOLD"] = "전쟁부대 은행만 골드 전송을 지원합니다."

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "전투 중에는 창을 열 수 없습니다. 전투가 끝난 후 다시 시도하세요."
L["BANK_IS_ACTIVE"] = "은행 활성화됨"
L["ITEMS_CACHED_FORMAT"] = "%d개 아이템 캐시됨"
L["UP_TO_DATE"] = "최신 상태"
L["NEVER_SCANNED"] = "스캔한 적 없음"

-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "캐릭터"
L["TABLE_HEADER_LEVEL"] = "레벨"
L["TABLE_HEADER_GOLD"] = "골드"
L["TABLE_HEADER_LAST_SEEN"] = "마지막 접속"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "'%s'에 일치하는 아이템이 없습니다"
L["NO_ITEMS_MATCH_GENERIC"] = "검색어에 일치하는 아이템이 없습니다"
L["ITEMS_SCAN_HINT"] = "아이템은 자동으로 스캔됩니다. 아무것도 나타나지 않으면 /reload를 시도하세요."
L["ITEMS_WARBAND_BANK_HINT"] = "아이템을 스캔하려면 전쟁부대 은행을 엽니다(첫 방문 시 자동 스캔)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "다음 단계:"
L["CURRENCY_TRANSFER_STEP_1"] = "화폐 창에서 |cffffffff%s|r 찾기"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800우클릭|r"
L["CURRENCY_TRANSFER_STEP_3"] = "|cffffffff'전쟁부대로 전송'|r 선택"
L["CURRENCY_TRANSFER_STEP_4"] = "|cff00ff00%s|r 선택"
L["CURRENCY_TRANSFER_STEP_5"] = "금액 입력: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "화폐 창이 열렸습니다!"
L["CURRENCY_TRANSFER_SECURITY"] = "(Blizzard 보안으로 인해 자동 전송 불가)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "지역: "
L["ADDED"] = "추가됨"
L["WEEKLY_VAULT_TRACKER"] = "주간 금고 추적기"
L["DAILY_QUEST_TRACKER"] = "일일 퀘스트 추적기"
L["CUSTOM_PLAN_STATUS"] = "사용자 정의 계획 '%s' %s"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = "던전"
L["VAULT_SLOT_RAIDS"] = "공격대"
L["VAULT_SLOT_WORLD"] = "월드"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "속성"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_GAIN"] = "|cffff8800[WN-평판]|r |cff00ff00[%s]|r: |cff00ff00+%s|r 획득 |cff00ff00(%s / %s)|r"
L["CHAT_REP_GAIN_NOMAX"] = "|cffff8800[WN-평판]|r |cff00ff00[%s]|r: |cff00ff00+%s|r 획득"
L["CHAT_REP_STANDING"] = "|cffff8800[WN-평판]|r |cff00ff00[%s]|r: 현재 |cff%s%s|r"
L["CHAT_CUR_GAIN"] = "|cffcc66ff[WN-화폐]|r %s: |cff00ff00+%s|r 획득 |cff00ff00(%s / %s)|r"
L["CHAT_CUR_GAIN_NOMAX"] = "|cffcc66ff[WN-화폐]|r %s: |cff00ff00+%s|r 획득 |cff00ff00(%s)|r"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "계획 완료: "
L["WEEKLY_VAULT_PLAN_NAME"] = "주간 금고 - %s"
L["VAULT_PLANS_RESET"] = "주간 대금고 계획이 초기화되었습니다! (%d개 계획%s)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "캐릭터를 찾을 수 없음"
L["EMPTY_CHARACTERS_DESC"] = "캐릭터로 로그인하여 추적을 시작하세요.\n캐릭터 데이터는 매 로그인 시 자동으로 수집됩니다."
L["EMPTY_ITEMS_TITLE"] = "캐시된 아이템 없음"
L["EMPTY_ITEMS_DESC"] = "전쟁부대 은행 또는 개인 은행을 열어 아이템을 스캔하세요.\n아이템은 첫 방문 시 자동으로 캐시됩니다."
L["EMPTY_STORAGE_TITLE"] = "보관함 데이터 없음"
L["EMPTY_STORAGE_DESC"] = "아이템은 은행이나 가방을 열 때 스캔됩니다.\n은행을 방문하여 보관함 추적을 시작하세요."
L["EMPTY_PLANS_TITLE"] = "아직 계획 없음"
L["EMPTY_PLANS_DESC"] = "위에서 탈것, 애완동물, 장난감 또는 업적을 탐색하여\n수집 목표를 추가하고 진행도를 추적하세요."
L["EMPTY_REPUTATION_TITLE"] = "평판 데이터 없음"
L["EMPTY_REPUTATION_DESC"] = "평판은 로그인 시 자동으로 스캔됩니다.\n캐릭터로 로그인하여 진영 평판을 추적하세요."
L["EMPTY_CURRENCY_TITLE"] = "화폐 데이터 없음"
L["EMPTY_CURRENCY_DESC"] = "화폐는 모든 캐릭터에서 자동으로 추적됩니다.\n캐릭터로 로그인하여 화폐를 추적하세요."
L["EMPTY_PVE_TITLE"] = "PvE 데이터 없음"
L["EMPTY_PVE_DESC"] = "PvE 진행도는 캐릭터 로그인 시 추적됩니다.\n대금고, 신화+ 및 공격대 잠금이 여기에 표시됩니다."
L["EMPTY_STATISTICS_TITLE"] = "통계를 사용할 수 없음"
L["EMPTY_STATISTICS_DESC"] = "통계는 추적 중인 캐릭터에서 수집됩니다.\n캐릭터로 로그인하여 데이터 수집을 시작하세요."
L["NO_ADDITIONAL_INFO"] = "추가 정보 없음"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "이 캐릭터를 추적하시겠습니까?"
L["CLEANUP_NO_INACTIVE"] = "비활성 캐릭터를 찾을 수 없습니다 (90일 이상)"
L["CLEANUP_REMOVED_FORMAT"] = "비활성 캐릭터 %d개 제거됨"
L["TRACKING_ENABLED_MSG"] = "캐릭터 추적 활성화!"
L["TRACKING_DISABLED_MSG"] = "캐릭터 추적 비활성화!"
L["TRACKING_ENABLED"] = "추적 활성화됨"
L["TRACKING_DISABLED"] = "추적 비활성화됨 (읽기 전용 모드)"
L["STATUS_LABEL"] = "상태:"
L["ERROR_LABEL"] = "오류:"
L["ERROR_NAME_REALM_REQUIRED"] = "캐릭터 이름과 서버가 필요합니다"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s에 이미 활성 주간 계획이 있습니다"

-- Profiles (AceDB)
L["PROFILES"] = "프로필"
L["PROFILES_DESC"] = "애드온 프로필 관리"
