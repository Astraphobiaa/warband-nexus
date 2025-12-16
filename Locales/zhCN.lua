--[[
    Warband Nexus - Simplified Chinese Localization
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "zhCN")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus 已加载。输入 /wn 或 /warbandnexus 查看选项。"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "常规设置"
L["ENABLE_ADDON"] = "启用插件"
L["MINIMAP_ICON"] = "显示小地图图标"
L["DEBUG_MODE"] = "调试模式"

-- Scanner Module
L["SCAN_STARTED"] = "正在扫描战团银行..."
L["SCAN_COMPLETE"] = "扫描完成。在 %d 个格子中找到 %d 个物品。"
L["SCAN_FAILED"] = "扫描失败：战团银行未打开。"

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = "搜索物品..."
L["BTN_SCAN"] = "扫描银行"
L["BTN_DEPOSIT"] = "存放队列"
L["BTN_SORT"] = "整理银行"
L["BTN_CLOSE"] = "关闭"
L["BTN_SETTINGS"] = "设置"



