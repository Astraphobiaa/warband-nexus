--[[
    Warband Nexus - Portuguese (Brazil) Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "ptBR")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus carregado. Digite /wn ou /warbandnexus para opções."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Configurações Gerais"
L["ENABLE_ADDON"] = "Ativar Addon"
L["MINIMAP_ICON"] = "Mostrar ícone do minimapa"
L["DEBUG_MODE"] = "Modo de depuração"

-- Scanner Module
L["SCAN_STARTED"] = "Escaneando banco de Clã de Guerra..."
L["SCAN_COMPLETE"] = "Escaneamento completo. Encontrados %d itens em %d espaços."
L["SCAN_FAILED"] = "Escaneamento falhou: O banco de Clã de Guerra não está aberto."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = "Pesquisar itens..."
L["BTN_SCAN"] = "Escanear Banco"
L["BTN_DEPOSIT"] = "Fila de Depósito"
L["BTN_SORT"] = "Ordenar Banco"
L["BTN_CLOSE"] = "Fechar"
L["BTN_SETTINGS"] = "Configurações"

