--[[
    Warband Nexus - Spanish (Spain) Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "esES")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus cargado. Escribe /wn o /warbandnexus para opciones."
L["VERSION"] = GAME_VERSION_LABEL or "Versi�n"

-- Slash Commands
L["SLASH_HELP"] = "Comandos disponibles:"
L["SLASH_OPTIONS"] = "Abrir panel de opciones"
L["SLASH_SCAN"] = "Escanear banco de banda de guerra"
L["SLASH_SHOW"] = "Mostrar/ocultar ventana principal"
L["SLASH_DEPOSIT"] = "Abrir cola de dep�sito"
L["SLASH_SEARCH"] = "Buscar un objeto"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Configuraci�n general"
L["GENERAL_SETTINGS_DESC"] = "Configurar el comportamiento general del addon"
L["ENABLE_ADDON"] = "Activar addon"
L["ENABLE_ADDON_DESC"] = "Activar o desactivar la funcionalidad de Warband Nexus"
L["MINIMAP_ICON"] = "Mostrar icono del minimapa"
L["MINIMAP_ICON_DESC"] = "Mostrar u ocultar el bot�n del minimapa"
L["DEBUG_MODE"] = "Modo de depuraci�n"
L["DEBUG_MODE_DESC"] = "Activar mensajes de depuraci�n en el chat"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "Configuraci�n de escaneo"
L["SCANNING_SETTINGS_DESC"] = "Configurar el comportamiento de escaneo del banco"
L["AUTO_SCAN"] = "Escaneo autom�tico al abrir"
L["AUTO_SCAN_DESC"] = "Escanear autom�ticamente el banco de banda de guerra al abrirlo"
L["SCAN_DELAY"] = "Retraso de escaneo"
L["SCAN_DELAY_DESC"] = "Retraso entre operaciones de escaneo (en segundos)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "Configuraci�n de dep�sito"
L["DEPOSIT_SETTINGS_DESC"] = "Configurar el comportamiento de dep�sito de objetos"
L["GOLD_RESERVE"] = "Reserva de oro"
L["GOLD_RESERVE_DESC"] = "Oro m�nimo a mantener en el inventario personal (en oro)"
L["AUTO_DEPOSIT_REAGENTS"] = "Depositar reactivos autom�ticamente"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "Poner reactivos en cola de dep�sito al abrir el banco"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Configuraci�n de pantalla"
L["DISPLAY_SETTINGS_DESC"] = "Configurar la apariencia visual"
L["SHOW_ITEM_LEVEL"] = "Mostrar nivel de objeto"
L["SHOW_ITEM_LEVEL_DESC"] = "Mostrar nivel de objeto en equipamiento"
L["SHOW_ITEM_COUNT"] = "Mostrar cantidad de objetos"
L["SHOW_ITEM_COUNT_DESC"] = "Mostrar cantidades apiladas en objetos"
L["HIGHLIGHT_QUALITY"] = "Resaltar por calidad"
L["HIGHLIGHT_QUALITY_DESC"] = "A�adir bordes de color seg�n la calidad del objeto"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "Configuraci�n de pesta�as"
L["TAB_SETTINGS_DESC"] = "Configurar el comportamiento de las pesta�as del banco de banda de guerra"
L["IGNORED_TABS"] = "Pesta�as ignoradas"
L["IGNORED_TABS_DESC"] = "Seleccionar pesta�as a excluir del escaneo y operaciones"
L["TAB_1"] = "Pesta�a de banda de guerra 1"
L["TAB_2"] = "Pesta�a de banda de guerra 2"
L["TAB_3"] = "Pesta�a de banda de guerra 3"
L["TAB_4"] = "Pesta�a de banda de guerra 4"
L["TAB_5"] = "Pesta�a de banda de guerra 5"

-- Scanner Module
L["SCAN_STARTED"] = "Escaneando banco de banda de guerra..."
L["SCAN_COMPLETE"] = "Escaneo completado. Se encontraron %d objetos en %d espacios."
L["SCAN_FAILED"] = "Escaneo fallido: El banco de banda de guerra no est� abierto."
L["SCAN_TAB"] = "Escaneando pesta�a %d..."
L["CACHE_CLEARED"] = "Cach� de objetos borrada."
L["CACHE_UPDATED"] = "Cach� de objetos actualizada."

-- Banker Module
L["BANK_NOT_OPEN"] = "El banco de banda de guerra no est� abierto."
L["DEPOSIT_STARTED"] = "Iniciando operaci�n de dep�sito..."
L["DEPOSIT_COMPLETE"] = "Dep�sito completado. %d objetos transferidos."
L["DEPOSIT_CANCELLED"] = "Dep�sito cancelado."
L["DEPOSIT_QUEUE_EMPTY"] = "La cola de dep�sito est� vac�a."
L["DEPOSIT_QUEUE_CLEARED"] = "Cola de dep�sito vaciada."
L["ITEM_QUEUED"] = "%s en cola para dep�sito."
L["ITEM_REMOVED"] = "%s eliminado de la cola."
L["GOLD_DEPOSITED"] = "%s oro depositado en el banco de banda de guerra."
L["INSUFFICIENT_GOLD"] = "Oro insuficiente para el dep�sito."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "Cantidad no v�lida."
L["WITHDRAW_BANK_NOT_OPEN"] = "�El banco debe estar abierto para retirar!"
L["WITHDRAW_IN_COMBAT"] = "No se puede retirar durante el combate."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "No hay suficiente oro en el banco de banda de guerra."
L["WITHDRAWN_LABEL"] = "Retirado:"
L["WITHDRAW_API_UNAVAILABLE"] = "API de retiro no disponible."
L["SORT_IN_COMBAT"] = "No se puede ordenar durante el combate."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global: SEARCH
L["SEARCH_CATEGORY_FORMAT"] = "Buscar %s..."
L["BTN_SCAN"] = "Escanear banco"
L["BTN_DEPOSIT"] = "Cola de dep�sito"
L["BTN_SORT"] = "Ordenar banco"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global: CLOSE
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global: SETTINGS
L["BTN_REFRESH"] = REFRESH -- Blizzard Global: REFRESH
L["BTN_CLEAR_QUEUE"] = "Vaciar cola"
L["BTN_DEPOSIT_ALL"] = "Depositar todo"
L["BTN_DEPOSIT_GOLD"] = "Depositar oro"
L["ENABLE"] = ENABLE or "Activar" -- Blizzard Global
L["ENABLE_MODULE"] = "Activar m�dulo"

-- Main Tabs (Blizzard Globals where available)
L["TAB_CHARACTERS"] = CHARACTER or "Personajes" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "Objetos" -- Blizzard Global
L["TAB_STORAGE"] = "Almacenamiento"
L["TAB_PLANS"] = "Planes"
L["TAB_REPUTATION"] = REPUTATION or "Reputaci�n" -- Blizzard Global
L["TAB_REPUTATIONS"] = "Reputaciones"
L["TAB_CURRENCY"] = CURRENCY or "Moneda" -- Blizzard Global
L["TAB_CURRENCIES"] = "Monedas"
L["TAB_PVE"] = "JcE"
L["TAB_STATISTICS"] = STATISTICS or "Estad�sticas" -- Blizzard Global

-- Item Categories (Using Blizzard Globals where available)
L["CATEGORY_ALL"] = ALL or "Todos los objetos" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipamiento" -- Blizzard Global
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumibles" -- Blizzard Global
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reactivos" -- Blizzard Global
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Mercanc�as" -- Blizzard Global
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Objetos de misi�n" -- Blizzard Global
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Miscel�nea" -- Blizzard Global

-- Quality Filters (Using Blizzard Globals - automatically localized!)
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC -- Blizzard Global: "Poor"
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC -- Blizzard Global: "Common"
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC -- Blizzard Global: "Uncommon"
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC -- Blizzard Global: "Rare"
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC -- Blizzard Global: "Epic"
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC -- Blizzard Global: "Legendary"
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC -- Blizzard Global: "Artifact"
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC -- Blizzard Global: "Heirloom"

-- Characters Tab
L["HEADER_FAVORITES"] = FAVORITES or "Favoritos" -- Blizzard Global
L["HEADER_CHARACTERS"] = CHARACTER or "Personajes"
L["HEADER_CURRENT_CHARACTER"] = "PERSONAJE ACTUAL"
L["HEADER_WARBAND_GOLD"] = "ORO DE BANDA DE GUERRA"
L["HEADER_TOTAL_GOLD"] = "ORO TOTAL"
L["HEADER_REALM_GOLD"] = "ORO DEL REINO"
L["HEADER_REALM_TOTAL"] = "TOTAL DEL REINO"
L["CHARACTER_LAST_SEEN_FORMAT"] = "Visto por �ltima vez: %s"
L["CHARACTER_GOLD_FORMAT"] = "Oro: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "Oro combinado de todos los personajes en este reino"

-- Items Tab
L["ITEMS_HEADER"] = "Objetos del banco"
L["ITEMS_HEADER_DESC"] = "Explorar y gestionar tu banco de banda de guerra y personal"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " objetos..."
L["ITEMS_WARBAND_BANK"] = "Banco de banda de guerra"
L["ITEMS_PLAYER_BANK"] = BANK or "Banco personal" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Banco de hermandad" -- Blizzard Global
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipamiento"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumibles"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reactivos"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Mercanc�as"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Misi�n"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscel�nea"
L["GROUP_CONTAINER"] = "Contenedores"

-- Storage Tab
L["STORAGE_HEADER"] = "Explorador de almacenamiento"
L["STORAGE_HEADER_DESC"] = "Explorar todos los objetos organizados por tipo"
L["STORAGE_WARBAND_BANK"] = "Banco de banda de guerra"
L["STORAGE_PERSONAL_BANKS"] = "Bancos personales"
L["STORAGE_TOTAL_SLOTS"] = "Espacios totales"
L["STORAGE_FREE_SLOTS"] = "Espacios libres"
L["STORAGE_BAG_HEADER"] = "Bolsas de banda de guerra"
L["STORAGE_PERSONAL_HEADER"] = "Banco personal"

-- Plans Tab
L["PLANS_MY_PLANS"] = "Mis planes"
L["PLANS_COLLECTIONS"] = "Planes de colecci�n"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "A�adir plan personalizado"
L["PLANS_NO_RESULTS"] = "No se encontraron resultados."
L["PLANS_ALL_COLLECTED"] = "�Todos los objetos recolectados!"
L["PLANS_RECIPE_HELP"] = "Haz clic derecho en las recetas de tu inventario para a�adirlas aqu�."
L["COLLECTION_PLANS"] = "Planes de colecci�n"
L["SEARCH_PLANS"] = "Buscar planes..."
L["COMPLETED_PLANS"] = "Planes completados"
L["SHOW_COMPLETED"] = "Mostrar completados"
L["SHOW_PLANNED"] = "Mostrar planeados"
L["NO_PLANNED_ITEMS"] = "A�n no hay %ss planeados"

-- Plans Categories (Blizzard Globals where available)
L["CATEGORY_MY_PLANS"] = "Mis planes"
L["CATEGORY_DAILY_TASKS"] = "Tareas diarias"
L["CATEGORY_MOUNTS"] = MOUNTS or "Monturas" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "Mascotas" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "Juguetes" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transfiguraci�n" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "Ilusiones"
L["CATEGORY_TITLES"] = TITLES or "T�tulos"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Logros" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " reputaci�n..."
L["REP_HEADER_WARBAND"] = "Reputaci�n de banda de guerra"
L["REP_HEADER_CHARACTER"] = "Reputaci�n del personaje"
L["REP_STANDING_FORMAT"] = "Rango: %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " moneda..."
L["CURRENCY_HEADER_WARBAND"] = "Transferible entre banda"
L["CURRENCY_HEADER_CHARACTER"] = "Vinculado al personaje"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "Bandas" -- Blizzard Global
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Mazmorras" -- Blizzard Global
L["PVE_HEADER_DELVES"] = "Excavaciones"
L["PVE_HEADER_WORLD_BOSS"] = "Jefes de mundo"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "Estad�sticas" -- Blizzard Global: STATISTICS
L["STATS_TOTAL_ITEMS"] = "Objetos totales"
L["STATS_TOTAL_SLOTS"] = "Espacios totales"
L["STATS_FREE_SLOTS"] = "Espacios libres"
L["STATS_USED_SLOTS"] = "Espacios usados"
L["STATS_TOTAL_VALUE"] = "Valor total"
L["COLLECTED"] = "Recolectado"
L["TOTAL"] = "Total"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Personaje" -- Blizzard Global: CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Ubicaci�n" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "Banco de banda de guerra"
L["TOOLTIP_TAB"] = "Pesta�a"
L["TOOLTIP_SLOT"] = "Espacio"
L["TOOLTIP_COUNT"] = "Cantidad"
L["CHARACTER_INVENTORY"] = "Inventario"
L["CHARACTER_BANK"] = "Banco"

-- Try Counter
L["TRY_COUNT"] = "Contador de intentos"
L["SET_TRY_COUNT"] = "Establecer intentos"
L["TRIES"] = "Intentos"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "Establecer ciclo de reinicio"
L["DAILY_RESET"] = "Reinicio diario"
L["WEEKLY_RESET"] = "Reinicio semanal"
L["NONE_DISABLE"] = "Ninguno (Desactivar)"
L["RESET_CYCLE_LABEL"] = "Ciclo de reinicio:"
L["RESET_NONE"] = "Ninguno"
L["DOUBLECLICK_RESET"] = "Doble clic para restablecer la posici�n"

-- Error Messages
L["ERROR_GENERIC"] = "Se ha producido un error."
L["ERROR_API_UNAVAILABLE"] = "La API requerida no est� disponible."
L["ERROR_BANK_CLOSED"] = "No se puede realizar la operaci�n: banco cerrado."
L["ERROR_INVALID_ITEM"] = "Objeto especificado no v�lido."
L["ERROR_PROTECTED_FUNCTION"] = "No se puede llamar a una funci�n protegida en combate."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "�Depositar %d objetos en el banco de banda de guerra?"
L["CONFIRM_CLEAR_QUEUE"] = "�Vaciar todos los objetos de la cola de dep�sito?"
L["CONFIRM_DEPOSIT_GOLD"] = "�Depositar %s oro en el banco de banda de guerra?"

-- Update Notification
L["WHATS_NEW"] = "Novedades"
L["GOT_IT"] = "�Entendido!"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "PUNTOS DE LOGRO"
L["MOUNTS_COLLECTED"] = "MONTURAS RECOLECTADAS"
L["BATTLE_PETS"] = "MASCOTAS DE BATALLA"
L["ACCOUNT_WIDE"] = "Toda la cuenta"
L["STORAGE_OVERVIEW"] = "Resumen de almacenamiento"
L["WARBAND_SLOTS"] = "ESPACIOS DE BANDA"
L["PERSONAL_SLOTS"] = "ESPACIOS PERSONALES"
L["TOTAL_FREE"] = "TOTAL LIBRE"
L["TOTAL_ITEMS"] = "OBJETOS TOTALES"

-- Plans Tracker Window
L["WEEKLY_VAULT"] = "Gran C�mara semanal"
L["CUSTOM"] = "Personalizado"
L["NO_PLANS_IN_CATEGORY"] = "No hay planes en esta categor�a.\nA�ade planes desde la pesta�a Planes."
L["SOURCE_LABEL"] = "Fuente:"
L["ZONE_LABEL"] = "Zona:"
L["VENDOR_LABEL"] = "Vendedor:"
L["DROP_LABEL"] = "Bot�n:"
L["REQUIREMENT_LABEL"] = "Requisito:"
L["RIGHT_CLICK_REMOVE"] = "Clic derecho para eliminar"
L["TRACKED"] = "Rastreado"
L["TRACK"] = "Rastrear"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Rastrear en objetivos de Blizzard (m�x. 10)"
L["UNKNOWN"] = "Desconocido"
L["NO_REQUIREMENTS"] = "Sin requisitos (completado instant�neo)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "Sin actividad planificada"
L["CLICK_TO_ADD_GOALS"] = "�Haz clic en Monturas, Mascotas o Juguetes arriba para a�adir objetivos!"
L["UNKNOWN_QUEST"] = "Misi�n desconocida"
L["ALL_QUESTS_COMPLETE"] = "�Todas las misiones completadas!"
L["CURRENT_PROGRESS"] = "Progreso actual"
L["SELECT_CONTENT"] = "Seleccionar contenido:"
L["QUEST_TYPES"] = "Tipos de misi�n:"
L["WORK_IN_PROGRESS"] = "En desarrollo"
L["RECIPE_BROWSER"] = "Explorador de recetas"
L["NO_RESULTS_FOUND"] = "No se encontraron resultados."
L["TRY_ADJUSTING_SEARCH"] = "Intenta ajustar tu b�squeda o filtros."
L["NO_COLLECTED_YET"] = "Ning�n %s recolectado a�n"
L["START_COLLECTING"] = "�Empieza a recolectar para verlos aqu�!"
L["ALL_COLLECTED_CATEGORY"] = "�Todos los %ss recolectados!"
L["COLLECTED_EVERYTHING"] = "�Has recolectado todo en esta categor�a!"
L["PROGRESS_LABEL"] = "Progreso:"
L["REQUIREMENTS_LABEL"] = "Requisitos:"
L["INFORMATION_LABEL"] = "Informaci�n:"
L["DESCRIPTION_LABEL"] = "Descripci�n:"
L["REWARD_LABEL"] = "Recompensa:"
L["DETAILS_LABEL"] = "Detalles:"
L["COST_LABEL"] = "Coste:"
L["LOCATION_LABEL"] = "Ubicaci�n:"
L["TITLE_LABEL"] = "T�tulo:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "�Ya has completado todos los logros de esta categor�a!"
L["DAILY_PLAN_EXISTS"] = "El plan diario ya existe"
L["WEEKLY_PLAN_EXISTS"] = "El plan semanal ya existe"

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "Tus personajes"
L["CHARACTERS_TRACKED_FORMAT"] = "%d personajes rastreados"
L["NO_CHARACTER_DATA"] = "No hay datos de personajes disponibles"
L["NO_FAVORITES"] = "A�n no hay personajes favoritos. Haz clic en el icono de estrella para marcar un personaje como favorito."
L["ALL_FAVORITED"] = "�Todos los personajes est�n marcados como favoritos!"
L["UNTRACKED_CHARACTERS"] = "Personajes no rastreados"
L["ILVL_SHORT"] = "iLvl"
L["ONLINE"] = "En l�nea"
L["TIME_LESS_THAN_MINUTE"] = "< 1m hace"
L["TIME_MINUTES_FORMAT"] = "hace %dm"
L["TIME_HOURS_FORMAT"] = "hace %dh"
L["TIME_DAYS_FORMAT"] = "hace %dd"
L["REMOVE_FROM_FAVORITES"] = "Quitar de favoritos"
L["ADD_TO_FAVORITES"] = "A�adir a favoritos"
L["FAVORITES_TOOLTIP"] = "Los personajes favoritos aparecen en la parte superior de la lista"
L["CLICK_TO_TOGGLE"] = "Clic para alternar"
L["UNKNOWN_PROFESSION"] = "Profesi�n desconocida"
L["SKILL_LABEL"] = "Habilidad:"
L["OVERALL_SKILL"] = "Habilidad total:"
L["BONUS_SKILL"] = "Habilidad bonus:"
L["KNOWLEDGE_LABEL"] = "Conocimiento:"
L["SPEC_LABEL"] = "Espec."
L["POINTS_SHORT"] = "pts"
L["RECIPES_KNOWN"] = "Recetas conocidas:"
L["OPEN_PROFESSION_HINT"] = "Abrir ventana de profesi�n"
L["FOR_DETAILED_INFO"] = "para informaci�n detallada"
L["CHARACTER_IS_TRACKED"] = "Este personaje est� siendo rastreado."
L["TRACKING_ACTIVE_DESC"] = "La recopilaci�n de datos y las actualizaciones est�n activas."
L["CLICK_DISABLE_TRACKING"] = "Haz clic para desactivar el rastreo."
L["MUST_LOGIN_TO_CHANGE"] = "Debes iniciar sesi�n con este personaje para cambiar el rastreo."
L["TRACKING_ENABLED"] = "Rastreo activado"
L["CLICK_ENABLE_TRACKING"] = "Haz clic para activar el rastreo de este personaje."
L["TRACKING_WILL_BEGIN"] = "La recopilaci�n de datos comenzar� inmediatamente."
L["CHARACTER_NOT_TRACKED"] = "Este personaje no est� siendo rastreado."
L["MUST_LOGIN_TO_ENABLE"] = "Debes iniciar sesi�n con este personaje para activar el rastreo."
L["ENABLE_TRACKING"] = "Activar rastreo"
L["DELETE_CHARACTER_TITLE"] = "�Eliminar personaje?"
L["THIS_CHARACTER"] = "este personaje"
L["DELETE_CHARACTER"] = "Eliminar personaje"
L["REMOVE_FROM_TRACKING_FORMAT"] = "Quitar %s del rastreo"
L["CLICK_TO_DELETE"] = "Haz clic para eliminar"
L["CONFIRM_DELETE"] = "�Est�s seguro de que quieres eliminar a |cff00ccff%s|r?"
L["CANNOT_UNDO"] = "�Esta acci�n no se puede deshacer!"
L["DELETE"] = DELETE or "Eliminar"
L["CANCEL"] = CANCEL or "Cancelar"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "Objetos personales"
L["ITEMS_SUBTITLE"] = "Explora tu banco de banda de guerra y objetos personales (Banco + Inventario)"
L["ITEMS_DISABLED_TITLE"] = "Objetos del banco de banda de guerra"
L["ITEMS_LOADING"] = "Cargando datos de inventario"
L["GUILD_BANK_REQUIRED"] = "Debes estar en una hermandad para acceder al banco de hermandad."
L["ITEMS_SEARCH"] = "Buscar objetos..."
L["NEVER"] = "Nunca"
L["ITEM_FALLBACK_FORMAT"] = "Objeto %s"
L["TAB_FORMAT"] = "Pesta�a %d"
L["BAG_FORMAT"] = "Bolsa %d"
L["BANK_BAG_FORMAT"] = "Bolsa de banco %d"
L["ITEM_ID_LABEL"] = "ID de objeto:"
L["QUALITY_TOOLTIP_LABEL"] = "Calidad:"
L["STACK_LABEL"] = "Mont�n:"
L["RIGHT_CLICK_MOVE"] = "Mover a bolsa"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Dividir mont�n"
L["LEFT_CLICK_PICKUP"] = "Recoger"
L["ITEMS_BANK_NOT_OPEN"] = "Banco no abierto"
L["SHIFT_LEFT_CLICK_LINK"] = "Enlazar en chat"
L["ITEM_DEFAULT_TOOLTIP"] = "Objeto"
L["ITEMS_STATS_ITEMS"] = "%s objetos"
L["ITEMS_STATS_SLOTS"] = "%s/%s espacios"
L["ITEMS_STATS_LAST"] = "�ltimo: %s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "Almacenamiento de personaje"
L["STORAGE_SEARCH"] = "Buscar almacenamiento..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "Progreso JcE"
L["PVE_SUBTITLE"] = "Gran C�mara, bloqueos de banda y M�tica+ en tu banda de guerra"
L["PVE_NO_CHARACTER"] = "No hay datos de personaje disponibles"
L["LV_FORMAT"] = "Nv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = RAID or "Raid"
L["VAULT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon"
L["VAULT_WORLD"] = "Mundo"
L["VAULT_SLOT_FORMAT"] = "%s Espacio %d"
L["VAULT_NO_PROGRESS"] = "A�n no hay progreso"
L["VAULT_UNLOCK_FORMAT"] = "Completa %s actividades para desbloquear"
L["VAULT_NEXT_TIER_FORMAT"] = "Siguiente nivel: %d iLvl al completar %s"
L["VAULT_REMAINING_FORMAT"] = "Restantes: %s actividades"
L["VAULT_PROGRESS_FORMAT"] = "Progreso: %s / %s"
L["OVERALL_SCORE_LABEL"] = "Puntuaci�n total:"
L["BEST_KEY_FORMAT"] = "Mejor llave: +%d"
L["SCORE_FORMAT"] = "Puntuaci�n: %s"
L["NOT_COMPLETED_SEASON"] = "No completado esta temporada"
L["CURRENT_MAX_FORMAT"] = "Actual: %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "Progreso: %.1f%%"
L["NO_CAP_LIMIT"] = "Sin l�mite m�ximo"
L["GREAT_VAULT"] = "Gran C�mara"
L["LOADING_PVE"] = "Cargando datos JcE..."
L["PVE_APIS_LOADING"] = "Por favor espera, las APIs de WoW se est�n inicializando..."
L["NO_VAULT_DATA"] = "Sin datos de c�mara"
L["NO_DATA"] = "Sin datos"
L["KEYSTONE"] = "Piedra angular"
L["NO_KEY"] = "Sin llave"
L["AFFIXES"] = "Afijos"
L["NO_AFFIXES"] = "Sin afijos"
L["VAULT_BEST_KEY"] = "Mejor llave:"
L["VAULT_SCORE"] = "Puntuaci�n:"

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "Resumen de reputaci�n"
L["REP_SUBTITLE"] = "Rastrea facciones y renombre en tu banda de guerra"
L["REP_DISABLED_TITLE"] = "Rastreo de reputaci�n"
L["REP_LOADING_TITLE"] = "Cargando datos de reputaci�n"
L["REP_SEARCH"] = "Buscar reputaciones..."
L["REP_PARAGON_TITLE"] = "Reputaci�n Parag�n"
L["REP_REWARD_AVAILABLE"] = "�Recompensa disponible!"
L["REP_CONTINUE_EARNING"] = "Contin�a ganando reputaci�n para obtener recompensas"
L["REP_CYCLES_FORMAT"] = "Ciclos: %d"
L["REP_PROGRESS_HEADER"] = "Progreso: %d/%d"
L["REP_PARAGON_PROGRESS"] = "Progreso Parag�n:"
L["REP_PROGRESS_COLON"] = "Progreso:"
L["REP_CYCLES_COLON"] = "Ciclos:"
L["REP_CHARACTER_PROGRESS"] = "Progreso del personaje:"
L["REP_RENOWN_FORMAT"] = "Renombre %d"
L["REP_PARAGON_FORMAT"] = "Parag�n (%s)"
L["REP_UNKNOWN_FACTION"] = "Facci�n desconocida"
L["REP_API_UNAVAILABLE_TITLE"] = "API de reputaci�n no disponible"
L["REP_API_UNAVAILABLE_DESC"] = "La API C_Reputation no est� disponible en este servidor. Esta funci�n requiere WoW 11.0+ (The War Within)."
L["REP_FOOTER_TITLE"] = "Rastreo de reputaci�n"
L["REP_FOOTER_DESC"] = "Las reputaciones se escanean autom�ticamente al iniciar sesi�n y cuando cambian. Usa el panel de reputaci�n del juego para ver informaci�n detallada y recompensas."
L["REP_CLEARING_CACHE"] = "Limpiando cach� y recargando..."
L["REP_LOADING_DATA"] = "Cargando datos de reputaci�n..."
L["REP_MAX"] = "M�x."
L["REP_TIER_FORMAT"] = "Nivel %d"
L["ACCOUNT_WIDE_LABEL"] = "Toda la cuenta"
L["NO_RESULTS"] = "Sin resultados"
L["NO_REP_MATCH"] = "Ninguna reputaci�n coincide con '%s'"
L["NO_REP_DATA"] = "No hay datos de reputaci�n disponibles"
L["REP_SCAN_TIP"] = "Las reputaciones se escanean autom�ticamente. Intenta /reload si no aparece nada."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "Reputaciones de toda la cuenta (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "Sin reputaciones de toda la cuenta"
L["NO_CHARACTER_REPS"] = "Sin reputaciones de personaje"

-- =============================================
-- Currency Tab
-- =============================================
L["GOLD_LABEL"] = "Oro"
L["CURRENCY_TITLE"] = "Rastreador de monedas"
L["CURRENCY_SUBTITLE"] = "Rastrea todas las monedas de tus personajes"
L["CURRENCY_DISABLED_TITLE"] = "Rastreo de monedas"
L["CURRENCY_LOADING_TITLE"] = "Cargando datos de monedas"
L["CURRENCY_SEARCH"] = "Buscar monedas..."
L["CURRENCY_HIDE_EMPTY"] = "Ocultar vac�as"
L["CURRENCY_SHOW_EMPTY"] = "Mostrar vac�as"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "Todas transferibles entre banda"
L["CURRENCY_CHARACTER_SPECIFIC"] = "Monedas espec�ficas del personaje"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "Limitaci�n de transferencia de monedas"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "La API de Blizzard no admite transferencias autom�ticas de monedas. Por favor, usa la ventana de monedas del juego para transferir manualmente las monedas de banda de guerra."
L["CURRENCY_UNKNOWN"] = "Moneda desconocida"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "Elimina todos los planes completados de tu lista Mis planes. Esto eliminar� todos los planes personalizados completados y quitar� las monturas/mascotas/juguetes completados de tus planes. �Esta acci�n no se puede deshacer!"
L["RECIPE_BROWSER_DESC"] = "Abre la ventana de profesi�n en el juego para explorar recetas.\nEl addon escanear� las recetas disponibles cuando la ventana est� abierta."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "Fuente: [Logro %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s ya tiene un plan activo de Gran C�mara semanal. Puedes encontrarlo en la categor�a 'Mis planes'."
L["DAILY_PLAN_EXISTS_DESC"] = "%s ya tiene un plan activo de misi�n diaria. Puedes encontrarlo en la categor�a 'Tareas diarias'."
L["TRANSMOG_WIP_DESC"] = "El rastreo de colecci�n de transfiguraci�n est� actualmente en desarrollo.\n\nEsta funci�n estar� disponible en una actualizaci�n futura con mejor\nrendimiento y mejor integraci�n con los sistemas de banda de guerra."
L["WEEKLY_VAULT_CARD"] = "Tarjeta de Gran C�mara semanal"
L["WEEKLY_VAULT_COMPLETE"] = "Tarjeta de Gran C�mara semanal - Completada"
L["UNKNOWN_SOURCE"] = "Fuente desconocida"
L["DAILY_TASKS_PREFIX"] = "Tareas diarias - "
L["NO_FOUND_FORMAT"] = "No se encontraron %ss"
L["PLANS_COUNT_FORMAT"] = "%d planes"
L["PET_BATTLE_LABEL"] = "Combate de mascotas:"
L["QUEST_LABEL"] = "Misi�n:"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "Idioma actual:"
L["LANGUAGE_TOOLTIP"] = "El addon utiliza autom�ticamente el idioma de tu cliente de WoW. Para cambiarlo, actualiza la configuraci�n de Battle.net."
L["POPUP_DURATION"] = "Duraci�n del popup"
L["POPUP_POSITION"] = "Posici�n del popup"
L["SET_POSITION"] = "Establecer posici�n"
L["DRAG_TO_POSITION"] = "Arrastra para posicionar\nClic derecho para confirmar"
L["RESET_DEFAULT"] = "Restablecer predeterminado"
L["TEST_POPUP"] = "Probar popup"
L["CUSTOM_COLOR"] = "Color personalizado"
L["OPEN_COLOR_PICKER"] = "Abrir selector de color"
L["COLOR_PICKER_TOOLTIP"] = "Abre el selector de color nativo de WoW para elegir un color de tema personalizado"
L["PRESET_THEMES"] = "Temas predefinidos"
L["WARBAND_NEXUS_SETTINGS"] = "Configuraci�n de Warband Nexus"
L["NO_OPTIONS"] = "Sin opciones"
L["NONE_LABEL"] = NONE or "Ninguno"
L["TAB_FILTERING"] = "Filtrado de pesta�as"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Notificaciones"
L["SCROLL_SPEED"] = "Velocidad de desplazamiento"
L["ANCHOR_FORMAT"] = "Ancla: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "Mostrar planificador semanal"
L["LOCK_MINIMAP_ICON"] = "Bloquear icono del minimapa"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "Mostrar objetos en descripciones"
L["AUTO_SCAN_ITEMS"] = "Escanear objetos autom�ticamente"
L["LIVE_SYNC"] = "Sincronizaci�n en vivo"
L["BACKPACK_LABEL"] = "Mochila"
L["REAGENT_LABEL"] = "Reactivo"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "M�dulo desactivado"
L["LOADING"] = "Cargando..."
L["PLEASE_WAIT"] = "Por favor espera..."
L["RESET_PREFIX"] = "Reinicio:"
L["TRANSFER_CURRENCY"] = "Transferir moneda"
L["AMOUNT_LABEL"] = "Cantidad:"
L["TO_CHARACTER"] = "Al personaje:"
L["SELECT_CHARACTER"] = "Seleccionar personaje..."
L["CURRENCY_TRANSFER_INFO"] = "La ventana de monedas se abrir� autom�ticamente.\nNecesitar�s hacer clic derecho manualmente en la moneda para transferirla."
L["OK_BUTTON"] = OKAY or "Aceptar"
L["SAVE"] = "Guardar"
L["TITLE_FIELD"] = "T�tulo:"
L["DESCRIPTION_FIELD"] = "Descripci�n:"
L["CREATE_CUSTOM_PLAN"] = "Crear plan personalizado"
L["REPORT_BUGS"] = "Reporta errores o comparte sugerencias en CurseForge para ayudar a mejorar el addon."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus proporciona una interfaz centralizada para gestionar todos tus personajes, monedas, reputaciones, objetos y progreso JcE en toda tu banda de guerra."
L["CHARACTERS_DESC"] = "Ver todos los personajes con oro, nivel, iLvl, facci�n, raza, clase, profesiones, piedra angular e info de �ltima sesi�n. Rastrea o deja de rastrear personajes, marca favoritos."
L["ITEMS_DESC"] = "Busca y explora objetos en todas las bolsas, bancos y banco de banda. Escaneo autom�tico al abrir un banco. Los tooltips muestran qu� personajes poseen cada objeto."
L["STORAGE_DESC"] = "Vista de inventario agregada de todos los personajes � bolsas, banco personal y banco de banda combinados en un solo lugar."
L["PVE_DESC"] = "Rastrea el progreso de Gran C�mara con indicadores de nivel, puntuaciones y claves M�tica+, afijos, historial de mazmorras y moneda de mejora en todos los personajes."
L["REPUTATIONS_DESC"] = "Compara el progreso de reputaci�n entre todos los personajes. Muestra facciones de Toda la cuenta vs Espec�ficas con tooltips para desglose por personaje."
L["CURRENCY_DESC"] = "Ver todas las monedas organizadas por expansi�n. Compara cantidades entre personajes con tooltips al pasar el cursor. Oculta monedas vac�as con un clic."
L["PLANS_DESC"] = "Rastrea monturas, mascotas, juguetes, logros y transmog no recolectados. A�ade objetivos, ve fuentes de drop y sigue los contadores de intentos. Acceso v�a /wn plan o icono del minimapa."
L["STATISTICS_DESC"] = "Ver puntos de logro, progreso de colecci�n de monturas/mascotas/juguetes/ilusiones/t�tulos, contador de mascotas �nicas y estad�sticas de uso de bolsas/banco."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "Mythic"
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "Heroic"
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "Normal"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Nivel %d"
L["PVP_TYPE"] = PVP or "PvP"
L["PREPARING"] = "Preparando"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Estad�sticas de cuenta"
L["STATISTICS_SUBTITLE"] = "Progreso de colecci�n, oro y resumen de almacenamiento"
L["MOST_PLAYED"] = "M�S JUGADOS"
L["PLAYED_DAYS"] = "D�as"
L["PLAYED_HOURS"] = "Horas"
L["PLAYED_MINUTES"] = "Minutos"
L["PLAYED_DAY"] = "D�a"
L["PLAYED_HOUR"] = "Hora"
L["PLAYED_MINUTE"] = "Minuto"
L["MORE_CHARACTERS"] = "personaje m�s"
L["MORE_CHARACTERS_PLURAL"] = "personajes m�s"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "�Bienvenido a Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "Resumen del AddOn"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "Rastrea tus objetivos de colecci�n"
L["ACTIVE_PLAN_FORMAT"] = "%d plan activo"
L["ACTIVE_PLANS_FORMAT"] = "%d planes activos"
L["RESET_LABEL"] = RESET or "Reiniciar"

-- Plans - Type Names
L["TYPE_MOUNT"] = MOUNT or "Montura"
L["TYPE_PET"] = PET or "Mascota"
L["TYPE_TOY"] = TOY or "Juguete"
L["TYPE_RECIPE"] = "Receta"
L["TYPE_ILLUSION"] = "Ilusi�n"
L["TYPE_TITLE"] = "T�tulo"
L["TYPE_CUSTOM"] = "Personalizado"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transfiguraci�n"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Bot�n"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Misi�n"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Vendedor"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profesi�n"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Combate de mascotas"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Logro"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "Evento mundial"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promoci�n"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "Juego de cartas coleccionables"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "Tienda del juego"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "Fabricado"
L["SOURCE_TYPE_TRADING_POST"] = "Puesto comercial"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "Desconocido"
L["SOURCE_TYPE_PVP"] = PVP or "JcJ"
L["SOURCE_TYPE_TREASURE"] = "Tesoro"
L["SOURCE_TYPE_PUZZLE"] = "Puzle"
L["SOURCE_TYPE_RENOWN"] = "Renombre"

-- Plans - Transmog Source Labels (Blizzard TRANSMOG_SOURCE_* Globals)
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Bot�n de jefe"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Misi�n"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Vendedor"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "Bot�n en el mundo"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Logro"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Profesi�n"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "Vendido por"
L["PARSE_CRAFTED"] = "Fabricado"
L["PARSE_ZONE"] = ZONE or "Zona"
L["PARSE_COST"] = "Coste"
L["PARSE_REPUTATION"] = REPUTATION or "Reputaci�n"
L["PARSE_FACTION"] = FACTION or "Facci�n"
L["PARSE_ARENA"] = ARENA or "Arena"
L["PARSE_DUNGEON"] = DUNGEONS or "Mazmorra"
L["PARSE_RAID"] = RAID or "Banda"
L["PARSE_HOLIDAY"] = "Festividad"
L["PARSE_RATED"] = "Puntuado"
L["PARSE_BATTLEGROUND"] = "Campo de batalla"
L["PARSE_DISCOVERY"] = "Descubrimiento"
L["PARSE_CONTAINED_IN"] = "Contenido en"
L["PARSE_GARRISON"] = "Ciudadela"
L["PARSE_GARRISON_BUILDING"] = "Edificio de ciudadela"
L["PARSE_STORE"] = "Tienda"
L["PARSE_ORDER_HALL"] = "Sala de la orden"
L["PARSE_COVENANT"] = "Pacto"
L["PARSE_FRIENDSHIP"] = "Amistad"
L["PARSE_PARAGON"] = "Dechado"
L["PARSE_MISSION"] = "Misi�n"
L["PARSE_EXPANSION"] = "Expansi�n"
L["PARSE_SCENARIO"] = "Escenario"
L["PARSE_CLASS_HALL"] = "Sala de la orden"
L["PARSE_CAMPAIGN"] = "Campa�a"
L["PARSE_EVENT"] = "Evento"
L["PARSE_SPECIAL"] = "Especial"
L["PARSE_BRAWLERS_GUILD"] = "Gremio de camorristas"
L["PARSE_CHALLENGE_MODE"] = "Modo desaf�o"
L["PARSE_MYTHIC_PLUS"] = "M�tica+"
L["PARSE_TIMEWALKING"] = "Paseo del tiempo"
L["PARSE_ISLAND_EXPEDITION"] = "Expedici�n a islas"
L["PARSE_WARFRONT"] = "Frente de guerra"
L["PARSE_TORGHAST"] = "Torghast"
L["PARSE_ZERETH_MORTIS"] = "Zereth Mortis"
L["PARSE_HIDDEN"] = "Oculto"
L["PARSE_RARE"] = "Raro"
L["PARSE_WORLD_BOSS"] = "Jefe de mundo"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Bot�n"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "Del logro"
L["FALLBACK_UNKNOWN_PET"] = "Mascota desconocida"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "Colecci�n de mascotas"
L["FALLBACK_TOY_COLLECTION"] = "Colecci�n de juguetes"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Colecci�n de transfiguraci�n"
L["FALLBACK_PLAYER_TITLE"] = "T�tulo de jugador"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Desconocido"
L["FALLBACK_ILLUSION_FORMAT"] = "Ilusi�n %s"
L["SOURCE_ENCHANTING"] = "Encantamiento"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "Establecer intentos para:\n%s"
L["RESET_COMPLETED_CONFIRM"] = "�Est�s seguro de que quieres eliminar TODOS los planes completados?\n\n�Esto no se puede deshacer!"
L["YES_RESET"] = "S�, reiniciar"
L["REMOVED_PLANS_FORMAT"] = "Se eliminaron %d plan(es) completado(s)."

-- Plans - Buttons
L["ADD_CUSTOM"] = "A�adir personalizado"
L["ADD_VAULT"] = "A�adir C�mara"
L["ADD_QUEST"] = "A�adir misi�n"
L["CREATE_PLAN"] = "Crear plan"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "Diaria"
L["QUEST_CAT_WORLD"] = "Mundo"
L["QUEST_CAT_WEEKLY"] = "Semanal"
L["QUEST_CAT_ASSIGNMENT"] = "Asignaci�n"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Categor�a desconocida"
L["SCANNING_FORMAT"] = "Escaneando %s"
L["CUSTOM_PLAN_SOURCE"] = "Plan personalizado"
L["POINTS_FORMAT"] = "%d Puntos"
L["SOURCE_NOT_AVAILABLE"] = "Informaci�n de fuente no disponible"
L["PROGRESS_ON_FORMAT"] = "Est�s en %d/%d del progreso"
L["COMPLETED_REQ_FORMAT"] = "Has completado %d de %d requisitos totales"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Midnight"
L["CONTENT_TWW"] = "The War Within"
L["QUEST_TYPE_DAILY"] = "Misiones diarias"
L["QUEST_TYPE_DAILY_DESC"] = "Misiones diarias regulares de PNJs"
L["QUEST_TYPE_WORLD"] = "Misiones de mundo"
L["QUEST_TYPE_WORLD_DESC"] = "Misiones de mundo de toda la zona"
L["QUEST_TYPE_WEEKLY"] = "Misiones semanales"
L["QUEST_TYPE_WEEKLY_DESC"] = "Misiones semanales recurrentes"
L["QUEST_TYPE_ASSIGNMENTS"] = "Asignaciones"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "Asignaciones y tareas especiales"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "M�tica+"
L["RAIDS_LABEL"] = RAIDS or "Raids"

-- PlanCardFactory
L["FACTION_LABEL"] = "Facci�n:"
L["FRIENDSHIP_LABEL"] = "Amistad"
L["RENOWN_TYPE_LABEL"] = "Renombre"
L["ADD_BUTTON"] = "+ A�adir"
L["ADDED_LABEL"] = "A�adido"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s de %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Mostrar cantidades apiladas en objetos en la vista de almacenamiento"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Mostrar la secci�n del planificador semanal en la pesta�a Personajes"
L["LOCK_MINIMAP_TOOLTIP"] = "Bloquear el icono del minimapa en su lugar (previene arrastrar)"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "Muestra el recuento de objetos de la banda de guerra y del personaje en las descripciones (B�squeda de WN)."
L["AUTO_SCAN_TOOLTIP"] = "Escanear y almacenar objetos autom�ticamente cuando abres bancos o bolsas"
L["LIVE_SYNC_TOOLTIP"] = "Mantener la cach� de objetos actualizada en tiempo real mientras los bancos est�n abiertos"
L["SHOW_ILVL_TOOLTIP"] = "Mostrar insignias de nivel de objeto en equipamiento en la lista de objetos"
L["SCROLL_SPEED_TOOLTIP"] = "Multiplicador de velocidad de desplazamiento (1.0x = 28 px por paso)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "Ignorar Pesta�a %d del banco de banda de guerra del escaneo autom�tico"
L["IGNORE_SCAN_FORMAT"] = "Ignorar %s del escaneo autom�tico"
L["BANK_LABEL"] = BANK or "Banco"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "Activar notificaciones"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Interruptor principal para todas las ventanas emergentes de notificaciones"
L["VAULT_REMINDER"] = "Recordatorio de C�mara"
L["VAULT_REMINDER_TOOLTIP"] = "Mostrar recordatorio cuando tengas recompensas de Gran C�mara semanal sin reclamar"
L["LOOT_ALERTS"] = "Alertas de bot�n"
L["LOOT_ALERTS_TOOLTIP"] = "Interruptor principal de popups de coleccionables. Desactivarlo oculta todas las notificaciones de coleccionables."
L["LOOT_ALERTS_MOUNT"] = "Notificaciones de monturas"
L["LOOT_ALERTS_MOUNT_TOOLTIP"] = "Mostrar notificaci�n al recolectar una nueva montura."
L["LOOT_ALERTS_PET"] = "Notificaciones de mascotas"
L["LOOT_ALERTS_PET_TOOLTIP"] = "Mostrar notificaci�n al recolectar una nueva mascota."
L["LOOT_ALERTS_TOY"] = "Notificaciones de juguetes"
L["LOOT_ALERTS_TOY_TOOLTIP"] = "Mostrar notificaci�n al recolectar un nuevo juguete."
L["LOOT_ALERTS_TRANSMOG"] = "Notificaciones de apariencia"
L["LOOT_ALERTS_TRANSMOG_TOOLTIP"] = "Mostrar notificaci�n al recolectar una nueva apariencia de armadura o arma."
L["LOOT_ALERTS_ILLUSION"] = "Notificaciones de ilusiones"
L["LOOT_ALERTS_ILLUSION_TOOLTIP"] = "Mostrar notificaci�n al recolectar una nueva ilusi�n de arma."
L["LOOT_ALERTS_TITLE"] = "Notificaciones de t�tulos"
L["LOOT_ALERTS_TITLE_TOOLTIP"] = "Mostrar notificaci�n al obtener un nuevo t�tulo."
L["LOOT_ALERTS_ACHIEVEMENT"] = "Notificaciones de logros"
L["LOOT_ALERTS_ACHIEVEMENT_TOOLTIP"] = "Mostrar notificaci�n al obtener un nuevo logro."
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Ocultar alerta de logro de Blizzard"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Ocultar la ventana emergente de logro predeterminada de Blizzard y usar la notificaci�n de Warband Nexus en su lugar"
L["REPUTATION_GAINS"] = "Ganancias de reputaci�n"
L["REPUTATION_GAINS_TOOLTIP"] = "Mostrar mensajes de chat cuando ganes reputaci�n con facciones"
L["CURRENCY_GAINS"] = "Ganancias de moneda"
L["CURRENCY_GAINS_TOOLTIP"] = "Mostrar mensajes de chat cuando ganes monedas"
L["SCREEN_FLASH_EFFECT"] = "Efecto de destello de pantalla"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Reproducir un efecto de destello de pantalla al obtener un nuevo coleccionable (montura, mascota, juguete, etc.)"
L["AUTO_TRY_COUNTER"] = "Contador de intentos autom�tico"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Contar autom�ticamente los intentos al saquear NPCs, raros, jefes, pescar o abrir contenedores que pueden soltar monturas, mascotas o juguetes. Muestra el n�mero de intentos en el chat cuando el coleccionable no cae."
L["DURATION_LABEL"] = "Duraci�n"
L["DAYS_LABEL"] = "d�as"
L["WEEKS_LABEL"] = "semanas"
L["EXTEND_DURATION"] = "Extender duraci�n"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Arrastra el marco verde para establecer la posici�n del popup. Clic derecho para confirmar."
L["POSITION_RESET_MSG"] = "Posici�n del popup restablecida a predeterminado (Centro superior)"
L["POSITION_SAVED_MSG"] = "�Posici�n del popup guardada!"
L["TEST_NOTIFICATION_TITLE"] = "Notificaci�n de prueba"
L["TEST_NOTIFICATION_MSG"] = "Prueba de posici�n"
L["NOTIFICATION_DEFAULT_TITLE"] = "Notificaci�n"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "Tema y apariencia"
L["COLOR_PURPLE"] = "Morado"
L["COLOR_PURPLE_DESC"] = "Tema morado cl�sico (predeterminado)"
L["COLOR_BLUE"] = "Azul"
L["COLOR_BLUE_DESC"] = "Tema azul fr�o"
L["COLOR_GREEN"] = "Verde"
L["COLOR_GREEN_DESC"] = "Tema verde naturaleza"
L["COLOR_RED"] = "Rojo"
L["COLOR_RED_DESC"] = "Tema rojo ardiente"
L["COLOR_ORANGE"] = "Naranja"
L["COLOR_ORANGE_DESC"] = "Tema naranja c�lido"
L["COLOR_CYAN"] = "Cian"
L["COLOR_CYAN_DESC"] = "Tema cian brillante"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "Familia de fuente"
L["FONT_FAMILY_TOOLTIP"] = "Elige la fuente utilizada en toda la interfaz del addon"
L["FONT_SCALE"] = "Escala de fuente"
L["FONT_SCALE_TOOLTIP"] = "Ajustar el tama�o de fuente en todos los elementos de la interfaz"
L["FONT_SCALE_WARNING"] = "Advertencia: Una escala de fuente mayor puede causar desbordamiento de texto en algunos elementos de la interfaz."
L["RESOLUTION_NORMALIZATION"] = "Normalizaci�n de resoluci�n"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Ajustar tama�os de fuente basados en la resoluci�n de pantalla y escala de interfaz para que el texto permanezca del mismo tama�o f�sico en diferentes monitores"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Avanzado"

-- =============================================
-- Settings - Module Management
-- =============================================
L["MODULE_MANAGEMENT"] = "Gesti�n de m�dulos"
L["MODULE_MANAGEMENT_DESC"] = "Activar o desactivar m�dulos de recopilaci�n de datos espec�ficos. Desactivar un m�dulo detendr� sus actualizaciones de datos y ocultar� su pesta�a de la interfaz."
L["MODULE_CURRENCIES"] = "Monedas"
L["MODULE_CURRENCIES_DESC"] = "Rastrear monedas de toda la cuenta y espec�ficas del personaje (Oro, Honor, Conquista, etc.)"
L["MODULE_REPUTATIONS"] = "Reputaciones"
L["MODULE_REPUTATIONS_DESC"] = "Rastrear el progreso de reputaci�n con facciones, niveles de renombre y recompensas parag�n"
L["MODULE_ITEMS"] = "Objetos"
L["MODULE_ITEMS_DESC"] = "Rastrear objetos del banco de banda de guerra, funcionalidad de b�squeda y categor�as de objetos"
L["MODULE_STORAGE"] = "Almacenamiento"
L["MODULE_STORAGE_DESC"] = "Rastrear bolsas del personaje, banco personal y almacenamiento del banco de banda de guerra"
L["MODULE_PVE"] = "JcE"
L["MODULE_PVE_DESC"] = "Rastrear mazmorras M�tica+, progreso de bandas y recompensas de Gran C�mara"
L["MODULE_PLANS"] = "Planes"
L["MODULE_PLANS_DESC"] = "Rastrear objetivos personales para monturas, mascotas, juguetes, logros y tareas personalizadas"
L["MODULE_PROFESSIONS"] = "Profesiones"
L["MODULE_PROFESSIONS_DESC"] = "Rastrear habilidades de profesi�n, concentraci�n, conocimiento y ventana de recetas"
L["PROFESSIONS_DISABLED_TITLE"] = "Profesiones"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Nivel de objeto %s"
L["ITEM_NUMBER_FORMAT"] = "Objeto #%s"
L["CHARACTER_CURRENCIES"] = "Monedas del personaje:"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "Cuenta global (Banda de guerra) � mismo saldo en todos los personajes."
L["YOU_MARKER"] = "(T�)"
L["WN_SEARCH"] = "B�squeda WN"
L["WARBAND_BANK_COLON"] = "Banco de banda de guerra:"
L["AND_MORE_FORMAT"] = "... y %d m�s"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "Has recolectado una montura"
L["COLLECTED_PET_MSG"] = "Has recolectado una mascota de batalla"
L["COLLECTED_TOY_MSG"] = "Has recolectado un juguete"
L["COLLECTED_ILLUSION_MSG"] = "Has recolectado una ilusi�n"
L["COLLECTED_ITEM_MSG"] = "Has recibido un bot�n raro"
L["ACHIEVEMENT_COMPLETED_MSG"] = "�Logro completado!"
L["EARNED_TITLE_MSG"] = "Has obtenido un t�tulo"
L["COMPLETED_PLAN_MSG"] = "Has completado un plan"
L["DAILY_QUEST_CAT"] = "Misi�n diaria"
L["WORLD_QUEST_CAT"] = "Misi�n de mundo"
L["WEEKLY_QUEST_CAT"] = "Misi�n semanal"
L["SPECIAL_ASSIGNMENT_CAT"] = "Asignaci�n especial"
L["DELVE_CAT"] = "Excavaci�n"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "Dungeon"
L["RAID_CAT"] = RAID or "Raid"
L["WORLD_CAT"] = "Mundo"
L["ACTIVITY_CAT"] = "Actividad"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Progreso"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Progreso completado"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Plan de Gran C�mara semanal - %s"
L["ALL_SLOTS_COMPLETE"] = "�Todos los espacios completados!"
L["QUEST_COMPLETED_SUFFIX"] = "Completada"
L["WEEKLY_VAULT_READY"] = "�Gran C�mara semanal lista!"
L["UNCLAIMED_REWARDS"] = "Tienes recompensas sin reclamar"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "Oro total:"
L["CHARACTERS_COLON"] = "Personajes:"
L["LEFT_CLICK_TOGGLE"] = "Clic izquierdo: Alternar ventana"
L["RIGHT_CLICK_PLANS"] = "Clic derecho: Abrir Planes"
L["MINIMAP_SHOWN_MSG"] = "Bot�n del minimapa mostrado"
L["MINIMAP_HIDDEN_MSG"] = "Bot�n del minimapa oculto (usa /wn minimap para mostrar)"
L["TOGGLE_WINDOW"] = "Alternar ventana"
L["SCAN_BANK_MENU"] = "Escanear banco"
L["TRACKING_DISABLED_SCAN_MSG"] = "El rastreo de personajes est� desactivado. Activa el rastreo en configuraci�n para escanear el banco."
L["SCAN_COMPLETE_MSG"] = "�Escaneo completado!"
L["BANK_NOT_OPEN_MSG"] = "El banco no est� abierto"
L["OPTIONS_MENU"] = "Opciones"
L["HIDE_MINIMAP_BUTTON"] = "Ocultar bot�n del minimapa"
L["MENU_UNAVAILABLE_MSG"] = "Men� de clic derecho no disponible"
L["USE_COMMANDS_MSG"] = "Usa /wn show, /wn options, /wn help"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "M�x"
L["OPEN_AND_GUIDE"] = "Abrir y guiar"
L["FROM_LABEL"] = "De:"
L["AVAILABLE_LABEL"] = "Disponible:"
L["ONLINE_LABEL"] = "(En l�nea)"
L["DATA_SOURCE_TITLE"] = "Informaci�n de fuente de datos"
L["DATA_SOURCE_USING"] = "Esta pesta�a est� usando:"
L["DATA_SOURCE_MODERN"] = "Servicio de cach� moderno (basado en eventos)"
L["DATA_SOURCE_LEGACY"] = "Acceso directo a BD heredado"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Necesita migraci�n al servicio de cach�"
L["GLOBAL_DB_VERSION"] = "Versi�n de BD global:"

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "Personajes"
L["INFO_TAB_ITEMS"] = "Objetos"
L["INFO_TAB_STORAGE"] = "Almacenamiento"
L["INFO_TAB_PVE"] = "JcE"
L["INFO_TAB_REPUTATIONS"] = "Reputaciones"
L["INFO_TAB_CURRENCY"] = "Moneda"
L["INFO_TAB_PLANS"] = "Planes"
L["INFO_TAB_STATISTICS"] = "Estad�sticas"
L["SPECIAL_THANKS"] = "Agradecimientos especiales"
L["SUPPORTERS_TITLE"] = "Patrocinadores"
L["THANK_YOU_MSG"] = "�Gracias por usar Warband Nexus!"

-- =============================================
-- Changelog (What's New) - v2.1.2
-- =============================================
L["CHANGELOG_V213"] =     "CAMBIOS:\n- Se a?adi? un sistema de clasificaci?n.\n- Se corrigieron varios errores de la interfaz (UI).\n- Se a?adi? un bot?n para alternar el Compa?ero de Recetas de Profesiones y se movi? su ventana a la izquierda.\n- Se solucionaron los problemas de seguimiento de la Concentraci?n de Profesiones.\n- Se solucion? un problema por el cual el contador de intentos mostraba incorrectamente '1 attempts' inmediatamente despu?s de encontrar un bot?n coleccionable.\n- Se redujeron significativamente los tirones en la interfaz y las ca?das de FPS al despojar objetos o abrir contenedores optimizando la l?gica de seguimiento en segundo plano.\n- Se corrigi? un error que imped?a que las bajas de jefes se sumaran correctamente a los intentos de obtenci?n de ciertas monturas (ej. Mecatraje de la B?veda de Piedra).\n- Se corrigi? que los Contenedores desbordantes no comprobaran correctamente las monedas u otras recompensas.\n\nGracias por tu continuo apoyo!\n\nPara informar sobre problemas o compartir tus comentarios, deja un mensaje en CurseForge - Warband Nexus."

L["CHANGELOG_V212"] =     "CAMBIOS:\n- Se a?adi? un sistema de clasificaci?n.\n- Se corrigieron varios errores de la interfaz (UI).\n- Se a?adi? un bot?n para alternar el Compa?ero de Recetas de Profesiones y se movi? su ventana a la izquierda.\n- Se solucionaron los problemas de seguimiento de la Concentraci?n de Profesiones.\n- Se solucion? un problema por el cual el contador de intentos mostraba incorrectamente '1 attempts' inmediatamente despu?s de encontrar un bot?n coleccionable.\n- Se redujeron significativamente los tirones en la interfaz y las ca?das de FPS al despojar objetos o abrir contenedores optimizando la l?gica de seguimiento en segundo plano.\n- Se corrigi? un error que imped?a que las bajas de jefes se sumaran correctamente a los intentos de obtenci?n de ciertas monturas (ej. Mecatraje de la B?veda de Piedra).\n- Se corrigi? que los Contenedores desbordantes no comprobaran correctamente las monedas u otras recompensas.\n\nGracias por tu continuo apoyo!\n\nPara informar sobre problemas o compartir tus comentarios, deja un mensaje en CurseForge - Warband Nexus."
-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "Confirmar acci�n"
L["CONFIRM"] = "Confirmar"
L["ENABLE_TRACKING_FORMAT"] = "�Activar rastreo para |cffffcc00%s|r?"
L["DISABLE_TRACKING_FORMAT"] = "�Desactivar rastreo para |cffffcc00%s|r?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "Reputaciones de toda la cuenta (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Reputaciones basadas en personaje (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "Recompensa esperando"
L["REP_PARAGON_LABEL"] = "Parag�n"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "Preparando..."
L["REP_LOADING_INITIALIZING"] = "Inicializando..."
L["REP_LOADING_FETCHING"] = "Cargando datos de reputaci�n..."
L["REP_LOADING_PROCESSING"] = "Procesando %d facciones..."
L["REP_LOADING_PROCESSING_COUNT"] = "Procesando... (%d/%d)"
L["REP_LOADING_SAVING"] = "Guardando en base de datos..."
L["REP_LOADING_COMPLETE"] = "�Completado!"

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "No se puede abrir la ventana durante el combate. Por favor intenta de nuevo despu�s de que termine el combate."
L["BANK_IS_ACTIVE"] = "El banco est� activo"
L["ITEMS_CACHED_FORMAT"] = "%d objetos en cach�"
-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "PERSONAJE"
L["TABLE_HEADER_LEVEL"] = "NIVEL"
L["TABLE_HEADER_GOLD"] = "ORO"
L["TABLE_HEADER_LAST_SEEN"] = "VISTO POR �LTIMA VEZ"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "Ning�n objeto coincide con '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "Ning�n objeto coincide con tu b�squeda"
L["ITEMS_SCAN_HINT"] = "Los objetos se escanean autom�ticamente. Intenta /reload si no aparece nada."
L["ITEMS_WARBAND_BANK_HINT"] = "Abre el banco de banda de guerra para escanear objetos (escaneado autom�ticamente en la primera visita)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Pr�ximos pasos:"
L["CURRENCY_TRANSFER_STEP_1"] = "Encuentra |cffffffff%s|r en la ventana de monedas"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800Clic derecho|r en �l"
L["CURRENCY_TRANSFER_STEP_3"] = "Selecciona |cffffffff'Transferir a banda de guerra'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Elige |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Ingresa cantidad: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "�La ventana de monedas est� ahora abierta!"
L["CURRENCY_TRANSFER_SECURITY"] = "(La seguridad de Blizzard previene la transferencia autom�tica)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "Zona: "
L["ADDED"] = "A�adido"
L["WEEKLY_VAULT_TRACKER"] = "Rastreador de Gran C�mara semanal"
L["DAILY_QUEST_TRACKER"] = "Rastreador de misiones diarias"
L["CUSTOM_PLAN_STATUS"] = "Plan personalizado '%s' %s"

-- =============================================
-- Achievement Popup
-- =============================================
L["ACHIEVEMENT_COMPLETED"] = "Completado"
L["ACHIEVEMENT_NOT_COMPLETED"] = "No completado"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d pts"
L["ADD_PLAN"] = "A�adir"
L["PLANNED"] = "Planeado"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon"
L["VAULT_SLOT_RAIDS"] = RAIDS or "Raids"
L["VAULT_SLOT_WORLD"] = "Mundo"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "Afijo"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_STANDING_LABEL"] = "Ahora"
L["CHAT_GAINED_PREFIX"] = "+"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "Plan completado: "
L["WEEKLY_VAULT_PLAN_NAME"] = "Gran C�mara semanal - %s"
L["VAULT_PLANS_RESET"] = "�Los planes de Gran C�mara semanal han sido reiniciados! (%d plan%s)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "No se encontraron personajes"
L["EMPTY_CHARACTERS_DESC"] = "Inicia sesi�n con tus personajes para empezar a rastrearlos.\nLos datos se recopilan autom�ticamente en cada inicio de sesi�n."
L["EMPTY_ITEMS_TITLE"] = "No hay objetos en cach�"
L["EMPTY_ITEMS_DESC"] = "Abre tu banco de banda de guerra o banco personal para escanear objetos.\nLos objetos se almacenan autom�ticamente en la primera visita."
L["EMPTY_STORAGE_TITLE"] = "Sin datos de almacenamiento"
L["EMPTY_STORAGE_DESC"] = "Los objetos se escanean al abrir bancos o bolsas.\nVisita un banco para empezar a rastrear tu almacenamiento."
L["EMPTY_PLANS_TITLE"] = "Sin planes a�n"
L["EMPTY_PLANS_DESC"] = "Explora monturas, mascotas, juguetes o logros arriba\npara a�adir objetivos de colecci�n y seguir tu progreso."
L["EMPTY_REPUTATION_TITLE"] = "Sin datos de reputaci�n"
L["EMPTY_REPUTATION_DESC"] = "Las reputaciones se escanean autom�ticamente al iniciar sesi�n.\nInicia sesi�n con un personaje para rastrear facciones."
L["EMPTY_CURRENCY_TITLE"] = "Sin datos de moneda"
L["EMPTY_CURRENCY_DESC"] = "Las monedas se rastrean autom�ticamente en todos tus personajes.\nInicia sesi�n con un personaje para rastrear monedas."
L["EMPTY_PVE_TITLE"] = "Sin datos de PvE"
L["EMPTY_PVE_DESC"] = "El progreso PvE se rastrea al iniciar sesi�n con tus personajes.\nGran C�mara, M�tica+ y bloqueos de banda aparecer�n aqu�."
L["EMPTY_STATISTICS_TITLE"] = "Sin estad�sticas disponibles"
L["EMPTY_STATISTICS_DESC"] = "Las estad�sticas provienen de tus personajes rastreados.\nInicia sesi�n con un personaje para recopilar datos."
L["NO_ADDITIONAL_INFO"] = "Sin informaci�n adicional"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "�Quieres hacer seguimiento de este personaje?"
L["CLEANUP_NO_INACTIVE"] = "No se encontraron personajes inactivos (90+ d�as)"
L["CLEANUP_REMOVED_FORMAT"] = "Se eliminaron %d personaje(s) inactivo(s)"
L["TRACKING_ENABLED_MSG"] = "�Seguimiento de personaje ACTIVADO!"
L["TRACKING_DISABLED_MSG"] = "�Seguimiento de personaje DESACTIVADO!"
L["TRACKING_ENABLED"] = "Seguimiento ACTIVADO"
L["TRACKING_DISABLED"] = "Seguimiento DESACTIVADO (modo solo lectura)"
L["STATUS_LABEL"] = "Estado:"
L["ERROR_LABEL"] = "Error:"
L["ERROR_NAME_REALM_REQUIRED"] = "Se requiere nombre de personaje y reino"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s ya tiene un plan semanal activo"

-- Profiles (AceDB)
L["PROFILES"] = "Perfiles"
L["PROFILES_DESC"] = "Gestionar perfiles del addon"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "No se encontraron criterios"
L["NO_REQUIREMENTS_INSTANT"] = "Sin requisitos (completado instant�neo)"

-- Statistics Tab (missing)
L["TOTAL_PETS"] = "Mascotas totales"

-- Items Tab (missing)
L["ITEM_LOADING_NAME"] = "Cargando..."

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
L["TAB_PROFESSIONS"] = "Profesiones"
L["YOUR_PROFESSIONS"] = "Profesiones de banda de guerra"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s personajes con profesiones"
L["HEADER_PROFESSIONS"] = "Resumen de profesiones"
L["NO_PROFESSIONS_DATA"] = "No hay datos de profesiones disponibles a�n. Abre la ventana de profesi�n (predeterminado: K) en cada personaje para recopilar datos."
L["CONCENTRATION"] = "Concentraci�n"
L["KNOWLEDGE"] = "Conocimiento"
L["SKILL"] = "Habilidad"
L["RECIPES"] = "Recetas"
L["UNSPENT_POINTS"] = "Puntos sin gastar"
L["COLLECTIBLE"] = "Coleccionable"
L["RECHARGE"] = "Recarga"
L["FULL"] = "Completo"
L["PROF_OPEN_RECIPE"] = "Abrir"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "Abrir la lista de recetas de esta profesi�n"
L["PROF_ONLY_CURRENT_CHAR"] = "Solo disponible para el personaje actual"
L["NO_PROFESSION"] = "Sin profesi�n"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "1.� fabricaci�n"
L["SKILL_UPS"] = "Subidas de habilidad"
L["COOLDOWNS"] = "Tiempos de espera"
L["ORDERS"] = "Pedidos"

-- Professions: Tooltips & Details
L["LEARNED_RECIPES"] = "Recetas aprendidas"
L["UNLEARNED_RECIPES"] = "Recetas sin aprender"
L["LAST_SCANNED"] = "�ltimo escaneo"
L["JUST_NOW"] = "Justo ahora"
L["RECIPE_NO_DATA"] = "Abre la ventana de profesi�n para recopilar datos de recetas"
L["FIRST_CRAFT_AVAILABLE"] = "Primeras fabricaciones disponibles"
L["FIRST_CRAFT_DESC"] = "Recetas que otorgan XP bonus en la primera fabricaci�n"
L["SKILLUP_RECIPES"] = "Recetas de subida"
L["SKILLUP_DESC"] = "Recetas que a�n pueden aumentar tu nivel de habilidad"
L["NO_ACTIVE_COOLDOWNS"] = "Sin tiempos de espera activos"

-- Professions: Crafting Orders
L["CRAFTING_ORDERS"] = "Pedidos de fabricaci�n"
L["PERSONAL_ORDERS"] = "Pedidos personales"
L["PUBLIC_ORDERS"] = "Pedidos p�blicos"
L["CLAIMS_REMAINING"] = "Reclamaciones restantes"
L["NO_ACTIVE_ORDERS"] = "Sin pedidos activos"
L["ORDER_NO_DATA"] = "Abre la profesi�n en la mesa de fabricaci�n para escanear"

-- Professions: Equipment
L["EQUIPMENT"] = "Equipamiento"
L["TOOL"] = "Herramienta"
L["ACCESSORY"] = "Accesorio"

-- =============================================
-- New keys (v2.1.0)
-- =============================================
L["TOOLTIP_ATTEMPTS"] = "intentos"
L["TOOLTIP_100_DROP"] = "100% Bot�n"
L["TOOLTIP_UNKNOWN"] = "Desconocido"
L["TOOLTIP_WARBAND_BANK"] = "Banco de banda de guerra"
L["TOOLTIP_HOLD_SHIFT"] = "  Mant�n [May�s] para listado completo"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - Concentraci�n"
L["TOOLTIP_FULL"] = "(Completo)"
L["NO_ITEMS_CACHED_TITLE"] = "Sin objetos en cach�"
L["COMBAT_CURRENCY_ERROR"] = "No se puede abrir la ventana de monedas durante el combate. Int�ntalo de nuevo despu�s del combate."
L["DB_LABEL"] = "BD:"
L["COLLECTING_PVE"] = "Recopilando datos JcE"
L["PVE_PREPARING"] = "Preparando"
L["PVE_GREAT_VAULT"] = "Gran C�mara"
L["PVE_MYTHIC_SCORES"] = "Puntuaciones M�tica+"
L["PVE_RAID_LOCKOUTS"] = "Bloqueos de banda"
L["PVE_INCOMPLETE_DATA"] = "Algunos datos pueden estar incompletos. Intenta actualizar m�s tarde."
L["VAULT_SLOTS_TO_FILL"] = "%d espacio%s de Gran C�mara por completar"
L["VAULT_SLOT_PLURAL"] = "s"
L["REP_RENOWN_NEXT"] = "Renombre %d"
L["REP_TO_NEXT_FORMAT"] = "%s rep para %s (%s)"
L["REP_FACTION_FALLBACK"] = "Facci�n"
L["COLLECTION_CANCELLED"] = "Recopilaci�n cancelada por el usuario"
L["CLEANUP_STALE_FORMAT"] = "Se eliminaron %d personaje(s) obsoleto(s)"
L["PERSONAL_BANK"] = "Banco personal"
L["WARBAND_BANK_LABEL"] = "Banco de banda de guerra"
L["WARBAND_BANK_TAB_FORMAT"] = "Pesta�a %d"
L["CURRENCY_OTHER"] = "Otros"
L["ERROR_SAVING_CHARACTER"] = "Error al guardar personaje:"
L["STANDING_HATED"] = "Odiado"
L["STANDING_HOSTILE"] = "Hostil"
L["STANDING_UNFRIENDLY"] = "Antip�tico"
L["STANDING_NEUTRAL"] = "Neutral"
L["STANDING_FRIENDLY"] = "Amistoso"
L["STANDING_HONORED"] = "Honorable"
L["STANDING_REVERED"] = "Reverenciado"
L["STANDING_EXALTED"] = "Exaltado"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d intentos para %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "�Obtenido %s! Contador de intentos reiniciado."
L["TRYCOUNTER_CAUGHT_RESET"] = "�Capturado %s! Contador de intentos reiniciado."
L["TRYCOUNTER_CONTAINER_RESET"] = "�Obtenido %s del contenedor! Contador de intentos reiniciado."
L["TRYCOUNTER_LOCKOUT_SKIP"] = "Omitido: bloqueo diario/semanal activo para este NPC."
L["TRYCOUNTER_INSTANCE_DROPS"] = "Bot�n coleccionable en esta instancia:"
L["TRYCOUNTER_COLLECTED_TAG"] = "(Recolectado)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " intentos"
L["TRYCOUNTER_TYPE_MOUNT"] = "Montura"
L["TRYCOUNTER_TYPE_PET"] = "Mascota"
L["TRYCOUNTER_TYPE_TOY"] = "Juguete"
L["TRYCOUNTER_TYPE_ITEM"] = "Objeto"
L["TRYCOUNTER_TRY_COUNTS"] = "Contador de intentos"
L["LT_CHARACTER_DATA"] = "Datos de personaje"
L["LT_CURRENCY_CACHES"] = "Monedas y cach�s"
L["LT_REPUTATIONS"] = "Reputaciones"
L["LT_PROFESSIONS"] = "Profesiones"
L["LT_PVE_DATA"] = "Datos JcE"
L["LT_COLLECTIONS"] = "Colecciones"
L["CONFIG_HEADER"] = "Warband Nexus"
L["CONFIG_HEADER_DESC"] = "Gesti�n moderna de banda de guerra y rastreo entre personajes."
L["CONFIG_GENERAL"] = "Configuraci�n general"
L["CONFIG_GENERAL_DESC"] = "Opciones b�sicas de configuraci�n y comportamiento del addon."
L["CONFIG_ENABLE"] = "Activar addon"
L["CONFIG_ENABLE_DESC"] = "Activar o desactivar el addon."
L["CONFIG_MINIMAP"] = "Bot�n del minimapa"
L["CONFIG_MINIMAP_DESC"] = "Mostrar un bot�n en el minimapa para acceso r�pido."
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "Mostrar objetos en descripciones"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "Mostrar cantidades de objetos de banda de guerra y personaje en las descripciones de objetos."
L["CONFIG_MODULES"] = "Gesti�n de m�dulos"
L["CONFIG_MODULES_DESC"] = "Activar o desactivar m�dulos individuales del addon. Los m�dulos desactivados no recopilar�n datos ni mostrar�n pesta�as."
L["CONFIG_MOD_CURRENCIES"] = "Monedas"
L["CONFIG_MOD_CURRENCIES_DESC"] = "Rastrear monedas en todos los personajes."
L["CONFIG_MOD_REPUTATIONS"] = "Reputaciones"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "Rastrear reputaciones en todos los personajes."
L["CONFIG_MOD_ITEMS"] = "Objetos"
L["CONFIG_MOD_ITEMS_DESC"] = "Rastrear objetos en bolsas y bancos."
L["CONFIG_MOD_STORAGE"] = "Almacenamiento"
L["CONFIG_MOD_STORAGE_DESC"] = "Pesta�a de almacenamiento para inventario y gesti�n del banco."
L["CONFIG_MOD_PVE"] = "JcE"
L["CONFIG_MOD_PVE_DESC"] = "Rastrear Gran C�mara, M�tica+ y bloqueos de banda."
L["CONFIG_MOD_PLANS"] = "Planes"
L["CONFIG_MOD_PLANS_DESC"] = "Rastreo de planes de colecci�n y objetivos de completado."
L["CONFIG_MOD_PROFESSIONS"] = "Profesiones"
L["CONFIG_MOD_PROFESSIONS_DESC"] = "Rastrear habilidades de profesi�n, recetas y concentraci�n."
L["CONFIG_AUTOMATION"] = "Automatizaci�n"
L["CONFIG_AUTOMATION_DESC"] = "Controlar qu� ocurre autom�ticamente al abrir el banco de banda de guerra."
L["CONFIG_AUTO_OPTIMIZE"] = "Optimizar base de datos autom�ticamente"
L["CONFIG_AUTO_OPTIMIZE_DESC"] = "Optimizar autom�ticamente la base de datos al iniciar sesi�n para mantener el almacenamiento eficiente."
L["CONFIG_SHOW_ITEM_COUNT"] = "Mostrar cantidad de objetos"
L["CONFIG_SHOW_ITEM_COUNT_DESC"] = "Mostrar descripciones con cantidad de objetos por personaje."
L["CONFIG_THEME_COLOR"] = "Color principal del tema"
L["CONFIG_THEME_COLOR_DESC"] = "Elegir el color de acento principal para la interfaz del addon."
L["CONFIG_THEME_PRESETS"] = "Temas predefinidos"
L["CONFIG_THEME_APPLIED"] = "�Tema %s aplicado!"
L["CONFIG_THEME_RESET_DESC"] = "Restablecer todos los colores del tema al morado predeterminado."
L["CONFIG_NOTIFICATIONS"] = "Notificaciones"
L["CONFIG_NOTIFICATIONS_DESC"] = "Configurar qu� notificaciones aparecen."
L["CONFIG_ENABLE_NOTIFICATIONS"] = "Activar notificaciones"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "Mostrar notificaciones emergentes para eventos de coleccionables."
L["CONFIG_NOTIFY_MOUNTS"] = "Notificaciones de monturas"
L["CONFIG_NOTIFY_MOUNTS_DESC"] = "Mostrar notificaciones al aprender una nueva montura."
L["CONFIG_NOTIFY_PETS"] = "Notificaciones de mascotas"
L["CONFIG_NOTIFY_PETS_DESC"] = "Mostrar notificaciones al aprender una nueva mascota."
L["CONFIG_NOTIFY_TOYS"] = "Notificaciones de juguetes"
L["CONFIG_NOTIFY_TOYS_DESC"] = "Mostrar notificaciones al aprender un nuevo juguete."
L["CONFIG_NOTIFY_ACHIEVEMENTS"] = "Notificaciones de logros"
L["CONFIG_NOTIFY_ACHIEVEMENTS_DESC"] = "Mostrar notificaciones al obtener un logro."
L["CONFIG_SHOW_UPDATE_NOTES"] = "Mostrar novedades de nuevo"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "Mostrar la ventana de novedades en el pr�ximo inicio de sesi�n."
L["CONFIG_UPDATE_NOTES_SHOWN"] = "La notificaci�n de actualizaci�n se mostrar� en el pr�ximo inicio de sesi�n."
L["CONFIG_RESET_PLANS"] = "Reiniciar planes completados"
L["CONFIG_RESET_PLANS_CONFIRM"] = "Esto eliminar� todos los planes completados. �Continuar?"
L["CONFIG_RESET_PLANS_FORMAT"] = "Se eliminaron %d plan(es) completado(s)."
L["CONFIG_NO_COMPLETED_PLANS"] = "No hay planes completados para eliminar."
L["CONFIG_TAB_FILTERING"] = "Filtrado de pesta�as"
L["CONFIG_TAB_FILTERING_DESC"] = "Elegir qu� pesta�as son visibles en la ventana principal."
L["CONFIG_CHARACTER_MGMT"] = "Gesti�n de personajes"
L["CONFIG_CHARACTER_MGMT_DESC"] = "Gestionar personajes rastreados y eliminar datos antiguos."
L["CONFIG_DELETE_CHAR"] = "Eliminar datos de personaje"
L["CONFIG_DELETE_CHAR_DESC"] = "Eliminar permanentemente todos los datos almacenados del personaje seleccionado."
L["CONFIG_DELETE_CONFIRM"] = "�Est�s seguro de que quieres eliminar permanentemente todos los datos de este personaje? Esta acci�n no se puede deshacer."
L["CONFIG_DELETE_SUCCESS"] = "Datos de personaje eliminados:"
L["CONFIG_DELETE_FAILED"] = "No se encontraron datos del personaje."
L["CONFIG_FONT_SCALING"] = "Fuente y escala"
L["CONFIG_FONT_SCALING_DESC"] = "Ajustar familia de fuente y escala de tama�o."
L["CONFIG_FONT_FAMILY"] = "Familia de fuente"
L["CONFIG_FONT_SIZE"] = "Escala de tama�o de fuente"
L["CONFIG_FONT_PREVIEW"] = "Vista previa: El veloz murci�lago hind� com�a feliz cardillo y kiwi"
L["CONFIG_ADVANCED"] = "Avanzado"
L["CONFIG_ADVANCED_DESC"] = "Configuraci�n avanzada y gesti�n de base de datos. �Usar con precauci�n!"
L["CONFIG_DEBUG_MODE"] = "Modo de depuraci�n"
L["CONFIG_DEBUG_MODE_DESC"] = "Activar registro detallado para depuraci�n. Activar solo si hay problemas."
L["CONFIG_DB_STATS"] = "Mostrar estad�sticas de base de datos"
L["CONFIG_DB_STATS_DESC"] = "Mostrar tama�o actual de la base de datos y estad�sticas de optimizaci�n."
L["CONFIG_DB_OPTIMIZER_NA"] = "Optimizador de base de datos no cargado"
L["CONFIG_OPTIMIZE_NOW"] = "Optimizar base de datos ahora"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "Ejecutar el optimizador de base de datos para limpiar y comprimir los datos almacenados."
L["CONFIG_COMMANDS_HEADER"] = "Comandos de barra"
L["DISPLAY_SETTINGS"] = "Configuraci�n de pantalla"
L["DISPLAY_SETTINGS_DESC"] = "Personalizar c�mo se muestran objetos e informaci�n."
L["RESET_DEFAULT"] = "Restablecer predeterminado"
L["ANTI_ALIASING"] = "Suavizado"
L["PROFESSIONS_INFO_DESC"] = "Rastrea habilidades de profesi�n, concentraci�n, conocimiento y �rboles de especializaci�n en todos los personajes. Incluye Recipe Companion para fuentes de reactivos."
L["CONTRIBUTORS_TITLE"] = "Colaboradores"
L["ANTI_ALIASING_DESC"] = "Estilo de renderizado de bordes de fuente (afecta la legibilidad)"

-- =============================================
-- Recipe Companion
-- =============================================
L["RECIPE_COMPANION_TITLE"] = "Compa�ero de Recetas"
L["TOGGLE_TRACKER"] = "Alternar Rastreador"

-- =============================================
-- Sorting
-- =============================================
L["SORT_BY_LABEL"] = "Ordenar por:"
L["SORT_MODE_MANUAL"] = "Manual (Orden Personalizado)"
L["SORT_MODE_NAME"] = "Nombre (A-Z)"
L["SORT_MODE_LEVEL"] = "Nivel (Mayor)"
L["SORT_MODE_ILVL"] = "Nivel de Objeto (Mayor)"
L["SORT_MODE_GOLD"] = "Oro (Mayor)"

-- =============================================
-- Gold Management
-- =============================================
L["GOLD_MANAGER_BTN"] = "Objetivo de Oro"
L["GOLD_MANAGEMENT_TITLE"] = "Objetivo de Oro"
L["GOLD_MANAGEMENT_DESC"] = "Configure la gesti�n autom�tica de oro. Tanto los dep�sitos como los retiros se realizan autom�ticamente cuando el banco est� abierto usando la API C_Bank."
L["GOLD_MANAGEMENT_WARNING"] = "|cff44ff44Totalmente Autom�tico:|r Tanto los dep�sitos como los retiros de oro se realizan autom�ticamente cuando el banco est� abierto. �Establece tu cantidad objetivo y deja que el addon gestione tu oro!"
L["GOLD_MANAGEMENT_ENABLE"] = "Activar Gesti�n de Oro"
L["GOLD_MANAGEMENT_MODE"] = "Modo de Gesti�n"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "Solo Depositar"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "Si tienes m�s de X oro, el exceso se depositar� autom�ticamente en el banco de banda de guerra."
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "Solo Retirar"
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "Si tienes menos de X oro, la diferencia se retirar� autom�ticamente del banco de banda de guerra."
L["GOLD_MANAGEMENT_MODE_BOTH"] = "Ambos"
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "Mantener autom�ticamente exactamente X oro en tu personaje (depositar si sobra, retirar si falta)."
L["GOLD_MANAGEMENT_TARGET"] = "Cantidad de Oro Objetivo"
L["GOLD_MANAGEMENT_GOLD_LABEL"] = "oro"
L["GOLD_MANAGEMENT_HELPER"] = "Ingresa la cantidad de oro que deseas mantener en este personaje. El addon gestionar� autom�ticamente tu oro cuando abras el banco."
L["GOLD_MANAGEMENT_NOTIFICATION_DEPOSIT"] = "Depositar %s en el banco de banda de guerra (tienes %s)"
L["GOLD_MANAGEMENT_NOTIFICATION_WITHDRAW"] = "Retirar %s del banco de banda de guerra (tienes %s)"
L["GOLD_MANAGEMENT_DEPOSITED"] = "Depositado %s en el banco de banda de guerra"
L["GOLD_MANAGEMENT_WITHDRAWN"] = "Retirado %s del banco de banda de guerra"
