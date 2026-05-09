--[[
    Warband Nexus - German Localization (deDE)
    
    German translations for Warband Nexus.
    
    NOTE: Many strings use Blizzard's built-in GlobalStrings for automatic localization!
    Examples:
    - CLOSE, SETTINGS, REFRESH, SEARCH → Blizzard globals
    - ITEM_QUALITY0_DESC through ITEM_QUALITY7_DESC → Quality names (Poor, Common, Rare, etc.)
    - BAG_FILTER_* → Category names (Equipment, Consumables, etc.)
    - CHARACTER, STATISTICS, LOCATION_COLON → Tooltip strings
    
    These strings are automatically localized by WoW in all supported languages.
    Custom strings (Warband Nexus specific) are translated here.
]]

local ADDON_NAME, ns = ...

---@class WarbandNexusLocale
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "deDE")
if not L then return end

-- General
L["ADDON_NAME"] = "Kriegerschar-Nexus"
-- Slash Commands
L["KEYBINDING"] = "Tastenkürzel"
L["KEYBINDING_UNBOUND"] = "Nicht belegt"
L["KEYBINDING_PRESS_KEY"] = "Taste drücken..."
L["KEYBINDING_TOOLTIP"] = "Klicken, um eine Taste für Warband Nexus zuzuweisen.\nESC zum Abbrechen."
L["KEYBINDING_CLEAR"] = "Tastenkürzel entfernen"
L["KEYBINDING_SAVED"] = "Tastenkürzel gespeichert."
L["KEYBINDING_COMBAT"] = "Tastenkürzel können im Kampf nicht geändert werden."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Allgemeine Einstellungen"
-- enUS fallback (new keys; translate when ready)
L["SETTINGS_SECTION_GENERAL_FEATURES"] = "Features"
L["SETTINGS_SECTION_GENERAL_CONTROLS"] = "Controls & scaling"
L["SETTINGS_SECTION_MODULES_LIST"] = "Enabled modules"
L["SETTINGS_SECTION_VAULT_GENERAL"] = "Shortcut behavior"
L["SETTINGS_SECTION_VAULT_LOOK"] = "Look & opacity"
L["SETTINGS_SECTION_TAB_WARBAND"] = "Warband Bank"
L["SETTINGS_SECTION_TAB_PERSONAL_BANK"] = "Personal Bank"
L["SETTINGS_SECTION_TAB_INVENTORY"] = "Inventory"
L["SETTINGS_SECTION_NOTIF_TIMING"] = "Timing"
L["SETTINGS_SECTION_NOTIF_POSITION"] = "Position"
L["DEBUG_MODE"] = "Debug-Protokollierung"
L["DEBUG_MODE_DESC"] = "Ausführliche Debug-Nachrichten im Chat für Fehlersuche ausgeben"
L["DEBUG_TRYCOUNTER_LOOT"] = "Versuchen Sie Counter Loot Debug"
L["DEBUG_TRYCOUNTER_LOOT_DESC"] = "Nur Loot-Fluss protokollieren (LOOT_OPENED, Quellenauflösung, Zonen-Fallback). Rep-/Währungs-Cache-Logs werden unterdrückt."

-- Options Panel - Scanning

-- Options Panel - Deposit

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Anzeige"
L["DISPLAY_SETTINGS_DESC"] = "Anpassen, wie Gegenstände und Informationen angezeigt werden."
L["SHOW_ITEM_COUNT"] = "Gegenstandsanzahl anzeigen"

-- Options Panel - Tabs

-- Scanner Module

-- Banker Module

-- Warband Bank Operations

-- UI Module
L["SEARCH_CATEGORY_FORMAT"] = "%s durchsuchen..."

-- Main Tabs (Blizzard Globals where available)
L["TAB_STORAGE"] = "Lager"
L["TAB_PLANS"] = "Zu erledigen"
L["TAB_REPUTATIONS"] = "Rufe"
L["TAB_CURRENCIES"] = "Währungen"
L["TAB_PVE"] = "PvE"
-- Characters Tab
L["HEADER_CURRENT_CHARACTER"] = "AKTUELLER CHARAKTER"
L["HEADER_WARBAND_GOLD"] = "KRIEGSMEUTE-GOLD"
L["HEADER_TOTAL_GOLD"] = "GOLD GESAMT"

-- Items Tab
L["ITEMS_HEADER"] = "Bank-Gegenstände"
L["ITEMS_WARBAND_BANK"] = "Kriegsmeute-Bank"

-- Storage Tab
L["STORAGE_HEADER"] = "Lager-Browser"
L["STORAGE_HEADER_DESC"] = "Alle Gegenstände nach Typ organisiert durchsuchen"
L["STORAGE_WARBAND_BANK"] = "Kriegsmeute-Bank"

-- Plans Tab
L["COLLECTION_PLANS"] = "Aufgabenliste"
L["SEARCH_PLANS"] = "Pläne suchen..."
L["SHOW_COMPLETED"] = "Abgeschlossene anzeigen"
L["SHOW_PLANNED"] = "Geplante anzeigen"
L["SHOW_PLANNED_DISABLED_HERE"] = "Wird in der To-Do-Liste und beim wöchentlichen Fortschritt nicht verwendet. Öffne Reittiere, Begleiter, Spielzeug oder eine andere Durchsuchen-Registerkarte, um diesen Filter zu nutzen."

-- Plans Categories (Blizzard Globals where available)
L["ACHIEVEMENT_SERIES"] = "Achievement-Serie"
L["LOADING_ACHIEVEMENTS"] = "Achievements werden geladen..."
L["CATEGORY_MY_PLANS"] = "To-Do-Liste"
L["CATEGORY_DAILY_TASKS"] = "Wöchentlicher Fortschritt"
L["CATEGORY_ILLUSIONS"] = "Illusionen"

-- Reputation Tab

-- Currency Tab

-- PvE Tab

-- Statistics
-- Tooltips
L["TOOLTIP_WARBAND_BANK"] = "Kriegsmeute-Bank"
L["CHARACTER_INVENTORY"] = "Inventar"
L["CHARACTER_BANK"] = "Persönliche Bank"

-- Try Counter
L["SET_TRY_COUNT"] = "Versuche festlegen"
L["TRY_COUNT_CLICK_HINT"] = "Klicken, um die Versuchszahl zu bearbeiten."
L["TRIES"] = "Versuche"
L["COLLECTION_LIST_ATTEMPTS_FMT"] = "%d Versuche"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "Reset-Zyklus festlegen"
L["DAILY_RESET"] = "Täglicher Reset"
L["WEEKLY_RESET"] = "Wöchentlicher Reset"
L["NONE_DISABLE"] = "Keiner (Deaktivieren)"
L["RESET_CYCLE_LABEL"] = "Reset-Zyklus:"
L["RESET_NONE"] = "Keiner"

-- Error Messages

-- Confirmation Dialogs

-- Update Notification
L["WHATS_NEW"] = "Neuigkeiten"
L["GOT_IT"] = "Verstanden!"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "ERFOLGSPUNKTE"
L["MOUNTS_COLLECTED"] = "REITTIERE GESAMMELT"
L["BATTLE_PETS"] = "KAMPFHAUSTIERE"
L["UNIQUE_PETS"] = "EINZIGARTIGE HAUSTIERE"
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
L["CLICK_TO_DISMISS"] = "Klicken zum Schließen"
L["TRACKED"] = "Verfolgt"
L["TRACK"] = "Verfolgen"
L["TRACK_BLIZZARD_OBJECTIVES"] = "In Blizzard-Zielen verfolgen (max. 10)"
L["NO_REQUIREMENTS"] = "Keine Voraussetzungen (sofort abgeschlossen)"

-- Plans UI
L["NO_ACTIVE_CONTENT"] = "Kein aktiver Inhalt diese Woche"
L["UNKNOWN_QUEST"] = "Unbekannte Quest"
L["CURRENT_PROGRESS"] = "Aktueller Fortschritt"
L["QUEST_TYPES"] = "Questtypen:"
L["WORK_IN_PROGRESS"] = "In Arbeit"
L["RECIPE_BROWSER"] = "Rezept-Browser"
L["TRY_ADJUSTING_SEARCH"] = "Versuche, deine Suche oder Filter anzupassen."
L["ALL_COLLECTED_CATEGORY"] = "Alle %ss gesammelt!"
L["COLLECTED_EVERYTHING"] = "Du hast alles in dieser Kategorie gesammelt!"
L["PROGRESS_LABEL"] = "Fortschritt:"
L["REQUIREMENTS_LABEL"] = "Voraussetzungen:"
L["INFORMATION_LABEL"] = "Informationen:"
L["DESCRIPTION_LABEL"] = "Beschreibung:"
L["REWARD_LABEL"] = "Belohnung:"
L["DETAILS_LABEL"] = "Einzelheiten:"
L["COST_LABEL"] = "Kosten:"
L["LOCATION_LABEL"] = "Ort:"
L["TITLE_LABEL"] = "Titel:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "Du hast bereits alle Erfolge in dieser Kategorie abgeschlossen!"
L["DAILY_PLAN_EXISTS"] = "Täglicher Plan existiert bereits"
L["WEEKLY_PLAN_EXISTS"] = "Wöchentlicher Plan existiert bereits"

L["YOUR_CHARACTERS"] = "Deine Charaktere"
L["CHARACTERS_TRACKED_FORMAT"] = "%d Charaktere verfolgt"
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
L["POINTS_SHORT"] = " Pkt."
L["TRACKING_ACTIVE_DESC"] = "Datenerfassung und Aktualisierungen sind aktiv."
L["TRACKING_ENABLED"] = "Verfolgung AKTIVIERT"
L["DELETE_CHARACTER_TITLE"] = "Charakter löschen?"
L["THIS_CHARACTER"] = "diesen Charakter"
L["DELETE_CHARACTER"] = "Ausgewählten Charakter löschen"
L["REMOVE_FROM_TRACKING_FORMAT"] = "%s aus der Verfolgung entfernen"
L["CLICK_TO_DELETE"] = "Klicken zum Löschen"
L["CONFIRM_DELETE"] = "Bist du sicher, dass du |cff00ccff%s|r löschen möchtest?"
L["CANNOT_UNDO"] = "Diese Aktion kann nicht rückgängig gemacht werden!"

-- Empty state cards (SharedWidgets EMPTY_STATE_CONFIG)
L["EMPTY_CHARACTERS_TITLE"] = "Keine Charaktere gefunden"
L["EMPTY_CHARACTERS_DESC"] = "Melde dich mit deinen Charakteren an, um sie zu verfolgen.\nCharakterdaten werden bei jedem Login automatisch erfasst."
L["EMPTY_ITEMS_TITLE"] = "Keine Gegenstände zwischengespeichert"
L["EMPTY_ITEMS_DESC"] = "Öffne deine Kriegsmeute-Bank oder persönliche Bank, um Gegenstände zu scannen.\nGegenstände werden beim ersten Besuch automatisch zwischengespeichert."
L["EMPTY_INVENTORY_TITLE"] = "Keine Gegenstände im Inventar"
L["EMPTY_INVENTORY_DESC"] = "Deine Inventartaschen sind leer."
L["EMPTY_PERSONAL_BANK_TITLE"] = "Keine Gegenstände in der persönlichen Bank"
L["EMPTY_PERSONAL_BANK_DESC"] = "Öffne deine persönliche Bank, um Gegenstände zu scannen.\nGegenstände werden beim ersten Besuch automatisch zwischengespeichert."
L["EMPTY_WARBAND_BANK_TITLE"] = "Keine Gegenstände in der Kriegsmeute-Bank"
L["EMPTY_WARBAND_BANK_DESC"] = "Öffne die Kriegsmeute-Bank, um Gegenstände zu scannen.\nGegenstände werden beim ersten Besuch automatisch zwischengespeichert."
L["EMPTY_GUILD_BANK_TITLE"] = "Keine Gegenstände in der Gildenbank"
L["EMPTY_GUILD_BANK_DESC"] = "Öffne die Gildenbank, um Gegenstände zu scannen.\nGegenstände werden beim ersten Besuch automatisch zwischengespeichert."
L["EMPTY_STORAGE_TITLE"] = "Keine Lagerdaten"
L["EMPTY_STORAGE_DESC"] = "Gegenstände werden gescannt, wenn du Banken oder Taschen öffnest.\nBesuche eine Bank, um dein Lager zu verfolgen."
L["EMPTY_PLANS_TITLE"] = "Noch keine Pläne"
L["EMPTY_PLANS_DESC"] = "Durchsuche oben Reittiere, Haustiere, Spielzeuge oder Erfolge,\num Sammlungsziele hinzuzufügen und deinen Fortschritt zu verfolgen."
L["EMPTY_REPUTATION_TITLE"] = "Keine Rufdaten"
L["EMPTY_REPUTATION_DESC"] = "Rufstände werden beim Login automatisch gescannt.\nMelde dich mit einem Charakter an, um Fraktionsruf zu verfolgen."
L["EMPTY_CURRENCY_TITLE"] = "Keine Währungsdaten"
L["EMPTY_CURRENCY_DESC"] = "Währungen werden automatisch über deine Charaktere hinweg verfolgt.\nMelde dich mit einem Charakter an, um Währungen zu verfolgen."
L["EMPTY_PVE_TITLE"] = "Keine PvE-Daten"
L["EMPTY_PVE_DESC"] = "PvE-Fortschritt wird erfasst, wenn du dich mit deinen Charaktern einloggst.\nGroße Schatzkammer, Mythisch+ und Raid-Sperren erscheinen hier."
L["EMPTY_STATISTICS_TITLE"] = "Keine Statistiken verfügbar"
L["EMPTY_STATISTICS_DESC"] = "Statistiken werden von deinen verfolgten Charakteren gesammelt.\nMelde dich mit einem Charakter an, um Daten zu erfassen."
L["COLLECTIONS_COMING_SOON_TITLE"] = "Demnächst"
L["COLLECTIONS_COMING_SOON_DESC"] = "Die Sammlungsübersicht (Reittiere, Haustiere, Spielzeuge, Transmog) wird hier verfügbar sein."

L["PERSONAL_ITEMS"] = "Persönliche Gegenstände"
L["ITEMS_SUBTITLE"] = "Durchsuche deine Kriegsmeute-Bank, Gildenbank und persönliche Gegenstände"
L["ITEMS_DISABLED_TITLE"] = "Kriegsmeute-Bank Gegenstände"
L["ITEMS_LOADING"] = "Lade Inventardaten"
L["GUILD_BANK_REQUIRED"] = "Du musst in einer Gilde sein, um auf die Gildenbank zuzugreifen."
L["GUILD_JOINED_FORMAT"] = "Gilde aktualisiert: %s"
L["GUILD_LEFT"] = "Du bist nicht mehr in einer Gilde. Gildenbank-Tab deaktiviert."
L["NOT_IN_GUILD"] = "Nicht in Gilde"
L["ITEMS_SEARCH"] = "Gegenstände suchen..."
L["NEVER"] = "Nie"
L["ITEM_FALLBACK_FORMAT"] = "Gegenstand %s"
L["ITEM_LOADING_NAME"] = "Laden..."
L["TAB_FORMAT"] = "Tab %d"
L["BAG_FORMAT"] = "Tasche %d"
L["BANK_BAG_FORMAT"] = "Banktasche %d"
L["ITEM_ID_LABEL"] = "Gegenstands-ID:"
L["STACK_LABEL"] = "Stapel:"
L["RIGHT_CLICK_MOVE"] = "In Tasche verschieben"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Stapel teilen"
L["LEFT_CLICK_PICKUP"] = "Aufnehmen"
L["ITEMS_BANK_NOT_OPEN"] = "Bank nicht geöffnet"
L["SHIFT_LEFT_CLICK_LINK"] = "Im Chat verlinken"
L["ITEMS_STATS_ITEMS"] = "%s Gegenstände"
L["ITEMS_STATS_SLOTS"] = "%s/%s Plätze"
L["ITEMS_STATS_LAST"] = "Zuletzt: %s"

L["STORAGE_DISABLED_TITLE"] = "Charakter-Lager"
L["STORAGE_SEARCH"] = "Lager durchsuchen..."

L["PVE_TITLE"] = "PvE-Fortschritt"
L["PVE_SUBTITLE"] = "Große Schatzkammer, Schlachtzug-Sperrungen & Mythic+ deiner Kriegsmeute"
L["LV_FORMAT"] = "Stufe %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_WORLD"] = "Welt"
L["VAULT_SLOT_FORMAT"] = "%s Platz %d"
L["OVERALL_SCORE_LABEL"] = "Gesamtwertung:"
L["NOT_COMPLETED_SEASON"] = "Diese Saison nicht abgeschlossen"
L["LOADING_PVE"] = "Lade PvE-Daten..."
L["PVE_VAULT_TRACKER_SUBTITLE"] = "Nicht eingelöste Belohnungen und erledigte Schatzkammer-Zeilen"
L["PVE_VAULT_TRACKER_EMPTY_TITLE"] = "Noch keine Schatzkammer-Zeilen"
L["PVE_VAULT_TRACKER_EMPTY_DESC"] = "Kein verfolgter Charakter hat gespeicherten Wochenfortschritt der Schatzkammer (nichts einzulösen oder als erledigt).\nMelde dich mit jedem Charakter an oder deaktiviere den Tracker für die volle PvE-Übersicht."
L["NO_VAULT_DATA"] = "Keine Schatzkammer-Daten"
L["NO_DATA"] = "Keine Daten"
L["KEYSTONE"] = "Schlüsselstein"
L["NO_KEY"] = "Kein Schlüssel"
L["AFFIXES"] = "Affixe"
L["NO_AFFIXES"] = "Keine Affixe"
L["VAULT_BEST_KEY"] = "Bester Schlüssel:"
L["VAULT_SCORE"] = "Wertung:"

-- Vault Tooltip (detailed)
L["VAULT_COMPLETED_ACTIVITIES"] = "Abgeschlossen"
L["VAULT_CLICK_TO_OPEN"] = "Zum Öffnen des Großen Gewölbes klicken"
L["VAULT_TRACKER_CARD_CLICK_HINT"] = "Zum Öffnen des Großen Gewölbes klicken"
L["VAULT_REWARD"] = "Belohnung"
L["VAULT_DUNGEONS"] = "Dungeons"
L["VAULT_BOSS_KILLS"] = "Bosskills"
L["VAULT_WORLD_ACTIVITIES"] = "Weltaktivitäten"
L["VAULT_ACTIVITIES"] = "Aktivitäten"
L["VAULT_REMAINING_SUFFIX"] = "verbleibend"

-- Delves Section (PvE Tab)
L["BOUNTIFUL_DELVE"] = "Truhenjäger-Beute"
L["PVE_BOUNTY_NEED_LOGIN"] = "Kein gespeicherter Status für diesen Charakter. Einloggen zum Aktualisieren."
L["SEASON"] = "Saison"
L["CURRENCY_LABEL_WEEKLY"] = "Wöchentlich"

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
L["REP_CYCLES_COLON"] = "Zyklen:"
L["REP_CHARACTER_PROGRESS"] = "Charakter-Fortschritt:"
L["REP_RENOWN_FORMAT"] = "Ruhm %d"
L["REP_PARAGON_FORMAT"] = "Paragon (%s)"
L["REP_UNKNOWN_FACTION"] = "Unbekannte Fraktion"
L["REP_API_UNAVAILABLE_TITLE"] = "Ruf-API nicht verfügbar"
L["REP_API_UNAVAILABLE_DESC"] = "Die C_Reputation API ist auf diesem Server nicht verfügbar. Dieses Feature erfordert WoW 12.0.5 (Midnight)."
L["REP_FOOTER_TITLE"] = "Ruf-Verfolgung"
L["REP_FOOTER_DESC"] = "Rufe werden automatisch beim Login und bei Änderungen gescannt. Verwende das Ruf-Fenster im Spiel für detaillierte Informationen und Belohnungen."
L["REP_CLEARING_CACHE"] = "Cache wird geleert und neu geladen..."
L["REP_MAX"] = "Max."
L["ACCOUNT_WIDE_LABEL"] = "Accountweit"
L["NO_RESULTS"] = "Keine Ergebnisse"
L["NO_ACCOUNT_WIDE_REPS"] = "Keine accountweiten Rufe"
L["NO_CHARACTER_REPS"] = "Keine charakterbasierten Rufe"

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

L["REMOVE_COMPLETED_TOOLTIP"] = "Entferne alle abgeschlossenen Pläne aus deiner Meine-Pläne-Liste. Diese Aktion kann nicht rückgängig gemacht werden!"
L["RECIPE_BROWSER_DESC"] = "Öffne dein Berufsfenster im Spiel, um Rezepte zu durchsuchen.\nDas Addon scannt verfügbare Rezepte, wenn das Fenster geöffnet ist."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "%s |cff00ff00[%s %s]|r"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s hat bereits einen aktiven Wochenplan für die Schatzkammer. Du findest ihn in der Kategorie 'Meine Pläne'."
L["DAILY_PLAN_EXISTS_DESC"] = "%s hat bereits einen aktiven täglichen Questplan. Du findest ihn in der Kategorie 'Tägliche Aufgaben'."
L["TRANSMOG_WIP_DESC"] = "Transmogrifikations-Sammlung wird derzeit entwickelt.\n\nDieses Feature wird in einem zukünftigen Update mit verbesserter\nLeistung und besserer Integration mit Kriegsmeute-Systemen verfügbar sein."
L["WEEKLY_VAULT_CARD"] = "Wöchentliche Schatzkammer-Karte"
L["WEEKLY_VAULT_COMPLETE"] = "Wöchentliche Schatzkammer-Karte - Abgeschlossen"
L["UNKNOWN_SOURCE"] = "Unbekannte Quelle"
L["DAILY_TASKS_PREFIX"] = "Wöchentlicher Fortschritt - "
L["PLANS_COUNT_FORMAT"] = "%d Pläne"
L["QUEST_LABEL"] = "Suche:"

L["CURRENT_LANGUAGE"] = "Aktuelle Sprache:"
L["LANGUAGE_TOOLTIP"] = "Das Addon verwendet automatisch die Sprache deines WoW-Clients. Um sie zu ändern, aktualisiere deine Battle.net-Einstellungen."
L["SET_POSITION"] = "Position festlegen"
L["DRAG_TO_POSITION"] = "Ziehen zum Positionieren\nRechtsklick zum Bestätigen"
L["RESET_DEFAULT"] = "Standard wiederherstellen"
L["CUSTOM_COLOR"] = "Eigene Farbe"
L["OPEN_COLOR_PICKER"] = "Farbwähler öffnen"
L["COLOR_PICKER_TOOLTIP"] = "Öffne WoWs nativen Farbwähler, um eine eigene Themenfarbe zu wählen"
L["PRESET_THEMES"] = "Voreingestellte Themen"
L["WARBAND_NEXUS_SETTINGS"] = "Warband Nexus Einstellungen"
L["NO_OPTIONS"] = "Keine Optionen"
L["TAB_FILTERING"] = "Tab-Filterung"
L["SCROLL_SPEED"] = "Scrollgeschwindigkeit"
L["ANCHOR_FORMAT"] = "Anker: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "Wochenplaner (Charaktere)"
L["LOCK_MINIMAP_ICON"] = "Minimap-Symbol sperren"
L["BACKPACK_LABEL"] = "Rucksack"
L["REAGENT_LABEL"] = "Reagenzien"

L["MODULE_DISABLED"] = "Modul deaktiviert"
L["LOADING"] = "Laden..."
L["PLEASE_WAIT"] = "Bitte warten..."
L["RESET_PREFIX"] = "Zurücksetzen:"
L["SAVE"] = "Speichern"
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

L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Stufe %d"
L["PREPARING"] = "Vorbereitung"

L["ACCOUNT_STATISTICS"] = "Account-Statistiken"
L["STATISTICS_SUBTITLE"] = "Sammlungsfortschritt, Gold und Lagerübersicht"
L["MOST_PLAYED"] = "MEISTGESPIELT"
L["PLAYED_DAYS"] = "Tage"
L["PLAYED_HOURS"] = "Stunden"
L["PLAYED_MINUTES"] = "Minuten"
L["PLAYED_DAY"] = "Tag"
L["PLAYED_HOUR"] = "Stunde"
L["PLAYED_MINUTE"] = "Min."
L["MORE_CHARACTERS"] = "weiterer Charakter"
L["MORE_CHARACTERS_PLURAL"] = "weitere Charaktere"

L["WELCOME_TITLE"] = "Willkommen bei Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "AddOn-Übersicht"
L["PLANS_SUBTITLE_TEXT"] = "Verfolge deine wöchentlichen Ziele & Sammlungen"
L["ACTIVE_PLAN_FORMAT"] = "%d aktiver Plan"
L["ACTIVE_PLANS_FORMAT"] = "%d aktive Pläne"
-- Plans - Type Names (Using Blizzard Globals where available)
L["TYPE_RECIPE"] = "Rezept"
L["TYPE_ILLUSION"] = "Illusion"
L["TYPE_TITLE"] = "Titel"
L["TYPE_CUSTOM"] = "Eigene"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals)
L["SOURCE_TYPE_TRADING_POST"] = "Handelsposten"
L["SOURCE_TYPE_TREASURE"] = "Schatz"
L["SOURCE_TYPE_PUZZLE"] = "Rätsel"
L["SOURCE_TYPE_RENOWN"] = "Ruhm"
-- Plans - Source Text Parsing Keywords
L["PARSE_SOLD_BY"] = "Verkauft von"
L["PARSE_CRAFTED"] = "Hergestellt"
L["PARSE_COST"] = "Kosten"
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
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "Vom Erfolg"
-- Plans - Fallback Labels
L["FALLBACK_UNKNOWN_PET"] = "Unbekanntes Haustier"
L["FALLBACK_PET_COLLECTION"] = "Haustiersammlung"
L["FALLBACK_TOY_COLLECTION"] = "Spielzeugsammlung"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Transmog-Sammlung"
L["FALLBACK_PLAYER_TITLE"] = "Spielertitel"
L["FALLBACK_ILLUSION_FORMAT"] = "Illusion %s"
L["SOURCE_ENCHANTING"] = "Verzauberkunst"

-- Plans - Dialogs
L["RESET_COMPLETED_CONFIRM"] = "Möchtest du wirklich ALLE abgeschlossenen Pläne entfernen?\n\nDies kann nicht rückgängig gemacht werden!"
L["YES_RESET"] = "Ja, zurücksetzen"
L["REMOVED_PLANS_FORMAT"] = "%d abgeschlossene(n) Plan/Pläne entfernt."

-- Plans - Buttons
L["ADD_CUSTOM"] = "Eigenen hinzufügen"
L["ADD_VAULT"] = "Schatzkammer hinzufügen"
L["ADD_QUEST"] = "Quest hinzufügen"
L["CREATE_PLAN"] = "Plan erstellen"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "Täglich"
L["QUEST_CAT_WORLD"] = "Welt"
L["QUEST_CAT_WEEKLY"] = "Wöchentlich"
L["QUEST_CAT_CONTENT_EVENTS"] = "Inhaltsereignis"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Unbekannte Kategorie"
L["SCANNING_FORMAT"] = "%s wird gescannt"
L["CUSTOM_PLAN_SOURCE"] = "Eigener Plan"
L["POINTS_FORMAT"] = "%d Punkte"
L["SOURCE_NOT_AVAILABLE"] = "Quellinformation nicht verfügbar"
L["PROGRESS_ON_FORMAT"] = "Du bist bei %d/%d im Fortschritt"
L["COMPLETED_REQ_FORMAT"] = "Du hast %d von %d Anforderungen abgeschlossen"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Mitternacht"
L["WEEKLY_RESET_LABEL"] = "Wöchentlicher Reset"
L["QUEST_TYPE_WEEKLY"] = "Wöchentliche Quests"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "Mythisch+"
L["FACTION_LABEL"] = "Fraktion:"
L["FRIENDSHIP_LABEL"] = "Freundschaft"
L["RENOWN_TYPE_LABEL"] = "Ruhm"
L["ADD_BUTTON"] = "+ Hinzufügen"
L["ADDED_LABEL"] = "Hinzugefügt"
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s von %s (%s%%)"

L["SHOW_ITEM_COUNT_TOOLTIP"] = "Stapelanzahl auf Gegenständen in der Lager- und Gegenstandsansicht anzeigen"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Wochenplaner-Bereich im Charaktere-Tab anzeigen oder ausblenden"
L["LOCK_MINIMAP_TOOLTIP"] = "Minimap-Symbol fixieren (verhindert Verschieben)"
L["SCROLL_SPEED_TOOLTIP"] = "Multiplikator für Scrollgeschwindigkeit (1.0x = 28 px pro Schritt)"
L["UI_SCALE"] = "UI-Skalierung"
L["UI_SCALE_TOOLTIP"] = "Skaliert das gesamte Addon-Fenster. Verringern Sie den Wert, wenn das Fenster zu viel Platz einnimmt."

L["IGNORE_WARBAND_TAB_FORMAT"] = "Tab %d ignorieren"
L["IGNORE_SCAN_FORMAT"] = "%s vom automatischen Scannen ausschließen"

L["ENABLE_NOTIFICATIONS"] = "Alle Benachrichtigungen aktivieren"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Hauptschalter — deaktiviert alle Popup-Benachrichtigungen, Chat-Hinweise und visuelle Effekte unten"
L["VAULT_REMINDER"] = "Weekly Vault Erinnerung"
L["VAULT_REMINDER_TOOLTIP"] = "Erinnerung beim Login anzeigen, wenn du nicht abgeholte Schatzkammer-Belohnungen hast"
L["LOOT_ALERTS"] = "Reittier-/Haustier-/Spielzeug-Beute-Hinweise"
L["LOOT_ALERTS_TOOLTIP"] = "Popup anzeigen, wenn ein NEUES Reittier, Haustier, Spielzeug oder Erfolg in deine Sammlung kommt."
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
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Erfolgs-Popup ersetzen"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Blizzards Standard-Erfolgspopup durch den Warband Nexus Benachrichtigungsstil ersetzen"
L["REPUTATION_GAINS"] = "Rufgewinne anzeigen"
L["REPUTATION_GAINS_TOOLTIP"] = "Rufgewinn-Nachrichten im Chat anzeigen, wenn du Fraktionsstand erreichst."
L["CURRENCY_GAINS"] = "Währungsgewinne anzeigen"
L["CURRENCY_GAINS_TOOLTIP"] = "Währungsgewinn-Nachrichten im Chat anzeigen, wenn du Währungen gewinnst."
L["SCREEN_FLASH_EFFECT"] = "Bildschirmblitz bei seltener Beute"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Bildschirmblitz-Animation abspielen, wenn du ein Sammelstück nach mehreren Versuchen endlich erhältst"
L["AUTO_TRY_COUNTER"] = "Auto-Track Drop-Versuche"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Fehlgeschlagene Drop-Versuche automatisch zählen beim Plündern von NPCs, Seltenen, Bossen, Angeln oder Behältern. Zeigt Gesamtversuchszahl im Popup, wenn das Sammelstück endlich droppt."
L["SETTINGS_ESC_HINT"] = "|cff999999ESC|r drücken, um dieses Fenster zu schließen."
L["HIDE_TRY_COUNTER_CHAT"] = "Versuche im Chat ausblenden"
L["HIDE_TRY_COUNTER_CHAT_TOOLTIP"] = "Blendet alle Try-Counter-Chatzeilen aus ([WN-Counter], [WN-Drops], erhalten/geangelt). Die Zählung läuft weiter; Popups und Bildschirmblitz bleiben.\n\nWenn aktiv, sind die Optionen für Instanz-Drop-Zeilen und Chat-Routing unten deaktiviert."
L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES"] = "Instanz-Eintrag: Drops im Chat auflisten"
L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES_TOOLTIP"] = "Beim Betreten einer Instanz mit Try-Counter: pro Item eine |cff9370DB[WN-Drops]|r-Zeile — Sammel-Link, benötigte Schwierigkeit (|cff00ff00grün|r passt, |cffff6666rot|r falsch, |cffffaa00bernstein|r unklar), Versuche oder „gesammelt“. Max. 18 Zeilen, danach |cff00ccff/wn check|r. Aus = nur kurzer Hinweis."
L["DURATION_LABEL"] = "Dauer"
L["DAYS_LABEL"] = "Tage"
L["WEEKS_LABEL"] = "Wochen"
L["EXTEND_DURATION"] = "Dauer verlängern"

L["DRAG_POSITION_MSG"] = "Ziehe den grünen Rahmen, um die Popup-Position festzulegen. Rechtsklick zum Bestätigen."
L["POSITION_RESET_MSG"] = "Popup-Position auf Standard zurückgesetzt (Oben Mitte)"
L["POSITION_SAVED_MSG"] = "Popup-Position gespeichert!"
L["TEST_NOTIFICATION_TITLE"] = "Test-Benachrichtigung"
L["TEST_NOTIFICATION_MSG"] = "Positionstest"
L["NOTIFICATION_DEFAULT_TITLE"] = "Benachrichtigung"

L["THEME_APPEARANCE"] = "Design & Erscheinungsbild"
L["SETTINGS_SECTION_THEME_COLORS"] = "Colors & accent"
L["SETTINGS_SECTION_THEME_TYPOGRAPHY"] = "Fonts & readability"
L["COLOR_PURPLE"] = "Lila-Design"
L["COLOR_PURPLE_DESC"] = "Klassisches Lila-Design (Standard)"
L["COLOR_BLUE"] = "Blau-Design"
L["COLOR_BLUE_DESC"] = "Kühles Blau-Design"
L["COLOR_GREEN"] = "Grün-Design"
L["COLOR_GREEN_DESC"] = "Natur-Grün-Design"
L["COLOR_RED"] = "Rot-Design"
L["COLOR_RED_DESC"] = "Feuriges Rot-Design"
L["COLOR_ORANGE"] = "Orange-Design"
L["COLOR_ORANGE_DESC"] = "Warmes Orange-Design"
L["COLOR_CYAN"] = "Cyan-Design"
L["COLOR_CYAN_DESC"] = "Helles Cyan-Design"
L["USE_CLASS_COLOR_ACCENT"] = "Use class color as accent" -- fallback enUS
L["USE_CLASS_COLOR_ACCENT_TOOLTIP"] = "Use your current character's class color for accents, borders, and tabs. Falls back to your saved theme color when the class cannot be resolved." -- fallback enUS

L["FONT_FAMILY"] = "Schriftfamilie"
L["FONT_FAMILY_TOOLTIP"] = "Schriftart für die gesamte Addon-Oberfläche wählen"
L["FONT_SCALE"] = "Schriftgröße"
L["FONT_SCALE_TOOLTIP"] = "Schriftgröße über alle UI-Elemente anpassen."
L["ANTI_ALIASING"] = "Kantenglättung"
L["ANTI_ALIASING_DESC"] = "Schriftkanten-Rendering (beeinflusst Lesbarkeit)"
L["FONT_SCALE_WARNING"] = "Warnung: Größere Schriftskalierung kann in manchen UI-Elementen zu Textüberlauf führen."
L["RESOLUTION_NORMALIZATION"] = "Auflösungsnormalisierung"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Schriftgrößen basierend auf Bildschirmauflösung und UI-Skalierung anpassen für konsistente physische Größe auf verschiedenen Displays"

L["ADVANCED_SECTION"] = "Erweitert"

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
L["MODULE_PLANS"] = "Zu erledigen"
L["MODULE_PLANS_DESC"] = "Verfolge persönliche Ziele für Reittiere, Haustiere, Spielzeuge, Erfolge und eigene Aufgaben"
L["MODULE_PROFESSIONS"] = "Berufe"
L["MODULE_PROFESSIONS_DESC"] = "Verfolge Berufsskills, Konzentration, Wissen und Rezeptbegleiter-Fenster"
L["PROFESSIONS_DISABLED_TITLE"] = "Berufe"

L["ITEM_NUMBER_FORMAT"] = "Gegenstand #%s"
L["WN_SEARCH"] = "WN Suche"

L["COLLECTED_MOUNT_MSG"] = "Du hast ein Reittier gesammelt"
L["COLLECTED_PET_MSG"] = "Du hast ein Kampfhaustier gesammelt"
L["COLLECTED_TOY_MSG"] = "Du hast ein Spielzeug gesammelt"
L["COLLECTED_ILLUSION_MSG"] = "Du hast eine Illusion gesammelt"
L["COLLECTED_ITEM_MSG"] = "Du hast einen seltenen Drop erhalten"
L["ACHIEVEMENT_COMPLETED_MSG"] = "Erfolg abgeschlossen!"
L["HIDDEN_ACHIEVEMENT"] = "Versteckter Erfolg"
L["EARNED_TITLE_MSG"] = "Du hast einen Titel erhalten"
L["COMPLETED_PLAN_MSG"] = "Du hast einen Plan abgeschlossen"
L["DAILY_QUEST_CAT"] = "Tagesquest"
L["WORLD_QUEST_CAT"] = "Weltquest"
L["WEEKLY_QUEST_CAT"] = "Wochenquest"
L["SPECIAL_ASSIGNMENT_CAT"] = "Spezialauftrag"
L["DELVE_CAT"] = "Tiefe"
L["WORLD_CAT"] = "Welt"
L["ACTIVITY_CAT"] = "Aktivität"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Fortschritt"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Fortschritt abgeschlossen"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Wöchentlicher Schatzkammer-Plan - %s"
L["ALL_SLOTS_COMPLETE"] = "Alle Plätze abgeschlossen!"
L["QUEST_COMPLETED_SUFFIX"] = "Abgeschlossen"
L["WEEKLY_VAULT_READY"] = "Wöchentliche Schatzkammer bereit!"
L["VAULT_LOOT_READY_SHORT"] = "Bereit!"
L["VAULT_TRACK_WAITING_RESET"] = "Warte auf Reset"
L["VAULT_TRACK_WAITING_RESET_SHORT"] = "Zurücksetzen"
L["VAULT_SUMMARY_ALL_TITLE"] = "Große Schatzkammer — alle Charaktere"
L["VAULT_SUMMARY_ALL_SUB"] = "Raid · M+ · Welt entsprechen den PvE-Spalten."
L["VAULT_SUMMARY_COL_NAME"] = "Charakter"
L["VAULT_SUMMARY_COL_REALM"] = "Reich"
L["VAULT_SUMMARY_NO_CHARS"] = "Keine verfolgten Charaktere."
L["VAULT_SUMMARY_MORE"] = "… und %d weitere (PvE-Liste)."
L["UNCLAIMED_REWARDS"] = "Du hast nicht abgeholte Belohnungen"

L["TOTAL_GOLD_LABEL"] = "Gold gesamt:"
L["LEFT_CLICK_TOGGLE"] = "Linksklick: Fenster ein-/ausblenden"
L["RIGHT_CLICK_PLANS"] = "Rechtsklick: Pläne öffnen"
L["MINIMAP_SHOWN_MSG"] = "Minimap-Schaltfläche angezeigt"
L["MINIMAP_HIDDEN_MSG"] = "Minimap-Schaltfläche ausgeblendet (unter Warband Nexus → Einstellungen → Minimap wieder aktivieren)."
L["TOGGLE_WINDOW"] = "Fenster umschalten"
L["SCAN_BANK_MENU"] = "Bank scannen"
L["TRACKING_DISABLED_SCAN_MSG"] = "Charakterverfolgung ist deaktiviert. Aktiviere die Verfolgung in den Einstellungen, um die Bank zu scannen."
L["SCAN_COMPLETE_MSG"] = "Scan abgeschlossen!"
L["BANK_NOT_OPEN_MSG"] = "Bank ist nicht geöffnet"
L["OPTIONS_MENU"] = "Optionen"
L["HIDE_MINIMAP_BUTTON"] = "Minimap-Schaltfläche ausblenden"
L["MENU_UNAVAILABLE_MSG"] = "Rechtsklick-Menü nicht verfügbar"
L["USE_COMMANDS_MSG"] = "Verwende /wn show, /wn options, /wn help"

L["DATA_SOURCE_TITLE"] = "Datenquelleninformation"
L["DATA_SOURCE_USING"] = "Dieser Tab verwendet:"
L["DATA_SOURCE_MODERN"] = "Moderner Cache-Dienst (eventgesteuert)"
L["DATA_SOURCE_LEGACY"] = "Alter direkter DB-Zugriff"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Benötigt Migration zum Cache-Dienst"
L["GLOBAL_DB_VERSION"] = "Globale DB-Version:"

L["INFO_TAB_CHARACTERS"] = "Charaktere"
L["INFO_TAB_ITEMS"] = "Gegenstände"
L["INFO_TAB_STORAGE"] = "Lager"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "Rufe"
L["INFO_TAB_CURRENCY"] = "Währung"
L["INFO_TAB_PLANS"] = "Zu erledigen"
L["INFO_TAB_GEAR"] = "Ausrüstung"
L["INFO_TAB_COLLECTIONS"] = "Sammlungen"
L["INFO_TAB_STATISTICS"] = "Statistiken"
L["GEAR_DESC"] = "Ausgerüstete Items, Upgrade-Optionen, Lager-Empfehlungen (BoE/Warbound) und Upgrade-Kandidaten über Charaktere."
L["COLLECTIONS_DESC"] = "Übersicht Reittiere, Haustiere, Spielzeuge, Transmog. Sammlungsfortschritt und fehlende Items finden."
L["INFO_CREDITS_SECTION_TITLE"] = "Danksagungen"
L["INFO_CREDITS_LORE_SUBTITLE"] = "Besonderer Dank"
L["INFO_FEATURES_SECTION_TITLE"] = "Funktionsübersicht"
L["HEADER_INFO_TOOLTIP"] = "Anleitung & Danksagungen"
L["HEADER_INFO_TOOLTIP_HINT"] = "Funktionen und Mitwirkende — Danksagungen stehen oben."
L["CONTRIBUTORS_TITLE"] = "Mitwirkende"
L["THANK_YOU_MSG"] = "Vielen Dank, dass du Warband Nexus verwendest!"
L["INFO_TAB_PROFESSIONS"] = "Berufe"
L["PROFESSIONS_INFO_DESC"] = "Verfolge Berufsfertigkeiten, Konzentration, Wissen und Spezialisierungsbäume über alle Charaktere. Enthält Recipe Companion für Reagenzienquellen."

L["AVAILABLE_COMMANDS"] = "Verfügbare Befehle:"
L["CMD_OPEN"] = "Addon-Fenster öffnen"
L["CMD_PLANS"] = "To-Do-Tracker-Fenster umschalten"
L["CMD_OPTIONS"] = "Einstellungen öffnen"
L["CMD_MINIMAP"] = "Minimap-Schaltfläche umschalten"
L["CMD_CHANGELOG"] = "Änderungsprotokoll anzeigen"
L["CMD_DEBUG"] = "Debug-Modus umschalten"
L["CMD_PROFILER"] = "Performance-Profiler"
L["CMD_HELP"] = "Diese Liste anzeigen"
L["PLANS_NOT_AVAILABLE"] = "Pläne-Tracker nicht verfügbar."
L["MINIMAP_NOT_AVAILABLE"] = "Minimap-Schaltflächen-Modul nicht geladen."
L["PROFILER_NOT_LOADED"] = "Profiler-Modul nicht geladen."
L["UNKNOWN_COMMAND"] = "Unbekannter Befehl."
L["TYPE_HELP"] = "Tippe"
L["FOR_AVAILABLE_COMMANDS"] = "für verfügbare Befehle."
L["UNKNOWN_DEBUG_CMD"] = "Unbekannter Debug-Befehl:"
L["DEBUG_ENABLED"] = "Debug-Modus AKTIVIERT."
L["DEBUG_DISABLED"] = "Debug-Modus DEAKTIVIERT."
L["CHARACTER_LABEL"] = "Charakter:"
L["TRACK_USAGE"] = "Verwendung: enable | disable | status"

L["CLICK_TO_COPY"] = "Klicken zum Kopieren des Einladungslinks"
L["WELCOME_MSG_FORMAT"] = "Willkommen bei Warband Nexus v%s"
L["WELCOME_TYPE_CMD"] = "Bitte tippe"
L["WELCOME_OPEN_INTERFACE"] = "um die Oberfläche zu öffnen."


-- What's New (only CHANGELOG_V<x><y><z> for current ADDON_VERSION — see NotificationManager.VersionToChangelogKey)

-- What's New / changelog body for ADDON_VERSION 2.6.4 (key CHANGELOG_V264)
L["CHANGELOG_V264"] = [=[v2.6.4 (2026-04-26)

- Ashes of Belo'ren and L'ura references updated.
- Less delay when the Characters, Gear, and PvE tabs refresh their data.
- Bug fixes and small improvements.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.6.3 (key CHANGELOG_V263)
L["CHANGELOG_V263"] = [=[v2.6.3 (2026-04-21)

PvE cache & SavedVariables
- Character keys are normalized (GetCanonicalCharacterKey) on every PvE cache read/write so each character uses one SV bucket — migration, import, and live updates no longer split the same toon across different key spellings.
- Mythic+ dungeon scores: avoid wiping good SavedVariables when the API returns overall 0 with no per-map data while SV still has progress; per-map merge keeps prior rows when the API snapshot is all zeros.
- Great Vault: empty/nil C_WeeklyRewards.GetActivities() does not overwrite persisted vault data (wait for server / open Great Vault).
- Import from legacy/migration: skip destructive mythic, vault, or lockout writes when the incoming snapshot is empty but existing cache still has rows.
- Keystone: only clear stored key when the API reports level 0; nil map/level during API races does not wipe a cached key.
- MYTHIC_PLUS_CURRENT_AFFIX_UPDATE: refresh affixes; prune keystones by weekly reset timestamp only (no blanket wipe of all characters' keys).
- PLAYER_LOGOUT: persist cache without running a full PvE refresh (logout APIs often return empty/zero).

Debug (Config → Debug Mode)
- Optional chat diagnostics prefixed |cff00ccff[PvE Cache]|r: dungeon score save/skip, keystone decisions, Great Vault API empty vs saved, ImportLegacy branches, and bestRuns overall score line (parallel to dungeonScores).

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.6.2 (key CHANGELOG_V262)
L["CHANGELOG_V262"] = [=[v2.6.2 (2026-04-21)

Currency & chat
- Fixed WN-Currency chat queue (FIFO with table.remove) so rapid lines are not dropped.
- Dawncrest / split currencies: fewer duplicate notifications when bag quantity and totalEarned update on different ticks; short defer when useful.
- Block internal Blizzard currency labels (Delves / System / Seasonal Affix / Events Active|Maximum, etc.) from WN-Currency; validate meta names on live API as well.
- Login: suppress WN-Currency notifications until the first full currency scan completes (stops login CURRENCY_DISPLAY_UPDATE burst from flooding chat).

Reputation
- Removed duplicate WN-Reputation line from companion delta watcher; DB pipeline owns chat.
- Companion XP loot: seed pre standing / renown so level-up and standing lines behave correctly.
- Optional "Reached renown level %d" (locale WN_REPUTATION_RENOWN_LEVEL_UP); renown level-up derived when MAJOR_FACTION events do not fire.

Keybind & settings UI
- Toggle keybind cannot be ESC; legacy ESC bindings are cleared on load/save (game menu path stays reliable).
- Settings: dedicated key capture (clear, combat-blocked); main window keyboard is suppressed while Settings is open so movement, chat, and Blizzard keybinding capture keep working.
- Settings root keeps frame keyboard off (large panel no longer steals the global key stack).

ESC & WindowManager
- ToggleGameMenu uses hooksecurefunc only — never replace the global (avoids taint / protected-call failures such as SpellStopCasting).
- Same ESC press no longer closes two layers (addon + game menu); aligns with CloseSpecialWindows / UISpecialFrames for the Settings panel.
- Combat restore no longer forces keyboard back on for the Settings panel.

Weekly Vault / PvE UI (ready state)
- When Great Vault rewards are claimable (live check or cached), Weekly Vault bars on plan cards, the Plans tracker, and the PvE tab show the localized short label (VAULT_LOOT_READY_SHORT) instead of only threshold ticks.
- PvE Dawncrest columns use Constants.DAWNCREST_UI (single source with Gear / currency).

Commands & professions
- /wn keys (party): strip link pipes from aggregated text for Midnight chat rules; use a visible separator between entries when packing lines.
- Profession window: optional "(N)" craft-from-materials count appended to the schematic title after init.

Localization & tooling
- Locale key parity maintained; scripts/check_locales.py for audits.

CurseForge: Warband Nexus]=]


L["CONFIRM_ACTION"] = "Aktion bestätigen"
L["CONFIRM"] = "Bestätigen"
L["ENABLE_TRACKING_FORMAT"] = "Verfolgung für |cffffcc00%s|r aktivieren?"
L["DISABLE_TRACKING_FORMAT"] = "Verfolgung für |cffffcc00%s|r deaktivieren?"

L["REP_SECTION_ACCOUNT_WIDE"] = "Accountweite Rufe (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Charakterbasierte Rufe (%s)"
L["REP_REWARD_WAITING"] = "Belohnung wartet"
L["REP_PARAGON_LABEL"] = "Paragon"

L["REP_LOADING_PREPARING"] = "Vorbereitung..."
L["REP_LOADING_INITIALIZING"] = "Initialisierung..."
L["REP_LOADING_FETCHING"] = "Lade Rufdaten..."
L["REP_LOADING_PROCESSING"] = "Verarbeite %d Fraktionen..."
L["REP_LOADING_SAVING"] = "Speichere in Datenbank..."
L["REP_LOADING_COMPLETE"] = "Fertig!"

L["COMBAT_LOCKDOWN_MSG"] = "Fenster kann im Kampf nicht geöffnet werden. Bitte nach dem Kampf erneut versuchen."
L["BANK_IS_ACTIVE"] = "Bank ist aktiv"


L["NO_ITEMS_MATCH"] = "Keine Gegenstände stimmen mit '%s' überein"
L["NO_ITEMS_MATCH_GENERIC"] = "Keine Gegenstände stimmen mit deiner Suche überein"
L["ITEMS_SCAN_HINT"] = "Gegenstände werden automatisch gescannt. Versuche /reload, wenn nichts erscheint."
L["ITEMS_WARBAND_BANK_HINT"] = "Öffne die Kriegsmeute-Bank, um Gegenstände zu scannen (automatisch beim ersten Besuch)"


L["ADDED"] = "Hinzugefügt"
L["WEEKLY_VAULT_TRACKER"] = "Wöchentlicher Schatzkammer-Tracker"
L["DAILY_QUEST_TRACKER"] = "Täglicher Quest-Tracker"

L["ACHIEVEMENT_NOT_COMPLETED"] = "Nicht abgeschlossen"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d Pkt."
L["ADD_PLAN"] = "Hinzufügen"
L["PLANNED"] = "Geplant"

L["VAULT_SLOT_WORLD"] = "Welt"

L["AFFIX_TITLE_FALLBACK"] = "Affix"
L["WN_REPUTATION_RENOWN_LEVEL_UP"] = "Ruhm-Stufe %d erreicht"


L["PLAN_COMPLETED"] = "Plan abgeschlossen: "
L["WEEKLY_VAULT_PLAN_NAME"] = "Wöchentliche Schatzkammer - %s"
L["VAULT_PLANS_RESET"] = "Wöchentliche Schatzkammer-Pläne wurden zurückgesetzt! (%d Plan%s)"

L["NO_SCAN"] = "Nicht gescannt"
L["NO_ADDITIONAL_INFO"] = "Keine weiteren Informationen"

L["TRACK_CHARACTER_QUESTION"] = "Möchtest du diesen Charakter verfolgen?"
L["CLEANUP_NO_INACTIVE"] = "Keine inaktiven Charaktere gefunden (90+ Tage)"
L["CLEANUP_REMOVED_FORMAT"] = "%d inaktive(n) Charakter(e) entfernt"
L["TRACKING_ENABLED_MSG"] = "Charakterverfolgung AKTIVIERT!"
L["TRACKING_DISABLED_MSG"] = "Charakterverfolgung DEAKTIVIERT!"
L["TRACKING_DISABLED"] = "Verfolgung DEAKTIVIERT (Nur-Lesen-Modus)"
L["STATUS_LABEL"] = "Status:"
L["ERROR_LABEL"] = "Fehler:"
L["ERROR_NAME_REALM_REQUIRED"] = "Charaktername und Realm erforderlich"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s hat bereits einen aktiven Wochenplan"

-- Profiles (AceDB)

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "Keine Kriterien gefunden"
L["NO_REQUIREMENTS_INSTANT"] = "Keine Anforderungen (sofortiger Abschluss)"

L["TAB_PROFESSIONS"] = "Berufe"
L["YOUR_PROFESSIONS"] = "Kriegsmeute-Berufe"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s Charaktere mit Berufen"
L["NO_PROFESSIONS_DATA"] = "Noch keine Berufsdaten verfügbar. Öffne dein Berufsfenster (Standard: K) bei jedem Charakter, um Daten zu sammeln."
L["CONCENTRATION"] = "Konzentration"
L["KNOWLEDGE"] = "Wissen"
L["SKILL"] = "Fertigkeit"
L["RECIPES"] = "Rezepte"
L["UNSPENT_POINTS"] = "Unverteilte Punkte"
L["UNSPENT_KNOWLEDGE_TOOLTIP"] = "Unverteilte Wissenspunkte"
L["UNSPENT_KNOWLEDGE_COUNT"] = "%d unverteilte(r) Wissenspunkt(e)"
L["COLLECTIBLE"] = "Sammelbar"
L["RECHARGE"] = "Aufladen"
L["FULL"] = "Voll"
L["PROF_CONCENTRATION_FULL"] = "Voll"
L["PROF_CONCENTRATION_HOURS_REMAINING"] = "%d Stunden"
L["PROF_CONCENTRATION_MINUTES_REMAINING"] = "%d Min."
L["PROF_CONCENTRATION_DAYS_HOURS_MIN"] = "%d T. %d Std. %d Min."
L["PROF_CONCENTRATION_HOURS_MIN"] = "%d Std. %d Min."
L["PROF_CONCENTRATION_MINUTES_ONLY"] = "%d Min."
L["PROF_OPEN_RECIPE"] = "Öffnen"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "Rezeptliste dieses Berufs öffnen"
L["PROF_ONLY_CURRENT_CHAR"] = "Nur für den aktuellen Charakter verfügbar"
L["NO_PROFESSION"] = "Kein Beruf"

-- Professions: Column Headers
L["UNIQUES"] = "Einzigartige"
L["TREATISE"] = "Abhandlung"
L["GATHERING"] = "Sammeln"
L["CATCH_UP"] = "Nachholen"
L["MOXIE"] = "Moxie"
L["COOLDOWNS"] = "Abklingzeiten"

-- Professions: Tooltips & Details

-- Professions: Crafting Orders

-- Professions: Equipment
L["EQUIPMENT"] = "Ausrüstung"
L["TOOL"] = "Werkzeug"
L["ACCESSORY"] = "Zubehör"

L["TRACK_ITEM_DB"] = "Artikel-DB verfolgen"
L["TRACK_ITEM_DB_DESC"] = "Verwalte, welche Sammel-Drops verfolgt werden. Eingebaute Einträge umschalten oder eigene Quellen hinzufügen."
L["MANAGE_ITEMS"] = "Gegenstandsverfolgung"
L["SELECT_ITEM"] = "Gegenstand auswählen"
L["SELECT_ITEM_DESC"] = "Wähle ein Sammelstück zur Verwaltung."
L["SELECT_ITEM_HINT"] = "Wähle oben einen Gegenstand, um Details anzuzeigen."
L["REPEATABLE_LABEL"] = "Wiederholbar"
L["SOURCE_SINGULAR"] = "Quelle"
L["SOURCE_PLURAL"] = "Quellen"
L["UNTRACKED"] = "Nicht verfolgt"
L["CUSTOM_ENTRIES"] = "Eigene Einträge"
L["CURRENT_ENTRIES_LABEL"] = "Aktuell:"
L["NO_CUSTOM_ENTRIES"] = "Keine eigenen Einträge."
L["ITEM_ID_INPUT"] = "Gegenstands-ID"
L["ITEM_ID_INPUT_DESC"] = "Gegenstands-ID zum Verfolgen eingeben."
L["LOOKUP_ITEM"] = "Nachschlagen"
L["LOOKUP_ITEM_DESC"] = "Gegenstandsname und Typ aus ID ermitteln."
L["ITEM_LOOKUP_FAILED"] = "Gegenstand nicht gefunden."
L["SOURCE_TYPE"] = "Quelltyp"
L["SOURCE_TYPE_DESC"] = "NPC oder Objekt."
L["SOURCE_TYPE_NPC"] = "NPC"
L["SOURCE_TYPE_OBJECT"] = "Objekt"
L["SOURCE_ID"] = "Quell-ID"
L["SOURCE_ID_DESC"] = "NPC-ID oder Objekt-ID."
L["REPEATABLE_TOGGLE"] = "Wiederholbar"
L["REPEATABLE_TOGGLE_DESC"] = "Ob dieser Drop bei jedem Sperrzeit mehrmals versucht werden kann."
L["ADD_ENTRY"] = "+ Eintrag hinzufügen"
L["ADD_ENTRY_DESC"] = "Diesen eigenen Drop-Eintrag hinzufügen."
L["ENTRY_ADDED"] = "Eigener Eintrag hinzugefügt."
L["ENTRY_ADD_FAILED"] = "Gegenstands-ID und Quell-ID sind erforderlich."
L["REMOVE_ENTRY"] = "Eigenen Eintrag entfernen"
L["REMOVE_ENTRY_DESC"] = "Wähle einen eigenen Eintrag zum Entfernen."
L["REMOVE_BUTTON"] = "- Ausgewählte entfernen"
L["REMOVE_BUTTON_DESC"] = "Den ausgewählten eigenen Eintrag entfernen."
L["ENTRY_REMOVED"] = "Eintrag entfernt."
L["SOURCE_NAME"] = "Quellenname"
L["SOURCE_NAME_DESC"] = "Optionale Anzeigename für die Quelle (z.B. NPC oder Objektname)."
L["STATISTIC_IDS"] = "Statistik-IDs"
L["STATISTIC_IDS_DESC"] = "Kommagetrennte WoW-Statistik-IDs für Kill-/Drop-Zählung (optional)."
L["MANAGE_BUILTIN"] = "Integrierte Einträge verwalten"
L["MANAGE_BUILTIN_DESC"] = "Integrierte Tracking-Einträge nach Gegenstands-ID suchen und umschalten."
L["SEARCH_BUILTIN"] = "Integrierte nach Gegenstands-ID durchsuchen"
L["SEARCH_BUILTIN_DESC"] = "Gegenstands-ID eingeben, um Quellen in der integrierten Datenbank zu finden."
L["SEARCH_BUTTON"] = "Suchen"
L["CURRENTLY_UNTRACKED"] = "Derzeit nicht verfolgt"
L["ITEM_RESOLVED"] = "Gegenstand aufgelöst: %s (%s)"
L["ACHIEVEMENT"] = "Erfolg"
L["CRITERIA"] = "Kriterien"
L["CUSTOM_PLAN_COMPLETED"] = "Benutzerplan '%s' |cff00ff00abgeschlossen|r"
L["DESCRIPTION"] = "Beschreibung"
L["PARSE_AMOUNT"] = "Menge"
L["PARSE_LOCATION"] = "Standort"
L["SHOWING_X_OF_Y"] = "%d von %d Ergebnissen angezeigt"
L["SOURCE_UNKNOWN"] = "Unbekannt"
L["ZONE_DROP"] = "Zonen-Drop"
L["FISHING"] = "Angeln"
L["CONFIG_RECIPE_COMPANION"] = "Rezeptbegleiter"
L["CONFIG_RECIPE_COMPANION_DESC"] = "Rezeptbegleiter-Fenster neben der Berufe-UI anzeigen (Reagenzienverfügbarkeit pro Charakter)."
L["TRYCOUNTER_DIFFICULTY_SKIP"] = "Übersprungen: %s erfordert %s-Schwierigkeit (aktuell: %s)"
L["TRYCOUNTER_OBTAINED"] = "%s erhalten!"

L["RECIPE_COMPANION_TITLE"] = "Rezeptbegleiter"
L["TOGGLE_TRACKER"] = "Tracker umschalten"
L["SELECT_RECIPE"] = "Rezept auswählen"
L["RECIPE_COMPANION_EMPTY"] = "Wähle ein Rezept, um die Reagenzienverfügbarkeit pro Charakter zu sehen."
L["CRAFTERS_SECTION"] = "Handwerker"
L["TOTAL_REAGENTS"] = "Reagenzien gesamt"

L["DATABASE_UPDATED_MSG"] = "Datenbank auf Version aktualisiert."
L["DATABASE_RELOAD_REQUIRED"] = "Ein einmaliges Neuladen ist erforderlich, um Änderungen anzuwenden."
L["MIGRATION_RESET_COMPLETE"] = "Reset abgeschlossen. Alle Daten werden automatisch neu gescannt."

L["SYNCING_COMPLETE"] = "Synchronisierung abgeschlossen!"
L["SYNCING_LABEL_FORMAT"] = "WN-Synchronisierung: %s"
L["SETTINGS_UI_UNAVAILABLE"] = "Einstellungs-UI nicht verfügbar. Versuche /wn, um das Hauptfenster zu öffnen."

L["TRACKED_LABEL"] = "Verfolgt"
L["TRACKED_DETAILED_LINE1"] = "Vollständige detaillierte Daten"
L["TRACKED_DETAILED_LINE2"] = "Alle Funktionen aktiviert"
L["UNTRACKED_LABEL"] = "Nicht verfolgt"
L["UNTRACKED_VIEWONLY_LINE1"] = "Nur-Lesen-Modus"
L["UNTRACKED_VIEWONLY_LINE2"] = "Nur grundlegende Infos"
L["TRACKING_ENABLED_CHAT"] = "Charakterverfolgung aktiviert. Datenerfassung beginnt."
L["TRACKING_DISABLED_CHAT"] = "Charakterverfolgung deaktiviert. Nur-Lesen-Modus aktiv."
L["TRACKING_NOT_ENABLED_TOOLTIP"] = "Charakterverfolgung ist deaktiviert. Klicke, um den Charaktere-Tab zu öffnen."
L["TRACKING_BADGE_CLICK_HINT"] = "Klicke, um die Verfolgung zu ändern."
L["TRACKING_TAB_LOCKED_TITLE"] = "Charakter wird nicht verfolgt"
L["TRACKING_TAB_LOCKED_DESC"] = "Dieser Tab funktioniert nur für verfolgte Charaktere.\nAktiviere die Verfolgung auf der Charaktere-Seite über das Verfolgungssymbol."
L["OPEN_CHARACTERS_TAB"] = "Charaktere öffnen"
L["TRACKING_BADGE_TRACKING"] = "Verfolgt"
L["TRACKING_BADGE_UNTRACKED"] = "Nicht\nverfolgt"
L["TRACKING_BADGE_BANK"] = "Bank ist\nAktiv"
L["ADDED_TO_FAVORITES"] = "Zu Favoriten hinzugefügt:"
L["REMOVED_FROM_FAVORITES"] = "Aus Favoriten entfernt:"

L["TOOLTIP_ATTEMPTS"] = "Versuche"
L["TOOLTIP_100_DROP"] = "100 % Drop"
L["TOOLTIP_UNKNOWN"] = "Unbekannt"
L["TOOLTIP_HOLD_SHIFT"] = "  [Umschalt] halten für vollständige Liste"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - Konzentration"
L["TOOLTIP_FULL"] = "(Voll)"
L["TOOLTIP_NO_LOOT_UNTIL_RESET"] = "Keine Beute bis zum nächsten Reset"

L["NO_ITEMS_CACHED_TITLE"] = "Keine Gegenstände gespeichert"
L["DB_LABEL"] = "DB:"

L["COLLECTING_PVE"] = "Sammle PvE-Daten"
L["PVE_PREPARING"] = "Vorbereitung"
L["PVE_GREAT_VAULT"] = "Große Schatzkammer"
L["PVE_MYTHIC_SCORES"] = "Mythisch+-Wertungen"
L["PVE_RAID_LOCKOUTS"] = "Schlachtzug-Sperren"
L["PVE_INCOMPLETE_DATA"] = "Einige Daten könnten unvollständig sein. Später erneut aktualisieren."
L["VAULT_SLOTS_TO_FILL"] = "%d Große Schatzkammer-Platz%s zu füllen"
L["VAULT_SLOT_PLURAL"] = "S"
L["REP_RENOWN_NEXT"] = "Ruhm %d"
L["REP_TO_NEXT_FORMAT"] = "%s Ruf bis %s (%s)"
L["REP_FACTION_FALLBACK"] = "Fraktion"
L["COLLECTION_CANCELLED"] = "Sammlung vom Benutzer abgebrochen"
L["PERSONAL_BANK"] = "Persönliche Bank"
L["WARBAND_BANK_LABEL"] = "Kriegsmeute-Bank"
L["WARBAND_BANK_TAB_FORMAT"] = "Tab %d"
L["CURRENCY_OTHER"] = "Andere"

L["STANDING_HATED"] = "Verhasst"
L["STANDING_HOSTILE"] = "Feindselig"
L["STANDING_UNFRIENDLY"] = "Unfreundlich"
L["STANDING_NEUTRAL"] = "Neutral"
L["STANDING_FRIENDLY"] = "Verbündet"
L["STANDING_HONORED"] = "Wohlwollend"
L["STANDING_REVERED"] = "Respektiert"
L["STANDING_EXALTED"] = "Ehrfürchtig"

L["TRYCOUNTER_INCREMENT_CHAT"] = "%d Versuche für %s"
L["TRYCOUNTER_CHAT_OBTAINED_FIRST_LINK"] = "Du hast %s beim ersten Versuch erhalten!"
L["TRYCOUNTER_CHAT_OBTAINED_AFTER_LINK"] = "Du hast %s nach %d Versuchen erhalten!"
L["TRYCOUNTER_CHAT_ATTEMPTS_FOR_LINK"] = "%d Versuche für %s"
L["TRYCOUNTER_CHAT_FIRST_FOR_LINK"] = "Erster Versuch für %s"
L["TRYCOUNTER_CHAT_TAG_CONTAINER"] = "Behälter"
L["TRYCOUNTER_CHAT_TAG_FISHING"] = "Angeln"
L["TRYCOUNTER_CHAT_TAG_RESET"] = "Zähler zurückgesetzt"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d Versuche für %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "%s erhalten! Versuchszähler zurückgesetzt."
L["TRYCOUNTER_WHAT_A_GRIND"] = "Was für eine Quälerei! %d Versuche (erwartete ~%d%% Chance bis jetzt) für %s"
L["TRYCOUNTER_CAUGHT_RESET"] = "%s eingefangen! Versuchszähler zurückgesetzt."
L["TRYCOUNTER_CAUGHT"] = "%s gefangen!"
L["TRYCOUNTER_CONTAINER_RESET"] = "%s aus Behälter erhalten! Versuchszähler zurückgesetzt."
L["TRYCOUNTER_CONTAINER"] = "%s aus Container erhalten!"
L["TRYCOUNTER_LOCKOUT_SKIP"] = "Übersprungen: Tägliche/wöchentliche Sperre für diesen NSC aktiv."
L["TRYCOUNTER_INSTANCE_ENTRY_HINT"] = "In dieser Instanz werden Reittiere im Versuchszähler für deine Schwierigkeit geführt. |cffffffff/wn check|r am Boss (Ziel/Mouseover) zeigt Details."
L["TRYCOUNTER_COLLECTED_TAG"] = "(Gesammelt)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " Versuche"
L["TRYCOUNTER_TRY_COUNTS"] = "Versuchszähler"
L["TRYCOUNTER_PROBE_ENTER"] = "Betreten: %s — Schwierigkeit: %s"
L["TRYCOUNTER_PROBE_DB_HEADER"] = "Mount-Quellen (Try-Counter-DB) — deine Schwierigkeit: %s"
L["TRYCOUNTER_PROBE_MOUNT_LINE"] = "%s > %s > %s > %s"
L["TRYCOUNTER_PROBE_ENC_NO_MOUNTS"] = "%s: Keine Mount-Einträge in der Datenbank"
L["TRYCOUNTER_PROBE_JOURNAL_MISS"] = "Begegnungsjournal für diese Instanz konnte nicht ermittelt werden."
L["TRYCOUNTER_PROBE_NO_MAPPED_BOSSES"] = "Keine Bosse dieser Instanz sind in den Try-Counter-Daten hinterlegt."
L["TRYCOUNTER_PROBE_STATUS_COLLECTED"] = "Bereits gesammelt"
L["TRYCOUNTER_PROBE_STATUS_OBTAINABLE"] = "Auf dieser Schwierigkeit erhältlich"
L["TRYCOUNTER_PROBE_STATUS_WRONG_DIFF"] = "Auf der aktuellen Schwierigkeit nicht verfügbar"
L["TRYCOUNTER_PROBE_STATUS_DIFF_UNKNOWN"] = "Schwierigkeit unbekannt"
L["TRYCOUNTER_PROBE_REQ_ANY"] = "jede Schwierigkeit"
L["TRYCOUNTER_PROBE_REQ_MYTHIC"] = "nur Mythisch"
L["TRYCOUNTER_PROBE_REQ_LFR"] = "nur LFR"
L["TRYCOUNTER_PROBE_REQ_NORMAL_PLUS"] = "Normal+ Raid (nicht LFR)"
L["TRYCOUNTER_PROBE_REQ_HEROIC"] = "Heroisch+ (inkl. Mythisch & 25H)"
L["TRYCOUNTER_PROBE_REQ_25H"] = "nur 25er Heroisch"
L["TRYCOUNTER_PROBE_REQ_10N"] = "nur 10er Normal"
L["TRYCOUNTER_PROBE_REQ_25N"] = "nur 25er Normal"
L["TRYCOUNTER_PROBE_REQ_25MAN"] = "25er Normal oder Heroisch"

L["LT_CHARACTER_DATA"] = "Charakterdaten"
L["LT_CURRENCY_CACHES"] = "Währungen & Caches"
L["LT_REPUTATIONS"] = "Rufe"
L["LT_PROFESSIONS"] = "Berufe"
L["LT_PVE_DATA"] = "PvE-Daten"
L["LT_COLLECTIONS"] = "Sammlungen"
L["LOADING_COLLECTIONS"] = "Sammlungen werden geladen..."
L["SYNC_COMPLETE"] = "Synchronisiert"
L["FILTER_COLLECTED"] = "Gesammelt"
L["FILTER_UNCOLLECTED"] = "Nicht gesammelt"

L["CONFIG_HEADER"] = "Kriegerschar-Nexus"
L["CONFIG_HEADER_DESC"] = "Moderne Kriegsmeute-Verwaltung und übergreifende Charakterverfolgung."
L["CONFIG_GENERAL"] = "Allgemeine Einstellungen"
L["CONFIG_GENERAL_DESC"] = "Grundlegende Addon-Einstellungen und Verhaltensoptionen."
L["CONFIG_ENABLE"] = "Addon aktivieren"
L["CONFIG_ENABLE_DESC"] = "Addon ein- oder ausschalten."
L["CONFIG_MINIMAP"] = "Minimap-Schaltfläche"
L["CONFIG_MINIMAP_DESC"] = "Schaltfläche auf der Minimap für schnellen Zugriff anzeigen."
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "Gegenstände in Tooltips anzeigen"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "Kriegsmeute- und Charakter-Gegenstandsanzahl in Gegenstands-Tooltips anzeigen."
L["CONFIG_MODULES"] = "Modulverwaltung"
L["CONFIG_MODULES_DESC"] = "Einzelne Addon-Module aktivieren oder deaktivieren. Deaktivierte Module sammeln keine Daten und zeigen keine UI-Tabs."
L["CONFIG_MOD_CURRENCIES"] = "Währungen"
L["CONFIG_MOD_CURRENCIES_DESC"] = "Währungen über alle Charaktere verfolgen."
L["CONFIG_MOD_REPUTATIONS"] = "Rufe"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "Rufe über alle Charaktere verfolgen."
L["CONFIG_MOD_ITEMS"] = "Gegenstände"
L["CONFIG_MOD_ITEMS_DESC"] = "Gegenstände in Taschen und Banken verfolgen."
L["CONFIG_MOD_STORAGE"] = "Lager"
L["CONFIG_MOD_STORAGE_DESC"] = "Lager-Tab für Inventar- und Bankverwaltung."
L["CONFIG_MOD_PVE"] = "PvE"
L["CONFIG_MOD_PVE_DESC"] = "Große Schatzkammer, Mythisch+ und Schlachtzug-Sperren verfolgen."
L["CONFIG_MOD_PLANS"] = "Zu erledigen"
L["CONFIG_MOD_PLANS_DESC"] = "Wöchentliche Aufgabenverfolgung, Sammlungsziele und Tresorfortschritt."
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
L["CONFIG_THEME_APPLIED"] = "%s Design angewendet!"
L["CONFIG_THEME_RESET_DESC"] = "Alle Designfarben auf das Standard-Lila-Design zurücksetzen."
L["CONFIG_NOTIFICATIONS"] = "Benachrichtigungen"
L["CONFIG_NOTIFICATIONS_DESC"] = "Konfigurieren, welche Benachrichtigungen erscheinen."
L["CONFIG_ENABLE_NOTIFICATIONS"] = "Benachrichtigungen aktivieren"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "Popup-Benachrichtigungen für Sammel-Ereignisse anzeigen."
L["CONFIG_SHOW_UPDATE_NOTES"] = "Update-Hinweise erneut anzeigen"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "'Was ist neu'-Fenster beim nächsten Einloggen anzeigen."
L["CONFIG_UPDATE_NOTES_SHOWN"] = "Update-Benachrichtigung wird beim nächsten Einloggen angezeigt."
L["CONFIG_RESET_PLANS"] = "Abgeschlossene Pläne zurücksetzen"
L["CONFIG_RESET_PLANS_FORMAT"] = "%d abgeschlossene(r) Plan/Pläne entfernt."
L["CONFIG_TAB_FILTERING"] = "Tab-Filterung"
L["CONFIG_TAB_FILTERING_DESC"] = "Wählen, welche Tabs im Hauptfenster sichtbar sind."
L["CONFIG_CHARACTER_MGMT"] = "Charakterverwaltung"
L["CONFIG_CHARACTER_MGMT_DESC"] = "Verfolgte Charaktere verwalten und alte Daten entfernen."
L["CONFIG_DELETE_CHAR"] = "Charakterdaten löschen"
L["CONFIG_DELETE_CHAR_DESC"] = "Alle gespeicherten Daten des ausgewählten Charakters dauerhaft entfernen."
L["CONFIG_FONT_SCALING"] = "Schrift & Skalierung"
L["CONFIG_FONT_SCALING_DESC"] = "Schriftfamilie und Größen-Skalierung anpassen."
L["CONFIG_FONT_FAMILY"] = "Schriftfamilie"
L["CONFIG_ADVANCED"] = "Erweitert"
L["CONFIG_ADVANCED_DESC"] = "Erweiterte Einstellungen und Datenbankverwaltung. Mit Vorsicht verwenden!"
L["CONFIG_DEBUG_MODE"] = "Debug-Modus"
L["CONFIG_DEBUG_MODE_DESC"] = "Ausführliche Protokollierung für Debug-Zwecke aktivieren. Nur bei Fehlersuche aktivieren."
L["CONFIG_DB_STATS"] = "Datenbankstatistiken anzeigen"
L["CONFIG_DB_STATS_DESC"] = "Aktuelle Datenbankgröße und Optimierungsstatistiken anzeigen."
L["CONFIG_OPTIMIZE_NOW"] = "Datenbank jetzt optimieren"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "Datenbank-Optimierer ausführen, um gespeicherte Daten zu bereinigen und zu komprimieren."
L["CONFIG_COMMANDS_HEADER"] = "Slash-Befehle"

L["SORT_BY_LABEL"] = "Sortieren nach:"
L["SORT_MODE_DEFAULT"] = "Standardreihenfolge"
L["SORT_MODE_MANUAL"] = "Manuell (Eigene Reihenfolge)"
L["SORT_MODE_NAME"] = "Name (A–Z)"
L["SORT_MODE_LEVEL"] = "Stufe (Höchste)"
L["SORT_MODE_ILVL"] = "Gegenstandsstufe (Höchste)"
L["SORT_MODE_GOLD"] = "Gold (Höchstes)"

L["GOLD_MANAGER_BTN"] = "Goldziel"
L["GOLD_MANAGEMENT_TITLE"] = "Goldziel"
L["GOLD_MANAGEMENT_ENABLE"] = "Goldverwaltung aktivieren"
L["GOLD_MANAGEMENT_MODE"] = "Verwaltungsmodus"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "Nur einzahlen"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "Wenn du mehr als X Gold hast, wird der Überschuss automatisch in die Kriegsmeute-Bank eingezahlt."
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "Nur abheben"
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "Wenn du weniger als X Gold hast, wird die Differenz automatisch von der Kriegsmeute-Bank abgehoben."
L["GOLD_MANAGEMENT_MODE_BOTH"] = "Beide"
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "Automatisch genau X Gold auf deinem Charakter beibehalten (einzahlen wenn mehr, abheben wenn weniger)."
L["GOLD_MANAGEMENT_TARGET"] = "Ziel-Goldbetrag"
L["GOLD_MANAGEMENT_HELPER"] = "Gib den Goldbetrag ein, den du auf diesem Charakter behalten möchtest. Das Addon verwaltet dein Gold automatisch, wenn du die Bank öffnest."

-- Full parity with enUS (remaining keys)
L["ACHIEVEMENT_PROGRESS_TITLE"] = "Erfolgsfortschritt"
L["CMD_FIRSTCRAFT"] = "Erstherstellungs-Bonus-Rezepte pro Erweiterung anzeigen (zuerst Beruf öffnen)"
L["COLLECTIONS_SUBTITLE"] = "Reittiere, Begleiter, Spielzeuge und Transmog-Übersicht"
L["COLLECTIONS_SUBTAB_RECENT"] = "Neueste"
L["COLLECTIONS_CONTENT_TITLE_ACHIEVEMENTS"] = "Erfolge"
L["COLLECTIONS_CONTENT_SUB_ACHIEVEMENTS"] = "Durchsuche deine Erfolge."
L["COLLECTIONS_CONTENT_TITLE_MOUNTS"] = "Reittiere"
L["COLLECTIONS_CONTENT_SUB_MOUNTS"] = "Reittiersammlung der Kriegsschar, Quellen und Vorschau."
L["COLLECTIONS_CONTENT_TITLE_PETS"] = "Begleiter"
L["COLLECTIONS_CONTENT_SUB_PETS"] = "Kampfhaustiere und Begleiter deines gesamten Kontos."
L["COLLECTIONS_CONTENT_TITLE_TOYS"] = "Spielzeugkiste"
L["COLLECTIONS_CONTENT_SUB_TOYS"] = "Spielzeuge und nutzbare Sammelobjekte."
L["COLLECTIONS_CONTENT_TITLE_RECENT"] = "Kürzlich erhalten"
L["COLLECTIONS_CONTENT_SUB_RECENT"] = "Neueste Erfolge, Reittiere, Begleiter und Spielzeuge deines Kontos."
L["COLLECTIONS_RECENT_JUST_NOW"] = "Gerade eben"
L["COLLECTIONS_RECENT_MINUTES_AGO"] = "vor %d Min."
L["COLLECTIONS_RECENT_HOURS_AGO"] = "vor %d Std."
L["COLLECTIONS_RECENT_DAYS_AGO"] = "vor %d Tagen"
L["COLLECTIONS_ACQUIRED_LABEL"] = "Erhalten"
L["COLLECTIONS_ACQUIRED_LINE"] = "%s: %s"
L["COLLECTIONS_RECENT_TAB_EMPTY"] = "Noch nichts aufgezeichnet."
L["COLLECTIONS_RECENT_CHARACTER_SUFFIX"] = "|cff888888  ·  %s|r"
L["COLLECTIONS_RECENT_EMPTY"] = "Noch nichts aufgezeichnet."
L["COLLECTIONS_RECENT_SEARCH_EMPTY"] = "Keine passenden Einträge."
L["COLLECTIONS_RECENT_SECTION_NONE"] = "Noch keine Einträge."
L["COLLECTIONS_RECENT_CARD_RESET_TOOLTIP"] = "Letzte Einträge dieser Kategorie löschen"
L["COLLECTIONS_RECENT_TOOLTIP_SECTION_CATEGORY"] = "Kategorie"
L["COLLECTIONS_RECENT_TOOLTIP_SECTION_PROGRESS"] = "Fortschritt"
L["COLLECTIONS_RECENT_TOOLTIP_SECTION_CHARACTER"] = "Charakter"
L["COLLECTIONS_RECENT_TOOLTIP_SECTION_TIME"] = "Erfasst"
L["COLLECTIONS_RECENT_ROW_BY"] = "Von %s"
L["COLLECTIONS_RECENT_ACH_HIDE_ALT_EARNED"] = "Auf dem Konto abgeschlossen, bevor dieser Charakter."
L["CONFIG_DEBUG_VERBOSE"] = "Debug ausführlich (Cache-/Scan-/Tooltip-Logs)"
L["CONFIG_DEBUG_VERBOSE_DESC"] = "Bei aktiviertem Debug-Modus auch Währungs-/Ruf-Cache-, Taschen-Scan-, Tooltip- und Berufs-Logs anzeigen. Aus lassen, um Chat-Spam zu reduzieren."
L["CRITERIA_PROGRESS_CRITERION"] = "Kriterien"
L["CRITERIA_PROGRESS_FORMAT"] = "Fortschritt %d/%d"
L["CRITERIA_PROGRESS_MSG"] = "Fortschritt"
L["DRAG_BOTH_POSITION_MSG"] = "Ziehen zum Positionieren. Rechtsklick speichert dieselbe Position für Benachrichtigung und Kriterien."
L["FALLBACK_TOY_BOX"] = "Spielzeugkiste"
L["FALLBACK_WARBAND_TOY"] = "Kriegsmeute-Spielzeug"
L["FILTER_SHOW_MISSING"] = "Fehlend"
L["FILTER_SHOW_OWNED"] = "Im Besitz"
L["GEAR_STORAGE_BOE"] = "BoE"
L["GEAR_STORAGE_WARBOUND"] = "Kriegsgebunden"
L["GEAR_STORAGE_TITLE"] = "Empfehlungen für Lager-Upgrades"
L["GEAR_STORAGE_EMPTY"] = "Keine besseren BoE- / Warbound-Upgrades für diesen Charakter gefunden."
L["GEAR_STORAGE_EMPTY_NO_BOE_WOE"] = "Keine BoE- oder WoE-Upgrades für Ausrüstungsplätze gefunden."
L["GEAR_SLOT_FALLBACK_FORMAT"] = "Platz %d"
L["GEAR_ITEM_UPGRADE_RECOMMENDATIONS_TITLE"] = "Empfehlungen für Gegenstands-Upgrades"
L["ILVL_SHORT_LABEL"] = "iLvl"
L["GEAR_TAB_DESC"] = "Ausgerüstete Ausrüstung, Upgrade-Optionen und übergreifende Upgrade-Kandidaten"
L["GEAR_TAB_TITLE"] = "Ausrüstungsverwaltung"
L["LT_COLLECTION_DATA"] = "Sammlungsdaten"
L["NOTIFICATION_DURATION"] = "Benachrichtigungsdauer"
L["NOTIFICATION_GHOST_CRITERIA"] = "Kriterien-Fortschritt"
L["NOTIFICATION_GHOST_MAIN"] = "Erfolg / Benachrichtigung"
L["NOTIFICATION_POSITION"] = "Benachrichtigungsposition"
L["PROF_FILTER_ALL"] = "Alle"
L["PROF_FIRSTCRAFT_NO_DATA"] = "Keine Berufsdaten verfügbar."
L["RESET_POSITION"] = "Position zurücksetzen"
L["SELECT_MOUNT_FROM_LIST"] = "Wähle ein Reittier aus der Liste"
L["SELECT_PET_FROM_LIST"] = "Wähle einen Begleiter aus der Liste"
L["SELECT_TO_SEE_DETAILS"] = "Wähle ein(e) %s für Details."
L["SET_BOTH_POSITION"] = "Beide Positionen setzen"
L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS"] = "Kriterien-Fortschritt-Toast"
L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS_TOOLTIP"] = "Kleine Benachrichtigung anzeigen, wenn ein Erfolgskriterium abgeschlossen wird (Fortschritt X/Y und Kriterienname)."
L["SOURCE"] = "Quelle"
L["TAB_COLLECTIONS"] = "Sammlungen"
L["TAB_GEAR"] = "Ausrüstung"
L["TEST_NOTIFICATION"] = "Testbenachrichtigung"
L["USE_ALERTFRAME_POSITION"] = "AlertFrame-Position verwenden"
L["USE_ALERTFRAME_POSITION_ACTIVE"] = "Blizzard-AlertFrame-Position wird verwendet"

-- Missing locale keys filled from enUS fallback
L["MODULE_GEAR"] = "Ausrüstung"
L["MODULE_GEAR_DESC"] = "Ausrüstungsverwaltung und Gegenstandsstufenverfolgung über alle Charaktere"
L["MODULE_COLLECTIONS"] = "Sammlungen"
L["MODULE_COLLECTIONS_DESC"] = "Reittiere, Haustiere, Spielzeuge, Transmog und Sammlungsübersicht"
L["MODULE_TRY_COUNTER"] = "Versuchszähler"
L["MODULE_TRY_COUNTER_DESC"] = "Automatische Zählung von Drop-Versuchen bei NPC-Tötungen, Bossen, Angeln und Behältern. Deaktivierung stoppt alle Try-Count-Verarbeitung, Tooltips und Benachrichtigungen."
L["PROF_EQUIPMENT_HINT"] = "Beruf (K) auf diesem Charakter öffnen, um Ausrüstung zu scannen."
L["PROF_INFO_TOOLTIP"] = "Berufsdetails anzeigen"
L["PROF_INFO_NO_DATA"] = "Keine Berufsdaten verfügbar.\nBitte melde dich mit diesem Charakter an und öffne das Berufsfenster (K), um Daten zu sammeln."
L["PROF_INFO_SKILLS"] = "Erweiterungsfertigkeiten"
L["PROF_INFO_TOOL"] = "Werkzeug"
L["PROF_INFO_ACC1"] = "Zubehör 1"
L["PROF_INFO_ACC2"] = "Zubehör 2"
L["PROF_INFO_KNOWN"] = "Bekannt"
L["PROF_INFO_WEEKLY"] = "Wöchentlicher Wissensfortschritt"
L["PROF_INFO_COOLDOWNS"] = "Abklingzeiten"
L["PROF_INFO_READY"] = "Bereit"
L["PROF_INFO_LAST_UPDATE"] = "Zuletzt aktualisiert"
L["PROF_INFO_LOCKED"] = "Gesperrt"
L["PROF_INFO_UNLEARNED"] = "Ungelernt"
L["NOTIFICATION_FIRST_TRY"] = "Beim ersten Versuch bekommen!"
L["NOTIFICATION_GOT_IT_AFTER"] = "Nach %d Versuchen bekommen!"
L["NOTIFICATION_COLLECTIBLE_CHARACTER_LINE"] = "Charakter: %s"
L["MONEY_LOGS_BTN"] = "Geld-Protokoll"
L["MONEY_LOGS_TITLE"] = "Geld-Protokoll"
L["MONEY_LOGS_SUMMARY_TITLE"] = "Charakterbeiträge"
L["MONEY_LOGS_COLUMN_NET"] = "Netto"
L["MONEY_LOGS_COLUMN_TIME"] = "Zeit"
L["MONEY_LOGS_COLUMN_CHARACTER"] = "Charakter"
L["MONEY_LOGS_COLUMN_TYPE"] = "Typ"
L["MONEY_LOGS_COLUMN_TOFROM"] = "Von / An"
L["MONEY_LOGS_COLUMN_AMOUNT"] = "Betrag"
L["MONEY_LOGS_EMPTY"] = "Noch keine Geldtransaktionen aufgezeichnet."
L["MONEY_LOGS_DEPOSIT"] = "Einzahlung"
L["MONEY_LOGS_WITHDRAW"] = "Abhebung"
L["MONEY_LOGS_TO_WARBAND_BANK"] = "Kriegsmeute-Bank"
L["MONEY_LOGS_FROM_WARBAND_BANK"] = "Von Kriegsmeute-Bank"
L["MONEY_LOGS_RESET"] = "Zurücksetzen"
L["MONEY_LOGS_FILTER_ALL"] = "Alle"
L["MONEY_LOGS_CHAT_DEPOSIT"] = "|cff00ff00Geld-Log:|r %s in die Kriegsmeute-Bank eingezahlt"
L["MONEY_LOGS_CHAT_WITHDRAW"] = "|cffff9900Geld-Log:|r %s von der Kriegsmeute-Bank abgehoben"

-- New keys (session additions)
L["MINIMAP_CHARS_GOLD"] = "Charakter-Gold:"
L["MINIMAP_MORE_FORMAT"] = "... +%d weitere"
L["GEAR_UPGRADE_CURRENCIES"] = "Aufwertungswährungen"
L["GEAR_CHARACTER_STATS"] = "Charakter-Statistiken"
L["GEAR_NO_ITEM_EQUIPPED"] = "Kein Gegenstand in diesem Slot ausgerüstet."
L["GEAR_NO_PREVIEW"] = "Keine Vorschau"
L["GEAR_OFFLINE_BADGE"] = "Offline"
L["GEAR_NO_PREVIEW_HINT"] = "Melde dich mit diesem Charakter an, um die Erscheinungsvorschau zu aktualisieren."
L["GEAR_STATS_CURRENT_ONLY"] = "Statistiken nur für\naktuellen Charakter verfügbar"
L["GEAR_SLOT_RING1"] = "Klingeln 1"
L["GEAR_SLOT_RING2"] = "Ring 2"
L["GEAR_SLOT_TRINKET1"] = "Schmuckstück 1"
L["GEAR_SLOT_TRINKET2"] = "Schmuckstück 2"
    L["GEAR_MISSING_ENCHANT"] = "Fehlende Verzauberung"
    L["GEAR_MISSING_GEM"] = "Fehlender Edelstein"
L["GEAR_UPGRADE_AVAILABLE_FORMAT"] = "Verfügbare Aufwertung auf %s %d/%d%s"
L["GEAR_UPGRADES_WITH_CURRENCY_FORMAT"] = "%d Aufwertung(en) mit aktueller Währung"
L["GEAR_CRESTS_GOLD_ONLY"] = "Abzeichen benötigt: 0 (nur Gold — zuvor erreicht)"
L["GEAR_UPGRADES_GOLD_ONLY_FORMAT"] = "%d Aufwertung(en) nur Gold (zuvor erreicht)"
L["GEAR_NEED_MORE_CRESTS_FORMAT"] = "%s %d/%d — mehr Abzeichen benötigt"
L["WOW_TOKEN_LABEL"] = "WoW-Token"
L["FORMAT_BUTTON"] = "Format"
L["STATS_PLAYED_STEAM_ZERO"] = "0 Stunden"
L["STATS_PLAYED_STEAM_FLOAT"] = "%.1f Stunden"
L["STATS_PLAYED_STEAM_THOUSAND"] = "%d,%03d Stunden"
L["STATS_PLAYED_STEAM_INT"] = "%d Stunden"
L["SHOW_ALL"] = "Alle anzeigen"
L["DISCORD_TOOLTIP"] = "Discord zu Warband Nexus"
L["SOURCE_OTHER"] = "Sonstige"
L["CONTENT_KHAZ_ALGAR"] = "Khaz Algar"
L["CONTENT_DRAGON_ISLES"] = "Dracheninseln"
L["MODULE_DISABLED_DESC_FORMAT"] = "Aktiviere es in %s, um %s zu verwenden."
L["PART_OF_FORMAT"] = "Teil von: %s"
L["LOCKED_WORLD_QUESTS"] = "Gesperrt — schließe Weltquests ab zum Freischalten"
L["QUEST_ID_FORMAT"] = "Quest-ID: %s"
L["GOLD_MANAGEMENT_CHAR_ONLY"] = "Nur für diesen Charakter (%s)"
L["GOLD_MANAGEMENT_CHAR_ONLY_DESC"] = "Separate Goldverwaltungseinstellungen nur für diesen Charakter verwenden. Andere Charaktere verwenden die geteilten Profilsettings."
L["GOLD_MGMT_PROFILE_TITLE"] = "Profil (Alle Charaktere)"
L["GOLD_MGMT_USING_PROFILE"] = "Nutzt Profil"
L["GOLD_MGMT_MODE_SHORT_DEPOSIT"] = "Einzahlen"
L["GOLD_MGMT_MODE_SHORT_WITHDRAW"] = "Abheben"
L["GOLD_MGMT_MODE_SHORT_BOTH"] = "Beides"
L["COMPLETE_LABEL"] = "Abgeschlossen"
L["FIRST_CRAFT"] = "Erstherstellung"
L["COLUMNS_BUTTON"] = "Spalten"
L["HIDE_FILTER_BUTTON"] = "Ausblenden"
L["HIDE_FILTER_LEVEL_80"] = "Stufe 80"
L["HIDE_FILTER_LEVEL_90"] = "Stufe 90"
L["HIDE_FILTER_STATE_OFF"] = "Aus"
L["HIDE_FILTER_TOOLTIP_TOGGLE"] = "Filter umschalten: Stufe 80 / Stufe 90"
L["HIDE_FILTER_TOOLTIP_CURRENT"] = "Aktuell: %s"

-- Reminder / Alert System
L["ALERT_ACTIVE"] = "Alarm aktiv"
L["REMINDER_PREFIX"] = "Erinnerung"
L["REMINDER_DAILY_LOGIN"] = "Täglicher Login"
L["REMINDER_WEEKLY_RESET"] = "Wöchentlicher Reset"
L["REMINDER_DAYS_BEFORE"] = "%d Tage vor dem Zurücksetzen"
L["REMINDER_ZONE_ENTER"] = "%s eingegeben"
L["REMINDER_OPT_DAILY"] = "Erinnern Sie sich an die tägliche Anmeldung"
L["REMINDER_OPT_WEEKLY"] = "Erinnerung nach wöchentlichem Zurücksetzen"
L["REMINDER_OPT_DAYS_BEFORE"] = "Erinnern Sie %d Tage vor dem Zurücksetzen daran"
L["REMINDER_OPT_ZONE"] = "Erinnerung beim Betreten der Quellzone"
L["SET_ALERT"] = "Alarm einstellen"
L["SET_ALERT_TITLE"] = "Alarm einstellen"
L["REMOVE_ALERT"] = "Warnung entfernen"

-- PvE Columns & Crests
L["PVE_COL_COFFER_SHARDS"] = "Truhenscherben"
L["PVE_COL_RESTORED_KEY"] = "Schlüssel wiederhergestellt"
L["PVE_CREST_ADV"] = "Abenteurer"
L["PVE_CREST_CHAMP"] = "Champion"
L["PVE_CREST_HERO"] = "Held"
L["PVE_CREST_MYTH"] = "Mythos"
L["PVE_CREST_EXPLORER"] = "Forscher"
L["PVE_CREST_VET"] = "Veteran"
L["PVE_COL_VAULT_STATUS"] = "Tresorstatus"
L["PVE_COL_NEBULOUS_VOIDCORE"] = "Nebulöser Leerekern"
L["PVE_COL_DAWNLIGHT_MANAFLUX"] = "Morgenlicht-Manaflux"
L["PVE_HEADER_RAID_SHORT"] = "Raid"
L["PVE_HEADER_MAP_SHORT"] = "Karte"
L["PVE_HEADER_STATUS_SHORT"] = "Status"
L["PVE_COMPACT_COFFER_SHARD"] = "Truhenscherbe"
L["PVE_COMPACT_RESTORED"] = "Wiederhergestellt"
L["PVE_COMPACT_VOIDCORE"] = "Leerekern"
L["PVE_COMPACT_MANAFLUX"] = "Manaflux"
L["PVE_CREST_GENERIC"] = "Wappen"
L["VAULT_SLOTS_SHORT_FORMAT"] = "%d Plätze"
L["PVE_VAULT_SLOT_COMPLETE_FORMAT"] = "Platz %d: |cff80ff80✓|r %s"
L["PVE_VAULT_SLOT_PROGRESS_FORMAT"] = "Platz %d: |cffff8888%d/%d|r"
L["PVE_VAULT_SLOT_EMPTY_FORMAT"] = "Platz %d: —"
L["PVE_VAULT_SLOT_UNLOCKED"] = "Freigeschaltet"
L["SHIFT_HINT_SEASON_PROGRESS"] = "Umschalttaste gedrückt halten für Saisonfortschritt"
L["SHIFT_HINT_SEASON_PROGRESS_SHORT"] = "Shift: Saisonfortschritt"

-- Vault Tooltips
L["VAULT_BASED_ON_FORMAT"] = "Die Gegenstandsstufe dieser Belohnung basiert auf der niedrigsten Ihrer %d Top-Läufe in dieser Woche (derzeit %s)."
L["VAULT_COMPLETE_MORE_FORMAT"] = "Schließe diese Woche %d weitere %s ab, um sie freizuschalten."
L["VAULT_COMPLETE_ON"] = "Schließen Sie diese Aktivität am %s ab"
L["VAULT_DELVE_TIER_FORMAT"] = "Stufe %d (%d)"
L["VAULT_ENCOUNTER_LIST_FORMAT"] = "%s"
L["VAULT_IMPROVE_TO"] = "Verbessern"
L["VAULT_RAID_BASED_FORMAT"] = "Belohnung basierend auf dem höchsten besiegten Schwierigkeitsgrad (derzeit %s)."
L["VAULT_SLOT_SA"] = "Aufgaben"
L["VAULT_TOP_RUNS_FORMAT"] = "Top %d Läufe diese Woche"
L["VAULT_UNLOCK_REWARD"] = "Belohnung freischalten"

-- Character / Statistics
L["WARBAND_BANK"] = "Kriegstruppbank"
L["WARBAND_WEALTH"] = "Reichtum der Kriegerschar"

-- Gear Crafting
L["GEAR_CRAFTED_NO_CRESTS"] = "Es sind keine Wappen zum Umgestalten verfügbar"
L["GEAR_TRACK_CRAFTED_FALLBACK"] = "Hergestellt"
L["GEAR_CRAFTED_MAX_ILVL_LINE"] = "%s (max. Gegenstandsstufe %d)"
L["GEAR_CRAFTED_RECAST_TO_LINE"] = "Umwerten auf %s (Gegenstandsstufe %d)"
L["GEAR_DAWNCREST_PLAYBOOK_TITLE"] = "Dawncrest upgrade playbook" -- fallback enUS
L["GEAR_DAWNCREST_PLAYBOOK_SUMMARY"] = "Each upgrade step: %s Dawncrests + gold. Earn via delves, dungeons, Mythic+, and raids — hover header for tier sources." -- fallback enUS
L["GEAR_DAWNCREST_PLAYBOOK_TOOLTIP_LEAD"] = "Item upgrades spend %s Dawncrests per tier step (plus gold) at the upgrade vendor." -- fallback enUS
L["GEAR_DAWNCREST_PLAYBOOK_CAP_HINT"] = "Season and weekly caps apply — amounts are shown on each currency row (Shift: season progress)." -- fallback enUS
L["GEAR_DAWNCREST_PLAYBOOK_BY_TIER"] = "Sources by Dawncrest tier:" -- fallback enUS
L["GEAR_DAWNCREST_PLAYBOOK_NO_SOURCES"] = "Earn via seasonal PvE rewards matching this crest tier." -- fallback enUS
L["GEAR_CRAFTED_COST_DAWNCREST"] = "Kosten: %d %s Dämmerungswappen"
L["GEAR_CRAFTED_NEXT_TIER_CRESTS"] = "%s (Gegenstandsstufe %d): %d/%d Wappen (%d fehlen noch)"

-- Other
L["TRACK_ACTIVITIES"] = "Verfolgen Sie Aktivitäten"

L["SHOW_COMPLETED_HELP"] = "To-Do-Liste und Wöchentlicher Fortschritt: aus = laufende Pläne; an = nur abgeschlossene. Durchsuchen (Reittiere usw.): aus = ungesammelt (nur To-Do wenn Geplant an); an = gesammelte auf der To-Do (Geplant filtert weiter)."
L["SHOW_PLANNED_HELP"] = "Nur Durchsuchen-Register (ausgeblendet in To-Do & Wochenfortschritt): an = nur Einträge auf deiner To-Do. Mit Abgeschlossene aus: noch benötigt; mit Abgeschlossene an: erledigt; beides an: alle geplanten; beides aus: volle ungesammelte Liste."
L["PLANS_ACHIEVEMENTS_EMPTY_TITLE"] = "Keine Erfolge anzuzeigen"
L["PLANS_ACHIEVEMENTS_EMPTY_HINT"] = "Füge Erfolge von dieser Liste zur To-Do hinzu oder ändere Geplant / Abgeschlossene. Die Liste füllt sich beim Scannen; bei Bedarf /reload."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP"] = "|cffccaa00Warband Nexus|r\nKlicken, um diesen Erfolg zur To-Do-Liste hinzuzufügen (wie + Hinzufügen)."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_REMOVE"] = "|cffccaa00Warband Nexus|r\nKlicken, um diesen Erfolg aus der To-Do-Liste zu entfernen."
L["RECENT_TOOLTIP_OBTAINED_BY"] = "Obtained by:" -- fallback enUS
L["RECENT_TOOLTIP_ACHIEVEMENT_EARNED_BY"] = "This achievement was earned by %s" -- fallback enUS
L["RECENT_TOOLTIP_EARNED_BY"] = "Obtained by %s" -- fallback enUS
L["POINTS_LABEL"] = "Points" -- fallback enUS
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_COMBAT"] = "Im Kampf nicht verfügbar."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_COMPLETE"] = "Dieser Erfolg ist bereits abgeschlossen."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_IN_PLANS"] = "Bereits auf der To-Do-Liste."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_TRACKED"] = "Bereits verfolgt (Beobachtungsleiste)."
L["ACHIEVEMENT_FRAME_WN_ALREADY_PLANNED"] = "Bereits auf der To-Do-Liste."
L["ACHIEVEMENT_FRAME_WN_TRACK_FAILED"] = "Erfolg konnte nicht zur Blizzard-Verfolgung hinzugefügt werden (Liste voll oder nicht verfügbar)."
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_TITLE"] = "Nichts anzuzeigen"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_DESC"] = "Keine geplanten Einträge in dieser Kategorie entsprechen den Filtern. Zur To-Do hinzufügen oder Geplant / Abgeschlossene anpassen."
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_TITLE"] = "Keine abgeschlossenen To-Do-Einträge"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_DESC"] = "In dieser Kategorie ist noch nichts auf der To-Do gesammelt oder abgeschlossen. Abgeschlossene aus, um laufende zu sehen."
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_TITLE"] = "Keine laufenden To-Do-Einträge"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_DESC"] = "In dieser Kategorie ist auf der To-Do nichts mehr ungesammelt. Abgeschlossene aktivieren oder Ziele hinzufügen."
L["TRYCOUNTER_CHAT_ROUTE_LABEL"] = "Versuchszähler-Chat-Ausgabe"
L["TRYCOUNTER_CHAT_ROUTE_DESC"] = "Wo Versuchszähler-Zeilen erscheinen. Standard = gleiche Tabs wie Beute. „Warband Nexus“ nutzt die Gruppe WN_TRYCOUNTER (in Chat-Tab-Einstellungen wählbar). „Alle Tabs“ sendet in jedes nummerierte Chatfenster."
L["TRYCOUNTER_CHAT_ROUTE_LOOT"] = "1) Wie Beute (Standard)"
L["TRYCOUNTER_CHAT_ROUTE_DEDICATED"] = "2) Warband Nexus (eigener Filter)"
L["TRYCOUNTER_CHAT_ROUTE_ALL_TABS"] = "3) Alle Standard-Chat-Tabs"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_BTN"] = "Versuchszähler zum gewählten Chat-Tab hinzufügen"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_TOOLTIP"] = "Chat-Tab anklicken, dann hier klicken. Ideal für „Warband Nexus (eigener Filter)“. Fügt die Gruppe WN_TRYCOUNTER zu diesem Tab hinzu."
L["TRYCOUNTER_CHAT_ADD_TO_TAB_OK"] = "|cff9966ff[Warband Nexus]|r Versuchszähler im gewählten Chat-Tab aktiviert."
L["TRYCOUNTER_CHAT_ADD_TO_TAB_FAIL"] = "|cffff6600[Warband Nexus]|r Chat-Tab konnte nicht aktualisiert werden (kein Chat oder API blockiert)."
L["WELCOME_NEW_VERSION_CHAT"] = "|cffffff00Neuigkeiten:|r Es kann ein Popup über dem Chat erscheinen, oder tippe |cffffff00/wn changelog|r."
L["CONFIG_SHOW_LOGIN_CHAT"] = "Login-Nachricht im Chat"
L["CONFIG_SHOW_LOGIN_CHAT_DESC"] = "Kurze Willkommenszeile bei aktivierten Benachrichtigungen. Nutzt die System-Nachrichtengruppe und einen sichtbaren Chat-Tab (z. B. für Chattynator). Das „Was ist neu“-Fenster ist separat (Vollbild-Popup)."
L["CONFIG_HIDE_PLAYED_TIME_CHAT"] = "Spielzeit im Chat ausblenden"
L["CONFIG_HIDE_PLAYED_TIME_CHAT_DESC"] = "Blendet Systemmeldungen zu Gesamtspielzeit und Spielzeit auf dieser Stufe aus. Aus = wieder anzeigen (auch bei /played)."
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN"] = "Spielzeit beim Login abfragen"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN_DESC"] = "Wenn aktiv, fragt das Addon /played im Hintergrund ab („Meist gespielt“ usw.); Chat-Ausgabe wird unterdrückt. Wenn aus, kein automatischer Abruf beim Login (manuelles /played funktioniert)."
L["PROFESSIONS_WIDE_TABLE_HINT"] = "Tipp: Leiste unten oder Umschalt+Mausrad, um alle Spalten zu sehen."

-- Blizzard GlobalStrings (Auto-localized by WoW) [parity sync]
L["BANK_LABEL"] = BANK or "Bank"
L["BTN_SETTINGS"] = SETTINGS
L["CANCEL"] = CANCEL or "Cancel"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Achievements"
L["CATEGORY_ALL"] = ALL or "All Items"
L["CATEGORY_MOUNTS"] = MOUNTS or "Mounts"
L["CATEGORY_PETS"] = PETS or "Pets"
L["CATEGORY_TITLES"] = TITLES or "Titles"
L["CATEGORY_TOYS"] = TOY_BOX or "Toys"
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmog"
L["DELETE"] = DELETE or "Delete"
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "Heroic"
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "Mythic"
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "Normal"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "Dungeon"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Unknown"
L["FIRSTCRAFT"] = PROFESSIONS_FIRST_CRAFT or "First Craft"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
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
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Dungeons"
L["PVE_HEADER_RAIDS"] = RAIDS or "Raids"
L["PVP_TYPE"] = PVP or "PvP"
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
L["PROFESSION_SUMMARY_SLOT_ACCESSORY"] = "Accessoire"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Achievement"
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
L["TAB_CHARACTERS"] = CHARACTER or "Characters"
L["TAB_CURRENCY"] = CURRENCY or "Currency"
L["TAB_ITEMS"] = ITEMS or "Items"
L["TAB_REPUTATION"] = REPUTATION or "Reputation"
L["TAB_STATISTICS"] = STATISTICS or "Statistics"
L["TYPE_MOUNT"] = MOUNT or "Mount"
L["TYPE_PET"] = PET or "Pet"
L["TYPE_TOY"] = TOY or "Toy"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transmog"
L["VAULT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon"
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
L["CLICK_TO_COPY_LINK"] = "Klicken Sie, um den Link zu kopieren"
L["PLAN_CHAT_LINK_TITLE"] = "Chat-Link"
L["PLAN_CHAT_LINK_HINT"] = "Klicken, um in den Chat einzuf�gen"
L["PLAN_CHAT_LINK_UNAVAILABLE"] = "F�r diesen Eintrag ist kein Chat-Link verf�gbar."
L["CLICK_FOR_WOWHEAD_LINK"] = "Klicken Sie hier für den Wowhead-Link"
L["PLAN_ACTION_COMPLETE"] = "Vervollständigen Sie den Plan"
L["PLAN_ACTION_DELETE"] = "Löschen Sie den Plan"
L["OBJECTIVE_INDEX_FORMAT"] = "Ziel %d"
L["QUEST_PROGRESS_FORMAT"] = "Fortschritt: %d/%d (%d%%)"
L["QUEST_TIME_REMAINING_FORMAT"] = "%s übrig"
L["EVENT_GROUP_SOIREE"] = "Saltherils Soiree"
L["EVENT_GROUP_ABUNDANCE"] = "Fülle"
L["EVENT_GROUP_HARANIR"] = "Legenden der Haranir"
L["EVENT_GROUP_STORMARION"] = "Stormarion-Angriff"
L["QUEST_CATEGORY_DESC_WEEKLY"] = "Wöchentliche Ziele, Jagden, Funken, Weltboss, Gewölbe"
L["QUEST_CATEGORY_DESC_WORLD"] = "Zonenweite wiederholbare Weltquests"
L["QUEST_CATEGORY_DESC_DAILY"] = "Täglich wiederholbare Quests von NPCs"
L["QUEST_CATEGORY_DESC_EVENTS"] = "Bonusziele, Aufgaben und Aktivitäten"
L["GEAR_NO_TRACKED_CHARACTERS_TITLE"] = "Keine verfolgten Zeichen"
L["GEAR_NO_TRACKED_CHARACTERS_DESC"] = "Melden Sie sich bei einem Charakter an, um mit der Verfolgung der Ausrüstung zu beginnen."
L["SOURCE_TYPE_CATEGORY_FORMAT"] = "Kategorie %d"
L["TYPE_ITEM"] = ITEM or "Item"
L["CTRL_C_LABEL"] = "Strg+C"
L["WOW_TOKEN_COUNT_LABEL"] = "Token"
L["NOT_AVAILABLE_SHORT"] = "N / A"
L["COLLECTION_RULE_API_NOT_AVAILABLE"] = "API nicht verf�gbar"
L["COLLECTION_RULE_INVALID_MOUNT"] = "Ung�ltiges Reittier"
L["COLLECTION_RULE_FACTION_CLASS_RESTRICTED"] = "Fraktions- oder klassenbeschr�nkt"


-- -----------------------------------------------------------------------------
-- Parity sync from enUS.lua (auto-appended) — 228 keys
-- -----------------------------------------------------------------------------
L["CHANGELOG_V300"] = [=[v3.0.0 (2026-05-09)

Bundled highlights (prior patch notes through 2.7.2)

Saved Instances & lockouts
- Account-wide Saved Instances window: raid + dungeon lockouts, themed Factory scroll, collapse/expand, symmetric header columns, FontManager typography, clearer borders and resize behavior.
- Backend: dungeon rows with difficulty pills; secret-safe raid detection; lockout freshness; collapse persistence; DataService staggered PvE capture aligned with PvECacheService.

Try Counter & sources
- ENCOUNTER_END-driven counting (next-frame schedule); clearer miss/stat paths; rare-farm off-by-one fix; encounter-specific dedup; per-corpse GUID dedup; NEW_MOUNT_ADDED / NEW_PET_ADDED backup; safer multi-event registration.
- CollectibleSourceDB / locale rows for Sylvanas SoD Mythic chest attribution across clients.

Gear, Vault & currencies
- Quick-access menu (Vault Tracker, Saved Instances, Plans, Settings).
- PvE Vault Status column + per-slot vault tooltips; live C_WeeklyRewards.HasAvailableRewards for ready state; alt weekly-reset promotion fixes; Status column width for localized labels.
- Dawncrest crest farming tooltips; Shift-expand currency rows (`<bag> · <earned> / <cap>`); tier-colored upgrade tracks; subtitle hints; `/wn maxonly` (hide alts below level 80).
- Gear paperdoll height/columns; recommendations scrollbar auto-hide; full currency names; Vault Tracker on FontManager; character order from Characters tab; enchant rank glyphs (R1–R3); Voidcore / coffer display fixes.

Plans & Collections
- Achievement Journal circular WN badge (add/remove To-Do), localized.
- Plans Tracker mirrors To-Do: ParseMultipleSources rows, type badges, portrait-aligned info rows, tries/delete alignment, ExpandableRow layout fixes, full achievement body text without MaxLines caps.
- Collections › Recent Obtains: full-height cards, auto-hiding scrollbars, tooltip detail (earned/obtained-by wording); 2.7.2 polish — title/subtitle, per-category reset, labeled tooltip sections, Plans metrics (`UI_PLANS_CARD_METRICS`), Weekly Progress accordion tween + scroll resync, Show Planned always visible (disabled on To-Do/Weekly with tooltip), themed checkbox accent fixes, tighter plan source icons.

Locales
- `SHOW_PLANNED_DISABLED_HERE` and `COLLECTIONS_RECENT_*` for all shipped languages; restored collections strings (koKR / ruRU / zhTW) and mojibake fixes (deDE / es / fr).

Full merged notes: repository CHANGES.md / CHANGES.txt · listing on CurseForge / Wago.

CurseForge: Warband Nexus]=]

L["CHANGELOG_V270"] = [=[v2.7.0 (2026-05-05)

Saved Instances — layout + readability pass
- Reworked the view into a clean header/row structure: `Instance (Difficulty)` with character progress rows directly underneath.
- Added per-group collapse/expand controls with larger chevrons and stable collapse state while the window is open.
- Added fixed right-side columns in headers (character count + progress) for symmetric vertical alignment across all groups.
- Synced row progress formatting with header progress formatting for consistent numeric alignment.

Saved Instances — theme and typography parity
- Header and character rows now use outlined borders (theme-colored) for clearer section boundaries.
- Font rendering now uses the selected addon font through `FontManager` in the Saved Instances surface.
- Theme refresh now re-renders Saved Instances when open, so color/font changes follow the main addon window immediately.

Saved Instances — scrolling + interaction
- Switched to the standardized Factory scrollframe + themed scrollbar column used by the main addon UI.
- Scrollbar visibility now updates automatically based on content size.
- Resizable window behavior was retained and integrated with content/scroll refresh.

CurseForge: Warband Nexus]=]


L["CHANGELOG_V268"] = [=[v2.6.8 (2026-05-04)

Try Counter — architectural overhaul
- Counting is now event-driven by ENCOUNTER_END (next frame instead of a 5-second wait). Chests, personal-loot bags, and post-cinematic loot can be opened seconds, hours, or days later without re-counting or off-by-one.
- Stat-backed miss path now prints "N attempts for [item]" — previously the reseed could complete silently and Sylvanas / LFR Jaina kills produced no try-counter line at all.
- Fixed off-by-one on open-world rare farms: 4 misses followed by a drop on kill 5 now correctly says "after 5 attempts" (was "after 4").
- Fixed encounter fallback being silently suppressed by unrelated tier-token / currency loot (Anima Vessels, etc.) inside the kill window.
- Added definitive NEW_MOUNT_ADDED / NEW_PET_ADDED backup so post-cinematic chest grants always emit the correct obtained line, even when the primary loot-window detection misses.

Sylvanas (Sanctum of Domination, Mythic)
- All client locales now resolve the Sylvanas encounter for Vengeance's Reins try counting. Added a slot-first outcome rule for the Mythic chest so secret-GUID loot is attributed by tracked itemID rather than failing to bind to the kill.

Saved Instances
- Now lists dungeon lockouts alongside raids: 5-player Normal / Heroic / Mythic / M+ rows surface with their own difficulty pills.
- Lockouts are filtered by reset time so expired rows no longer linger; collapse state per instance persists across sessions.
- isRaid is treated as advisory — falls back to DifficultyID + maxPlayers when the value is wrapped or missing in Midnight 12.0 contexts.

Data collection
- Per-character lockouts capture both raid and dungeon entries (matches the cache pipeline) so the Vault button now reflects everything you're saved to.

CurseForge: Warband Nexus]=]


L["CREST_SOURCES_HEADER"] = "Quellen:"
L["CREST_TO_CAP_SUFFIX"] = "bis Saisonobergrenze"
L["GEAR_SECTION_CHARACTER"] = "Charakter"
L["SAVED_INSTANCES_RESET_DAYS"] = "%dT"
L["SAVED_INSTANCES_RESET_HOURS"] = "%dh"
L["SAVED_INSTANCES_RESET_LESS_HOUR"] = "<1h"
L["VAULT_PENDING"] = "Ausstehend…"
L["VAULT_READY_TO_CLAIM"] = "Bereit"
L["VAULT_SLOTS_EARNED"] = "Plätze verdient"

L["CHANGELOG_V267"] = [=[v2.6.7 (2026-04-29)

PvE — Great Vault tracker
- Added Weekly Vault tracker visibility improvements for unclaimed rewards and completed vault rows.
- Claimable Great Vault rewards now show the short "loot ready" status label consistently across PvE and Plans surfaces.

UI — minimap shortcut
- Improved quick access flow through the minimap button and /wn minimap toggle shortcut.

Collections — loot alerts
- Bag scan now checks the permanent notified cache before firing mount, pet, and toy collectible toasts.
- Fixed repeated collectible popups caused by duplicate BAG_UPDATE-driven re-detection.
- Already-notified collectibles now stay silent across reloads and relogs.

Collections — recent list
- Recent obtained entries are now retention-pruned (7 days) so stale rows are cleaned automatically.

CurseForge: Warband Nexus]=]
L["CHANGELOG_V266"] = [=[v2.6.6b (2026-04-28)

Gear tab — Storage Upgrade Recommendations
- Recommendations now respect transferability: only BoE, Warbound, and Warbound-until-equipped items can surface from another character's bags or the Warband Bank. Soulbound items that were once BoE but have since been equipped are filtered out (they cannot be transferred).
- Two-handed main hand suppresses off-hand suggestions: equipping a 2H staff/polearm no longer brings up low-ilvl off-hand "upgrades" against an empty slot.
- Warband-until-Equipped (WuE) items are now correctly identified via the tooltip text — Blizzard's bindType API reports them as plain "BoE", which previously mislabelled every WuE item.
- Cross-character cold-cache fix: WuE and BoE items in another character's bag are now resolved through Blizzard's GET_ITEM_INFO_RECEIVED warm-up so their true ilvl (e.g. Champion 3/6 = 253) is used instead of the template base ilvl.
- Stat and level filters relaxed when previewing alts: C_Item.GetItemStats only reports the logged-in character's primary, and stale DB level snapshots can lag the live character — both checks now run only when the selected tab character is the player.

Gear tab — UI
- Storage Upgrade Recommendations card revised: subtitle clarifies "Transferable items only (BoE / Warbound)", row spacing increased, source font weight tuned for readability.
- Compact bind labels in the recommendation list: BoE / WuE / WB instead of long phrases.

Event-driven UI refresh
- Gear tab now refreshes on bag updates (newly looted BoEs surface immediately).
- Money, currency variants, collection events, vault events, character tracking changes, gold management edits, and bank money log updates all trigger the appropriate tab redraw.
- GET_ITEM_INFO_RECEIVED listener: gear tab re-scans once cold-cache hyperlinks finish async resolution.

Collections — loot alerts
- Bag-scan collectible detection now skips mounts, pets, and toys already marked as notified in SavedVariables (permanent dedupe).
- Prevents duplicate collection popups when repeated bag updates re-detected the same collectible.

Single-roof version system (no more wiped data on releases)
- Addon releases no longer invalidate any cache. Bumping the addon version preserves all character state, vault progress, mythic key history, and currency totals.
- Game build (WoW patch) is the trigger for API-bound cache invalidation (reputation, collection) where Blizzard's API shape may have shifted.
- Per-cache schema versions live in Constants.VERSIONS.CACHE; only the cache whose integer is bumped gets refreshed.
- Every invalidation creates an automatic backup at db.global.cacheBackups[name] before resetting; recoverable via WarbandNexus:RestoreCacheBackup(name).

Diagnostics
- New /wn dumpitem <itemID> command: prints all API data + every persisted bag/bank/warband-bank instance of an item to chat for troubleshooting.

CurseForge: Warband Nexus]=]
L["GEAR_STORAGE_SUBTITLE"] = "Nur übertragbare Gegenstände (BoE / Warbound)"
L["GEAR_STORAGE_WARBOUND_UNTIL_EQUIPPED"] = "Kriegsgebunden, bis ausgerüstet"
L["TRY_COUNTER_DROP_SCREENSHOT"] = "Screenshot zum verfolgten Abwurf"
L["TRY_COUNTER_DROP_SCREENSHOT_TOOLTIP"] = "Machen Sie kurz nach dem Popup einen automatischen Spiel-Screenshot, wenn ein Reittier, ein Haustier, ein Spielzeug oder eine Illusion mit Try-Tracking fallen gelassen wird. Deaktivieren Sie diese Option, wenn Sie keine zusätzlichen Dateien in Ihrem Screenshots-Ordner haben möchten."
L["VAULT_TRACKER_STATUS_PENDING"] = "Ausstehend..."
L["VAULT_TRACKER_STATUS_READY_CLAIM"] = "Bereit zum Anspruch"
L["VAULT_TRACKER_STATUS_SLOTS_READY"] = "Plätze freigeschaltet"

L["CONFIG_VAULT_BUTTON"] = "Schnellzugriff"
L["CONFIG_VAULT_BUTTON_DESC"] = "Zeigt den verschiebbaren Schnellzugriff an. Linksklick führt die gewählte Aktion aus; Rechtsklick öffnet das WN-Schnellmenü."
L["CONFIG_VAULT_BUTTON_SECTION"] = "Schnellzugriff"
L["CONFIG_VAULT_OPT_ENABLED"] = "Schnellzugriff aktivieren"
L["CONFIG_VAULT_OPT_ENABLED_DESC"] = "Zeigt den verschiebbaren Schnellzugriff an."
L["CONFIG_VAULT_OPT_MOUSEOVER"] = "Erst bei Mouseover einblenden"
L["CONFIG_VAULT_OPT_MOUSEOVER_DESC"] = "Blendet den Schnellzugriff aus, bis sich der Mauszeiger über seiner gespeicherten Position befindet."
L["CONFIG_VAULT_OPT_READY_ONLY"] = "Erst bei bereiter Belohnung einblenden"
L["CONFIG_VAULT_OPT_READY_ONLY_DESC"] = "Zeigt den Schnellzugriff nur, wenn mindestens ein Charakter eine abholbereite Tresorbelohnung hat."
L["CONFIG_VAULT_OPT_REALM"] = "Realmnamen anzeigen"
L["CONFIG_VAULT_OPT_REALM_DESC"] = "Zeigt Charakter-Realmnamen in Schnellzugriff-Tabellen und Tooltips."
L["CONFIG_VAULT_OPT_REWARD_ILVL"] = "Belohnungs-Gegenstandsstufe anzeigen"
L["CONFIG_VAULT_OPT_REWARD_ILVL_DESC"] = "Zeigt die Gegenstandsstufe der Belohnung in abgeschlossenen Tresor-Slots statt Häkchen-Symbolen."
L["CONFIG_VAULT_COL_RAID"] = "Schlachtzug-Spalte"
L["CONFIG_VAULT_COL_RAID_DESC"] = "Zeigt den Schlachtzug-Tresorfortschritt in der Schnellzugriff-Tabelle."
L["CONFIG_VAULT_COL_DUNGEON"] = "Dungeon-Spalte"
L["CONFIG_VAULT_COL_DUNGEON_DESC"] = "Zeigt Mythic+-Dungeon-Tresorfortschritt in der Schnellzugriff-Tabelle."
L["CONFIG_VAULT_COL_WORLD"] = "Welt-Spalte"
L["CONFIG_VAULT_COL_WORLD_DESC"] = "Zeigt Weltaktivitäten-Tresorfortschritt in der Schnellzugriff-Tabelle."
L["CONFIG_VAULT_COL_BOUNTY"] = "Spalte „Beutejäger-Kopfgeld“"
L["CONFIG_VAULT_COL_BOUNTY_DESC"] = "Zeigt den Abschluss von Beutejäger-Kopfgeld in der Schnellzugriff-Tabelle."
L["CONFIG_VAULT_COL_VOIDCORE"] = "Spalte Nebulöser Leerekern"
L["CONFIG_VAULT_COL_VOIDCORE_DESC"] = "Zeigt Fortschritt für Nebulösen Leerekern in der Schnellzugriff-Tabelle."
L["CONFIG_VAULT_COL_MANAFLUX"] = "Spalte Morgenlicht-Manaflux"
L["CONFIG_VAULT_COL_MANAFLUX_DESC"] = "Zeigt Morgenlicht Manaflux-Währung in der Schnellzugriff-Tabelle."
L["CONFIG_VAULT_BUTTON_OPACITY"] = "Knopfdeckkraft"
L["CONFIG_VAULT_BUTTON_OPACITY_DESC"] = "Passt die Deckkraft des Schnellzugriffs an, wenn er sichtbar ist."
L["CONFIG_VAULT_OPT_SUMMARY_MOUSEOVER"] = "Kriegstrupp-Zusammenfassung bei Mouseover"
L["CONFIG_VAULT_OPT_SUMMARY_MOUSEOVER_DESC"] = "Zeigt beim Überfahren die Tresor-Zusammenfassung des Kriegstrupps. Aus: nur aktueller Charakter."
L["CONFIG_VAULT_LEFT_CLICK_HEADER"] = "Linksklick"
L["CONFIG_VAULT_LEFT_CLICK_PVE"] = "Linksklick: PvE-Tab"
L["CONFIG_VAULT_LEFT_CLICK_PVE_DESC"] = "Linksklick auf Schnellzugriff öffnet den PvE-Tab."
L["CONFIG_VAULT_LEFT_CLICK_CHARS"] = "Linksklick: Charaktere-Tab"
L["CONFIG_VAULT_LEFT_CLICK_CHARS_DESC"] = "Linksklick auf Schnellzugriff öffnet den Charaktere-Tab."
L["CONFIG_VAULT_LEFT_CLICK_VAULT"] = "Linksklick: Tresor-Tracker"
L["CONFIG_VAULT_LEFT_CLICK_VAULT_DESC"] = "Linksklick auf Schnellzugriff öffnet das Tresor-Tracker-Fenster."
L["CONFIG_VAULT_LEFT_CLICK_SAVED"] = "Linksklick: Gespeicherte Instanzen"
L["CONFIG_VAULT_LEFT_CLICK_SAVED_DESC"] = "Linksklick auf Schnellzugriff öffnet das Mini-Fenster Gespeicherte Instanzen."
L["CONFIG_VAULT_LEFT_CLICK_PLANS"] = "Linksklick: Pläne / Aufgaben"
L["CONFIG_VAULT_LEFT_CLICK_PLANS_DESC"] = "Linksklick auf Schnellzugriff öffnet das Mini-Fenster Pläne / Aufgaben."
L["CMD_QT"] = "Schnellzugriff-Menü öffnen"
L["CONFIG_VAULT_QT_UNAVAILABLE"] = "Schnellzugriff ist noch nicht verfügbar."
L["VAULT_BUTTON_MENU_TITLE"] = "WN-Menü"
L["VAULT_BUTTON_MENU_TRACKER"] = "Tresor-Tracker"
L["VAULT_BUTTON_MENU_SAVED"] = "Gespeicherte Instanzen"
L["VAULT_BUTTON_MENU_PLANS"] = "Pläne / Aufgaben"
L["VAULT_BUTTON_MENU_SETTINGS"] = "Einstellungen"

L["SAVED_INSTANCES_TITLE"] = "Gespeicherte Instanzen"
L["SAVED_INSTANCES_EMPTY"] = "Noch keine Schlachtzug-Sperren erfasst.\nMelde dich mit einem Charakter mit aktiven Sperren an."
L["SAVED_INSTANCES_NO_FILTER_MATCH"] = "Keine Instanzen entsprechen den aktuellen Filtern."
L["SAVED_INSTANCES_SUMMARY"] = "%d Instanzen · %d Charaktere"
L["SAVED_INSTANCES_WARBAND_CLEARED"] = "Kriegstrupp"
L["SAVED_INSTANCES_EXPAND_HINT"] = "Klicken, um Charakter-Sperren zu erweitern"
