--[[
    Warband Nexus - Russian Localization
    Uses Blizzard Global Strings where available for automatic localization.
]]

local ADDON_NAME, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "ruRU")
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus загружен. Введите /wn или /warbandnexus для настроек."
L["VERSION"] = GAME_VERSION_LABEL or "Версия"

-- Slash Commands
L["SLASH_HELP"] = "Доступные команды:"
L["SLASH_OPTIONS"] = "Открыть панель настроек"
L["SLASH_SCAN"] = "Сканировать банк отряда"
L["SLASH_SHOW"] = "Показать/скрыть главное окно"
L["SLASH_DEPOSIT"] = "Открыть очередь вклада"
L["SLASH_SEARCH"] = "Найти предмет"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "Общие настройки"
L["GENERAL_SETTINGS_DESC"] = "Настройка общего поведения аддона"
L["ENABLE_ADDON"] = "Включить аддон"
L["ENABLE_ADDON_DESC"] = "Включить или отключить функциональность Warband Nexus"
L["MINIMAP_ICON"] = "Показать значок на миникарте"
L["MINIMAP_ICON_DESC"] = "Показать или скрыть кнопку на миникарте"
L["DEBUG_MODE"] = "Режим отладки"
L["DEBUG_MODE_DESC"] = "Включить отладочные сообщения в чате"

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "Настройки сканирования"
L["SCANNING_SETTINGS_DESC"] = "Настройка поведения сканирования банка"
L["AUTO_SCAN"] = "Автосканирование при открытии"
L["AUTO_SCAN_DESC"] = "Автоматически сканировать банк отряда при открытии"
L["SCAN_DELAY"] = "Задержка сканирования"
L["SCAN_DELAY_DESC"] = "Задержка между операциями сканирования (в секундах)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "Настройки вклада"
L["DEPOSIT_SETTINGS_DESC"] = "Настройка поведения вклада предметов"
L["GOLD_RESERVE"] = "Запас золота"
L["GOLD_RESERVE_DESC"] = "Минимальное количество золота в личном инвентаре (в золоте)"
L["AUTO_DEPOSIT_REAGENTS"] = "Автовклад реагентов"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "Помещать реагенты в очередь вклада при открытии банка"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Настройки отображения"
L["DISPLAY_SETTINGS_DESC"] = "Настройка внешнего вида"
L["SHOW_ITEM_LEVEL"] = "Показать уровень предмета"
L["SHOW_ITEM_LEVEL_DESC"] = "Отображать уровень предмета на экипировке"
L["SHOW_ITEM_COUNT"] = "Показать количество предметов"
L["SHOW_ITEM_COUNT_DESC"] = "Отображать количество в стопке на предметах"
L["HIGHLIGHT_QUALITY"] = "Подсветка по качеству"
L["HIGHLIGHT_QUALITY_DESC"] = "Добавить цветные рамки по качеству предмета"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "Настройки вкладок"
L["TAB_SETTINGS_DESC"] = "Настройка поведения вкладок банка отряда"
L["IGNORED_TABS"] = "Игнорируемые вкладки"
L["IGNORED_TABS_DESC"] = "Выберите вкладки для исключения из сканирования и операций"
L["TAB_1"] = "Вкладка отряда 1"
L["TAB_2"] = "Вкладка отряда 2"
L["TAB_3"] = "Вкладка отряда 3"
L["TAB_4"] = "Вкладка отряда 4"
L["TAB_5"] = "Вкладка отряда 5"

-- Scanner Module
L["SCAN_STARTED"] = "Сканирование банка отряда..."
L["SCAN_COMPLETE"] = "Сканирование завершено. Найдено %d предметов в %d ячейках."
L["SCAN_FAILED"] = "Ошибка сканирования: Банк отряда не открыт."
L["SCAN_TAB"] = "Сканирование вкладки %d..."
L["CACHE_CLEARED"] = "Кэш предметов очищен."
L["CACHE_UPDATED"] = "Кэш предметов обновлён."

-- Banker Module
L["BANK_NOT_OPEN"] = "Банк отряда не открыт."
L["DEPOSIT_STARTED"] = "Начало операции вклада..."
L["DEPOSIT_COMPLETE"] = "Вклад завершён. Перенесено %d предметов."
L["DEPOSIT_CANCELLED"] = "Вклад отменён."
L["DEPOSIT_QUEUE_EMPTY"] = "Очередь вклада пуста."
L["DEPOSIT_QUEUE_CLEARED"] = "Очередь вклада очищена."
L["ITEM_QUEUED"] = "%s добавлен в очередь вклада."
L["ITEM_REMOVED"] = "%s удалён из очереди."
L["GOLD_DEPOSITED"] = "%s золота вложено в банк отряда."
L["INSUFFICIENT_GOLD"] = "Недостаточно золота для вклада."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "Неверная сумма."
L["WITHDRAW_BANK_NOT_OPEN"] = "Банк должен быть открыт для снятия!"
L["WITHDRAW_IN_COMBAT"] = "Невозможно снять во время боя."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "Недостаточно золота в банке отряда."
L["WITHDRAWN_LABEL"] = "Снято:"
L["WITHDRAW_API_UNAVAILABLE"] = "API снятия недоступен."
L["SORT_IN_COMBAT"] = "Невозможно сортировать во время боя."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global: SEARCH
L["SEARCH_CATEGORY_FORMAT"] = "Поиск %s..."
L["BTN_SCAN"] = "Сканировать банк"
L["BTN_DEPOSIT"] = "Очередь вклада"
L["BTN_SORT"] = "Сортировать банк"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global: CLOSE
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global: SETTINGS
L["BTN_REFRESH"] = REFRESH -- Blizzard Global: REFRESH
L["BTN_CLEAR_QUEUE"] = "Очистить очередь"
L["BTN_DEPOSIT_ALL"] = "Вложить всё"
L["BTN_DEPOSIT_GOLD"] = "Вложить золото"
L["ENABLE"] = ENABLE or "Включить" -- Blizzard Global
L["ENABLE_MODULE"] = "Включить модуль"

-- Main Tabs (Blizzard Globals where available)
L["TAB_CHARACTERS"] = CHARACTER or "Персонажи" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "Предметы" -- Blizzard Global
L["TAB_STORAGE"] = "Хранилище"
L["TAB_PLANS"] = "Планы"
L["TAB_REPUTATION"] = REPUTATION or "Репутация" -- Blizzard Global
L["TAB_REPUTATIONS"] = "Репутации"
L["TAB_CURRENCY"] = CURRENCY or "Валюта" -- Blizzard Global
L["TAB_CURRENCIES"] = "Валюты"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "Статистика" -- Blizzard Global

-- Item Categories (Using Blizzard Globals where available)
L["CATEGORY_ALL"] = ALL or "Все предметы" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Экипировка" -- Blizzard Global
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Расходники" -- Blizzard Global
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Реагенты" -- Blizzard Global
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Торговые товары" -- Blizzard Global
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Предметы заданий" -- Blizzard Global
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Разное" -- Blizzard Global

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
L["HEADER_FAVORITES"] = FAVORITES or "Избранное" -- Blizzard Global
L["HEADER_CHARACTERS"] = CHARACTER or "Персонажи"
L["HEADER_CURRENT_CHARACTER"] = "ТЕКУЩИЙ ПЕРСОНАЖ"
L["HEADER_WARBAND_GOLD"] = "ЗОЛОТО ОТРЯДА"
L["HEADER_TOTAL_GOLD"] = "ВСЕГО ЗОЛОТА"
L["HEADER_REALM_GOLD"] = "ЗОЛОТО НА СЕРВЕРЕ"
L["HEADER_REALM_TOTAL"] = "ИТОГО НА СЕРВЕРЕ"
L["CHARACTER_LAST_SEEN_FORMAT"] = "Был в сети: %s"
L["CHARACTER_GOLD_FORMAT"] = "Золото: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "Суммарное золото всех персонажей на этом сервере"

-- Items Tab
L["ITEMS_HEADER"] = "Предметы банка"
L["ITEMS_HEADER_DESC"] = "Просмотр и управление банком отряда и личным банком"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " предметы..."
L["ITEMS_WARBAND_BANK"] = "Банк отряда"
L["ITEMS_PLAYER_BANK"] = BANK or "Личный банк" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Банк гильдии" -- Blizzard Global
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Экипировка"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Расходники"
L["GROUP_PROFESSION"] = "Профессия"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Реагенты"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Торговые товары"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Задание"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Разное"
L["GROUP_CONTAINER"] = "Контейнеры"

-- Storage Tab
L["STORAGE_HEADER"] = "Обозреватель хранилища"
L["STORAGE_HEADER_DESC"] = "Просмотр всех предметов по типу"
L["STORAGE_WARBAND_BANK"] = "Банк отряда"
L["STORAGE_PERSONAL_BANKS"] = "Личные банки"
L["STORAGE_TOTAL_SLOTS"] = "Всего ячеек"
L["STORAGE_FREE_SLOTS"] = "Свободных ячеек"
L["STORAGE_BAG_HEADER"] = "Сумки отряда"
L["STORAGE_PERSONAL_HEADER"] = "Личный банк"

-- Plans Tab
L["PLANS_MY_PLANS"] = "Мои планы"
L["PLANS_COLLECTIONS"] = "Планы коллекции"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "Добавить свой план"
L["PLANS_NO_RESULTS"] = "Результатов не найдено."
L["PLANS_ALL_COLLECTED"] = "Все предметы собраны!"
L["PLANS_RECIPE_HELP"] = "Щёлкните правой кнопкой мыши по рецептам в инвентаре, чтобы добавить их сюда."
L["COLLECTION_PLANS"] = "Планы коллекции"
L["SEARCH_PLANS"] = "Поиск планов..."
L["COMPLETED_PLANS"] = "Завершённые планы"
L["SHOW_COMPLETED"] = "Показать завершённые"

-- Plans Categories (Blizzard Globals where available)
L["CATEGORY_MY_PLANS"] = "Мои планы"
L["CATEGORY_DAILY_TASKS"] = "Ежедневные задания"
L["CATEGORY_MOUNTS"] = MOUNTS or "Средства передвижения" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "Питомцы" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "Игрушки" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Трансмогрификация" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "Иллюзии"
L["CATEGORY_TITLES"] = TITLES or "Титулы"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Достижения" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " репутация..."
L["REP_HEADER_WARBAND"] = "Репутация отряда"
L["REP_HEADER_CHARACTER"] = "Репутация персонажа"
L["REP_STANDING_FORMAT"] = "Статус: %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " валюта..."
L["CURRENCY_HEADER_WARBAND"] = "Переводимые в отряде"
L["CURRENCY_HEADER_CHARACTER"] = "Привязанные к персонажу"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "Рейды" -- Blizzard Global
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Подземелья" -- Blizzard Global
L["PVE_HEADER_DELVES"] = "Вылазки"
L["PVE_HEADER_WORLD_BOSS"] = "Мировые боссы"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "Статистика" -- Blizzard Global: STATISTICS
L["STATS_TOTAL_ITEMS"] = "Всего предметов"
L["STATS_TOTAL_SLOTS"] = "Всего ячеек"
L["STATS_FREE_SLOTS"] = "Свободных ячеек"
L["STATS_USED_SLOTS"] = "Занятых ячеек"
L["STATS_TOTAL_VALUE"] = "Общая стоимость"
L["COLLECTED"] = "Собрано"
L["TOTAL"] = "Всего"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Персонаж" -- Blizzard Global: CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Местоположение" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "Банк отряда"
L["TOOLTIP_TAB"] = "Вкладка"
L["TOOLTIP_SLOT"] = "Ячейка"
L["TOOLTIP_COUNT"] = "Количество"
L["CHARACTER_INVENTORY"] = "Инвентарь"
L["CHARACTER_BANK"] = "Банк"

-- Try Counter
L["TRY_COUNT"] = "Счётчик попыток"
L["SET_TRY_COUNT"] = "Установить попытки"
L["TRIES"] = "Попытки"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "Установить цикл сброса"
L["DAILY_RESET"] = "Ежедневный сброс"
L["WEEKLY_RESET"] = "Еженедельный сброс"
L["NONE_DISABLE"] = "Нет (Отключить)"
L["RESET_CYCLE_LABEL"] = "Цикл сброса:"
L["RESET_NONE"] = "Нет"
L["DOUBLECLICK_RESET"] = "Двойной клик для сброса позиции"

-- Error Messages
L["ERROR_GENERIC"] = "Произошла ошибка."
L["ERROR_API_UNAVAILABLE"] = "Необходимый API недоступен."
L["ERROR_BANK_CLOSED"] = "Невозможно выполнить операцию: банк закрыт."
L["ERROR_INVALID_ITEM"] = "Указан недопустимый предмет."
L["ERROR_PROTECTED_FUNCTION"] = "Невозможно вызвать защищённую функцию в бою."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "Вложить %d предметов в банк отряда?"
L["CONFIRM_CLEAR_QUEUE"] = "Очистить все предметы из очереди вклада?"
L["CONFIRM_DEPOSIT_GOLD"] = "Вложить %s золота в банк отряда?"

-- Update Notification
L["WHATS_NEW"] = "Что нового"
L["GOT_IT"] = "Понятно!"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "ОЧКИ ДОСТИЖЕНИЙ"
L["MOUNTS_COLLECTED"] = "СОБРАННЫЕ СРЕДСТВА ПЕРЕДВИЖЕНИЯ"
L["BATTLE_PETS"] = "БОЕВЫЕ ПИТОМЦЫ"
L["ACCOUNT_WIDE"] = "На весь аккаунт"
L["STORAGE_OVERVIEW"] = "Обзор хранилища"
L["WARBAND_SLOTS"] = "ЯЧЕЙКИ ОТРЯДА"
L["PERSONAL_SLOTS"] = "ЛИЧНЫЕ ЯЧЕЙКИ"
L["TOTAL_FREE"] = "ВСЕГО СВОБОДНО"
L["TOTAL_ITEMS"] = "ВСЕГО ПРЕДМЕТОВ"

-- Plans Tracker Window
L["WEEKLY_VAULT"] = "Еженедельное хранилище"
L["CUSTOM"] = "Своё"
L["NO_PLANS_IN_CATEGORY"] = "В этой категории нет планов.\nДобавьте планы на вкладке Планы."
L["SOURCE_LABEL"] = "Источник:"
L["ZONE_LABEL"] = "Зона:"
L["VENDOR_LABEL"] = "Торговец:"
L["DROP_LABEL"] = "Добыча:"
L["REQUIREMENT_LABEL"] = "Требование:"
L["RIGHT_CLICK_REMOVE"] = "ПКМ для удаления"
L["TRACKED"] = "Отслеживается"
L["TRACK"] = "Отслеживать"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Отслеживать в целях Blizzard (макс. 10)"
L["UNKNOWN"] = "Неизвестно"
L["NO_REQUIREMENTS"] = "Нет требований (мгновенное выполнение)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "Нет запланированных действий"
L["CLICK_TO_ADD_GOALS"] = "Нажмите на Средства передвижения, Питомцы или Игрушки выше, чтобы добавить цели!"
L["UNKNOWN_QUEST"] = "Неизвестное задание"
L["ALL_QUESTS_COMPLETE"] = "Все задания выполнены!"
L["CURRENT_PROGRESS"] = "Текущий прогресс"
L["SELECT_CONTENT"] = "Выберите контент:"
L["QUEST_TYPES"] = "Типы заданий:"
L["WORK_IN_PROGRESS"] = "В разработке"
L["RECIPE_BROWSER"] = "Браузер рецептов"
L["NO_RESULTS_FOUND"] = "Результатов не найдено."
L["TRY_ADJUSTING_SEARCH"] = "Попробуйте изменить поиск или фильтры."
L["NO_COLLECTED_YET"] = "Ещё нет собранных %s"
L["START_COLLECTING"] = "Начните собирать, чтобы увидеть их здесь!"
L["ALL_COLLECTED_CATEGORY"] = "Все %s собраны!"
L["COLLECTED_EVERYTHING"] = "Вы собрали всё в этой категории!"
L["PROGRESS_LABEL"] = "Прогресс:"
L["REQUIREMENTS_LABEL"] = "Требования:"
L["INFORMATION_LABEL"] = "Информация:"
L["DESCRIPTION_LABEL"] = "Описание:"
L["REWARD_LABEL"] = "Награда:"
L["DETAILS_LABEL"] = "Подробности:"
L["COST_LABEL"] = "Стоимость:"
L["LOCATION_LABEL"] = "Расположение:"
L["TITLE_LABEL"] = "Титул:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "Вы уже выполнили все достижения в этой категории!"
L["DAILY_PLAN_EXISTS"] = "Ежедневный план уже существует"
L["WEEKLY_PLAN_EXISTS"] = "Еженедельный план уже существует"

-- =============================================
-- Characters Tab
-- =============================================
L["YOUR_CHARACTERS"] = "Ваши персонажи"
L["CHARACTERS_TRACKED_FORMAT"] = "%d персонажей отслеживается"
L["NO_CHARACTER_DATA"] = "Нет данных о персонажах"
L["NO_FAVORITES"] = "Пока нет избранных персонажей. Нажмите на значок звезды, чтобы добавить персонажа в избранное."
L["ALL_FAVORITED"] = "Все персонажи в избранном!"
L["UNTRACKED_CHARACTERS"] = "Неотслеживаемые персонажи"
L["ILVL_SHORT"] = "iLvl"
L["ONLINE"] = "В сети"
L["TIME_LESS_THAN_MINUTE"] = "< 1 мин назад"
L["TIME_MINUTES_FORMAT"] = "%d мин назад"
L["TIME_HOURS_FORMAT"] = "%d ч назад"
L["TIME_DAYS_FORMAT"] = "%d дн назад"
L["REMOVE_FROM_FAVORITES"] = "Удалить из избранного"
L["ADD_TO_FAVORITES"] = "Добавить в избранное"
L["FAVORITES_TOOLTIP"] = "Избранные персонажи отображаются вверху списка"
L["CLICK_TO_TOGGLE"] = "Нажмите для переключения"
L["UNKNOWN_PROFESSION"] = "Неизвестная профессия"
L["SKILL_LABEL"] = "Навык:"
L["OVERALL_SKILL"] = "Общий навык:"
L["BONUS_SKILL"] = "Бонусный навык:"
L["KNOWLEDGE_LABEL"] = "Знание:"
L["SPEC_LABEL"] = "Спец."
L["POINTS_SHORT"] = "очк."
L["RECIPES_KNOWN"] = "Известные рецепты:"
L["OPEN_PROFESSION_HINT"] = "Открыть окно профессии"
L["FOR_DETAILED_INFO"] = "для подробной информации"
L["CHARACTER_IS_TRACKED"] = "Этот персонаж отслеживается."
L["TRACKING_ACTIVE_DESC"] = "Сбор данных и обновления активны."
L["CLICK_DISABLE_TRACKING"] = "Нажмите, чтобы отключить отслеживание."
L["MUST_LOGIN_TO_CHANGE"] = "Вы должны войти этим персонажем, чтобы изменить отслеживание."
L["TRACKING_ENABLED"] = "Отслеживание включено"
L["CLICK_ENABLE_TRACKING"] = "Нажмите, чтобы включить отслеживание для этого персонажа."
L["TRACKING_WILL_BEGIN"] = "Сбор данных начнётся немедленно."
L["CHARACTER_NOT_TRACKED"] = "Этот персонаж не отслеживается."
L["MUST_LOGIN_TO_ENABLE"] = "Вы должны войти этим персонажем, чтобы включить отслеживание."
L["ENABLE_TRACKING"] = "Включить отслеживание"
L["DELETE_CHARACTER_TITLE"] = "Удалить персонажа?"
L["THIS_CHARACTER"] = "этого персонажа"
L["DELETE_CHARACTER"] = "Удалить персонажа"
L["REMOVE_FROM_TRACKING_FORMAT"] = "Удалить %s из отслеживания"
L["CLICK_TO_DELETE"] = "Нажмите для удаления"
L["CONFIRM_DELETE"] = "Вы уверены, что хотите удалить |cff00ccff%s|r?"
L["CANNOT_UNDO"] = "Это действие нельзя отменить!"
L["DELETE"] = DELETE or "Удалить"
L["CANCEL"] = CANCEL or "Отмена"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "Личные предметы"
L["ITEMS_SUBTITLE"] = "Просмотр банка отряда и личных предметов (Банк + Инвентарь)"
L["ITEMS_DISABLED_TITLE"] = "Предметы банка отряда"
L["ITEMS_LOADING"] = "Загрузка данных инвентаря"
L["GUILD_BANK_REQUIRED"] = "Вы должны состоять в гильдии для доступа к банку гильдии."
L["ITEMS_SEARCH"] = "Поиск предметов..."
L["NEVER"] = "Никогда"
L["ITEM_FALLBACK_FORMAT"] = "Предмет %s"
L["TAB_FORMAT"] = "Вкладка %d"
L["BAG_FORMAT"] = "Сумка %d"
L["BANK_BAG_FORMAT"] = "Банковская сумка %d"
L["ITEM_ID_LABEL"] = "ID предмета:"
L["QUALITY_TOOLTIP_LABEL"] = "Качество:"
L["STACK_LABEL"] = "Стопка:"
L["RIGHT_CLICK_MOVE"] = "Переместить в сумку"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Разделить стопку"
L["LEFT_CLICK_PICKUP"] = "Поднять"
L["ITEMS_BANK_NOT_OPEN"] = "Банк не открыт"
L["SHIFT_LEFT_CLICK_LINK"] = "Ссылка в чат"
L["ITEM_DEFAULT_TOOLTIP"] = "Предмет"
L["ITEMS_STATS_ITEMS"] = "%s предметов"
L["ITEMS_STATS_SLOTS"] = "%s/%s ячеек"
L["ITEMS_STATS_LAST"] = "Последний: %s"

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "Хранилище персонажа"
L["STORAGE_SEARCH"] = "Поиск в хранилище..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "Прогресс PvE"
L["PVE_SUBTITLE"] = "Великое хранилище, блокировки рейдов и Мифический+ по всему отряду"
L["PVE_NO_CHARACTER"] = "Нет данных о персонаже"
L["LV_FORMAT"] = "Ур. %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = "Рейд"
L["VAULT_DUNGEON"] = "Подземелье"
L["VAULT_WORLD"] = "Мир"
L["VAULT_SLOT_FORMAT"] = "%s Ячейка %d"
L["VAULT_NO_PROGRESS"] = "Прогресса пока нет"
L["VAULT_UNLOCK_FORMAT"] = "Завершите %s активностей для разблокировки"
L["VAULT_NEXT_TIER_FORMAT"] = "Следующий уровень: %d iLvl при завершении %s"
L["VAULT_REMAINING_FORMAT"] = "Осталось: %s активностей"
L["VAULT_PROGRESS_FORMAT"] = "Прогресс: %s / %s"
L["OVERALL_SCORE_LABEL"] = "Общий счёт:"
L["BEST_KEY_FORMAT"] = "Лучший ключ: +%d"
L["SCORE_FORMAT"] = "Счёт: %s"
L["NOT_COMPLETED_SEASON"] = "Не завершено в этом сезоне"
L["CURRENT_MAX_FORMAT"] = "Текущий: %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "Прогресс: %.1f%%"
L["NO_CAP_LIMIT"] = "Нет лимита"
L["GREAT_VAULT"] = "Великое хранилище"
L["LOADING_PVE"] = "Загрузка данных PvE..."
L["PVE_APIS_LOADING"] = "Подождите, API WoW инициализируются..."
L["NO_VAULT_DATA"] = "Нет данных хранилища"
L["NO_DATA"] = "Нет данных"
L["KEYSTONE"] = "Ключ"
L["NO_KEY"] = "Нет ключа"
L["AFFIXES"] = "Модификаторы"
L["NO_AFFIXES"] = "Нет модификаторов"
L["VAULT_BEST_KEY"] = "Лучший ключ:"
L["VAULT_SCORE"] = "Счёт:"

-- =============================================
-- Reputation Tab
-- =============================================
L["REP_TITLE"] = "Обзор репутации"
L["REP_SUBTITLE"] = "Отслеживание фракций и известности по всему отряду"
L["REP_DISABLED_TITLE"] = "Отслеживание репутации"
L["REP_LOADING_TITLE"] = "Загрузка данных репутации"
L["REP_SEARCH"] = "Поиск репутаций..."
L["REP_PARAGON_TITLE"] = "Репутация совершенства"
L["REP_REWARD_AVAILABLE"] = "Награда доступна!"
L["REP_CONTINUE_EARNING"] = "Продолжайте зарабатывать репутацию для наград"
L["REP_CYCLES_FORMAT"] = "Циклы: %d"
L["REP_PROGRESS_HEADER"] = "Прогресс: %d/%d"
L["REP_PARAGON_PROGRESS"] = "Прогресс совершенства:"
L["REP_PROGRESS_COLON"] = "Прогресс:"
L["REP_CYCLES_COLON"] = "Циклы:"
L["REP_CHARACTER_PROGRESS"] = "Прогресс персонажа:"
L["REP_RENOWN_FORMAT"] = "Известность %d"
L["REP_PARAGON_FORMAT"] = "Совершенство (%s)"
L["REP_UNKNOWN_FACTION"] = "Неизвестная фракция"
L["REP_API_UNAVAILABLE_TITLE"] = "API репутации недоступен"
L["REP_API_UNAVAILABLE_DESC"] = "API C_Reputation недоступен на этом сервере. Эта функция требует WoW 11.0+ (The War Within)."
L["REP_FOOTER_TITLE"] = "Отслеживание репутации"
L["REP_FOOTER_DESC"] = "Репутации сканируются автоматически при входе и при изменении. Используйте панель репутации в игре для подробной информации и наград."
L["REP_CLEARING_CACHE"] = "Очистка кэша и перезагрузка..."
L["REP_LOADING_DATA"] = "Загрузка данных репутации..."
L["REP_MAX"] = "Макс."
L["REP_TIER_FORMAT"] = "Уровень %d"
L["ACCOUNT_WIDE_LABEL"] = "На весь аккаунт"
L["NO_RESULTS"] = "Нет результатов"
L["NO_REP_MATCH"] = "Нет репутаций, соответствующих '%s'"
L["NO_REP_DATA"] = "Нет данных о репутации"
L["REP_SCAN_TIP"] = "Репутации сканируются автоматически. Попробуйте /reload, если ничего не появляется."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "Репутации на весь аккаунт (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "Нет репутаций на весь аккаунт"
L["NO_CHARACTER_REPS"] = "Нет репутаций персонажа"

-- =============================================
-- Currency Tab
-- =============================================
L["CURRENCY_TITLE"] = "Отслеживание валюты"
L["CURRENCY_SUBTITLE"] = "Отслеживание всех валют ваших персонажей"
L["CURRENCY_DISABLED_TITLE"] = "Отслеживание валюты"
L["CURRENCY_LOADING_TITLE"] = "Загрузка данных валюты"
L["CURRENCY_SEARCH"] = "Поиск валют..."
L["CURRENCY_HIDE_EMPTY"] = "Скрыть пустые"
L["CURRENCY_SHOW_EMPTY"] = "Показать пустые"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "Все переводимые в отряде"
L["CURRENCY_CHARACTER_SPECIFIC"] = "Валюты, привязанные к персонажу"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "Ограничение перевода валюты"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "API Blizzard не поддерживает автоматические переводы валюты. Пожалуйста, используйте окно валюты в игре для ручного перевода валют отряда."
L["CURRENCY_UNKNOWN"] = "Неизвестная валюта"

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "Удалить все завершённые планы из списка Мои планы. Это удалит все завершённые пользовательские планы и удалит собранные средства передвижения/питомцев/игрушки из ваших планов. Это действие нельзя отменить!"
L["RECIPE_BROWSER_DESC"] = "Откройте окно профессии в игре для просмотра рецептов.\nАддон будет сканировать доступные рецепты, когда окно открыто."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "Источник: [Достижение %s]"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s уже имеет активный план еженедельного хранилища. Вы можете найти его в категории 'Мои планы'."
L["DAILY_PLAN_EXISTS_DESC"] = "%s уже имеет активный план ежедневных заданий. Вы можете найти его в категории 'Ежедневные задания'."
L["TRANSMOG_WIP_DESC"] = "Отслеживание коллекции трансмогрификации находится в разработке.\n\nЭта функция будет доступна в будущем обновлении с улучшенной\nпроизводительностью и лучшей интеграцией с системами отряда."
L["WEEKLY_VAULT_CARD"] = "Карточка еженедельного хранилища"
L["WEEKLY_VAULT_COMPLETE"] = "Карточка еженедельного хранилища - Завершено"
L["UNKNOWN_SOURCE"] = "Неизвестный источник"
L["DAILY_TASKS_PREFIX"] = "Ежедневные задания - "
L["NO_FOUND_FORMAT"] = "Не найдено %s"
L["PLANS_COUNT_FORMAT"] = "%d планов"
L["PET_BATTLE_LABEL"] = "Бой питомцев:"
L["QUEST_LABEL"] = "Задание:"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "Текущий язык:"
L["LANGUAGE_TOOLTIP"] = "Аддон автоматически использует язык вашего клиента WoW. Для изменения обновите настройки Battle.net."
L["POPUP_DURATION"] = "Длительность уведомления"
L["POPUP_POSITION"] = "Позиция уведомления"
L["SET_POSITION"] = "Установить позицию"
L["DRAG_TO_POSITION"] = "Перетащите для позиционирования\nПКМ для подтверждения"
L["RESET_DEFAULT"] = "Сбросить по умолчанию"
L["TEST_POPUP"] = "Тест уведомления"
L["CUSTOM_COLOR"] = "Свой цвет"
L["OPEN_COLOR_PICKER"] = "Открыть палитру цветов"
L["COLOR_PICKER_TOOLTIP"] = "Откройте стандартную палитру цветов WoW, чтобы выбрать свой цвет темы"
L["PRESET_THEMES"] = "Готовые темы"
L["WARBAND_NEXUS_SETTINGS"] = "Настройки Warband Nexus"
L["NO_OPTIONS"] = "Нет опций"
L["NONE_LABEL"] = NONE or "Нет"
L["TAB_FILTERING"] = "Фильтрация вкладок"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Уведомления"
L["SCROLL_SPEED"] = "Скорость прокрутки"
L["ANCHOR_FORMAT"] = "Якорь: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "Показать еженедельный планировщик"
L["LOCK_MINIMAP_ICON"] = "Заблокировать значок на миникарте"
L["AUTO_SCAN_ITEMS"] = "Автосканирование предметов"
L["LIVE_SYNC"] = "Синхронизация в реальном времени"
L["BACKPACK_LABEL"] = "Рюкзак"
L["REAGENT_LABEL"] = "Реагенты"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "Модуль отключён"
L["LOADING"] = "Загрузка..."
L["PLEASE_WAIT"] = "Подождите..."
L["RESET_PREFIX"] = "Сброс:"
L["TRANSFER_CURRENCY"] = "Перевести валюту"
L["AMOUNT_LABEL"] = "Сумма:"
L["TO_CHARACTER"] = "Персонажу:"
L["SELECT_CHARACTER"] = "Выберите персонажа..."
L["CURRENCY_TRANSFER_INFO"] = "Окно валюты будет открыто автоматически.\nВам нужно будет вручную щёлкнуть правой кнопкой мыши по валюте для перевода."
L["OK_BUTTON"] = OKAY or "ОК"
L["SAVE"] = "Сохранить"
L["TITLE_FIELD"] = "Название:"
L["DESCRIPTION_FIELD"] = "Описание:"
L["CREATE_CUSTOM_PLAN"] = "Создать свой план"
L["REPORT_BUGS"] = "Сообщите об ошибках или поделитесь предложениями на CurseForge, чтобы помочь улучшить аддон."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus предоставляет централизованный интерфейс для управления всеми вашими персонажами, валютами, репутациями, предметами и прогрессом PvE по всему отряду."
L["CHARACTERS_DESC"] = "Просмотр всех персонажей с золотом, уровнем, iLvl, фракцией, расой, классом, профессиями, ключом и временем последней игры. Отслеживание и удаление персонажей, отметка избранных."
L["ITEMS_DESC"] = "Поиск и просмотр предметов во всех сумках, банках и банке военной группы. Автосканирование при открытии банка. Подсказки показывают, у каких персонажей есть каждый предмет."
L["STORAGE_DESC"] = "Обобщённый инвентарь всех персонажей — сумки, личный банк и банк военной группы в одном месте."
L["PVE_DESC"] = "Отслеживание Великого хранилища с индикаторами уровня, рейтинги и ключи Мифический+, аффиксы, история подземелий и валюта улучшения для всех персонажей."
L["REPUTATIONS_DESC"] = "Сравнение прогресса репутации по всем персонажам. Показывает фракции аккаунта и персонажа с подсказками при наведении для разбивки по персонажам."
L["CURRENCY_DESC"] = "Просмотр всех валют по дополнениям. Сравнение сумм между персонажами с подсказками при наведении. Скрытие пустых валют одним кликом."
L["PLANS_DESC"] = "Отслеживание несобранных маунтов, питомцев, игрушек, достижений и трансмога. Добавление целей, просмотр источников дропа и счётчиков попыток. Доступ через /wn plan или значок миникарты."
L["STATISTICS_DESC"] = "Просмотр очков достижений, прогресса коллекции маунтов/питомцев/игрушек/иллюзий/титулов, счётчика уникальных питомцев и статистики использования сумок/банков."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "Мифический"
L["DIFFICULTY_HEROIC"] = "Героический"
L["DIFFICULTY_NORMAL"] = "Обычный"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Уровень %d"
L["PVP_TYPE"] = "PvP"
L["PREPARING"] = "Подготовка"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Статистика аккаунта"
L["STATISTICS_SUBTITLE"] = "Прогресс коллекции, золото и обзор хранилища"
L["MOST_PLAYED"] = "САМЫЕ ИГРАЕМЫЕ"
L["PLAYED_DAYS"] = "Дней"
L["PLAYED_HOURS"] = "Часов"
L["PLAYED_MINUTES"] = "Минут"
L["PLAYED_DAY"] = "День"
L["PLAYED_HOUR"] = "Час"
L["PLAYED_MINUTE"] = "Минута"
L["MORE_CHARACTERS"] = "ещё персонаж"
L["MORE_CHARACTERS_PLURAL"] = "ещё персонажей"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "Добро пожаловать в Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "Обзор аддона"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "Отслеживание целей коллекции"
L["ACTIVE_PLAN_FORMAT"] = "%d активный план"
L["ACTIVE_PLANS_FORMAT"] = "%d активных планов"
L["RESET_LABEL"] = RESET or "Сброс"

-- Plans - Type Names
L["TYPE_MOUNT"] = MOUNT or "Средство передвижения"
L["TYPE_PET"] = PET or "Питомец"
L["TYPE_TOY"] = TOY or "Игрушка"
L["TYPE_RECIPE"] = "Рецепт"
L["TYPE_ILLUSION"] = "Иллюзия"
L["TYPE_TITLE"] = "Титул"
L["TYPE_CUSTOM"] = "Свой"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Трансмогрификация"

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Добыча"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Задание"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Торговец"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Профессия"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Битва питомцев"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Достижение"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "Мировое событие"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Акция"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "Коллекционная карточная игра"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "Внутриигровой магазин"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "Создано"
L["SOURCE_TYPE_TRADING_POST"] = "Торговый пост"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "Неизвестно"
L["SOURCE_TYPE_PVP"] = PVP or "PvP"
L["SOURCE_TYPE_TREASURE"] = "Сокровище"
L["SOURCE_TYPE_PUZZLE"] = "Головоломка"
L["SOURCE_TYPE_RENOWN"] = "Известность"

-- Plans - Transmog Source Labels (Blizzard TRANSMOG_SOURCE_* Globals)
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Добыча с боссов"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Задание"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Торговец"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "Мировая добыча"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Достижение"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Профессия"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
L["PARSE_SOLD_BY"] = "Продается"
L["PARSE_CRAFTED"] = "Изготовлено"
L["PARSE_ZONE"] = ZONE or "Зона"
L["PARSE_COST"] = "Стоимость"
L["PARSE_REPUTATION"] = REPUTATION or "Репутация"
L["PARSE_FACTION"] = FACTION or "Фракция"
L["PARSE_ARENA"] = ARENA or "Арена"
L["PARSE_DUNGEON"] = DUNGEONS or "Подземелье"
L["PARSE_RAID"] = RAID or "Рейд"
L["PARSE_HOLIDAY"] = "Праздник"
L["PARSE_RATED"] = "Рейтинговый"
L["PARSE_BATTLEGROUND"] = "Поле боя"
L["PARSE_DISCOVERY"] = "Открытие"
L["PARSE_CONTAINED_IN"] = "Содержится в"
L["PARSE_GARRISON"] = "Гарнизон"
L["PARSE_GARRISON_BUILDING"] = "Здание гарнизона"
L["PARSE_STORE"] = "Магазин"
L["PARSE_ORDER_HALL"] = "Зал ордена"
L["PARSE_COVENANT"] = "Ковенант"
L["PARSE_FRIENDSHIP"] = "Дружба"
L["PARSE_PARAGON"] = "Идеал"
L["PARSE_MISSION"] = "Задание"
L["PARSE_EXPANSION"] = "Дополнение"
L["PARSE_SCENARIO"] = "Сценарий"
L["PARSE_CLASS_HALL"] = "Зал ордена"
L["PARSE_CAMPAIGN"] = "Кампания"
L["PARSE_EVENT"] = "Событие"
L["PARSE_SPECIAL"] = "Особое"
L["PARSE_BRAWLERS_GUILD"] = "Бойцовская гильдия"
L["PARSE_CHALLENGE_MODE"] = "Испытание"
L["PARSE_MYTHIC_PLUS"] = "Эпохальный+"
L["PARSE_TIMEWALKING"] = "Путешествие во времени"
L["PARSE_ISLAND_EXPEDITION"] = "Островная экспедиция"
L["PARSE_WARFRONT"] = "Фронт"
L["PARSE_TORGHAST"] = "Торгаст"
L["PARSE_ZERETH_MORTIS"] = "Зерет Мортис"
L["PARSE_HIDDEN"] = "Скрытый"
L["PARSE_RARE"] = "Редкий"
L["PARSE_WORLD_BOSS"] = "Мировой босс"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Добыча"
L["PARSE_NPC"] = "НИП"
L["PARSE_FROM_ACHIEVEMENT"] = "Из достижения"
L["FALLBACK_UNKNOWN_PET"] = "Неизвестный питомец"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "Коллекция питомцев"
L["FALLBACK_TOY_COLLECTION"] = "Коллекция игрушек"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Коллекция трансмогрификации"
L["FALLBACK_PLAYER_TITLE"] = "Звание игрока"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Неизвестно"
L["FALLBACK_ILLUSION_FORMAT"] = "Иллюзия %s"
L["SOURCE_ENCHANTING"] = "Наложение чар"

-- Plans - Dialogs
L["SET_TRY_COUNT_TEXT"] = "Установить количество попыток для:\n%s"
L["RESET_COMPLETED_CONFIRM"] = "Вы уверены, что хотите удалить ВСЕ завершённые планы?\n\nЭто нельзя отменить!"
L["YES_RESET"] = "Да, сбросить"
L["REMOVED_PLANS_FORMAT"] = "Удалено %d завершённых планов."

-- Plans - Buttons
L["ADD_CUSTOM"] = "Добавить свой"
L["ADD_VAULT"] = "Добавить хранилище"
L["ADD_QUEST"] = "Добавить задание"
L["CREATE_PLAN"] = "Создать план"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "Ежедневные"
L["QUEST_CAT_WORLD"] = "Мир"
L["QUEST_CAT_WEEKLY"] = "Еженедельные"
L["QUEST_CAT_ASSIGNMENT"] = "Поручение"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Неизвестная категория"
L["SCANNING_FORMAT"] = "Сканирование %s"
L["CUSTOM_PLAN_SOURCE"] = "Свой план"
L["POINTS_FORMAT"] = "%d очков"
L["SOURCE_NOT_AVAILABLE"] = "Информация об источнике недоступна"
L["PROGRESS_ON_FORMAT"] = "Вы на %d/%d в прогрессе"
L["COMPLETED_REQ_FORMAT"] = "Вы выполнили %d из %d общих требований"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Midnight"
L["CONTENT_TWW"] = "The War Within"
L["QUEST_TYPE_DAILY"] = "Ежедневные задания"
L["QUEST_TYPE_DAILY_DESC"] = "Обычные ежедневные задания от NPC"
L["QUEST_TYPE_WORLD"] = "Задания мира"
L["QUEST_TYPE_WORLD_DESC"] = "Задания мира по всей зоне"
L["QUEST_TYPE_WEEKLY"] = "Еженедельные задания"
L["QUEST_TYPE_WEEKLY_DESC"] = "Еженедельные повторяющиеся задания"
L["QUEST_TYPE_ASSIGNMENTS"] = "Поручения"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "Специальные поручения и задачи"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "М+"
L["RAIDS_LABEL"] = "Рейды"

-- PlanCardFactory
L["FACTION_LABEL"] = "Фракция:"
L["FRIENDSHIP_LABEL"] = "Дружба"
L["RENOWN_TYPE_LABEL"] = "Известность"
L["ADD_BUTTON"] = "+ Добавить"
L["ADDED_LABEL"] = "Добавлено"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s из %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Отображать количество в стопке на предметах в представлении хранилища"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Отображать раздел еженедельного планировщика на вкладке Персонажи"
L["LOCK_MINIMAP_TOOLTIP"] = "Заблокировать значок на миникарте на месте (предотвращает перетаскивание)"
L["AUTO_SCAN_TOOLTIP"] = "Автоматически сканировать и кэшировать предметы при открытии банков или сумок"
L["LIVE_SYNC_TOOLTIP"] = "Обновлять кэш предметов в реальном времени, пока банки открыты"
L["SHOW_ILVL_TOOLTIP"] = "Отображать значки уровня предметов на экипировке в списке предметов"
L["SCROLL_SPEED_TOOLTIP"] = "Множитель скорости прокрутки (1.0x = 28 пикселей за шаг)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "Игнорировать вкладку банка отряда %d при автоматическом сканировании"
L["IGNORE_SCAN_FORMAT"] = "Игнорировать %s при автоматическом сканировании"
L["BANK_LABEL"] = BANK or "Банк"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "Включить уведомления"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Главный переключатель для всех всплывающих уведомлений"
L["VAULT_REMINDER"] = "Напоминание о хранилище"
L["VAULT_REMINDER_TOOLTIP"] = "Показывать напоминание, когда у вас есть неполученные награды еженедельного хранилища"
L["LOOT_ALERTS"] = "Оповещения о добыче"
L["LOOT_ALERTS_TOOLTIP"] = "Показывать уведомление, когда НОВОЕ средство передвижения, питомец или игрушка попадает в вашу сумку"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Скрыть оповещение о достижении Blizzard"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Скрыть стандартное всплывающее окно достижения Blizzard и использовать уведомление Warband Nexus вместо этого"
L["REPUTATION_GAINS"] = "Прирост репутации"
L["REPUTATION_GAINS_TOOLTIP"] = "Показывать сообщения в чате, когда вы получаете репутацию у фракций"
L["CURRENCY_GAINS"] = "Прирост валюты"
L["CURRENCY_GAINS_TOOLTIP"] = "Показывать сообщения в чате, когда вы получаете валюту"
L["DURATION_LABEL"] = "Длительность"
L["DAYS_LABEL"] = "дней"
L["WEEKS_LABEL"] = "недель"
L["EXTEND_DURATION"] = "Продлить срок"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Перетащите зелёную рамку, чтобы установить позицию всплывающего окна. ПКМ для подтверждения."
L["POSITION_RESET_MSG"] = "Позиция всплывающего окна сброшена на значение по умолчанию (Верхний центр)"
L["POSITION_SAVED_MSG"] = "Позиция всплывающего окна сохранена!"
L["TEST_NOTIFICATION_TITLE"] = "Тестовое уведомление"
L["TEST_NOTIFICATION_MSG"] = "Тест позиции"
L["NOTIFICATION_DEFAULT_TITLE"] = "Уведомление"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
L["THEME_APPEARANCE"] = "Тема и внешний вид"
L["COLOR_PURPLE"] = "Фиолетовый"
L["COLOR_PURPLE_DESC"] = "Классическая фиолетовая тема (по умолчанию)"
L["COLOR_BLUE"] = "Синий"
L["COLOR_BLUE_DESC"] = "Холодная синяя тема"
L["COLOR_GREEN"] = "Зелёный"
L["COLOR_GREEN_DESC"] = "Природная зелёная тема"
L["COLOR_RED"] = "Красный"
L["COLOR_RED_DESC"] = "Огненная красная тема"
L["COLOR_ORANGE"] = "Оранжевый"
L["COLOR_ORANGE_DESC"] = "Тёплая оранжевая тема"
L["COLOR_CYAN"] = "Голубой"
L["COLOR_CYAN_DESC"] = "Яркая голубая тема"

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "Семейство шрифтов"
L["FONT_FAMILY_TOOLTIP"] = "Выберите шрифт, используемый во всём интерфейсе аддона"
L["FONT_SCALE"] = "Масштаб шрифта"
L["FONT_SCALE_TOOLTIP"] = "Настройка размера шрифта для всех элементов интерфейса"
L["RESOLUTION_NORMALIZATION"] = "Нормализация разрешения"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Настройка размеров шрифтов на основе разрешения экрана и масштаба интерфейса, чтобы текст оставался одного физического размера на разных мониторах"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Дополнительно"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Уровень предмета %s"
L["ITEM_NUMBER_FORMAT"] = "Предмет #%s"
L["CHARACTER_CURRENCIES"] = "Валюты персонажа:"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "Учётная запись (Боевой отряд) — один баланс для всех персонажей."
L["YOU_MARKER"] = "(Вы)"
L["WN_SEARCH"] = "WN Поиск"
L["WARBAND_BANK_COLON"] = "Банк отряда:"
L["AND_MORE_FORMAT"] = "... и ещё %d"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "Вы собрали средство передвижения"
L["COLLECTED_PET_MSG"] = "Вы собрали боевого питомца"
L["COLLECTED_TOY_MSG"] = "Вы собрали игрушку"
L["COLLECTED_ILLUSION_MSG"] = "Вы собрали иллюзию"
L["ACHIEVEMENT_COMPLETED_MSG"] = "Достижение завершено!"
L["EARNED_TITLE_MSG"] = "Вы получили титул"
L["COMPLETED_PLAN_MSG"] = "Вы завершили план"
L["DAILY_QUEST_CAT"] = "Ежедневное задание"
L["WORLD_QUEST_CAT"] = "Задание мира"
L["WEEKLY_QUEST_CAT"] = "Еженедельное задание"
L["SPECIAL_ASSIGNMENT_CAT"] = "Специальное поручение"
L["DELVE_CAT"] = "Вылазка"
L["DUNGEON_CAT"] = "Подземелье"
L["RAID_CAT"] = "Рейд"
L["WORLD_CAT"] = "Мир"
L["ACTIVITY_CAT"] = "Активность"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Прогресс"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Прогресс завершён"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "План еженедельного хранилища - %s"
L["ALL_SLOTS_COMPLETE"] = "Все ячейки завершены!"
L["QUEST_COMPLETED_SUFFIX"] = "Завершено"
L["WEEKLY_VAULT_READY"] = "Еженедельное хранилище готово!"
L["UNCLAIMED_REWARDS"] = "У вас есть неполученные награды"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "Всего золота:"
L["CHARACTERS_COLON"] = "Персонажи:"
L["LEFT_CLICK_TOGGLE"] = "ЛКМ: Переключить окно"
L["RIGHT_CLICK_PLANS"] = "ПКМ: Открыть планы"
L["MINIMAP_SHOWN_MSG"] = "Кнопка на миникарте показана"
L["MINIMAP_HIDDEN_MSG"] = "Кнопка на миникарте скрыта (используйте /wn minimap для показа)"
L["TOGGLE_WINDOW"] = "Переключить окно"
L["SCAN_BANK_MENU"] = "Сканировать банк"
L["TRACKING_DISABLED_SCAN_MSG"] = "Отслеживание персонажей отключено. Включите отслеживание в настройках для сканирования банка."
L["SCAN_COMPLETE_MSG"] = "Сканирование завершено!"
L["BANK_NOT_OPEN_MSG"] = "Банк не открыт"
L["OPTIONS_MENU"] = "Настройки"
L["HIDE_MINIMAP_BUTTON"] = "Скрыть кнопку на миникарте"
L["MENU_UNAVAILABLE_MSG"] = "Контекстное меню недоступно"
L["USE_COMMANDS_MSG"] = "Используйте /wn show, /wn scan, /wn config"

-- =============================================
-- SharedWidgets (extended)
-- =============================================
L["MAX_BUTTON"] = "Макс"
L["OPEN_AND_GUIDE"] = "Открыть и руководство"
L["FROM_LABEL"] = "От:"
L["AVAILABLE_LABEL"] = "Доступно:"
L["ONLINE_LABEL"] = "(В сети)"
L["DATA_SOURCE_TITLE"] = "Информация об источнике данных"
L["DATA_SOURCE_USING"] = "Эта вкладка использует:"
L["DATA_SOURCE_MODERN"] = "Современный сервис кэша (на основе событий)"
L["DATA_SOURCE_LEGACY"] = "Устаревший прямой доступ к БД"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Требуется миграция на сервис кэша"
L["GLOBAL_DB_VERSION"] = "Версия глобальной БД:"

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "Персонажи"
L["INFO_TAB_ITEMS"] = "Предметы"
L["INFO_TAB_STORAGE"] = "Хранилище"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "Репутации"
L["INFO_TAB_CURRENCY"] = "Валюта"
L["INFO_TAB_PLANS"] = "Планы"
L["INFO_TAB_STATISTICS"] = "Статистика"
L["SPECIAL_THANKS"] = "Особая благодарность"
L["SUPPORTERS_TITLE"] = "Поддерживающие"
L["THANK_YOU_MSG"] = "Спасибо за использование Warband Nexus!"

-- =============================================
-- Changelog (What's New) - v2.0.0
-- =============================================
L["CHANGELOG_V200"] = "НОВЫЕ ФУНКЦИИ:\n" ..
    "- Отслеживание персонажей: Выберите, каких персонажей отслеживать или убрать из отслеживания.\n" ..
    "- Умное отслеживание валюты и репутации: Уведомления в чате в реальном времени с прогрессом.\n" ..
    "- Счётчик попыток маунтов: Отслеживайте ваши попытки получить дроп (В разработке).\n" ..
    "- Отслеживание инвентаря + банка + банка военной группы: Отслеживание предметов во всех хранилищах.\n" ..
    "- Система подсказок: Совершенно новый пользовательский фреймворк подсказок.\n" ..
    "- Подсказка отслеживания предметов: Смотрите, у каких персонажей есть предмет при наведении.\n" ..
    "- Вкладка Планы: Отслеживайте следующие цели — маунты, питомцы, игрушки, достижения, трансмог.\n" ..
    "- Окно Планов: Быстрый доступ через /wn plan или правый клик по значку миникарты.\n" ..
    "- Умное отслеживание данных аккаунта: Автоматическая синхронизация данных военной группы.\n" ..
    "- Локализация: Поддержка 11 языков.\n" ..
    "- Сравнение репутации и валюты: Подсказки при наведении показывают разбивку по персонажам.\n" ..
    "- Система уведомлений: Напоминания о добыче, достижениях и хранилище.\n" ..
    "- Пользовательская система шрифтов: Выберите предпочтительный шрифт и масштаб.\n" ..
    "\n" ..
    "УЛУЧШЕНИЯ:\n" ..
    "- Данные персонажа: Добавлены фракция, раса, iLvl и информация о ключе.\n" ..
    "- Интерфейс банка отключён (заменён улучшенным Хранилищем).\n" ..
    "- Личные предметы: Отслеживает ваш банк + инвентарь.\n" ..
    "- Хранилище: Отслеживает банк + инвентарь + банк военной группы всех персонажей.\n" ..
    "- PvE: Индикатор уровня хранилища, рейтинг/трекер подземелий, аффиксы, валюта улучшения.\n" ..
    "- Вкладка Репутация: Упрощённый вид (старая система фильтров удалена).\n" ..
    "- Вкладка Валюта: Упрощённый вид (старая система фильтров удалена).\n" ..
    "- Статистика: Добавлен счётчик уникальных питомцев.\n" ..
    "- Настройки: Пересмотрены и реорганизованы.\n" ..
    "\n" ..
    "Спасибо за ваше терпение и интерес.\n" ..
    "\n" ..
    "Чтобы сообщить о проблемах или поделиться отзывом, оставьте комментарий на CurseForge - Warband Nexus."

-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "Подтвердить действие"
L["CONFIRM"] = "Подтвердить"
L["ENABLE_TRACKING_FORMAT"] = "Включить отслеживание для |cffffcc00%s|r?"
L["DISABLE_TRACKING_FORMAT"] = "Отключить отслеживание для |cffffcc00%s|r?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "Репутации на весь аккаунт (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Репутации персонажа (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "Награда ожидает"
L["REP_PARAGON_LABEL"] = "Совершенство"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "Подготовка..."
L["REP_LOADING_INITIALIZING"] = "Инициализация..."
L["REP_LOADING_FETCHING"] = "Загрузка данных репутации..."
L["REP_LOADING_PROCESSING"] = "Обработка %d фракций..."
L["REP_LOADING_PROCESSING_COUNT"] = "Обработка... (%d/%d)"
L["REP_LOADING_SAVING"] = "Сохранение в базу данных..."
L["REP_LOADING_COMPLETE"] = "Завершено!"

-- =============================================
-- Gold Transfer
-- =============================================
L["GOLD_TRANSFER"] = "Перевод золота"
L["GOLD_LABEL"] = "Золото"
L["SILVER_LABEL"] = "Серебро"
L["COPPER_LABEL"] = "Медь"
L["DEPOSIT"] = "Вложить"
L["WITHDRAW"] = "Снять"
L["DEPOSIT_TO_WARBAND"] = "Вложить в банк отряда"
L["WITHDRAW_FROM_WARBAND"] = "Снять из банка отряда"
L["YOUR_GOLD_FORMAT"] = "Ваше золото: %s"
L["WARBAND_BANK_FORMAT"] = "Банк отряда: %s"
L["NOT_ENOUGH_GOLD"] = "Недостаточно золота."
L["ENTER_AMOUNT"] = "Пожалуйста, введите сумму."
L["ONLY_WARBAND_GOLD"] = "Только банк отряда поддерживает перевод золота."

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "Невозможно открыть окно во время боя. Пожалуйста, попробуйте снова после окончания боя."
L["BANK_IS_ACTIVE"] = "Банк активен"
L["ITEMS_CACHED_FORMAT"] = "%d предметов в кэше"
L["UP_TO_DATE"] = "Актуально"
L["NEVER_SCANNED"] = "Никогда не сканировалось"

-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "ПЕРСОНАЖ"
L["TABLE_HEADER_LEVEL"] = "УРОВЕНЬ"
L["TABLE_HEADER_GOLD"] = "ЗОЛОТО"
L["TABLE_HEADER_LAST_SEEN"] = "ПОСЛЕДНИЙ РАЗ В СЕТИ"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "Нет предметов, соответствующих '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "Нет предметов, соответствующих вашему поиску"
L["ITEMS_SCAN_HINT"] = "Предметы сканируются автоматически. Попробуйте /reload, если ничего не появляется."
L["ITEMS_WARBAND_BANK_HINT"] = "Откройте банк отряда для сканирования предметов (автоматически сканируется при первом посещении)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Следующие шаги:"
L["CURRENCY_TRANSFER_STEP_1"] = "Найдите |cffffffff%s|r в окне валюты"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800ПКМ|r на нём"
L["CURRENCY_TRANSFER_STEP_3"] = "Выберите |cffffffff'Перевести в отряд'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Выберите |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Введите сумму: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "Окно валюты теперь открыто!"
L["CURRENCY_TRANSFER_SECURITY"] = "(Безопасность Blizzard предотвращает автоматический перевод)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "Зона: "
L["ADDED"] = "Добавлено"
L["WEEKLY_VAULT_TRACKER"] = "Отслеживание еженедельного хранилища"
L["DAILY_QUEST_TRACKER"] = "Отслеживание ежедневных заданий"
L["CUSTOM_PLAN_STATUS"] = "Свой план '%s' %s"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = "Подземелье"
L["VAULT_SLOT_RAIDS"] = "Рейды"
L["VAULT_SLOT_WORLD"] = "Мир"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "Модификатор"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_STANDING_LABEL"] = "Сейчас"
L["CHAT_GAINED_PREFIX"] = "+"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "План завершён: "
L["WEEKLY_VAULT_PLAN_NAME"] = "Еженедельное хранилище - %s"
L["VAULT_PLANS_RESET"] = "Планы еженедельного Великого хранилища были сброшены! (%d план%s)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "Персонажи не найдены"
L["EMPTY_CHARACTERS_DESC"] = "Войдите в игру своими персонажами, чтобы начать отслеживание.\nДанные собираются автоматически при каждом входе."
L["EMPTY_ITEMS_TITLE"] = "Нет кэшированных предметов"
L["EMPTY_ITEMS_DESC"] = "Откройте банк отряда или личный банк для сканирования предметов.\nПредметы кэшируются автоматически при первом посещении."
L["EMPTY_STORAGE_TITLE"] = "Нет данных хранилища"
L["EMPTY_STORAGE_DESC"] = "Предметы сканируются при открытии банков или сумок.\nПосетите банк, чтобы начать отслеживание хранилища."
L["EMPTY_PLANS_TITLE"] = "Пока нет планов"
L["EMPTY_PLANS_DESC"] = "Просмотрите средства передвижения, питомцев, игрушки или достижения выше,\nчтобы добавить цели коллекции и отслеживать прогресс."
L["EMPTY_REPUTATION_TITLE"] = "Нет данных о репутации"
L["EMPTY_REPUTATION_DESC"] = "Репутации сканируются автоматически при входе.\nВойдите персонажем, чтобы отслеживать фракции."
L["EMPTY_CURRENCY_TITLE"] = "Нет данных о валютах"
L["EMPTY_CURRENCY_DESC"] = "Валюты отслеживаются автоматически на всех персонажах.\nВойдите персонажем, чтобы отслеживать валюты."
L["EMPTY_PVE_TITLE"] = "Нет данных PvE"
L["EMPTY_PVE_DESC"] = "Прогресс PvE отслеживается при входе персонажами.\nВеликое хранилище, Мифический+ и блокировки рейдов появятся здесь."
L["EMPTY_STATISTICS_TITLE"] = "Статистика недоступна"
L["EMPTY_STATISTICS_DESC"] = "Статистика собирается с ваших отслеживаемых персонажей.\nВойдите персонажем, чтобы начать сбор данных."
L["NO_ADDITIONAL_INFO"] = "Дополнительная информация отсутствует"

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "Хотите отслеживать этого персонажа?"
L["CLEANUP_NO_INACTIVE"] = "Неактивные персонажи не найдены (90+ дней)"
L["CLEANUP_REMOVED_FORMAT"] = "Удалено %d неактивных персонажей"
L["TRACKING_ENABLED_MSG"] = "Отслеживание персонажа ВКЛЮЧЕНО!"
L["TRACKING_DISABLED_MSG"] = "Отслеживание персонажа ОТКЛЮЧЕНО!"
L["TRACKING_ENABLED"] = "Отслеживание ВКЛЮЧЕНО"
L["TRACKING_DISABLED"] = "Отслеживание ОТКЛЮЧЕНО (режим только чтение)"
L["STATUS_LABEL"] = "Статус:"
L["ERROR_LABEL"] = "Ошибка:"
L["ERROR_NAME_REALM_REQUIRED"] = "Требуется имя персонажа и игровой мир"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s уже имеет активный недельный план"

-- Profiles (AceDB)
L["PROFILES"] = "Профили"
L["PROFILES_DESC"] = "Управление профилями аддона"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "Критерии не найдены"
L["NO_REQUIREMENTS_INSTANT"] = "Нет требований (мгновенное выполнение)"

-- Statistics Tab (missing)
L["TOTAL_PETS"] = "Всего питомцев"

-- Items Tab (missing)
L["ITEM_LOADING_NAME"] = "Загрузка..."

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
