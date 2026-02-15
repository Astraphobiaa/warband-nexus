--[[
    Warband Nexus - French Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "frFR")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus chargé. Tapez /wn ou /warbandnexus pour les options."
L["VERSION"] = GAME_VERSION_LABEL or "Version"

-- Slash Commands
L["SLASH_HELP"] = "Commandes disponibles :"
L["SLASH_OPTIONS"] = "Ouvrir le panneau d'options"
L["SLASH_SCAN"] = "Scanner la banque de bataillon"
L["SLASH_SHOW"] = "Afficher/masquer la fenêtre principale"
L["SLASH_DEPOSIT"] = "Ouvrir la file de dépôt"
L["SLASH_SEARCH"] = "Rechercher un objet"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Paramètres généraux"
L["GENERAL_SETTINGS_DESC"] = "Configurer le comportement général de l'addon"
L["ENABLE_ADDON"] = "Activer l'addon"
L["ENABLE_ADDON_DESC"] = "Activer ou désactiver les fonctionnalités de Warband Nexus"
L["MINIMAP_ICON"] = "Afficher l'icône de la minicarte"
L["MINIMAP_ICON_DESC"] = "Afficher ou masquer le bouton de la minicarte"
L["DEBUG_MODE"] = "Mode débogage"
L["DEBUG_MODE_DESC"] = "Activer les messages de débogage dans le chat"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "Paramètres d'analyse"
L["SCANNING_SETTINGS_DESC"] = "Configurer le comportement d'analyse de la banque"
L["AUTO_SCAN"] = "Analyse automatique à l'ouverture"
L["AUTO_SCAN_DESC"] = "Analyser automatiquement la banque de bataillon à l'ouverture"
L["SCAN_DELAY"] = "Délai d'analyse"
L["SCAN_DELAY_DESC"] = "Délai entre les opérations d'analyse (en secondes)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "Paramètres de dépôt"
L["DEPOSIT_SETTINGS_DESC"] = "Configurer le comportement de dépôt des objets"
L["GOLD_RESERVE"] = "Réserve d'or"
L["GOLD_RESERVE_DESC"] = "Or minimum à conserver dans l'inventaire personnel (en or)"
L["AUTO_DEPOSIT_REAGENTS"] = "Dépôt automatique des réactifs"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "Mettre les réactifs en file de dépôt à l'ouverture de la banque"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Paramètres d'affichage"
L["DISPLAY_SETTINGS_DESC"] = "Configurer l'apparence visuelle"
L["SHOW_ITEM_LEVEL"] = "Afficher le niveau d'objet"
L["SHOW_ITEM_LEVEL_DESC"] = "Afficher le niveau d'objet sur l'équipement"
L["SHOW_ITEM_COUNT"] = "Afficher le nombre d'objets"
L["SHOW_ITEM_COUNT_DESC"] = "Afficher les quantités empilées sur les objets"
L["HIGHLIGHT_QUALITY"] = "Surligner par qualité"
L["HIGHLIGHT_QUALITY_DESC"] = "Ajouter des bordures colorées selon la qualité des objets"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "Paramètres des onglets"
L["TAB_SETTINGS_DESC"] = "Configurer le comportement des onglets de la banque"
L["IGNORED_TABS"] = "Onglets ignorés"
L["IGNORED_TABS_DESC"] = "Sélectionner les onglets à exclure de l'analyse et des opérations"
L["TAB_1"] = "Onglet de  bataillon 1"
L["TAB_2"] = "Onglet de  bataillon 2"
L["TAB_3"] = "Onglet de  bataillon 3"
L["TAB_4"] = "Onglet de  bataillon 4"
L["TAB_5"] = "Onglet de  bataillon 5"

-- Scanner Module
L["SCAN_STARTED"] = "Analyse de la banque de bataillon..."
L["SCAN_COMPLETE"] = "Analyse terminée. %d objets trouvés dans %d emplacements."
L["SCAN_FAILED"] = "Échec de l'analyse : La banque de bataillon n'est pas ouverte."
L["SCAN_TAB"] = "Analyse de l'onglet %d..."
L["CACHE_CLEARED"] = "Cache d'objets vidé."
L["CACHE_UPDATED"] = "Cache d'objets mis à jour."

-- Banker Module
L["BANK_NOT_OPEN"] = "La banque de bataillon n'est pas ouverte."
L["DEPOSIT_STARTED"] = "Début de l'opération de dépôt..."
L["DEPOSIT_COMPLETE"] = "Dépôt terminé. %d objets transférés."
L["DEPOSIT_CANCELLED"] = "Dépôt annulé."
L["DEPOSIT_QUEUE_EMPTY"] = "La file de dépôt est vide."
L["DEPOSIT_QUEUE_CLEARED"] = "File de dépôt vidée."
L["ITEM_QUEUED"] = "%s mis en file de dépôt."
L["ITEM_REMOVED"] = "%s retiré de la file."
L["GOLD_DEPOSITED"] = "%s or déposé dans la banque de bataillon."
L["INSUFFICIENT_GOLD"] = "Or insuffisant pour le dépôt."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "Montant invalide."
L["WITHDRAW_BANK_NOT_OPEN"] = "La banque doit être ouverte pour retirer !"
L["WITHDRAW_IN_COMBAT"] = "Impossible de retirer en combat."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "Pas assez d'or dans la banque de bataillon."
L["WITHDRAWN_LABEL"] = "Retiré :"
L["WITHDRAW_API_UNAVAILABLE"] = "API de retrait non disponible."
L["SORT_IN_COMBAT"] = "Impossible de trier en combat."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global
L["SEARCH_CATEGORY_FORMAT"] = "Rechercher %s..."
L["BTN_SCAN"] = "Analyser la banque"
L["BTN_DEPOSIT"] = "File de dépôt"
L["BTN_SORT"] = "Trier la banque"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "Vider la file"
L["BTN_DEPOSIT_ALL"] = "Tout déposer"
L["BTN_DEPOSIT_GOLD"] = "Déposer l'or"
L["ENABLE"] = ENABLE or "Activer" -- Blizzard Global
L["ENABLE_MODULE"] = "Activer le module"

-- Main Tabs (Blizzard Globals where available)
L["TAB_CHARACTERS"] = CHARACTER or "Personnages" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "Objets" -- Blizzard Global
L["TAB_STORAGE"] = "Stockage"
L["TAB_PLANS"] = "Plans"
L["TAB_REPUTATION"] = REPUTATION or "Réputation" -- Blizzard Global
L["TAB_REPUTATIONS"] = "Réputations"
L["TAB_CURRENCY"] = CURRENCY or "Devises" -- Blizzard Global
L["TAB_CURRENCIES"] = "Devises"
L["TAB_PVE"] = "JcE"
L["TAB_STATISTICS"] = STATISTICS or "Statistiques" -- Blizzard Global

-- Item Categories (Using Blizzard Globals where available)
L["CATEGORY_ALL"] = ALL or "Tous les objets" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Équipement" -- Blizzard Global
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consommables" -- Blizzard Global
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Réactifs" -- Blizzard Global
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Marchandises" -- Blizzard Global
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Objets de quête" -- Blizzard Global
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Divers" -- Blizzard Global

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
L["HEADER_FAVORITES"] = FAVORITES or "Favoris" -- Blizzard Global
L["HEADER_CHARACTERS"] = CHARACTER or "Personnages"
L["HEADER_CURRENT_CHARACTER"] = "PERSONNAGE ACTUEL"
L["HEADER_WARBAND_GOLD"] = "OR DU BATAILLON"
L["HEADER_TOTAL_GOLD"] = "OR TOTAL"
L["HEADER_REALM_GOLD"] = "OR DU ROYAUME"
L["HEADER_REALM_TOTAL"] = "TOTAL DU ROYAUME"
L["CHARACTER_LAST_SEEN_FORMAT"] = "Vu pour la dernière fois : %s"
L["CHARACTER_GOLD_FORMAT"] = "Or : %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "Or combiné de tous les personnages sur ce royaume"

-- Items Tab
L["ITEMS_HEADER"] = "Objets de banque"
L["ITEMS_HEADER_DESC"] = "Parcourir et gérer votre banque de bataillon et personnelle"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " objets..."
L["ITEMS_WARBAND_BANK"] = "Banque de bataillon"
L["ITEMS_PLAYER_BANK"] = BANK or "Banque personnelle" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Banque de guilde" -- Blizzard Global
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Équipement"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consommables"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Réactifs"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Marchandises"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quête"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Divers"
L["GROUP_CONTAINER"] = "Conteneurs"

-- Storage Tab
L["STORAGE_HEADER"] = "Navigateur de stockage"
L["STORAGE_HEADER_DESC"] = "Parcourir tous les objets organisés par type"
L["STORAGE_WARBAND_BANK"] = "Banque de bataillon"
L["STORAGE_PERSONAL_BANKS"] = "Banques personnelles"
L["STORAGE_TOTAL_SLOTS"] = "Emplacements totaux"
L["STORAGE_FREE_SLOTS"] = "Emplacements libres"
L["STORAGE_BAG_HEADER"] = "Sacs de bataillon"
L["STORAGE_PERSONAL_HEADER"] = "Banque personnelle"

-- Plans Tab
L["PLANS_MY_PLANS"] = "Mes plans"
L["PLANS_COLLECTIONS"] = "Plans de collection"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "Ajouter un plan personnalisé"
L["PLANS_NO_RESULTS"] = "Aucun résultat trouvé."
L["PLANS_ALL_COLLECTED"] = "Tous les objets collectés !"
L["PLANS_RECIPE_HELP"] = "Clic droit sur les recettes dans votre inventaire pour les ajouter ici."
L["COLLECTION_PLANS"] = "Plans de collection"
L["SEARCH_PLANS"] = "Rechercher des plans..."
L["COMPLETED_PLANS"] = "Plans terminés"
L["SHOW_COMPLETED"] = "Afficher terminés"

-- Plans Categories (Blizzard Globals where available)
L["CATEGORY_MY_PLANS"] = "Mes plans"
L["CATEGORY_DAILY_TASKS"] = "Tâches quotidiennes"
L["CATEGORY_MOUNTS"] = MOUNTS or "Montures" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "Mascottes" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "Jouets" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmogrification" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "Illusions"
L["CATEGORY_TITLES"] = TITLES or "Titres"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Hauts faits" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " réputation..."
L["REP_HEADER_WARBAND"] = "Réputation du bataillon"
L["REP_HEADER_CHARACTER"] = "Réputation du personnage"
L["REP_STANDING_FORMAT"] = "Rang : %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " devises..."
L["CURRENCY_HEADER_WARBAND"] = "Transférable entre personnage du bataillon"
L["CURRENCY_HEADER_CHARACTER"] = "Lié au personnage"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "Raids" -- Blizzard Global
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Donjons" -- Blizzard Global
L["PVE_HEADER_DELVES"] = "Explorations"
L["PVE_HEADER_WORLD_BOSS"] = "Boss mondiaux"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "Statistiques" -- Blizzard Global: STATISTICS
L["STATS_TOTAL_ITEMS"] = "Total d'objets"
L["STATS_TOTAL_SLOTS"] = "Total d'emplacements"
L["STATS_FREE_SLOTS"] = "Emplacements libres"
L["STATS_USED_SLOTS"] = "Emplacements utilisés"
L["STATS_TOTAL_VALUE"] = "Valeur totale"
L["COLLECTED"] = "Collecté"
L["TOTAL"] = "Total"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Personnage" -- Blizzard Global: CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Emplacement" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "Banque de bataillon"
L["TOOLTIP_TAB"] = "Onglet"
L["TOOLTIP_SLOT"] = "Emplacement"
L["TOOLTIP_COUNT"] = "Quantité"
L["CHARACTER_INVENTORY"] = "Inventaire"
L["CHARACTER_BANK"] = "Banque"

-- Try Counter
L["TRY_COUNT"] = "Compteur d'essais"
L["SET_TRY_COUNT"] = "Définir les essais"
L["TRIES"] = "Essais"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "Définir le cycle de réinitialisation"
L["DAILY_RESET"] = "Réinitialisation quotidienne"
L["WEEKLY_RESET"] = "Réinitialisation hebdomadaire"
L["NONE_DISABLE"] = "Aucun (Désactiver)"
L["RESET_CYCLE_LABEL"] = "Cycle de réinitialisation :"
L["RESET_NONE"] = "Aucun"
L["DOUBLECLICK_RESET"] = "Double-cliquez pour réinitialiser la position"

-- Error Messages
L["ERROR_GENERIC"] = "Une erreur s'est produite."
L["ERROR_API_UNAVAILABLE"] = "L'API requise n'est pas disponible."
L["ERROR_BANK_CLOSED"] = "Impossible d'effectuer l'opération : banque fermée."
L["ERROR_INVALID_ITEM"] = "Objet spécifié invalide."
L["ERROR_PROTECTED_FUNCTION"] = "Impossible d'appeler une fonction protégée en combat."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "Déposer %d objets dans la banque de bataillon ?"
L["CONFIRM_CLEAR_QUEUE"] = "Vider tous les objets de la file de dépôt ?"
L["CONFIRM_DEPOSIT_GOLD"] = "Déposer %s or dans la banque de bataillon ?"

-- Update Notification
L["WHATS_NEW"] = "Nouveautés"
L["GOT_IT"] = "Compris !"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "POINTS DE HAUT FAIT"
L["MOUNTS_COLLECTED"] = "MONTURES COLLECTÉES"
L["BATTLE_PETS"] = "MASCOTTES DE COMBAT"
L["ACCOUNT_WIDE"] = "Compte entier"
L["STORAGE_OVERVIEW"] = "Aperçu du stockage"
L["WARBAND_SLOTS"] = "EMPLACEMENTS BATAILLON"
L["PERSONAL_SLOTS"] = "EMPLACEMENTS PERSONNELS"
L["TOTAL_FREE"] = "TOTAL LIBRE"
L["TOTAL_ITEMS"] = "TOTAL OBJETS"

-- Plans Tracker Window
L["WEEKLY_VAULT"] = "Grand coffre hebdomadaire"
L["CUSTOM"] = "Personnalisé"
L["NO_PLANS_IN_CATEGORY"] = "Aucun plan dans cette catégorie.\nAjoutez des plans depuis l'onglet Plans."
L["SOURCE_LABEL"] = "Source :"
L["ZONE_LABEL"] = "Zone :"
L["VENDOR_LABEL"] = "Marchand :"
L["DROP_LABEL"] = "Butin :"
L["REQUIREMENT_LABEL"] = "Condition :"
L["RIGHT_CLICK_REMOVE"] = "Clic droit pour retirer"
L["TRACKED"] = "Suivi"
L["TRACK"] = "Suivre"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Suivre dans les objectifs Blizzard (max 10)"
L["UNKNOWN"] = "Inconnu"
L["NO_REQUIREMENTS"] = "Aucune condition (complétion instantanée)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "Aucune activité planifiée"
L["CLICK_TO_ADD_GOALS"] = "Cliquez sur Montures, Mascottes ou Jouets ci-dessus pour ajouter des objectifs !"
L["UNKNOWN_QUEST"] = "Quête inconnue"
L["ALL_QUESTS_COMPLETE"] = "Toutes les quêtes terminées !"
L["CURRENT_PROGRESS"] = "Progression actuelle"
L["SELECT_CONTENT"] = "Sélectionner le contenu :"
L["QUEST_TYPES"] = "Types de quêtes :"
L["WORK_IN_PROGRESS"] = "En cours de développement"
L["RECIPE_BROWSER"] = "Navigateur de recettes"
L["NO_RESULTS_FOUND"] = "Aucun résultat trouvé."
L["TRY_ADJUSTING_SEARCH"] = "Essayez d'ajuster votre recherche ou vos filtres."
L["NO_COLLECTED_YET"] = "Aucun %s collecté pour le moment"
L["START_COLLECTING"] = "Commencez à collecter pour les voir ici !"
L["ALL_COLLECTED_CATEGORY"] = "Tous les %ss collectés !"
L["COLLECTED_EVERYTHING"] = "Vous avez tout collecté dans cette catégorie !"
L["PROGRESS_LABEL"] = "Progression :"
L["REQUIREMENTS_LABEL"] = "Conditions :"
L["INFORMATION_LABEL"] = "Information :"
L["DESCRIPTION_LABEL"] = "Description :"
L["REWARD_LABEL"] = "Récompense :"
L["DETAILS_LABEL"] = "Détails :"
L["COST_LABEL"] = "Coût :"
L["LOCATION_LABEL"] = "Emplacement :"
L["TITLE_LABEL"] = "Titre :"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "Vous avez déjà terminé tous les hauts faits de cette catégorie !"
L["DAILY_PLAN_EXISTS"] = "Le plan quotidien existe déjà"
L["WEEKLY_PLAN_EXISTS"] = "Le plan hebdomadaire existe déjà"

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "Vos personnages"
L["CHARACTERS_TRACKED_FORMAT"] = "%d personnages suivis"
L["NO_CHARACTER_DATA"] = "Aucune donnée de personnage disponible"
L["NO_FAVORITES"] = "Aucun personnage favori pour le moment. Cliquez sur l'icône étoile pour favoriser un personnage."
L["ALL_FAVORITED"] = "Tous les personnages sont favoris !"
L["UNTRACKED_CHARACTERS"] = "Personnages non suivis"
L["ILVL_SHORT"] = "iLvl"
L["ONLINE"] = "En ligne"
L["TIME_LESS_THAN_MINUTE"] = "< 1 min"
L["TIME_MINUTES_FORMAT"] = "il y a %d min"
L["TIME_HOURS_FORMAT"] = "il y a %d h"
L["TIME_DAYS_FORMAT"] = "il y a %d j"
L["REMOVE_FROM_FAVORITES"] = "Retirer des favoris"
L["ADD_TO_FAVORITES"] = "Ajouter aux favoris"
L["FAVORITES_TOOLTIP"] = "Les personnages favoris apparaissent en haut de la liste"
L["CLICK_TO_TOGGLE"] = "Cliquer pour basculer"
L["UNKNOWN_PROFESSION"] = "Profession inconnue"
L["SKILL_LABEL"] = "Compétence :"
L["OVERALL_SKILL"] = "Compétence globale :"
L["BONUS_SKILL"] = "Compétence bonus :"
L["KNOWLEDGE_LABEL"] = "Connaissance :"
L["SPEC_LABEL"] = "Spéc."
L["POINTS_SHORT"] = "pts"
L["RECIPES_KNOWN"] = "Recettes connues :"
L["OPEN_PROFESSION_HINT"] = "Ouvrir la fenêtre de profession"
L["FOR_DETAILED_INFO"] = "pour des informations détaillées"
L["CHARACTER_IS_TRACKED"] = "Ce personnage est suivi."
L["TRACKING_ACTIVE_DESC"] = "La collecte de données et les mises à jour sont actives."
L["CLICK_DISABLE_TRACKING"] = "Cliquer pour désactiver le suivi."
L["MUST_LOGIN_TO_CHANGE"] = "Vous devez vous connecter avec ce personnage pour changer le suivi."
L["TRACKING_ENABLED"] = "Suivi activé"
L["CLICK_ENABLE_TRACKING"] = "Cliquer pour activer le suivi pour ce personnage."
L["TRACKING_WILL_BEGIN"] = "La collecte de données commencera immédiatement."
L["CHARACTER_NOT_TRACKED"] = "Ce personnage n'est pas suivi."
L["MUST_LOGIN_TO_ENABLE"] = "Vous devez vous connecter avec ce personnage pour activer le suivi."
L["ENABLE_TRACKING"] = "Activer le suivi"
L["DELETE_CHARACTER_TITLE"] = "Supprimer le personnage ?"
L["THIS_CHARACTER"] = "ce personnage"
L["DELETE_CHARACTER"] = "Supprimer le personnage"
L["REMOVE_FROM_TRACKING_FORMAT"] = "Retirer %s du suivi"
L["CLICK_TO_DELETE"] = "Cliquer pour supprimer"
L["CONFIRM_DELETE"] = "Êtes-vous sûr de vouloir supprimer |cff00ccff%s|r ?"
L["CANNOT_UNDO"] = "Cette action est irréversible !"
L["DELETE"] = DELETE or "Supprimer"
L["CANCEL"] = CANCEL or "Annuler"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "Objets personnels"
L["ITEMS_SUBTITLE"] = "Parcourir votre banque de bataillon et objets personnels (Banque + Inventaire)"
L["ITEMS_DISABLED_TITLE"] = "Objets de banque de bataillon"
L["ITEMS_LOADING"] = "Chargement des données d'inventaire"
L["GUILD_BANK_REQUIRED"] = "Vous devez être dans une guilde pour accéder à la banque de guilde."
L["ITEMS_SEARCH"] = "Rechercher des objets..."
L["NEVER"] = "Jamais"
L["ITEM_FALLBACK_FORMAT"] = "Objet %s"
L["TAB_FORMAT"] = "Onglet %d"
L["BAG_FORMAT"] = "Sac %d"
L["BANK_BAG_FORMAT"] = "Sac de banque %d"
L["ITEM_ID_LABEL"] = "ID d'objet :"
L["QUALITY_TOOLTIP_LABEL"] = "Qualité :"
L["STACK_LABEL"] = "Pile :"
L["RIGHT_CLICK_MOVE"] = "Déplacer vers le sac"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Diviser la pile"
L["LEFT_CLICK_PICKUP"] = "Prendre"
L["ITEMS_BANK_NOT_OPEN"] = "Banque non ouverte"
L["SHIFT_LEFT_CLICK_LINK"] = "Lier dans le chat"
L["ITEM_DEFAULT_TOOLTIP"] = "Objet"
L["ITEMS_STATS_ITEMS"] = "%s objets"
L["ITEMS_STATS_SLOTS"] = "%s/%s emplacements"
L["ITEMS_STATS_LAST"] = "Dernier : %s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "Stockage global"
L["STORAGE_SEARCH"] = "Rechercher dans le stockage..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "Progression JcE"
L["PVE_SUBTITLE"] = "Grand coffre, verrous de raid & Mythique+ de votre bataillon"
L["PVE_NO_CHARACTER"] = "Aucune donnée de personnage disponible"
L["LV_FORMAT"] = "Niv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = RAID or "Raid"
L["VAULT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon"
L["VAULT_WORLD"] = "Monde"
L["VAULT_SLOT_FORMAT"] = "%s Emplacement %d"
L["VAULT_NO_PROGRESS"] = "Aucune progression pour le moment"
L["VAULT_UNLOCK_FORMAT"] = "Compléter %s activités pour débloquer"
L["VAULT_NEXT_TIER_FORMAT"] = "Niveau suivant : %d iLvl en complétant %s"
L["VAULT_REMAINING_FORMAT"] = "Restant : %s activités"
L["VAULT_PROGRESS_FORMAT"] = "Progression : %s / %s"
L["OVERALL_SCORE_LABEL"] = "Score global :"
L["BEST_KEY_FORMAT"] = "Meilleure clé : +%d"
L["SCORE_FORMAT"] = "Score : %s"
L["NOT_COMPLETED_SEASON"] = "Non complété cette saison"
L["CURRENT_MAX_FORMAT"] = "Actuel : %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "Progression : %.1f%%"
L["NO_CAP_LIMIT"] = "Pas de limite"
L["GREAT_VAULT"] = "Grand coffre"
L["LOADING_PVE"] = "Chargement des données JcE..."
L["PVE_APIS_LOADING"] = "Veuillez patienter, les API WoW s'initialisent..."
L["NO_VAULT_DATA"] = "Aucune donnée de coffre"
L["NO_DATA"] = "Aucune donnée"
L["KEYSTONE"] = "Clé de donjon"
L["NO_KEY"] = "Pas de clé"
L["AFFIXES"] = "Affixes"
L["NO_AFFIXES"] = "Pas d'affixes"
L["VAULT_BEST_KEY"] = "Meilleure clé :"
L["VAULT_SCORE"] = "Score :"

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "Aperçu des réputations"
L["REP_SUBTITLE"] = "Suivre les factions et le renom de votre bataillon"
L["REP_DISABLED_TITLE"] = "Suivi des réputations"
L["REP_LOADING_TITLE"] = "Chargement des données de réputation"
L["REP_SEARCH"] = "Rechercher des réputations..."
L["REP_PARAGON_TITLE"] = "Réputation parangon"
L["REP_REWARD_AVAILABLE"] = "Récompense disponible !"
L["REP_CONTINUE_EARNING"] = "Continuez à gagner de la réputation pour des récompenses"
L["REP_CYCLES_FORMAT"] = "Cycles : %d"
L["REP_PROGRESS_HEADER"] = "Progression : %d/%d"
L["REP_PARAGON_PROGRESS"] = "Progression parangon :"
L["REP_PROGRESS_COLON"] = "Progression :"
L["REP_CYCLES_COLON"] = "Cycles :"
L["REP_CHARACTER_PROGRESS"] = "Progression du personnage :"
L["REP_RENOWN_FORMAT"] = "Renom %d"
L["REP_PARAGON_FORMAT"] = "Parangon (%s)"
L["REP_UNKNOWN_FACTION"] = "Faction inconnue"
L["REP_API_UNAVAILABLE_TITLE"] = "API de réputation non disponible"
L["REP_API_UNAVAILABLE_DESC"] = "L'API C_Reputation n'est pas disponible sur ce serveur. Cette fonctionnalité nécessite WoW 11.0+ (The War Within)."
L["REP_FOOTER_TITLE"] = "Suivi des réputations"
L["REP_FOOTER_DESC"] = "Les réputations sont scannées automatiquement à la connexion et lors des changements. Utilisez le panneau de réputation en jeu pour voir les informations détaillées et les récompenses."
L["REP_CLEARING_CACHE"] = "Vidage du cache et rechargement..."
L["REP_LOADING_DATA"] = "Chargement des données de réputation..."
L["REP_MAX"] = "Max."
L["REP_TIER_FORMAT"] = "Niveau %d"
L["ACCOUNT_WIDE_LABEL"] = "Compte entier"
L["NO_RESULTS"] = "Aucun résultat"
L["NO_REP_MATCH"] = "Aucune réputation ne correspond à '%s'"
L["NO_REP_DATA"] = "Aucune donnée de réputation disponible"
L["REP_SCAN_TIP"] = "Les réputations sont scannées automatiquement. Essayez /reload si rien n'apparaît."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "Réputations de compte entier (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "Aucune réputation de compte entier"
L["NO_CHARACTER_REPS"] = "Aucune réputation de personnage"

-- =============================================
-- Currency Tab
-- =============================================
L["CURRENCY_TITLE"] = "Suivi des devises"
L["CURRENCY_SUBTITLE"] = "Suivre toutes les devises de vos personnages"
L["CURRENCY_DISABLED_TITLE"] = "Suivi des devises"
L["CURRENCY_LOADING_TITLE"] = "Chargement des données de devises"
L["CURRENCY_SEARCH"] = "Rechercher des devises..."
L["CURRENCY_HIDE_EMPTY"] = "Masquer les vides"
L["CURRENCY_SHOW_EMPTY"] = "Afficher les vides"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "Tous transférables entre bataillon"
L["CURRENCY_CHARACTER_SPECIFIC"] = "Devises spécifiques au personnage"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "Limitation du transfert de devises"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "L'API Blizzard ne prend pas en charge les transferts automatiques de devises. Veuillez utiliser la fenêtre de devises en jeu pour transférer manuellement les devises de bataillon."
L["CURRENCY_UNKNOWN"] = "Devise inconnue"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "Retirer tous les plans complétés de votre liste Mes plans. Cela supprimera tous les plans personnalisés complétés et retirera les montures/mascottes/jouets complétés de vos plans. Cette action est irréversible !"
L["RECIPE_BROWSER_DESC"] = "Ouvrez votre fenêtre de profession en jeu pour parcourir les recettes.\nL'addon scannera les recettes disponibles lorsque la fenêtre est ouverte."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "Source : [Haut fait %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s a déjà un plan de grand coffre hebdomadaire actif. Vous pouvez le trouver dans la catégorie 'Mes plans'."
L["DAILY_PLAN_EXISTS_DESC"] = "%s a déjà un plan de quête quotidienne actif. Vous pouvez le trouver dans la catégorie 'Tâches quotidiennes'."
L["TRANSMOG_WIP_DESC"] = "Le suivi de collection de transmogrification est actuellement en développement.\n\nCette fonctionnalité sera disponible dans une mise à jour future avec des\naméliorations de performance et une meilleure intégration avec les systèmes de bataillon."
L["WEEKLY_VAULT_CARD"] = "Carte du grand coffre hebdomadaire"
L["WEEKLY_VAULT_COMPLETE"] = "Carte du grand coffre hebdomadaire - Complété"
L["UNKNOWN_SOURCE"] = "Source inconnue"
L["DAILY_TASKS_PREFIX"] = "Tâches quotidiennes - "
L["NO_FOUND_FORMAT"] = "Aucun %s trouvé"
L["PLANS_COUNT_FORMAT"] = "%d plans"
L["PET_BATTLE_LABEL"] = "Combat de mascotte :"
L["QUEST_LABEL"] = "Quête :"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "Langue actuelle :"
L["LANGUAGE_TOOLTIP"] = "L'addon utilise automatiquement la langue de votre client WoW. Pour la changer, mettez à jour vos paramètres Battle.net."
L["POPUP_DURATION"] = "Durée du popup"
L["POPUP_POSITION"] = "Position du popup"
L["SET_POSITION"] = "Définir la position"
L["DRAG_TO_POSITION"] = "Glissez pour positionner\nClic droit pour confirmer"
L["RESET_DEFAULT"] = "Réinitialiser par défaut"
L["TEST_POPUP"] = "Tester le popup"
L["CUSTOM_COLOR"] = "Couleur personnalisée"
L["OPEN_COLOR_PICKER"] = "Ouvrir le sélecteur de couleurs"
L["COLOR_PICKER_TOOLTIP"] = "Ouvrir le sélecteur de couleurs natif de WoW pour choisir une couleur de thème personnalisée"
L["PRESET_THEMES"] = "Thèmes prédéfinis"
L["WARBAND_NEXUS_SETTINGS"] = "Paramètres Warband Nexus"
L["NO_OPTIONS"] = "Aucune option"
L["NONE_LABEL"] = NONE or "Aucun"
L["TAB_FILTERING"] = "Filtrage des onglets"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Notifications"
L["SCROLL_SPEED"] = "Vitesse de défilement"
L["ANCHOR_FORMAT"] = "Ancre : %s  |  X : %d  |  Y : %d"
L["SHOW_WEEKLY_PLANNER"] = "Afficher le planificateur hebdomadaire"
L["LOCK_MINIMAP_ICON"] = "Verrouiller l'icône de la minicarte"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "Afficher les objets dans les infobulles"
L["AUTO_SCAN_ITEMS"] = "Analyse automatique des objets"
L["LIVE_SYNC"] = "Synchronisation en direct"
L["BACKPACK_LABEL"] = "Sac à dos"
L["REAGENT_LABEL"] = "Réactif"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "Module désactivé"
L["LOADING"] = "Chargement..."
L["PLEASE_WAIT"] = "Veuillez patienter..."
L["RESET_PREFIX"] = "Réinitialisation :"
L["TRANSFER_CURRENCY"] = "Transférer la devise"
L["AMOUNT_LABEL"] = "Montant :"
L["TO_CHARACTER"] = "Vers le personnage :"
L["SELECT_CHARACTER"] = "Sélectionner un personnage..."
L["CURRENCY_TRANSFER_INFO"] = "La fenêtre de devises sera ouverte automatiquement.\nVous devrez faire un clic droit sur la devise pour transférer manuellement."
L["OK_BUTTON"] = OKAY or "OK"
L["SAVE"] = "Sauvegarder"
L["TITLE_FIELD"] = "Titre :"
L["DESCRIPTION_FIELD"] = "Description :"
L["CREATE_CUSTOM_PLAN"] = "Créer un plan personnalisé"
L["REPORT_BUGS"] = "Signalez les bugs ou partagez des suggestions sur CurseForge pour aider à améliorer l'addon."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus fournit une interface centralisée pour gérer tous vos personnages, devises, réputations, objets et progression JcE de tout votre bataillon."
L["CHARACTERS_DESC"] = "Affichez tous les personnages avec or, niveau, iLvl, faction, race, classe, métiers, clé de voûte et dernière connexion. Suivez ou retirez des personnages, marquez vos favoris."
L["ITEMS_DESC"] = "Recherchez et parcourez les objets dans tous les sacs, banques et banque de compagnie. Scan automatique à l'ouverture d'une banque. Les tooltips montrent quels personnages possèdent chaque objet."
L["STORAGE_DESC"] = "Vue d'inventaire agrégée de tous les personnages — sacs, banque personnelle et banque de compagnie réunis en un seul endroit."
L["PVE_DESC"] = "Suivez le Grand Coffre avec indicateurs de palier, scores et clés Mythique+, affixes, historique de donjon et devises d'amélioration sur tous les personnages."
L["REPUTATIONS_DESC"] = "Comparez la progression de réputation de tous les personnages. Affiche les factions Compte vs Personnage avec tooltips au survol pour le détail par personnage."
L["CURRENCY_DESC"] = "Affichez toutes les devises organisées par extension. Comparez les montants entre personnages avec tooltips au survol. Masquez les devises vides en un clic."
L["PLANS_DESC"] = "Suivez les montures, mascottes, jouets, hauts faits et transmogs non collectés. Ajoutez des objectifs, consultez les sources de drop et suivez les tentatives. Accès via /wn plan ou icône minimap."
L["STATISTICS_DESC"] = "Affichez les points de haut fait, la progression de collection montures/mascottes/jouets/illusions/titres, le compteur de mascottes uniques et les statistiques d'utilisation sacs/banques."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "Mythique"
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "Héroique"
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "Normal"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Niveau %d"
L["PVP_TYPE"] = PVP or "PvP"
L["PREPARING"] = "Préparation"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Statistiques de compte"
L["STATISTICS_SUBTITLE"] = "Progression de collection, or et aperçu du stockage"
L["MOST_PLAYED"] = "PLUS JOUÉS"
L["PLAYED_DAYS"] = "Jours"
L["PLAYED_HOURS"] = "Heures"
L["PLAYED_MINUTES"] = "Minutes"
L["PLAYED_DAY"] = "Jour"
L["PLAYED_HOUR"] = "Heure"
L["PLAYED_MINUTE"] = "Minute"
L["MORE_CHARACTERS"] = "personnage de plus"
L["MORE_CHARACTERS_PLURAL"] = "personnages de plus"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "Bienvenue dans Warband Nexus !"
L["ADDON_OVERVIEW_TITLE"] = "Aperçu de l'addon"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "Suivre vos objectifs de collection"
L["ACTIVE_PLAN_FORMAT"] = "%d plan actif"
L["ACTIVE_PLANS_FORMAT"] = "%d plans actifs"
L["RESET_LABEL"] = RESET or "Réinitialiser"

-- Plans - Type Names
L["TYPE_MOUNT"] = MOUNT or "Monture"
L["TYPE_PET"] = PET or "Mascotte"
L["TYPE_TOY"] = TOY or "Jouet"
L["TYPE_RECIPE"] = "Recette"
L["TYPE_ILLUSION"] = "Illusion"
L["TYPE_TITLE"] = "Titre"
L["TYPE_CUSTOM"] = "Personnalisé"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transmogrification"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Butin"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Quête"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Marchand"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Combat de mascotte"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Haut fait"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "Événement mondial"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promotion"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "Jeu de cartes à collectionner"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "Boutique en jeu"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "Fabriqué"
L["SOURCE_TYPE_TRADING_POST"] = "Comptoir"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "Inconnu"
L["SOURCE_TYPE_PVP"] = PVP or "JcJ"
L["SOURCE_TYPE_TREASURE"] = "Trésor"
L["SOURCE_TYPE_PUZZLE"] = "Énigme"
L["SOURCE_TYPE_RENOWN"] = "Renom"

-- Plans - Transmog Source Labels (Blizzard TRANSMOG_SOURCE_* Globals)
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Butin de boss"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Quête"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Marchand"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "Butin mondial"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Haut fait"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Métier"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "Vendu par"
L["PARSE_CRAFTED"] = "Fabriqué"
L["PARSE_ZONE"] = ZONE or "Zone"
L["PARSE_COST"] = "Coût"
L["PARSE_REPUTATION"] = REPUTATION or "Réputation"
L["PARSE_FACTION"] = FACTION or "Faction"
L["PARSE_ARENA"] = ARENA or "Arène"
L["PARSE_DUNGEON"] = DUNGEONS or "Donjon"
L["PARSE_RAID"] = RAID or "Raid"
L["PARSE_HOLIDAY"] = "Fête"
L["PARSE_RATED"] = "Classé"
L["PARSE_BATTLEGROUND"] = "Champ de bataille"
L["PARSE_DISCOVERY"] = "Découverte"
L["PARSE_CONTAINED_IN"] = "Contenu dans"
L["PARSE_GARRISON"] = "Fief"
L["PARSE_GARRISON_BUILDING"] = "Bâtiment de fief"
L["PARSE_STORE"] = "Boutique"
L["PARSE_ORDER_HALL"] = "Sanctuaire de classe"
L["PARSE_COVENANT"] = "Congrégation"
L["PARSE_FRIENDSHIP"] = "Amitié"
L["PARSE_PARAGON"] = "Parangon"
L["PARSE_MISSION"] = "Mission"
L["PARSE_EXPANSION"] = "Extension"
L["PARSE_SCENARIO"] = "Scénario"
L["PARSE_CLASS_HALL"] = "Sanctuaire de classe"
L["PARSE_CAMPAIGN"] = "Campagne"
L["PARSE_EVENT"] = "Événement"
L["PARSE_SPECIAL"] = "Spécial"
L["PARSE_BRAWLERS_GUILD"] = "Guilde des bagarreurs"
L["PARSE_CHALLENGE_MODE"] = "Mode défi"
L["PARSE_MYTHIC_PLUS"] = "Mythique+"
L["PARSE_TIMEWALKING"] = "Marcheurs du temps"
L["PARSE_ISLAND_EXPEDITION"] = "Expédition insulaire"
L["PARSE_WARFRONT"] = "Front de guerre"
L["PARSE_TORGHAST"] = "Torghast"
L["PARSE_ZERETH_MORTIS"] = "Zereth Mortis"
L["PARSE_HIDDEN"] = "Caché"
L["PARSE_RARE"] = "Rare"
L["PARSE_WORLD_BOSS"] = "Boss mondial"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Butin"
L["PARSE_NPC"] = "PNJ"
L["PARSE_FROM_ACHIEVEMENT"] = "Du haut fait"
L["FALLBACK_UNKNOWN_PET"] = "Familier inconnu"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "Collection de mascottes"
L["FALLBACK_TOY_COLLECTION"] = "Collection de jouets"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Collection de transmogrification"
L["FALLBACK_PLAYER_TITLE"] = "Titre de joueur"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Inconnu"
L["FALLBACK_ILLUSION_FORMAT"] = "Illusion %s"
L["SOURCE_ENCHANTING"] = "Enchantement"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "Définir le nombre d'essais pour :\n%s"
L["RESET_COMPLETED_CONFIRM"] = "Êtes-vous sûr de vouloir retirer TOUS les plans complétés ?\n\nCela ne peut pas être annulé !"
L["YES_RESET"] = "Oui, réinitialiser"
L["REMOVED_PLANS_FORMAT"] = "%d plan(s) complété(s) retiré(s)."

-- Plans - Buttons
L["ADD_CUSTOM"] = "Ajouter personnalisé"
L["ADD_VAULT"] = "Ajouter coffre"
L["ADD_QUEST"] = "Ajouter quête"
L["CREATE_PLAN"] = "Créer un plan"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "Quotidien"
L["QUEST_CAT_WORLD"] = "Monde"
L["QUEST_CAT_WEEKLY"] = "Hebdomadaire"
L["QUEST_CAT_ASSIGNMENT"] = "Mission"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Catégorie inconnue"
L["SCANNING_FORMAT"] = "Analyse de %s"
L["CUSTOM_PLAN_SOURCE"] = "Plan personnalisé"
L["POINTS_FORMAT"] = "%d Points"
L["SOURCE_NOT_AVAILABLE"] = "Informations de source non disponibles"
L["PROGRESS_ON_FORMAT"] = "Vous êtes à %d/%d de la progression"
L["COMPLETED_REQ_FORMAT"] = "Vous avez complété %d des %d conditions totales"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Midnight"
L["CONTENT_TWW"] = "The War Within"
L["QUEST_TYPE_DAILY"] = "Quêtes quotidiennes"
L["QUEST_TYPE_DAILY_DESC"] = "Quêtes quotidiennes régulières des PNJ"
L["QUEST_TYPE_WORLD"] = "Quêtes mondiales"
L["QUEST_TYPE_WORLD_DESC"] = "Quêtes mondiales à l'échelle de la zone"
L["QUEST_TYPE_WEEKLY"] = "Quêtes hebdomadaires"
L["QUEST_TYPE_WEEKLY_DESC"] = "Quêtes hebdomadaires récurrentes"
L["QUEST_TYPE_ASSIGNMENTS"] = "Missions"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "Missions et tâches spéciales"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "Mythique+"
L["RAIDS_LABEL"] = RAIDS or "Raids"

-- PlanCardFactory
L["FACTION_LABEL"] = "Faction :"
L["FRIENDSHIP_LABEL"] = "Amitié"
L["RENOWN_TYPE_LABEL"] = "Renom"
L["ADD_BUTTON"] = "+ Ajouter"
L["ADDED_LABEL"] = "Ajouté"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s sur %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Afficher les quantités empilées sur les objets dans la vue de stockage"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Afficher la section Planificateur hebdomadaire dans l'onglet Personnages"
L["LOCK_MINIMAP_TOOLTIP"] = "Verrouiller l'icône de la minicarte en place (empêche le déplacement)"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "Affiche le nombre d'objets du bataillon et du personnage dans les infobulles (Recherche WN)."
L["AUTO_SCAN_TOOLTIP"] = "Analyser et mettre en cache automatiquement les objets lorsque vous ouvrez les banques ou sacs"
L["LIVE_SYNC_TOOLTIP"] = "Maintenir le cache d'objets à jour en temps réel pendant que les banques sont ouvertes"
L["SHOW_ILVL_TOOLTIP"] = "Afficher les badges de niveau d'objet sur l'équipement dans la liste des objets"
L["SCROLL_SPEED_TOOLTIP"] = "Multiplicateur de vitesse de défilement (1.0x = 28 px par étape)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "Ignorer l'onglet %d de la banque de bataillon de l'analyse automatique"
L["IGNORE_SCAN_FORMAT"] = "Ignorer %s de l'analyse automatique"
L["BANK_LABEL"] = BANK or "Banque"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "Activer les notifications"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Interrupteur principal pour toutes les notifications popup"
L["VAULT_REMINDER"] = "Rappel du coffre"
L["VAULT_REMINDER_TOOLTIP"] = "Afficher un rappel lorsque vous avez des récompenses de grand coffre hebdomadaire non réclamées"
L["LOOT_ALERTS"] = "Alertes de butin"
L["LOOT_ALERTS_TOOLTIP"] = "Afficher une notification lorsqu'une NOUVELLE monture, mascotte ou jouet entre dans votre sac"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Masquer l'alerte de haut fait Blizzard"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Masquer le popup de haut fait par défaut de Blizzard et utiliser la notification Warband Nexus à la place"
L["REPUTATION_GAINS"] = "Gains de réputation"
L["REPUTATION_GAINS_TOOLTIP"] = "Afficher les messages de chat lorsque vous gagnez de la réputation avec des factions"
L["CURRENCY_GAINS"] = "Gains de devises"
L["CURRENCY_GAINS_TOOLTIP"] = "Afficher les messages de chat lorsque vous gagnez des devises"
L["SCREEN_FLASH_EFFECT"] = "Effet de flash d'écran"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Jouer un effet de flash d'écran lorsque vous obtenez un nouveau collectionnable (monture, mascotte, jouet, etc.)"
L["AUTO_TRY_COUNTER"] = "Compteur d'essais automatique"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Comptabiliser automatiquement les tentatives lors du pillage de PNJ, rares, boss, pêche ou ouverture de conteneurs qui peuvent donner des montures, mascottes ou jouets. Affiche le nombre de tentatives dans le chat lorsque le collectionnable ne tombe pas."
L["DURATION_LABEL"] = "Durée"
L["DAYS_LABEL"] = "jours"
L["WEEKS_LABEL"] = "semaines"
L["EXTEND_DURATION"] = "Prolonger la durée"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Glissez le cadre vert pour définir la position du popup. Clic droit pour confirmer."
L["POSITION_RESET_MSG"] = "Position du popup réinitialisée par défaut (Haut Centre)"
L["POSITION_SAVED_MSG"] = "Position du popup sauvegardée !"
L["TEST_NOTIFICATION_TITLE"] = "Test de notification"
L["TEST_NOTIFICATION_MSG"] = "Test de position"
L["NOTIFICATION_DEFAULT_TITLE"] = "Notification"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "Thème et apparence"
L["COLOR_PURPLE"] = "Violet"
L["COLOR_PURPLE_DESC"] = "Thème violet classique (par défaut)"
L["COLOR_BLUE"] = "Bleu"
L["COLOR_BLUE_DESC"] = "Thème bleu froid"
L["COLOR_GREEN"] = "Vert"
L["COLOR_GREEN_DESC"] = "Thème vert nature"
L["COLOR_RED"] = "Rouge"
L["COLOR_RED_DESC"] = "Thème rouge flamboyant"
L["COLOR_ORANGE"] = "Orange"
L["COLOR_ORANGE_DESC"] = "Thème orange chaud"
L["COLOR_CYAN"] = "Cyan"
L["COLOR_CYAN_DESC"] = "Thème cyan brillant"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "Famille de polices"
L["FONT_FAMILY_TOOLTIP"] = "Choisir la police utilisée dans toute l'interface de l'addon"
L["FONT_SCALE"] = "Échelle de police"
L["FONT_SCALE_TOOLTIP"] = "Ajuster la taille de la police sur tous les éléments de l'interface"
L["FONT_SCALE_WARNING"] = "Attention : Une échelle de police élevée peut causer un débordement de texte dans certains éléments de l'interface."
L["RESOLUTION_NORMALIZATION"] = "Normalisation de résolution"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Ajuster les tailles de police en fonction de la résolution d'écran et de l'échelle de l'interface pour que le texte reste de la même taille physique sur différents moniteurs"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Avancé"

-- =============================================
-- Settings - Module Management
-- =============================================
L["MODULE_MANAGEMENT"] = "Gestion des modules"
L["MODULE_MANAGEMENT_DESC"] = "Activer ou désactiver des modules de collecte de données spécifiques. La désactivation d'un module arrêtera ses mises à jour de données et masquera son onglet de l'interface."
L["MODULE_CURRENCIES"] = "Devises"
L["MODULE_CURRENCIES_DESC"] = "Suivre les devises de compte et spécifiques au personnage (Or, Honneur, Conquête, etc.)"
L["MODULE_REPUTATIONS"] = "Réputations"
L["MODULE_REPUTATIONS_DESC"] = "Suivre la progression de réputation avec les factions, les niveaux de renom et les récompenses parangon"
L["MODULE_ITEMS"] = "Objets"
L["MODULE_ITEMS_DESC"] = "Suivre les objets de la banque de bataillon, la fonction de recherche et les catégories d'objets"
L["MODULE_STORAGE"] = "Stockage"
L["MODULE_STORAGE_DESC"] = "Suivre les sacs du personnage, la banque personnelle et le stockage de la banque de bataillon"
L["MODULE_PVE"] = "JcE"
L["MODULE_PVE_DESC"] = "Suivre les donjons Mythique+, la progression des raids et les récompenses du grand coffre"
L["MODULE_PLANS"] = "Plans"
L["MODULE_PLANS_DESC"] = "Suivre les objectifs personnels pour les montures, mascottes, jouets, hauts faits et tâches personnalisées"
L["MODULE_PROFESSIONS"] = "Métiers"
L["MODULE_PROFESSIONS_DESC"] = "Suivre les compétences de métier, la concentration, les connaissances et la fenêtre compagnon de recettes"
L["PROFESSIONS_DISABLED_TITLE"] = "Métiers"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Niveau d'objet %s"
L["ITEM_NUMBER_FORMAT"] = "Objet #%s"
L["CHARACTER_CURRENCIES"] = "Devises du personnage :"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "Compte entier (bataillon) — même solde sur tous les personnages."
L["YOU_MARKER"] = "(Vous)"
L["WN_SEARCH"] = "Recherche WN"
L["WARBAND_BANK_COLON"] = "Banque de bataillon :"
L["AND_MORE_FORMAT"] = "... et %d de plus"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "Vous avez collecté une monture"
L["COLLECTED_PET_MSG"] = "Vous avez collecté une mascotte de combat"
L["COLLECTED_TOY_MSG"] = "Vous avez collecté un jouet"
L["COLLECTED_ILLUSION_MSG"] = "Vous avez collecté une illusion"
L["ACHIEVEMENT_COMPLETED_MSG"] = "Haut fait complété !"
L["EARNED_TITLE_MSG"] = "Vous avez obtenu un titre"
L["COMPLETED_PLAN_MSG"] = "Vous avez complété un plan"
L["DAILY_QUEST_CAT"] = "Quête quotidienne"
L["WORLD_QUEST_CAT"] = "Quête mondiale"
L["WEEKLY_QUEST_CAT"] = "Quête hebdomadaire"
L["SPECIAL_ASSIGNMENT_CAT"] = "Mission spéciale"
L["DELVE_CAT"] = "Exploration"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "Donjon"
L["RAID_CAT"] = RAID or "Raid"
L["WORLD_CAT"] = "Monde"
L["ACTIVITY_CAT"] = "Activité"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Progression"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Progression complétée"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Plan de grand coffre hebdomadaire - %s"
L["ALL_SLOTS_COMPLETE"] = "Tous les emplacements complétés !"
L["QUEST_COMPLETED_SUFFIX"] = "Complété"
L["WEEKLY_VAULT_READY"] = "Grand coffre hebdomadaire prêt !"
L["UNCLAIMED_REWARDS"] = "Vous avez des récompenses non réclamées"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "Or total :"
L["CHARACTERS_COLON"] = "Personnages :"
L["LEFT_CLICK_TOGGLE"] = "Clic gauche : Basculer la fenêtre"
L["RIGHT_CLICK_PLANS"] = "Clic droit : Ouvrir les plans"
L["MINIMAP_SHOWN_MSG"] = "Bouton de minicarte affiché"
L["MINIMAP_HIDDEN_MSG"] = "Bouton de minicarte masqué (utilisez /wn minimap pour afficher)"
L["TOGGLE_WINDOW"] = "Basculer la fenêtre"
L["SCAN_BANK_MENU"] = "Analyser la banque"
L["TRACKING_DISABLED_SCAN_MSG"] = "Le suivi de personnage est désactivé. Activez le suivi dans les paramètres pour analyser la banque."
L["SCAN_COMPLETE_MSG"] = "Analyse terminée !"
L["BANK_NOT_OPEN_MSG"] = "La banque n'est pas ouverte"
L["OPTIONS_MENU"] = "Options"
L["HIDE_MINIMAP_BUTTON"] = "Masquer le bouton de la minicarte"
L["MENU_UNAVAILABLE_MSG"] = "Menu clic droit non disponible"
L["USE_COMMANDS_MSG"] = "Utilisez /wn show, /wn scan, /wn config"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "Max"
L["OPEN_AND_GUIDE"] = "Ouvrir et guider"
L["FROM_LABEL"] = "De :"
L["AVAILABLE_LABEL"] = "Disponible :"
L["ONLINE_LABEL"] = "(En ligne)"
L["DATA_SOURCE_TITLE"] = "Informations sur la source de données"
L["DATA_SOURCE_USING"] = "Cet onglet utilise :"
L["DATA_SOURCE_MODERN"] = "Service de cache moderne (orienté événements)"
L["DATA_SOURCE_LEGACY"] = "Accès direct à la base de données (ancien)"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Nécessite une migration vers le service de cache"
L["GLOBAL_DB_VERSION"] = "Version de la base de données globale :"

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "Personnages"
L["INFO_TAB_ITEMS"] = "Objets"
L["INFO_TAB_STORAGE"] = "Stockage"
L["INFO_TAB_PVE"] = "JcE"
L["INFO_TAB_REPUTATIONS"] = "Réputations"
L["INFO_TAB_CURRENCY"] = "Devises"
L["INFO_TAB_PLANS"] = "Plans"
L["INFO_TAB_STATISTICS"] = "Statistiques"
L["SPECIAL_THANKS"] = "Remerciements spéciaux"
L["SUPPORTERS_TITLE"] = "Supporters"
L["THANK_YOU_MSG"] = "Merci d'utiliser Warband Nexus !"

-- =============================================
-- Changelog (What's New) - v2.0.0
-- =============================================
L["CHANGELOG_V200"] = "NOUVELLES FONCTIONNALITÉS :\n" ..
    "- Suivi des personnages : Choisissez quels personnages suivre ou ne pas suivre.\n" ..
    "- Suivi intelligent des Devises et Réputations : Notifications en temps réel dans le chat avec progression.\n" ..
    "- Compteur d'essais de montures : Suivez vos tentatives de drop (En cours).\n" ..
    "- Suivi Inventaire + Banque + Banque de compagnie : Suivez les objets dans tous les stockages.\n" ..
    "- Système de tooltips : Nouveau cadre de tooltips personnalisé.\n" ..
    "- Tooltip Suivi d'objets : Voyez quels personnages possèdent un objet au survol.\n" ..
    "- Onglet Plans : Suivez vos prochains objectifs — montures, mascottes, jouets, hauts faits, transmog.\n" ..
    "- Fenêtre Plans : Accès rapide via /wn plan ou clic droit sur l'icône minimap.\n" ..
    "- Suivi intelligent des données de compte : Synchronisation automatique des données de compagnie.\n" ..
    "- Localisation : 11 langues supportées.\n" ..
    "- Comparaison Réputation & Devises : Les tooltips au survol montrent le détail par personnage.\n" ..
    "- Système de notifications : Rappels de butin, hauts faits et coffre.\n" ..
    "- Système de polices personnalisé : Choisissez votre police et mise à l'échelle préférées.\n" ..
    "\n" ..
    "AMÉLIORATIONS :\n" ..
    "- Données de personnage : Faction, Race, iLvl et info Clé de voûte ajoutées.\n" ..
    "- Interface Banque désactivée (remplacée par le Stockage amélioré).\n" ..
    "- Objets personnels : Suit votre banque + inventaire.\n" ..
    "- Stockage : Suit banque + inventaire + banque de compagnie sur tous les personnages.\n" ..
    "- PvE : Indicateur de palier coffre, score donjon/clés, affixes, devises d'amélioration.\n" ..
    "- Onglet Réputations : Vue simplifiée (ancien système de filtres supprimé).\n" ..
    "- Onglet Devises : Vue simplifiée (ancien système de filtres supprimé).\n" ..
    "- Statistiques : Compteur de mascottes uniques ajouté.\n" ..
    "- Paramètres : Révisés et réorganisés.\n" ..
    "\n" ..
    "Merci pour votre patience et votre intérêt.\n" ..
    "\n" ..
    "Pour signaler des problèmes ou partager des commentaires, laissez un commentaire sur CurseForge - Warband Nexus."

-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "Confirmer l'action"
L["CONFIRM"] = "Confirmer"
L["ENABLE_TRACKING_FORMAT"] = "Activer le suivi pour |cffffcc00%s|r ?"
L["DISABLE_TRACKING_FORMAT"] = "Désactiver le suivi pour |cffffcc00%s|r ?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "Réputations de compte entier (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Réputations basées sur le personnage (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "Récompense en attente"
L["REP_PARAGON_LABEL"] = "Parangon"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "Préparation..."
L["REP_LOADING_INITIALIZING"] = "Initialisation..."
L["REP_LOADING_FETCHING"] = "Chargement des données de réputation..."
L["REP_LOADING_PROCESSING"] = "Traitement de %d factions..."
L["REP_LOADING_PROCESSING_COUNT"] = "Traitement... (%d/%d)"
L["REP_LOADING_SAVING"] = "Enregistrement dans la base de données..."
L["REP_LOADING_COMPLETE"] = "Terminé !"

-- =============================================
-- Gold Transfer
-- =============================================
L["GOLD_TRANSFER"] = "Transfert d'or"
L["GOLD_LABEL"] = "Or"
L["SILVER_LABEL"] = "Argent"
L["COPPER_LABEL"] = "Cuivre"
L["DEPOSIT"] = "Déposer"
L["WITHDRAW"] = "Retirer"
L["DEPOSIT_TO_WARBAND"] = "Déposer dans la banque de bataillon"
L["WITHDRAW_FROM_WARBAND"] = "Retirer de la banque de bataillon"
L["YOUR_GOLD_FORMAT"] = "Votre or : %s"
L["WARBAND_BANK_FORMAT"] = "Banque de bataillon : %s"
L["NOT_ENOUGH_GOLD"] = "Pas assez d'or disponible."
L["ENTER_AMOUNT"] = "Veuillez entrer un montant."
L["ONLY_WARBAND_GOLD"] = "Seule la banque de bataillon prend en charge le transfert d'or."

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "Impossible d'ouvrir la fenêtre en combat. Veuillez réessayer après la fin du combat."
L["BANK_IS_ACTIVE"] = "La banque est active"
L["ITEMS_CACHED_FORMAT"] = "%d objets mis en cache"
L["UP_TO_DATE"] = "À jour"
L["NEVER_SCANNED"] = "Jamais analysé"

-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "PERSONNAGE"
L["TABLE_HEADER_LEVEL"] = "NIVEAU"
L["TABLE_HEADER_GOLD"] = "OR"
L["TABLE_HEADER_LAST_SEEN"] = "VU POUR LA DERNIÈRE FOIS"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "Aucun objet ne correspond à '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "Aucun objet ne correspond à votre recherche"
L["ITEMS_SCAN_HINT"] = "Les objets sont analysés automatiquement. Essayez /reload si rien n'apparaît."
L["ITEMS_WARBAND_BANK_HINT"] = "Ouvrez la banque de bataillon pour analyser les objets (analysé automatiquement lors de la première visite)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Prochaines étapes :"
L["CURRENCY_TRANSFER_STEP_1"] = "Trouvez |cffffffff%s|r dans la fenêtre de devises"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800Clic droit|r dessus"
L["CURRENCY_TRANSFER_STEP_3"] = "Sélectionnez |cffffffff'Transférer au bataillon'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Choisissez |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Entrez le montant : |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "La fenêtre de devises est maintenant ouverte !"
L["CURRENCY_TRANSFER_SECURITY"] = "(La sécurité Blizzard empêche le transfert automatique)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "Zone : "
L["ADDED"] = "Ajouté"
L["WEEKLY_VAULT_TRACKER"] = "Suivi du grand coffre hebdomadaire"
L["DAILY_QUEST_TRACKER"] = "Suivi des quêtes quotidiennes"
L["CUSTOM_PLAN_STATUS"] = "Plan personnalisé '%s' %s"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = LFG_TYPE_DUNGEON or "Donjons"
L["VAULT_SLOT_RAIDS"] = RAIDS or "Raids"
L["VAULT_SLOT_WORLD"] = "Monde"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "Affixe"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_STANDING_LABEL"] = "Maintenant"
L["CHAT_GAINED_PREFIX"] = "+"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "Plan complété : "
L["WEEKLY_VAULT_PLAN_NAME"] = "Grand coffre hebdomadaire - %s"
L["VAULT_PLANS_RESET"] = "Les plans de grand coffre hebdomadaire ont été réinitialisés ! (%d plan%s)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "Aucun personnage trouvé"
L["EMPTY_CHARACTERS_DESC"] = "Connectez-vous avec vos personnages pour commencer à les suivre.\nLes données sont collectées automatiquement à chaque connexion."
L["EMPTY_ITEMS_TITLE"] = "Aucun objet en cache"
L["EMPTY_ITEMS_DESC"] = "Ouvrez votre banque de bataillon ou personnelle pour scanner les objets.\nLes objets sont mis en cache automatiquement lors de la première visite."
L["EMPTY_STORAGE_TITLE"] = "Aucune donnée de stockage"
L["EMPTY_STORAGE_DESC"] = "Les objets sont scannés à l'ouverture des banques ou des sacs.\nVisitez une banque pour commencer à suivre votre stockage."
L["EMPTY_PLANS_TITLE"] = "Aucun plan pour l'instant"
L["EMPTY_PLANS_DESC"] = "Parcourez les montures, mascottes, jouets ou hauts faits ci-dessus\npour ajouter des objectifs et suivre votre progression."
L["EMPTY_REPUTATION_TITLE"] = "Aucune donnée de réputation"
L["EMPTY_REPUTATION_DESC"] = "Les réputations sont scannées automatiquement à la connexion.\nConnectez-vous avec un personnage pour suivre les factions."
L["EMPTY_CURRENCY_TITLE"] = "Aucune donnée de devise"
L["EMPTY_CURRENCY_DESC"] = "Les devises sont suivies automatiquement sur tous vos personnages.\nConnectez-vous avec un personnage pour suivre les devises."
L["EMPTY_PVE_TITLE"] = "Aucune donnée PvE"
L["EMPTY_PVE_DESC"] = "La progression PvE est suivie lorsque vous vous connectez.\nGrand coffre, Mythique+ et verrouillages de raid apparaîtront ici."
L["EMPTY_STATISTICS_TITLE"] = "Aucune statistique disponible"
L["EMPTY_STATISTICS_DESC"] = "Les statistiques proviennent de vos personnages suivis.\nConnectez-vous avec un personnage pour collecter des données."
L["NO_ADDITIONAL_INFO"] = "Aucune information supplémentaire"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "Voulez-vous suivre ce personnage ?"
L["CLEANUP_NO_INACTIVE"] = "Aucun personnage inactif trouvé (90+ jours)"
L["CLEANUP_REMOVED_FORMAT"] = "%d personnage(s) inactif(s) supprimé(s)"
L["TRACKING_ENABLED_MSG"] = "Suivi de personnage ACTIVÉ !"
L["TRACKING_DISABLED_MSG"] = "Suivi de personnage DÉSACTIVÉ !"
L["TRACKING_ENABLED"] = "Suivi ACTIVÉ"
L["TRACKING_DISABLED"] = "Suivi DÉSACTIVÉ (mode lecture seule)"
L["STATUS_LABEL"] = "Statut :"
L["ERROR_LABEL"] = "Erreur :"
L["ERROR_NAME_REALM_REQUIRED"] = "Nom du personnage et royaume requis"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s a déjà un plan hebdomadaire actif"

-- Profiles (AceDB)
L["PROFILES"] = "Profils"
L["PROFILES_DESC"] = "Gérer les profils de l'addon"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "Aucun critère trouvé"
L["NO_REQUIREMENTS_INSTANT"] = "Aucune condition (achèvement instantané)"

-- Statistics Tab (missing)
L["TOTAL_PETS"] = "Total des mascottes"

-- Items Tab (missing)
L["ITEM_LOADING_NAME"] = "Chargement..."

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
