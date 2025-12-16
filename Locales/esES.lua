--[[
    Warband Nexus - Spanish (Spain) Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "esES")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus cargado. Escribe /wn o /warbandnexus para opciones."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Configuración General"
L["ENABLE_ADDON"] = "Activar Addon"
L["MINIMAP_ICON"] = "Mostrar icono del minimapa"
L["DEBUG_MODE"] = "Modo de depuración"

-- Scanner Module
L["SCAN_STARTED"] = "Escaneando banco de banda de guerra..."
L["SCAN_COMPLETE"] = "Escaneo completado. Se encontraron %d objetos en %d espacios."
L["SCAN_FAILED"] = "Escaneo fallido: El banco de banda de guerra no está abierto."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = "Buscar objetos..."
L["BTN_SCAN"] = "Escanear Banco"
L["BTN_DEPOSIT"] = "Cola de Depósito"
L["BTN_SORT"] = "Ordenar Banco"
L["BTN_CLOSE"] = "Cerrar"
L["BTN_SETTINGS"] = "Configuración"


