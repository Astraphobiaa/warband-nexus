--[[
    Warband Nexus - French Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "frFR")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus chargé. Tapez /wn ou /warbandnexus pour les options."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Paramètres Généraux"
L["ENABLE_ADDON"] = "Activer l'addon"
L["MINIMAP_ICON"] = "Afficher l'icône de la minicarte"
L["DEBUG_MODE"] = "Mode débogage"

-- Scanner Module
L["SCAN_STARTED"] = "Analyse de la banque de confrérie..."
L["SCAN_COMPLETE"] = "Analyse terminée. %d objets trouvés dans %d emplacements."
L["SCAN_FAILED"] = "Échec de l'analyse: La banque de confrérie n'est pas ouverte."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = "Rechercher des objets..."
L["BTN_SCAN"] = "Analyser la Banque"
L["BTN_DEPOSIT"] = "File de Dépôt"
L["BTN_SORT"] = "Trier la Banque"
L["BTN_CLOSE"] = "Fermer"
L["BTN_SETTINGS"] = "Paramètres"



