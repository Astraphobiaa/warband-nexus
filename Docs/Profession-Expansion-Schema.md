# Profession Expansion Schema (Midnight 12.0.1)

Bu dokuman profession verisinin tek kaynak akisini tanimlar:

- API -> DB
- UI sadece DB okur
- Tum guncelleme event-driven calisir

## Hedef

Expansion verilerini karistirmadan saklamak:

- Midnight verisi Midnight bucket'inda
- Khaz Algar verisi Khaz Algar bucket'inda
- Her bucket Blizzard'in `skillLineID` degeriyle izole edilir

## DB Semasi

Karakter bazinda (`db.global.characters[charKey]`) yeni normalize alan:

```lua
professionData = {
    schemaVersion = 1,
    lastUpdate = time(),
    bySkillLine = {
        [skillLineID] = {
            skillLineID = number,
            professionName = string, -- parent profession (Tailoring vb)
            expansionName = string,  -- expansion child name (Midnight Tailoring vb)
            lastUpdate = number,

            skill = { current, max, lastUpdate },
            concentration = { current, max, currencyID, lastUpdate },
            knowledge = {
                hasUnspentPoints,
                unspentPoints,
                spentPoints,
                maxPoints,
                currencyName,
                currencyIcon,
                specTabs,
                lastUpdate,
            },
            cooldowns = { [recipeID] = cooldownEntry },
            orders = { personalCount, guildCount, publicCount, lastUpdate },
        }
    },
    byProfession = {
        [professionName] = {
            [skillLineID] = true,
        }
    }
}
```

Not: Legacy alanlar (`concentration`, `knowledgeData`, `professionExpansions`, `professionCooldowns`, `craftingOrders`) geriye uyumluluk icin korunur.

## Event -> Collector Akisi

- `TRADE_SKILL_SHOW`
  - concentration
  - knowledge
  - expansion skill data
  - cooldowns
  - crafting orders
  - profession equipment
- `TRADE_SKILL_LIST_UPDATE` (debounced)
  - concentration
  - knowledge
  - expansion skill data
  - cooldowns
  - crafting orders
- `TRAIT_NODE_CHANGED` / `TRAIT_CONFIG_UPDATED`
  - knowledge refresh
- `WN_CURRENCY_UPDATED` (currencyID ile)
  - concentration realtime refresh

## API Kaynaklari

- Skill + expansion ayrimi:
  - `C_TradeSkillUI.GetChildProfessionInfos()`
  - `C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)`
- Concentration:
  - `C_TradeSkillUI.GetConcentrationCurrencyID(skillLineID)`
  - `C_CurrencyInfo.GetCurrencyInfo(currencyID)`
- Knowledge:
  - `C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)`
  - `C_ProfSpecs.GetSpecTabIDsForSkillLine(skillLineID)`
  - `C_Traits.GetTreeCurrencyInfo(configID, treeID, false)`
- Cooldowns:
  - `C_TradeSkillUI.GetAllRecipeIDs()`
  - `C_TradeSkillUI.GetRecipeCooldown(recipeID)`
  - `C_TradeSkillUI.GetRecipeInfo(recipeID)`
- Crafting orders:
  - `C_CraftingOrders.GetNumPersonalOrders()`
  - `C_CraftingOrders.GetNumGuildOrders()`

## Taint/Secret Guvenligi

- API string degerleri `SafeAPIString` ile `issecretvalue` kontrolunden sonra yazilir.
- Secret degerler DB'ye yazilmaz; fallback kullanilir.

## Dogrulama

1. Profesyon penceresini ac (`K`) ve expansion tab degistir.
2. Her tab gecisinden sonra collector calisir.
3. `professionData.bySkillLine` icinde her expansion farkli `skillLineID` altinda yazilir.
4. `DataService` kayitlarinda `professionData`, `professionCooldowns`, `craftingOrders` korunur (overwrite olmaz).
