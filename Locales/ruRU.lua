--[[
    Warband Nexus - Russian Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "ruRU")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus загружен. Введите /wn или /warbandnexus для настроек."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Общие настройки"
L["ENABLE_ADDON"] = "Включить аддон"
L["MINIMAP_ICON"] = "Показать значок на миникарте"
L["DEBUG_MODE"] = "Режим отладки"

-- Scanner Module
L["SCAN_STARTED"] = "Сканирование банка воинского клана..."
L["SCAN_COMPLETE"] = "Сканирование завершено. Найдено %d предметов в %d ячейках."
L["SCAN_FAILED"] = "Ошибка сканирования: Банк воинского клана не открыт."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = "Поиск предметов..."
L["BTN_SCAN"] = "Сканировать банк"
L["BTN_DEPOSIT"] = "Очередь вклада"
L["BTN_SORT"] = "Сортировать банк"
L["BTN_CLOSE"] = "Закрыть"
L["BTN_SETTINGS"] = "Настройки"



