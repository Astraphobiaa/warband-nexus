# WoW Profession API Limitation (Retail)

## Özet

Retail WoW’da **recipe, concentration, knowledge, cooldown ve crafting order** verileri **sadece profesyon penceresi açıkken** (C_TradeSkillUI bağlamında) alınabiliyor. Bu verileri arka planda veya penceresi kapalıyken çeken bir API yok.

## API Davranışı

| Veri | Pencere kapalıyken? | Pencere açıkken |
|------|----------------------|------------------|
| Skill level (expansion bazlı) | Sadece daha önce açılmış profession için (GetProfessionInfoBySkillLineID) | Evet |
| Recipes (known/total, first craft, skill up) | Hayır | Evet (GetAllRecipeIDs, GetRecipeInfo) |
| Concentration | Hayır | Evet (GetConcentrationCurrencyID) |
| Knowledge (C_ProfSpecs / C_Traits) | Hayır | Evet |
| Cooldowns, Orders | Hayır | Evet |

- `C_TradeSkillUI.OpenTradeSkill(skillLineID)` pencereyi açar ve “hardware event” gerektirir; sessizce arka planda açıp kapatmak tasarım gereği mümkün değil.
- Bu yüzden **veri toplama tek yolu**: Kullanıcı profesyon penceresini (K) açtığında `TRADE_SKILL_SHOW` ile tetiklenen toplama ve DB’ye yazma.

## Addon’daki Tasarım

1. **TRADE_SKILL_SHOW** (profesyon penceresi açıldığında):  
   Concentration, knowledge, recipes, cooldowns, orders toplanıp `db.global.characters[charKey]` içine yazılıyor (0.6s + 1.2s retry ile API hazır olana kadar deneme).
2. **UI**: Aynı `db.global.characters` verisini okuyor; expansion filtresi sadece recipe / first craft / skill up gösterimini filtreler. Concentration ve knowledge, DB’de varsa her zaman gösterilir.
3. **Skill level**: Kullanıcı o profession’ı en az bir kez açtıysa, `discoveredSkillLines` ile saklanan skill line’lar için `GetProfessionInfoBySkillLineID` login’de penceresi açmadan skill güncelleyebiliyor.

Sonuç: İstediğin “tüm profession verilerini otomatik arka planda al” sistemi **WoW retail API’siyle mümkün değil**; veri ancak kullanıcı (K) ile profesyon penceresini açtığında güncelleniyor. Addon bu kısıta göre “açıldığında topla, sakla, UI’da göster” mantığıyla çalışıyor.
