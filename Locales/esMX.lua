--[[
    Warband Nexus - Spanish (Mexico) Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "esMX")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus cargado. Escribe /wn o /warbandnexus para opciones."
L["VERSION"] = GAME_VERSION_LABEL or "Versiï¿½n"

-- Slash Commands
L["SLASH_HELP"] = "Comandos disponibles:"
L["SLASH_OPTIONS"] = "Abrir panel de opciones"
L["SLASH_SCAN"] = "Escanear banco de banda de guerra"
L["SLASH_SHOW"] = "Mostrar/ocultar ventana principal"
L["SLASH_DEPOSIT"] = "Abrir cola de depï¿½sito"
L["SLASH_SEARCH"] = "Buscar un objeto"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Configuraciï¿½n general"
L["GENERAL_SETTINGS_DESC"] = "Configurar el comportamiento general del addon"
L["ENABLE_ADDON"] = "Activar addon"
L["ENABLE_ADDON_DESC"] = "Activar o desactivar la funcionalidad de Warband Nexus"
L["MINIMAP_ICON"] = "Mostrar icono del minimapa"
L["MINIMAP_ICON_DESC"] = "Mostrar u ocultar el botï¿½n del minimapa"
L["DEBUG_MODE"] = "Modo de depuraciï¿½n"
L["DEBUG_MODE_DESC"] = "Activar mensajes de depuraciï¿½n en el chat"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "Configuraciï¿½n de escaneo"
L["SCANNING_SETTINGS_DESC"] = "Configurar el comportamiento de escaneo del banco"
L["AUTO_SCAN"] = "Escaneo automï¿½tico al abrir"
L["AUTO_SCAN_DESC"] = "Escanear automï¿½ticamente el banco al abrirlo"
L["SCAN_DELAY"] = "Retraso de escaneo"
L["SCAN_DELAY_DESC"] = "Retraso entre operaciones de escaneo (en segundos)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "Configuraciï¿½n de depï¿½sito"
L["DEPOSIT_SETTINGS_DESC"] = "Configurar el comportamiento de depï¿½sito de objetos"
L["GOLD_RESERVE"] = "Reserva de oro"
L["GOLD_RESERVE_DESC"] = "Oro mï¿½nimo a mantener en el inventario personal (en oro)"
L["AUTO_DEPOSIT_REAGENTS"] = "Depositar reactivos automï¿½ticamente"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "Poner reactivos en cola de depï¿½sito al abrir el banco"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Configuraciï¿½n de pantalla"
L["DISPLAY_SETTINGS_DESC"] = "Configurar la apariencia visual"
L["SHOW_ITEM_LEVEL"] = "Mostrar nivel de objeto"
L["SHOW_ITEM_LEVEL_DESC"] = "Mostrar nivel de objeto en equipamiento"
L["SHOW_ITEM_COUNT"] = "Mostrar cantidad de objetos"
L["SHOW_ITEM_COUNT_DESC"] = "Mostrar cantidades apiladas en objetos"
L["HIGHLIGHT_QUALITY"] = "Resaltar por calidad"
L["HIGHLIGHT_QUALITY_DESC"] = "Aï¿½adir bordes de color segï¿½n la calidad del objeto"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "Configuraciï¿½n de pestaï¿½as"
L["TAB_SETTINGS_DESC"] = "Configurar el comportamiento de las pestaï¿½as del banco"
L["IGNORED_TABS"] = "Pestaï¿½as ignoradas"
L["IGNORED_TABS_DESC"] = "Seleccionar pestaï¿½as a excluir del escaneo y operaciones"
L["TAB_1"] = "Pestaï¿½a de banda 1"
L["TAB_2"] = "Pestaï¿½a de banda 2"
L["TAB_3"] = "Pestaï¿½a de banda 3"
L["TAB_4"] = "Pestaï¿½a de banda 4"
L["TAB_5"] = "Pestaï¿½a de banda 5"

-- Scanner Module
L["SCAN_STARTED"] = "Escaneando banco de banda de guerra..."
L["SCAN_COMPLETE"] = "Escaneo completado. Se encontraron %d objetos en %d espacios."
L["SCAN_FAILED"] = "Escaneo fallido: El banco de banda de guerra no estï¿½ abierto."
L["SCAN_TAB"] = "Escaneando pestaï¿½a %d..."
L["CACHE_CLEARED"] = "Cachï¿½ de objetos borrada."
L["CACHE_UPDATED"] = "Cachï¿½ de objetos actualizada."

-- Banker Module
L["BANK_NOT_OPEN"] = "El banco de banda de guerra no estï¿½ abierto."
L["DEPOSIT_STARTED"] = "Iniciando operaciï¿½n de depï¿½sito..."
L["DEPOSIT_COMPLETE"] = "Depï¿½sito completado. %d objetos transferidos."
L["DEPOSIT_CANCELLED"] = "Depï¿½sito cancelado."
L["DEPOSIT_QUEUE_EMPTY"] = "La cola de depï¿½sito estï¿½ vacï¿½a."
L["DEPOSIT_QUEUE_CLEARED"] = "Cola de depï¿½sito vaciada."
L["ITEM_QUEUED"] = "%s en cola para depï¿½sito."
L["ITEM_REMOVED"] = "%s eliminado de la cola."
L["GOLD_DEPOSITED"] = "%s oro depositado en el banco de banda de guerra."
L["INSUFFICIENT_GOLD"] = "Oro insuficiente para el depï¿½sito."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "Cantidad no vï¿½lida."
L["WITHDRAW_BANK_NOT_OPEN"] = "ï¿½El banco debe estar abierto para retirar!"
L["WITHDRAW_IN_COMBAT"] = "No se puede retirar durante el combate."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "No hay suficiente oro en el banco de banda de guerra."
L["WITHDRAWN_LABEL"] = "Retirado:"
L["WITHDRAW_API_UNAVAILABLE"] = "API de retiro no disponible."
L["SORT_IN_COMBAT"] = "No se puede ordenar durante el combate."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global
L["SEARCH_CATEGORY_FORMAT"] = "Buscar %s..."
L["BTN_SCAN"] = "Escanear banco"
L["BTN_DEPOSIT"] = "Cola de depï¿½sito"
L["BTN_SORT"] = "Ordenar banco"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "Vaciar cola"
L["BTN_DEPOSIT_ALL"] = "Depositar todo"
L["BTN_DEPOSIT_GOLD"] = "Depositar oro"
L["ENABLE"] = ENABLE or "Activar" -- Blizzard Global
L["ENABLE_MODULE"] = "Activar mï¿½dulo"

-- Main Tabs
L["TAB_CHARACTERS"] = CHARACTER or "Personajes" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "Objetos" -- Blizzard Global
L["TAB_STORAGE"] = "Almacenamiento"
L["TAB_PLANS"] = "Planes"
L["TAB_REPUTATION"] = REPUTATION or "Reputaciï¿½n" -- Blizzard Global
L["TAB_REPUTATIONS"] = "Reputaciones"
L["TAB_CURRENCY"] = CURRENCY or "Moneda" -- Blizzard Global
L["TAB_CURRENCIES"] = "Monedas"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "Estadï¿½sticas" -- Blizzard Global

-- Item Categories (Blizzard Globals)
L["CATEGORY_ALL"] = ALL or "Todos los objetos" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipamiento"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumibles"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reactivos"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Mercancï¿½as"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Objetos de misiï¿½n"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Miscelï¿½nea"

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
L["HEADER_FAVORITES"] = FAVORITES or "Favoritos" -- Blizzard Global
L["HEADER_CHARACTERS"] = CHARACTER or "Personajes"
L["HEADER_CURRENT_CHARACTER"] = "PERSONAJE ACTUAL"
L["HEADER_WARBAND_GOLD"] = "ORO DE BANDA DE GUERRA"
L["HEADER_TOTAL_GOLD"] = "ORO TOTAL"
L["HEADER_REALM_GOLD"] = "ORO DEL REINO"
L["HEADER_REALM_TOTAL"] = "TOTAL DEL REINO"
L["CHARACTER_LAST_SEEN_FORMAT"] = "Visto por ï¿½ltima vez: %s"
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
L["GROUP_PROFESSION"] = "Profesiï¿½n"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reactivos"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Mercancï¿½as"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Misiï¿½n"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscelï¿½nea"
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
L["PLANS_COLLECTIONS"] = "Planes de colecciï¿½n"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "Aï¿½adir plan personalizado"
L["PLANS_NO_RESULTS"] = "No se encontraron resultados."
L["PLANS_ALL_COLLECTED"] = "ï¿½Todos los objetos recolectados!"
L["PLANS_RECIPE_HELP"] = "Haz clic derecho en las recetas de tu inventario para aï¿½adirlas aquï¿½."
L["COLLECTION_PLANS"] = "Planes de colecciï¿½n"
L["SEARCH_PLANS"] = "Buscar planes..."
L["COMPLETED_PLANS"] = "Planes completados"
L["SHOW_COMPLETED"] = "Mostrar completados"
L["SHOW_PLANNED"] = "Mostrar planeados"
L["NO_PLANNED_ITEMS"] = "Aï¿½n no hay %ss planeados"

-- Plans Categories (Blizzard Globals)
L["CATEGORY_MY_PLANS"] = "Mis Planes"
L["CATEGORY_DAILY_TASKS"] = "Tareas diarias"
L["CATEGORY_MOUNTS"] = MOUNTS or "Monturas" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "Mascotas" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "Juguetes" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transfiguraciï¿½n" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "Ilusiones"
L["CATEGORY_TITLES"] = TITLES or "Tï¿½tulos"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Logros" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " reputaciï¿½n..."
L["REP_HEADER_WARBAND"] = "Reputaciï¿½n de banda de guerra"
L["REP_HEADER_CHARACTER"] = "Reputaciï¿½n del personaje"
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
L["STATS_HEADER"] = STATISTICS or "Estadï¿½sticas"
L["STATS_TOTAL_ITEMS"] = "Objetos totales"
L["STATS_TOTAL_SLOTS"] = "Espacios totales"
L["STATS_FREE_SLOTS"] = "Espacios libres"
L["STATS_USED_SLOTS"] = "Espacios usados"
L["STATS_TOTAL_VALUE"] = "Valor total"
L["COLLECTED"] = "Recolectado"
L["TOTAL"] = "Total"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Personaje" -- Blizzard Global
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Ubicaciï¿½n" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "Banco de banda de guerra"
L["TOOLTIP_TAB"] = "Pestaï¿½a"
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
L["DOUBLECLICK_RESET"] = "Doble clic para restablecer la posiciï¿½n"

-- Error Messages
L["ERROR_GENERIC"] = "Se ha producido un error."
L["ERROR_API_UNAVAILABLE"] = "La API requerida no estï¿½ disponible."
L["ERROR_BANK_CLOSED"] = "No se puede realizar la operaciï¿½n: banco cerrado."
L["ERROR_INVALID_ITEM"] = "Objeto especificado no vï¿½lido."
L["ERROR_PROTECTED_FUNCTION"] = "No se puede llamar a una funciï¿½n protegida en combate."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "ï¿½Depositar %d objetos en el banco de banda de guerra?"
L["CONFIRM_CLEAR_QUEUE"] = "ï¿½Vaciar todos los objetos de la cola de depï¿½sito?"
L["CONFIRM_DEPOSIT_GOLD"] = "ï¿½Depositar %s oro en el banco de banda de guerra?"

-- Update Notification
L["WHATS_NEW"] = "Novedades"
L["GOT_IT"] = "ï¿½Entendido!"

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
L["WEEKLY_VAULT"] = "Bï¿½veda Semanal"
L["CUSTOM"] = "Personalizado"
L["NO_PLANS_IN_CATEGORY"] = "No hay planes en esta categorï¿½a.\nAï¿½ade planes desde la pestaï¿½a Planes."
L["SOURCE_LABEL"] = "Fuente:"
L["ZONE_LABEL"] = "Zona:"
L["VENDOR_LABEL"] = "Vendedor:"
L["DROP_LABEL"] = "Botï¿½n:"
L["REQUIREMENT_LABEL"] = "Requisito:"
L["RIGHT_CLICK_REMOVE"] = "Clic derecho para eliminar"
L["TRACKED"] = "Rastreado"
L["TRACK"] = "Rastrear"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Rastrear en objetivos de Blizzard (mï¿½x. 10)"
L["UNKNOWN"] = "Desconocido"
L["NO_REQUIREMENTS"] = "Sin requisitos (completado instantï¿½neo)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "Sin actividad planificada"
L["CLICK_TO_ADD_GOALS"] = "ï¿½Haz clic en Monturas, Mascotas o Juguetes arriba para aï¿½adir objetivos!"
L["UNKNOWN_QUEST"] = "Misiï¿½n desconocida"
L["ALL_QUESTS_COMPLETE"] = "ï¿½Todas las misiones completadas!"
L["CURRENT_PROGRESS"] = "Progreso actual"
L["SELECT_CONTENT"] = "Seleccionar contenido:"
L["QUEST_TYPES"] = "Tipos de misiï¿½n:"
L["WORK_IN_PROGRESS"] = "En desarrollo"
L["RECIPE_BROWSER"] = "Explorador de recetas"
L["NO_RESULTS_FOUND"] = "No se encontraron resultados."
L["TRY_ADJUSTING_SEARCH"] = "Intenta ajustar tu bï¿½squeda o filtros."
L["NO_COLLECTED_YET"] = "Ningï¿½n %s recolectado aï¿½n"
L["START_COLLECTING"] = "ï¿½Empieza a recolectar para verlos aquï¿½!"
L["ALL_COLLECTED_CATEGORY"] = "ï¿½Todos los %ss recolectados!"
L["COLLECTED_EVERYTHING"] = "ï¿½Has recolectado todo en esta categorï¿½a!"
L["PROGRESS_LABEL"] = "Progreso:"
L["REQUIREMENTS_LABEL"] = "Requisitos:"
L["INFORMATION_LABEL"] = "Informaciï¿½n:"
L["DESCRIPTION_LABEL"] = "Descripciï¿½n:"
L["REWARD_LABEL"] = "Recompensa:"
L["DETAILS_LABEL"] = "Detalles:"
L["COST_LABEL"] = "Coste:"
L["LOCATION_LABEL"] = "Ubicaciï¿½n:"
L["TITLE_LABEL"] = "Tï¿½tulo:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "ï¿½Ya has completado todos los logros de esta categorï¿½a!"
L["DAILY_PLAN_EXISTS"] = "El plan diario ya existe"
L["WEEKLY_PLAN_EXISTS"] = "El plan semanal ya existe"

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "Tus personajes"
L["CHARACTERS_TRACKED_FORMAT"] = "%d personajes rastreados"
L["NO_CHARACTER_DATA"] = "No hay datos de personajes disponibles"
L["NO_FAVORITES"] = "Aï¿½n no hay personajes favoritos. Haz clic en el icono de estrella para marcar un personaje como favorito."
L["ALL_FAVORITED"] = "ï¿½Todos los personajes estï¿½n marcados como favoritos!"
L["UNTRACKED_CHARACTERS"] = "Personajes no rastreados"
L["ILVL_SHORT"] = "iLvl"
L["ONLINE"] = "En lï¿½nea"
L["TIME_LESS_THAN_MINUTE"] = "< 1m atrï¿½s"
L["TIME_MINUTES_FORMAT"] = "%dm atrï¿½s"
L["TIME_HOURS_FORMAT"] = "%dh atrï¿½s"
L["TIME_DAYS_FORMAT"] = "%dd atrï¿½s"
L["REMOVE_FROM_FAVORITES"] = "Quitar de favoritos"
L["ADD_TO_FAVORITES"] = "Aï¿½adir a favoritos"
L["FAVORITES_TOOLTIP"] = "Los personajes favoritos aparecen en la parte superior de la lista"
L["CLICK_TO_TOGGLE"] = "Clic para alternar"
L["UNKNOWN_PROFESSION"] = "Profesiï¿½n desconocida"
L["SKILL_LABEL"] = "Habilidad:"
L["OVERALL_SKILL"] = "Habilidad total:"
L["BONUS_SKILL"] = "Habilidad de bonificaciï¿½n:"
L["KNOWLEDGE_LABEL"] = "Conocimiento:"
L["SPEC_LABEL"] = "Espec."
L["POINTS_SHORT"] = "pts"
L["RECIPES_KNOWN"] = "Recetas conocidas:"
L["OPEN_PROFESSION_HINT"] = "Abrir ventana de profesiï¿½n"
L["FOR_DETAILED_INFO"] = "para informaciï¿½n detallada"
L["CHARACTER_IS_TRACKED"] = "Este personaje estï¿½ siendo rastreado."
L["TRACKING_ACTIVE_DESC"] = "La recopilaciï¿½n de datos y las actualizaciones estï¿½n activas."
L["CLICK_DISABLE_TRACKING"] = "Haz clic para desactivar el rastreo."
L["MUST_LOGIN_TO_CHANGE"] = "Debes iniciar sesiï¿½n con este personaje para cambiar el rastreo."
L["TRACKING_ENABLED"] = "Rastreo activado"
L["CLICK_ENABLE_TRACKING"] = "Haz clic para activar el rastreo para este personaje."
L["TRACKING_WILL_BEGIN"] = "La recopilaciï¿½n de datos comenzarï¿½ de inmediato."
L["CHARACTER_NOT_TRACKED"] = "Este personaje no estï¿½ siendo rastreado."
L["MUST_LOGIN_TO_ENABLE"] = "Debes iniciar sesiï¿½n con este personaje para activar el rastreo."
L["ENABLE_TRACKING"] = "Activar rastreo"
L["DELETE_CHARACTER_TITLE"] = "ï¿½Eliminar personaje?"
L["THIS_CHARACTER"] = "este personaje"
L["DELETE_CHARACTER"] = "Eliminar personaje"
L["REMOVE_FROM_TRACKING_FORMAT"] = "Quitar %s del rastreo"
L["CLICK_TO_DELETE"] = "Haz clic para eliminar"
L["CONFIRM_DELETE"] = "ï¿½Estï¿½s seguro de que quieres eliminar a |cff00ccff%s|r?"
L["CANNOT_UNDO"] = "ï¿½Esta acciï¿½n no se puede deshacer!"
L["DELETE"] = DELETE or "Eliminar"
L["CANCEL"] = CANCEL or "Cancelar"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "Objetos personales"
L["ITEMS_SUBTITLE"] = "Explora tu Banco de Banda de Guerra, Banco de Hermandad y Objetos Personales"
L["ITEMS_DISABLED_TITLE"] = "Objetos del Banco de Banda de Guerra"
L["ITEMS_LOADING"] = "Cargando datos de inventario"
L["GUILD_BANK_REQUIRED"] = "Debes estar en una hermandad para acceder al Banco de Hermandad."
L["GUILD_JOINED_FORMAT"] = "Hermandad actualizada: %s"
L["GUILD_LEFT"] = "Ya no estás en una hermandad. Pestaña de Banco de Hermandad desactivada."
L["NO_PERMISSION"] = "Sin permiso"
L["NOT_IN_GUILD"] = "No en hermandad"
L["ITEMS_SEARCH"] = "Buscar objetos..."
L["NEVER"] = "Nunca"
L["ITEM_FALLBACK_FORMAT"] = "Objeto %s"
L["TAB_FORMAT"] = "Pestaï¿½a %d"
L["BAG_FORMAT"] = "Bolsa %d"
L["BANK_BAG_FORMAT"] = "Bolsa de banco %d"
L["ITEM_ID_LABEL"] = "ID de objeto:"
L["QUALITY_TOOLTIP_LABEL"] = "Calidad:"
L["STACK_LABEL"] = "Montï¿½n:"
L["RIGHT_CLICK_MOVE"] = "Mover a bolsa"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Dividir montï¿½n"
L["LEFT_CLICK_PICKUP"] = "Recoger"
L["ITEMS_BANK_NOT_OPEN"] = "Banco no abierto"
L["SHIFT_LEFT_CLICK_LINK"] = "Enlazar en chat"
L["ITEM_DEFAULT_TOOLTIP"] = "Objeto"
L["ITEMS_STATS_ITEMS"] = "%s objetos"
L["ITEMS_STATS_SLOTS"] = "%s/%s espacios"
L["ITEMS_STATS_LAST"] = "ï¿½ltimo: %s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "Almacenamiento de personaje"
L["STORAGE_SEARCH"] = "Buscar almacenamiento..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "Progreso PvE"
L["PVE_SUBTITLE"] = "Gran Bï¿½veda, Bloqueos de Banda y Mï¿½tica+ en tu Banda de Guerra"
L["PVE_NO_CHARACTER"] = "No hay datos de personajes disponibles"
L["LV_FORMAT"] = "Nv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = "Banda"
L["VAULT_DUNGEON"] = "Mazmorra"
L["VAULT_WORLD"] = "Mundo"
L["VAULT_SLOT_FORMAT"] = "%s Espacio %d"
L["VAULT_NO_PROGRESS"] = "Aï¿½n no hay progreso"
L["VAULT_UNLOCK_FORMAT"] = "Completa %s actividades para desbloquear"
L["VAULT_NEXT_TIER_FORMAT"] = "Siguiente nivel: %d iLvl al completar %s"
L["VAULT_REMAINING_FORMAT"] = "Restante: %s actividades"
L["VAULT_PROGRESS_FORMAT"] = "Progreso: %s / %s"
L["OVERALL_SCORE_LABEL"] = "Puntuaciï¿½n total:"
L["BEST_KEY_FORMAT"] = "Mejor llave: +%d"
L["SCORE_FORMAT"] = "Puntuaciï¿½n: %s"
L["NOT_COMPLETED_SEASON"] = "No completado esta temporada"
L["CURRENT_MAX_FORMAT"] = "Actual: %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "Progreso: %.1f%%"
L["NO_CAP_LIMIT"] = "Sin lï¿½mite mï¿½ximo"
L["GREAT_VAULT"] = "Gran Bï¿½veda"
L["LOADING_PVE"] = "Cargando datos PvE..."
L["PVE_APIS_LOADING"] = "Por favor espera, las APIs de WoW se estï¿½n inicializando..."
L["NO_VAULT_DATA"] = "Sin datos de bï¿½veda"
L["NO_DATA"] = "Sin datos"
L["KEYSTONE"] = "Piedra angular"
L["NO_KEY"] = "Sin llave"
L["AFFIXES"] = "Afijos"
L["NO_AFFIXES"] = "Sin afijos"
L["VAULT_BEST_KEY"] = "Mejor llave:"
L["VAULT_SCORE"] = "Puntuaciï¿½n:"

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "Resumen de Reputaciï¿½n"
L["REP_SUBTITLE"] = "Rastrea facciones y renombre en tu banda de guerra"
L["REP_DISABLED_TITLE"] = "Rastreo de Reputaciï¿½n"
L["REP_LOADING_TITLE"] = "Cargando Datos de Reputaciï¿½n"
L["REP_SEARCH"] = "Buscar reputaciones..."
L["REP_PARAGON_TITLE"] = "Reputaciï¿½n Paragï¿½n"
L["REP_REWARD_AVAILABLE"] = "ï¿½Recompensa disponible!"
L["REP_CONTINUE_EARNING"] = "Continï¿½a ganando reputaciï¿½n para obtener recompensas"
L["REP_CYCLES_FORMAT"] = "Ciclos: %d"
L["REP_PROGRESS_HEADER"] = "Progreso: %d/%d"
L["REP_PARAGON_PROGRESS"] = "Progreso Paragï¿½n:"
L["REP_PROGRESS_COLON"] = "Progreso:"
L["REP_CYCLES_COLON"] = "Ciclos:"
L["REP_CHARACTER_PROGRESS"] = "Progreso del personaje:"
L["REP_RENOWN_FORMAT"] = "Renombre %d"
L["REP_PARAGON_FORMAT"] = "Paragï¿½n (%s)"
L["REP_UNKNOWN_FACTION"] = "Facciï¿½n desconocida"
L["REP_API_UNAVAILABLE_TITLE"] = "API de Reputaciï¿½n No Disponible"
L["REP_API_UNAVAILABLE_DESC"] = "La API C_Reputation no estï¿½ disponible en este servidor. Esta funciï¿½n requiere WoW 11.0+ (The War Within)."
L["REP_FOOTER_TITLE"] = "Rastreo de Reputaciï¿½n"
L["REP_FOOTER_DESC"] = "Las reputaciones se escanean automï¿½ticamente al iniciar sesiï¿½n y cuando cambian. Usa el panel de reputaciï¿½n en el juego para ver informaciï¿½n detallada y recompensas."
L["REP_CLEARING_CACHE"] = "Limpiando cachï¿½ y recargando..."
L["REP_LOADING_DATA"] = "Cargando datos de reputaciï¿½n..."
L["REP_MAX"] = "Mï¿½x."
L["REP_TIER_FORMAT"] = "Nivel %d"
L["ACCOUNT_WIDE_LABEL"] = "Toda la cuenta"
L["NO_RESULTS"] = "Sin resultados"
L["NO_REP_MATCH"] = "Ninguna reputaciï¿½n coincide con '%s'"
L["NO_REP_DATA"] = "No hay datos de reputaciï¿½n disponibles"
L["REP_SCAN_TIP"] = "Las reputaciones se escanean automï¿½ticamente. Intenta /reload si no aparece nada."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "Reputaciones de toda la cuenta (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "Sin reputaciones de toda la cuenta"
L["NO_CHARACTER_REPS"] = "Sin reputaciones de personaje"

-- =============================================
-- Currency Tab
-- =============================================
L["GOLD_LABEL"] = "Oro"
L["CURRENCY_TITLE"] = "Rastreador de Monedas"
L["CURRENCY_SUBTITLE"] = "Rastrea todas las monedas de tus personajes"
L["CURRENCY_DISABLED_TITLE"] = "Rastreo de Monedas"
L["CURRENCY_LOADING_TITLE"] = "Cargando Datos de Monedas"
L["CURRENCY_SEARCH"] = "Buscar monedas..."
L["CURRENCY_HIDE_EMPTY"] = "Ocultar vacï¿½as"
L["CURRENCY_SHOW_EMPTY"] = "Mostrar vacï¿½as"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "Todas Transferibles entre Banda"
L["CURRENCY_CHARACTER_SPECIFIC"] = "Monedas Especï¿½ficas del Personaje"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "Limitaciï¿½n de Transferencia de Monedas"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "La API de Blizzard no admite transferencias automï¿½ticas de monedas. Por favor, usa la ventana de monedas en el juego para transferir manualmente las monedas de Banda de Guerra."
L["CURRENCY_UNKNOWN"] = "Moneda desconocida"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "Elimina todos los planes completados de tu lista Mis Planes. Esto eliminarï¿½ todos los planes personalizados completados y quitarï¿½ las monturas/mascotas/juguetes completados de tus planes. ï¿½Esta acciï¿½n no se puede deshacer!"
L["RECIPE_BROWSER_DESC"] = "Abre tu ventana de Profesiï¿½n en el juego para explorar recetas.\nEl addon escanearï¿½ las recetas disponibles cuando la ventana estï¿½ abierta."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "Fuente: [Logro %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s ya tiene un plan activo de bï¿½veda semanal. Puedes encontrarlo en la categorï¿½a 'Mis Planes'."
L["DAILY_PLAN_EXISTS_DESC"] = "%s ya tiene un plan activo de misiï¿½n diaria. Puedes encontrarlo en la categorï¿½a 'Tareas Diarias'."
L["TRANSMOG_WIP_DESC"] = "El rastreo de colecciï¿½n de transfiguraciï¿½n estï¿½ actualmente en desarrollo.\n\nEsta funciï¿½n estarï¿½ disponible en una actualizaciï¿½n futura con mejor\nrendimiento y mejor integraciï¿½n con los sistemas de Banda de Guerra."
L["WEEKLY_VAULT_CARD"] = "Tarjeta de Bï¿½veda Semanal"
L["WEEKLY_VAULT_COMPLETE"] = "Tarjeta de Bï¿½veda Semanal - Completada"
L["UNKNOWN_SOURCE"] = "Fuente desconocida"
L["DAILY_TASKS_PREFIX"] = "Tareas Diarias - "
L["NO_FOUND_FORMAT"] = "No se encontraron %ss"
L["PLANS_COUNT_FORMAT"] = "%d planes"
L["PET_BATTLE_LABEL"] = "Batalla de mascotas:"
L["QUEST_LABEL"] = "Misiï¿½n:"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "Idioma actual:"
L["LANGUAGE_TOOLTIP"] = "El addon utiliza automï¿½ticamente el idioma de tu cliente de WoW. Para cambiarlo, actualiza la configuraciï¿½n de Battle.net."
L["POPUP_DURATION"] = "Duraciï¿½n del popup"
L["POPUP_POSITION"] = "Posiciï¿½n del popup"
L["SET_POSITION"] = "Establecer posiciï¿½n"
L["DRAG_TO_POSITION"] = "Arrastra para posicionar\nClic derecho para confirmar"
L["RESET_DEFAULT"] = "Restablecer predeterminado"
L["TEST_POPUP"] = "Probar popup"
L["CUSTOM_COLOR"] = "Color personalizado"
L["OPEN_COLOR_PICKER"] = "Abrir selector de color"
L["COLOR_PICKER_TOOLTIP"] = "Abre el selector de color nativo de WoW para elegir un color de tema personalizado"
L["PRESET_THEMES"] = "Temas predefinidos"
L["WARBAND_NEXUS_SETTINGS"] = "Configuraciï¿½n de Warband Nexus"
L["NO_OPTIONS"] = "Sin opciones"
L["NONE_LABEL"] = NONE or "Ninguno"
L["TAB_FILTERING"] = "Filtrado de pestaï¿½as"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Notificaciones"
L["SCROLL_SPEED"] = "Velocidad de desplazamiento"
L["ANCHOR_FORMAT"] = "Ancla: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "Mostrar Planificador Semanal"
L["LOCK_MINIMAP_ICON"] = "Bloquear icono del minimapa"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "Mostrar objetos en descripciones"
L["AUTO_SCAN_ITEMS"] = "Escaneo automï¿½tico de objetos"
L["LIVE_SYNC"] = "Sincronizaciï¿½n en vivo"
L["BACKPACK_LABEL"] = "Mochila"
L["REAGENT_LABEL"] = "Reactivo"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "Mï¿½dulo desactivado"
L["LOADING"] = "Cargando..."
L["PLEASE_WAIT"] = "Por favor espera..."
L["RESET_PREFIX"] = "Reinicio:"
L["TRANSFER_CURRENCY"] = "Transferir moneda"
L["AMOUNT_LABEL"] = "Cantidad:"
L["TO_CHARACTER"] = "Al personaje:"
L["SELECT_CHARACTER"] = "Seleccionar personaje..."
L["CURRENCY_TRANSFER_INFO"] = "La ventana de monedas se abrirï¿½ automï¿½ticamente.\nNecesitarï¿½s hacer clic derecho manualmente en la moneda para transferirla."
L["OK_BUTTON"] = OKAY or "OK"
L["SAVE"] = "Guardar"
L["TITLE_FIELD"] = "Tï¿½tulo:"
L["DESCRIPTION_FIELD"] = "Descripciï¿½n:"
L["CREATE_CUSTOM_PLAN"] = "Crear Plan Personalizado"
L["REPORT_BUGS"] = "Reporta errores o comparte sugerencias en CurseForge para ayudar a mejorar el addon."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus proporciona una interfaz centralizada para gestionar todos tus personajes, monedas, reputaciones, objetos y progreso PvE en toda tu Banda de Guerra."
L["CHARACTERS_DESC"] = "Ver todos los personajes con oro, nivel, iLvl, facciï¿½n, raza, clase, profesiones, piedra angular e info de ï¿½ltima sesiï¿½n. Rastrea o deja de rastrear personajes, marca favoritos."
L["ITEMS_DESC"] = "Busca y explora objetos en todas las bolsas, bancos y banco de banda. Escaneo automï¿½tico al abrir un banco. Los tooltips muestran quï¿½ personajes poseen cada objeto."
L["STORAGE_DESC"] = "Vista de inventario agregada de todos los personajes ï¿½ bolsas, banco personal y banco de banda combinados en un solo lugar."
L["PVE_DESC"] = "Rastrea el progreso de Gran Bï¿½veda con indicadores de nivel, puntuaciones y claves Mï¿½tica+, afijos, historial de mazmorras y moneda de mejora en todos los personajes."
L["REPUTATIONS_DESC"] = "Compara el progreso de reputaciï¿½n entre todos los personajes. Muestra facciones de Toda la Cuenta vs Especï¿½ficas con tooltips para desglose por personaje."
L["CURRENCY_DESC"] = "Ver todas las monedas organizadas por expansiï¿½n. Compara cantidades entre personajes con tooltips al pasar el cursor. Oculta monedas vacï¿½as con un clic."
L["PLANS_DESC"] = "Rastrea monturas, mascotas, juguetes, logros y transmog no recolectados. Aï¿½ade objetivos, ve fuentes de drop y sigue los contadores de intentos. Acceso vï¿½a /wn plan o ï¿½cono del minimapa."
L["STATISTICS_DESC"] = "Ver puntos de logro, progreso de colecciï¿½n de monturas/mascotas/juguetes/ilusiones/tï¿½tulos, contador de mascotas ï¿½nicas y estadï¿½sticas de uso de bolsas/banco."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "Mï¿½tica"
L["DIFFICULTY_HEROIC"] = "Heroica"
L["DIFFICULTY_NORMAL"] = "Normal"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Nivel %d"
L["PVP_TYPE"] = "JcJ"
L["PREPARING"] = "Preparando"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Estadï¿½sticas de Cuenta"
L["STATISTICS_SUBTITLE"] = "Progreso de colecciï¿½n, oro y resumen de almacenamiento"
L["MOST_PLAYED"] = "Mï¿½S JUGADOS"
L["PLAYED_DAYS"] = "Dï¿½as"
L["PLAYED_HOURS"] = "Horas"
L["PLAYED_MINUTES"] = "Minutos"
L["PLAYED_DAY"] = "Dï¿½a"
L["PLAYED_HOUR"] = "Hora"
L["PLAYED_MINUTE"] = "Minuto"
L["MORE_CHARACTERS"] = "personaje mï¿½s"
L["MORE_CHARACTERS_PLURAL"] = "personajes mï¿½s"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "ï¿½Bienvenido a Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "Resumen del AddOn"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "Rastrea tus objetivos de colecciï¿½n"
L["ACTIVE_PLAN_FORMAT"] = "%d plan activo"
L["ACTIVE_PLANS_FORMAT"] = "%d planes activos"
L["RESET_LABEL"] = RESET or "Reiniciar"

-- Plans - Type Names
L["TYPE_MOUNT"] = MOUNT or "Montura"
L["TYPE_PET"] = PET or "Mascota"
L["TYPE_TOY"] = TOY or "Juguete"
L["TYPE_RECIPE"] = "Receta"
L["TYPE_ILLUSION"] = "Ilusiï¿½n"
L["TYPE_TITLE"] = "Tï¿½tulo"
L["TYPE_CUSTOM"] = "Personalizado"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transfiguraciï¿½n"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Botï¿½n"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Misiï¿½n"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Vendedor"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profesiï¿½n"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Combate de mascotas"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Logro"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "Evento mundial"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promociï¿½n"
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
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Botï¿½n de jefe"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Misiï¿½n"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Vendedor"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "Botï¿½n en el mundo"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Logro"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Profesiï¿½n"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "Vendido por"
L["PARSE_CRAFTED"] = "Fabricado"
L["PARSE_ZONE"] = ZONE or "Zona"
L["PARSE_COST"] = "Costo"
L["PARSE_REPUTATION"] = REPUTATION or "Reputaciï¿½n"
L["PARSE_FACTION"] = FACTION or "Facciï¿½n"
L["PARSE_ARENA"] = ARENA or "Arena"
L["PARSE_DUNGEON"] = DUNGEONS or "Calabozo"
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
L["PARSE_MISSION"] = "Misiï¿½n"
L["PARSE_EXPANSION"] = "Expansiï¿½n"
L["PARSE_SCENARIO"] = "Escenario"
L["PARSE_CLASS_HALL"] = "Sala de la orden"
L["PARSE_CAMPAIGN"] = "Campaï¿½a"
L["PARSE_EVENT"] = "Evento"
L["PARSE_SPECIAL"] = "Especial"
L["PARSE_BRAWLERS_GUILD"] = "Gremio de camorristas"
L["PARSE_CHALLENGE_MODE"] = "Modo desafï¿½o"
L["PARSE_MYTHIC_PLUS"] = "Mï¿½tica+"
L["PARSE_TIMEWALKING"] = "Paseo del tiempo"
L["PARSE_ISLAND_EXPEDITION"] = "Expediciï¿½n a islas"
L["PARSE_WARFRONT"] = "Frente de guerra"
L["PARSE_TORGHAST"] = "Torghast"
L["PARSE_ZERETH_MORTIS"] = "Zereth Mortis"
L["PARSE_HIDDEN"] = "Oculto"
L["PARSE_RARE"] = "Raro"
L["PARSE_WORLD_BOSS"] = "Jefe de mundo"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Botï¿½n"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "Del logro"
L["FALLBACK_UNKNOWN_PET"] = "Mascota desconocida"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "Colecciï¿½n de mascotas"
L["FALLBACK_TOY_COLLECTION"] = "Colecciï¿½n de juguetes"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Colecciï¿½n de transfiguraciï¿½n"
L["FALLBACK_PLAYER_TITLE"] = "Tï¿½tulo de jugador"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Desconocido"
L["FALLBACK_ILLUSION_FORMAT"] = "Ilusiï¿½n %s"
L["SOURCE_ENCHANTING"] = "Encantamiento"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "Establecer contador de intentos para:\n%s"
L["RESET_COMPLETED_CONFIRM"] = "ï¿½Estï¿½s seguro de que quieres eliminar TODOS los planes completados?\n\nï¿½Esto no se puede deshacer!"
L["YES_RESET"] = "Sï¿½, Reiniciar"
L["REMOVED_PLANS_FORMAT"] = "Se eliminaron %d plan(es) completado(s)."

-- Plans - Buttons
L["ADD_CUSTOM"] = "Aï¿½adir Personalizado"
L["ADD_VAULT"] = "Aï¿½adir Bï¿½veda"
L["ADD_QUEST"] = "Aï¿½adir Misiï¿½n"
L["CREATE_PLAN"] = "Crear Plan"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "Diaria"
L["QUEST_CAT_WORLD"] = "Mundo"
L["QUEST_CAT_WEEKLY"] = "Semanal"
L["QUEST_CAT_ASSIGNMENT"] = "Asignaciï¿½n"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Categorï¿½a desconocida"
L["SCANNING_FORMAT"] = "Escaneando %s"
L["CUSTOM_PLAN_SOURCE"] = "Plan personalizado"
L["POINTS_FORMAT"] = "%d Puntos"
L["SOURCE_NOT_AVAILABLE"] = "Informaciï¿½n de fuente no disponible"
L["PROGRESS_ON_FORMAT"] = "Estï¿½s en %d/%d del progreso"
L["COMPLETED_REQ_FORMAT"] = "Has completado %d de %d requisitos totales"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Midnight"
L["CONTENT_TWW"] = "The War Within"
L["QUEST_TYPE_DAILY"] = "Misiones Diarias"
L["QUEST_TYPE_DAILY_DESC"] = "Misiones diarias regulares de PNJs"
L["QUEST_TYPE_WORLD"] = "Misiones de Mundo"
L["QUEST_TYPE_WORLD_DESC"] = "Misiones de mundo a nivel de zona"
L["QUEST_TYPE_WEEKLY"] = "Misiones Semanales"
L["QUEST_TYPE_WEEKLY_DESC"] = "Misiones semanales recurrentes"
L["QUEST_TYPE_ASSIGNMENTS"] = "Asignaciones"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "Asignaciones y tareas especiales"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "Mï¿½tica+"
L["RAIDS_LABEL"] = "Bandas"

-- PlanCardFactory
L["FACTION_LABEL"] = "Facciï¿½n:"
L["FRIENDSHIP_LABEL"] = "Amistad"
L["RENOWN_TYPE_LABEL"] = "Renombre"
L["ADD_BUTTON"] = "+ Aï¿½adir"
L["ADDED_LABEL"] = "Aï¿½adido"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s de %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Mostrar cantidades apiladas en objetos en la vista de almacenamiento"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Mostrar la secciï¿½n del Planificador Semanal en la pestaï¿½a Personajes"
L["LOCK_MINIMAP_TOOLTIP"] = "Bloquear el icono del minimapa en su lugar (previene arrastrar)"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "Muestra la cantidad de objetos de la banda de guerra y del personaje en las descripciones emergentes (Bï¿½squeda de WN)."
L["AUTO_SCAN_TOOLTIP"] = "Escanear y almacenar en cachï¿½ objetos automï¿½ticamente cuando abres bancos o bolsas"
L["LIVE_SYNC_TOOLTIP"] = "Mantener la cachï¿½ de objetos actualizada en tiempo real mientras los bancos estï¿½n abiertos"
L["SHOW_ILVL_TOOLTIP"] = "Mostrar insignias de nivel de objeto en equipamiento en la lista de objetos"
L["SCROLL_SPEED_TOOLTIP"] = "Multiplicador de velocidad de desplazamiento (1.0x = 28 px por paso)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "Ignorar Pestaï¿½a %d del Banco de Banda de Guerra del escaneo automï¿½tico"
L["IGNORE_SCAN_FORMAT"] = "Ignorar %s del escaneo automï¿½tico"
L["BANK_LABEL"] = BANK or "Banco"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "Activar Notificaciones"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Interruptor maestro para todas las ventanas emergentes de notificaciï¿½n"
L["VAULT_REMINDER"] = "Recordatorio de Bï¿½veda"
L["VAULT_REMINDER_TOOLTIP"] = "Mostrar recordatorio cuando tengas recompensas de Bï¿½veda Semanal sin reclamar"
L["LOOT_ALERTS"] = "Alertas de Botï¿½n"
L["LOOT_ALERTS_TOOLTIP"] = "Interruptor principal de popups de coleccionables. Desactivarlo oculta todas las notificaciones de coleccionables."
L["LOOT_ALERTS_MOUNT"] = "Notificaciones de monturas"
L["LOOT_ALERTS_MOUNT_TOOLTIP"] = "Mostrar notificaciï¿½n al recolectar una nueva montura."
L["LOOT_ALERTS_PET"] = "Notificaciones de mascotas"
L["LOOT_ALERTS_PET_TOOLTIP"] = "Mostrar notificaciï¿½n al recolectar una nueva mascota."
L["LOOT_ALERTS_TOY"] = "Notificaciones de juguetes"
L["LOOT_ALERTS_TOY_TOOLTIP"] = "Mostrar notificaciï¿½n al recolectar un nuevo juguete."
L["LOOT_ALERTS_TRANSMOG"] = "Notificaciones de apariencia"
L["LOOT_ALERTS_TRANSMOG_TOOLTIP"] = "Mostrar notificaciï¿½n al recolectar una nueva apariencia de armadura o arma."
L["LOOT_ALERTS_ILLUSION"] = "Notificaciones de ilusiones"
L["LOOT_ALERTS_ILLUSION_TOOLTIP"] = "Mostrar notificaciï¿½n al recolectar una nueva ilusiï¿½n de arma."
L["LOOT_ALERTS_TITLE"] = "Notificaciones de tï¿½tulos"
L["LOOT_ALERTS_TITLE_TOOLTIP"] = "Mostrar notificaciï¿½n al obtener un nuevo tï¿½tulo."
L["LOOT_ALERTS_ACHIEVEMENT"] = "Notificaciones de logros"
L["LOOT_ALERTS_ACHIEVEMENT_TOOLTIP"] = "Mostrar notificaciï¿½n al obtener un nuevo logro."
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Ocultar Alerta de Logro de Blizzard"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Ocultar la ventana emergente de logro predeterminada de Blizzard y usar la notificaciï¿½n de Warband Nexus en su lugar"
L["REPUTATION_GAINS"] = "Ganancias de Reputaciï¿½n"
L["REPUTATION_GAINS_TOOLTIP"] = "Mostrar mensajes de chat cuando ganes reputaciï¿½n con facciones"
L["CURRENCY_GAINS"] = "Ganancias de Monedas"
L["CURRENCY_GAINS_TOOLTIP"] = "Mostrar mensajes de chat cuando ganes monedas"
L["SCREEN_FLASH_EFFECT"] = "Efecto de destello de pantalla"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Reproducir un efecto de destello de pantalla al obtener un nuevo coleccionable (montura, mascota, juguete, etc.)"
L["AUTO_TRY_COUNTER"] = "Contador de intentos automï¿½tico"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Contar automï¿½ticamente los intentos al saquear NPCs, raros, jefes, pescar o abrir contenedores que pueden soltar monturas, mascotas o juguetes. Muestra el nï¿½mero de intentos en el chat cuando el coleccionable no cae."
L["DURATION_LABEL"] = "Duraciï¿½n"
L["DAYS_LABEL"] = "dï¿½as"
L["WEEKS_LABEL"] = "semanas"
L["EXTEND_DURATION"] = "Extender duraciï¿½n"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Arrastra el marco verde para establecer la posiciï¿½n de la ventana emergente. Clic derecho para confirmar."
L["POSITION_RESET_MSG"] = "Posiciï¿½n de la ventana emergente restablecida al predeterminado (Centro Superior)"
L["POSITION_SAVED_MSG"] = "ï¿½Posiciï¿½n de la ventana emergente guardada!"
L["TEST_NOTIFICATION_TITLE"] = "Notificaciï¿½n de prueba"
L["TEST_NOTIFICATION_MSG"] = "Prueba de posiciï¿½n"
L["NOTIFICATION_DEFAULT_TITLE"] = "Notificaciï¿½n"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "Tema y Apariencia"
L["COLOR_PURPLE"] = "Morado"
L["COLOR_PURPLE_DESC"] = "Tema morado clï¿½sico (predeterminado)"
L["COLOR_BLUE"] = "Azul"
L["COLOR_BLUE_DESC"] = "Tema azul frï¿½o"
L["COLOR_GREEN"] = "Verde"
L["COLOR_GREEN_DESC"] = "Tema verde naturaleza"
L["COLOR_RED"] = "Rojo"
L["COLOR_RED_DESC"] = "Tema rojo ardiente"
L["COLOR_ORANGE"] = "Naranja"
L["COLOR_ORANGE_DESC"] = "Tema naranja cï¿½lido"
L["COLOR_CYAN"] = "Cian"
L["COLOR_CYAN_DESC"] = "Tema cian brillante"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "Familia de Fuente"
L["FONT_FAMILY_TOOLTIP"] = "Elige la fuente utilizada en toda la interfaz del addon"
L["FONT_SCALE"] = "Escala de Fuente"
L["FONT_SCALE_TOOLTIP"] = "Ajustar el tamaï¿½o de fuente en todos los elementos de la interfaz"
L["FONT_SCALE_WARNING"] = "Advertencia: Una escala de fuente mayor puede causar desbordamiento de texto en algunos elementos de la interfaz."
L["RESOLUTION_NORMALIZATION"] = "Normalizaciï¿½n de Resoluciï¿½n"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Ajustar tamaï¿½os de fuente basados en resoluciï¿½n de pantalla y escala de interfaz para que el texto permanezca del mismo tamaï¿½o fï¿½sico en diferentes monitores"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Avanzado"

-- =============================================
-- Settings - Module Management
-- =============================================
L["MODULE_MANAGEMENT"] = "Gestiï¿½n de mï¿½dulos"
L["MODULE_MANAGEMENT_DESC"] = "Activar o desactivar mï¿½dulos de recopilaciï¿½n de datos especï¿½ficos. Desactivar un mï¿½dulo detendrï¿½ sus actualizaciones de datos y ocultarï¿½ su pestaï¿½a de la interfaz."
L["MODULE_CURRENCIES"] = "Monedas"
L["MODULE_CURRENCIES_DESC"] = "Rastrear monedas de toda la cuenta y especï¿½ficas del personaje (Oro, Honor, Conquista, etc.)"
L["MODULE_REPUTATIONS"] = "Reputaciones"
L["MODULE_REPUTATIONS_DESC"] = "Rastrear el progreso de reputaciï¿½n con facciones, niveles de renombre y recompensas paragï¿½n"
L["MODULE_ITEMS"] = "Objetos"
L["MODULE_ITEMS_DESC"] = "Rastrear objetos del banco de banda de guerra, funcionalidad de bï¿½squeda y categorï¿½as de objetos"
L["MODULE_STORAGE"] = "Almacenamiento"
L["MODULE_STORAGE_DESC"] = "Rastrear bolsas del personaje, banco personal y almacenamiento del banco de banda de guerra"
L["MODULE_PVE"] = "JcE"
L["MODULE_PVE_DESC"] = "Rastrear mazmorras Mï¿½tica+, progreso de bandas y recompensas de Gran Cï¿½mara"
L["MODULE_PLANS"] = "Planes"
L["MODULE_PLANS_DESC"] = "Rastrear objetivos personales para monturas, mascotas, juguetes, logros y tareas personalizadas"
L["MODULE_PROFESSIONS"] = "Profesiones"
L["MODULE_PROFESSIONS_DESC"] = "Rastrear habilidades de profesiï¿½n, concentraciï¿½n, conocimiento y ventana de recetas"
L["PROFESSIONS_DISABLED_TITLE"] = "Profesiones"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Nivel de Objeto %s"
L["ITEM_NUMBER_FORMAT"] = "Objeto #%s"
L["CHARACTER_CURRENCIES"] = "Monedas del Personaje:"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "Cuenta global (Banda de guerra) ï¿½ mismo saldo en todos los personajes."
L["YOU_MARKER"] = "(Tï¿½)"
L["WN_SEARCH"] = "Bï¿½squeda WN"
L["WARBAND_BANK_COLON"] = "Banco de Banda de Guerra:"
L["AND_MORE_FORMAT"] = "... y %d mï¿½s"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "Has recolectado una montura"
L["COLLECTED_PET_MSG"] = "Has recolectado una mascota de batalla"
L["COLLECTED_TOY_MSG"] = "Has recolectado un juguete"
L["COLLECTED_ILLUSION_MSG"] = "Has recolectado una ilusiï¿½n"
L["COLLECTED_ITEM_MSG"] = "Has recibido un botï¿½n raro"
L["ACHIEVEMENT_COMPLETED_MSG"] = "ï¿½Logro completado!"
L["EARNED_TITLE_MSG"] = "Has obtenido un tï¿½tulo"
L["COMPLETED_PLAN_MSG"] = "Has completado un plan"
L["DAILY_QUEST_CAT"] = "Misiï¿½n Diaria"
L["WORLD_QUEST_CAT"] = "Misiï¿½n de Mundo"
L["WEEKLY_QUEST_CAT"] = "Misiï¿½n Semanal"
L["SPECIAL_ASSIGNMENT_CAT"] = "Asignaciï¿½n Especial"
L["DELVE_CAT"] = "Excavaciï¿½n"
L["DUNGEON_CAT"] = "Mazmorra"
L["RAID_CAT"] = "Banda"
L["WORLD_CAT"] = "Mundo"
L["ACTIVITY_CAT"] = "Actividad"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Progreso"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Progreso Completado"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Plan de Bï¿½veda Semanal - %s"
L["ALL_SLOTS_COMPLETE"] = "ï¿½Todos los Espacios Completados!"
L["QUEST_COMPLETED_SUFFIX"] = "Completada"
L["WEEKLY_VAULT_READY"] = "ï¿½Bï¿½veda Semanal Lista!"
L["UNCLAIMED_REWARDS"] = "Tienes recompensas sin reclamar"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "Oro Total:"
L["CHARACTERS_COLON"] = "Personajes:"
L["LEFT_CLICK_TOGGLE"] = "Clic Izquierdo: Alternar ventana"
L["RIGHT_CLICK_PLANS"] = "Clic Derecho: Abrir Planes"
L["MINIMAP_SHOWN_MSG"] = "Botï¿½n del minimapa mostrado"
L["MINIMAP_HIDDEN_MSG"] = "Botï¿½n del minimapa oculto (usa /wn minimap para mostrar)"
L["TOGGLE_WINDOW"] = "Alternar Ventana"
L["SCAN_BANK_MENU"] = "Escanear Banco"
L["TRACKING_DISABLED_SCAN_MSG"] = "El rastreo de personajes estï¿½ desactivado. Activa el rastreo en la configuraciï¿½n para escanear el banco."
L["SCAN_COMPLETE_MSG"] = "ï¿½Escaneo completado!"
L["BANK_NOT_OPEN_MSG"] = "El banco no estï¿½ abierto"
L["OPTIONS_MENU"] = "Opciones"
L["HIDE_MINIMAP_BUTTON"] = "Ocultar Botï¿½n del Minimapa"
L["MENU_UNAVAILABLE_MSG"] = "Menï¿½ de clic derecho no disponible"
L["USE_COMMANDS_MSG"] = "Usa /wn show, /wn options, /wn help"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "Mï¿½x"
L["OPEN_AND_GUIDE"] = "Abrir y Guiar"
L["FROM_LABEL"] = "De:"
L["AVAILABLE_LABEL"] = "Disponible:"
L["ONLINE_LABEL"] = "(En lï¿½nea)"
L["DATA_SOURCE_TITLE"] = "Informaciï¿½n de Fuente de Datos"
L["DATA_SOURCE_USING"] = "Esta pestaï¿½a estï¿½ usando:"
L["DATA_SOURCE_MODERN"] = "Servicio de cachï¿½ moderno (basado en eventos)"
L["DATA_SOURCE_LEGACY"] = "Acceso directo a BD heredado"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Necesita migraciï¿½n al servicio de cachï¿½"
L["GLOBAL_DB_VERSION"] = "Versiï¿½n de BD Global:"

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "Personajes"
L["INFO_TAB_ITEMS"] = "Objetos"
L["INFO_TAB_STORAGE"] = "Almacenamiento"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "Reputaciones"
L["INFO_TAB_CURRENCY"] = "Monedas"
L["INFO_TAB_PLANS"] = "Planes"
L["INFO_TAB_STATISTICS"] = "Estadï¿½sticas"
L["SPECIAL_THANKS"] = "Agradecimientos Especiales"
L["SUPPORTERS_TITLE"] = "Patrocinadores"
L["THANK_YOU_MSG"] = "ï¿½Gracias por usar Warband Nexus!"

-- =============================================
-- Changelog (What's New) - v2.1.4
-- =============================================
L["CHANGELOG_V214"] = "NUEVAS CARACTERÍSTICAS:\n- Meta de Oro: Sistema inteligente de gestión automática de oro\n  • Establecer cantidad meta de oro por personaje (predeterminado: 10 oro)\n  • Tres modos: Solo Depositar, Solo Retirar o Ambos\n  • Depósitos Y retiros completamente automáticos al abrir el banco\n  • Usa C_Bank API (DepositMoney/WithdrawMoney)\n  • Retraso inteligente de 2 segundos entre operaciones\n  • Operación silenciosa (sin spam)\n  • Integrado en el encabezado de la pestaña Objetos\n  • Widget de botón de radio personalizado con tema\n  • 11 traducciones de idiomas incluidas\n\nMEJORAS:\n- UI: Widget de botón de radio personalizado agregado a SharedWidgets\n- UI: Botones de tamaño automático basados en ancho de texto localizado\n- Rendimiento: Registro de depuración eliminado para operación más limpia\n\n¡Gracias por tu continuo apoyo!\n\nPara reportar problemas o compartir comentarios, deja un comentario en CurseForge - Warband Nexus."

-- =============================================
-- Changelog (What's New) - v2.1.2
-- =============================================
L["CHANGELOG_V213"] =     "CAMBIOS:\n- Se agreg? un sistema de clasificaci?n.\n- Se arreglaron varios errores de interfaz (UI).\n- Se agreg? un bot?n para alternar el Compa?ero de Recetas de Profesiones y su ventana se movi? a la izquierda.\n- Se corrigieron los problemas de seguimiento de la Concentraci?n de Profesi?n.\n- Se arregl? un problema donde el contador de intentos mostraba por error '1 attempts' justo despu?s de encontrar un coleccionable en tu bot?n.\n- Se redujo considerablemente el tartamudeo de la interfaz y las ca?das de FPS al despojar objetos o abrir contenedores optimizando el rastreo en segundo plano.\n- Se corrigi? un error por el cual las bajas de jefes no se sumaban correctamente a los intentos de ciertas monturas (por ejemplo, Mecatraje de la B?veda de Piedra).\n- Se corrigi? que los Contenedores desbordantes no contaran correctamente las monedas ni otros objetos obtenidos.\n\nGracias por tu continuo apoyo!\n\nPara reportar problemas o compartir tus comentarios, deja un mensaje en CurseForge - Warband Nexus."

L["CHANGELOG_V212"] =     "CAMBIOS:\n- Se agreg? un sistema de clasificaci?n.\n- Se arreglaron varios errores de interfaz (UI).\n- Se agreg? un bot?n para alternar el Compa?ero de Recetas de Profesiones y su ventana se movi? a la izquierda.\n- Se corrigieron los problemas de seguimiento de la Concentraci?n de Profesi?n.\n- Se arregl? un problema donde el contador de intentos mostraba por error '1 attempts' justo despu?s de encontrar un coleccionable en tu bot?n.\n- Se redujo considerablemente el tartamudeo de la interfaz y las ca?das de FPS al despojar objetos o abrir contenedores optimizando el rastreo en segundo plano.\n- Se corrigi? un error por el cual las bajas de jefes no se sumaban correctamente a los intentos de ciertas monturas (por ejemplo, Mecatraje de la B?veda de Piedra).\n- Se corrigi? que los Contenedores desbordantes no contaran correctamente las monedas ni otros objetos obtenidos.\n\nGracias por tu continuo apoyo!\n\nPara reportar problemas o compartir tus comentarios, deja un mensaje en CurseForge - Warband Nexus."
-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "Confirmar Acciï¿½n"
L["CONFIRM"] = "Confirmar"
L["ENABLE_TRACKING_FORMAT"] = "ï¿½Activar rastreo para |cffffcc00%s|r?"
L["DISABLE_TRACKING_FORMAT"] = "ï¿½Desactivar rastreo para |cffffcc00%s|r?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "Reputaciones de Toda la Cuenta (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Reputaciones Basadas en Personaje (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "Recompensa Esperando"
L["REP_PARAGON_LABEL"] = "Paragï¿½n"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "Preparando..."
L["REP_LOADING_INITIALIZING"] = "Inicializando..."
L["REP_LOADING_FETCHING"] = "Obteniendo datos de reputaciï¿½n..."
L["REP_LOADING_PROCESSING"] = "Procesando %d facciones..."
L["REP_LOADING_PROCESSING_COUNT"] = "Procesando... (%d/%d)"
L["REP_LOADING_SAVING"] = "Guardando en base de datos..."
L["REP_LOADING_COMPLETE"] = "ï¿½Completado!"

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "No se puede abrir la ventana durante el combate. Por favor intenta de nuevo despuï¿½s de que termine el combate."
L["BANK_IS_ACTIVE"] = "El banco estï¿½ activo"
L["ITEMS_CACHED_FORMAT"] = "%d objetos en cachï¿½"
-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "PERSONAJE"
L["TABLE_HEADER_LEVEL"] = "NIVEL"
L["TABLE_HEADER_GOLD"] = "ORO"
L["TABLE_HEADER_LAST_SEEN"] = "VISTO POR ï¿½LTIMA VEZ"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "Ningï¿½n objeto coincide con '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "Ningï¿½n objeto coincide con tu bï¿½squeda"
L["ITEMS_SCAN_HINT"] = "Los objetos se escanean automï¿½ticamente. Intenta /reload si no aparece nada."
L["ITEMS_WARBAND_BANK_HINT"] = "Abre el Banco de Banda de Guerra para escanear objetos (escaneado automï¿½ticamente en la primera visita)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Prï¿½ximos pasos:"
L["CURRENCY_TRANSFER_STEP_1"] = "Encuentra |cffffffff%s|r en la ventana de monedas"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800Clic derecho|r en ï¿½l"
L["CURRENCY_TRANSFER_STEP_3"] = "Selecciona |cffffffff'Transferir a Banda de Guerra'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Elige |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Ingresa cantidad: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "ï¿½La ventana de monedas estï¿½ ahora abierta!"
L["CURRENCY_TRANSFER_SECURITY"] = "(La seguridad de Blizzard previene la transferencia automï¿½tica)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "Zona: "
L["ADDED"] = "Aï¿½adido"
L["WEEKLY_VAULT_TRACKER"] = "Rastreador de Bï¿½veda Semanal"
L["DAILY_QUEST_TRACKER"] = "Rastreador de Misiones Diarias"
L["CUSTOM_PLAN_STATUS"] = "Plan personalizado '%s' %s"

-- =============================================
-- Achievement Popup
-- =============================================
L["ACHIEVEMENT_COMPLETED"] = "Completado"
L["ACHIEVEMENT_NOT_COMPLETED"] = "No completado"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d pts"
L["ADD_PLAN"] = "Aï¿½adir"
L["PLANNED"] = "Planeado"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = "Mazmorra"
L["VAULT_SLOT_RAIDS"] = "Bandas"
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
L["WEEKLY_VAULT_PLAN_NAME"] = "Bï¿½veda Semanal - %s"
L["VAULT_PLANS_RESET"] = "ï¿½Los planes de Gran Bï¿½veda semanal han sido reiniciados! (%d plan%s)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "No se encontraron personajes"
L["EMPTY_CHARACTERS_DESC"] = "Inicia sesiï¿½n con tus personajes para empezar a rastrearlos.\nLos datos se recopilan automï¿½ticamente en cada inicio de sesiï¿½n."
L["EMPTY_ITEMS_TITLE"] = "No hay objetos en cachï¿½"
L["EMPTY_ITEMS_DESC"] = "Abre tu banco de banda de guerra o banco personal para escanear objetos.\nLos objetos se almacenan automï¿½ticamente en la primera visita."
L["EMPTY_STORAGE_TITLE"] = "Sin datos de almacenamiento"
L["EMPTY_STORAGE_DESC"] = "Los objetos se escanean al abrir bancos o bolsas.\nVisita un banco para empezar a rastrear tu almacenamiento."
L["EMPTY_PLANS_TITLE"] = "Sin planes aï¿½n"
L["EMPTY_PLANS_DESC"] = "Explora monturas, mascotas, juguetes o logros arriba\npara aï¿½adir objetivos de colecciï¿½n y seguir tu progreso."
L["EMPTY_REPUTATION_TITLE"] = "Sin datos de reputaciï¿½n"
L["EMPTY_REPUTATION_DESC"] = "Las reputaciones se escanean automï¿½ticamente al iniciar sesiï¿½n.\nInicia sesiï¿½n con un personaje para rastrear facciones."
L["EMPTY_CURRENCY_TITLE"] = "Sin datos de moneda"
L["EMPTY_CURRENCY_DESC"] = "Las monedas se rastrean automï¿½ticamente en todos tus personajes.\nInicia sesiï¿½n con un personaje para rastrear monedas."
L["EMPTY_PVE_TITLE"] = "Sin datos de PvE"
L["EMPTY_PVE_DESC"] = "El progreso PvE se rastrea al iniciar sesiï¿½n con tus personajes.\nGran Bï¿½veda, Mï¿½tica+ y bloqueos de banda aparecerï¿½n aquï¿½."
L["EMPTY_STATISTICS_TITLE"] = "Sin estadï¿½sticas disponibles"
L["EMPTY_STATISTICS_DESC"] = "Las estadï¿½sticas provienen de tus personajes rastreados.\nInicia sesiï¿½n con un personaje para recopilar datos."
L["NO_ADDITIONAL_INFO"] = "Sin informaciï¿½n adicional"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "ï¿½Quieres rastrear este personaje?"
L["CLEANUP_NO_INACTIVE"] = "No se encontraron personajes inactivos (90+ dï¿½as)"
L["CLEANUP_REMOVED_FORMAT"] = "Se eliminaron %d personaje(s) inactivo(s)"
L["TRACKING_ENABLED_MSG"] = "ï¿½Rastreo de personaje ACTIVADO!"
L["TRACKING_DISABLED_MSG"] = "ï¿½Rastreo de personaje DESACTIVADO!"
L["TRACKING_ENABLED"] = "Rastreo ACTIVADO"
L["TRACKING_DISABLED"] = "Rastreo DESACTIVADO (modo solo lectura)"
L["STATUS_LABEL"] = "Estado:"
L["ERROR_LABEL"] = "Error:"
L["ERROR_NAME_REALM_REQUIRED"] = "Se requiere nombre de personaje y reino"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s ya tiene un plan semanal activo"

-- Profiles (AceDB)
L["PROFILES"] = "Perfiles"
L["PROFILES_DESC"] = "Gestionar perfiles del addon"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "No se encontraron criterios"
L["NO_REQUIREMENTS_INSTANT"] = "Sin requisitos (completado instantï¿½neo)"

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
L["NO_PROFESSIONS_DATA"] = "No hay datos de profesiones disponibles aï¿½n. Abre la ventana de profesiï¿½n (predeterminado: K) en cada personaje para recopilar datos."
L["CONCENTRATION"] = "Concentraciï¿½n"
L["KNOWLEDGE"] = "Conocimiento"
L["SKILL"] = "Habilidad"
L["RECIPES"] = "Recetas"
L["UNSPENT_POINTS"] = "Puntos sin gastar"
L["COLLECTIBLE"] = "Coleccionable"
L["RECHARGE"] = "Recarga"
L["FULL"] = "Completo"
L["PROF_OPEN_RECIPE"] = "Abrir"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "Abrir la lista de recetas de esta profesiï¿½n"
L["PROF_ONLY_CURRENT_CHAR"] = "Solo disponible para el personaje actual"
L["NO_PROFESSION"] = "Sin profesiï¿½n"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "1.ï¿½ fabricaciï¿½n"
L["SKILL_UPS"] = "Subidas de habilidad"
L["COOLDOWNS"] = "Tiempos de espera"
L["ORDERS"] = "Pedidos"

-- Professions: Tooltips & Details
L["LEARNED_RECIPES"] = "Recetas aprendidas"
L["UNLEARNED_RECIPES"] = "Recetas sin aprender"
L["LAST_SCANNED"] = "ï¿½ltimo escaneo"
L["JUST_NOW"] = "Justo ahora"
L["RECIPE_NO_DATA"] = "Abre la ventana de profesiï¿½n para recopilar datos de recetas"
L["FIRST_CRAFT_AVAILABLE"] = "Primeras fabricaciones disponibles"
L["FIRST_CRAFT_DESC"] = "Recetas que otorgan XP bonus en la primera fabricaciï¿½n"
L["SKILLUP_RECIPES"] = "Recetas de subida"
L["SKILLUP_DESC"] = "Recetas que aï¿½n pueden aumentar tu nivel de habilidad"
L["NO_ACTIVE_COOLDOWNS"] = "Sin tiempos de espera activos"

-- Professions: Crafting Orders
L["CRAFTING_ORDERS"] = "Pedidos de fabricaciï¿½n"
L["PERSONAL_ORDERS"] = "Pedidos personales"
L["PUBLIC_ORDERS"] = "Pedidos pï¿½blicos"
L["CLAIMS_REMAINING"] = "Reclamaciones restantes"
L["NO_ACTIVE_ORDERS"] = "Sin pedidos activos"
L["ORDER_NO_DATA"] = "Abre la profesiï¿½n en la mesa de fabricaciï¿½n para escanear"

-- Professions: Equipment
L["EQUIPMENT"] = "Equipamiento"
L["TOOL"] = "Herramienta"
L["ACCESSORY"] = "Accesorio"

-- =============================================
-- New keys (v2.1.0)
-- =============================================
L["TOOLTIP_ATTEMPTS"] = "intentos"
L["TOOLTIP_100_DROP"] = "100% Botï¿½n"
L["TOOLTIP_UNKNOWN"] = "Desconocido"
L["TOOLTIP_WARBAND_BANK"] = "Banco de banda de guerra"
L["TOOLTIP_HOLD_SHIFT"] = "  Mantï¿½n [Mayï¿½s] para listado completo"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - Concentraciï¿½n"
L["TOOLTIP_FULL"] = "(Completo)"
L["NO_ITEMS_CACHED_TITLE"] = "Sin objetos en cachï¿½"
L["COMBAT_CURRENCY_ERROR"] = "No se puede abrir la ventana de monedas durante el combate. Intï¿½ntalo de nuevo despuï¿½s del combate."
L["DB_LABEL"] = "BD:"
L["COLLECTING_PVE"] = "Recopilando datos JcE"
L["PVE_PREPARING"] = "Preparando"
L["PVE_GREAT_VAULT"] = "Gran Cï¿½mara"
L["PVE_MYTHIC_SCORES"] = "Puntuaciones Mï¿½tica+"
L["PVE_RAID_LOCKOUTS"] = "Bloqueos de banda"
L["PVE_INCOMPLETE_DATA"] = "Algunos datos pueden estar incompletos. Intenta actualizar mï¿½s tarde."
L["VAULT_SLOTS_TO_FILL"] = "%d espacio%s de Gran Cï¿½mara por completar"
L["VAULT_SLOT_PLURAL"] = "s"
L["REP_RENOWN_NEXT"] = "Renombre %d"
L["REP_TO_NEXT_FORMAT"] = "%s rep para %s (%s)"
L["REP_FACTION_FALLBACK"] = "Facciï¿½n"
L["COLLECTION_CANCELLED"] = "Recopilaciï¿½n cancelada por el usuario"
L["CLEANUP_STALE_FORMAT"] = "Se eliminaron %d personaje(s) obsoleto(s)"
L["PERSONAL_BANK"] = "Banco personal"
L["WARBAND_BANK_LABEL"] = "Banco de banda de guerra"
L["WARBAND_BANK_TAB_FORMAT"] = "Pestaï¿½a %d"
L["CURRENCY_OTHER"] = "Otros"
L["ERROR_SAVING_CHARACTER"] = "Error al guardar personaje:"
L["STANDING_HATED"] = "Odiado"
L["STANDING_HOSTILE"] = "Hostil"
L["STANDING_UNFRIENDLY"] = "Antipï¿½tico"
L["STANDING_NEUTRAL"] = "Neutral"
L["STANDING_FRIENDLY"] = "Amistoso"
L["STANDING_HONORED"] = "Honorable"
L["STANDING_REVERED"] = "Reverenciado"
L["STANDING_EXALTED"] = "Exaltado"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d intentos para %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "ï¿½Obtenido %s! Contador de intentos reiniciado."
L["TRYCOUNTER_CAUGHT_RESET"] = "ï¿½Capturado %s! Contador de intentos reiniciado."
L["TRYCOUNTER_CONTAINER_RESET"] = "ï¿½Obtenido %s del contenedor! Contador de intentos reiniciado."
L["TRYCOUNTER_LOCKOUT_SKIP"] = "Omitido: bloqueo diario/semanal activo para este NPC."
L["TRYCOUNTER_INSTANCE_DROPS"] = "Botï¿½n coleccionable en esta instancia:"
L["TRYCOUNTER_COLLECTED_TAG"] = "(Recolectado)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " intentos"
L["TRYCOUNTER_TYPE_MOUNT"] = "Montura"
L["TRYCOUNTER_TYPE_PET"] = "Mascota"
L["TRYCOUNTER_TYPE_TOY"] = "Juguete"
L["TRYCOUNTER_TYPE_ITEM"] = "Objeto"
L["TRYCOUNTER_TRY_COUNTS"] = "Contador de intentos"
L["LT_CHARACTER_DATA"] = "Datos de personaje"
L["LT_CURRENCY_CACHES"] = "Monedas y cachï¿½s"
L["LT_REPUTATIONS"] = "Reputaciones"
L["LT_PROFESSIONS"] = "Profesiones"
L["LT_PVE_DATA"] = "Datos JcE"
L["LT_COLLECTIONS"] = "Colecciones"
L["CONFIG_HEADER"] = "Warband Nexus"
L["CONFIG_HEADER_DESC"] = "Gestiï¿½n moderna de banda de guerra y rastreo entre personajes."
L["CONFIG_GENERAL"] = "Configuraciï¿½n general"
L["CONFIG_GENERAL_DESC"] = "Opciones bï¿½sicas de configuraciï¿½n y comportamiento del addon."
L["CONFIG_ENABLE"] = "Activar addon"
L["CONFIG_ENABLE_DESC"] = "Activar o desactivar el addon."
L["CONFIG_MINIMAP"] = "Botï¿½n del minimapa"
L["CONFIG_MINIMAP_DESC"] = "Mostrar un botï¿½n en el minimapa para acceso rï¿½pido."
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "Mostrar objetos en descripciones"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "Mostrar cantidades de objetos de banda de guerra y personaje en las descripciones de objetos."
L["CONFIG_MODULES"] = "Gestiï¿½n de mï¿½dulos"
L["CONFIG_MODULES_DESC"] = "Activar o desactivar mï¿½dulos individuales del addon. Los mï¿½dulos desactivados no recopilarï¿½n datos ni mostrarï¿½n pestaï¿½as."
L["CONFIG_MOD_CURRENCIES"] = "Monedas"
L["CONFIG_MOD_CURRENCIES_DESC"] = "Rastrear monedas en todos los personajes."
L["CONFIG_MOD_REPUTATIONS"] = "Reputaciones"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "Rastrear reputaciones en todos los personajes."
L["CONFIG_MOD_ITEMS"] = "Objetos"
L["CONFIG_MOD_ITEMS_DESC"] = "Rastrear objetos en bolsas y bancos."
L["CONFIG_MOD_STORAGE"] = "Almacenamiento"
L["CONFIG_MOD_STORAGE_DESC"] = "Pestaï¿½a de almacenamiento para inventario y gestiï¿½n del banco."
L["CONFIG_MOD_PVE"] = "JcE"
L["CONFIG_MOD_PVE_DESC"] = "Rastrear Gran Cï¿½mara, Mï¿½tica+ y bloqueos de banda."
L["CONFIG_MOD_PLANS"] = "Planes"
L["CONFIG_MOD_PLANS_DESC"] = "Rastreo de planes de colecciï¿½n y objetivos de completado."
L["CONFIG_MOD_PROFESSIONS"] = "Profesiones"
L["CONFIG_MOD_PROFESSIONS_DESC"] = "Rastrear habilidades de profesiï¿½n, recetas y concentraciï¿½n."
L["CONFIG_AUTOMATION"] = "Automatizaciï¿½n"
L["CONFIG_AUTOMATION_DESC"] = "Controlar quï¿½ ocurre automï¿½ticamente al abrir el banco de banda de guerra."
L["CONFIG_AUTO_OPTIMIZE"] = "Optimizar base de datos automï¿½ticamente"
L["CONFIG_AUTO_OPTIMIZE_DESC"] = "Optimizar automï¿½ticamente la base de datos al iniciar sesiï¿½n para mantener el almacenamiento eficiente."
L["CONFIG_SHOW_ITEM_COUNT"] = "Mostrar cantidad de objetos"
L["CONFIG_SHOW_ITEM_COUNT_DESC"] = "Mostrar descripciones con cantidad de objetos por personaje."
L["CONFIG_THEME_COLOR"] = "Color principal del tema"
L["CONFIG_THEME_COLOR_DESC"] = "Elegir el color de acento principal para la interfaz del addon."
L["CONFIG_THEME_PRESETS"] = "Temas predefinidos"
L["CONFIG_THEME_APPLIED"] = "ï¿½Tema %s aplicado!"
L["CONFIG_THEME_RESET_DESC"] = "Restablecer todos los colores del tema al morado predeterminado."
L["CONFIG_NOTIFICATIONS"] = "Notificaciones"
L["CONFIG_NOTIFICATIONS_DESC"] = "Configurar quï¿½ notificaciones aparecen."
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
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "Mostrar la ventana de novedades en el prï¿½ximo inicio de sesiï¿½n."
L["CONFIG_UPDATE_NOTES_SHOWN"] = "La notificaciï¿½n de actualizaciï¿½n se mostrarï¿½ en el prï¿½ximo inicio de sesiï¿½n."
L["CONFIG_RESET_PLANS"] = "Reiniciar planes completados"
L["CONFIG_RESET_PLANS_CONFIRM"] = "Esto eliminarï¿½ todos los planes completados. ï¿½Continuar?"
L["CONFIG_RESET_PLANS_FORMAT"] = "Se eliminaron %d plan(es) completado(s)."
L["CONFIG_NO_COMPLETED_PLANS"] = "No hay planes completados para eliminar."
L["CONFIG_TAB_FILTERING"] = "Filtrado de pestaï¿½as"
L["CONFIG_TAB_FILTERING_DESC"] = "Elegir quï¿½ pestaï¿½as son visibles en la ventana principal."
L["CONFIG_CHARACTER_MGMT"] = "Gestiï¿½n de personajes"
L["CONFIG_CHARACTER_MGMT_DESC"] = "Gestionar personajes rastreados y eliminar datos antiguos."
L["CONFIG_DELETE_CHAR"] = "Eliminar datos de personaje"
L["CONFIG_DELETE_CHAR_DESC"] = "Eliminar permanentemente todos los datos almacenados del personaje seleccionado."
L["CONFIG_DELETE_CONFIRM"] = "ï¿½Estï¿½s seguro de que quieres eliminar permanentemente todos los datos de este personaje? Esta acciï¿½n no se puede deshacer."
L["CONFIG_DELETE_SUCCESS"] = "Datos de personaje eliminados:"
L["CONFIG_DELETE_FAILED"] = "No se encontraron datos del personaje."
L["CONFIG_FONT_SCALING"] = "Fuente y escala"
L["CONFIG_FONT_SCALING_DESC"] = "Ajustar familia de fuente y escala de tamaï¿½o."
L["CONFIG_FONT_FAMILY"] = "Familia de fuente"
L["CONFIG_FONT_SIZE"] = "Escala de tamaï¿½o de fuente"
L["CONFIG_FONT_PREVIEW"] = "Vista previa: El veloz murciï¿½lago hindï¿½ comï¿½a feliz cardillo y kiwi"
L["CONFIG_ADVANCED"] = "Avanzado"
L["CONFIG_ADVANCED_DESC"] = "Configuraciï¿½n avanzada y gestiï¿½n de base de datos. ï¿½Usar con precauciï¿½n!"
L["CONFIG_DEBUG_MODE"] = "Modo de depuraciï¿½n"
L["CONFIG_DEBUG_MODE_DESC"] = "Activar registro detallado para depuraciï¿½n. Activar solo si hay problemas."
L["CONFIG_DB_STATS"] = "Mostrar estadï¿½sticas de base de datos"
L["CONFIG_DB_STATS_DESC"] = "Mostrar tamaï¿½o actual de la base de datos y estadï¿½sticas de optimizaciï¿½n."
L["CONFIG_DB_OPTIMIZER_NA"] = "Optimizador de base de datos no cargado"
L["CONFIG_OPTIMIZE_NOW"] = "Optimizar base de datos ahora"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "Ejecutar el optimizador de base de datos para limpiar y comprimir los datos almacenados."
L["CONFIG_COMMANDS_HEADER"] = "Comandos de barra"
L["DISPLAY_SETTINGS"] = "Configuraciï¿½n de pantalla"
L["DISPLAY_SETTINGS_DESC"] = "Personalizar cï¿½mo se muestran objetos e informaciï¿½n."
L["RESET_DEFAULT"] = "Restablecer predeterminado"
L["ANTI_ALIASING"] = "Suavizado"
L["PROFESSIONS_INFO_DESC"] = "Rastrea habilidades de profesiï¿½n, concentraciï¿½n, conocimiento y ï¿½rboles de especializaciï¿½n en todos los personajes. Incluye Recipe Companion para fuentes de reactivos."
L["CONTRIBUTORS_TITLE"] = "Colaboradores"
L["ANTI_ALIASING_DESC"] = "Estilo de renderizado de bordes de fuente (afecta la legibilidad)"

-- =============================================
-- Recipe Companion
-- =============================================
L["RECIPE_COMPANION_TITLE"] = "Compaï¿½ero de Recetas"
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
L["GOLD_MANAGER_BTN"] = "Meta de Oro"
L["GOLD_MANAGEMENT_TITLE"] = "Meta de Oro"
L["GOLD_MANAGEMENT_DESC"] = "Configura la gestiï¿½n automï¿½tica de oro. Tanto los depï¿½sitos como los retiros se realizan automï¿½ticamente cuando el banco estï¿½ abierto usando la API C_Bank."
L["GOLD_MANAGEMENT_WARNING"] = "|cff44ff44Totalmente Automï¿½tico:|r Tanto los depï¿½sitos como los retiros de oro se realizan automï¿½ticamente cuando el banco estï¿½ abierto. ï¿½Establece tu cantidad objetivo y deja que el addon gestione tu oro!"
L["GOLD_MANAGEMENT_ENABLE"] = "Activar Gestiï¿½n de Oro"
L["GOLD_MANAGEMENT_MODE"] = "Modo de Gestiï¿½n"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "Solo Depositar"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "Si tienes mï¿½s de X oro, el exceso se depositarï¿½ automï¿½ticamente en el banco de banda de guerra."
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "Solo Retirar"
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "Si tienes menos de X oro, la diferencia se retirarï¿½ automï¿½ticamente del banco de banda de guerra."
L["GOLD_MANAGEMENT_MODE_BOTH"] = "Ambos"
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "Mantener automï¿½ticamente exactamente X oro en tu personaje (depositar si sobra, retirar si falta)."
L["GOLD_MANAGEMENT_TARGET"] = "Cantidad de Oro Objetivo"
L["GOLD_MANAGEMENT_GOLD_LABEL"] = "oro"
L["GOLD_MANAGEMENT_HELPER"] = "Ingresa la cantidad de oro que deseas mantener en este personaje. El addon gestionarï¿½ automï¿½ticamente tu oro cuando abras el banco."
L["GOLD_MANAGEMENT_NOTIFICATION_DEPOSIT"] = "Depositar %s en el banco de banda de guerra (tienes %s)"
L["GOLD_MANAGEMENT_NOTIFICATION_WITHDRAW"] = "Retirar %s del banco de banda de guerra (tienes %s)"
L["GOLD_MANAGEMENT_DEPOSITED"] = "Depositado %s en el banco de banda de guerra"
L["GOLD_MANAGEMENT_WITHDRAWN"] = "Retirado %s del banco de banda de guerra"
