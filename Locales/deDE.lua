--[[
    Warband Nexus - German Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "deDE")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus geladen. Tippe /wn oder /warbandnexus für Optionen."
L["VERSION"] = GAME_VERSION_LABEL or "Version"

-- Slash Commands
L["SLASH_HELP"] = "Verfügbare Befehle:"
L["SLASH_OPTIONS"] = "Optionen öffnen"
L["SLASH_SCAN"] = "Kriegsmeute-Bank scannen"
L["SLASH_SHOW"] = "Hauptfenster ein-/ausblenden"
L["SLASH_DEPOSIT"] = "Einzahlungswarteschlange öffnen"
L["SLASH_SEARCH"] = "Nach einem Gegenstand suchen"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Allgemeine Einstellungen"
L["GENERAL_SETTINGS_DESC"] = "Allgemeines Addon-Verhalten konfigurieren"
L["ENABLE_ADDON"] = "Addon aktivieren"
L["ENABLE_ADDON_DESC"] = "Warband Nexus aktivieren oder deaktivieren"
L["MINIMAP_ICON"] = "Minimap-Symbol anzeigen"
L["MINIMAP_ICON_DESC"] = "Minimap-Schaltfläche ein- oder ausblenden"
L["DEBUG_MODE"] = "Debug-Modus"
L["DEBUG_MODE_DESC"] = "Debug-Nachrichten im Chat aktivieren"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "Scan-Einstellungen"
L["SCANNING_SETTINGS_DESC"] = "Scan-Verhalten der Bank konfigurieren"
L["AUTO_SCAN"] = "Automatisch scannen beim Öffnen"
L["AUTO_SCAN_DESC"] = "Kriegsmeute-Bank automatisch scannen beim Öffnen"
L["SCAN_DELAY"] = "Scan-Verzögerung"
L["SCAN_DELAY_DESC"] = "Verzögerung zwischen Scan-Vorgängen (in Sekunden)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "Einzahlungseinstellungen"
L["DEPOSIT_SETTINGS_DESC"] = "Gegenstandseinzahlung konfigurieren"
L["GOLD_RESERVE"] = "Goldreserve"
L["GOLD_RESERVE_DESC"] = "Mindestgold im persönlichen Inventar behalten (in Gold)"
L["AUTO_DEPOSIT_REAGENTS"] = "Reagenzien automatisch einzahlen"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "Reagenzien in die Warteschlange stellen beim Öffnen der Bank"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Anzeigeeinstellungen"
L["DISPLAY_SETTINGS_DESC"] = "Visuelle Darstellung konfigurieren"
L["SHOW_ITEM_LEVEL"] = "Gegenstandsstufe anzeigen"
L["SHOW_ITEM_LEVEL_DESC"] = "Gegenstandsstufe auf Ausrüstung anzeigen"
L["SHOW_ITEM_COUNT"] = "Gegenstandsanzahl anzeigen"
L["SHOW_ITEM_COUNT_DESC"] = "Stapelanzahl auf Gegenständen anzeigen"
L["HIGHLIGHT_QUALITY"] = "Nach Qualität hervorheben"
L["HIGHLIGHT_QUALITY_DESC"] = "Farbige Rahmen basierend auf Gegenstandsqualität"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "Tab-Einstellungen"
L["TAB_SETTINGS_DESC"] = "Kriegsmeute-Bank-Tab-Verhalten konfigurieren"
L["IGNORED_TABS"] = "Ignorierte Tabs"
L["IGNORED_TABS_DESC"] = "Tabs vom Scannen und Operationen ausschließen"
L["TAB_1"] = "Kriegsmeute-Tab 1"
L["TAB_2"] = "Kriegsmeute-Tab 2"
L["TAB_3"] = "Kriegsmeute-Tab 3"
L["TAB_4"] = "Kriegsmeute-Tab 4"
L["TAB_5"] = "Kriegsmeute-Tab 5"

-- Scanner Module
L["SCAN_STARTED"] = "Scanne Kriegsmeute-Bank..."
L["SCAN_COMPLETE"] = "Scan abgeschlossen. %d Gegenstände in %d Plätzen gefunden."
L["SCAN_FAILED"] = "Scan fehlgeschlagen: Kriegsmeute-Bank ist nicht geöffnet."
L["SCAN_TAB"] = "Scanne Tab %d..."
L["CACHE_CLEARED"] = "Gegenstands-Cache gelöscht."
L["CACHE_UPDATED"] = "Gegenstands-Cache aktualisiert."

-- Banker Module
L["BANK_NOT_OPEN"] = "Kriegsmeute-Bank ist nicht geöffnet."
L["DEPOSIT_STARTED"] = "Einzahlungsvorgang gestartet..."
L["DEPOSIT_COMPLETE"] = "Einzahlung abgeschlossen. %d Gegenstände übertragen."
L["DEPOSIT_CANCELLED"] = "Einzahlung abgebrochen."
L["DEPOSIT_QUEUE_EMPTY"] = "Einzahlungswarteschlange ist leer."
L["DEPOSIT_QUEUE_CLEARED"] = "Einzahlungswarteschlange gelöscht."
L["ITEM_QUEUED"] = "%s zur Einzahlung vorgemerkt."
L["ITEM_REMOVED"] = "%s aus der Warteschlange entfernt."
L["GOLD_DEPOSITED"] = "%s Gold in die Kriegsmeute-Bank eingezahlt."
L["INSUFFICIENT_GOLD"] = "Nicht genug Gold für die Einzahlung."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "Ungültiger Betrag."
L["WITHDRAW_BANK_NOT_OPEN"] = "Bank muss geöffnet sein zum Abheben!"
L["WITHDRAW_IN_COMBAT"] = "Kann im Kampf nicht abheben."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "Nicht genug Gold in der Kriegsmeute-Bank."
L["WITHDRAWN_LABEL"] = "Abgehoben:"
L["WITHDRAW_API_UNAVAILABLE"] = "Abhebe-API nicht verfügbar."
L["SORT_IN_COMBAT"] = "Kann im Kampf nicht sortieren."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global
L["SEARCH_CATEGORY_FORMAT"] = "%s durchsuchen..."
L["BTN_SCAN"] = "Bank scannen"
L["BTN_DEPOSIT"] = "Einzahlungswarteschlange"
L["BTN_SORT"] = "Bank sortieren"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "Warteschlange leeren"
L["BTN_DEPOSIT_ALL"] = "Alles einzahlen"
L["BTN_DEPOSIT_GOLD"] = "Gold einzahlen"
L["ENABLE"] = ENABLE or "Aktivieren" -- Blizzard Global
L["ENABLE_MODULE"] = "Modul aktivieren"

-- Main Tabs
L["TAB_CHARACTERS"] = CHARACTER or "Charaktere" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "Gegenstände" -- Blizzard Global
L["TAB_STORAGE"] = "Lager"
L["TAB_PLANS"] = "Pläne"
L["TAB_REPUTATION"] = REPUTATION or "Ruf" -- Blizzard Global
L["TAB_REPUTATIONS"] = "Rufe"
L["TAB_CURRENCY"] = CURRENCY or "Währung" -- Blizzard Global
L["TAB_CURRENCIES"] = "Währungen"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "Statistiken" -- Blizzard Global

-- Item Categories (Blizzard Globals)
L["CATEGORY_ALL"] = ALL or "Alle Gegenstände" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Ausrüstung"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Verbrauchsgüter"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagenzien"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Handelswaren"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Questgegenstände"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Verschiedenes"

-- Quality Filters (Blizzard Globals - automatically localized)
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC

-- Characters Tab
L["HEADER_FAVORITES"] = FAVORITES or "Favoriten" -- Blizzard Global
L["HEADER_CHARACTERS"] = CHARACTER or "Charaktere"
L["HEADER_CURRENT_CHARACTER"] = "AKTUELLER CHARAKTER"
L["HEADER_WARBAND_GOLD"] = "KRIEGSMEUTE-GOLD"
L["HEADER_TOTAL_GOLD"] = "GOLD GESAMT"
L["HEADER_REALM_GOLD"] = "REALM-GOLD"
L["HEADER_REALM_TOTAL"] = "REALM GESAMT"
L["CHARACTER_LAST_SEEN_FORMAT"] = "Zuletzt gesehen: %s"
L["CHARACTER_GOLD_FORMAT"] = "Gold: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "Kombiniertes Gold aller Charaktere auf diesem Realm"

-- Items Tab
L["ITEMS_HEADER"] = "Bank-Gegenstände"
L["ITEMS_HEADER_DESC"] = "Durchsuche und verwalte deine Kriegsmeute- und persönliche Bank"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " Gegenstände..."
L["ITEMS_WARBAND_BANK"] = "Kriegsmeute-Bank"
L["ITEMS_PLAYER_BANK"] = BANK or "Persönliche Bank"
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Gildenbank"
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Ausrüstung"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Verbrauchsgüter"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagenzien"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Handelswaren"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quest"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Verschiedenes"
L["GROUP_CONTAINER"] = "Behälter"

-- Storage Tab
L["STORAGE_HEADER"] = "Lager-Browser"
L["STORAGE_HEADER_DESC"] = "Alle Gegenstände nach Typ organisiert durchsuchen"
L["STORAGE_WARBAND_BANK"] = "Kriegsmeute-Bank"
L["STORAGE_PERSONAL_BANKS"] = "Persönliche Banken"
L["STORAGE_TOTAL_SLOTS"] = "Plätze gesamt"
L["STORAGE_FREE_SLOTS"] = "Freie Plätze"
L["STORAGE_BAG_HEADER"] = "Kriegsmeute-Taschen"
L["STORAGE_PERSONAL_HEADER"] = "Persönliche Bank"

-- Plans Tab
L["PLANS_MY_PLANS"] = "Meine Pläne"
L["PLANS_COLLECTIONS"] = "Sammlungspläne"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "Eigenen Plan hinzufügen"
L["PLANS_NO_RESULTS"] = "Keine Ergebnisse gefunden."
L["PLANS_ALL_COLLECTED"] = "Alle Gegenstände gesammelt!"
L["PLANS_RECIPE_HELP"] = "Rechtsklick auf Rezepte im Inventar, um sie hier hinzuzufügen."
L["COLLECTION_PLANS"] = "Sammlungspläne"
L["SEARCH_PLANS"] = "Pläne suchen..."
L["COMPLETED_PLANS"] = "Abgeschlossene Pläne"
L["SHOW_COMPLETED"] = "Abgeschlossene anzeigen"
L["SHOW_PLANNED"] = "Geplante anzeigen"
L["NO_PLANNED_ITEMS"] = "Noch keine geplanten %ss"

-- Plans Categories (Blizzard Globals)
L["CATEGORY_MY_PLANS"] = "Meine Pläne"
L["CATEGORY_DAILY_TASKS"] = "Tägliche Aufgaben"
L["CATEGORY_MOUNTS"] = MOUNTS or "Reittiere"
L["CATEGORY_PETS"] = PETS or "Haustiere"
L["CATEGORY_TOYS"] = TOY_BOX or "Spielzeug"
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmogrifikation"
L["CATEGORY_ILLUSIONS"] = "Illusionen"
L["CATEGORY_TITLES"] = TITLES or "Titel"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Erfolge"

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " Ruf..."
L["REP_HEADER_WARBAND"] = "Kriegsmeute-Ruf"
L["REP_HEADER_CHARACTER"] = "Charakter-Ruf"
L["REP_STANDING_FORMAT"] = "Rang: %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " Währung..."
L["CURRENCY_HEADER_WARBAND"] = "Kriegsmeute-übertragbar"
L["CURRENCY_HEADER_CHARACTER"] = "Charaktergebunden"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "Schlachtzüge"
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Dungeons"
L["PVE_HEADER_DELVES"] = "Tiefen"
L["PVE_HEADER_WORLD_BOSS"] = "Weltbosse"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "Statistiken"
L["STATS_TOTAL_ITEMS"] = "Gegenstände gesamt"
L["STATS_TOTAL_SLOTS"] = "Plätze gesamt"
L["STATS_FREE_SLOTS"] = "Freie Plätze"
L["STATS_USED_SLOTS"] = "Belegte Plätze"
L["STATS_TOTAL_VALUE"] = "Gesamtwert"
L["COLLECTED"] = "Gesammelt"
L["TOTAL"] = "Gesamt"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Charakter"
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Ort"
L["TOOLTIP_WARBAND_BANK"] = "Kriegsmeute-Bank"
L["TOOLTIP_TAB"] = "Tab"
L["TOOLTIP_SLOT"] = "Platz"
L["TOOLTIP_COUNT"] = "Anzahl"
L["CHARACTER_INVENTORY"] = "Inventar"
L["CHARACTER_BANK"] = "Bank"

-- Try Counter
L["TRY_COUNT"] = "Versuchszähler"
L["SET_TRY_COUNT"] = "Versuche festlegen"
L["TRIES"] = "Versuche"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "Reset-Zyklus festlegen"
L["DAILY_RESET"] = "Täglicher Reset"
L["WEEKLY_RESET"] = "Wöchentlicher Reset"
L["NONE_DISABLE"] = "Keiner (Deaktivieren)"
L["RESET_CYCLE_LABEL"] = "Reset-Zyklus:"
L["RESET_NONE"] = "Keiner"
L["DOUBLECLICK_RESET"] = "Doppelklick zum Zurücksetzen der Position"

-- Error Messages
L["ERROR_GENERIC"] = "Ein Fehler ist aufgetreten."
L["ERROR_API_UNAVAILABLE"] = "Erforderliche API ist nicht verfügbar."
L["ERROR_BANK_CLOSED"] = "Aktion nicht möglich: Bank ist geschlossen."
L["ERROR_INVALID_ITEM"] = "Ungültiger Gegenstand angegeben."
L["ERROR_PROTECTED_FUNCTION"] = "Geschützte Funktion kann im Kampf nicht aufgerufen werden."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "%d Gegenstände in die Kriegsmeute-Bank einzahlen?"
L["CONFIRM_CLEAR_QUEUE"] = "Alle Gegenstände aus der Warteschlange entfernen?"
L["CONFIRM_DEPOSIT_GOLD"] = "%s Gold in die Kriegsmeute-Bank einzahlen?"

-- Update Notification
L["WHATS_NEW"] = "Neuigkeiten"
L["GOT_IT"] = "Verstanden!"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "ERFOLGSPUNKTE"
L["MOUNTS_COLLECTED"] = "REITTIERE GESAMMELT"
L["BATTLE_PETS"] = "KAMPFHAUSTIERE"
L["ACCOUNT_WIDE"] = "Accountweit"
L["STORAGE_OVERVIEW"] = "Lagerübersicht"
L["WARBAND_SLOTS"] = "KRIEGSMEUTE-PLÄTZE"
L["PERSONAL_SLOTS"] = "PERSÖNLICHE PLÄTZE"
L["TOTAL_FREE"] = "GESAMT FREI"
L["TOTAL_ITEMS"] = "GEGENSTÄNDE GESAMT"

-- Plans Tracker
L["WEEKLY_VAULT"] = "Wöchentliche Schatzkammer"
L["CUSTOM"] = "Eigene"
L["NO_PLANS_IN_CATEGORY"] = "Keine Pläne in dieser Kategorie.\nFüge Pläne im Pläne-Tab hinzu."
L["SOURCE_LABEL"] = "Quelle:"
L["ZONE_LABEL"] = "Zone:"
L["VENDOR_LABEL"] = "Händler:"
L["DROP_LABEL"] = "Beute:"
L["REQUIREMENT_LABEL"] = "Voraussetzung:"
L["RIGHT_CLICK_REMOVE"] = "Rechtsklick zum Entfernen"
L["TRACKED"] = "Verfolgt"
L["TRACK"] = "Verfolgen"
L["TRACK_BLIZZARD_OBJECTIVES"] = "In Blizzard-Zielen verfolgen (max. 10)"
L["UNKNOWN"] = "Unbekannt"
L["NO_REQUIREMENTS"] = "Keine Voraussetzungen (sofort abgeschlossen)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "Keine geplante Aktivität"
L["CLICK_TO_ADD_GOALS"] = "Klicke oben auf Reittiere, Haustiere oder Spielzeug, um Ziele hinzuzufügen!"
L["UNKNOWN_QUEST"] = "Unbekannte Quest"
L["ALL_QUESTS_COMPLETE"] = "Alle Quests abgeschlossen!"
L["CURRENT_PROGRESS"] = "Aktueller Fortschritt"
L["SELECT_CONTENT"] = "Inhalt auswählen:"
L["QUEST_TYPES"] = "Questtypen:"
L["WORK_IN_PROGRESS"] = "In Arbeit"
L["RECIPE_BROWSER"] = "Rezept-Browser"
L["NO_RESULTS_FOUND"] = "Keine Ergebnisse gefunden."
L["TRY_ADJUSTING_SEARCH"] = "Versuche, deine Suche oder Filter anzupassen."
L["NO_COLLECTED_YET"] = "Noch keine %ss gesammelt"
L["START_COLLECTING"] = "Beginne zu sammeln, um sie hier zu sehen!"
L["ALL_COLLECTED_CATEGORY"] = "Alle %ss gesammelt!"
L["COLLECTED_EVERYTHING"] = "Du hast alles in dieser Kategorie gesammelt!"
L["PROGRESS_LABEL"] = "Fortschritt:"
L["REQUIREMENTS_LABEL"] = "Voraussetzungen:"
L["INFORMATION_LABEL"] = "Information:"
L["DESCRIPTION_LABEL"] = "Beschreibung:"
L["REWARD_LABEL"] = "Belohnung:"
L["DETAILS_LABEL"] = "Details:"
L["COST_LABEL"] = "Kosten:"
L["LOCATION_LABEL"] = "Ort:"
L["TITLE_LABEL"] = "Titel:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "Du hast bereits alle Erfolge in dieser Kategorie abgeschlossen!"
L["DAILY_PLAN_EXISTS"] = "Täglicher Plan existiert bereits"
L["WEEKLY_PLAN_EXISTS"] = "Wöchentlicher Plan existiert bereits"

-- PvE Tab
L["GREAT_VAULT"] = "Große Schatzkammer"
L["LOADING_PVE"] = "Lade PvE-Daten..."
L["PVE_APIS_LOADING"] = "Bitte warten, WoW-APIs werden initialisiert..."
L["NO_VAULT_DATA"] = "Keine Schatzkammer-Daten"
L["NO_DATA"] = "Keine Daten"
L["KEYSTONE"] = "Schlüsselstein"
L["NO_KEY"] = "Kein Schlüssel"
L["AFFIXES"] = "Affixe"
L["NO_AFFIXES"] = "Keine Affixe"
L["VAULT_BEST_KEY"] = "Bester Schlüssel:"
L["VAULT_SCORE"] = "Wertung:"

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "Deine Charaktere"
L["CHARACTERS_TRACKED_FORMAT"] = "%d Charaktere verfolgt"
L["NO_CHARACTER_DATA"] = "Keine Charakterdaten verfügbar"
L["NO_FAVORITES"] = "Noch keine Lieblingscharaktere. Klicke auf das Sternsymbol, um einen Charakter zu favorisieren."
L["ALL_FAVORITED"] = "Alle Charaktere sind favorisiert!"
L["UNTRACKED_CHARACTERS"] = "Nicht verfolgte Charaktere"
L["ILVL_SHORT"] = "iLvl"
L["ONLINE"] = "Online"
L["TIME_LESS_THAN_MINUTE"] = "< 1 Min."
L["TIME_MINUTES_FORMAT"] = "vor %d Min."
L["TIME_HOURS_FORMAT"] = "vor %d Std."
L["TIME_DAYS_FORMAT"] = "vor %d T."
L["REMOVE_FROM_FAVORITES"] = "Aus Favoriten entfernen"
L["ADD_TO_FAVORITES"] = "Zu Favoriten hinzufügen"
L["FAVORITES_TOOLTIP"] = "Lieblingscharaktere erscheinen oben in der Liste"
L["CLICK_TO_TOGGLE"] = "Klicken zum Umschalten"
L["UNKNOWN_PROFESSION"] = "Unbekannter Beruf"
L["SKILL_LABEL"] = "Fertigkeit:"
L["OVERALL_SKILL"] = "Gesamtfertigkeit:"
L["BONUS_SKILL"] = "Bonusfertigkeit:"
L["KNOWLEDGE_LABEL"] = "Wissen:"
L["SPEC_LABEL"] = "Spez."
L["POINTS_SHORT"] = "Pkt."
L["RECIPES_KNOWN"] = "Bekannte Rezepte:"
L["OPEN_PROFESSION_HINT"] = "Berufsfenster öffnen"
L["FOR_DETAILED_INFO"] = "für detaillierte Informationen"
L["CHARACTER_IS_TRACKED"] = "Dieser Charakter wird verfolgt."
L["TRACKING_ACTIVE_DESC"] = "Datenerfassung und Aktualisierungen sind aktiv."
L["CLICK_DISABLE_TRACKING"] = "Klicken, um Verfolgung zu deaktivieren."
L["MUST_LOGIN_TO_CHANGE"] = "Du musst dich mit diesem Charakter einloggen, um die Verfolgung zu ändern."
L["TRACKING_ENABLED"] = "Verfolgung aktiviert"
L["CLICK_ENABLE_TRACKING"] = "Klicken, um Verfolgung für diesen Charakter zu aktivieren."
L["TRACKING_WILL_BEGIN"] = "Datenerfassung beginnt sofort."
L["CHARACTER_NOT_TRACKED"] = "Dieser Charakter wird nicht verfolgt."
L["MUST_LOGIN_TO_ENABLE"] = "Du musst dich mit diesem Charakter einloggen, um die Verfolgung zu aktivieren."
L["ENABLE_TRACKING"] = "Verfolgung aktivieren"
L["DELETE_CHARACTER_TITLE"] = "Charakter löschen?"
L["THIS_CHARACTER"] = "diesen Charakter"
L["DELETE_CHARACTER"] = "Charakter löschen"
L["REMOVE_FROM_TRACKING_FORMAT"] = "%s aus der Verfolgung entfernen"
L["CLICK_TO_DELETE"] = "Klicken zum Löschen"
L["CONFIRM_DELETE"] = "Bist du sicher, dass du |cff00ccff%s|r löschen möchtest?"
L["CANNOT_UNDO"] = "Diese Aktion kann nicht rückgängig gemacht werden!"
L["DELETE"] = DELETE or "Löschen"
L["CANCEL"] = CANCEL or "Abbrechen"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "Persönliche Gegenstände"
L["ITEMS_SUBTITLE"] = "Durchsuche deine Kriegsmeute-Bank und persönliche Gegenstände (Bank + Inventar)"
L["ITEMS_DISABLED_TITLE"] = "Kriegsmeute-Bank Gegenstände"
L["ITEMS_LOADING"] = "Lade Inventardaten"
L["GUILD_BANK_REQUIRED"] = "Du musst in einer Gilde sein, um auf die Gildenbank zuzugreifen."
L["ITEMS_SEARCH"] = "Gegenstände suchen..."
L["NEVER"] = "Nie"
L["ITEM_FALLBACK_FORMAT"] = "Gegenstand %s"
L["TAB_FORMAT"] = "Tab %d"
L["BAG_FORMAT"] = "Tasche %d"
L["BANK_BAG_FORMAT"] = "Banktasche %d"
L["ITEM_ID_LABEL"] = "Gegenstands-ID:"
L["QUALITY_TOOLTIP_LABEL"] = "Qualität:"
L["STACK_LABEL"] = "Stapel:"
L["RIGHT_CLICK_MOVE"] = "In Tasche verschieben"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Stapel teilen"
L["LEFT_CLICK_PICKUP"] = "Aufnehmen"
L["ITEMS_BANK_NOT_OPEN"] = "Bank nicht geöffnet"
L["SHIFT_LEFT_CLICK_LINK"] = "Im Chat verlinken"
L["ITEM_DEFAULT_TOOLTIP"] = "Gegenstand"
L["ITEMS_STATS_ITEMS"] = "%s Gegenstände"
L["ITEMS_STATS_SLOTS"] = "%s/%s Plätze"
L["ITEMS_STATS_LAST"] = "Zuletzt: %s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "Charakter-Lager"
L["STORAGE_SEARCH"] = "Lager durchsuchen..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "PvE-Fortschritt"
L["PVE_SUBTITLE"] = "Große Schatzkammer, Schlachtzug-Sperrungen & Mythic+ deiner Kriegsmeute"
L["PVE_NO_CHARACTER"] = "Keine Charakterdaten verfügbar"
L["LV_FORMAT"] = "Lv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = RAID or "Raid"
L["VAULT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon"
L["VAULT_WORLD"] = "Welt"
L["VAULT_SLOT_FORMAT"] = "%s Platz %d"
L["VAULT_NO_PROGRESS"] = "Noch kein Fortschritt"
L["VAULT_UNLOCK_FORMAT"] = "Schließe %s Aktivitäten ab zum Freischalten"
L["VAULT_NEXT_TIER_FORMAT"] = "Nächste Stufe: %d iLvl bei Abschluss von %s"
L["VAULT_REMAINING_FORMAT"] = "Verbleibend: %s Aktivitäten"
L["VAULT_PROGRESS_FORMAT"] = "Fortschritt: %s / %s"
L["OVERALL_SCORE_LABEL"] = "Gesamtwertung:"
L["BEST_KEY_FORMAT"] = "Bester Schlüssel: +%d"
L["SCORE_FORMAT"] = "Wertung: %s"
L["NOT_COMPLETED_SEASON"] = "Diese Saison nicht abgeschlossen"
L["CURRENT_MAX_FORMAT"] = "Aktuell: %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "Fortschritt: %.1f%%"
L["NO_CAP_LIMIT"] = "Kein Limit"

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "Rufübersicht"
L["REP_SUBTITLE"] = "Verfolge Fraktionen und Ruhm deiner Kriegsmeute"
L["REP_DISABLED_TITLE"] = "Ruf-Verfolgung"
L["REP_LOADING_TITLE"] = "Lade Rufdaten"
L["REP_SEARCH"] = "Rufe durchsuchen..."
L["REP_PARAGON_TITLE"] = "Paragon-Ruf"
L["REP_REWARD_AVAILABLE"] = "Belohnung verfügbar!"
L["REP_CONTINUE_EARNING"] = "Sammle weiter Ruf für Belohnungen"
L["REP_CYCLES_FORMAT"] = "Zyklen: %d"
L["REP_PROGRESS_HEADER"] = "Fortschritt: %d/%d"
L["REP_PARAGON_PROGRESS"] = "Paragon-Fortschritt:"
L["REP_PROGRESS_COLON"] = "Fortschritt:"
L["REP_CYCLES_COLON"] = "Zyklen:"
L["REP_CHARACTER_PROGRESS"] = "Charakter-Fortschritt:"
L["REP_RENOWN_FORMAT"] = "Ruhm %d"
L["REP_PARAGON_FORMAT"] = "Paragon (%s)"
L["REP_UNKNOWN_FACTION"] = "Unbekannte Fraktion"
L["REP_API_UNAVAILABLE_TITLE"] = "Ruf-API nicht verfügbar"
L["REP_API_UNAVAILABLE_DESC"] = "Die C_Reputation API ist auf diesem Server nicht verfügbar. Dieses Feature erfordert WoW 11.0+ (The War Within)."
L["REP_FOOTER_TITLE"] = "Ruf-Verfolgung"
L["REP_FOOTER_DESC"] = "Rufe werden automatisch beim Login und bei Änderungen gescannt. Verwende das Ruf-Fenster im Spiel für detaillierte Informationen und Belohnungen."
L["REP_CLEARING_CACHE"] = "Cache wird geleert und neu geladen..."
L["REP_LOADING_DATA"] = "Lade Rufdaten..."
L["REP_MAX"] = "Max."
L["REP_TIER_FORMAT"] = "Stufe %d"
L["ACCOUNT_WIDE_LABEL"] = "Accountweit"
L["NO_RESULTS"] = "Keine Ergebnisse"
L["NO_REP_MATCH"] = "Keine Rufe stimmen mit '%s' überein"
L["NO_REP_DATA"] = "Keine Rufdaten verfügbar"
L["REP_SCAN_TIP"] = "Rufe werden automatisch gescannt. Versuche /reload, wenn nichts erscheint."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "Accountweite Rufe (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "Keine accountweiten Rufe"
L["NO_CHARACTER_REPS"] = "Keine charakterbasierten Rufe"

-- =============================================
-- Currency Tab
-- =============================================
L["GOLD_LABEL"] = "Gold"
L["CURRENCY_TITLE"] = "Währungs-Tracker"
L["CURRENCY_SUBTITLE"] = "Verfolge alle Währungen deiner Charaktere"
L["CURRENCY_DISABLED_TITLE"] = "Währungsverfolgung"
L["CURRENCY_LOADING_TITLE"] = "Lade Währungsdaten"
L["CURRENCY_SEARCH"] = "Währungen suchen..."
L["CURRENCY_HIDE_EMPTY"] = "Leere ausblenden"
L["CURRENCY_SHOW_EMPTY"] = "Leere anzeigen"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "Alle Kriegsmeute-übertragbar"
L["CURRENCY_CHARACTER_SPECIFIC"] = "Charakterspezifische Währungen"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "Währungsübertragungsbeschränkung"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "Die Blizzard-API unterstützt keine automatischen Währungsübertragungen. Bitte verwende das Währungsfenster im Spiel, um Kriegsmeute-Währungen manuell zu übertragen."
L["CURRENCY_UNKNOWN"] = "Unbekannte Währung"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "Entferne alle abgeschlossenen Pläne aus deiner Meine-Pläne-Liste. Dies löscht alle abgeschlossenen eigenen Pläne und entfernt gesammelte Reittiere/Haustiere/Spielzeuge. Diese Aktion kann nicht rückgängig gemacht werden!"
L["RECIPE_BROWSER_DESC"] = "Öffne dein Berufsfenster im Spiel, um Rezepte zu durchsuchen.\nDas Addon scannt verfügbare Rezepte, wenn das Fenster geöffnet ist."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "Quelle: [Erfolg %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s hat bereits einen aktiven Wochenplan für die Schatzkammer. Du findest ihn in der Kategorie 'Meine Pläne'."
L["DAILY_PLAN_EXISTS_DESC"] = "%s hat bereits einen aktiven täglichen Questplan. Du findest ihn in der Kategorie 'Tägliche Aufgaben'."
L["TRANSMOG_WIP_DESC"] = "Transmogrifikations-Sammlung wird derzeit entwickelt.\n\nDieses Feature wird in einem zukünftigen Update mit verbesserter\nLeistung und besserer Integration mit Kriegsmeute-Systemen verfügbar sein."
L["WEEKLY_VAULT_CARD"] = "Wöchentliche Schatzkammer-Karte"
L["WEEKLY_VAULT_COMPLETE"] = "Wöchentliche Schatzkammer-Karte - Abgeschlossen"
L["UNKNOWN_SOURCE"] = "Unbekannte Quelle"
L["DAILY_TASKS_PREFIX"] = "Tägliche Aufgaben - "
L["NO_FOUND_FORMAT"] = "Keine %ss gefunden"
L["PLANS_COUNT_FORMAT"] = "%d Pläne"
L["PET_BATTLE_LABEL"] = "Haustierkampf:"
L["QUEST_LABEL"] = "Quest:"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "Aktuelle Sprache:"
L["LANGUAGE_TOOLTIP"] = "Das Addon verwendet automatisch die Sprache deines WoW-Clients. Um sie zu ändern, aktualisiere deine Battle.net-Einstellungen."
L["POPUP_DURATION"] = "Popup-Dauer"
L["POPUP_POSITION"] = "Popup-Position"
L["SET_POSITION"] = "Position festlegen"
L["DRAG_TO_POSITION"] = "Ziehen zum Positionieren\nRechtsklick zum Bestätigen"
L["RESET_DEFAULT"] = "Standard wiederherstellen"
L["TEST_POPUP"] = "Popup testen"
L["CUSTOM_COLOR"] = "Eigene Farbe"
L["OPEN_COLOR_PICKER"] = "Farbwähler öffnen"
L["COLOR_PICKER_TOOLTIP"] = "Öffne WoWs nativen Farbwähler, um eine eigene Themenfarbe zu wählen"
L["PRESET_THEMES"] = "Voreingestellte Themen"
L["WARBAND_NEXUS_SETTINGS"] = "Warband Nexus Einstellungen"
L["NO_OPTIONS"] = "Keine Optionen"
L["NONE_LABEL"] = NONE or "Keine"
L["TAB_FILTERING"] = "Tab-Filterung"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Benachrichtigungen"
L["SCROLL_SPEED"] = "Scrollgeschwindigkeit"
L["ANCHOR_FORMAT"] = "Anker: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "Wochenplaner anzeigen"
L["LOCK_MINIMAP_ICON"] = "Minimap-Symbol sperren"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "Gegenstände in Tooltips anzeigen"
L["AUTO_SCAN_ITEMS"] = "Auto-Scan Gegenstände"
L["LIVE_SYNC"] = "Live-Synchronisierung"
L["BACKPACK_LABEL"] = "Rucksack"
L["REAGENT_LABEL"] = "Reagenzien"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "Modul deaktiviert"
L["LOADING"] = "Laden..."
L["PLEASE_WAIT"] = "Bitte warten..."
L["RESET_PREFIX"] = "Reset:"
L["TRANSFER_CURRENCY"] = "Währung übertragen"
L["AMOUNT_LABEL"] = "Betrag:"
L["TO_CHARACTER"] = "An Charakter:"
L["SELECT_CHARACTER"] = "Charakter wählen..."
L["CURRENCY_TRANSFER_INFO"] = "Das Währungsfenster wird automatisch geöffnet.\nDu musst die Währung manuell per Rechtsklick übertragen."
L["OK_BUTTON"] = OKAY or "OK"
L["SAVE"] = "Speichern"
L["TITLE_FIELD"] = "Titel:"
L["DESCRIPTION_FIELD"] = "Beschreibung:"
L["CREATE_CUSTOM_PLAN"] = "Eigenen Plan erstellen"
L["REPORT_BUGS"] = "Melde Fehler oder teile Vorschläge auf CurseForge, um das Addon zu verbessern."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus bietet eine zentrale Oberfläche zur Verwaltung aller deiner Charaktere, Währungen, Rufe, Gegenstände und PvE-Fortschritte deiner gesamten Kriegsmeute."
L["CHARACTERS_DESC"] = "Zeige alle Charaktere mit Gold, Stufe, Gegenstandsstufe, Fraktion, Volk, Klasse, Berufen, Schlüsselstein und letzter Spielzeit. Verfolge oder entfolge Charaktere, markiere Favoriten."
L["ITEMS_DESC"] = "Suche und durchstöbere Gegenstände in allen Taschen, Banken und der Kriegsmeute-Bank. Automatischer Scan beim Öffnen einer Bank. Zeigt per Tooltip, welche Charaktere jeden Gegenstand besitzen."
L["STORAGE_DESC"] = "Zusammengefasstes Inventar aller Charaktere — Taschen, persönliche Bank und Kriegsmeute-Bank an einem Ort vereint."
L["PVE_DESC"] = "Verfolge den Schatzkammer-Fortschritt mit Stufenindikator, Mythic+ Wertungen und Schlüssel, Schlüsselstein-Affixe, Dungeon-Verlauf und Aufwertungswährung über alle Charaktere."
L["REPUTATIONS_DESC"] = "Vergleiche den Ruffortschritt aller Charaktere. Zeigt Accountweite vs. Charakterspezifische Fraktionen mit Hover-Tooltips für Aufschlüsselung pro Charakter."
L["CURRENCY_DESC"] = "Zeige alle Währungen nach Erweiterung organisiert. Vergleiche Mengen über Charaktere mit Hover-Tooltips. Leere Währungen mit einem Klick ausblenden."
L["PLANS_DESC"] = "Verfolge nicht gesammelte Reittiere, Haustiere, Spielzeuge, Erfolge und Transmog. Ziele hinzufügen, Drop-Quellen ansehen und Versuchszähler verfolgen. Zugriff über /wn plan oder Minimap-Symbol."
L["STATISTICS_DESC"] = "Zeige Erfolgspunkte, Reittier-/Haustier-/Spielzeug-/Illusions-/Titel-Sammlungsfortschritt, einzigartige Haustierzählung und Taschen-/Banknutzungsstatistiken."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "Mythic"
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "Heroic"
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "Normal"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Stufe %d"
L["PVP_TYPE"] = PVP or "PvP"
L["PREPARING"] = "Vorbereitung"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Account-Statistiken"
L["STATISTICS_SUBTITLE"] = "Sammlungsfortschritt, Gold und Lagerübersicht"
L["MOST_PLAYED"] = "MEISTGESPIELT"
L["PLAYED_DAYS"] = "Tage"
L["PLAYED_HOURS"] = "Stunden"
L["PLAYED_MINUTES"] = "Minuten"
L["PLAYED_DAY"] = "Tag"
L["PLAYED_HOUR"] = "Stunde"
L["PLAYED_MINUTE"] = "Minute"
L["MORE_CHARACTERS"] = "weiterer Charakter"
L["MORE_CHARACTERS_PLURAL"] = "weitere Charaktere"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "Willkommen bei Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "AddOn-Übersicht"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "Verfolge deine Sammlungsziele"
L["ACTIVE_PLAN_FORMAT"] = "%d aktiver Plan"
L["ACTIVE_PLANS_FORMAT"] = "%d aktive Pläne"
L["RESET_LABEL"] = RESET or "Zurücksetzen"

-- Plans - Typnamen
L["TYPE_MOUNT"] = MOUNT or "Reittier"
L["TYPE_PET"] = PET or "Haustier"
L["TYPE_TOY"] = TOY or "Spielzeug"
L["TYPE_RECIPE"] = "Rezept"
L["TYPE_ILLUSION"] = "Illusion"
L["TYPE_TITLE"] = "Titel"
L["TYPE_CUSTOM"] = "Benutzerdefiniert"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transmog"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Beute"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Quest"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Händler"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Beruf"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Haustierkampf"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Erfolg"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "Weltereignis"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promotion"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "Sammelkartenspiel"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "Ingame-Shop"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "Hergestellt"
L["SOURCE_TYPE_TRADING_POST"] = "Handelsposten"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "Unbekannt"
L["SOURCE_TYPE_PVP"] = PVP or "PvP"
L["SOURCE_TYPE_TREASURE"] = "Schatz"
L["SOURCE_TYPE_PUZZLE"] = "Rätsel"
L["SOURCE_TYPE_RENOWN"] = "Ruhm"

-- Plans - Transmog Source Labels (Blizzard TRANSMOG_SOURCE_* Globals)
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Bossbeute"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Quest"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Händler"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "Weltbeute"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Erfolg"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Beruf"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "Verkauft von"
L["PARSE_CRAFTED"] = "Hergestellt"
L["PARSE_ZONE"] = ZONE or "Zone"
L["PARSE_COST"] = "Kosten"
L["PARSE_REPUTATION"] = REPUTATION or "Ruf"
L["PARSE_FACTION"] = FACTION or "Fraktion"
L["PARSE_ARENA"] = ARENA or "Arena"
L["PARSE_DUNGEON"] = DUNGEONS or "Dungeon"
L["PARSE_RAID"] = RAID or "Schlachtzug"
L["PARSE_HOLIDAY"] = "Feiertag"
L["PARSE_RATED"] = "Gewertet"
L["PARSE_BATTLEGROUND"] = "Schlachtfeld"
L["PARSE_DISCOVERY"] = "Entdeckung"
L["PARSE_CONTAINED_IN"] = "Enthalten in"
L["PARSE_GARRISON"] = "Garnison"
L["PARSE_GARRISON_BUILDING"] = "Garnisongebäude"
L["PARSE_STORE"] = "Shop"
L["PARSE_ORDER_HALL"] = "Ordenshalle"
L["PARSE_COVENANT"] = "Pakt"
L["PARSE_FRIENDSHIP"] = "Freundschaft"
L["PARSE_PARAGON"] = "Paragon"
L["PARSE_MISSION"] = "Mission"
L["PARSE_EXPANSION"] = "Erweiterung"
L["PARSE_SCENARIO"] = "Szenario"
L["PARSE_CLASS_HALL"] = "Klassenhalle"
L["PARSE_CAMPAIGN"] = "Kampagne"
L["PARSE_EVENT"] = "Ereignis"
L["PARSE_SPECIAL"] = "Spezial"
L["PARSE_BRAWLERS_GUILD"] = "Kampfgilde"
L["PARSE_CHALLENGE_MODE"] = "Herausforderungsmodus"
L["PARSE_MYTHIC_PLUS"] = "Mythisch+"
L["PARSE_TIMEWALKING"] = "Zeitwanderung"
L["PARSE_ISLAND_EXPEDITION"] = "Inselexpedition"
L["PARSE_WARFRONT"] = "Kriegsfront"
L["PARSE_TORGHAST"] = "Torghast"
L["PARSE_ZERETH_MORTIS"] = "Zereth Mortis"
L["PARSE_HIDDEN"] = "Versteckt"
L["PARSE_RARE"] = "Selten"
L["PARSE_WORLD_BOSS"] = "Weltboss"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Beute"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "Vom Erfolg"
L["FALLBACK_UNKNOWN_PET"] = "Unbekanntes Haustier"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "Haustiersammlung"
L["FALLBACK_TOY_COLLECTION"] = "Spielzeugsammlung"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Transmog-Sammlung"
L["FALLBACK_PLAYER_TITLE"] = "Spielertitel"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Unbekannt"
L["FALLBACK_ILLUSION_FORMAT"] = "Illusion %s"
L["SOURCE_ENCHANTING"] = "Verzauberkunst"

-- Plans - Dialoge
L["SET_TRY_COUNT_TEXT"] = "Versuche festlegen für:\n%s"
L["RESET_COMPLETED_CONFIRM"] = "Möchtest du wirklich ALLE abgeschlossenen Pläne entfernen?\n\nDies kann nicht rückgängig gemacht werden!"
L["YES_RESET"] = "Ja, zurücksetzen"
L["REMOVED_PLANS_FORMAT"] = "%d abgeschlossene(n) Plan/Pläne entfernt."

-- Plans - Schaltflächen
L["ADD_CUSTOM"] = "Eigenen hinzufügen"
L["ADD_VAULT"] = "Vault hinzufügen"
L["ADD_QUEST"] = "Quest hinzufügen"
L["CREATE_PLAN"] = "Plan erstellen"

-- Plans - Quest-Kategorien
L["QUEST_CAT_DAILY"] = "Täglich"
L["QUEST_CAT_WORLD"] = "Welt"
L["QUEST_CAT_WEEKLY"] = "Wöchentlich"
L["QUEST_CAT_ASSIGNMENT"] = "Auftrag"

-- Plans - Durchsuchen
L["UNKNOWN_CATEGORY"] = "Unbekannte Kategorie"
L["SCANNING_FORMAT"] = "%s wird gescannt"
L["CUSTOM_PLAN_SOURCE"] = "Benutzerdefinierter Plan"
L["POINTS_FORMAT"] = "%d Punkte"
L["SOURCE_NOT_AVAILABLE"] = "Quellinformation nicht verfügbar"
L["PROGRESS_ON_FORMAT"] = "Du bist bei %d/%d im Fortschritt"
L["COMPLETED_REQ_FORMAT"] = "Du hast %d von %d Anforderungen abgeschlossen"

-- Plans - Inhalte & Quest-Typen
L["CONTENT_MIDNIGHT"] = "Midnight"
L["CONTENT_TWW"] = "The War Within"
L["QUEST_TYPE_DAILY"] = "Tägliche Quests"
L["QUEST_TYPE_DAILY_DESC"] = "Reguläre tägliche Quests von NPCs"
L["QUEST_TYPE_WORLD"] = "Weltquests"
L["QUEST_TYPE_WORLD_DESC"] = "Zonenweite Weltquests"
L["QUEST_TYPE_WEEKLY"] = "Wöchentliche Quests"
L["QUEST_TYPE_WEEKLY_DESC"] = "Wöchentlich wiederkehrende Quests"
L["QUEST_TYPE_ASSIGNMENTS"] = "Aufträge"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "Spezielle Aufträge und Aufgaben"

-- Plans - Wöchentlicher Vault-Fortschritt
L["MYTHIC_PLUS_LABEL"] = "Mythisch+"
L["RAIDS_LABEL"] = RAIDS or "Raids"

-- PlanCardFactory
L["FACTION_LABEL"] = "Fraktion:"
L["FRIENDSHIP_LABEL"] = "Freundschaft"
L["RENOWN_TYPE_LABEL"] = "Ruhm"
L["ADD_BUTTON"] = "+ Hinzufügen"
L["ADDED_LABEL"] = "Hinzugefügt"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s von %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Stapelanzahl auf Gegenständen in der Lageransicht anzeigen"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Wochenplaner-Bereich im Charaktere-Tab anzeigen"
L["LOCK_MINIMAP_TOOLTIP"] = "Minimap-Symbol fixieren (verhindert Verschieben)"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "Zeigt die Anzahl der Gegenstände für die Kriegsmeute und Charaktere in Tooltips an (WN Suche)."
L["AUTO_SCAN_TOOLTIP"] = "Gegenstände automatisch scannen und cachen beim Öffnen von Banken oder Taschen"
L["LIVE_SYNC_TOOLTIP"] = "Gegenstands-Cache in Echtzeit aktualisieren, während Banken geöffnet sind"
L["SHOW_ILVL_TOOLTIP"] = "Gegenstandsstufen-Abzeichen auf Ausrüstung in der Gegenstandsliste anzeigen"
L["SCROLL_SPEED_TOOLTIP"] = "Multiplikator für Scrollgeschwindigkeit (1.0x = 28 px pro Schritt)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "Kriegsmeute-Bank Tab %d vom automatischen Scannen ausschließen"
L["IGNORE_SCAN_FORMAT"] = "%s vom automatischen Scannen ausschließen"
L["BANK_LABEL"] = BANK or "Bank"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "Benachrichtigungen aktivieren"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Hauptschalter für alle Benachrichtigungs-Popups"
L["VAULT_REMINDER"] = "Schatzkammer-Erinnerung"
L["VAULT_REMINDER_TOOLTIP"] = "Erinnerung anzeigen, wenn nicht abgeholte Schatzkammer-Belohnungen verfügbar sind"
L["LOOT_ALERTS"] = "Beute-Warnungen"
L["LOOT_ALERTS_TOOLTIP"] = "Hauptschalter für Sammlungs-Popups. Deaktivierung blendet alle Sammlungs-Benachrichtigungen aus."
L["LOOT_ALERTS_MOUNT"] = "Reittier-Benachrichtigungen"
L["LOOT_ALERTS_MOUNT_TOOLTIP"] = "Benachrichtigung anzeigen, wenn du ein neues Reittier sammelst."
L["LOOT_ALERTS_PET"] = "Haustier-Benachrichtigungen"
L["LOOT_ALERTS_PET_TOOLTIP"] = "Benachrichtigung anzeigen, wenn du ein neues Haustier sammelst."
L["LOOT_ALERTS_TOY"] = "Spielzeug-Benachrichtigungen"
L["LOOT_ALERTS_TOY_TOOLTIP"] = "Benachrichtigung anzeigen, wenn du ein neues Spielzeug sammelst."
L["LOOT_ALERTS_TRANSMOG"] = "Aussehens-Benachrichtigungen"
L["LOOT_ALERTS_TRANSMOG_TOOLTIP"] = "Benachrichtigung anzeigen, wenn du ein neues Rüstungs- oder Waffenaussehen sammelst."
L["LOOT_ALERTS_ILLUSION"] = "Illusions-Benachrichtigungen"
L["LOOT_ALERTS_ILLUSION_TOOLTIP"] = "Benachrichtigung anzeigen, wenn du eine neue Waffenillusion sammelst."
L["LOOT_ALERTS_TITLE"] = "Titel-Benachrichtigungen"
L["LOOT_ALERTS_TITLE_TOOLTIP"] = "Benachrichtigung anzeigen, wenn du einen neuen Titel verdienst."
L["LOOT_ALERTS_ACHIEVEMENT"] = "Erfolgs-Benachrichtigungen"
L["LOOT_ALERTS_ACHIEVEMENT_TOOLTIP"] = "Benachrichtigung anzeigen, wenn du einen neuen Erfolg verdienst."
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Blizzard-Erfolgswarnung ausblenden"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Blizzards Standard-Erfolgspopup ausblenden und stattdessen Warband Nexus Benachrichtigung verwenden"
L["REPUTATION_GAINS"] = "Rufgewinne"
L["REPUTATION_GAINS_TOOLTIP"] = "Chatnachrichten anzeigen, wenn du Ruf bei Fraktionen gewinnst"
L["CURRENCY_GAINS"] = "Währungsgewinne"
L["CURRENCY_GAINS_TOOLTIP"] = "Chatnachrichten anzeigen, wenn du Währungen gewinnst"
L["SCREEN_FLASH_EFFECT"] = "Bildschirmblitz-Effekt"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Bildschirmblitz-Effekt abspielen, wenn du ein neues Sammelstück erhältst (Reittier, Haustier, Spielzeug usw.)"
L["AUTO_TRY_COUNTER"] = "Automatischer Versuchszähler"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Versuche automatisch zählen beim Plündern von NPCs, Seltenen, Bossen, Angeln oder Öffnen von Behältern, die Reittiere, Haustiere oder Spielzeuge droppen. Zeigt die Versuchszahl im Chat, wenn das Sammelstück nicht droppt."
L["DURATION_LABEL"] = "Dauer"
L["DAYS_LABEL"] = "Tage"
L["WEEKS_LABEL"] = "Wochen"
L["EXTEND_DURATION"] = "Dauer verlängern"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Ziehe den grünen Rahmen, um die Popup-Position festzulegen. Rechtsklick zum Bestätigen."
L["POSITION_RESET_MSG"] = "Popup-Position auf Standard zurückgesetzt (Oben Mitte)"
L["POSITION_SAVED_MSG"] = "Popup-Position gespeichert!"
L["TEST_NOTIFICATION_TITLE"] = "Test-Benachrichtigung"
L["TEST_NOTIFICATION_MSG"] = "Positionstest"
L["NOTIFICATION_DEFAULT_TITLE"] = "Benachrichtigung"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "Design & Erscheinungsbild"
L["COLOR_PURPLE"] = "Lila"
L["COLOR_PURPLE_DESC"] = "Klassisches Lila-Design (Standard)"
L["COLOR_BLUE"] = "Blau"
L["COLOR_BLUE_DESC"] = "Kühles Blau-Design"
L["COLOR_GREEN"] = "Grün"
L["COLOR_GREEN_DESC"] = "Natur-Grün-Design"
L["COLOR_RED"] = "Rot"
L["COLOR_RED_DESC"] = "Feuriges Rot-Design"
L["COLOR_ORANGE"] = "Orange"
L["COLOR_ORANGE_DESC"] = "Warmes Orange-Design"
L["COLOR_CYAN"] = "Cyan"
L["COLOR_CYAN_DESC"] = "Helles Cyan-Design"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "Schriftfamilie"
L["FONT_FAMILY_TOOLTIP"] = "Wähle die Schriftart für die gesamte Addon-Oberfläche"
L["FONT_SCALE"] = "Schriftgröße"
L["FONT_SCALE_TOOLTIP"] = "Schriftgröße über alle UI-Elemente anpassen"
L["FONT_SCALE_WARNING"] = "Warnung: Größere Schriftskalierung kann in manchen UI-Elementen zu Textüberlauf führen."
L["RESOLUTION_NORMALIZATION"] = "Auflösungsnormalisierung"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Schriftgrößen basierend auf Bildschirmauflösung und UI-Skalierung anpassen, damit Text auf verschiedenen Monitoren gleich groß bleibt"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Erweitert"

-- =============================================
-- Settings - Module Management
-- =============================================
L["MODULE_MANAGEMENT"] = "Modulverwaltung"
L["MODULE_MANAGEMENT_DESC"] = "Aktiviere oder deaktiviere bestimmte Datenerfassungsmodule. Das Deaktivieren eines Moduls stoppt seine Datenaktualisierungen und blendet seinen Tab in der Benutzeroberfläche aus."
L["MODULE_CURRENCIES"] = "Währungen"
L["MODULE_CURRENCIES_DESC"] = "Verfolge accountweite und charakterspezifische Währungen (Gold, Ehre, Eroberung usw.)"
L["MODULE_REPUTATIONS"] = "Rufe"
L["MODULE_REPUTATIONS_DESC"] = "Verfolge Ruffortschritt mit Fraktionen, Ruhmstufen und Paragon-Belohnungen"
L["MODULE_ITEMS"] = "Gegenstände"
L["MODULE_ITEMS_DESC"] = "Verfolge Kriegsmeute-Bank Gegenstände, Suchfunktion und Gegenstandskategorien"
L["MODULE_STORAGE"] = "Lager"
L["MODULE_STORAGE_DESC"] = "Verfolge Charaktertaschen, persönliche Bank und Kriegsmeute-Bank Lager"
L["MODULE_PVE"] = "PvE"
L["MODULE_PVE_DESC"] = "Verfolge Mythisch+ Dungeons, Schlachtzugfortschritt und Große Schatzkammer Belohnungen"
L["MODULE_PLANS"] = "Pläne"
L["MODULE_PLANS_DESC"] = "Verfolge persönliche Ziele für Reittiere, Haustiere, Spielzeuge, Erfolge und eigene Aufgaben"
L["MODULE_PROFESSIONS"] = "Berufe"
L["MODULE_PROFESSIONS_DESC"] = "Verfolge Berufsskills, Konzentration, Wissen und Rezeptbegleiter-Fenster"
L["PROFESSIONS_DISABLED_TITLE"] = "Berufe"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Gegenstandsstufe %s"
L["ITEM_NUMBER_FORMAT"] = "Gegenstand #%s"
L["CHARACTER_CURRENCIES"] = "Charakter-Währungen:"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "Accountweit (Kriegsschar) — gleicher Kontostand bei allen Charakteren."
L["YOU_MARKER"] = "(Du)"
L["WN_SEARCH"] = "WN Suche"
L["WARBAND_BANK_COLON"] = "Kriegsmeute-Bank:"
L["AND_MORE_FORMAT"] = "... und %d weitere"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "Du hast ein Reittier gesammelt"
L["COLLECTED_PET_MSG"] = "Du hast ein Kampfhaustier gesammelt"
L["COLLECTED_TOY_MSG"] = "Du hast ein Spielzeug gesammelt"
L["COLLECTED_ILLUSION_MSG"] = "Du hast eine Illusion gesammelt"
L["COLLECTED_ITEM_MSG"] = "Du hast einen seltenen Drop erhalten"
L["ACHIEVEMENT_COMPLETED_MSG"] = "Erfolg abgeschlossen!"
L["EARNED_TITLE_MSG"] = "Du hast einen Titel erhalten"
L["COMPLETED_PLAN_MSG"] = "Du hast einen Plan abgeschlossen"
L["DAILY_QUEST_CAT"] = "Tagesquest"
L["WORLD_QUEST_CAT"] = "Weltquest"
L["WEEKLY_QUEST_CAT"] = "Wochenquest"
L["SPECIAL_ASSIGNMENT_CAT"] = "Spezialauftrag"
L["DELVE_CAT"] = "Tiefe"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "Dungeon"
L["RAID_CAT"] = RAID or "Raid"
L["WORLD_CAT"] = "Welt"
L["ACTIVITY_CAT"] = "Aktivität"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Fortschritt"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Fortschritt abgeschlossen"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Wöchentlicher Schatzkammer-Plan - %s"
L["ALL_SLOTS_COMPLETE"] = "Alle Plätze abgeschlossen!"
L["QUEST_COMPLETED_SUFFIX"] = "Abgeschlossen"
L["WEEKLY_VAULT_READY"] = "Wöchentliche Schatzkammer bereit!"
L["UNCLAIMED_REWARDS"] = "Du hast nicht abgeholte Belohnungen"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "Gold gesamt:"
L["CHARACTERS_COLON"] = "Charaktere:"
L["LEFT_CLICK_TOGGLE"] = "Linksklick: Fenster ein-/ausblenden"
L["RIGHT_CLICK_PLANS"] = "Rechtsklick: Pläne öffnen"
L["MINIMAP_SHOWN_MSG"] = "Minimap-Schaltfläche angezeigt"
L["MINIMAP_HIDDEN_MSG"] = "Minimap-Schaltfläche ausgeblendet (verwende /wn minimap zum Anzeigen)"
L["TOGGLE_WINDOW"] = "Fenster umschalten"
L["SCAN_BANK_MENU"] = "Bank scannen"
L["TRACKING_DISABLED_SCAN_MSG"] = "Charakterverfolgung ist deaktiviert. Aktiviere die Verfolgung in den Einstellungen, um die Bank zu scannen."
L["SCAN_COMPLETE_MSG"] = "Scan abgeschlossen!"
L["BANK_NOT_OPEN_MSG"] = "Bank ist nicht geöffnet"
L["OPTIONS_MENU"] = "Optionen"
L["HIDE_MINIMAP_BUTTON"] = "Minimap-Schaltfläche ausblenden"
L["MENU_UNAVAILABLE_MSG"] = "Rechtsklick-Menü nicht verfügbar"
L["USE_COMMANDS_MSG"] = "Verwende /wn show, /wn options, /wn help"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "Max"
L["OPEN_AND_GUIDE"] = "Öffnen & Anleitung"
L["FROM_LABEL"] = "Von:"
L["AVAILABLE_LABEL"] = "Verfügbar:"
L["ONLINE_LABEL"] = "(Online)"
L["DATA_SOURCE_TITLE"] = "Datenquelleninformation"
L["DATA_SOURCE_USING"] = "Dieser Tab verwendet:"
L["DATA_SOURCE_MODERN"] = "Moderner Cache-Dienst (eventgesteuert)"
L["DATA_SOURCE_LEGACY"] = "Alter direkter DB-Zugriff"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Benötigt Migration zum Cache-Dienst"
L["GLOBAL_DB_VERSION"] = "Globale DB-Version:"

-- =============================================
-- Information Dialog - Tab-Überschriften
-- =============================================
L["INFO_TAB_CHARACTERS"] = "Charaktere"
L["INFO_TAB_ITEMS"] = "Gegenstände"
L["INFO_TAB_STORAGE"] = "Lager"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "Rufe"
L["INFO_TAB_CURRENCY"] = "Währungen"
L["INFO_TAB_PLANS"] = "Pläne"
L["INFO_TAB_STATISTICS"] = "Statistiken"
L["SPECIAL_THANKS"] = "Besonderer Dank"
L["SUPPORTERS_TITLE"] = "Unterstützer"
L["THANK_YOU_MSG"] = "Vielen Dank, dass du Warband Nexus verwendest!"

-- =============================================
-- Changelog (What's New) - v2.1.2
-- =============================================
L["CHANGELOG_V212"] =     "�NDERUNGEN:\n- Sortiersystem hinzugef�gt.\n- Verschiedene UI-Fehler behoben.\n- Umschaltfl�che f�r den Beruf-Rezeptbegleiter hinzugef�gt und dessen Fenster nach links verschoben.\n- Probleme bei der Verfolgung der Berufskonzentration behoben.\n- Fehler behoben, bei dem der Try-Z�hler f�lschlicherweise sofort '1 attempts' anzeigte, nachdem ein Sammelgegenstand erbeutet wurde.\n- UI-Ruckeln und FPS-Einbr�che beim Pl�ndern von Gegenst�nden oder �ffnen von Beh�ltern durch Optimierung der Hintergrundverfolgung deutlich reduziert.\n- Fehler behoben, bei dem Boss-Kills bei bestimmten Reittieren (z. B. Steinw�lbegomechanismus) nicht korrekt zu den Beuteversuchen addiert wurden.\n- Fehler behoben, bei dem �berf�llte M�llcontainer nicht korrekt auf W�hrung oder andere erbeutete Gegenst�nde gepr�ft wurden.\n\nVielen Dank f�r deine anhaltende Unterst�tzung!\n\nUm Probleme zu melden oder Feedback zu geben, hinterlasse einen Kommentar auf CurseForge - Warband Nexus."
-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "Aktion bestätigen"
L["CONFIRM"] = "Bestätigen"
L["ENABLE_TRACKING_FORMAT"] = "Verfolgung für |cffffcc00%s|r aktivieren?"
L["DISABLE_TRACKING_FORMAT"] = "Verfolgung für |cffffcc00%s|r deaktivieren?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "Accountweite Rufe (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Charakterbasierte Rufe (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "Belohnung wartet"
L["REP_PARAGON_LABEL"] = "Paragon"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "Vorbereitung..."
L["REP_LOADING_INITIALIZING"] = "Initialisierung..."
L["REP_LOADING_FETCHING"] = "Lade Rufdaten..."
L["REP_LOADING_PROCESSING"] = "Verarbeite %d Fraktionen..."
L["REP_LOADING_PROCESSING_COUNT"] = "Verarbeitung... (%d/%d)"
L["REP_LOADING_SAVING"] = "Speichere in Datenbank..."
L["REP_LOADING_COMPLETE"] = "Fertig!"

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "Fenster kann im Kampf nicht geöffnet werden. Bitte nach dem Kampf erneut versuchen."
L["BANK_IS_ACTIVE"] = "Bank ist aktiv"
L["ITEMS_CACHED_FORMAT"] = "%d Gegenstände gespeichert"
-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "CHARAKTER"
L["TABLE_HEADER_LEVEL"] = "STUFE"
L["TABLE_HEADER_GOLD"] = "GOLD"
L["TABLE_HEADER_LAST_SEEN"] = "ZULETZT GESEHEN"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "Keine Gegenstände stimmen mit '%s' überein"
L["NO_ITEMS_MATCH_GENERIC"] = "Keine Gegenstände stimmen mit deiner Suche überein"
L["ITEMS_SCAN_HINT"] = "Gegenstände werden automatisch gescannt. Versuche /reload, wenn nichts erscheint."
L["ITEMS_WARBAND_BANK_HINT"] = "Öffne die Kriegsmeute-Bank, um Gegenstände zu scannen (automatisch beim ersten Besuch)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Nächste Schritte:"
L["CURRENCY_TRANSFER_STEP_1"] = "Finde |cffffffff%s|r im Währungsfenster"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800Rechtsklick|r darauf"
L["CURRENCY_TRANSFER_STEP_3"] = "Wähle |cffffffff'An Kriegsmeute übertragen'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Wähle |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Betrag eingeben: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "Währungsfenster ist jetzt geöffnet!"
L["CURRENCY_TRANSFER_SECURITY"] = "(Blizzard-Sicherheit verhindert automatische Übertragung)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "Zone: "
L["ADDED"] = "Hinzugefügt"
L["WEEKLY_VAULT_TRACKER"] = "Wöchentl. Tresor-Tracker"
L["DAILY_QUEST_TRACKER"] = "Täglicher Quest-Tracker"
L["CUSTOM_PLAN_STATUS"] = "Eigener Plan '%s' %s"

-- =============================================
-- Achievement Popup
-- =============================================
L["ACHIEVEMENT_COMPLETED"] = "Abgeschlossen"
L["ACHIEVEMENT_NOT_COMPLETED"] = "Nicht abgeschlossen"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d Pkt."
L["ADD_PLAN"] = "Hinzufügen"
L["PLANNED"] = "Geplant"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon"
L["VAULT_SLOT_RAIDS"] = RAIDS or "Raids"
L["VAULT_SLOT_WORLD"] = "Welt"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "Affix"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_STANDING_LABEL"] = "Jetzt"
L["CHAT_GAINED_PREFIX"] = "+"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "Plan abgeschlossen: "
L["WEEKLY_VAULT_PLAN_NAME"] = "Wöchentlicher Tresor - %s"
L["VAULT_PLANS_RESET"] = "Wöchentliche Tresor-Pläne wurden zurückgesetzt! (%d Plan%s)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "Keine Charaktere gefunden"
L["EMPTY_CHARACTERS_DESC"] = "Melde dich mit deinen Charakteren an, um sie zu verfolgen.\nCharakterdaten werden bei jeder Anmeldung automatisch gesammelt."
L["EMPTY_ITEMS_TITLE"] = "Keine Gegenstände gespeichert"
L["EMPTY_ITEMS_DESC"] = "Öffne deine Kriegsmeute-Bank oder persönliche Bank, um Gegenstände zu scannen.\nGegenstände werden beim ersten Besuch automatisch zwischengespeichert."
L["EMPTY_STORAGE_TITLE"] = "Keine Lagerdaten"
L["EMPTY_STORAGE_DESC"] = "Gegenstände werden beim Öffnen von Banken oder Taschen gescannt.\nBesuche eine Bank, um dein Lager zu verfolgen."
L["EMPTY_PLANS_TITLE"] = "Noch keine Pläne"
L["EMPTY_PLANS_DESC"] = "Durchstöbere Reittiere, Haustiere, Spielzeuge oder Erfolge oben,\num Sammelziele hinzuzufügen und deinen Fortschritt zu verfolgen."
L["EMPTY_REPUTATION_TITLE"] = "Keine Rufwerte vorhanden"
L["EMPTY_REPUTATION_DESC"] = "Rufwerte werden automatisch bei der Anmeldung gescannt.\nMelde dich mit einem Charakter an, um Fraktionsstände zu verfolgen."
L["EMPTY_CURRENCY_TITLE"] = "Keine Währungsdaten"
L["EMPTY_CURRENCY_DESC"] = "Währungen werden automatisch über alle Charaktere verfolgt.\nMelde dich mit einem Charakter an, um Währungen zu verfolgen."
L["EMPTY_PVE_TITLE"] = "Keine PvE-Daten"
L["EMPTY_PVE_DESC"] = "PvE-Fortschritt wird verfolgt, wenn du dich mit Charakteren anmeldest.\nSchatzkammer, Mythisch+ und Schlachtzugssperren erscheinen hier."
L["EMPTY_STATISTICS_TITLE"] = "Keine Statistiken verfügbar"
L["EMPTY_STATISTICS_DESC"] = "Statistiken werden von deinen verfolgten Charakteren gesammelt.\nMelde dich mit einem Charakter an, um Daten zu sammeln."
L["NO_ADDITIONAL_INFO"] = "Keine weiteren Informationen"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "Möchtest du diesen Charakter verfolgen?"
L["CLEANUP_NO_INACTIVE"] = "Keine inaktiven Charaktere gefunden (90+ Tage)"
L["CLEANUP_REMOVED_FORMAT"] = "%d inaktive(n) Charakter(e) entfernt"
L["TRACKING_ENABLED_MSG"] = "Charakterverfolgung AKTIVIERT!"
L["TRACKING_DISABLED_MSG"] = "Charakterverfolgung DEAKTIVIERT!"
L["TRACKING_ENABLED"] = "Verfolgung AKTIVIERT"
L["TRACKING_DISABLED"] = "Verfolgung DEAKTIVIERT (Nur-Lesen-Modus)"
L["STATUS_LABEL"] = "Status:"
L["ERROR_LABEL"] = "Fehler:"
L["ERROR_NAME_REALM_REQUIRED"] = "Charaktername und Realm erforderlich"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s hat bereits einen aktiven Wochenplan"

-- Profiles (AceDB)
L["PROFILES"] = "Profile"
L["PROFILES_DESC"] = "Addon-Profile verwalten"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "Keine Kriterien gefunden"
L["NO_REQUIREMENTS_INSTANT"] = "Keine Anforderungen (sofortiger Abschluss)"

-- Statistics Tab (missing)
L["TOTAL_PETS"] = "Begleiter gesamt"

-- Items Tab (missing)
L["ITEM_LOADING_NAME"] = "Laden..."

-- Transmog Slot Names (Blizzard INVTYPE_* Globals)
L["SLOT_HEAD"] = INVTYPE_HEAD or "Head"
L["SLOT_SHOULDER"] = INVTYPE_SHOULDER or "Shoulder"
L["SLOT_BACK"] = INVTYPE_CLOAK or "Back"
L["SLOT_CHEST"] = INVTYPE_CHEST or "Chest"
L["SLOT_SHIRT"] = INVTYPE_BODY or "Shirt"
L["SLOT_TABARD"] = INVTYPE_TABARD or "Tabard"
L["SLOT_WRIST"] = INVTYPE_WRIST or "Wrist"
L["SLOT_HANDS"] = INVTYPE_HAND or "Hands"
L["SLOT_WAIST"] = INVTYPE_WAIST or "Waist"
L["SLOT_LEGS"] = INVTYPE_LEGS or "Legs"
L["SLOT_FEET"] = INVTYPE_FEET or "Feet"
L["SLOT_MAINHAND"] = INVTYPE_WEAPONMAINHAND or "Main Hand"
L["SLOT_OFFHAND"] = INVTYPE_WEAPONOFFHAND or "Off Hand"

-- =============================================
-- Professions Tab
-- =============================================
L["TAB_PROFESSIONS"] = "Berufe"
L["YOUR_PROFESSIONS"] = "Kriegsmeute-Berufe"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s Charaktere mit Berufen"
L["HEADER_PROFESSIONS"] = "Berufsübersicht"
L["NO_PROFESSIONS_DATA"] = "Noch keine Berufsdaten verfügbar. Öffne dein Berufsfenster (Standard: K) bei jedem Charakter, um Daten zu sammeln."
L["CONCENTRATION"] = "Konzentration"
L["KNOWLEDGE"] = "Wissen"
L["SKILL"] = "Fertigkeit"
L["RECIPES"] = "Rezepte"
L["UNSPENT_POINTS"] = "Unverteilte Punkte"
L["COLLECTIBLE"] = "Sammelbar"
L["RECHARGE"] = "Aufladen"
L["FULL"] = "Voll"
L["PROF_OPEN_RECIPE"] = "Öffnen"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "Rezeptliste dieses Berufs öffnen"
L["PROF_ONLY_CURRENT_CHAR"] = "Nur für den aktuellen Charakter verfügbar"
L["NO_PROFESSION"] = "Kein Beruf"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "Erstes Fertigen"
L["SKILL_UPS"] = "Fertigkeitsstufen"
L["COOLDOWNS"] = "Abklingzeiten"
L["ORDERS"] = "Aufträge"

-- Professions: Tooltips & Details
L["LEARNED_RECIPES"] = "Gelernte Rezepte"
L["UNLEARNED_RECIPES"] = "Ungelernte Rezepte"
L["LAST_SCANNED"] = "Zuletzt gescannt"
L["JUST_NOW"] = "Gerade eben"
L["RECIPE_NO_DATA"] = "Berufsfenster öffnen, um Rezeptdaten zu sammeln"
L["FIRST_CRAFT_AVAILABLE"] = "Verfügbare Erstfertigungen"
L["FIRST_CRAFT_DESC"] = "Rezepte, die beim ersten Fertigen Bonus-EP gewähren"
L["SKILLUP_RECIPES"] = "Fertigkeits-Rezepte"
L["SKILLUP_DESC"] = "Rezepte, die deine Fertigkeitsstufe noch erhöhen können"
L["NO_ACTIVE_COOLDOWNS"] = "Keine aktiven Abklingzeiten"

-- Professions: Crafting Orders
L["CRAFTING_ORDERS"] = "Fertigungsaufträge"
L["PERSONAL_ORDERS"] = "Persönliche Aufträge"
L["PUBLIC_ORDERS"] = "Öffentliche Aufträge"
L["CLAIMS_REMAINING"] = "Anspruch verbleibend"
L["NO_ACTIVE_ORDERS"] = "Keine aktiven Aufträge"
L["ORDER_NO_DATA"] = "Beruf am Fertigungstisch öffnen zum Scannen"

-- Professions: Equipment
L["EQUIPMENT"] = "Ausrüstung"
L["TOOL"] = "Werkzeug"
L["ACCESSORY"] = "Zubehör"

-- =============================================
-- New keys (v2.1.0)
-- =============================================
L["TOOLTIP_ATTEMPTS"] = "Versuche"
L["TOOLTIP_100_DROP"] = "100% Drop"
L["TOOLTIP_UNKNOWN"] = "Unbekannt"
L["TOOLTIP_WARBAND_BANK"] = "Kriegsmeute-Bank"
L["TOOLTIP_HOLD_SHIFT"] = "  [Umschalt] halten für vollständige Liste"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - Konzentration"
L["TOOLTIP_FULL"] = "(Voll)"
L["NO_ITEMS_CACHED_TITLE"] = "Keine Gegenstände gespeichert"
L["COMBAT_CURRENCY_ERROR"] = "Währungsfenster kann im Kampf nicht geöffnet werden. Versuche es nach dem Kampf erneut."
L["DB_LABEL"] = "DB:"
L["COLLECTING_PVE"] = "Sammle PvE-Daten"
L["PVE_PREPARING"] = "Vorbereitung"
L["PVE_GREAT_VAULT"] = "Große Schatzkammer"
L["PVE_MYTHIC_SCORES"] = "Mythisch+-Wertungen"
L["PVE_RAID_LOCKOUTS"] = "Schlachtzug-Sperren"
L["PVE_INCOMPLETE_DATA"] = "Einige Daten könnten unvollständig sein. Später erneut aktualisieren."
L["VAULT_SLOTS_TO_FILL"] = "%d Große Schatzkammer-Slot%s zu füllen"
L["VAULT_SLOT_PLURAL"] = "s"
L["REP_RENOWN_NEXT"] = "Ruf %d"
L["REP_TO_NEXT_FORMAT"] = "%s Ruf bis %s (%s)"
L["REP_FACTION_FALLBACK"] = "Fraktion"
L["COLLECTION_CANCELLED"] = "Sammlung vom Benutzer abgebrochen"
L["CLEANUP_STALE_FORMAT"] = "%d veraltete(r) Charakter(e) bereinigt"
L["PERSONAL_BANK"] = "Persönliche Bank"
L["WARBAND_BANK_LABEL"] = "Kriegsmeute-Bank"
L["WARBAND_BANK_TAB_FORMAT"] = "Tab %d"
L["CURRENCY_OTHER"] = "Andere"
L["ERROR_SAVING_CHARACTER"] = "Fehler beim Speichern des Charakters:"
L["STANDING_HATED"] = "Verhasst"
L["STANDING_HOSTILE"] = "Feindselig"
L["STANDING_UNFRIENDLY"] = "Unfreundlich"
L["STANDING_NEUTRAL"] = "Neutral"
L["STANDING_FRIENDLY"] = "Verbündet"
L["STANDING_HONORED"] = "Wohlwollend"
L["STANDING_REVERED"] = "Respektiert"
L["STANDING_EXALTED"] = "Ehrfürchtig"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d Versuche für %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "%s erhalten! Versuchszähler zurückgesetzt."
L["TRYCOUNTER_CAUGHT_RESET"] = "%s eingefangen! Versuchszähler zurückgesetzt."
L["TRYCOUNTER_CONTAINER_RESET"] = "%s aus Behälter erhalten! Versuchszähler zurückgesetzt."
L["TRYCOUNTER_LOCKOUT_SKIP"] = "Übersprungen: Tägliche/wöchentliche Sperre für diesen NSC aktiv."
L["TRYCOUNTER_INSTANCE_DROPS"] = "Sammelbare Beute in dieser Instanz:"
L["TRYCOUNTER_COLLECTED_TAG"] = "(Gesammelt)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " Versuche"
L["TRYCOUNTER_TYPE_MOUNT"] = "Reittier"
L["TRYCOUNTER_TYPE_PET"] = "Haustier"
L["TRYCOUNTER_TYPE_TOY"] = "Spielzeug"
L["TRYCOUNTER_TYPE_ITEM"] = "Gegenstand"
L["TRYCOUNTER_TRY_COUNTS"] = "Versuchszähler"
L["LT_CHARACTER_DATA"] = "Charakterdaten"
L["LT_CURRENCY_CACHES"] = "Währungen & Caches"
L["LT_REPUTATIONS"] = "Ruf"
L["LT_PROFESSIONS"] = "Berufe"
L["LT_PVE_DATA"] = "PvE-Daten"
L["LT_COLLECTIONS"] = "Sammlungen"
L["CONFIG_HEADER"] = "Warband Nexus"
L["CONFIG_HEADER_DESC"] = "Moderne Kriegsmeute-Verwaltung und übergreifende Charakterverfolgung."
L["CONFIG_GENERAL"] = "Allgemeine Einstellungen"
L["CONFIG_GENERAL_DESC"] = "Grundlegende Addon-Einstellungen und Verhaltensoptionen."
L["CONFIG_ENABLE"] = "Addon aktivieren"
L["CONFIG_ENABLE_DESC"] = "Addon ein- oder ausschalten."
L["CONFIG_MINIMAP"] = "Minikarten-Schaltfläche"
L["CONFIG_MINIMAP_DESC"] = "Schaltfläche auf der Minikarte für schnellen Zugriff anzeigen."
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "Gegenstände in Tooltips anzeigen"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "Kriegsmeute- und Charakter-Gegenstandsanzahl in Gegenstands-Tooltips anzeigen."
L["CONFIG_MODULES"] = "Modulverwaltung"
L["CONFIG_MODULES_DESC"] = "Einzelne Addon-Module aktivieren oder deaktivieren. Deaktivierte Module sammeln keine Daten und zeigen keine UI-Tabs."
L["CONFIG_MOD_CURRENCIES"] = "Währungen"
L["CONFIG_MOD_CURRENCIES_DESC"] = "Währungen über alle Charaktere verfolgen."
L["CONFIG_MOD_REPUTATIONS"] = "Ruf"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "Ruf über alle Charaktere verfolgen."
L["CONFIG_MOD_ITEMS"] = "Gegenstände"
L["CONFIG_MOD_ITEMS_DESC"] = "Gegenstände in Taschen und Banken verfolgen."
L["CONFIG_MOD_STORAGE"] = "Lager"
L["CONFIG_MOD_STORAGE_DESC"] = "Lager-Tab für Inventar- und Bankverwaltung."
L["CONFIG_MOD_PVE"] = "PvE"
L["CONFIG_MOD_PVE_DESC"] = "Große Schatzkammer, Mythisch+ und Schlachtzug-Sperren verfolgen."
L["CONFIG_MOD_PLANS"] = "Pläne"
L["CONFIG_MOD_PLANS_DESC"] = "Sammlungsplan-Verfolgung und Abschlussziele."
L["CONFIG_MOD_PROFESSIONS"] = "Berufe"
L["CONFIG_MOD_PROFESSIONS_DESC"] = "Berufsfertigkeiten, Rezepte und Konzentration verfolgen."
L["CONFIG_AUTOMATION"] = "Automatisierung"
L["CONFIG_AUTOMATION_DESC"] = "Steuern, was automatisch passiert, wenn du deine Kriegsmeute-Bank öffnest."
L["CONFIG_AUTO_OPTIMIZE"] = "Datenbank automatisch optimieren"
L["CONFIG_AUTO_OPTIMIZE_DESC"] = "Datenbank beim Einloggen automatisch optimieren, um Speicher effizient zu halten."
L["CONFIG_SHOW_ITEM_COUNT"] = "Gegenstandsanzahl anzeigen"
L["CONFIG_SHOW_ITEM_COUNT_DESC"] = "Tooltips mit Gegenstandsanzahl anzeigen (wie viele von jedem Gegenstand du über alle Charaktere hast)."
L["CONFIG_THEME_COLOR"] = "Haupt-Akzentfarbe"
L["CONFIG_THEME_COLOR_DESC"] = "Primäre Akzentfarbe für die Addon-UI wählen."
L["CONFIG_THEME_PRESETS"] = "Design-Voreinstellungen"
L["CONFIG_THEME_APPLIED"] = "%s Design angewendet!"
L["CONFIG_THEME_RESET_DESC"] = "Alle Designfarben auf das Standard-Lila-Design zurücksetzen."
L["CONFIG_NOTIFICATIONS"] = "Benachrichtigungen"
L["CONFIG_NOTIFICATIONS_DESC"] = "Konfigurieren, welche Benachrichtigungen erscheinen."
L["CONFIG_ENABLE_NOTIFICATIONS"] = "Benachrichtigungen aktivieren"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "Popup-Benachrichtigungen für Sammel-Ereignisse anzeigen."
L["CONFIG_NOTIFY_MOUNTS"] = "Reittier-Benachrichtigungen"
L["CONFIG_NOTIFY_MOUNTS_DESC"] = "Benachrichtigungen anzeigen, wenn du ein neues Reittier lernst."
L["CONFIG_NOTIFY_PETS"] = "Haustier-Benachrichtigungen"
L["CONFIG_NOTIFY_PETS_DESC"] = "Benachrichtigungen anzeigen, wenn du ein neues Haustier lernst."
L["CONFIG_NOTIFY_TOYS"] = "Spielzeug-Benachrichtigungen"
L["CONFIG_NOTIFY_TOYS_DESC"] = "Benachrichtigungen anzeigen, wenn du ein neues Spielzeug lernst."
L["CONFIG_NOTIFY_ACHIEVEMENTS"] = "Erfolgs-Benachrichtigungen"
L["CONFIG_NOTIFY_ACHIEVEMENTS_DESC"] = "Benachrichtigungen anzeigen, wenn du einen Erfolg erreichst."
L["CONFIG_SHOW_UPDATE_NOTES"] = "Update-Hinweise erneut anzeigen"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "'Was ist neu'-Fenster beim nächsten Einloggen anzeigen."
L["CONFIG_UPDATE_NOTES_SHOWN"] = "Update-Benachrichtigung wird beim nächsten Einloggen angezeigt."
L["CONFIG_RESET_PLANS"] = "Abgeschlossene Pläne zurücksetzen"
L["CONFIG_RESET_PLANS_CONFIRM"] = "Dies entfernt alle abgeschlossenen Pläne. Fortfahren?"
L["CONFIG_RESET_PLANS_FORMAT"] = "%d abgeschlossene(r) Plan/Pläne entfernt."
L["CONFIG_NO_COMPLETED_PLANS"] = "Keine abgeschlossenen Pläne zum Entfernen."
L["CONFIG_TAB_FILTERING"] = "Tab-Filterung"
L["CONFIG_TAB_FILTERING_DESC"] = "Wählen, welche Tabs im Hauptfenster sichtbar sind."
L["CONFIG_CHARACTER_MGMT"] = "Charakterverwaltung"
L["CONFIG_CHARACTER_MGMT_DESC"] = "Verfolgte Charaktere verwalten und alte Daten entfernen."
L["CONFIG_DELETE_CHAR"] = "Charakterdaten löschen"
L["CONFIG_DELETE_CHAR_DESC"] = "Alle gespeicherten Daten des ausgewählten Charakters dauerhaft entfernen."
L["CONFIG_DELETE_CONFIRM"] = "Bist du sicher, dass du alle Daten dieses Charakters dauerhaft löschen möchtest? Dies kann nicht rückgängig gemacht werden."
L["CONFIG_DELETE_SUCCESS"] = "Charakterdaten gelöscht:"
L["CONFIG_DELETE_FAILED"] = "Charakterdaten nicht gefunden."
L["CONFIG_FONT_SCALING"] = "Schrift & Skalierung"
L["CONFIG_FONT_SCALING_DESC"] = "Schriftfamilie und Größen-Skalierung anpassen."
L["CONFIG_FONT_FAMILY"] = "Schriftfamilie"
L["CONFIG_FONT_SIZE"] = "Schriftgrößen-Skalierung"
L["CONFIG_FONT_PREVIEW"] = "Vorschau: The quick brown fox jumps over the lazy dog"
L["CONFIG_ADVANCED"] = "Erweitert"
L["CONFIG_ADVANCED_DESC"] = "Erweiterte Einstellungen und Datenbankverwaltung. Mit Vorsicht verwenden!"
L["CONFIG_DEBUG_MODE"] = "Debug-Modus"
L["CONFIG_DEBUG_MODE_DESC"] = "Ausführliche Protokollierung für Debug-Zwecke aktivieren. Nur bei Fehlersuche aktivieren."
L["CONFIG_DB_STATS"] = "Datenbankstatistiken anzeigen"
L["CONFIG_DB_STATS_DESC"] = "Aktuelle Datenbankgröße und Optimierungsstatistiken anzeigen."
L["CONFIG_DB_OPTIMIZER_NA"] = "Datenbank-Optimierer nicht geladen"
L["CONFIG_OPTIMIZE_NOW"] = "Datenbank jetzt optimieren"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "Datenbank-Optimierer ausführen, um gespeicherte Daten zu bereinigen und zu komprimieren."
L["CONFIG_COMMANDS_HEADER"] = "Slash-Befehle"
L["DISPLAY_SETTINGS"] = "Anzeige"
L["DISPLAY_SETTINGS_DESC"] = "Anpassen, wie Gegenstände und Informationen angezeigt werden."
L["RESET_DEFAULT"] = "Standard wiederherstellen"
L["ANTI_ALIASING"] = "Kantenglättung"
L["PROFESSIONS_INFO_DESC"] = "Verfolge Berufsfertigkeiten, Konzentration, Wissen und Spezialisierungsbäume über alle Charaktere. Enthält Recipe Companion für Reagenzienquellen."
L["CONTRIBUTORS_TITLE"] = "Mitwirkende"
L["ANTI_ALIASING_DESC"] = "Schriftkanten-Rendering (beeinflusst Lesbarkeit)"

-- =============================================
-- Recipe Companion
-- =============================================
L["RECIPE_COMPANION_TITLE"] = "Rezeptbegleiter"
L["TOGGLE_TRACKER"] = "Tracker umschalten"

-- =============================================
-- Sorting
-- =============================================
L["SORT_BY_LABEL"] = "Sortieren nach:"
L["SORT_MODE_MANUAL"] = "Manuell (Eigene Reihenfolge)"
L["SORT_MODE_NAME"] = "Name (A-Z)"
L["SORT_MODE_LEVEL"] = "Stufe (Höchste)"
L["SORT_MODE_ILVL"] = "Gegenstandsstufe (Höchste)"
L["SORT_MODE_GOLD"] = "Gold (Höchstes)"
