--[[
    Warband Nexus - Portuguese (Brazil) Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "ptBR")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus carregado. Digite /wn ou /warbandnexus para opções."
L["VERSION"] = GAME_VERSION_LABEL or "Versão"

-- Slash Commands
L["SLASH_HELP"] = "Comandos disponíveis:"
L["SLASH_OPTIONS"] = "Abrir painel de opções"
L["SLASH_SCAN"] = "Escanear banco de Bando de Guerra"
L["SLASH_SHOW"] = "Mostrar/ocultar janela principal"
L["SLASH_DEPOSIT"] = "Abrir fila de depósito"
L["SLASH_SEARCH"] = "Pesquisar um item"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Configurações gerais"
L["GENERAL_SETTINGS_DESC"] = "Configurar comportamento geral do addon"
L["ENABLE_ADDON"] = "Ativar addon"
L["ENABLE_ADDON_DESC"] = "Ativar ou desativar funcionalidades do Warband Nexus"
L["MINIMAP_ICON"] = "Mostrar ícone do minimapa"
L["MINIMAP_ICON_DESC"] = "Mostrar ou ocultar o botão do minimapa"
L["DEBUG_MODE"] = "Modo de depuração"
L["DEBUG_MODE_DESC"] = "Ativar mensagens de depuração no chat"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "Configurações de escaneamento"
L["SCANNING_SETTINGS_DESC"] = "Configurar comportamento de escaneamento do banco"
L["AUTO_SCAN"] = "Escaneamento automático ao abrir"
L["AUTO_SCAN_DESC"] = "Escanear automaticamente o banco de Bando de Guerra ao abrir"
L["SCAN_DELAY"] = "Atraso de escaneamento"
L["SCAN_DELAY_DESC"] = "Atraso entre operações de escaneamento (em segundos)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "Configurações de depósito"
L["DEPOSIT_SETTINGS_DESC"] = "Configurar comportamento de depósito de itens"
L["GOLD_RESERVE"] = "Reserva de ouro"
L["GOLD_RESERVE_DESC"] = "Ouro mínimo a manter no inventário pessoal (em ouro)"
L["AUTO_DEPOSIT_REAGENTS"] = "Depositar reagentes automaticamente"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "Colocar reagentes na fila de depósito ao abrir o banco"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Configurações de exibição"
L["DISPLAY_SETTINGS_DESC"] = "Configurar aparência visual"
L["SHOW_ITEM_LEVEL"] = "Mostrar nível do item"
L["SHOW_ITEM_LEVEL_DESC"] = "Exibir nível do item em equipamentos"
L["SHOW_ITEM_COUNT"] = "Mostrar quantidade de itens"
L["SHOW_ITEM_COUNT_DESC"] = "Exibir quantidades empilhadas nos itens"
L["HIGHLIGHT_QUALITY"] = "Destacar por qualidade"
L["HIGHLIGHT_QUALITY_DESC"] = "Adicionar bordas coloridas baseadas na qualidade do item"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "Configurações de abas"
L["TAB_SETTINGS_DESC"] = "Configurar comportamento das abas do banco de Bando de Guerra"
L["IGNORED_TABS"] = "Abas ignoradas"
L["IGNORED_TABS_DESC"] = "Selecionar abas a excluir do escaneamento e operações"
L["TAB_1"] = "Aba de Bando de Guerra 1"
L["TAB_2"] = "Aba de Bando de Guerra 2"
L["TAB_3"] = "Aba de Bando de Guerra 3"
L["TAB_4"] = "Aba de Bando de Guerra 4"
L["TAB_5"] = "Aba de Bando de Guerra 5"

-- Scanner Module
L["SCAN_STARTED"] = "Escaneando banco de Bando de Guerra..."
L["SCAN_COMPLETE"] = "Escaneamento completo. Encontrados %d itens em %d espaços."
L["SCAN_FAILED"] = "Escaneamento falhou: O banco de Bando de Guerra não está aberto."
L["SCAN_TAB"] = "Escaneando aba %d..."
L["CACHE_CLEARED"] = "Cache de itens limpo."
L["CACHE_UPDATED"] = "Cache de itens atualizado."

-- Banker Module
L["BANK_NOT_OPEN"] = "O banco de Bando de Guerra não está aberto."
L["DEPOSIT_STARTED"] = "Iniciando operação de depósito..."
L["DEPOSIT_COMPLETE"] = "Depósito completo. %d itens transferidos."
L["DEPOSIT_CANCELLED"] = "Depósito cancelado."
L["DEPOSIT_QUEUE_EMPTY"] = "A fila de depósito está vazia."
L["DEPOSIT_QUEUE_CLEARED"] = "Fila de depósito esvaziada."
L["ITEM_QUEUED"] = "%s adicionado à fila de depósito."
L["ITEM_REMOVED"] = "%s removido da fila."
L["GOLD_DEPOSITED"] = "%s ouro depositado no banco de Bando de Guerra."
L["INSUFFICIENT_GOLD"] = "Ouro insuficiente para depósito."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "Valor inválido."
L["WITHDRAW_BANK_NOT_OPEN"] = "O banco deve estar aberto para sacar!"
L["WITHDRAW_IN_COMBAT"] = "Não é possível sacar durante combate."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "Ouro insuficiente no banco de Bando de Guerra."
L["WITHDRAWN_LABEL"] = "Sacado:"
L["WITHDRAW_API_UNAVAILABLE"] = "API de saque não disponível."
L["SORT_IN_COMBAT"] = "Não é possível ordenar durante combate."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global
L["SEARCH_CATEGORY_FORMAT"] = "Pesquisar %s..."
L["BTN_SCAN"] = "Escanear banco"
L["BTN_DEPOSIT"] = "Fila de depósito"
L["BTN_SORT"] = "Ordenar banco"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "Limpar fila"
L["BTN_DEPOSIT_ALL"] = "Depositar tudo"
L["BTN_DEPOSIT_GOLD"] = "Depositar ouro"
L["ENABLE"] = ENABLE or "Ativar" -- Blizzard Global
L["ENABLE_MODULE"] = "Ativar módulo"

-- Main Tabs (Blizzard Globals where available)
L["TAB_CHARACTERS"] = CHARACTER or "Personagens" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "Itens" -- Blizzard Global
L["TAB_STORAGE"] = "Armazenamento"
L["TAB_PLANS"] = "Planos"
L["TAB_REPUTATION"] = REPUTATION or "Reputação" -- Blizzard Global
L["TAB_REPUTATIONS"] = "Reputações"
L["TAB_CURRENCY"] = CURRENCY or "Moeda" -- Blizzard Global
L["TAB_CURRENCIES"] = "Moedas"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "Estatísticas" -- Blizzard Global

-- Item Categories (Using Blizzard Globals where available)
L["CATEGORY_ALL"] = ALL or "Todos os itens" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipamento" -- Blizzard Global
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumíveis" -- Blizzard Global
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagentes" -- Blizzard Global
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Mercadorias" -- Blizzard Global
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Itens de missão" -- Blizzard Global
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Diversos" -- Blizzard Global

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
L["HEADER_CHARACTERS"] = CHARACTER or "Personagens"
L["HEADER_CURRENT_CHARACTER"] = "PERSONAGEM ATUAL"
L["HEADER_WARBAND_GOLD"] = "OURO DO BANDO DE GUERRA"
L["HEADER_TOTAL_GOLD"] = "OURO TOTAL"
L["HEADER_REALM_GOLD"] = "OURO DO REINO"
L["HEADER_REALM_TOTAL"] = "TOTAL DO REINO"
L["CHARACTER_LAST_SEEN_FORMAT"] = "Visto por último: %s"
L["CHARACTER_GOLD_FORMAT"] = "Ouro: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "Ouro combinado de todos os personagens neste reino"

-- Items Tab
L["ITEMS_HEADER"] = "Itens do banco"
L["ITEMS_HEADER_DESC"] = "Explorar e gerenciar seu banco de Bando de Guerra e pessoal"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " itens..."
L["ITEMS_WARBAND_BANK"] = "Banco de Bando de Guerra"
L["ITEMS_PLAYER_BANK"] = BANK or "Banco pessoal" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Banco da guilda" -- Blizzard Global
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipamento"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumíveis"
L["GROUP_PROFESSION"] = "Profissão"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagentes"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Mercadorias"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Missão"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Diversos"
L["GROUP_CONTAINER"] = "Recipientes"

-- Storage Tab
L["STORAGE_HEADER"] = "Navegador de armazenamento"
L["STORAGE_HEADER_DESC"] = "Explorar todos os itens organizados por tipo"
L["STORAGE_WARBAND_BANK"] = "Banco de Bando de Guerra"
L["STORAGE_PERSONAL_BANKS"] = "Bancos pessoais"
L["STORAGE_TOTAL_SLOTS"] = "Espaços totais"
L["STORAGE_FREE_SLOTS"] = "Espaços livres"
L["STORAGE_BAG_HEADER"] = "Bolsas de Bando de Guerra"
L["STORAGE_PERSONAL_HEADER"] = "Banco pessoal"

-- Plans Tab
L["PLANS_MY_PLANS"] = "Meus planos"
L["PLANS_COLLECTIONS"] = "Planos de coleção"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "Adicionar plano personalizado"
L["PLANS_NO_RESULTS"] = "Nenhum resultado encontrado."
L["PLANS_ALL_COLLECTED"] = "Todos os itens coletados!"
L["PLANS_RECIPE_HELP"] = "Clique com o botão direito nas receitas do inventário para adicioná-las aqui."
L["COLLECTION_PLANS"] = "Planos de coleção"
L["SEARCH_PLANS"] = "Buscar planos..."
L["COMPLETED_PLANS"] = "Planos concluídos"
L["SHOW_COMPLETED"] = "Mostrar concluídos"
L["SHOW_PLANNED"] = "Mostrar planejados"
L["NO_PLANNED_ITEMS"] = "Nenhum %s planejado ainda"

-- Plans Categories (Blizzard Globals where available)
L["CATEGORY_MY_PLANS"] = "Meus planos"
L["CATEGORY_DAILY_TASKS"] = "Tarefas diárias"
L["CATEGORY_MOUNTS"] = MOUNTS or "Montarias" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "Mascotes" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "Brinquedos" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmogrificação" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "Ilusões"
L["CATEGORY_TITLES"] = TITLES or "Títulos"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Conquistas" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " reputação..."
L["REP_HEADER_WARBAND"] = "Reputação de Bando de Guerra"
L["REP_HEADER_CHARACTER"] = "Reputação do personagem"
L["REP_STANDING_FORMAT"] = "Posição: %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " moeda..."
L["CURRENCY_HEADER_WARBAND"] = "Transferível entre Bando"
L["CURRENCY_HEADER_CHARACTER"] = "Vinculado ao personagem"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "Raides" -- Blizzard Global
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Masmorras" -- Blizzard Global
L["PVE_HEADER_DELVES"] = "Imersões"
L["PVE_HEADER_WORLD_BOSS"] = "Chefes mundiais"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "Estatísticas" -- Blizzard Global: STATISTICS
L["STATS_TOTAL_ITEMS"] = "Itens totais"
L["STATS_TOTAL_SLOTS"] = "Espaços totais"
L["STATS_FREE_SLOTS"] = "Espaços livres"
L["STATS_USED_SLOTS"] = "Espaços usados"
L["STATS_TOTAL_VALUE"] = "Valor total"
L["COLLECTED"] = "Coletado"
L["TOTAL"] = "Total"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Personagem" -- Blizzard Global: CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Localização" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "Banco de Bando de Guerra"
L["TOOLTIP_TAB"] = "Aba"
L["TOOLTIP_SLOT"] = "Espaço"
L["TOOLTIP_COUNT"] = "Quantidade"
L["CHARACTER_INVENTORY"] = "Inventário"
L["CHARACTER_BANK"] = "Banco"

-- Try Counter
L["TRY_COUNT"] = "Contador de tentativas"
L["SET_TRY_COUNT"] = "Definir tentativas"
L["TRIES"] = "Tentativas"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "Definir ciclo de reset"
L["DAILY_RESET"] = "Reset diário"
L["WEEKLY_RESET"] = "Reset semanal"
L["NONE_DISABLE"] = "Nenhum (Desativar)"
L["RESET_CYCLE_LABEL"] = "Ciclo de reset:"
L["RESET_NONE"] = "Nenhum"
L["DOUBLECLICK_RESET"] = "Clique duplo para redefinir a posição"

-- Error Messages
L["ERROR_GENERIC"] = "Ocorreu um erro."
L["ERROR_API_UNAVAILABLE"] = "A API necessária não está disponível."
L["ERROR_BANK_CLOSED"] = "Não é possível realizar a operação: banco fechado."
L["ERROR_INVALID_ITEM"] = "Item especificado inválido."
L["ERROR_PROTECTED_FUNCTION"] = "Não é possível chamar função protegida em combate."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "Depositar %d itens no banco de Bando de Guerra?"
L["CONFIRM_CLEAR_QUEUE"] = "Limpar todos os itens da fila de depósito?"
L["CONFIRM_DEPOSIT_GOLD"] = "Depositar %s ouro no banco de Bando de Guerra?"

-- Update Notification
L["WHATS_NEW"] = "Novidades"
L["GOT_IT"] = "Entendi!"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "PONTOS DE CONQUISTA"
L["MOUNTS_COLLECTED"] = "MONTARIAS COLETADAS"
L["BATTLE_PETS"] = "MASCOTES DE BATALHA"
L["ACCOUNT_WIDE"] = "Toda a conta"
L["STORAGE_OVERVIEW"] = "Visão geral do armazenamento"
L["WARBAND_SLOTS"] = "ESPAÇOS DE BANDO"
L["PERSONAL_SLOTS"] = "ESPAÇOS PESSOAIS"
L["TOTAL_FREE"] = "TOTAL LIVRE"
L["TOTAL_ITEMS"] = "ITENS TOTAIS"

-- Plans Tracker Window
L["WEEKLY_VAULT"] = "Grande Cofre Semanal"
L["CUSTOM"] = "Personalizado"
L["NO_PLANS_IN_CATEGORY"] = "Nenhum plano nesta categoria.\nAdicione planos na aba Planos."
L["SOURCE_LABEL"] = "Fonte:"
L["ZONE_LABEL"] = "Zona:"
L["VENDOR_LABEL"] = "Vendedor:"
L["DROP_LABEL"] = "Saque:"
L["REQUIREMENT_LABEL"] = "Requisito:"
L["RIGHT_CLICK_REMOVE"] = "Clique direito para remover"
L["TRACKED"] = "Rastreado"
L["TRACK"] = "Rastrear"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Rastrear nos objetivos da Blizzard (máx. 10)"
L["UNKNOWN"] = "Desconhecido"
L["NO_REQUIREMENTS"] = "Sem requisitos (conclusão instantânea)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "Nenhuma atividade planejada"
L["CLICK_TO_ADD_GOALS"] = "Clique em Montarias, Mascotes ou Brinquedos acima para adicionar objetivos!"
L["UNKNOWN_QUEST"] = "Missão desconhecida"
L["ALL_QUESTS_COMPLETE"] = "Todas as missões completas!"
L["CURRENT_PROGRESS"] = "Progresso atual"
L["SELECT_CONTENT"] = "Selecionar conteúdo:"
L["QUEST_TYPES"] = "Tipos de missão:"
L["WORK_IN_PROGRESS"] = "Em desenvolvimento"
L["RECIPE_BROWSER"] = "Navegador de receitas"
L["NO_RESULTS_FOUND"] = "Nenhum resultado encontrado."
L["TRY_ADJUSTING_SEARCH"] = "Tente ajustar sua pesquisa ou filtros."
L["NO_COLLECTED_YET"] = "Nenhum %s coletado ainda"
L["START_COLLECTING"] = "Comece a coletar para vê-los aqui!"
L["ALL_COLLECTED_CATEGORY"] = "Todos os %ss coletados!"
L["COLLECTED_EVERYTHING"] = "Você coletou tudo nesta categoria!"
L["PROGRESS_LABEL"] = "Progresso:"
L["REQUIREMENTS_LABEL"] = "Requisitos:"
L["INFORMATION_LABEL"] = "Informação:"
L["DESCRIPTION_LABEL"] = "Descrição:"
L["REWARD_LABEL"] = "Recompensa:"
L["DETAILS_LABEL"] = "Detalhes:"
L["COST_LABEL"] = "Custo:"
L["LOCATION_LABEL"] = "Localização:"
L["TITLE_LABEL"] = "Título:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "Você já completou todas as conquistas nesta categoria!"
L["DAILY_PLAN_EXISTS"] = "Plano diário já existe"
L["WEEKLY_PLAN_EXISTS"] = "Plano semanal já existe"

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "Seus personagens"
L["CHARACTERS_TRACKED_FORMAT"] = "%d personagens rastreados"
L["NO_CHARACTER_DATA"] = "Nenhum dado de personagem disponível"
L["NO_FAVORITES"] = "Nenhum personagem favorito ainda. Clique no ícone de estrela para favoritar um personagem."
L["ALL_FAVORITED"] = "Todos os personagens estão favoritados!"
L["UNTRACKED_CHARACTERS"] = "Personagens não rastreados"
L["ILVL_SHORT"] = "iLvl"
L["ONLINE"] = "Online"
L["TIME_LESS_THAN_MINUTE"] = "< 1m atrás"
L["TIME_MINUTES_FORMAT"] = "%dm atrás"
L["TIME_HOURS_FORMAT"] = "%dh atrás"
L["TIME_DAYS_FORMAT"] = "%dd atrás"
L["REMOVE_FROM_FAVORITES"] = "Remover dos favoritos"
L["ADD_TO_FAVORITES"] = "Adicionar aos favoritos"
L["FAVORITES_TOOLTIP"] = "Personagens favoritos aparecem no topo da lista"
L["CLICK_TO_TOGGLE"] = "Clique para alternar"
L["UNKNOWN_PROFESSION"] = "Profissão desconhecida"
L["SKILL_LABEL"] = "Habilidade:"
L["OVERALL_SKILL"] = "Habilidade geral:"
L["BONUS_SKILL"] = "Habilidade bônus:"
L["KNOWLEDGE_LABEL"] = "Conhecimento:"
L["SPEC_LABEL"] = "Espec"
L["POINTS_SHORT"] = "pts"
L["RECIPES_KNOWN"] = "Receitas conhecidas:"
L["OPEN_PROFESSION_HINT"] = "Abrir janela de profissão"
L["FOR_DETAILED_INFO"] = "para informações detalhadas"
L["CHARACTER_IS_TRACKED"] = "Este personagem está sendo rastreado."
L["TRACKING_ACTIVE_DESC"] = "Coleta de dados e atualizações estão ativas."
L["CLICK_DISABLE_TRACKING"] = "Clique para desativar o rastreamento."
L["MUST_LOGIN_TO_CHANGE"] = "Você deve fazer login com este personagem para alterar o rastreamento."
L["TRACKING_ENABLED"] = "Rastreamento ativado"
L["CLICK_ENABLE_TRACKING"] = "Clique para ativar o rastreamento para este personagem."
L["TRACKING_WILL_BEGIN"] = "A coleta de dados começará imediatamente."
L["CHARACTER_NOT_TRACKED"] = "Este personagem não está sendo rastreado."
L["MUST_LOGIN_TO_ENABLE"] = "Você deve fazer login com este personagem para ativar o rastreamento."
L["ENABLE_TRACKING"] = "Ativar rastreamento"
L["DELETE_CHARACTER_TITLE"] = "Excluir personagem?"
L["THIS_CHARACTER"] = "este personagem"
L["DELETE_CHARACTER"] = "Excluir personagem"
L["REMOVE_FROM_TRACKING_FORMAT"] = "Remover %s do rastreamento"
L["CLICK_TO_DELETE"] = "Clique para excluir"
L["CONFIRM_DELETE"] = "Tem certeza de que deseja excluir |cff00ccff%s|r?"
L["CANNOT_UNDO"] = "Esta ação não pode ser desfeita!"
L["DELETE"] = DELETE or "Excluir"
L["CANCEL"] = CANCEL or "Cancelar"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "Itens pessoais"
L["ITEMS_SUBTITLE"] = "Explorar seu banco de Bando de Guerra e itens pessoais (Banco + Inventário)"
L["ITEMS_DISABLED_TITLE"] = "Itens do banco de Bando de Guerra"
L["ITEMS_LOADING"] = "Carregando dados do inventário"
L["GUILD_BANK_REQUIRED"] = "Você deve estar em uma guilda para acessar o banco da guilda."
L["ITEMS_SEARCH"] = "Pesquisar itens..."
L["NEVER"] = "Nunca"
L["ITEM_FALLBACK_FORMAT"] = "Item %s"
L["TAB_FORMAT"] = "Aba %d"
L["BAG_FORMAT"] = "Bolsa %d"
L["BANK_BAG_FORMAT"] = "Bolsa do banco %d"
L["ITEM_ID_LABEL"] = "ID do item:"
L["QUALITY_TOOLTIP_LABEL"] = "Qualidade:"
L["STACK_LABEL"] = "Pilha:"
L["RIGHT_CLICK_MOVE"] = "Mover para bolsa"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Dividir pilha"
L["LEFT_CLICK_PICKUP"] = "Pegar"
L["ITEMS_BANK_NOT_OPEN"] = "Banco não aberto"
L["SHIFT_LEFT_CLICK_LINK"] = "Vincular no chat"
L["ITEM_DEFAULT_TOOLTIP"] = "Item"
L["ITEMS_STATS_ITEMS"] = "%s itens"
L["ITEMS_STATS_SLOTS"] = "%s/%s espaços"
L["ITEMS_STATS_LAST"] = "Último: %s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "Armazenamento do personagem"
L["STORAGE_SEARCH"] = "Pesquisar armazenamento..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "Progresso PvE"
L["PVE_SUBTITLE"] = "Grande Cofre, bloqueios de raide e Mítica+ em todo o seu Bando de Guerra"
L["PVE_NO_CHARACTER"] = "Nenhum dado de personagem disponível"
L["LV_FORMAT"] = "Nv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = "Raide"
L["VAULT_DUNGEON"] = "Masmorra"
L["VAULT_WORLD"] = "Mundo"
L["VAULT_SLOT_FORMAT"] = "%s Espaço %d"
L["VAULT_NO_PROGRESS"] = "Nenhum progresso ainda"
L["VAULT_UNLOCK_FORMAT"] = "Complete %s atividades para desbloquear"
L["VAULT_NEXT_TIER_FORMAT"] = "Próximo nível: %d iLvl ao completar %s"
L["VAULT_REMAINING_FORMAT"] = "Restante: %s atividades"
L["VAULT_PROGRESS_FORMAT"] = "Progresso: %s / %s"
L["OVERALL_SCORE_LABEL"] = "Pontuação geral:"
L["BEST_KEY_FORMAT"] = "Melhor chave: +%d"
L["SCORE_FORMAT"] = "Pontuação: %s"
L["NOT_COMPLETED_SEASON"] = "Não completado nesta temporada"
L["CURRENT_MAX_FORMAT"] = "Atual: %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "Progresso: %.1f%%"
L["NO_CAP_LIMIT"] = "Sem limite máximo"
L["GREAT_VAULT"] = "Grande Cofre"
L["LOADING_PVE"] = "Carregando dados PvE..."
L["PVE_APIS_LOADING"] = "Aguarde, as APIs do WoW estão inicializando..."
L["NO_VAULT_DATA"] = "Sem dados do cofre"
L["NO_DATA"] = "Sem dados"
L["KEYSTONE"] = "Pedra-chave"
L["NO_KEY"] = "Sem chave"
L["AFFIXES"] = "Afixos"
L["NO_AFFIXES"] = "Sem afixos"
L["VAULT_BEST_KEY"] = "Melhor chave:"
L["VAULT_SCORE"] = "Pontuação:"

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "Visão geral de reputação"
L["REP_SUBTITLE"] = "Rastrear facções e renome em todo o seu bando de guerra"
L["REP_DISABLED_TITLE"] = "Rastreamento de reputação"
L["REP_LOADING_TITLE"] = "Carregando dados de reputação"
L["REP_SEARCH"] = "Pesquisar reputações..."
L["REP_PARAGON_TITLE"] = "Reputação Paragão"
L["REP_REWARD_AVAILABLE"] = "Recompensa disponível!"
L["REP_CONTINUE_EARNING"] = "Continue ganhando reputação para recompensas"
L["REP_CYCLES_FORMAT"] = "Ciclos: %d"
L["REP_PROGRESS_HEADER"] = "Progresso: %d/%d"
L["REP_PARAGON_PROGRESS"] = "Progresso Paragão:"
L["REP_PROGRESS_COLON"] = "Progresso:"
L["REP_CYCLES_COLON"] = "Ciclos:"
L["REP_CHARACTER_PROGRESS"] = "Progresso do personagem:"
L["REP_RENOWN_FORMAT"] = "Renome %d"
L["REP_PARAGON_FORMAT"] = "Paragão (%s)"
L["REP_UNKNOWN_FACTION"] = "Facção desconhecida"
L["REP_API_UNAVAILABLE_TITLE"] = "API de reputação não disponível"
L["REP_API_UNAVAILABLE_DESC"] = "A API C_Reputation não está disponível neste servidor. Este recurso requer WoW 11.0+ (The War Within)."
L["REP_FOOTER_TITLE"] = "Rastreamento de reputação"
L["REP_FOOTER_DESC"] = "As reputações são escaneadas automaticamente no login e quando alteradas. Use o painel de reputação no jogo para ver informações detalhadas e recompensas."
L["REP_CLEARING_CACHE"] = "Limpando cache e recarregando..."
L["REP_LOADING_DATA"] = "Carregando dados de reputação..."
L["REP_MAX"] = "Máx."
L["REP_TIER_FORMAT"] = "Nível %d"
L["ACCOUNT_WIDE_LABEL"] = "Toda a conta"
L["NO_RESULTS"] = "Sem resultados"
L["NO_REP_MATCH"] = "Nenhuma reputação corresponde a '%s'"
L["NO_REP_DATA"] = "Nenhum dado de reputação disponível"
L["REP_SCAN_TIP"] = "As reputações são escaneadas automaticamente. Tente /reload se nada aparecer."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "Reputações de toda a conta (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "Sem reputações de toda a conta"
L["NO_CHARACTER_REPS"] = "Sem reputações de personagem"

-- =============================================
-- Currency Tab
-- =============================================
L["GOLD_LABEL"] = "Ouro"
L["CURRENCY_TITLE"] = "Rastreador de moedas"
L["CURRENCY_SUBTITLE"] = "Rastrear todas as moedas em seus personagens"
L["CURRENCY_DISABLED_TITLE"] = "Rastreamento de moedas"
L["CURRENCY_LOADING_TITLE"] = "Carregando dados de moedas"
L["CURRENCY_SEARCH"] = "Pesquisar moedas..."
L["CURRENCY_HIDE_EMPTY"] = "Ocultar vazias"
L["CURRENCY_SHOW_EMPTY"] = "Mostrar vazias"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "Todas transferíveis entre Bando"
L["CURRENCY_CHARACTER_SPECIFIC"] = "Moedas específicas do personagem"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "Limitação de transferência de moeda"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "A API da Blizzard não suporta transferências automáticas de moedas. Use o quadro de moedas no jogo para transferir manualmente moedas do Bando de Guerra."
L["CURRENCY_UNKNOWN"] = "Moeda desconhecida"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "Remover todos os planos concluídos da sua lista Meus Planos. Isso excluirá todos os planos personalizados concluídos e removerá montarias/mascotes/brinquedos concluídos dos seus planos. Esta ação não pode ser desfeita!"
L["RECIPE_BROWSER_DESC"] = "Abra sua janela de profissão no jogo para navegar receitas.\nO addon escaneará receitas disponíveis quando a janela estiver aberta."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "Fonte: [Conquista %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s já tem um plano semanal do Grande Cofre ativo. Você pode encontrá-lo na categoria 'Meus Planos'."
L["DAILY_PLAN_EXISTS_DESC"] = "%s já tem um plano de missão diária ativo. Você pode encontrá-lo na categoria 'Tarefas diárias'."
L["TRANSMOG_WIP_DESC"] = "O rastreamento de coleção de transmogrificação está atualmente em desenvolvimento.\n\nEste recurso estará disponível em uma atualização futura com\nmelhor desempenho e melhor integração com sistemas de Bando de Guerra."
L["WEEKLY_VAULT_CARD"] = "Cartão do Grande Cofre Semanal"
L["WEEKLY_VAULT_COMPLETE"] = "Cartão do Grande Cofre Semanal - Concluído"
L["UNKNOWN_SOURCE"] = "Fonte desconhecida"
L["DAILY_TASKS_PREFIX"] = "Tarefas diárias - "
L["NO_FOUND_FORMAT"] = "Nenhum %s encontrado"
L["PLANS_COUNT_FORMAT"] = "%d planos"
L["PET_BATTLE_LABEL"] = "Batalha de mascote:"
L["QUEST_LABEL"] = "Missão:"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "Idioma atual:"
L["LANGUAGE_TOOLTIP"] = "O addon usa automaticamente o idioma do seu cliente WoW. Para alterar, atualize as configurações do Battle.net."
L["POPUP_DURATION"] = "Duração do popup"
L["POPUP_POSITION"] = "Posição do popup"
L["SET_POSITION"] = "Definir posição"
L["DRAG_TO_POSITION"] = "Arraste para posicionar\nClique direito para confirmar"
L["RESET_DEFAULT"] = "Restaurar padrão"
L["TEST_POPUP"] = "Testar popup"
L["CUSTOM_COLOR"] = "Cor personalizada"
L["OPEN_COLOR_PICKER"] = "Abrir seletor de cores"
L["COLOR_PICKER_TOOLTIP"] = "Abra o seletor de cores nativo do WoW para escolher uma cor de tema personalizada"
L["PRESET_THEMES"] = "Temas predefinidos"
L["WARBAND_NEXUS_SETTINGS"] = "Configurações do Warband Nexus"
L["NO_OPTIONS"] = "Sem opções"
L["NONE_LABEL"] = NONE or "Nenhum"
L["TAB_FILTERING"] = "Filtragem de abas"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Notificações"
L["SCROLL_SPEED"] = "Velocidade de rolagem"
L["ANCHOR_FORMAT"] = "Âncora: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "Mostrar planejador semanal"
L["LOCK_MINIMAP_ICON"] = "Bloquear ícone do minimapa"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "Exibe a contagem de itens do bando de guerra e do personagem nas dicas de interface (Busca WN)."
L["AUTO_SCAN_ITEMS"] = "Escaneamento automático de itens"
L["LIVE_SYNC"] = "Sincronização ao vivo"
L["BACKPACK_LABEL"] = "Mochila"
L["REAGENT_LABEL"] = "Reagente"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "Módulo desativado"
L["LOADING"] = "Carregando..."
L["PLEASE_WAIT"] = "Aguarde..."
L["RESET_PREFIX"] = "Reset:"
L["TRANSFER_CURRENCY"] = "Transferir moeda"
L["AMOUNT_LABEL"] = "Quantidade:"
L["TO_CHARACTER"] = "Para o personagem:"
L["SELECT_CHARACTER"] = "Selecionar personagem..."
L["CURRENCY_TRANSFER_INFO"] = "A janela de moedas será aberta automaticamente.\nVocê precisará clicar com o botão direito na moeda para transferir manualmente."
L["OK_BUTTON"] = OKAY or "OK"
L["SAVE"] = "Salvar"
L["TITLE_FIELD"] = "Título:"
L["DESCRIPTION_FIELD"] = "Descrição:"
L["CREATE_CUSTOM_PLAN"] = "Criar plano personalizado"
L["REPORT_BUGS"] = "Reporte bugs ou compartilhe sugestões no CurseForge para ajudar a melhorar o addon."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus fornece uma interface centralizada para gerenciar todos os seus personagens, moedas, reputações, itens e progresso PvE em todo o seu Bando de Guerra."
L["CHARACTERS_DESC"] = "Visualize todos os personagens com ouro, nível, iLvl, facção, raça, classe, profissões, pedra-chave e última sessão. Rastreie ou pare de rastrear personagens, marque favoritos."
L["ITEMS_DESC"] = "Pesquise e explore itens em todas as bolsas, bancos e banco de bando. Escaneamento automático ao abrir um banco. Os tooltips mostram quais personagens possuem cada item."
L["STORAGE_DESC"] = "Vista de inventário agregada de todos os personagens — bolsas, banco pessoal e banco de bando combinados em um só lugar."
L["PVE_DESC"] = "Rastreie o Grande Cofre com indicadores de nível, pontuações e chaves Mítica+, afixos, histórico de masmorra e moeda de melhoria em todos os personagens."
L["REPUTATIONS_DESC"] = "Compare o progresso de reputação de todos os personagens. Mostra facções de Toda a Conta vs Específicas com tooltips ao passar para detalhamento por personagem."
L["CURRENCY_DESC"] = "Visualize todas as moedas por expansão. Compare valores entre personagens com tooltips ao passar. Oculte moedas vazias com um clique."
L["PLANS_DESC"] = "Rastreie montarias, mascotes, brinquedos, conquistas e transmog não coletados. Adicione metas, veja fontes de drop e acompanhe contadores de tentativas. Acesso via /wn plan ou ícone do minimapa."
L["STATISTICS_DESC"] = "Visualize pontos de conquista, progresso de coleção de montarias/mascotes/brinquedos/ilusões/títulos, contador de mascotes únicos e estatísticas de uso de bolsas/banco."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "Mítico"
L["DIFFICULTY_HEROIC"] = "Heróico"
L["DIFFICULTY_NORMAL"] = "Normal"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Nível %d"
L["PVP_TYPE"] = "PvP"
L["PREPARING"] = "Preparando"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Estatísticas da conta"
L["STATISTICS_SUBTITLE"] = "Progresso de coleção, ouro e visão geral do armazenamento"
L["MOST_PLAYED"] = "MAIS JOGADOS"
L["PLAYED_DAYS"] = "Dias"
L["PLAYED_HOURS"] = "Horas"
L["PLAYED_MINUTES"] = "Minutos"
L["PLAYED_DAY"] = "Dia"
L["PLAYED_HOUR"] = "Hora"
L["PLAYED_MINUTE"] = "Minuto"
L["MORE_CHARACTERS"] = "personagem a mais"
L["MORE_CHARACTERS_PLURAL"] = "personagens a mais"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "Bem-vindo ao Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "Visão geral do addon"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "Rastreie seus objetivos de coleção"
L["ACTIVE_PLAN_FORMAT"] = "%d plano ativo"
L["ACTIVE_PLANS_FORMAT"] = "%d planos ativos"
L["RESET_LABEL"] = RESET or "Resetar"

-- Plans - Type Names
L["TYPE_MOUNT"] = MOUNT or "Montaria"
L["TYPE_PET"] = PET or "Mascote"
L["TYPE_TOY"] = TOY or "Brinquedo"
L["TYPE_RECIPE"] = "Receita"
L["TYPE_ILLUSION"] = "Ilusão"
L["TYPE_TITLE"] = "Título"
L["TYPE_CUSTOM"] = "Personalizado"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transmogrificação"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Saque"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Missão"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Vendedor"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profissão"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Batalha de Mascote"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Conquista"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "Evento Mundial"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promoção"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "Jogo de Cartas Colecionáveis"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "Loja do Jogo"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "Criado"
L["SOURCE_TYPE_TRADING_POST"] = "Posto Comercial"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "Desconhecido"
L["SOURCE_TYPE_PVP"] = PVP or "JxJ"
L["SOURCE_TYPE_TREASURE"] = "Tesouro"
L["SOURCE_TYPE_PUZZLE"] = "Quebra-cabeça"
L["SOURCE_TYPE_RENOWN"] = "Renome"

-- Plans - Transmog Source Labels (Blizzard TRANSMOG_SOURCE_* Globals)
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Saque de Chefe"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Missão"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Vendedor"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "Saque no Mundo"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Conquista"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Profissão"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "Vendido por"
L["PARSE_CRAFTED"] = "Fabricado"
L["PARSE_ZONE"] = ZONE or "Zona"
L["PARSE_COST"] = "Custo"
L["PARSE_REPUTATION"] = REPUTATION or "Reputação"
L["PARSE_FACTION"] = FACTION or "Facção"
L["PARSE_ARENA"] = ARENA or "Arena"
L["PARSE_DUNGEON"] = DUNGEONS or "Masmorra"
L["PARSE_RAID"] = RAID or "Raide"
L["PARSE_HOLIDAY"] = "Feriado"
L["PARSE_RATED"] = "Ranqueado"
L["PARSE_BATTLEGROUND"] = "Campo de Batalha"
L["PARSE_DISCOVERY"] = "Descoberta"
L["PARSE_CONTAINED_IN"] = "Contido em"
L["PARSE_GARRISON"] = "Guarnição"
L["PARSE_GARRISON_BUILDING"] = "Edifício da Guarnição"
L["PARSE_STORE"] = "Loja"
L["PARSE_ORDER_HALL"] = "Salão da Ordem"
L["PARSE_COVENANT"] = "Pacto"
L["PARSE_FRIENDSHIP"] = "Amizade"
L["PARSE_PARAGON"] = "Paragão"
L["PARSE_MISSION"] = "Missão"
L["PARSE_EXPANSION"] = "Expansão"
L["PARSE_SCENARIO"] = "Cenário"
L["PARSE_CLASS_HALL"] = "Salão da Ordem"
L["PARSE_CAMPAIGN"] = "Campanha"
L["PARSE_EVENT"] = "Evento"
L["PARSE_SPECIAL"] = "Especial"
L["PARSE_BRAWLERS_GUILD"] = "Guilda dos Brigões"
L["PARSE_CHALLENGE_MODE"] = "Modo Desafio"
L["PARSE_MYTHIC_PLUS"] = "Mítica+"
L["PARSE_TIMEWALKING"] = "Caminhada Temporal"
L["PARSE_ISLAND_EXPEDITION"] = "Expedição às Ilhas"
L["PARSE_WARFRONT"] = "Frente de Guerra"
L["PARSE_TORGHAST"] = "Torghast"
L["PARSE_ZERETH_MORTIS"] = "Zereth Mortis"
L["PARSE_HIDDEN"] = "Oculto"
L["PARSE_RARE"] = "Raro"
L["PARSE_WORLD_BOSS"] = "Chefe Mundial"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Saque"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "Da Conquista"
L["FALLBACK_UNKNOWN_PET"] = "Mascote Desconhecido"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "Coleção de mascotes"
L["FALLBACK_TOY_COLLECTION"] = "Coleção de brinquedos"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Coleção de transmogrificação"
L["FALLBACK_PLAYER_TITLE"] = "Título de jogador"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Desconhecido"
L["FALLBACK_ILLUSION_FORMAT"] = "Ilusão %s"
L["SOURCE_ENCHANTING"] = "Encantamento"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "Definir contador de tentativas para:\n%s"
L["RESET_COMPLETED_CONFIRM"] = "Tem certeza de que deseja remover TODOS os planos concluídos?\n\nIsso não pode ser desfeito!"
L["YES_RESET"] = "Sim, resetar"
L["REMOVED_PLANS_FORMAT"] = "%d plano(s) concluído(s) removido(s)."

-- Plans - Buttons
L["ADD_CUSTOM"] = "Adicionar personalizado"
L["ADD_VAULT"] = "Adicionar cofre"
L["ADD_QUEST"] = "Adicionar missão"
L["CREATE_PLAN"] = "Criar plano"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "Diária"
L["QUEST_CAT_WORLD"] = "Mundo"
L["QUEST_CAT_WEEKLY"] = "Semanal"
L["QUEST_CAT_ASSIGNMENT"] = "Tarefa"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Categoria desconhecida"
L["SCANNING_FORMAT"] = "Escaneando %s"
L["CUSTOM_PLAN_SOURCE"] = "Plano personalizado"
L["POINTS_FORMAT"] = "%d Pontos"
L["SOURCE_NOT_AVAILABLE"] = "Informações da fonte não disponíveis"
L["PROGRESS_ON_FORMAT"] = "Você está em %d/%d no progresso"
L["COMPLETED_REQ_FORMAT"] = "Você completou %d de %d requisitos totais"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Midnight"
L["CONTENT_TWW"] = "The War Within"
L["QUEST_TYPE_DAILY"] = "Missões diárias"
L["QUEST_TYPE_DAILY_DESC"] = "Missões diárias regulares de NPCs"
L["QUEST_TYPE_WORLD"] = "Missões mundiais"
L["QUEST_TYPE_WORLD_DESC"] = "Missões mundiais em toda a zona"
L["QUEST_TYPE_WEEKLY"] = "Missões semanais"
L["QUEST_TYPE_WEEKLY_DESC"] = "Missões semanais recorrentes"
L["QUEST_TYPE_ASSIGNMENTS"] = "Tarefas"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "Tarefas e missões especiais"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "Mítica+"
L["RAIDS_LABEL"] = "Raides"

-- PlanCardFactory
L["FACTION_LABEL"] = "Facção:"
L["FRIENDSHIP_LABEL"] = "Amizade"
L["RENOWN_TYPE_LABEL"] = "Renome"
L["ADD_BUTTON"] = "+ Adicionar"
L["ADDED_LABEL"] = "Adicionado"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s de %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Exibir contagens de pilha em itens na visualização de armazenamento"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Exibir a seção Planejador Semanal na aba Personagens"
L["LOCK_MINIMAP_TOOLTIP"] = "Bloquear o ícone do minimapa no lugar (impede arrastar)"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "Mostrar itens nas dicas de interface"
L["AUTO_SCAN_TOOLTIP"] = "Escanear e armazenar em cache itens automaticamente quando você abre bancos ou bolsas"
L["LIVE_SYNC_TOOLTIP"] = "Manter o cache de itens atualizado em tempo real enquanto os bancos estão abertos"
L["SHOW_ILVL_TOOLTIP"] = "Exibir emblemas de nível de item em equipamentos na lista de itens"
L["SCROLL_SPEED_TOOLTIP"] = "Multiplicador para velocidade de rolagem (1.0x = 28 px por passo)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "Ignorar Aba do Banco de Bando de Guerra %d do escaneamento automático"
L["IGNORE_SCAN_FORMAT"] = "Ignorar %s do escaneamento automático"
L["BANK_LABEL"] = BANK or "Banco"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "Ativar notificações"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Interruptor principal para todos os pop-ups de notificação"
L["VAULT_REMINDER"] = "Lembrete do cofre"
L["VAULT_REMINDER_TOOLTIP"] = "Mostrar lembrete quando você tiver recompensas do Grande Cofre Semanal não reivindicadas"
L["LOOT_ALERTS"] = "Alertas de saque"
L["LOOT_ALERTS_TOOLTIP"] = "Interruptor principal de popups de colecionáveis. Desativar oculta todas as notificações de colecionáveis."
L["LOOT_ALERTS_MOUNT"] = "Notificações de montarias"
L["LOOT_ALERTS_MOUNT_TOOLTIP"] = "Mostrar notificação ao coletar uma nova montaria."
L["LOOT_ALERTS_PET"] = "Notificações de mascotes"
L["LOOT_ALERTS_PET_TOOLTIP"] = "Mostrar notificação ao coletar um novo mascote."
L["LOOT_ALERTS_TOY"] = "Notificações de brinquedos"
L["LOOT_ALERTS_TOY_TOOLTIP"] = "Mostrar notificação ao coletar um novo brinquedo."
L["LOOT_ALERTS_TRANSMOG"] = "Notificações de aparência"
L["LOOT_ALERTS_TRANSMOG_TOOLTIP"] = "Mostrar notificação ao coletar uma nova aparência de armadura ou arma."
L["LOOT_ALERTS_ILLUSION"] = "Notificações de ilusões"
L["LOOT_ALERTS_ILLUSION_TOOLTIP"] = "Mostrar notificação ao coletar uma nova ilusão de arma."
L["LOOT_ALERTS_TITLE"] = "Notificações de títulos"
L["LOOT_ALERTS_TITLE_TOOLTIP"] = "Mostrar notificação ao obter um novo título."
L["LOOT_ALERTS_ACHIEVEMENT"] = "Notificações de conquistas"
L["LOOT_ALERTS_ACHIEVEMENT_TOOLTIP"] = "Mostrar notificação ao obter uma nova conquista."
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Ocultar alerta de conquista da Blizzard"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Ocultar o popup de conquista padrão da Blizzard e usar a notificação do Warband Nexus em vez disso"
L["REPUTATION_GAINS"] = "Ganhos de reputação"
L["REPUTATION_GAINS_TOOLTIP"] = "Mostrar mensagens no chat quando você ganhar reputação com facções"
L["CURRENCY_GAINS"] = "Ganhos de moeda"
L["CURRENCY_GAINS_TOOLTIP"] = "Mostrar mensagens no chat quando você ganhar moedas"
L["SCREEN_FLASH_EFFECT"] = "Efeito de Flash na Tela"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Reproduzir um efeito de flash na tela ao obter um novo colecionável (montaria, mascote, brinquedo, etc.)"
L["AUTO_TRY_COUNTER"] = "Contador de Tentativas Automático"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Contar automaticamente as tentativas ao saquear NPCs, raros, chefes, pescar ou abrir recipientes que podem dropar montarias, mascotes ou brinquedos. Mostra a contagem de tentativas no chat quando o colecionável não cai."
L["DURATION_LABEL"] = "Duração"
L["DAYS_LABEL"] = "dias"
L["WEEKS_LABEL"] = "semanas"
L["EXTEND_DURATION"] = "Estender duração"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Arraste o quadro verde para definir a posição do popup. Clique direito para confirmar."
L["POSITION_RESET_MSG"] = "Posição do popup resetada para o padrão (Centro Superior)"
L["POSITION_SAVED_MSG"] = "Posição do popup salva!"
L["TEST_NOTIFICATION_TITLE"] = "Notificação de teste"
L["TEST_NOTIFICATION_MSG"] = "Teste de posição"
L["NOTIFICATION_DEFAULT_TITLE"] = "Notificação"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "Tema e aparência"
L["COLOR_PURPLE"] = "Roxo"
L["COLOR_PURPLE_DESC"] = "Tema roxo clássico (padrão)"
L["COLOR_BLUE"] = "Azul"
L["COLOR_BLUE_DESC"] = "Tema azul frio"
L["COLOR_GREEN"] = "Verde"
L["COLOR_GREEN_DESC"] = "Tema verde natureza"
L["COLOR_RED"] = "Vermelho"
L["COLOR_RED_DESC"] = "Tema vermelho ardente"
L["COLOR_ORANGE"] = "Laranja"
L["COLOR_ORANGE_DESC"] = "Tema laranja quente"
L["COLOR_CYAN"] = "Ciano"
L["COLOR_CYAN_DESC"] = "Tema ciano brilhante"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "Família da fonte"
L["FONT_FAMILY_TOOLTIP"] = "Escolha a fonte usada em toda a interface do addon"
L["FONT_SCALE"] = "Escala da fonte"
L["FONT_SCALE_TOOLTIP"] = "Ajustar o tamanho da fonte em todos os elementos da interface"
L["FONT_SCALE_WARNING"] = "Aviso: Uma escala de fonte maior pode causar estouro de texto em alguns elementos da interface."
L["RESOLUTION_NORMALIZATION"] = "Normalização de resolução"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Ajustar tamanhos de fonte com base na resolução da tela e escala da interface para que o texto permaneça do mesmo tamanho físico em diferentes monitores"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Avançado"

-- =============================================
-- Settings - Module Management
-- =============================================
L["MODULE_MANAGEMENT"] = "Gerenciamento de Módulos"
L["MODULE_MANAGEMENT_DESC"] = "Ativar ou desativar módulos de coleta de dados específicos. Desativar um módulo interromperá suas atualizações de dados e ocultará sua aba da interface."
L["MODULE_CURRENCIES"] = "Moedas"
L["MODULE_CURRENCIES_DESC"] = "Rastrear moedas de toda a conta e específicas do personagem (Ouro, Honra, Conquista, etc.)"
L["MODULE_REPUTATIONS"] = "Reputações"
L["MODULE_REPUTATIONS_DESC"] = "Rastrear o progresso de reputação com facções, níveis de renome e recompensas paragão"
L["MODULE_ITEMS"] = "Itens"
L["MODULE_ITEMS_DESC"] = "Rastrear itens do banco de bando de guerra, funcionalidade de busca e categorias de itens"
L["MODULE_STORAGE"] = "Armazenamento"
L["MODULE_STORAGE_DESC"] = "Rastrear bolsas do personagem, banco pessoal e armazenamento do banco de bando de guerra"
L["MODULE_PVE"] = "PvE"
L["MODULE_PVE_DESC"] = "Rastrear masmorras Mítica+, progresso de raides e recompensas do Grande Cofre"
L["MODULE_PLANS"] = "Planos"
L["MODULE_PLANS_DESC"] = "Rastrear objetivos pessoais para montarias, mascotes, brinquedos, conquistas e tarefas personalizadas"
L["MODULE_PROFESSIONS"] = "Profissões"
L["MODULE_PROFESSIONS_DESC"] = "Rastrear habilidades de profissão, concentração, conhecimento e janela de receitas"
L["PROFESSIONS_DISABLED_TITLE"] = "Profissões"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Nível do item %s"
L["ITEM_NUMBER_FORMAT"] = "Item #%s"
L["CHARACTER_CURRENCIES"] = "Moedas do personagem:"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "Conta global (Bando de guerra) — mesmo saldo em todos os personagens."
L["YOU_MARKER"] = "(Você)"
L["WN_SEARCH"] = "Pesquisa WN"
L["WARBAND_BANK_COLON"] = "Banco de Bando de Guerra:"
L["AND_MORE_FORMAT"] = "... e %d mais"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "Você coletou uma montaria"
L["COLLECTED_PET_MSG"] = "Você coletou um mascote de batalha"
L["COLLECTED_TOY_MSG"] = "Você coletou um brinquedo"
L["COLLECTED_ILLUSION_MSG"] = "Você coletou uma ilusão"
L["COLLECTED_ITEM_MSG"] = "Você recebeu um drop raro"
L["ACHIEVEMENT_COMPLETED_MSG"] = "Conquista concluída!"
L["EARNED_TITLE_MSG"] = "Você ganhou um título"
L["COMPLETED_PLAN_MSG"] = "Você concluiu um plano"
L["DAILY_QUEST_CAT"] = "Missão diária"
L["WORLD_QUEST_CAT"] = "Missão mundial"
L["WEEKLY_QUEST_CAT"] = "Missão semanal"
L["SPECIAL_ASSIGNMENT_CAT"] = "Tarefa especial"
L["DELVE_CAT"] = "Imersão"
L["DUNGEON_CAT"] = "Masmorra"
L["RAID_CAT"] = "Raide"
L["WORLD_CAT"] = "Mundo"
L["ACTIVITY_CAT"] = "Atividade"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Progresso"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Progresso concluído"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Plano do Grande Cofre Semanal - %s"
L["ALL_SLOTS_COMPLETE"] = "Todos os espaços concluídos!"
L["QUEST_COMPLETED_SUFFIX"] = "Concluída"
L["WEEKLY_VAULT_READY"] = "Grande Cofre Semanal pronto!"
L["UNCLAIMED_REWARDS"] = "Você tem recompensas não reivindicadas"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "Ouro total:"
L["CHARACTERS_COLON"] = "Personagens:"
L["LEFT_CLICK_TOGGLE"] = "Clique esquerdo: Alternar janela"
L["RIGHT_CLICK_PLANS"] = "Clique direito: Abrir planos"
L["MINIMAP_SHOWN_MSG"] = "Botão do minimapa mostrado"
L["MINIMAP_HIDDEN_MSG"] = "Botão do minimapa oculto (use /wn minimap para mostrar)"
L["TOGGLE_WINDOW"] = "Alternar janela"
L["SCAN_BANK_MENU"] = "Escanear banco"
L["TRACKING_DISABLED_SCAN_MSG"] = "O rastreamento de personagem está desativado. Ative o rastreamento nas configurações para escanear o banco."
L["SCAN_COMPLETE_MSG"] = "Escaneamento completo!"
L["BANK_NOT_OPEN_MSG"] = "O banco não está aberto"
L["OPTIONS_MENU"] = "Opções"
L["HIDE_MINIMAP_BUTTON"] = "Ocultar botão do minimapa"
L["MENU_UNAVAILABLE_MSG"] = "Menu de clique direito indisponível"
L["USE_COMMANDS_MSG"] = "Use /wn show, /wn options, /wn help"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "Máx"
L["OPEN_AND_GUIDE"] = "Abrir e guiar"
L["FROM_LABEL"] = "De:"
L["AVAILABLE_LABEL"] = "Disponível:"
L["ONLINE_LABEL"] = "(Online)"
L["DATA_SOURCE_TITLE"] = "Informações da fonte de dados"
L["DATA_SOURCE_USING"] = "Esta aba está usando:"
L["DATA_SOURCE_MODERN"] = "Serviço de cache moderno (orientado a eventos)"
L["DATA_SOURCE_LEGACY"] = "Acesso direto ao banco de dados legado"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Precisa migrar para o serviço de cache"
L["GLOBAL_DB_VERSION"] = "Versão do banco de dados global:"

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "Personagens"
L["INFO_TAB_ITEMS"] = "Itens"
L["INFO_TAB_STORAGE"] = "Armazenamento"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "Reputações"
L["INFO_TAB_CURRENCY"] = "Moeda"
L["INFO_TAB_PLANS"] = "Planos"
L["INFO_TAB_STATISTICS"] = "Estatísticas"
L["SPECIAL_THANKS"] = "Agradecimentos especiais"
L["SUPPORTERS_TITLE"] = "Apoiadores"
L["THANK_YOU_MSG"] = "Obrigado por usar o Warband Nexus!"

-- =============================================
-- Changelog (What's New) - v2.1.2
-- =============================================
L["CHANGELOG_V213"] =     "ALTERA??ES:\n- Adicionado sistema de classifica??o.\n- V?rios bugs de interface (UI) corrigidos.\n- Adicionado um bot?o para alternar o Companheiro de Receitas de Profiss?o e sua janela foi movida para a esquerda.\n- Corrigidos problemas de rastreamento de Concentra??o de Profiss?o.\n- Corrigido um problema em que o Contador de Tentativas mostrava incorretamente '1 attempts' imediatamente ap?s encontrar uma recompensa colecion?vel em seu saque.\n- Travamentos de interface e quedas de FPS reduzidos significativamente ao saquear itens ou abrir cont?ineres otimizando a l?gica de rastreamento em segundo plano.\n- Corrigido um bug em que abates de chefes n?o somavam corretamente ?s tentativas de saque para certas montarias (ex. Mecatraje da C?mara de Pedra).\n- As Lixeiras Transbordantes agora verificam corretamente a obten??o de moedas e outros itens.\n\nObrigado pelo seu apoio cont?nuo!\n\nPara relatar problemas ou compartilhar coment?rios, deixe uma mensagem no CurseForge - Warband Nexus."

L["CHANGELOG_V212"] =     "ALTERA??ES:\n- Adicionado sistema de classifica??o.\n- V?rios bugs de interface (UI) corrigidos.\n- Adicionado um bot?o para alternar o Companheiro de Receitas de Profiss?o e sua janela foi movida para a esquerda.\n- Corrigidos problemas de rastreamento de Concentra??o de Profiss?o.\n- Corrigido um problema em que o Contador de Tentativas mostrava incorretamente '1 attempts' imediatamente ap?s encontrar uma recompensa colecion?vel em seu saque.\n- Travamentos de interface e quedas de FPS reduzidos significativamente ao saquear itens ou abrir cont?ineres otimizando a l?gica de rastreamento em segundo plano.\n- Corrigido um bug em que abates de chefes n?o somavam corretamente ?s tentativas de saque para certas montarias (ex. Mecatraje da C?mara de Pedra).\n- As Lixeiras Transbordantes agora verificam corretamente a obten??o de moedas e outros itens.\n\nObrigado pelo seu apoio cont?nuo!\n\nPara relatar problemas ou compartilhar coment?rios, deixe uma mensagem no CurseForge - Warband Nexus."
-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "Confirmar ação"
L["CONFIRM"] = "Confirmar"
L["ENABLE_TRACKING_FORMAT"] = "Ativar rastreamento para |cffffcc00%s|r?"
L["DISABLE_TRACKING_FORMAT"] = "Desativar rastreamento para |cffffcc00%s|r?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "Reputações de toda a conta (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Reputações baseadas em personagem (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "Recompensa aguardando"
L["REP_PARAGON_LABEL"] = "Paragão"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "Preparando..."
L["REP_LOADING_INITIALIZING"] = "Inicializando..."
L["REP_LOADING_FETCHING"] = "Carregando dados de reputação..."
L["REP_LOADING_PROCESSING"] = "Processando %d facções..."
L["REP_LOADING_PROCESSING_COUNT"] = "Processando... (%d/%d)"
L["REP_LOADING_SAVING"] = "Salvando no banco de dados..."
L["REP_LOADING_COMPLETE"] = "Completo!"

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "Não é possível abrir a janela durante o combate. Por favor, tente novamente após o combate terminar."
L["BANK_IS_ACTIVE"] = "Banco está ativo"
L["ITEMS_CACHED_FORMAT"] = "%d itens em cache"
-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "PERSONAGEM"
L["TABLE_HEADER_LEVEL"] = "NÍVEL"
L["TABLE_HEADER_GOLD"] = "OURO"
L["TABLE_HEADER_LAST_SEEN"] = "VISTO POR ÚLTIMO"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "Nenhum item corresponde a '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "Nenhum item corresponde à sua pesquisa"
L["ITEMS_SCAN_HINT"] = "Os itens são escaneados automaticamente. Tente /reload se nada aparecer."
L["ITEMS_WARBAND_BANK_HINT"] = "Abra o banco de Bando de Guerra para escanear itens (escaneado automaticamente na primeira visita)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Próximos passos:"
L["CURRENCY_TRANSFER_STEP_1"] = "Encontre |cffffffff%s|r na janela de moedas"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800Clique com o botão direito|r nele"
L["CURRENCY_TRANSFER_STEP_3"] = "Selecione |cffffffff'Transferir para Bando de Guerra'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Escolha |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Insira a quantidade: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "A janela de moedas está aberta agora!"
L["CURRENCY_TRANSFER_SECURITY"] = "(A segurança da Blizzard impede transferência automática)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "Zona: "
L["ADDED"] = "Adicionado"
L["WEEKLY_VAULT_TRACKER"] = "Rastreador do Grande Cofre Semanal"
L["DAILY_QUEST_TRACKER"] = "Rastreador de missões diárias"
L["CUSTOM_PLAN_STATUS"] = "Plano personalizado '%s' %s"

-- =============================================
-- Achievement Popup
-- =============================================
L["ACHIEVEMENT_COMPLETED"] = "Concluído"
L["ACHIEVEMENT_NOT_COMPLETED"] = "Não concluído"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d pts"
L["ADD_PLAN"] = "Adicionar"
L["PLANNED"] = "Planejado"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = "Masmorra"
L["VAULT_SLOT_RAIDS"] = "Raides"
L["VAULT_SLOT_WORLD"] = "Mundo"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "Afixo"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_STANDING_LABEL"] = "Agora"
L["CHAT_GAINED_PREFIX"] = "+"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "Plano concluído: "
L["WEEKLY_VAULT_PLAN_NAME"] = "Grande Cofre Semanal - %s"
L["VAULT_PLANS_RESET"] = "Os planos do Grande Cofre Semanal foram resetados! (%d plano%s)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "Nenhum personagem encontrado"
L["EMPTY_CHARACTERS_DESC"] = "Faça login com seus personagens para começar a rastreá-los.\nOs dados são coletados automaticamente a cada login."
L["EMPTY_ITEMS_TITLE"] = "Nenhum item em cache"
L["EMPTY_ITEMS_DESC"] = "Abra seu Banco de Bando de Guerra ou banco pessoal para escanear itens.\nOs itens são armazenados automaticamente na primeira visita."
L["EMPTY_STORAGE_TITLE"] = "Sem dados de armazenamento"
L["EMPTY_STORAGE_DESC"] = "Os itens são escaneados ao abrir bancos ou bolsas.\nVisite um banco para começar a rastrear seu armazenamento."
L["EMPTY_PLANS_TITLE"] = "Nenhum plano ainda"
L["EMPTY_PLANS_DESC"] = "Navegue por montarias, mascotes, brinquedos ou conquistas acima\npara adicionar metas de coleção e acompanhar seu progresso."
L["EMPTY_REPUTATION_TITLE"] = "Sem dados de reputação"
L["EMPTY_REPUTATION_DESC"] = "As reputações são escaneadas automaticamente no login.\nFaça login com um personagem para rastrear facções."
L["EMPTY_CURRENCY_TITLE"] = "Sem dados de moeda"
L["EMPTY_CURRENCY_DESC"] = "As moedas são rastreadas automaticamente em todos os personagens.\nFaça login com um personagem para rastrear moedas."
L["EMPTY_PVE_TITLE"] = "Sem dados de PvE"
L["EMPTY_PVE_DESC"] = "O progresso PvE é rastreado quando você faz login com personagens.\nGrande Cofre, Mítica+ e bloqueios de raide aparecerão aqui."
L["EMPTY_STATISTICS_TITLE"] = "Sem estatísticas disponíveis"
L["EMPTY_STATISTICS_DESC"] = "As estatísticas são coletadas dos seus personagens rastreados.\nFaça login com um personagem para coletar dados."
L["NO_ADDITIONAL_INFO"] = "Sem informações adicionais"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "Deseja rastrear este personagem?"
L["CLEANUP_NO_INACTIVE"] = "Nenhum personagem inativo encontrado (90+ dias)"
L["CLEANUP_REMOVED_FORMAT"] = "Removidos %d personagem(ns) inativo(s)"
L["TRACKING_ENABLED_MSG"] = "Rastreamento de personagem ATIVADO!"
L["TRACKING_DISABLED_MSG"] = "Rastreamento de personagem DESATIVADO!"
L["TRACKING_ENABLED"] = "Rastreamento ATIVADO"
L["TRACKING_DISABLED"] = "Rastreamento DESATIVADO (modo somente leitura)"
L["STATUS_LABEL"] = "Status:"
L["ERROR_LABEL"] = "Erro:"
L["ERROR_NAME_REALM_REQUIRED"] = "Nome do personagem e reino necessários"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s já tem um plano semanal ativo"

-- Profiles (AceDB)
L["PROFILES"] = "Perfis"
L["PROFILES_DESC"] = "Gerenciar perfis do addon"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "Nenhum critério encontrado"
L["NO_REQUIREMENTS_INSTANT"] = "Sem requisitos (conclusão instantânea)"

-- Statistics Tab (missing)
L["TOTAL_PETS"] = "Total de Mascotes"

-- Items Tab (missing)
L["ITEM_LOADING_NAME"] = "Carregando..."

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
L["TAB_PROFESSIONS"] = "Profissões"
L["YOUR_PROFESSIONS"] = "Profissões do Bando de Guerra"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s personagens com profissões"
L["HEADER_PROFESSIONS"] = "Visão Geral das Profissões"
L["NO_PROFESSIONS_DATA"] = "Nenhum dado de profissão disponível ainda. Abra a janela de profissão (padrão: K) em cada personagem para coletar dados."
L["CONCENTRATION"] = "Concentração"
L["KNOWLEDGE"] = "Conhecimento"
L["SKILL"] = "Habilidade"
L["RECIPES"] = "Receitas"
L["UNSPENT_POINTS"] = "Pontos não gastos"
L["COLLECTIBLE"] = "Colecionável"
L["RECHARGE"] = "Recarga"
L["FULL"] = "Cheio"
L["PROF_OPEN_RECIPE"] = "Abrir"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "Abrir a lista de receitas desta profissão"
L["PROF_ONLY_CURRENT_CHAR"] = "Disponível apenas para o personagem atual"
L["NO_PROFESSION"] = "Sem Profissão"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "1ª Fabricação"
L["SKILL_UPS"] = "Ganhos de Habilidade"
L["COOLDOWNS"] = "Recargas"
L["ORDERS"] = "Pedidos"

-- Professions: Tooltips & Details
L["LEARNED_RECIPES"] = "Receitas Aprendidas"
L["UNLEARNED_RECIPES"] = "Receitas Não Aprendidas"
L["LAST_SCANNED"] = "Último Escaneamento"
L["JUST_NOW"] = "Agora mesmo"
L["RECIPE_NO_DATA"] = "Abra a janela de profissão para coletar dados de receitas"
L["FIRST_CRAFT_AVAILABLE"] = "Primeiras Fabricações Disponíveis"
L["FIRST_CRAFT_DESC"] = "Receitas que concedem XP bônus na primeira fabricação"
L["SKILLUP_RECIPES"] = "Receitas de Ganho de Habilidade"
L["SKILLUP_DESC"] = "Receitas que ainda podem aumentar seu nível de habilidade"
L["NO_ACTIVE_COOLDOWNS"] = "Nenhuma recarga ativa"

-- Professions: Crafting Orders
L["CRAFTING_ORDERS"] = "Pedidos de Fabricação"
L["PERSONAL_ORDERS"] = "Pedidos Pessoais"
L["PUBLIC_ORDERS"] = "Pedidos Públicos"
L["CLAIMS_REMAINING"] = "Reivindicações Restantes"
L["NO_ACTIVE_ORDERS"] = "Nenhum pedido ativo"
L["ORDER_NO_DATA"] = "Abra a profissão na mesa de fabricação para escanear"

-- Professions: Equipment
L["EQUIPMENT"] = "Equipamento"
L["TOOL"] = "Ferramenta"
L["ACCESSORY"] = "Acessório"

-- =============================================
-- New keys (v2.1.0)
-- =============================================
L["TOOLTIP_ATTEMPTS"] = "tentativas"
L["TOOLTIP_100_DROP"] = "100%% Drop"
L["TOOLTIP_UNKNOWN"] = "Desconhecido"
L["TOOLTIP_WARBAND_BANK"] = "Banco de Bando de Guerra"
L["TOOLTIP_HOLD_SHIFT"] = "  Segure [Shift] para lista completa"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - Concentração"
L["TOOLTIP_FULL"] = "(Cheio)"
L["NO_ITEMS_CACHED_TITLE"] = "Nenhum item em cache"
L["COMBAT_CURRENCY_ERROR"] = "Não é possível abrir o painel de moedas durante o combate. Tente novamente após o combate."
L["DB_LABEL"] = "DB:"
L["COLLECTING_PVE"] = "Coletando dados PvE"
L["PVE_PREPARING"] = "Preparando"
L["PVE_GREAT_VAULT"] = "Grande Cofre"
L["PVE_MYTHIC_SCORES"] = "Pontuações Mítica+"
L["PVE_RAID_LOCKOUTS"] = "Bloqueios de Raide"
L["PVE_INCOMPLETE_DATA"] = "Alguns dados podem estar incompletos. Tente atualizar mais tarde."
L["VAULT_SLOTS_TO_FILL"] = "%d espaço%s do Grande Cofre para preencher"
L["VAULT_SLOT_PLURAL"] = "s"
L["REP_RENOWN_NEXT"] = "Renome %d"
L["REP_TO_NEXT_FORMAT"] = "%s rep até %s (%s)"
L["REP_FACTION_FALLBACK"] = "Facção"
L["COLLECTION_CANCELLED"] = "Coleta cancelada pelo usuário"
L["CLEANUP_STALE_FORMAT"] = "Removidos %d personagem(ns) obsoleto(s)"
L["PERSONAL_BANK"] = "Banco pessoal"
L["WARBAND_BANK_LABEL"] = "Banco de Bando de Guerra"
L["WARBAND_BANK_TAB_FORMAT"] = "Aba %d"
L["CURRENCY_OTHER"] = "Outro"
L["ERROR_SAVING_CHARACTER"] = "Erro ao salvar personagem:"
L["STANDING_HATED"] = "Odiado"
L["STANDING_HOSTILE"] = "Hostil"
L["STANDING_UNFRIENDLY"] = "Antipático"
L["STANDING_NEUTRAL"] = "Neutro"
L["STANDING_FRIENDLY"] = "Amigável"
L["STANDING_HONORED"] = "Honrado"
L["STANDING_REVERED"] = "Reverenciado"
L["STANDING_EXALTED"] = "Exaltado"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d tentativas para %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "Obtido %s! Contador de tentativas resetado."
L["TRYCOUNTER_CAUGHT_RESET"] = "Capturado %s! Contador de tentativas resetado."
L["TRYCOUNTER_CONTAINER_RESET"] = "Obtido %s do recipiente! Contador de tentativas resetado."
L["TRYCOUNTER_LOCKOUT_SKIP"] = "Ignorado: bloqueio diário/semanal ativo para este NPC."
L["TRYCOUNTER_INSTANCE_DROPS"] = "Colecionáveis nesta instância:"
L["TRYCOUNTER_COLLECTED_TAG"] = "(Coletado)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " tentativas"
L["TRYCOUNTER_TYPE_MOUNT"] = "Montaria"
L["TRYCOUNTER_TYPE_PET"] = "Mascote"
L["TRYCOUNTER_TYPE_TOY"] = "Brinquedo"
L["TRYCOUNTER_TYPE_ITEM"] = "Item"
L["TRYCOUNTER_TRY_COUNTS"] = "Contadores de tentativas"
L["LT_CHARACTER_DATA"] = "Dados do personagem"
L["LT_CURRENCY_CACHES"] = "Moedas e cache"
L["LT_REPUTATIONS"] = "Reputações"
L["LT_PROFESSIONS"] = "Profissões"
L["LT_PVE_DATA"] = "Dados PvE"
L["LT_COLLECTIONS"] = "Coleções"
L["CONFIG_HEADER"] = "Warband Nexus"
L["CONFIG_HEADER_DESC"] = "Gerenciamento moderno do Bando de Guerra e rastreamento entre personagens."
L["CONFIG_GENERAL"] = "Configurações gerais"
L["CONFIG_GENERAL_DESC"] = "Configurações básicas do addon e opções de comportamento."
L["CONFIG_ENABLE"] = "Ativar addon"
L["CONFIG_ENABLE_DESC"] = "Ligar ou desligar o addon."
L["CONFIG_MINIMAP"] = "Botão do minimapa"
L["CONFIG_MINIMAP_DESC"] = "Mostrar um botão no minimapa para acesso rápido."
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "Mostrar itens nas dicas"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "Exibir contagem de itens do Bando de Guerra e do personagem nas dicas de itens."
L["CONFIG_MODULES"] = "Gerenciamento de módulos"
L["CONFIG_MODULES_DESC"] = "Ativar ou desativar módulos individuais do addon. Módulos desativados não coletarão dados nem exibirão abas na interface."
L["CONFIG_MOD_CURRENCIES"] = "Moedas"
L["CONFIG_MOD_CURRENCIES_DESC"] = "Rastrear moedas em todos os personagens."
L["CONFIG_MOD_REPUTATIONS"] = "Reputações"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "Rastrear reputações em todos os personagens."
L["CONFIG_MOD_ITEMS"] = "Itens"
L["CONFIG_MOD_ITEMS_DESC"] = "Rastrear itens em bolsas e bancos."
L["CONFIG_MOD_STORAGE"] = "Armazenamento"
L["CONFIG_MOD_STORAGE_DESC"] = "Aba de armazenamento para inventário e gerenciamento de banco."
L["CONFIG_MOD_PVE"] = "PvE"
L["CONFIG_MOD_PVE_DESC"] = "Rastrear Grande Cofre, Mítica+ e bloqueios de raide."
L["CONFIG_MOD_PLANS"] = "Planos"
L["CONFIG_MOD_PLANS_DESC"] = "Rastreamento de planos de coleção e metas de conclusão."
L["CONFIG_MOD_PROFESSIONS"] = "Profissões"
L["CONFIG_MOD_PROFESSIONS_DESC"] = "Rastrear habilidades de profissão, receitas e concentração."
L["CONFIG_AUTOMATION"] = "Automação"
L["CONFIG_AUTOMATION_DESC"] = "Controlar o que acontece automaticamente ao abrir seu Banco de Bando de Guerra."
L["CONFIG_AUTO_OPTIMIZE"] = "Otimização automática do banco de dados"
L["CONFIG_AUTO_OPTIMIZE_DESC"] = "Otimizar automaticamente o banco de dados no login para manter o armazenamento eficiente."
L["CONFIG_SHOW_ITEM_COUNT"] = "Mostrar quantidade de itens"
L["CONFIG_SHOW_ITEM_COUNT_DESC"] = "Exibir dicas com a quantidade de cada item que você tem em todos os personagens."
L["CONFIG_THEME_COLOR"] = "Cor do tema principal"
L["CONFIG_THEME_COLOR_DESC"] = "Escolher a cor de destaque principal para a interface do addon."
L["CONFIG_THEME_PRESETS"] = "Temas predefinidos"
L["CONFIG_THEME_APPLIED"] = "Tema %s aplicado!"
L["CONFIG_THEME_RESET_DESC"] = "Redefinir todas as cores do tema para o roxo padrão."
L["CONFIG_NOTIFICATIONS"] = "Notificações"
L["CONFIG_NOTIFICATIONS_DESC"] = "Configurar quais notificações aparecem."
L["CONFIG_ENABLE_NOTIFICATIONS"] = "Ativar notificações"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "Mostrar notificações popup para eventos de colecionáveis."
L["CONFIG_NOTIFY_MOUNTS"] = "Notificações de montarias"
L["CONFIG_NOTIFY_MOUNTS_DESC"] = "Mostrar notificações ao aprender uma nova montaria."
L["CONFIG_NOTIFY_PETS"] = "Notificações de mascotes"
L["CONFIG_NOTIFY_PETS_DESC"] = "Mostrar notificações ao aprender um novo mascote."
L["CONFIG_NOTIFY_TOYS"] = "Notificações de brinquedos"
L["CONFIG_NOTIFY_TOYS_DESC"] = "Mostrar notificações ao aprender um novo brinquedo."
L["CONFIG_NOTIFY_ACHIEVEMENTS"] = "Notificações de conquistas"
L["CONFIG_NOTIFY_ACHIEVEMENTS_DESC"] = "Mostrar notificações ao ganhar uma conquista."
L["CONFIG_SHOW_UPDATE_NOTES"] = "Mostrar notas de atualização novamente"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "Exibir a janela Novidades no próximo login."
L["CONFIG_UPDATE_NOTES_SHOWN"] = "A notificação de atualização será exibida no próximo login."
L["CONFIG_RESET_PLANS"] = "Resetar planos concluídos"
L["CONFIG_RESET_PLANS_CONFIRM"] = "Isso removerá todos os planos concluídos. Continuar?"
L["CONFIG_RESET_PLANS_FORMAT"] = "Removidos %d plano(s) concluído(s)."
L["CONFIG_NO_COMPLETED_PLANS"] = "Nenhum plano concluído para remover."
L["CONFIG_TAB_FILTERING"] = "Filtragem de abas"
L["CONFIG_TAB_FILTERING_DESC"] = "Escolher quais abas são visíveis na janela principal."
L["CONFIG_CHARACTER_MGMT"] = "Gerenciamento de personagens"
L["CONFIG_CHARACTER_MGMT_DESC"] = "Gerenciar personagens rastreados e remover dados antigos."
L["CONFIG_DELETE_CHAR"] = "Excluir dados do personagem"
L["CONFIG_DELETE_CHAR_DESC"] = "Remover permanentemente todos os dados armazenados do personagem selecionado."
L["CONFIG_DELETE_CONFIRM"] = "Tem certeza de que deseja excluir permanentemente todos os dados deste personagem? Isso não pode ser desfeito."
L["CONFIG_DELETE_SUCCESS"] = "Dados do personagem excluídos:"
L["CONFIG_DELETE_FAILED"] = "Dados do personagem não encontrados."
L["CONFIG_FONT_SCALING"] = "Fonte e escala"
L["CONFIG_FONT_SCALING_DESC"] = "Ajustar família e tamanho da fonte."
L["CONFIG_FONT_FAMILY"] = "Família da fonte"
L["CONFIG_FONT_SIZE"] = "Escala do tamanho da fonte"
L["CONFIG_FONT_PREVIEW"] = "Visualização: The quick brown fox jumps over the lazy dog"
L["CONFIG_ADVANCED"] = "Avançado"
L["CONFIG_ADVANCED_DESC"] = "Configurações avançadas e gerenciamento do banco de dados. Use com cautela!"
L["CONFIG_DEBUG_MODE"] = "Modo de depuração"
L["CONFIG_DEBUG_MODE_DESC"] = "Ativar registro detalhado para depuração. Ative apenas para solução de problemas."
L["CONFIG_DB_STATS"] = "Mostrar estatísticas do banco de dados"
L["CONFIG_DB_STATS_DESC"] = "Exibir tamanho atual do banco de dados e estatísticas de otimização."
L["CONFIG_DB_OPTIMIZER_NA"] = "Otimizador do banco de dados não carregado"
L["CONFIG_OPTIMIZE_NOW"] = "Otimizar banco de dados agora"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "Executar o otimizador do banco de dados para limpar e comprimir dados armazenados."
L["CONFIG_COMMANDS_HEADER"] = "Comandos slash"
L["DISPLAY_SETTINGS"] = "Exibição"
L["DISPLAY_SETTINGS_DESC"] = "Personalizar como itens e informações são exibidos."
L["RESET_DEFAULT"] = "Restaurar padrão"
L["ANTI_ALIASING"] = "Anti-serrilhado"

L["PROFESSIONS_INFO_DESC"] = "Acompanhe habilidades de profissão, concentração, conhecimento e árvores de especialização em todos os personagens. Inclui Recipe Companion para fontes de reagentes."
L["CONTRIBUTORS_TITLE"] = "Contribuidores"
L["ANTI_ALIASING_DESC"] = "Estilo de renderização das bordas da fonte (afeta a legibilidade)"

-- =============================================
-- Recipe Companion
-- =============================================
L["RECIPE_COMPANION_TITLE"] = "Companheiro de Receitas"
L["TOGGLE_TRACKER"] = "Alternar Rastreador"

-- =============================================
-- Sorting
-- =============================================
L["SORT_BY_LABEL"] = "Ordenar por:"
L["SORT_MODE_MANUAL"] = "Manual (Ordem Personalizada)"
L["SORT_MODE_NAME"] = "Nome (A-Z)"
L["SORT_MODE_LEVEL"] = "Nível (Maior)"
L["SORT_MODE_ILVL"] = "Nível de Item (Maior)"
L["SORT_MODE_GOLD"] = "Ouro (Maior)"

-- =============================================
-- Gold Management
-- =============================================
L["GOLD_MANAGER_BTN"] = "Meta de Ouro"
L["GOLD_MANAGEMENT_TITLE"] = "Meta de Ouro"
L["GOLD_MANAGEMENT_ENABLE"] = "Enable Gold Management"
L["GOLD_MANAGEMENT_MODE"] = "Management Mode"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "Deposit Only"
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "Withdraw Only"
L["GOLD_MANAGEMENT_MODE_BOTH"] = "Ambos"
L["GOLD_MANAGEMENT_TARGET"] = "Target Gold Amount"
L["GOLD_MANAGEMENT_GOLD_LABEL"] = "gold"
L["GOLD_MANAGEMENT_NOTIFICATION_DEPOSIT"] = "Deposit %s to warband bank (you have %s)"
L["GOLD_MANAGEMENT_NOTIFICATION_WITHDRAW"] = "Withdraw %s from warband bank (you have %s)"
L["GOLD_MANAGEMENT_DESC"] = "Configure automatic gold management. Both deposits and withdrawals are performed automatically when the bank is open using C_Bank API."
L["GOLD_MANAGEMENT_WARNING"] = "|cff44ff44Fully Automatic:|r Both gold deposits and withdrawals are performed automatically when the bank is open. Set your target amount and let the addon manage your gold!"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "If you have more than X gold, excess will be automatically deposited to warband bank."
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "If you have less than X gold, the difference will be automatically withdrawn from warband bank."
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "Automatically maintain exactly X gold on your character (deposit if over, withdraw if under)."
L["GOLD_MANAGEMENT_HELPER"] = "Enter the amount of gold you want to keep on this character. The addon will automatically manage your gold when you open the bank."
L["GOLD_MANAGEMENT_WITHDRAWN"] = "Withdrawn %s from warband bank"
L["GOLD_MANAGEMENT_DEPOSITED"] = "Deposited %s to warband bank"
