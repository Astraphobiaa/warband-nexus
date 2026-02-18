--[[
    Warband Nexus - Italian Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "itIT")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus caricato. Digita /wn o /warbandnexus per le opzioni."
L["VERSION"] = GAME_VERSION_LABEL or "Versione"

-- Slash Commands
L["SLASH_HELP"] = "Comandi disponibili:"
L["SLASH_OPTIONS"] = "Apri pannello opzioni"
L["SLASH_SCAN"] = "Scansiona banca Warband"
L["SLASH_SHOW"] = "Mostra/nascondi finestra principale"
L["SLASH_DEPOSIT"] = "Apri coda deposito"
L["SLASH_SEARCH"] = "Cerca un oggetto"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Impostazioni generali"
L["GENERAL_SETTINGS_DESC"] = "Configura il comportamento generale dell'addon"
L["ENABLE_ADDON"] = "Abilita addon"
L["ENABLE_ADDON_DESC"] = "Abilita o disabilita le funzionalità di Warband Nexus"
L["MINIMAP_ICON"] = "Mostra icona minimappa"
L["MINIMAP_ICON_DESC"] = "Mostra o nascondi il pulsante della minimappa"
L["DEBUG_MODE"] = "Modalità debug"
L["DEBUG_MODE_DESC"] = "Abilita messaggi di debug nella chat"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "Impostazioni scansione"
L["SCANNING_SETTINGS_DESC"] = "Configura il comportamento di scansione della banca"
L["AUTO_SCAN"] = "Scansione automatica all'apertura"
L["AUTO_SCAN_DESC"] = "Scansiona automaticamente la banca Warband all'apertura"
L["SCAN_DELAY"] = "Ritardo scansione"
L["SCAN_DELAY_DESC"] = "Ritardo tra le operazioni di scansione (in secondi)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "Impostazioni deposito"
L["DEPOSIT_SETTINGS_DESC"] = "Configura il comportamento di deposito degli oggetti"
L["GOLD_RESERVE"] = "Riserva d'oro"
L["GOLD_RESERVE_DESC"] = "Oro minimo da mantenere nell'inventario personale (in oro)"
L["AUTO_DEPOSIT_REAGENTS"] = "Deposito automatico reagenti"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "Metti in coda i reagenti al deposito all'apertura della banca"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Impostazioni visualizzazione"
L["DISPLAY_SETTINGS_DESC"] = "Configura l'aspetto visivo"
L["SHOW_ITEM_LEVEL"] = "Mostra livello oggetto"
L["SHOW_ITEM_LEVEL_DESC"] = "Mostra il livello oggetto sull'equipaggiamento"
L["SHOW_ITEM_COUNT"] = "Mostra quantità oggetti"
L["SHOW_ITEM_COUNT_DESC"] = "Mostra le quantità impilate sugli oggetti"
L["HIGHLIGHT_QUALITY"] = "Evidenzia per qualità"
L["HIGHLIGHT_QUALITY_DESC"] = "Aggiungi bordi colorati in base alla qualità dell'oggetto"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "Impostazioni schede"
L["TAB_SETTINGS_DESC"] = "Configura il comportamento delle schede della banca"
L["IGNORED_TABS"] = "Schede ignorate"
L["IGNORED_TABS_DESC"] = "Seleziona le schede da escludere dalla scansione e dalle operazioni"
L["TAB_1"] = "Scheda Warband 1"
L["TAB_2"] = "Scheda Warband 2"
L["TAB_3"] = "Scheda Warband 3"
L["TAB_4"] = "Scheda Warband 4"
L["TAB_5"] = "Scheda Warband 5"

-- Scanner Module
L["SCAN_STARTED"] = "Scansione della banca Warband..."
L["SCAN_COMPLETE"] = "Scansione completata. Trovati %d oggetti in %d slot."
L["SCAN_FAILED"] = "Scansione fallita: La banca Warband non è aperta."
L["SCAN_TAB"] = "Scansione scheda %d..."
L["CACHE_CLEARED"] = "Cache oggetti svuotata."
L["CACHE_UPDATED"] = "Cache oggetti aggiornata."

-- Banker Module
L["BANK_NOT_OPEN"] = "La banca Warband non è aperta."
L["DEPOSIT_STARTED"] = "Inizio operazione di deposito..."
L["DEPOSIT_COMPLETE"] = "Deposito completato. %d oggetti trasferiti."
L["DEPOSIT_CANCELLED"] = "Deposito annullato."
L["DEPOSIT_QUEUE_EMPTY"] = "La coda di deposito è vuota."
L["DEPOSIT_QUEUE_CLEARED"] = "Coda di deposito svuotata."
L["ITEM_QUEUED"] = "%s messo in coda per il deposito."
L["ITEM_REMOVED"] = "%s rimosso dalla coda."
L["GOLD_DEPOSITED"] = "%s oro depositato nella banca Warband."
L["INSUFFICIENT_GOLD"] = "Oro insufficiente per il deposito."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "Importo non valido."
L["WITHDRAW_BANK_NOT_OPEN"] = "La banca deve essere aperta per prelevare!"
L["WITHDRAW_IN_COMBAT"] = "Impossibile prelevare durante il combattimento."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "Oro insufficiente nella banca Warband."
L["WITHDRAWN_LABEL"] = "Prelevato:"
L["WITHDRAW_API_UNAVAILABLE"] = "API di prelievo non disponibile."
L["SORT_IN_COMBAT"] = "Impossibile ordinare durante il combattimento."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global
L["SEARCH_CATEGORY_FORMAT"] = "Cerca %s..."
L["BTN_SCAN"] = "Scansiona banca"
L["BTN_DEPOSIT"] = "Coda deposito"
L["BTN_SORT"] = "Ordina banca"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "Svuota coda"
L["BTN_DEPOSIT_ALL"] = "Deposita tutto"
L["BTN_DEPOSIT_GOLD"] = "Deposita oro"
L["ENABLE"] = ENABLE or "Abilita" -- Blizzard Global
L["ENABLE_MODULE"] = "Abilita modulo"

-- Main Tabs
L["TAB_CHARACTERS"] = CHARACTER or "Personaggi" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "Oggetti" -- Blizzard Global
L["TAB_STORAGE"] = "Deposito"
L["TAB_PLANS"] = "Piani"
L["TAB_REPUTATION"] = REPUTATION or "Reputazione" -- Blizzard Global
L["TAB_REPUTATIONS"] = "Reputazioni"
L["TAB_CURRENCY"] = CURRENCY or "Valuta" -- Blizzard Global
L["TAB_CURRENCIES"] = "Valute"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "Statistiche" -- Blizzard Global

-- Item Categories (Blizzard Globals)
L["CATEGORY_ALL"] = ALL or "Tutti gli oggetti" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipaggiamento"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumabili"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagenti"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Merci commerciali"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Oggetti missione"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Varie"

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
L["HEADER_FAVORITES"] = FAVORITES or "Preferiti" -- Blizzard Global
L["HEADER_CHARACTERS"] = CHARACTER or "Personaggi"
L["HEADER_CURRENT_CHARACTER"] = "PERSONAGGIO ATTUALE"
L["HEADER_WARBAND_GOLD"] = "ORO WARBAND"
L["HEADER_TOTAL_GOLD"] = "ORO TOTALE"
L["HEADER_REALM_GOLD"] = "ORO DEL REAME"
L["HEADER_REALM_TOTAL"] = "TOTALE DEL REAME"
L["CHARACTER_LAST_SEEN_FORMAT"] = "Visto l'ultima volta: %s"
L["CHARACTER_GOLD_FORMAT"] = "Oro: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "Oro combinato di tutti i personaggi su questo reame"

-- Items Tab
L["ITEMS_HEADER"] = "Oggetti della banca"
L["ITEMS_HEADER_DESC"] = "Sfoglia e gestisci la tua banca Warband e personale"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " oggetti..."
L["ITEMS_WARBAND_BANK"] = "Banca Warband"
L["ITEMS_PLAYER_BANK"] = BANK or "Banca personale" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Banca di gilda" -- Blizzard Global
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipaggiamento"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumabili"
L["GROUP_PROFESSION"] = "Professione"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagenti"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Merci commerciali"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Missione"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Varie"
L["GROUP_CONTAINER"] = "Contenitori"

-- Storage Tab
L["STORAGE_HEADER"] = "Browser deposito"
L["STORAGE_HEADER_DESC"] = "Sfoglia tutti gli oggetti organizzati per tipo"
L["STORAGE_WARBAND_BANK"] = "Banca Warband"
L["STORAGE_PERSONAL_BANKS"] = "Banche personali"
L["STORAGE_TOTAL_SLOTS"] = "Slot totali"
L["STORAGE_FREE_SLOTS"] = "Slot liberi"
L["STORAGE_BAG_HEADER"] = "Borse Warband"
L["STORAGE_PERSONAL_HEADER"] = "Banca personale"

-- Plans Tab
L["PLANS_MY_PLANS"] = "I miei piani"
L["PLANS_COLLECTIONS"] = "Piani di collezione"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "Aggiungi piano personalizzato"
L["PLANS_NO_RESULTS"] = "Nessun risultato trovato."
L["PLANS_ALL_COLLECTED"] = "Tutti gli oggetti raccolti!"
L["PLANS_RECIPE_HELP"] = "Clic destro sulle ricette nel tuo inventario per aggiungerle qui."
L["COLLECTION_PLANS"] = "Piani di collezione"
L["SEARCH_PLANS"] = "Cerca piani..."
L["COMPLETED_PLANS"] = "Piani completati"
L["SHOW_COMPLETED"] = "Mostra completati"
L["SHOW_PLANNED"] = "Mostra pianificati"
L["NO_PLANNED_ITEMS"] = "Nessun %s pianificato"

-- Plans Categories (Blizzard Globals)
L["CATEGORY_MY_PLANS"] = "I miei piani"
L["CATEGORY_DAILY_TASKS"] = "Compiti giornalieri"
L["CATEGORY_MOUNTS"] = MOUNTS or "Cavalcature" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "Mascotte" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "Giocattoli" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Trasmogrificazione" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "Illusioni"
L["CATEGORY_TITLES"] = TITLES or "Titoli"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Imprese" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " reputazione..."
L["REP_HEADER_WARBAND"] = "Reputazione Warband"
L["REP_HEADER_CHARACTER"] = "Reputazione personaggio"
L["REP_STANDING_FORMAT"] = "Rango: %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " valuta..."
L["CURRENCY_HEADER_WARBAND"] = "Trasferibile Warband"
L["CURRENCY_HEADER_CHARACTER"] = "Legato al personaggio"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "Incursioni" -- Blizzard Global
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Spedizioni" -- Blizzard Global
L["PVE_HEADER_DELVES"] = "Esplorazioni"
L["PVE_HEADER_WORLD_BOSS"] = "Boss mondiali"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "Statistiche"
L["STATS_TOTAL_ITEMS"] = "Oggetti totali"
L["STATS_TOTAL_SLOTS"] = "Slot totali"
L["STATS_FREE_SLOTS"] = "Slot liberi"
L["STATS_USED_SLOTS"] = "Slot usati"
L["STATS_TOTAL_VALUE"] = "Valore totale"
L["COLLECTED"] = "Raccolto"
L["TOTAL"] = "Totale"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Personaggio" -- Blizzard Global
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Posizione" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "Banca Warband"
L["TOOLTIP_TAB"] = "Scheda"
L["TOOLTIP_SLOT"] = "Slot"
L["TOOLTIP_COUNT"] = "Quantità"
L["CHARACTER_INVENTORY"] = "Inventario"
L["CHARACTER_BANK"] = "Banca"

-- Try Counter
L["TRY_COUNT"] = "Contatore tentativi"
L["SET_TRY_COUNT"] = "Imposta tentativi"
L["TRIES"] = "Tentativi"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "Imposta ciclo di reset"
L["DAILY_RESET"] = "Reset giornaliero"
L["WEEKLY_RESET"] = "Reset settimanale"
L["NONE_DISABLE"] = "Nessuno (Disattiva)"
L["RESET_CYCLE_LABEL"] = "Ciclo di reset:"
L["RESET_NONE"] = "Nessuno"
L["DOUBLECLICK_RESET"] = "Doppio clic per ripristinare la posizione"

-- Error Messages
L["ERROR_GENERIC"] = "Si è verificato un errore."
L["ERROR_API_UNAVAILABLE"] = "L'API richiesta non è disponibile."
L["ERROR_BANK_CLOSED"] = "Impossibile eseguire l'operazione: banca chiusa."
L["ERROR_INVALID_ITEM"] = "Oggetto specificato non valido."
L["ERROR_PROTECTED_FUNCTION"] = "Impossibile chiamare una funzione protetta in combattimento."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "Depositare %d oggetti nella banca Warband?"
L["CONFIRM_CLEAR_QUEUE"] = "Svuotare tutti gli oggetti dalla coda di deposito?"
L["CONFIRM_DEPOSIT_GOLD"] = "Depositare %s oro nella banca Warband?"

-- Update Notification
L["WHATS_NEW"] = "Novità"
L["GOT_IT"] = "Capito!"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "PUNTI IMPRESA"
L["MOUNTS_COLLECTED"] = "CAVALCATURE RACCOLTE"
L["BATTLE_PETS"] = "MASCOTTE DI BATTAGLIA"
L["ACCOUNT_WIDE"] = "Intero account"
L["STORAGE_OVERVIEW"] = "Panoramica deposito"
L["WARBAND_SLOTS"] = "SLOT WARBAND"
L["PERSONAL_SLOTS"] = "SLOT PERSONALI"
L["TOTAL_FREE"] = "TOTALE LIBERO"
L["TOTAL_ITEMS"] = "OGGETTI TOTALI"

-- Plans Tracker
L["WEEKLY_VAULT"] = "Grande Deposito Settimanale"
L["CUSTOM"] = "Personalizzato"
L["NO_PLANS_IN_CATEGORY"] = "Nessun piano in questa categoria.\nAggiungi piani dalla scheda Piani."
L["SOURCE_LABEL"] = "Fonte:"
L["ZONE_LABEL"] = "Zona:"
L["VENDOR_LABEL"] = "Mercante:"
L["DROP_LABEL"] = "Bottino:"
L["REQUIREMENT_LABEL"] = "Requisito:"
L["RIGHT_CLICK_REMOVE"] = "Clic destro per rimuovere"
L["TRACKED"] = "Tracciato"
L["TRACK"] = "Traccia"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Traccia negli obiettivi Blizzard (max 10)"
L["UNKNOWN"] = "Sconosciuto"
L["NO_REQUIREMENTS"] = "Nessun requisito (completamento istantaneo)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "Nessuna attività pianificata"
L["CLICK_TO_ADD_GOALS"] = "Clicca su Cavalcature, Mascotte o Giocattoli sopra per aggiungere obiettivi!"
L["UNKNOWN_QUEST"] = "Missione sconosciuta"
L["ALL_QUESTS_COMPLETE"] = "Tutte le missioni completate!"
L["CURRENT_PROGRESS"] = "Progresso attuale"
L["SELECT_CONTENT"] = "Seleziona contenuto:"
L["QUEST_TYPES"] = "Tipi di missione:"
L["WORK_IN_PROGRESS"] = "In fase di sviluppo"
L["RECIPE_BROWSER"] = "Browser ricette"
L["NO_RESULTS_FOUND"] = "Nessun risultato trovato."
L["TRY_ADJUSTING_SEARCH"] = "Prova a modificare la ricerca o i filtri."
L["NO_COLLECTED_YET"] = "Nessun %s raccolto ancora"
L["START_COLLECTING"] = "Inizia a raccogliere per vederli qui!"
L["ALL_COLLECTED_CATEGORY"] = "Tutti i %s raccolti!"
L["COLLECTED_EVERYTHING"] = "Hai raccolto tutto in questa categoria!"
L["PROGRESS_LABEL"] = "Progresso:"
L["REQUIREMENTS_LABEL"] = "Requisiti:"
L["INFORMATION_LABEL"] = "Informazione:"
L["DESCRIPTION_LABEL"] = "Descrizione:"
L["REWARD_LABEL"] = "Ricompensa:"
L["DETAILS_LABEL"] = "Dettagli:"
L["COST_LABEL"] = "Costo:"
L["LOCATION_LABEL"] = "Posizione:"
L["TITLE_LABEL"] = "Titolo:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "Hai già completato tutte le imprese in questa categoria!"
L["DAILY_PLAN_EXISTS"] = "Il piano giornaliero esiste già"
L["WEEKLY_PLAN_EXISTS"] = "Il piano settimanale esiste già"

-- PvE Tab
L["GREAT_VAULT"] = "Grande Deposito"
L["LOADING_PVE"] = "Caricamento dati PvE..."
L["PVE_APIS_LOADING"] = "Attendere prego, le API di WoW si stanno inizializzando..."
L["NO_VAULT_DATA"] = "Nessun dato del Grande Deposito"
L["NO_DATA"] = "Nessun dato"
L["KEYSTONE"] = "Chiave del trionfo"
L["NO_KEY"] = "Nessuna chiave"
L["AFFIXES"] = "Affissi"
L["NO_AFFIXES"] = "Nessun affisso"
L["VAULT_BEST_KEY"] = "Miglior chiave:"
L["VAULT_SCORE"] = "Punteggio:"

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "I tuoi personaggi"
L["CHARACTERS_TRACKED_FORMAT"] = "%d personaggi tracciati"
L["NO_CHARACTER_DATA"] = "Nessun dato personaggio disponibile"
L["NO_FAVORITES"] = "Nessun personaggio preferito ancora. Clicca sull'icona stella per aggiungere un personaggio ai preferiti."
L["ALL_FAVORITED"] = "Tutti i personaggi sono nei preferiti!"
L["UNTRACKED_CHARACTERS"] = "Personaggi non tracciati"
L["ILVL_SHORT"] = "iLvl"
L["ONLINE"] = "Online"
L["TIME_LESS_THAN_MINUTE"] = "< 1m fa"
L["TIME_MINUTES_FORMAT"] = "%dm fa"
L["TIME_HOURS_FORMAT"] = "%dh fa"
L["TIME_DAYS_FORMAT"] = "%dd fa"
L["REMOVE_FROM_FAVORITES"] = "Rimuovi dai preferiti"
L["ADD_TO_FAVORITES"] = "Aggiungi ai preferiti"
L["FAVORITES_TOOLTIP"] = "I personaggi preferiti appaiono in cima alla lista"
L["CLICK_TO_TOGGLE"] = "Clicca per attivare/disattivare"
L["UNKNOWN_PROFESSION"] = "Professione sconosciuta"
L["SKILL_LABEL"] = "Abilità:"
L["OVERALL_SKILL"] = "Abilità complessiva:"
L["BONUS_SKILL"] = "Abilità bonus:"
L["KNOWLEDGE_LABEL"] = "Conoscenza:"
L["SPEC_LABEL"] = "Spec"
L["POINTS_SHORT"] = "punti"
L["RECIPES_KNOWN"] = "Ricette conosciute:"
L["OPEN_PROFESSION_HINT"] = "Apri finestra professione"
L["FOR_DETAILED_INFO"] = "per informazioni dettagliate"
L["CHARACTER_IS_TRACKED"] = "Questo personaggio è tracciato."
L["TRACKING_ACTIVE_DESC"] = "Raccolta dati e aggiornamenti sono attivi."
L["CLICK_DISABLE_TRACKING"] = "Clicca per disattivare il tracciamento."
L["MUST_LOGIN_TO_CHANGE"] = "Devi accedere con questo personaggio per cambiare il tracciamento."
L["TRACKING_ENABLED"] = "Tracciamento attivato"
L["CLICK_ENABLE_TRACKING"] = "Clicca per attivare il tracciamento per questo personaggio."
L["TRACKING_WILL_BEGIN"] = "La raccolta dati inizierà immediatamente."
L["CHARACTER_NOT_TRACKED"] = "Questo personaggio non è tracciato."
L["MUST_LOGIN_TO_ENABLE"] = "Devi accedere con questo personaggio per attivare il tracciamento."
L["ENABLE_TRACKING"] = "Attiva tracciamento"
L["DELETE_CHARACTER_TITLE"] = "Eliminare personaggio?"
L["THIS_CHARACTER"] = "questo personaggio"
L["DELETE_CHARACTER"] = "Elimina personaggio"
L["REMOVE_FROM_TRACKING_FORMAT"] = "Rimuovi %s dal tracciamento"
L["CLICK_TO_DELETE"] = "Clicca per eliminare"
L["CONFIRM_DELETE"] = "Sei sicuro di voler eliminare |cff00ccff%s|r?"
L["CANNOT_UNDO"] = "Questa azione non può essere annullata!"
L["DELETE"] = DELETE or "Elimina"
L["CANCEL"] = CANCEL or "Annulla"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "Oggetti personali"
L["ITEMS_SUBTITLE"] = "Sfoglia la tua Banca Warband e gli Oggetti Personali (Banca + Inventario)"
L["ITEMS_DISABLED_TITLE"] = "Oggetti Banca Warband"
L["ITEMS_LOADING"] = "Caricamento dati inventario"
L["GUILD_BANK_REQUIRED"] = "Devi essere in una gilda per accedere alla Banca di Gilda."
L["ITEMS_SEARCH"] = "Cerca oggetti..."
L["NEVER"] = "Mai"
L["ITEM_FALLBACK_FORMAT"] = "Oggetto %s"
L["TAB_FORMAT"] = "Scheda %d"
L["BAG_FORMAT"] = "Borsa %d"
L["BANK_BAG_FORMAT"] = "Borsa banca %d"
L["ITEM_ID_LABEL"] = "ID oggetto:"
L["QUALITY_TOOLTIP_LABEL"] = "Qualità:"
L["STACK_LABEL"] = "Pila:"
L["RIGHT_CLICK_MOVE"] = "Sposta in borsa"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Dividi pila"
L["LEFT_CLICK_PICKUP"] = "Raccogli"
L["ITEMS_BANK_NOT_OPEN"] = "Banca non aperta"
L["SHIFT_LEFT_CLICK_LINK"] = "Collega in chat"
L["ITEM_DEFAULT_TOOLTIP"] = "Oggetto"
L["ITEMS_STATS_ITEMS"] = "%s oggetti"
L["ITEMS_STATS_SLOTS"] = "%s/%s slot"
L["ITEMS_STATS_LAST"] = "Ultimo: %s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "Deposito personaggio"
L["STORAGE_SEARCH"] = "Cerca deposito..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "Progresso PvE"
L["PVE_SUBTITLE"] = "Grande Deposito, Blocchi Incursioni & Mitica+ della tua Brigata di guerra"
L["PVE_NO_CHARACTER"] = "Nessun dato personaggio disponibile"
L["LV_FORMAT"] = "Lv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = "Incursione"
L["VAULT_DUNGEON"] = "Spedizione"
L["VAULT_WORLD"] = "Mondo"
L["VAULT_SLOT_FORMAT"] = "%s Slot %d"
L["VAULT_NO_PROGRESS"] = "Nessun progresso ancora"
L["VAULT_UNLOCK_FORMAT"] = "Completa %s attività per sbloccare"
L["VAULT_NEXT_TIER_FORMAT"] = "Prossimo livello: %d iLvl al completamento di %s"
L["VAULT_REMAINING_FORMAT"] = "Rimanenti: %s attività"
L["VAULT_PROGRESS_FORMAT"] = "Progresso: %s / %s"
L["OVERALL_SCORE_LABEL"] = "Punteggio complessivo:"
L["BEST_KEY_FORMAT"] = "Miglior chiave: +%d"
L["SCORE_FORMAT"] = "Punteggio: %s"
L["NOT_COMPLETED_SEASON"] = "Non completato questa stagione"
L["CURRENT_MAX_FORMAT"] = "Attuale: %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "Progresso: %.1f%%"
L["NO_CAP_LIMIT"] = "Nessun limite massimo"

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "Panoramica Reputazione"
L["REP_SUBTITLE"] = "Traccia fazioni e Fama della tua brigata di guerra"
L["REP_DISABLED_TITLE"] = "Tracciamento Reputazione"
L["REP_LOADING_TITLE"] = "Caricamento dati reputazione"
L["REP_SEARCH"] = "Cerca reputazioni..."
L["REP_PARAGON_TITLE"] = "Reputazione Eccellenza"
L["REP_REWARD_AVAILABLE"] = "Ricompensa disponibile!"
L["REP_CONTINUE_EARNING"] = "Continua a guadagnare reputazione per ricompense"
L["REP_CYCLES_FORMAT"] = "Cicli: %d"
L["REP_PROGRESS_HEADER"] = "Progresso: %d/%d"
L["REP_PARAGON_PROGRESS"] = "Progresso Eccellenza:"
L["REP_PROGRESS_COLON"] = "Progresso:"
L["REP_CYCLES_COLON"] = "Cicli:"
L["REP_CHARACTER_PROGRESS"] = "Progresso personaggio:"
L["REP_RENOWN_FORMAT"] = "Fama %d"
L["REP_PARAGON_FORMAT"] = "Eccellenza (%s)"
L["REP_UNKNOWN_FACTION"] = "Fazione sconosciuta"
L["REP_API_UNAVAILABLE_TITLE"] = "API Reputazione non disponibile"
L["REP_API_UNAVAILABLE_DESC"] = "L'API C_Reputation non è disponibile su questo server. Questa funzionalità richiede WoW 11.0+ (The War Within)."
L["REP_FOOTER_TITLE"] = "Tracciamento Reputazione"
L["REP_FOOTER_DESC"] = "Le reputazioni vengono scansionate automaticamente al login e quando cambiano. Usa il pannello reputazione in-game per visualizzare informazioni dettagliate e ricompense."
L["REP_CLEARING_CACHE"] = "Svuotamento cache e ricaricamento..."
L["REP_LOADING_DATA"] = "Caricamento dati reputazione..."
L["REP_MAX"] = "Max."
L["REP_TIER_FORMAT"] = "Livello %d"
L["ACCOUNT_WIDE_LABEL"] = "Intero account"
L["NO_RESULTS"] = "Nessun risultato"
L["NO_REP_MATCH"] = "Nessuna reputazione corrisponde a '%s'"
L["NO_REP_DATA"] = "Nessun dato di reputazione disponibile"
L["REP_SCAN_TIP"] = "Le reputazioni vengono scansionate automaticamente. Prova /reload se non appare nulla."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "Reputazioni dell'intero account (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "Nessuna reputazione dell'intero account"
L["NO_CHARACTER_REPS"] = "Nessuna reputazione del personaggio"

-- =============================================
-- Currency Tab
-- =============================================
L["GOLD_LABEL"] = "Oro"
L["CURRENCY_TITLE"] = "Tracciamento Valute"
L["CURRENCY_SUBTITLE"] = "Traccia tutte le valute dei tuoi personaggi"
L["CURRENCY_DISABLED_TITLE"] = "Tracciamento Valute"
L["CURRENCY_LOADING_TITLE"] = "Caricamento dati valute"
L["CURRENCY_SEARCH"] = "Cerca valute..."
L["CURRENCY_HIDE_EMPTY"] = "Nascondi vuote"
L["CURRENCY_SHOW_EMPTY"] = "Mostra vuote"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "Tutte trasferibili Brigata di guerra"
L["CURRENCY_CHARACTER_SPECIFIC"] = "Valute specifiche del personaggio"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "Limitazione trasferimento valute"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "L'API Blizzard non supporta trasferimenti automatici di valute. Usa il pannello valute in-game per trasferire manualmente le valute della Brigata di guerra."
L["CURRENCY_UNKNOWN"] = "Valuta sconosciuta"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "Rimuovi tutti i piani completati dalla tua lista I miei piani. Questo eliminerà tutti i piani personalizzati completati e rimuoverà cavalcature/mascotte/giocattoli completati dai tuoi piani. Questa azione non può essere annullata!"
L["RECIPE_BROWSER_DESC"] = "Apri la finestra Professione in-game per sfogliare le ricette.\nL'addon scannerà le ricette disponibili quando la finestra è aperta."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "Fonte: [Impresa %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s ha già un piano Grande Deposito settimanale attivo. Puoi trovarlo nella categoria 'I miei piani'."
L["DAILY_PLAN_EXISTS_DESC"] = "%s ha già un piano missione giornaliera attivo. Puoi trovarlo nella categoria 'Compiti giornalieri'."
L["TRANSMOG_WIP_DESC"] = "Il tracciamento della collezione trasmogrificazione è attualmente in fase di sviluppo.\n\nQuesta funzionalità sarà disponibile in un aggiornamento futuro con\nprestazioni migliorate e migliore integrazione con i sistemi della Brigata di guerra."
L["WEEKLY_VAULT_CARD"] = "Carta Grande Deposito Settimanale"
L["WEEKLY_VAULT_COMPLETE"] = "Carta Grande Deposito Settimanale - Completato"
L["UNKNOWN_SOURCE"] = "Fonte sconosciuta"
L["DAILY_TASKS_PREFIX"] = "Compiti giornalieri - "
L["NO_FOUND_FORMAT"] = "Nessun %s trovato"
L["PLANS_COUNT_FORMAT"] = "%d piani"
L["PET_BATTLE_LABEL"] = "Battaglia mascotte:"
L["QUEST_LABEL"] = "Missione:"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "Lingua attuale:"
L["LANGUAGE_TOOLTIP"] = "L'addon utilizza automaticamente la lingua del tuo client WoW. Per cambiarla, aggiorna le impostazioni di Battle.net."
L["POPUP_DURATION"] = "Durata popup"
L["POPUP_POSITION"] = "Posizione popup"
L["SET_POSITION"] = "Imposta posizione"
L["DRAG_TO_POSITION"] = "Trascina per posizionare\nClic destro per confermare"
L["RESET_DEFAULT"] = "Ripristina predefinito"
L["TEST_POPUP"] = "Testa popup"
L["CUSTOM_COLOR"] = "Colore personalizzato"
L["OPEN_COLOR_PICKER"] = "Apri selettore colori"
L["COLOR_PICKER_TOOLTIP"] = "Apri il selettore colori nativo di WoW per scegliere un colore tema personalizzato"
L["PRESET_THEMES"] = "Temi predefiniti"
L["WARBAND_NEXUS_SETTINGS"] = "Impostazioni Warband Nexus"
L["NO_OPTIONS"] = "Nessuna opzione"
L["NONE_LABEL"] = NONE or "Nessuno"
L["TAB_FILTERING"] = "Filtraggio schede"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Notifiche"
L["SCROLL_SPEED"] = "Velocità scorrimento"
L["ANCHOR_FORMAT"] = "Ancora: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "Mostra pianificatore settimanale"
L["LOCK_MINIMAP_ICON"] = "Blocca icona minimappa"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "Mostra oggetti nei suggerimenti"
L["AUTO_SCAN_ITEMS"] = "Scansione automatica oggetti"
L["LIVE_SYNC"] = "Sincronizzazione in tempo reale"
L["BACKPACK_LABEL"] = "Zaino"
L["REAGENT_LABEL"] = "Reagente"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "Modulo disattivato"
L["LOADING"] = "Caricamento..."
L["PLEASE_WAIT"] = "Attendere prego..."
L["RESET_PREFIX"] = "Reset:"
L["TRANSFER_CURRENCY"] = "Trasferisci valuta"
L["AMOUNT_LABEL"] = "Importo:"
L["TO_CHARACTER"] = "Al personaggio:"
L["SELECT_CHARACTER"] = "Seleziona personaggio..."
L["CURRENCY_TRANSFER_INFO"] = "Il pannello valute si aprirà automaticamente.\nDovrai fare clic destro manualmente sulla valuta per trasferirla."
L["OK_BUTTON"] = OKAY or "OK"
L["SAVE"] = "Salva"
L["TITLE_FIELD"] = "Titolo:"
L["DESCRIPTION_FIELD"] = "Descrizione:"
L["CREATE_CUSTOM_PLAN"] = "Crea piano personalizzato"
L["REPORT_BUGS"] = "Segnala bug o condividi suggerimenti su CurseForge per aiutare a migliorare l'addon."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus fornisce un'interfaccia centralizzata per gestire tutti i tuoi personaggi, valute, reputazioni, oggetti e progresso PvE dell'intera tua Brigata di guerra."
L["CHARACTERS_DESC"] = "Visualizza tutti i personaggi con oro, livello, iLvl, fazione, razza, classe, professioni, chiave del potere e ultima sessione. Traccia o smetti di tracciare personaggi, segna i preferiti."
L["ITEMS_DESC"] = "Cerca e sfoglia oggetti in tutte le borse, banche e banca di banda. Scansione automatica all'apertura di una banca. I tooltip mostrano quali personaggi possiedono ogni oggetto."
L["STORAGE_DESC"] = "Vista inventario aggregata di tutti i personaggi — borse, banca personale e banca di banda combinati in un unico posto."
L["PVE_DESC"] = "Traccia il Grande Deposito con indicatori di livello, punteggi e chiavi Mitica+, affissi, storico dungeon e valuta potenziamento su tutti i personaggi."
L["REPUTATIONS_DESC"] = "Confronta il progresso di reputazione di tutti i personaggi. Mostra fazioni Account vs Personaggio con tooltip al passaggio per dettaglio per personaggio."
L["CURRENCY_DESC"] = "Visualizza tutte le valute organizzate per espansione. Confronta importi tra personaggi con tooltip al passaggio. Nascondi valute vuote con un clic."
L["PLANS_DESC"] = "Traccia cavalcature, mascotte, giocattoli, imprese e transmog non raccolti. Aggiungi obiettivi, visualizza fonti drop e monitora contatori tentativi. Accesso tramite /wn plan o icona minimappa."
L["STATISTICS_DESC"] = "Visualizza punti impresa, progresso collezione cavalcature/mascotte/giocattoli/illusioni/titoli, contatore mascotte uniche e statistiche utilizzo borse/banche."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "Mitica"
L["DIFFICULTY_HEROIC"] = "Eroica"
L["DIFFICULTY_NORMAL"] = "Normale"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Livello %d"
L["PVP_TYPE"] = "PvP"
L["PREPARING"] = "Preparazione"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Statistiche Account"
L["STATISTICS_SUBTITLE"] = "Progresso collezione, oro e panoramica deposito"
L["MOST_PLAYED"] = "PIÙ GIOCATI"
L["PLAYED_DAYS"] = "Giorni"
L["PLAYED_HOURS"] = "Ore"
L["PLAYED_MINUTES"] = "Minuti"
L["PLAYED_DAY"] = "Giorno"
L["PLAYED_HOUR"] = "Ora"
L["PLAYED_MINUTE"] = "Minuto"
L["MORE_CHARACTERS"] = "personaggio in più"
L["MORE_CHARACTERS_PLURAL"] = "personaggi in più"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "Benvenuto in Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "Panoramica AddOn"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "Traccia i tuoi obiettivi di collezione"
L["ACTIVE_PLAN_FORMAT"] = "%d piano attivo"
L["ACTIVE_PLANS_FORMAT"] = "%d piani attivi"
L["RESET_LABEL"] = RESET or "Ripristina"

-- Plans - Type Names
L["TYPE_MOUNT"] = MOUNT or "Cavalcatura"
L["TYPE_PET"] = PET or "Mascotte"
L["TYPE_TOY"] = TOY or "Giocattolo"
L["TYPE_RECIPE"] = "Ricetta"
L["TYPE_ILLUSION"] = "Illusione"
L["TYPE_TITLE"] = "Titolo"
L["TYPE_CUSTOM"] = "Personalizzato"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Trasmogrificazione"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Bottino"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Missione"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Venditore"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Professione"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Battaglia mascotte"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Impresa"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "Evento mondiale"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promozione"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "Gioco di carte collezionabili"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "Negozio in-game"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "Creato"
L["SOURCE_TYPE_TRADING_POST"] = "Emporio"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "Sconosciuto"
L["SOURCE_TYPE_PVP"] = PVP or "PvP"
L["SOURCE_TYPE_TREASURE"] = "Tesoro"
L["SOURCE_TYPE_PUZZLE"] = "Enigma"
L["SOURCE_TYPE_RENOWN"] = "Fama"

-- Plans - Transmog Source Labels (Blizzard TRANSMOG_SOURCE_* Globals)
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Bottino del boss"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Missione"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Mercante"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "Bottino nel mondo"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Impresa"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Professione"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "Venduto da"
L["PARSE_CRAFTED"] = "Creato"
L["PARSE_ZONE"] = ZONE or "Zona"
L["PARSE_COST"] = "Costo"
L["PARSE_REPUTATION"] = REPUTATION or "Reputazione"
L["PARSE_FACTION"] = FACTION or "Fazione"
L["PARSE_ARENA"] = ARENA or "Arena"
L["PARSE_DUNGEON"] = DUNGEONS or "Spedizione"
L["PARSE_RAID"] = RAID or "Incursione"
L["PARSE_HOLIDAY"] = "Festività"
L["PARSE_RATED"] = "Classificato"
L["PARSE_BATTLEGROUND"] = "Campo di battaglia"
L["PARSE_DISCOVERY"] = "Scoperta"
L["PARSE_CONTAINED_IN"] = "Contenuto in"
L["PARSE_GARRISON"] = "Guarnigione"
L["PARSE_GARRISON_BUILDING"] = "Edificio della guarnigione"
L["PARSE_STORE"] = "Negozio"
L["PARSE_ORDER_HALL"] = "Sala dell'ordine"
L["PARSE_COVENANT"] = "Congrega"
L["PARSE_FRIENDSHIP"] = "Amicizia"
L["PARSE_PARAGON"] = "Eccellenza"
L["PARSE_MISSION"] = "Missione"
L["PARSE_EXPANSION"] = "Espansione"
L["PARSE_SCENARIO"] = "Scenario"
L["PARSE_CLASS_HALL"] = "Sala dell'ordine"
L["PARSE_CAMPAIGN"] = "Campagna"
L["PARSE_EVENT"] = "Evento"
L["PARSE_SPECIAL"] = "Speciale"
L["PARSE_BRAWLERS_GUILD"] = "Gilda dei Combattenti"
L["PARSE_CHALLENGE_MODE"] = "Modalità sfida"
L["PARSE_MYTHIC_PLUS"] = "Mitica+"
L["PARSE_TIMEWALKING"] = "Cavalcata del Tempo"
L["PARSE_ISLAND_EXPEDITION"] = "Spedizione sulle isole"
L["PARSE_WARFRONT"] = "Fronte di guerra"
L["PARSE_TORGHAST"] = "Torghast"
L["PARSE_ZERETH_MORTIS"] = "Zereth Mortis"
L["PARSE_HIDDEN"] = "Nascosto"
L["PARSE_RARE"] = "Raro"
L["PARSE_WORLD_BOSS"] = "Boss mondiale"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Bottino"
L["PARSE_NPC"] = "PNG"
L["PARSE_FROM_ACHIEVEMENT"] = "Dall'impresa"
L["FALLBACK_UNKNOWN_PET"] = "Animale sconosciuto"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "Collezione animali"
L["FALLBACK_TOY_COLLECTION"] = "Collezione giocattoli"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Collezione trasmutazione"
L["FALLBACK_PLAYER_TITLE"] = "Titolo giocatore"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Sconosciuto"
L["FALLBACK_ILLUSION_FORMAT"] = "Illusione %s"
L["SOURCE_ENCHANTING"] = "Incantamento"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "Imposta tentativi per:\n%s"
L["RESET_COMPLETED_CONFIRM"] = "Sei sicuro di voler rimuovere TUTTI i piani completati?\n\nQuesto non può essere annullato!"
L["YES_RESET"] = "Sì, ripristina"
L["REMOVED_PLANS_FORMAT"] = "Rimossi %d piano/i completato/i."

-- Plans - Buttons
L["ADD_CUSTOM"] = "Aggiungi personalizzato"
L["ADD_VAULT"] = "Aggiungi Deposito"
L["ADD_QUEST"] = "Aggiungi missione"
L["CREATE_PLAN"] = "Crea piano"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "Giornaliera"
L["QUEST_CAT_WORLD"] = "Mondo"
L["QUEST_CAT_WEEKLY"] = "Settimanale"
L["QUEST_CAT_ASSIGNMENT"] = "Incarico"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Categoria sconosciuta"
L["SCANNING_FORMAT"] = "Scansione %s"
L["CUSTOM_PLAN_SOURCE"] = "Piano personalizzato"
L["POINTS_FORMAT"] = "%d Punti"
L["SOURCE_NOT_AVAILABLE"] = "Informazioni fonte non disponibili"
L["PROGRESS_ON_FORMAT"] = "Sei a %d/%d nel progresso"
L["COMPLETED_REQ_FORMAT"] = "Hai completato %d di %d requisiti totali"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Midnight"
L["CONTENT_TWW"] = "The War Within"
L["QUEST_TYPE_DAILY"] = "Missioni giornaliere"
L["QUEST_TYPE_DAILY_DESC"] = "Missioni giornaliere regolari da NPC"
L["QUEST_TYPE_WORLD"] = "Missioni mondo"
L["QUEST_TYPE_WORLD_DESC"] = "Missioni mondo a livello di zona"
L["QUEST_TYPE_WEEKLY"] = "Missioni settimanali"
L["QUEST_TYPE_WEEKLY_DESC"] = "Missioni settimanali ricorrenti"
L["QUEST_TYPE_ASSIGNMENTS"] = "Incarichi"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "Incarichi e compiti speciali"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "Mitica+"
L["RAIDS_LABEL"] = "Incursioni"

-- PlanCardFactory
L["FACTION_LABEL"] = "Fazione:"
L["FRIENDSHIP_LABEL"] = "Amicizia"
L["RENOWN_TYPE_LABEL"] = "Fama"
L["ADD_BUTTON"] = "+ Aggiungi"
L["ADDED_LABEL"] = "Aggiunto"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s di %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Mostra quantità pile sugli oggetti nella vista deposito"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Mostra la sezione Pianificatore settimanale nella scheda Personaggi"
L["LOCK_MINIMAP_TOOLTIP"] = "Blocca l'icona della minimappa in posizione (previene lo spostamento)"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "Visualizza il numero di oggetti della Brigata e del personaggio nei suggerimenti (Ricerca WN)."
L["AUTO_SCAN_TOOLTIP"] = "Scansiona e memorizza automaticamente gli oggetti quando apri banche o borse"
L["LIVE_SYNC_TOOLTIP"] = "Mantieni la cache oggetti aggiornata in tempo reale mentre le banche sono aperte"
L["SHOW_ILVL_TOOLTIP"] = "Mostra badge livello oggetto sull'equipaggiamento nella lista oggetti"
L["SCROLL_SPEED_TOOLTIP"] = "Moltiplicatore per la velocità di scorrimento (1.0x = 28 px per passo)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "Ignora Scheda Banca Brigata di guerra %d dalla scansione automatica"
L["IGNORE_SCAN_FORMAT"] = "Ignora %s dalla scansione automatica"
L["BANK_LABEL"] = BANK or "Banca"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "Abilita notifiche"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Interruttore principale per tutti i popup di notifica"
L["VAULT_REMINDER"] = "Promemoria Deposito"
L["VAULT_REMINDER_TOOLTIP"] = "Mostra promemoria quando hai ricompense Grande Deposito Settimanale non ritirate"
L["LOOT_ALERTS"] = "Avvisi bottino"
L["LOOT_ALERTS_TOOLTIP"] = "Mostra notifica quando un NUOVO cavalcatura, mascotte o giocattolo entra nella tua borsa"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Nascondi avviso impresa Blizzard"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Nascondi il popup impresa predefinito di Blizzard e usa invece la notifica Warband Nexus"
L["REPUTATION_GAINS"] = "Guadagni reputazione"
L["REPUTATION_GAINS_TOOLTIP"] = "Mostra messaggi chat quando guadagni reputazione con le fazioni"
L["CURRENCY_GAINS"] = "Guadagni valute"
L["CURRENCY_GAINS_TOOLTIP"] = "Mostra messaggi chat quando guadagni valute"
L["SCREEN_FLASH_EFFECT"] = "Effetto flash schermo"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Riprodurre un effetto flash sullo schermo quando ottieni un nuovo collezionabile (cavalcatura, mascotte, giocattolo, ecc.)"
L["AUTO_TRY_COUNTER"] = "Contatore tentativi automatico"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Contare automaticamente i tentativi quando saccheggi NPC, rari, boss, peschi o apri contenitori che possono rilasciare cavalcature, mascotte o giocattoli. Mostra il conteggio dei tentativi in chat quando il collezionabile non viene rilasciato."
L["DURATION_LABEL"] = "Durata"
L["DAYS_LABEL"] = "giorni"
L["WEEKS_LABEL"] = "settimane"
L["EXTEND_DURATION"] = "Estendi durata"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Trascina il riquadro verde per impostare la posizione del popup. Clic destro per confermare."
L["POSITION_RESET_MSG"] = "Posizione popup ripristinata al predefinito (Centro Superiore)"
L["POSITION_SAVED_MSG"] = "Posizione popup salvata!"
L["TEST_NOTIFICATION_TITLE"] = "Notifica di prova"
L["TEST_NOTIFICATION_MSG"] = "Test posizione"
L["NOTIFICATION_DEFAULT_TITLE"] = "Notifica"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "Tema & Aspetto"
L["COLOR_PURPLE"] = "Viola"
L["COLOR_PURPLE_DESC"] = "Tema viola classico (predefinito)"
L["COLOR_BLUE"] = "Blu"
L["COLOR_BLUE_DESC"] = "Tema blu fresco"
L["COLOR_GREEN"] = "Verde"
L["COLOR_GREEN_DESC"] = "Tema verde natura"
L["COLOR_RED"] = "Rosso"
L["COLOR_RED_DESC"] = "Tema rosso ardente"
L["COLOR_ORANGE"] = "Arancione"
L["COLOR_ORANGE_DESC"] = "Tema arancione caldo"
L["COLOR_CYAN"] = "Ciano"
L["COLOR_CYAN_DESC"] = "Tema ciano brillante"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "Famiglia carattere"
L["FONT_FAMILY_TOOLTIP"] = "Scegli il carattere utilizzato in tutta l'interfaccia dell'addon"
L["FONT_SCALE"] = "Scala carattere"
L["FONT_SCALE_TOOLTIP"] = "Regola la dimensione del carattere su tutti gli elementi dell'interfaccia"
L["FONT_SCALE_WARNING"] = "Attenzione: Una scala del carattere maggiore potrebbe causare overflow del testo in alcuni elementi dell'interfaccia."
L["RESOLUTION_NORMALIZATION"] = "Normalizzazione risoluzione"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Regola le dimensioni del carattere in base alla risoluzione dello schermo e alla scala dell'interfaccia in modo che il testo rimanga della stessa dimensione fisica su monitor diversi"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Avanzate"

-- =============================================
-- Settings - Module Management
-- =============================================
L["MODULE_MANAGEMENT"] = "Gestione moduli"
L["MODULE_MANAGEMENT_DESC"] = "Attiva o disattiva moduli di raccolta dati specifici. Disattivare un modulo interromperà i suoi aggiornamenti dati e nasconderà la sua scheda dall'interfaccia."
L["MODULE_CURRENCIES"] = "Valute"
L["MODULE_CURRENCIES_DESC"] = "Traccia valute dell'account e specifiche del personaggio (Oro, Onore, Conquista, ecc.)"
L["MODULE_REPUTATIONS"] = "Reputazioni"
L["MODULE_REPUTATIONS_DESC"] = "Traccia il progresso della reputazione con le fazioni, i livelli di fama e le ricompense parangone"
L["MODULE_ITEMS"] = "Oggetti"
L["MODULE_ITEMS_DESC"] = "Traccia gli oggetti della banca di compagnia, funzionalità di ricerca e categorie di oggetti"
L["MODULE_STORAGE"] = "Deposito"
L["MODULE_STORAGE_DESC"] = "Traccia le borse del personaggio, la banca personale e il deposito della banca di compagnia"
L["MODULE_PVE"] = "PvE"
L["MODULE_PVE_DESC"] = "Traccia dungeon Mitica+, progresso raid e ricompense del Grande Forziere"
L["MODULE_PLANS"] = "Piani"
L["MODULE_PLANS_DESC"] = "Traccia obiettivi personali per cavalcature, mascotte, giocattoli, imprese e attività personalizzate"
L["MODULE_PROFESSIONS"] = "Professioni"
L["MODULE_PROFESSIONS_DESC"] = "Traccia abilità professionali, concentrazione, conoscenza e finestra compagno ricette"
L["PROFESSIONS_DISABLED_TITLE"] = "Professioni"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Livello oggetto %s"
L["ITEM_NUMBER_FORMAT"] = "Oggetto #%s"
L["CHARACTER_CURRENCIES"] = "Valute personaggio:"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "Account-wide (Brigata di guerra) — stesso saldo su tutti i personaggi."
L["YOU_MARKER"] = "(Tu)"
L["WN_SEARCH"] = "Ricerca WN"
L["WARBAND_BANK_COLON"] = "Banca Brigata di guerra:"
L["AND_MORE_FORMAT"] = "... e %d altri"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "Hai raccolto una cavalcatura"
L["COLLECTED_PET_MSG"] = "Hai raccolto una mascotte di battaglia"
L["COLLECTED_TOY_MSG"] = "Hai raccolto un giocattolo"
L["COLLECTED_ILLUSION_MSG"] = "Hai raccolto un'illusione"
L["COLLECTED_ITEM_MSG"] = "Hai ottenuto un drop raro"
L["ACHIEVEMENT_COMPLETED_MSG"] = "Impresa completata!"
L["EARNED_TITLE_MSG"] = "Hai ottenuto un titolo"
L["COMPLETED_PLAN_MSG"] = "Hai completato un piano"
L["DAILY_QUEST_CAT"] = "Missione giornaliera"
L["WORLD_QUEST_CAT"] = "Missione mondo"
L["WEEKLY_QUEST_CAT"] = "Missione settimanale"
L["SPECIAL_ASSIGNMENT_CAT"] = "Incarico speciale"
L["DELVE_CAT"] = "Esplorazione"
L["DUNGEON_CAT"] = "Spedizione"
L["RAID_CAT"] = "Incursione"
L["WORLD_CAT"] = "Mondo"
L["ACTIVITY_CAT"] = "Attività"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Progresso"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Progresso completato"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Piano Grande Deposito Settimanale - %s"
L["ALL_SLOTS_COMPLETE"] = "Tutti gli slot completati!"
L["QUEST_COMPLETED_SUFFIX"] = "Completato"
L["WEEKLY_VAULT_READY"] = "Grande Deposito Settimanale pronto!"
L["UNCLAIMED_REWARDS"] = "Hai ricompense non ritirate"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "Oro totale:"
L["CHARACTERS_COLON"] = "Personaggi:"
L["LEFT_CLICK_TOGGLE"] = "Clic sinistro: Attiva/disattiva finestra"
L["RIGHT_CLICK_PLANS"] = "Clic destro: Apri Piani"
L["MINIMAP_SHOWN_MSG"] = "Pulsante minimappa mostrato"
L["MINIMAP_HIDDEN_MSG"] = "Pulsante minimappa nascosto (usa /wn minimap per mostrare)"
L["TOGGLE_WINDOW"] = "Attiva/disattiva finestra"
L["SCAN_BANK_MENU"] = "Scansiona banca"
L["TRACKING_DISABLED_SCAN_MSG"] = "Il tracciamento personaggio è disabilitato. Abilita il tracciamento nelle impostazioni per scansionare la banca."
L["SCAN_COMPLETE_MSG"] = "Scansione completata!"
L["BANK_NOT_OPEN_MSG"] = "La banca non è aperta"
L["OPTIONS_MENU"] = "Opzioni"
L["HIDE_MINIMAP_BUTTON"] = "Nascondi pulsante minimappa"
L["MENU_UNAVAILABLE_MSG"] = "Menu clic destro non disponibile"
L["USE_COMMANDS_MSG"] = "Usa /wn show, /wn options, /wn help"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "Max"
L["OPEN_AND_GUIDE"] = "Apri & Guida"
L["FROM_LABEL"] = "Da:"
L["AVAILABLE_LABEL"] = "Disponibile:"
L["ONLINE_LABEL"] = "(Online)"
L["DATA_SOURCE_TITLE"] = "Informazioni fonte dati"
L["DATA_SOURCE_USING"] = "Questa scheda sta usando:"
L["DATA_SOURCE_MODERN"] = "Servizio cache moderno (guidato da eventi)"
L["DATA_SOURCE_LEGACY"] = "Accesso DB diretto legacy"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Richiede migrazione al servizio cache"
L["GLOBAL_DB_VERSION"] = "Versione DB globale:"

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "Personaggi"
L["INFO_TAB_ITEMS"] = "Oggetti"
L["INFO_TAB_STORAGE"] = "Deposito"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "Reputazioni"
L["INFO_TAB_CURRENCY"] = "Valute"
L["INFO_TAB_PLANS"] = "Piani"
L["INFO_TAB_STATISTICS"] = "Statistiche"
L["SPECIAL_THANKS"] = "Ringraziamenti speciali"
L["SUPPORTERS_TITLE"] = "Sostenitori"
L["THANK_YOU_MSG"] = "Grazie per aver usato Warband Nexus!"

-- =============================================
-- Changelog (What's New) - v2.0.0
-- =============================================
L["CHANGELOG_V200"] = "NUOVE FUNZIONALITÀ:\n" ..
    "- Tracciamento Personaggi: Scegli quali personaggi tracciare o smettere di tracciare.\n" ..
    "- Tracciamento Intelligente Valute e Reputazione: Notifiche in tempo reale nella chat con progresso.\n" ..
    "- Contatore Tentativi Cavalcature: Traccia i tuoi tentativi di drop (In lavorazione).\n" ..
    "- Tracciamento Inventario + Banca + Banca di Banda: Traccia oggetti in tutti i depositi.\n" ..
    "- Sistema Tooltip: Nuovo framework di tooltip personalizzato.\n" ..
    "- Tooltip Tracciatore Oggetti: Vedi quali personaggi possiedono un oggetto al passaggio del mouse.\n" ..
    "- Scheda Piani: Traccia i tuoi prossimi obiettivi — cavalcature, mascotte, giocattoli, imprese, transmog.\n" ..
    "- Finestra Piani: Accesso rapido tramite /wn plan o clic destro sull'icona minimappa.\n" ..
    "- Tracciamento Intelligente Dati Account: Sincronizzazione automatica dei dati di banda.\n" ..
    "- Localizzazione: 11 lingue supportate.\n" ..
    "- Confronto Reputazione e Valute: I tooltip al passaggio mostrano il dettaglio per personaggio.\n" ..
    "- Sistema di Notifiche: Promemoria per bottino, imprese e deposito.\n" ..
    "- Sistema Caratteri Personalizzato: Scegli il tuo carattere e scala preferiti.\n" ..
    "\n" ..
    "MIGLIORAMENTI:\n" ..
    "- Dati personaggio: Fazione, Razza, iLvl e info Chiave del Potere aggiunti.\n" ..
    "- Interfaccia Banca disabilitata (sostituita dal Deposito migliorato).\n" ..
    "- Oggetti Personali: Traccia la tua banca + inventario.\n" ..
    "- Deposito: Traccia banca + inventario + banca di banda su tutti i personaggi.\n" ..
    "- PvE: Indicatore livello deposito, punteggio/tracker dungeon, affissi, valuta potenziamento.\n" ..
    "- Scheda Reputazioni: Vista semplificata (vecchio sistema filtri rimosso).\n" ..
    "- Scheda Valute: Vista semplificata (vecchio sistema filtri rimosso).\n" ..
    "- Statistiche: Contatore mascotte uniche aggiunto.\n" ..
    "- Impostazioni: Riviste e riorganizzate.\n" ..
    "\n" ..
    "Grazie per la vostra pazienza e interesse.\n" ..
    "\n" ..
    "Per segnalare problemi o condividere feedback, lascia un commento su CurseForge - Warband Nexus."

-- =============================================
-- Changelog (What's New) - v2.1.1
-- =============================================
L["CHANGELOG_V211"] = "NUOVE FUNZIONALITÀ:\n" ..
    "- Popup impresa: Clicca sui criteri di impresa collegati per vedere i dettagli con i pulsanti Traccia e +Aggiungi.\n" ..
    "- Indicatore Pianificato: Suffisso giallo \"(Pianificato)\" su oggetti, cavalcature, mascotte, giocattoli e imprese nei tuoi Piani.\n" ..
    "- Filtro Pianificato: Nuova casella nella vista esplora per mostrare solo gli oggetti pianificati.\n" ..
    "- Contatore tentativi per difficoltà: I tentativi ora rispettano la difficoltà di drop (es: cavalcatura Fyrakk solo in Eroico+).\n" ..
    "\n" ..
    "MIGLIORAMENTI:\n" ..
    "- UI Piani: Layout a mosaico per un impacchettamento più compatto delle schede.\n" ..
    "- UI Piani: I criteri completati non sono più interattivi (Traccia/+Aggiungi disabilitati).\n" ..
    "- Tooltip: Icona segno di spunta verde per gli oggetti raccolti (sostituisce il testo \"Raccolto\").\n" ..
    "- Contatore tentativi: Tracciamento di zona per il Frammento scoppiettante con 17+ rari dell'Isola di Dorn.\n" ..
    "- Contatore tentativi: Visualizzazione dei rendimenti di Meccanica varia (3 cavalcature, 6 mascotte) nei tooltip.\n" ..
    "- Midnight 12.0: Protezione valori segreti nella corrispondenza di difficoltà per sicurezza in combattimento.\n" ..
    "\n" ..
    "CORREZIONI BUG:\n" ..
    "- Il contatore tentativi non incrementa più alla difficoltà sbagliata (es: Fyrakk in Normale).\n" ..
    "- I piani appaiono immediatamente dopo +Aggiungi dalla navigazione o dai popup.\n" ..
    "- Il popup impresa si chiude cliccando all'esterno.\n" ..
    "- Le notifiche per giocattoli da venditori e mascotte rilevate funzionano di nuovo.\n" ..
    "- Le notifiche per drop di oggetti ripetibili funzionano di nuovo.\n" ..
    "- Corretti spazi nel layout delle schede al primo caricamento della scheda Piani.\n" ..
    "\n" ..
    "Grazie per il vostro continuo supporto!\n" ..
    "\n" ..
    "Per segnalare problemi o condividere feedback, lascia un commento su CurseForge - Warband Nexus."

-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "Conferma azione"
L["CONFIRM"] = "Conferma"
L["ENABLE_TRACKING_FORMAT"] = "Attivare il tracciamento per |cffffcc00%s|r?"
L["DISABLE_TRACKING_FORMAT"] = "Disattivare il tracciamento per |cffffcc00%s|r?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "Reputazioni dell'intero account (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Reputazioni basate sul personaggio (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "Ricompensa in attesa"
L["REP_PARAGON_LABEL"] = "Eccellenza"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "Preparazione..."
L["REP_LOADING_INITIALIZING"] = "Inizializzazione..."
L["REP_LOADING_FETCHING"] = "Recupero dati reputazione..."
L["REP_LOADING_PROCESSING"] = "Elaborazione %d fazioni..."
L["REP_LOADING_PROCESSING_COUNT"] = "Elaborazione... (%d/%d)"
L["REP_LOADING_SAVING"] = "Salvataggio nel database..."
L["REP_LOADING_COMPLETE"] = "Completato!"

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "Impossibile aprire la finestra durante il combattimento. Riprova dopo che il combattimento è terminato."
L["BANK_IS_ACTIVE"] = "La banca è attiva"
L["ITEMS_CACHED_FORMAT"] = "%d oggetti memorizzati"
-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "PERSONAGGIO"
L["TABLE_HEADER_LEVEL"] = "LIVELLO"
L["TABLE_HEADER_GOLD"] = "ORO"
L["TABLE_HEADER_LAST_SEEN"] = "ULTIMA VISITA"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "Nessun oggetto corrisponde a '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "Nessun oggetto corrisponde alla tua ricerca"
L["ITEMS_SCAN_HINT"] = "Gli oggetti vengono scansionati automaticamente. Prova /reload se non appare nulla."
L["ITEMS_WARBAND_BANK_HINT"] = "Apri la Banca Brigata di guerra per scansionare gli oggetti (scansione automatica al primo accesso)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Prossimi passi:"
L["CURRENCY_TRANSFER_STEP_1"] = "Trova |cffffffff%s|r nel pannello valute"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800Clic destro|r su di esso"
L["CURRENCY_TRANSFER_STEP_3"] = "Seleziona |cffffffff'Trasferisci alla Brigata di guerra'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Scegli |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Inserisci importo: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "Il pannello valute è ora aperto!"
L["CURRENCY_TRANSFER_SECURITY"] = "(La sicurezza di Blizzard impedisce il trasferimento automatico)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "Zona: "
L["ADDED"] = "Aggiunto"
L["WEEKLY_VAULT_TRACKER"] = "Tracciatore Grande Deposito Settimanale"
L["DAILY_QUEST_TRACKER"] = "Tracciatore Missioni Giornaliere"
L["CUSTOM_PLAN_STATUS"] = "Piano personalizzato '%s' %s"

-- =============================================
-- Achievement Popup
-- =============================================
L["ACHIEVEMENT_COMPLETED"] = "Completato"
L["ACHIEVEMENT_NOT_COMPLETED"] = "Non completato"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d punti"
L["ADD_PLAN"] = "Aggiungi"
L["PLANNED"] = "Pianificato"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = "Spedizione"
L["VAULT_SLOT_RAIDS"] = "Incursioni"
L["VAULT_SLOT_WORLD"] = "Mondo"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "Affisso"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_STANDING_LABEL"] = "Ora"
L["CHAT_GAINED_PREFIX"] = "+"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "Piano completato: "
L["WEEKLY_VAULT_PLAN_NAME"] = "Grande Deposito Settimanale - %s"
L["VAULT_PLANS_RESET"] = "I piani Grande Deposito Settimanale sono stati ripristinati! (%d piano/i)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "Nessun personaggio trovato"
L["EMPTY_CHARACTERS_DESC"] = "Accedi con i tuoi personaggi per iniziare a tracciarli.\nI dati vengono raccolti automaticamente ad ogni accesso."
L["EMPTY_ITEMS_TITLE"] = "Nessun oggetto in cache"
L["EMPTY_ITEMS_DESC"] = "Apri la banca della brigata o personale per scansionare gli oggetti.\nGli oggetti vengono memorizzati automaticamente alla prima visita."
L["EMPTY_STORAGE_TITLE"] = "Nessun dato di archiviazione"
L["EMPTY_STORAGE_DESC"] = "Gli oggetti vengono scansionati all'apertura di banche o borse.\nVisita una banca per iniziare a tracciare il tuo deposito."
L["EMPTY_PLANS_TITLE"] = "Nessun piano ancora"
L["EMPTY_PLANS_DESC"] = "Sfoglia cavalcature, mascotte, giocattoli o imprese sopra\nper aggiungere obiettivi e tracciare i tuoi progressi."
L["EMPTY_REPUTATION_TITLE"] = "Nessun dato di reputazione"
L["EMPTY_REPUTATION_DESC"] = "Le reputazioni vengono scansionate automaticamente all'accesso.\nAccedi con un personaggio per tracciare le fazioni."
L["EMPTY_CURRENCY_TITLE"] = "Nessun dato di valuta"
L["EMPTY_CURRENCY_DESC"] = "Le valute vengono tracciate automaticamente su tutti i personaggi.\nAccedi con un personaggio per tracciare le valute."
L["EMPTY_PVE_TITLE"] = "Nessun dato PvE"
L["EMPTY_PVE_DESC"] = "I progressi PvE vengono tracciati quando accedi con i personaggi.\nGrande Deposito, Mitica+ e blocchi raid appariranno qui."
L["EMPTY_STATISTICS_TITLE"] = "Nessuna statistica disponibile"
L["EMPTY_STATISTICS_DESC"] = "Le statistiche provengono dai personaggi tracciati.\nAccedi con un personaggio per raccogliere dati."
L["NO_ADDITIONAL_INFO"] = "Nessuna informazione aggiuntiva"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "Vuoi tracciare questo personaggio?"
L["CLEANUP_NO_INACTIVE"] = "Nessun personaggio inattivo trovato (90+ giorni)"
L["CLEANUP_REMOVED_FORMAT"] = "Rimossi %d personaggio/i inattivo/i"
L["TRACKING_ENABLED_MSG"] = "Tracciamento personaggio ATTIVATO!"
L["TRACKING_DISABLED_MSG"] = "Tracciamento personaggio DISATTIVATO!"
L["TRACKING_ENABLED"] = "Tracciamento ATTIVATO"
L["TRACKING_DISABLED"] = "Tracciamento DISATTIVATO (modalità sola lettura)"
L["STATUS_LABEL"] = "Stato:"
L["ERROR_LABEL"] = "Errore:"
L["ERROR_NAME_REALM_REQUIRED"] = "Nome personaggio e reame richiesti"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s ha già un piano settimanale attivo"

-- Profiles (AceDB)
L["PROFILES"] = "Profili"
L["PROFILES_DESC"] = "Gestisci i profili dell'addon"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "Nessun criterio trovato"
L["NO_REQUIREMENTS_INSTANT"] = "Nessun requisito (completamento istantaneo)"

-- Statistics Tab (missing)
L["TOTAL_PETS"] = "Mascotte totali"

-- Items Tab (missing)
L["ITEM_LOADING_NAME"] = "Caricamento..."

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
L["TAB_PROFESSIONS"] = "Professioni"
L["YOUR_PROFESSIONS"] = "Professioni della Brigata"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s personaggi con professioni"
L["HEADER_PROFESSIONS"] = "Panoramica Professioni"
L["NO_PROFESSIONS_DATA"] = "Nessun dato professione disponibile. Apri la finestra professione (predefinito: K) su ogni personaggio per raccogliere i dati."
L["CONCENTRATION"] = "Concentrazione"
L["KNOWLEDGE"] = "Conoscenza"
L["SKILL"] = "Abilità"
L["RECIPES"] = "Ricette"
L["UNSPENT_POINTS"] = "Punti non spesi"
L["COLLECTIBLE"] = "Collezionabile"
L["RECHARGE"] = "Ricarica"
L["FULL"] = "Pieno"
L["PROF_OPEN_RECIPE"] = "Apri"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "Apri l'elenco ricette di questa professione"
L["PROF_ONLY_CURRENT_CHAR"] = "Disponibile solo per il personaggio attuale"
L["NO_PROFESSION"] = "Nessuna professione"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "Prima creazione"
L["SKILL_UPS"] = "Progressione abilità"
L["COOLDOWNS"] = "Tempi di recupero"
L["ORDERS"] = "Ordini"

-- Professions: Tooltips & Details
L["LEARNED_RECIPES"] = "Ricette apprese"
L["UNLEARNED_RECIPES"] = "Ricette non apprese"
L["LAST_SCANNED"] = "Ultima scansione"
L["JUST_NOW"] = "Proprio ora"
L["RECIPE_NO_DATA"] = "Apri la finestra professione per raccogliere i dati delle ricette"
L["FIRST_CRAFT_AVAILABLE"] = "Prime creazioni disponibili"
L["FIRST_CRAFT_DESC"] = "Ricette che concedono XP bonus alla prima creazione"
L["SKILLUP_RECIPES"] = "Ricette di progressione"
L["SKILLUP_DESC"] = "Ricette che possono ancora aumentare il tuo livello di abilità"
L["NO_ACTIVE_COOLDOWNS"] = "Nessun tempo di recupero attivo"

-- Professions: Crafting Orders
L["CRAFTING_ORDERS"] = "Ordini di creazione"
L["PERSONAL_ORDERS"] = "Ordini personali"
L["PUBLIC_ORDERS"] = "Ordini pubblici"
L["CLAIMS_REMAINING"] = "Rivendicazioni rimanenti"
L["NO_ACTIVE_ORDERS"] = "Nessun ordine attivo"
L["ORDER_NO_DATA"] = "Apri la professione al banco da lavoro per scansionare"

-- Professions: Equipment
L["EQUIPMENT"] = "Equipaggiamento"
L["TOOL"] = "Strumento"
L["ACCESSORY"] = "Accessorio"

-- =============================================
-- New keys (v2.1.0)
-- =============================================
L["TOOLTIP_ATTEMPTS"] = "tentativi"
L["TOOLTIP_100_DROP"] = "100%% Drop"
L["TOOLTIP_UNKNOWN"] = "Sconosciuto"
L["TOOLTIP_WARBAND_BANK"] = "Banca Brigata"
L["TOOLTIP_HOLD_SHIFT"] = "  Tieni premuto [Maiusc] per l'elenco completo"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - Concentrazione"
L["TOOLTIP_FULL"] = "(Pieno)"
L["NO_ITEMS_CACHED_TITLE"] = "Nessun oggetto in cache"
L["COMBAT_CURRENCY_ERROR"] = "Impossibile aprire il pannello valute durante il combattimento. Riprova dopo il combattimento."
L["DB_LABEL"] = "DB:"
L["COLLECTING_PVE"] = "Raccolta dati PvE"
L["PVE_PREPARING"] = "Preparazione"
L["PVE_GREAT_VAULT"] = "Gran Camera"
L["PVE_MYTHIC_SCORES"] = "Punteggi Mitica+"
L["PVE_RAID_LOCKOUTS"] = "Blocchi Incursioni"
L["PVE_INCOMPLETE_DATA"] = "Alcuni dati potrebbero essere incompleti. Prova ad aggiornare più tardi."
L["VAULT_SLOTS_TO_FILL"] = "%d slot Gran Camera%s da riempire"
L["VAULT_SLOT_PLURAL"] = ""
L["REP_RENOWN_NEXT"] = "Fama %d"
L["REP_TO_NEXT_FORMAT"] = "%s rep fino a %s (%s)"
L["REP_FACTION_FALLBACK"] = "Fazione"
L["COLLECTION_CANCELLED"] = "Raccolta annullata dall'utente"
L["CLEANUP_STALE_FORMAT"] = "Rimossi %d personaggio/i obsoleti"
L["PERSONAL_BANK"] = "Banca personale"
L["WARBAND_BANK_LABEL"] = "Banca Brigata"
L["WARBAND_BANK_TAB_FORMAT"] = "Scheda %d"
L["CURRENCY_OTHER"] = "Altro"
L["ERROR_SAVING_CHARACTER"] = "Errore nel salvataggio del personaggio:"
L["STANDING_HATED"] = "Odiato"
L["STANDING_HOSTILE"] = "Ostile"
L["STANDING_UNFRIENDLY"] = "Scortese"
L["STANDING_NEUTRAL"] = "Neutrale"
L["STANDING_FRIENDLY"] = "Amichevole"
L["STANDING_HONORED"] = "Onorato"
L["STANDING_REVERED"] = "Riverito"
L["STANDING_EXALTED"] = "Osannato"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d tentativi per %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "Ottenuto %s! Contatore tentativi azzerato."
L["TRYCOUNTER_CAUGHT_RESET"] = "Catturato %s! Contatore tentativi azzerato."
L["TRYCOUNTER_CONTAINER_RESET"] = "Ottenuto %s dal contenitore! Contatore tentativi azzerato."
L["TRYCOUNTER_LOCKOUT_SKIP"] = "Saltato: blocco giornaliero/settimanale attivo per questo PNG."
L["TRYCOUNTER_INSTANCE_DROPS"] = "Collezionabili in questa istanza:"
L["TRYCOUNTER_COLLECTED_TAG"] = "(Raccolto)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " tentativi"
L["TRYCOUNTER_TYPE_MOUNT"] = "Cavalcatura"
L["TRYCOUNTER_TYPE_PET"] = "Mascotte"
L["TRYCOUNTER_TYPE_TOY"] = "Giocattolo"
L["TRYCOUNTER_TYPE_ITEM"] = "Oggetto"
L["TRYCOUNTER_TRY_COUNTS"] = "Contatori tentativi"
L["LT_CHARACTER_DATA"] = "Dati personaggio"
L["LT_CURRENCY_CACHES"] = "Valute e cache"
L["LT_REPUTATIONS"] = "Reputazioni"
L["LT_PROFESSIONS"] = "Professioni"
L["LT_PVE_DATA"] = "Dati PvE"
L["LT_COLLECTIONS"] = "Collezioni"
L["CONFIG_HEADER"] = "Warband Nexus"
L["CONFIG_HEADER_DESC"] = "Gestione moderna della Brigata e tracciamento tra personaggi."
L["CONFIG_GENERAL"] = "Impostazioni generali"
L["CONFIG_GENERAL_DESC"] = "Impostazioni base dell'addon e opzioni di comportamento."
L["CONFIG_ENABLE"] = "Abilita addon"
L["CONFIG_ENABLE_DESC"] = "Attiva o disattiva l'addon."
L["CONFIG_MINIMAP"] = "Pulsante minimappa"
L["CONFIG_MINIMAP_DESC"] = "Mostra un pulsante sulla minimappa per accesso rapido."
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "Mostra oggetti nei suggerimenti"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "Mostra le quantità di oggetti Brigata e personaggio nei suggerimenti degli oggetti."
L["CONFIG_MODULES"] = "Gestione moduli"
L["CONFIG_MODULES_DESC"] = "Abilita o disabilita i singoli moduli dell'addon. I moduli disabilitati non raccoglieranno dati né mostreranno schede nell'interfaccia."
L["CONFIG_MOD_CURRENCIES"] = "Valute"
L["CONFIG_MOD_CURRENCIES_DESC"] = "Traccia le valute su tutti i personaggi."
L["CONFIG_MOD_REPUTATIONS"] = "Reputazioni"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "Traccia le reputazioni su tutti i personaggi."
L["CONFIG_MOD_ITEMS"] = "Oggetti"
L["CONFIG_MOD_ITEMS_DESC"] = "Traccia gli oggetti in borse e banche."
L["CONFIG_MOD_STORAGE"] = "Deposito"
L["CONFIG_MOD_STORAGE_DESC"] = "Scheda deposito per inventario e gestione banca."
L["CONFIG_MOD_PVE"] = "PvE"
L["CONFIG_MOD_PVE_DESC"] = "Traccia Gran Camera, Mitica+ e blocchi incursioni."
L["CONFIG_MOD_PLANS"] = "Piani"
L["CONFIG_MOD_PLANS_DESC"] = "Tracciamento piani di collezione e obiettivi di completamento."
L["CONFIG_MOD_PROFESSIONS"] = "Professioni"
L["CONFIG_MOD_PROFESSIONS_DESC"] = "Traccia abilità professionali, ricette e concentrazione."
L["CONFIG_AUTOMATION"] = "Automazione"
L["CONFIG_AUTOMATION_DESC"] = "Controlla cosa succede automaticamente quando apri la Banca Brigata."
L["CONFIG_AUTO_OPTIMIZE"] = "Ottimizzazione automatica database"
L["CONFIG_AUTO_OPTIMIZE_DESC"] = "Ottimizza automaticamente il database all'accesso per mantenere lo storage efficiente."
L["CONFIG_SHOW_ITEM_COUNT"] = "Mostra quantità oggetti"
L["CONFIG_SHOW_ITEM_COUNT_DESC"] = "Mostra suggerimenti con la quantità di ogni oggetto che possiedi su tutti i personaggi."
L["CONFIG_THEME_COLOR"] = "Colore tema principale"
L["CONFIG_THEME_COLOR_DESC"] = "Scegli il colore di accento principale per l'interfaccia dell'addon."
L["CONFIG_THEME_PRESETS"] = "Temi predefiniti"
L["CONFIG_THEME_APPLIED"] = "Tema %s applicato!"
L["CONFIG_THEME_RESET_DESC"] = "Ripristina tutti i colori del tema al viola predefinito."
L["CONFIG_NOTIFICATIONS"] = "Notifiche"
L["CONFIG_NOTIFICATIONS_DESC"] = "Configura quali notifiche vengono mostrate."
L["CONFIG_ENABLE_NOTIFICATIONS"] = "Abilita notifiche"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "Mostra notifiche popup per eventi collezionabili."
L["CONFIG_NOTIFY_MOUNTS"] = "Notifiche cavalcature"
L["CONFIG_NOTIFY_MOUNTS_DESC"] = "Mostra notifiche quando impari una nuova cavalcatura."
L["CONFIG_NOTIFY_PETS"] = "Notifiche mascotte"
L["CONFIG_NOTIFY_PETS_DESC"] = "Mostra notifiche quando impari una nuova mascotte."
L["CONFIG_NOTIFY_TOYS"] = "Notifiche giocattoli"
L["CONFIG_NOTIFY_TOYS_DESC"] = "Mostra notifiche quando impari un nuovo giocattolo."
L["CONFIG_NOTIFY_ACHIEVEMENTS"] = "Notifiche imprese"
L["CONFIG_NOTIFY_ACHIEVEMENTS_DESC"] = "Mostra notifiche quando ottieni un'impresa."
L["CONFIG_SHOW_UPDATE_NOTES"] = "Mostra di nuovo le note di aggiornamento"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "Mostra la finestra Novità al prossimo accesso."
L["CONFIG_UPDATE_NOTES_SHOWN"] = "La notifica di aggiornamento verrà mostrata al prossimo accesso."
L["CONFIG_RESET_PLANS"] = "Ripristina piani completati"
L["CONFIG_RESET_PLANS_CONFIRM"] = "Questo rimuoverà tutti i piani completati. Continuare?"
L["CONFIG_RESET_PLANS_FORMAT"] = "Rimossi %d piano/i completato/i."
L["CONFIG_NO_COMPLETED_PLANS"] = "Nessun piano completato da rimuovere."
L["CONFIG_TAB_FILTERING"] = "Filtraggio schede"
L["CONFIG_TAB_FILTERING_DESC"] = "Scegli quali schede sono visibili nella finestra principale."
L["CONFIG_CHARACTER_MGMT"] = "Gestione personaggi"
L["CONFIG_CHARACTER_MGMT_DESC"] = "Gestisci i personaggi tracciati e rimuovi dati obsoleti."
L["CONFIG_DELETE_CHAR"] = "Elimina dati personaggio"
L["CONFIG_DELETE_CHAR_DESC"] = "Rimuovi permanentemente tutti i dati memorizzati per il personaggio selezionato."
L["CONFIG_DELETE_CONFIRM"] = "Sei sicuro di voler eliminare permanentemente tutti i dati di questo personaggio? Questa azione non può essere annullata."
L["CONFIG_DELETE_SUCCESS"] = "Dati personaggio eliminati:"
L["CONFIG_DELETE_FAILED"] = "Dati personaggio non trovati."
L["CONFIG_FONT_SCALING"] = "Carattere e scala"
L["CONFIG_FONT_SCALING_DESC"] = "Regola famiglia e dimensione del carattere."
L["CONFIG_FONT_FAMILY"] = "Famiglia carattere"
L["CONFIG_FONT_SIZE"] = "Scala dimensione carattere"
L["CONFIG_FONT_PREVIEW"] = "Anteprima: The quick brown fox jumps over the lazy dog"
L["CONFIG_ADVANCED"] = "Avanzate"
L["CONFIG_ADVANCED_DESC"] = "Impostazioni avanzate e gestione database. Usare con cautela!"
L["CONFIG_DEBUG_MODE"] = "Modalità debug"
L["CONFIG_DEBUG_MODE_DESC"] = "Abilita registrazione dettagliata per debug. Abilita solo per risolvere problemi."
L["CONFIG_DB_STATS"] = "Mostra statistiche database"
L["CONFIG_DB_STATS_DESC"] = "Mostra dimensione attuale del database e statistiche di ottimizzazione."
L["CONFIG_DB_OPTIMIZER_NA"] = "Ottimizzatore database non caricato"
L["CONFIG_OPTIMIZE_NOW"] = "Ottimizza database ora"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "Esegui l'ottimizzatore database per ripulire e comprimere i dati memorizzati."
L["CONFIG_COMMANDS_HEADER"] = "Comandi slash"
L["DISPLAY_SETTINGS"] = "Visualizzazione"
L["DISPLAY_SETTINGS_DESC"] = "Personalizza come oggetti e informazioni vengono mostrati."
L["RESET_DEFAULT"] = "Ripristina predefinito"
L["ANTI_ALIASING"] = "Anti-aliasing"
L["PROFESSIONS_INFO_DESC"] = "Traccia abilità professionali, concentrazione, conoscenza e alberi di specializzazione su tutti i personaggi. Include Recipe Companion per le fonti di reagenti."
L["CONTRIBUTORS_TITLE"] = "Collaboratori"
L["CHANGELOG_V210"] = "NUOVE FUNZIONALITÀ:\n" ..
    "- Scheda Professioni: Traccia abilità professionali, concentrazione, conoscenza e alberi di specializzazione su tutti i personaggi.\n" ..
    "- Finestra Recipe Companion: Sfoglia e traccia ricette con fonti di reagenti dalla tua Warband Bank.\n" ..
    "- Overlay di caricamento: Indicatore di progresso visivo durante la sincronizzazione dei dati.\n" ..
    "- Deduplicazione persistente delle notifiche: Le notifiche dei collezionabili non si ripetono più tra le sessioni.\n" ..
    "\n" ..
    "MIGLIORAMENTI:\n" ..
    "- Prestazioni: Riduzione significativa dei cali FPS al login con inizializzazione a budget di tempo.\n" ..
    "- Prestazioni: Rimosso lo scan del Journal delle istanze per eliminare i picchi di frame.\n" ..
    "- PvE: I dati dei personaggi alternativi ora persistono e si visualizzano correttamente tra i personaggi.\n" ..
    "- PvE: Dati del Great Vault salvati al logout per prevenire perdita di dati asincrona.\n" ..
    "- Valute: Visualizzazione gerarchica delle intestazioni conforme all'UI nativa di Blizzard (Legacy, raggruppamento Stagione).\n" ..
    "- Valute: Popolamento iniziale dei dati più veloce.\n" ..
    "- Notifiche: Avvisi soppressi per oggetti non farmabili (ricompense missione, oggetti da mercante).\n" ..
    "- Impostazioni: La finestra ora riutilizza i frame e non sposta più la finestra principale alla chiusura.\n" ..
    "- Tracciamento personaggi: Raccolta dati completamente condizionata alla conferma di tracciamento.\n" ..
    "- Personaggi: Le righe delle professioni ora si visualizzano per personaggi senza professioni.\n" ..
    "- Interfaccia: Spaziatura del testo migliorata (formato X : Y) su tutte le visualizzazioni.\n" ..
    "\n" ..
    "CORREZIONI:\n" ..
    "- Corretto: Notifica bottino ricorrente per collezionabili già posseduti ad ogni login.\n" ..
    "- Corretto: Menu ESC disabilitato dopo l'eliminazione di un personaggio.\n" ..
    "- Corretto: Ancora della finestra principale che si spostava alla chiusura delle Impostazioni con ESC.\n" ..
    "- Corretto: \"Most Played\" visualizzava i personaggi in modo errato.\n" ..
    "- Corretto: Dati del Great Vault non visualizzati per personaggi alternativi.\n" ..
    "- Corretto: Nomi dei reami visualizzati senza spazi.\n" ..
    "- Corretto: Info collezionabile del tooltip non visualizzata al primo hover.\n" ..
    "\n" ..
    "Grazie per il tuo continuo supporto!\n" ..
    "\n" ..
    "Per segnalare problemi o condividere feedback, lascia un commento su CurseForge - Warband Nexus."
L["ANTI_ALIASING_DESC"] = "Stile di rendering dei bordi del carattere (influenza la leggibilità)"
