--[[
    Warband Nexus - Italian Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "itIT")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus caricato. Digita /wn o /warbandnexus per le opzioni."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Impostazioni Generali"
L["ENABLE_ADDON"] = "Abilita Addon"
L["MINIMAP_ICON"] = "Mostra icona minimappa"
L["DEBUG_MODE"] = "Modalità Debug"

-- Scanner Module
L["SCAN_STARTED"] = "Scansione della banca Warband..."
L["SCAN_COMPLETE"] = "Scansione completata. Trovati %d oggetti in %d slot."
L["SCAN_FAILED"] = "Scansione fallita: La banca Warband non è aperta."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = "Cerca oggetti..."
L["BTN_SCAN"] = "Scansiona Banca"
L["BTN_DEPOSIT"] = "Coda Deposito"
L["BTN_SORT"] = "Ordina Banca"
L["BTN_CLOSE"] = "Chiudi"
L["BTN_SETTINGS"] = "Impostazioni"


