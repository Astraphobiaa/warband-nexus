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
L["VERSION"] = GAME_VERSION_LABEL or "Versión"

-- Slash Commands
L["SLASH_HELP"] = "Comandos disponibles:"
L["SLASH_OPTIONS"] = "Abrir panel de opciones"
L["SLASH_SCAN"] = "Escanear banco de banda de guerra"
L["SLASH_SHOW"] = "Mostrar/ocultar ventana principal"
L["SLASH_DEPOSIT"] = "Abrir cola de depósito"
L["SLASH_SEARCH"] = "Buscar un objeto"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Configuración general"
L["GENERAL_SETTINGS_DESC"] = "Configurar el comportamiento general del addon"
L["ENABLE_ADDON"] = "Activar addon"
L["ENABLE_ADDON_DESC"] = "Activar o desactivar la funcionalidad de Warband Nexus"
L["MINIMAP_ICON"] = "Mostrar icono del minimapa"
L["MINIMAP_ICON_DESC"] = "Mostrar u ocultar el botón del minimapa"
L["DEBUG_MODE"] = "Modo de depuración"
L["DEBUG_MODE_DESC"] = "Activar mensajes de depuración en el chat"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "Configuración de escaneo"
L["SCANNING_SETTINGS_DESC"] = "Configurar el comportamiento de escaneo del banco"
L["AUTO_SCAN"] = "Escaneo automático al abrir"
L["AUTO_SCAN_DESC"] = "Escanear automáticamente el banco al abrirlo"
L["SCAN_DELAY"] = "Retraso de escaneo"
L["SCAN_DELAY_DESC"] = "Retraso entre operaciones de escaneo (en segundos)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "Configuración de depósito"
L["DEPOSIT_SETTINGS_DESC"] = "Configurar el comportamiento de depósito de objetos"
L["GOLD_RESERVE"] = "Reserva de oro"
L["GOLD_RESERVE_DESC"] = "Oro mínimo a mantener en el inventario personal (en oro)"
L["AUTO_DEPOSIT_REAGENTS"] = "Depositar reactivos automáticamente"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "Poner reactivos en cola de depósito al abrir el banco"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Configuración de pantalla"
L["DISPLAY_SETTINGS_DESC"] = "Configurar la apariencia visual"
L["SHOW_ITEM_LEVEL"] = "Mostrar nivel de objeto"
L["SHOW_ITEM_LEVEL_DESC"] = "Mostrar nivel de objeto en equipamiento"
L["SHOW_ITEM_COUNT"] = "Mostrar cantidad de objetos"
L["SHOW_ITEM_COUNT_DESC"] = "Mostrar cantidades apiladas en objetos"
L["HIGHLIGHT_QUALITY"] = "Resaltar por calidad"
L["HIGHLIGHT_QUALITY_DESC"] = "Añadir bordes de color según la calidad del objeto"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "Configuración de pestañas"
L["TAB_SETTINGS_DESC"] = "Configurar el comportamiento de las pestañas del banco"
L["IGNORED_TABS"] = "Pestañas ignoradas"
L["IGNORED_TABS_DESC"] = "Seleccionar pestañas a excluir del escaneo y operaciones"
L["TAB_1"] = "Pestaña de banda 1"
L["TAB_2"] = "Pestaña de banda 2"
L["TAB_3"] = "Pestaña de banda 3"
L["TAB_4"] = "Pestaña de banda 4"
L["TAB_5"] = "Pestaña de banda 5"

-- Scanner Module
L["SCAN_STARTED"] = "Escaneando banco de banda de guerra..."
L["SCAN_COMPLETE"] = "Escaneo completado. Se encontraron %d objetos en %d espacios."
L["SCAN_FAILED"] = "Escaneo fallido: El banco de banda de guerra no está abierto."
L["SCAN_TAB"] = "Escaneando pestaña %d..."
L["CACHE_CLEARED"] = "Caché de objetos borrada."
L["CACHE_UPDATED"] = "Caché de objetos actualizada."

-- Banker Module
L["BANK_NOT_OPEN"] = "El banco de banda de guerra no está abierto."
L["DEPOSIT_STARTED"] = "Iniciando operación de depósito..."
L["DEPOSIT_COMPLETE"] = "Depósito completado. %d objetos transferidos."
L["DEPOSIT_CANCELLED"] = "Depósito cancelado."
L["DEPOSIT_QUEUE_EMPTY"] = "La cola de depósito está vacía."
L["DEPOSIT_QUEUE_CLEARED"] = "Cola de depósito vaciada."
L["ITEM_QUEUED"] = "%s en cola para depósito."
L["ITEM_REMOVED"] = "%s eliminado de la cola."
L["GOLD_DEPOSITED"] = "%s oro depositado en el banco de banda de guerra."
L["INSUFFICIENT_GOLD"] = "Oro insuficiente para el depósito."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "Cantidad no válida."
L["WITHDRAW_BANK_NOT_OPEN"] = "¡El banco debe estar abierto para retirar!"
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
L["BTN_DEPOSIT"] = "Cola de depósito"
L["BTN_SORT"] = "Ordenar banco"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "Vaciar cola"
L["BTN_DEPOSIT_ALL"] = "Depositar todo"
L["BTN_DEPOSIT_GOLD"] = "Depositar oro"
L["ENABLE"] = ENABLE or "Activar" -- Blizzard Global
L["ENABLE_MODULE"] = "Activar módulo"

-- Main Tabs
L["TAB_CHARACTERS"] = CHARACTER or "Personajes" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "Objetos" -- Blizzard Global
L["TAB_STORAGE"] = "Almacenamiento"
L["TAB_PLANS"] = "Planes"
L["TAB_REPUTATION"] = REPUTATION or "Reputación" -- Blizzard Global
L["TAB_REPUTATIONS"] = "Reputaciones"
L["TAB_CURRENCY"] = CURRENCY or "Moneda" -- Blizzard Global
L["TAB_CURRENCIES"] = "Monedas"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "Estadísticas" -- Blizzard Global

-- Item Categories (Blizzard Globals)
L["CATEGORY_ALL"] = ALL or "Todos los objetos" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipamiento"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumibles"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reactivos"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Mercancías"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Objetos de misión"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Miscelánea"

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
L["CHARACTER_LAST_SEEN_FORMAT"] = "Visto por última vez: %s"
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
L["GROUP_PROFESSION"] = "Profesión"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reactivos"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Mercancías"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Misión"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscelánea"
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
L["PLANS_COLLECTIONS"] = "Planes de colección"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "Añadir plan personalizado"
L["PLANS_NO_RESULTS"] = "No se encontraron resultados."
L["PLANS_ALL_COLLECTED"] = "¡Todos los objetos recolectados!"
L["PLANS_RECIPE_HELP"] = "Haz clic derecho en las recetas de tu inventario para añadirlas aquí."
L["COLLECTION_PLANS"] = "Planes de colección"
L["SEARCH_PLANS"] = "Buscar planes..."
L["COMPLETED_PLANS"] = "Planes completados"
L["SHOW_COMPLETED"] = "Mostrar completados"

-- Plans Categories (Blizzard Globals)
L["CATEGORY_MY_PLANS"] = "Mis Planes"
L["CATEGORY_DAILY_TASKS"] = "Tareas diarias"
L["CATEGORY_MOUNTS"] = MOUNTS or "Monturas" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "Mascotas" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "Juguetes" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transfiguración" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "Ilusiones"
L["CATEGORY_TITLES"] = TITLES or "Títulos"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Logros" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " reputación..."
L["REP_HEADER_WARBAND"] = "Reputación de banda de guerra"
L["REP_HEADER_CHARACTER"] = "Reputación del personaje"
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
L["STATS_HEADER"] = STATISTICS or "Estadísticas"
L["STATS_TOTAL_ITEMS"] = "Objetos totales"
L["STATS_TOTAL_SLOTS"] = "Espacios totales"
L["STATS_FREE_SLOTS"] = "Espacios libres"
L["STATS_USED_SLOTS"] = "Espacios usados"
L["STATS_TOTAL_VALUE"] = "Valor total"
L["COLLECTED"] = "Recolectado"
L["TOTAL"] = "Total"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Personaje" -- Blizzard Global
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Ubicación" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "Banco de banda de guerra"
L["TOOLTIP_TAB"] = "Pestaña"
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
L["DOUBLECLICK_RESET"] = "Doble clic para restablecer la posición"

-- Error Messages
L["ERROR_GENERIC"] = "Se ha producido un error."
L["ERROR_API_UNAVAILABLE"] = "La API requerida no está disponible."
L["ERROR_BANK_CLOSED"] = "No se puede realizar la operación: banco cerrado."
L["ERROR_INVALID_ITEM"] = "Objeto especificado no válido."
L["ERROR_PROTECTED_FUNCTION"] = "No se puede llamar a una función protegida en combate."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "¿Depositar %d objetos en el banco de banda de guerra?"
L["CONFIRM_CLEAR_QUEUE"] = "¿Vaciar todos los objetos de la cola de depósito?"
L["CONFIRM_DEPOSIT_GOLD"] = "¿Depositar %s oro en el banco de banda de guerra?"

-- Update Notification
L["WHATS_NEW"] = "Novedades"
L["GOT_IT"] = "¡Entendido!"

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
L["WEEKLY_VAULT"] = "Bóveda Semanal"
L["CUSTOM"] = "Personalizado"
L["NO_PLANS_IN_CATEGORY"] = "No hay planes en esta categoría.\nAñade planes desde la pestaña Planes."
L["SOURCE_LABEL"] = "Fuente:"
L["ZONE_LABEL"] = "Zona:"
L["VENDOR_LABEL"] = "Vendedor:"
L["DROP_LABEL"] = "Botín:"
L["REQUIREMENT_LABEL"] = "Requisito:"
L["RIGHT_CLICK_REMOVE"] = "Clic derecho para eliminar"
L["TRACKED"] = "Rastreado"
L["TRACK"] = "Rastrear"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Rastrear en objetivos de Blizzard (máx. 10)"
L["UNKNOWN"] = "Desconocido"
L["NO_REQUIREMENTS"] = "Sin requisitos (completado instantáneo)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "Sin actividad planificada"
L["CLICK_TO_ADD_GOALS"] = "¡Haz clic en Monturas, Mascotas o Juguetes arriba para añadir objetivos!"
L["UNKNOWN_QUEST"] = "Misión desconocida"
L["ALL_QUESTS_COMPLETE"] = "¡Todas las misiones completadas!"
L["CURRENT_PROGRESS"] = "Progreso actual"
L["SELECT_CONTENT"] = "Seleccionar contenido:"
L["QUEST_TYPES"] = "Tipos de misión:"
L["WORK_IN_PROGRESS"] = "En desarrollo"
L["RECIPE_BROWSER"] = "Explorador de recetas"
L["NO_RESULTS_FOUND"] = "No se encontraron resultados."
L["TRY_ADJUSTING_SEARCH"] = "Intenta ajustar tu búsqueda o filtros."
L["NO_COLLECTED_YET"] = "Ningún %s recolectado aún"
L["START_COLLECTING"] = "¡Empieza a recolectar para verlos aquí!"
L["ALL_COLLECTED_CATEGORY"] = "¡Todos los %ss recolectados!"
L["COLLECTED_EVERYTHING"] = "¡Has recolectado todo en esta categoría!"
L["PROGRESS_LABEL"] = "Progreso:"
L["REQUIREMENTS_LABEL"] = "Requisitos:"
L["INFORMATION_LABEL"] = "Información:"
L["DESCRIPTION_LABEL"] = "Descripción:"
L["REWARD_LABEL"] = "Recompensa:"
L["DETAILS_LABEL"] = "Detalles:"
L["COST_LABEL"] = "Coste:"
L["LOCATION_LABEL"] = "Ubicación:"
L["TITLE_LABEL"] = "Título:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "¡Ya has completado todos los logros de esta categoría!"
L["DAILY_PLAN_EXISTS"] = "El plan diario ya existe"
L["WEEKLY_PLAN_EXISTS"] = "El plan semanal ya existe"

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "Tus personajes"
L["CHARACTERS_TRACKED_FORMAT"] = "%d personajes rastreados"
L["NO_CHARACTER_DATA"] = "No hay datos de personajes disponibles"
L["NO_FAVORITES"] = "Aún no hay personajes favoritos. Haz clic en el icono de estrella para marcar un personaje como favorito."
L["ALL_FAVORITED"] = "¡Todos los personajes están marcados como favoritos!"
L["UNTRACKED_CHARACTERS"] = "Personajes no rastreados"
L["ILVL_SHORT"] = "iLvl"
L["ONLINE"] = "En línea"
L["TIME_LESS_THAN_MINUTE"] = "< 1m atrás"
L["TIME_MINUTES_FORMAT"] = "%dm atrás"
L["TIME_HOURS_FORMAT"] = "%dh atrás"
L["TIME_DAYS_FORMAT"] = "%dd atrás"
L["REMOVE_FROM_FAVORITES"] = "Quitar de favoritos"
L["ADD_TO_FAVORITES"] = "Añadir a favoritos"
L["FAVORITES_TOOLTIP"] = "Los personajes favoritos aparecen en la parte superior de la lista"
L["CLICK_TO_TOGGLE"] = "Clic para alternar"
L["UNKNOWN_PROFESSION"] = "Profesión desconocida"
L["SKILL_LABEL"] = "Habilidad:"
L["OVERALL_SKILL"] = "Habilidad total:"
L["BONUS_SKILL"] = "Habilidad de bonificación:"
L["KNOWLEDGE_LABEL"] = "Conocimiento:"
L["SPEC_LABEL"] = "Espec."
L["POINTS_SHORT"] = "pts"
L["RECIPES_KNOWN"] = "Recetas conocidas:"
L["OPEN_PROFESSION_HINT"] = "Abrir ventana de profesión"
L["FOR_DETAILED_INFO"] = "para información detallada"
L["CHARACTER_IS_TRACKED"] = "Este personaje está siendo rastreado."
L["TRACKING_ACTIVE_DESC"] = "La recopilación de datos y las actualizaciones están activas."
L["CLICK_DISABLE_TRACKING"] = "Haz clic para desactivar el rastreo."
L["MUST_LOGIN_TO_CHANGE"] = "Debes iniciar sesión con este personaje para cambiar el rastreo."
L["TRACKING_ENABLED"] = "Rastreo activado"
L["CLICK_ENABLE_TRACKING"] = "Haz clic para activar el rastreo para este personaje."
L["TRACKING_WILL_BEGIN"] = "La recopilación de datos comenzará de inmediato."
L["CHARACTER_NOT_TRACKED"] = "Este personaje no está siendo rastreado."
L["MUST_LOGIN_TO_ENABLE"] = "Debes iniciar sesión con este personaje para activar el rastreo."
L["ENABLE_TRACKING"] = "Activar rastreo"
L["DELETE_CHARACTER_TITLE"] = "¿Eliminar personaje?"
L["THIS_CHARACTER"] = "este personaje"
L["DELETE_CHARACTER"] = "Eliminar personaje"
L["REMOVE_FROM_TRACKING_FORMAT"] = "Quitar %s del rastreo"
L["CLICK_TO_DELETE"] = "Haz clic para eliminar"
L["CONFIRM_DELETE"] = "¿Estás seguro de que quieres eliminar a |cff00ccff%s|r?"
L["CANNOT_UNDO"] = "¡Esta acción no se puede deshacer!"
L["DELETE"] = DELETE or "Eliminar"
L["CANCEL"] = CANCEL or "Cancelar"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "Objetos personales"
L["ITEMS_SUBTITLE"] = "Explora tu Banco de Banda de Guerra y Objetos Personales (Banco + Inventario)"
L["ITEMS_DISABLED_TITLE"] = "Objetos del Banco de Banda de Guerra"
L["ITEMS_LOADING"] = "Cargando datos de inventario"
L["GUILD_BANK_REQUIRED"] = "Debes estar en una hermandad para acceder al Banco de Hermandad."
L["ITEMS_SEARCH"] = "Buscar objetos..."
L["NEVER"] = "Nunca"
L["ITEM_FALLBACK_FORMAT"] = "Objeto %s"
L["TAB_FORMAT"] = "Pestaña %d"
L["BAG_FORMAT"] = "Bolsa %d"
L["BANK_BAG_FORMAT"] = "Bolsa de banco %d"
L["ITEM_ID_LABEL"] = "ID de objeto:"
L["QUALITY_TOOLTIP_LABEL"] = "Calidad:"
L["STACK_LABEL"] = "Montón:"
L["RIGHT_CLICK_MOVE"] = "Mover a bolsa"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Dividir montón"
L["LEFT_CLICK_PICKUP"] = "Recoger"
L["ITEMS_BANK_NOT_OPEN"] = "Banco no abierto"
L["SHIFT_LEFT_CLICK_LINK"] = "Enlazar en chat"
L["ITEM_DEFAULT_TOOLTIP"] = "Objeto"
L["ITEMS_STATS_ITEMS"] = "%s objetos"
L["ITEMS_STATS_SLOTS"] = "%s/%s espacios"
L["ITEMS_STATS_LAST"] = "Último: %s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "Almacenamiento de personaje"
L["STORAGE_SEARCH"] = "Buscar almacenamiento..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "Progreso PvE"
L["PVE_SUBTITLE"] = "Gran Bóveda, Bloqueos de Banda y Mítica+ en tu Banda de Guerra"
L["PVE_NO_CHARACTER"] = "No hay datos de personajes disponibles"
L["LV_FORMAT"] = "Nv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = "Banda"
L["VAULT_DUNGEON"] = "Mazmorra"
L["VAULT_WORLD"] = "Mundo"
L["VAULT_SLOT_FORMAT"] = "%s Espacio %d"
L["VAULT_NO_PROGRESS"] = "Aún no hay progreso"
L["VAULT_UNLOCK_FORMAT"] = "Completa %s actividades para desbloquear"
L["VAULT_NEXT_TIER_FORMAT"] = "Siguiente nivel: %d iLvl al completar %s"
L["VAULT_REMAINING_FORMAT"] = "Restante: %s actividades"
L["VAULT_PROGRESS_FORMAT"] = "Progreso: %s / %s"
L["OVERALL_SCORE_LABEL"] = "Puntuación total:"
L["BEST_KEY_FORMAT"] = "Mejor llave: +%d"
L["SCORE_FORMAT"] = "Puntuación: %s"
L["NOT_COMPLETED_SEASON"] = "No completado esta temporada"
L["CURRENT_MAX_FORMAT"] = "Actual: %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "Progreso: %.1f%%"
L["NO_CAP_LIMIT"] = "Sin límite máximo"
L["GREAT_VAULT"] = "Gran Bóveda"
L["LOADING_PVE"] = "Cargando datos PvE..."
L["PVE_APIS_LOADING"] = "Por favor espera, las APIs de WoW se están inicializando..."
L["NO_VAULT_DATA"] = "Sin datos de bóveda"
L["NO_DATA"] = "Sin datos"
L["KEYSTONE"] = "Piedra angular"
L["NO_KEY"] = "Sin llave"
L["AFFIXES"] = "Afijos"
L["NO_AFFIXES"] = "Sin afijos"
L["VAULT_BEST_KEY"] = "Mejor llave:"
L["VAULT_SCORE"] = "Puntuación:"

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "Resumen de Reputación"
L["REP_SUBTITLE"] = "Rastrea facciones y renombre en tu banda de guerra"
L["REP_DISABLED_TITLE"] = "Rastreo de Reputación"
L["REP_LOADING_TITLE"] = "Cargando Datos de Reputación"
L["REP_SEARCH"] = "Buscar reputaciones..."
L["REP_PARAGON_TITLE"] = "Reputación Paragón"
L["REP_REWARD_AVAILABLE"] = "¡Recompensa disponible!"
L["REP_CONTINUE_EARNING"] = "Continúa ganando reputación para obtener recompensas"
L["REP_CYCLES_FORMAT"] = "Ciclos: %d"
L["REP_PROGRESS_HEADER"] = "Progreso: %d/%d"
L["REP_PARAGON_PROGRESS"] = "Progreso Paragón:"
L["REP_PROGRESS_COLON"] = "Progreso:"
L["REP_CYCLES_COLON"] = "Ciclos:"
L["REP_CHARACTER_PROGRESS"] = "Progreso del personaje:"
L["REP_RENOWN_FORMAT"] = "Renombre %d"
L["REP_PARAGON_FORMAT"] = "Paragón (%s)"
L["REP_UNKNOWN_FACTION"] = "Facción desconocida"
L["REP_API_UNAVAILABLE_TITLE"] = "API de Reputación No Disponible"
L["REP_API_UNAVAILABLE_DESC"] = "La API C_Reputation no está disponible en este servidor. Esta función requiere WoW 11.0+ (The War Within)."
L["REP_FOOTER_TITLE"] = "Rastreo de Reputación"
L["REP_FOOTER_DESC"] = "Las reputaciones se escanean automáticamente al iniciar sesión y cuando cambian. Usa el panel de reputación en el juego para ver información detallada y recompensas."
L["REP_CLEARING_CACHE"] = "Limpiando caché y recargando..."
L["REP_LOADING_DATA"] = "Cargando datos de reputación..."
L["REP_MAX"] = "Máx."
L["REP_TIER_FORMAT"] = "Nivel %d"
L["ACCOUNT_WIDE_LABEL"] = "Toda la cuenta"
L["NO_RESULTS"] = "Sin resultados"
L["NO_REP_MATCH"] = "Ninguna reputación coincide con '%s'"
L["NO_REP_DATA"] = "No hay datos de reputación disponibles"
L["REP_SCAN_TIP"] = "Las reputaciones se escanean automáticamente. Intenta /reload si no aparece nada."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "Reputaciones de toda la cuenta (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "Sin reputaciones de toda la cuenta"
L["NO_CHARACTER_REPS"] = "Sin reputaciones de personaje"

-- =============================================
-- Currency Tab
-- =============================================
L["CURRENCY_TITLE"] = "Rastreador de Monedas"
L["CURRENCY_SUBTITLE"] = "Rastrea todas las monedas de tus personajes"
L["CURRENCY_DISABLED_TITLE"] = "Rastreo de Monedas"
L["CURRENCY_LOADING_TITLE"] = "Cargando Datos de Monedas"
L["CURRENCY_SEARCH"] = "Buscar monedas..."
L["CURRENCY_HIDE_EMPTY"] = "Ocultar vacías"
L["CURRENCY_SHOW_EMPTY"] = "Mostrar vacías"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "Todas Transferibles entre Banda"
L["CURRENCY_CHARACTER_SPECIFIC"] = "Monedas Específicas del Personaje"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "Limitación de Transferencia de Monedas"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "La API de Blizzard no admite transferencias automáticas de monedas. Por favor, usa la ventana de monedas en el juego para transferir manualmente las monedas de Banda de Guerra."
L["CURRENCY_UNKNOWN"] = "Moneda desconocida"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "Elimina todos los planes completados de tu lista Mis Planes. Esto eliminará todos los planes personalizados completados y quitará las monturas/mascotas/juguetes completados de tus planes. ¡Esta acción no se puede deshacer!"
L["RECIPE_BROWSER_DESC"] = "Abre tu ventana de Profesión en el juego para explorar recetas.\nEl addon escaneará las recetas disponibles cuando la ventana esté abierta."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "Fuente: [Logro %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s ya tiene un plan activo de bóveda semanal. Puedes encontrarlo en la categoría 'Mis Planes'."
L["DAILY_PLAN_EXISTS_DESC"] = "%s ya tiene un plan activo de misión diaria. Puedes encontrarlo en la categoría 'Tareas Diarias'."
L["TRANSMOG_WIP_DESC"] = "El rastreo de colección de transfiguración está actualmente en desarrollo.\n\nEsta función estará disponible en una actualización futura con mejor\nrendimiento y mejor integración con los sistemas de Banda de Guerra."
L["WEEKLY_VAULT_CARD"] = "Tarjeta de Bóveda Semanal"
L["WEEKLY_VAULT_COMPLETE"] = "Tarjeta de Bóveda Semanal - Completada"
L["UNKNOWN_SOURCE"] = "Fuente desconocida"
L["DAILY_TASKS_PREFIX"] = "Tareas Diarias - "
L["NO_FOUND_FORMAT"] = "No se encontraron %ss"
L["PLANS_COUNT_FORMAT"] = "%d planes"
L["PET_BATTLE_LABEL"] = "Batalla de mascotas:"
L["QUEST_LABEL"] = "Misión:"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "Idioma actual:"
L["LANGUAGE_TOOLTIP"] = "El addon utiliza automáticamente el idioma de tu cliente de WoW. Para cambiarlo, actualiza la configuración de Battle.net."
L["POPUP_DURATION"] = "Duración del popup"
L["POPUP_POSITION"] = "Posición del popup"
L["SET_POSITION"] = "Establecer posición"
L["DRAG_TO_POSITION"] = "Arrastra para posicionar\nClic derecho para confirmar"
L["RESET_DEFAULT"] = "Restablecer predeterminado"
L["TEST_POPUP"] = "Probar popup"
L["CUSTOM_COLOR"] = "Color personalizado"
L["OPEN_COLOR_PICKER"] = "Abrir selector de color"
L["COLOR_PICKER_TOOLTIP"] = "Abre el selector de color nativo de WoW para elegir un color de tema personalizado"
L["PRESET_THEMES"] = "Temas predefinidos"
L["WARBAND_NEXUS_SETTINGS"] = "Configuración de Warband Nexus"
L["NO_OPTIONS"] = "Sin opciones"
L["NONE_LABEL"] = NONE or "Ninguno"
L["TAB_FILTERING"] = "Filtrado de pestañas"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Notificaciones"
L["SCROLL_SPEED"] = "Velocidad de desplazamiento"
L["ANCHOR_FORMAT"] = "Ancla: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "Mostrar Planificador Semanal"
L["LOCK_MINIMAP_ICON"] = "Bloquear icono del minimapa"
L["AUTO_SCAN_ITEMS"] = "Escaneo automático de objetos"
L["LIVE_SYNC"] = "Sincronización en vivo"
L["BACKPACK_LABEL"] = "Mochila"
L["REAGENT_LABEL"] = "Reactivo"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "Módulo desactivado"
L["LOADING"] = "Cargando..."
L["PLEASE_WAIT"] = "Por favor espera..."
L["RESET_PREFIX"] = "Reinicio:"
L["TRANSFER_CURRENCY"] = "Transferir moneda"
L["AMOUNT_LABEL"] = "Cantidad:"
L["TO_CHARACTER"] = "Al personaje:"
L["SELECT_CHARACTER"] = "Seleccionar personaje..."
L["CURRENCY_TRANSFER_INFO"] = "La ventana de monedas se abrirá automáticamente.\nNecesitarás hacer clic derecho manualmente en la moneda para transferirla."
L["OK_BUTTON"] = OKAY or "OK"
L["SAVE"] = "Guardar"
L["TITLE_FIELD"] = "Título:"
L["DESCRIPTION_FIELD"] = "Descripción:"
L["CREATE_CUSTOM_PLAN"] = "Crear Plan Personalizado"
L["REPORT_BUGS"] = "Reporta errores o comparte sugerencias en CurseForge para ayudar a mejorar el addon."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus proporciona una interfaz centralizada para gestionar todos tus personajes, monedas, reputaciones, objetos y progreso PvE en toda tu Banda de Guerra."
L["CHARACTERS_DESC"] = "Ver todos tus personajes con oro, nivel, profesiones e información de última vez jugado."
L["ITEMS_DESC"] = "Buscar objetos en todas las bolsas y bancos. Se actualiza automáticamente cuando abres el banco."
L["STORAGE_DESC"] = "Explora todo tu inventario agregado de todos los personajes y bancos."
L["PVE_DESC"] = "Rastrea la Gran Bóveda, piedras angulares Mítica+ y bloqueos de banda para todos los personajes."
L["REPUTATIONS_DESC"] = "Monitorea el progreso de reputación con filtrado inteligente (Toda la cuenta vs Específico del personaje)."
L["CURRENCY_DESC"] = "Ver todas las monedas organizadas por expansión con opciones de filtrado."
L["PLANS_DESC"] = "Explora y rastrea monturas, mascotas, juguetes, logros y transfiguraciones que aún no has recolectado."
L["STATISTICS_DESC"] = "Ver puntos de logro, progreso de colección y estadísticas de uso de bolsas/banco."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "Mítica"
L["DIFFICULTY_HEROIC"] = "Heroica"
L["DIFFICULTY_NORMAL"] = "Normal"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Nivel %d"
L["PVP_TYPE"] = "JcJ"
L["PREPARING"] = "Preparando"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Estadísticas de Cuenta"
L["STATISTICS_SUBTITLE"] = "Progreso de colección, oro y resumen de almacenamiento"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "¡Bienvenido a Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "Resumen del AddOn"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "Rastrea tus objetivos de colección"
L["ACTIVE_PLAN_FORMAT"] = "%d plan activo"
L["ACTIVE_PLANS_FORMAT"] = "%d planes activos"
L["RESET_LABEL"] = RESET or "Reiniciar"

-- Plans - Type Names
L["TYPE_MOUNT"] = MOUNT or "Montura"
L["TYPE_PET"] = PET or "Mascota"
L["TYPE_TOY"] = TOY or "Juguete"
L["TYPE_RECIPE"] = "Receta"
L["TYPE_ILLUSION"] = "Ilusión"
L["TYPE_TITLE"] = "Título"
L["TYPE_CUSTOM"] = "Personalizado"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transfiguración"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Botín"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Misión"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Vendedor"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profesión"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Combate de mascotas"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Logro"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "Evento mundial"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promoción"
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
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Botín de jefe"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Misión"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Vendedor"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "Botín en el mundo"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Logro"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Profesión"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "Vendido por"
L["PARSE_CRAFTED"] = "Fabricado"
L["PARSE_ZONE"] = ZONE or "Zona"
L["PARSE_COST"] = "Costo"
L["PARSE_REPUTATION"] = REPUTATION or "Reputación"
L["PARSE_FACTION"] = FACTION or "Facción"
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
L["PARSE_MISSION"] = "Misión"
L["PARSE_EXPANSION"] = "Expansión"
L["PARSE_SCENARIO"] = "Escenario"
L["PARSE_CLASS_HALL"] = "Sala de la orden"
L["PARSE_CAMPAIGN"] = "Campaña"
L["PARSE_EVENT"] = "Evento"
L["PARSE_SPECIAL"] = "Especial"
L["PARSE_BRAWLERS_GUILD"] = "Gremio de camorristas"
L["PARSE_CHALLENGE_MODE"] = "Modo desafío"
L["PARSE_MYTHIC_PLUS"] = "Mítica+"
L["PARSE_TIMEWALKING"] = "Paseo del tiempo"
L["PARSE_ISLAND_EXPEDITION"] = "Expedición a islas"
L["PARSE_WARFRONT"] = "Frente de guerra"
L["PARSE_TORGHAST"] = "Torghast"
L["PARSE_ZERETH_MORTIS"] = "Zereth Mortis"
L["PARSE_HIDDEN"] = "Oculto"
L["PARSE_RARE"] = "Raro"
L["PARSE_WORLD_BOSS"] = "Jefe de mundo"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Botín"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "Del logro"
L["FALLBACK_UNKNOWN_PET"] = "Mascota desconocida"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "Colección de mascotas"
L["FALLBACK_TOY_COLLECTION"] = "Colección de juguetes"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Colección de transfiguración"
L["FALLBACK_PLAYER_TITLE"] = "Título de jugador"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Desconocido"
L["FALLBACK_ILLUSION_FORMAT"] = "Ilusión %s"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "Establecer contador de intentos para:\n%s"
L["RESET_COMPLETED_CONFIRM"] = "¿Estás seguro de que quieres eliminar TODOS los planes completados?\n\n¡Esto no se puede deshacer!"
L["YES_RESET"] = "Sí, Reiniciar"
L["REMOVED_PLANS_FORMAT"] = "Se eliminaron %d plan(es) completado(s)."

-- Plans - Buttons
L["ADD_CUSTOM"] = "Añadir Personalizado"
L["ADD_VAULT"] = "Añadir Bóveda"
L["ADD_QUEST"] = "Añadir Misión"
L["CREATE_PLAN"] = "Crear Plan"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "Diaria"
L["QUEST_CAT_WORLD"] = "Mundo"
L["QUEST_CAT_WEEKLY"] = "Semanal"
L["QUEST_CAT_ASSIGNMENT"] = "Asignación"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Categoría desconocida"
L["SCANNING_FORMAT"] = "Escaneando %s"
L["CUSTOM_PLAN_SOURCE"] = "Plan personalizado"
L["POINTS_FORMAT"] = "%d Puntos"
L["SOURCE_NOT_AVAILABLE"] = "Información de fuente no disponible"
L["PROGRESS_ON_FORMAT"] = "Estás en %d/%d del progreso"
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
L["MYTHIC_PLUS_LABEL"] = "Mítica+"
L["RAIDS_LABEL"] = "Bandas"

-- PlanCardFactory
L["FACTION_LABEL"] = "Facción:"
L["FRIENDSHIP_LABEL"] = "Amistad"
L["RENOWN_TYPE_LABEL"] = "Renombre"
L["ADD_BUTTON"] = "+ Añadir"
L["ADDED_LABEL"] = "Añadido"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s de %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Mostrar cantidades apiladas en objetos en la vista de almacenamiento"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Mostrar la sección del Planificador Semanal en la pestaña Personajes"
L["LOCK_MINIMAP_TOOLTIP"] = "Bloquear el icono del minimapa en su lugar (previene arrastrar)"
L["AUTO_SCAN_TOOLTIP"] = "Escanear y almacenar en caché objetos automáticamente cuando abres bancos o bolsas"
L["LIVE_SYNC_TOOLTIP"] = "Mantener la caché de objetos actualizada en tiempo real mientras los bancos están abiertos"
L["SHOW_ILVL_TOOLTIP"] = "Mostrar insignias de nivel de objeto en equipamiento en la lista de objetos"
L["SCROLL_SPEED_TOOLTIP"] = "Multiplicador de velocidad de desplazamiento (1.0x = 28 px por paso)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "Ignorar Pestaña %d del Banco de Banda de Guerra del escaneo automático"
L["IGNORE_SCAN_FORMAT"] = "Ignorar %s del escaneo automático"
L["BANK_LABEL"] = BANK or "Banco"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "Activar Notificaciones"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Interruptor maestro para todas las ventanas emergentes de notificación"
L["VAULT_REMINDER"] = "Recordatorio de Bóveda"
L["VAULT_REMINDER_TOOLTIP"] = "Mostrar recordatorio cuando tengas recompensas de Bóveda Semanal sin reclamar"
L["LOOT_ALERTS"] = "Alertas de Botín"
L["LOOT_ALERTS_TOOLTIP"] = "Mostrar notificación cuando una NUEVA montura, mascota o juguete entra en tu bolsa"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Ocultar Alerta de Logro de Blizzard"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Ocultar la ventana emergente de logro predeterminada de Blizzard y usar la notificación de Warband Nexus en su lugar"
L["REPUTATION_GAINS"] = "Ganancias de Reputación"
L["REPUTATION_GAINS_TOOLTIP"] = "Mostrar mensajes de chat cuando ganes reputación con facciones"
L["CURRENCY_GAINS"] = "Ganancias de Monedas"
L["CURRENCY_GAINS_TOOLTIP"] = "Mostrar mensajes de chat cuando ganes monedas"
L["DURATION_LABEL"] = "Duración"
L["DAYS_LABEL"] = "días"
L["WEEKS_LABEL"] = "semanas"
L["EXTEND_DURATION"] = "Extender duración"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Arrastra el marco verde para establecer la posición de la ventana emergente. Clic derecho para confirmar."
L["POSITION_RESET_MSG"] = "Posición de la ventana emergente restablecida al predeterminado (Centro Superior)"
L["POSITION_SAVED_MSG"] = "¡Posición de la ventana emergente guardada!"
L["TEST_NOTIFICATION_TITLE"] = "Notificación de prueba"
L["TEST_NOTIFICATION_MSG"] = "Prueba de posición"
L["NOTIFICATION_DEFAULT_TITLE"] = "Notificación"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "Tema y Apariencia"
L["COLOR_PURPLE"] = "Morado"
L["COLOR_PURPLE_DESC"] = "Tema morado clásico (predeterminado)"
L["COLOR_BLUE"] = "Azul"
L["COLOR_BLUE_DESC"] = "Tema azul frío"
L["COLOR_GREEN"] = "Verde"
L["COLOR_GREEN_DESC"] = "Tema verde naturaleza"
L["COLOR_RED"] = "Rojo"
L["COLOR_RED_DESC"] = "Tema rojo ardiente"
L["COLOR_ORANGE"] = "Naranja"
L["COLOR_ORANGE_DESC"] = "Tema naranja cálido"
L["COLOR_CYAN"] = "Cian"
L["COLOR_CYAN_DESC"] = "Tema cian brillante"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "Familia de Fuente"
L["FONT_FAMILY_TOOLTIP"] = "Elige la fuente utilizada en toda la interfaz del addon"
L["FONT_SCALE"] = "Escala de Fuente"
L["FONT_SCALE_TOOLTIP"] = "Ajustar el tamaño de fuente en todos los elementos de la interfaz"
L["RESOLUTION_NORMALIZATION"] = "Normalización de Resolución"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Ajustar tamaños de fuente basados en resolución de pantalla y escala de interfaz para que el texto permanezca del mismo tamaño físico en diferentes monitores"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Avanzado"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Nivel de Objeto %s"
L["ITEM_NUMBER_FORMAT"] = "Objeto #%s"
L["CHARACTER_CURRENCIES"] = "Monedas del Personaje:"
L["YOU_MARKER"] = "(Tú)"
L["WN_SEARCH"] = "Búsqueda WN"
L["WARBAND_BANK_COLON"] = "Banco de Banda de Guerra:"
L["AND_MORE_FORMAT"] = "... y %d más"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "Has recolectado una montura"
L["COLLECTED_PET_MSG"] = "Has recolectado una mascota de batalla"
L["COLLECTED_TOY_MSG"] = "Has recolectado un juguete"
L["COLLECTED_ILLUSION_MSG"] = "Has recolectado una ilusión"
L["ACHIEVEMENT_COMPLETED_MSG"] = "¡Logro completado!"
L["EARNED_TITLE_MSG"] = "Has obtenido un título"
L["COMPLETED_PLAN_MSG"] = "Has completado un plan"
L["DAILY_QUEST_CAT"] = "Misión Diaria"
L["WORLD_QUEST_CAT"] = "Misión de Mundo"
L["WEEKLY_QUEST_CAT"] = "Misión Semanal"
L["SPECIAL_ASSIGNMENT_CAT"] = "Asignación Especial"
L["DELVE_CAT"] = "Excavación"
L["DUNGEON_CAT"] = "Mazmorra"
L["RAID_CAT"] = "Banda"
L["WORLD_CAT"] = "Mundo"
L["ACTIVITY_CAT"] = "Actividad"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Progreso"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Progreso Completado"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Plan de Bóveda Semanal - %s"
L["ALL_SLOTS_COMPLETE"] = "¡Todos los Espacios Completados!"
L["QUEST_COMPLETED_SUFFIX"] = "Completada"
L["WEEKLY_VAULT_READY"] = "¡Bóveda Semanal Lista!"
L["UNCLAIMED_REWARDS"] = "Tienes recompensas sin reclamar"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "Oro Total:"
L["CHARACTERS_COLON"] = "Personajes:"
L["LEFT_CLICK_TOGGLE"] = "Clic Izquierdo: Alternar ventana"
L["RIGHT_CLICK_PLANS"] = "Clic Derecho: Abrir Planes"
L["MINIMAP_SHOWN_MSG"] = "Botón del minimapa mostrado"
L["MINIMAP_HIDDEN_MSG"] = "Botón del minimapa oculto (usa /wn minimap para mostrar)"
L["TOGGLE_WINDOW"] = "Alternar Ventana"
L["SCAN_BANK_MENU"] = "Escanear Banco"
L["TRACKING_DISABLED_SCAN_MSG"] = "El rastreo de personajes está desactivado. Activa el rastreo en la configuración para escanear el banco."
L["SCAN_COMPLETE_MSG"] = "¡Escaneo completado!"
L["BANK_NOT_OPEN_MSG"] = "El banco no está abierto"
L["OPTIONS_MENU"] = "Opciones"
L["HIDE_MINIMAP_BUTTON"] = "Ocultar Botón del Minimapa"
L["MENU_UNAVAILABLE_MSG"] = "Menú de clic derecho no disponible"
L["USE_COMMANDS_MSG"] = "Usa /wn show, /wn scan, /wn config"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "Máx"
L["OPEN_AND_GUIDE"] = "Abrir y Guiar"
L["FROM_LABEL"] = "De:"
L["AVAILABLE_LABEL"] = "Disponible:"
L["ONLINE_LABEL"] = "(En línea)"
L["DATA_SOURCE_TITLE"] = "Información de Fuente de Datos"
L["DATA_SOURCE_USING"] = "Esta pestaña está usando:"
L["DATA_SOURCE_MODERN"] = "Servicio de caché moderno (basado en eventos)"
L["DATA_SOURCE_LEGACY"] = "Acceso directo a BD heredado"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Necesita migración al servicio de caché"
L["GLOBAL_DB_VERSION"] = "Versión de BD Global:"

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
L["INFO_TAB_STATISTICS"] = "Estadísticas"
L["SPECIAL_THANKS"] = "Agradecimientos Especiales"
L["SUPPORTERS_TITLE"] = "Patrocinadores"
L["THANK_YOU_MSG"] = "¡Gracias por usar Warband Nexus!"

-- =============================================
-- Changelog (What's New) - v2.0.0
-- =============================================
L["CHANGELOG_V200"] = "ACTUALIZACIONES IMPORTANTES:\n" ..
    "- Notificaciones de Botín y Logros: Recibe notificaciones cuando obtengas monturas, mascotas, juguetes, ilusiones, títulos y logros\n" ..
    "- Recordatorio de Bóveda Semanal: Notificación emergente cuando tengas recompensas de bóveda sin reclamar\n" ..
    "- Pestaña Planes: Organiza tus objetivos y rastrea lo que quieres recolectar a continuación\n" ..
    "- Sistema de Fuentes: Fuentes personalizables en todo el addon\n" ..
    "- Colores de Tema: Colores de acento personalizados para personalizar la interfaz\n" ..
    "- Mejoras de Interfaz: Diseño más limpio, mejor organización, búsqueda y pulido visual\n" ..
    "- Mensajes de chat para ganancias de Reputación y Monedas: Mensajes en tiempo real [WN-Reputación] y [WN-Moneda] con progreso\n" ..
    "- Sistema de Tooltips: Tooltips mejorados en toda la interfaz\n" ..
    "- Rastreo de Personajes: Elige qué personajes rastrear\n" ..
    "- Personajes Favoritos: Marca tus personajes favoritos en la lista con una estrella\n" ..
    "\n" ..
    "ACTUALIZACIONES MENORES:\n" ..
    "- Módulo de Banco desactivado\n" ..
    "- Sistema de base de datos antiguo eliminado (mejoras y correcciones de errores)\n" ..
    "- Opción para ocultar la ventana emergente de logro de Blizzard cuando uses notificaciones de WN\n" ..
    "- Posición configurable de notificación para toasts de botín y logros\n" ..
    "\n" ..
    "¡Gracias por usar Warband Nexus!\n" ..
    "\n" ..
    "Si deseas reportar un error o dejar comentarios, puedes dejar un comentario en CurseForge - Warband Nexus."

-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "Confirmar Acción"
L["CONFIRM"] = "Confirmar"
L["ENABLE_TRACKING_FORMAT"] = "¿Activar rastreo para |cffffcc00%s|r?"
L["DISABLE_TRACKING_FORMAT"] = "¿Desactivar rastreo para |cffffcc00%s|r?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "Reputaciones de Toda la Cuenta (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Reputaciones Basadas en Personaje (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "Recompensa Esperando"
L["REP_PARAGON_LABEL"] = "Paragón"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "Preparando..."
L["REP_LOADING_INITIALIZING"] = "Inicializando..."
L["REP_LOADING_FETCHING"] = "Obteniendo datos de reputación..."
L["REP_LOADING_PROCESSING"] = "Procesando %d facciones..."
L["REP_LOADING_PROCESSING_COUNT"] = "Procesando... (%d/%d)"
L["REP_LOADING_SAVING"] = "Guardando en base de datos..."
L["REP_LOADING_COMPLETE"] = "¡Completado!"

-- =============================================
-- Gold Transfer
-- =============================================
L["GOLD_TRANSFER"] = "Transferencia de Oro"
L["GOLD_LABEL"] = "Oro"
L["SILVER_LABEL"] = "Plata"
L["COPPER_LABEL"] = "Cobre"
L["DEPOSIT"] = "Depositar"
L["WITHDRAW"] = "Retirar"
L["DEPOSIT_TO_WARBAND"] = "Depositar en Banco de Banda de Guerra"
L["WITHDRAW_FROM_WARBAND"] = "Retirar del Banco de Banda de Guerra"
L["YOUR_GOLD_FORMAT"] = "Tu Oro: %s"
L["WARBAND_BANK_FORMAT"] = "Banco de Banda de Guerra: %s"
L["NOT_ENOUGH_GOLD"] = "No hay suficiente oro disponible."
L["ENTER_AMOUNT"] = "Por favor ingresa una cantidad."
L["ONLY_WARBAND_GOLD"] = "Solo el Banco de Banda de Guerra admite transferencia de oro."

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "No se puede abrir la ventana durante el combate. Por favor intenta de nuevo después de que termine el combate."
L["BANK_IS_ACTIVE"] = "El banco está activo"
L["ITEMS_CACHED_FORMAT"] = "%d objetos en caché"
L["UP_TO_DATE"] = "Actualizado"
L["NEVER_SCANNED"] = "Nunca Escaneado"

-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "PERSONAJE"
L["TABLE_HEADER_LEVEL"] = "NIVEL"
L["TABLE_HEADER_GOLD"] = "ORO"
L["TABLE_HEADER_LAST_SEEN"] = "VISTO POR ÚLTIMA VEZ"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "Ningún objeto coincide con '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "Ningún objeto coincide con tu búsqueda"
L["ITEMS_SCAN_HINT"] = "Los objetos se escanean automáticamente. Intenta /reload si no aparece nada."
L["ITEMS_WARBAND_BANK_HINT"] = "Abre el Banco de Banda de Guerra para escanear objetos (escaneado automáticamente en la primera visita)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Próximos pasos:"
L["CURRENCY_TRANSFER_STEP_1"] = "Encuentra |cffffffff%s|r en la ventana de monedas"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800Clic derecho|r en él"
L["CURRENCY_TRANSFER_STEP_3"] = "Selecciona |cffffffff'Transferir a Banda de Guerra'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Elige |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Ingresa cantidad: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "¡La ventana de monedas está ahora abierta!"
L["CURRENCY_TRANSFER_SECURITY"] = "(La seguridad de Blizzard previene la transferencia automática)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "Zona: "
L["ADDED"] = "Añadido"
L["WEEKLY_VAULT_TRACKER"] = "Rastreador de Bóveda Semanal"
L["DAILY_QUEST_TRACKER"] = "Rastreador de Misiones Diarias"
L["CUSTOM_PLAN_STATUS"] = "Plan personalizado '%s' %s"

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
L["CHAT_REP_GAIN"] = "|cffff8800[WN-Reputación]|r |cff00ff00[%s]|r: Ganaste |cff00ff00+%s|r |cff00ff00(%s / %s)|r"
L["CHAT_REP_GAIN_NOMAX"] = "|cffff8800[WN-Reputación]|r |cff00ff00[%s]|r: Ganaste |cff00ff00+%s|r"
L["CHAT_REP_STANDING"] = "|cffff8800[WN-Reputación]|r |cff00ff00[%s]|r: Ahora |cff%s%s|r"
L["CHAT_CUR_GAIN"] = "|cffcc66ff[WN-Moneda]|r %s: Ganaste |cff00ff00+%s|r |cff00ff00(%s / %s)|r"
L["CHAT_CUR_GAIN_NOMAX"] = "|cffcc66ff[WN-Moneda]|r %s: Ganaste |cff00ff00+%s|r |cff00ff00(%s)|r"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "Plan completado: "
L["WEEKLY_VAULT_PLAN_NAME"] = "Bóveda Semanal - %s"
L["VAULT_PLANS_RESET"] = "¡Los planes de Gran Bóveda semanal han sido reiniciados! (%d plan%s)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "No se encontraron personajes"
L["EMPTY_CHARACTERS_DESC"] = "Inicia sesión con tus personajes para empezar a rastrearlos.\nLos datos se recopilan automáticamente en cada inicio de sesión."
L["EMPTY_ITEMS_TITLE"] = "No hay objetos en caché"
L["EMPTY_ITEMS_DESC"] = "Abre tu banco de banda de guerra o banco personal para escanear objetos.\nLos objetos se almacenan automáticamente en la primera visita."
L["EMPTY_STORAGE_TITLE"] = "Sin datos de almacenamiento"
L["EMPTY_STORAGE_DESC"] = "Los objetos se escanean al abrir bancos o bolsas.\nVisita un banco para empezar a rastrear tu almacenamiento."
L["EMPTY_PLANS_TITLE"] = "Sin planes aún"
L["EMPTY_PLANS_DESC"] = "Explora monturas, mascotas, juguetes o logros arriba\npara añadir objetivos de colección y seguir tu progreso."
L["EMPTY_REPUTATION_TITLE"] = "Sin datos de reputación"
L["EMPTY_REPUTATION_DESC"] = "Las reputaciones se escanean automáticamente al iniciar sesión.\nInicia sesión con un personaje para rastrear facciones."
L["EMPTY_CURRENCY_TITLE"] = "Sin datos de moneda"
L["EMPTY_CURRENCY_DESC"] = "Las monedas se rastrean automáticamente en todos tus personajes.\nInicia sesión con un personaje para rastrear monedas."
L["EMPTY_PVE_TITLE"] = "Sin datos de PvE"
L["EMPTY_PVE_DESC"] = "El progreso PvE se rastrea al iniciar sesión con tus personajes.\nGran Bóveda, Mítica+ y bloqueos de banda aparecerán aquí."
L["EMPTY_STATISTICS_TITLE"] = "Sin estadísticas disponibles"
L["EMPTY_STATISTICS_DESC"] = "Las estadísticas provienen de tus personajes rastreados.\nInicia sesión con un personaje para recopilar datos."
L["NO_ADDITIONAL_INFO"] = "Sin información adicional"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "¿Quieres rastrear este personaje?"
L["CLEANUP_NO_INACTIVE"] = "No se encontraron personajes inactivos (90+ días)"
L["CLEANUP_REMOVED_FORMAT"] = "Se eliminaron %d personaje(s) inactivo(s)"
L["TRACKING_ENABLED_MSG"] = "¡Rastreo de personaje ACTIVADO!"
L["TRACKING_DISABLED_MSG"] = "¡Rastreo de personaje DESACTIVADO!"
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
L["NO_REQUIREMENTS_INSTANT"] = "Sin requisitos (completado instantáneo)"
