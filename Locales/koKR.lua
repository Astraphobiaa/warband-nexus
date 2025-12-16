--[[
    Warband Nexus - Korean Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "koKR")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus가 로드되었습니다. 옵션을 보려면 /wn 또는 /warbandnexus를 입력하세요."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "일반 설정"
L["ENABLE_ADDON"] = "애드온 활성화"
L["MINIMAP_ICON"] = "미니맵 아이콘 표시"
L["DEBUG_MODE"] = "디버그 모드"

-- Scanner Module
L["SCAN_STARTED"] = "전쟁부대 은행을 스캔하는 중..."
L["SCAN_COMPLETE"] = "스캔 완료. %d개의 슬롯에서 %d개의 아이템을 찾았습니다."
L["SCAN_FAILED"] = "스캔 실패: 전쟁부대 은행이 열려 있지 않습니다."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = "아이템 검색..."
L["BTN_SCAN"] = "은행 스캔"
L["BTN_DEPOSIT"] = "입금 대기열"
L["BTN_SORT"] = "은행 정렬"
L["BTN_CLOSE"] = "닫기"
L["BTN_SETTINGS"] = "설정"

