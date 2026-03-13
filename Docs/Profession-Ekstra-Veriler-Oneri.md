# Profession: Kullanıcıya Ekstra Sunulabilecek Veriler (API → DB → UI)

Tüm veriler: **API (pencere açıkken)** → **DB** → **UI** akışıyla; event-driven güncelleme.

---

## 1. Recipe özeti (bilinen / toplam, first craft, skill-up)

| Veri | API | DB (per skillLineID) | UI |
|------|-----|----------------------|-----|
| Bilinen tarif sayısı | `C_TradeSkillUI.GetAllRecipeIDs()` + `GetRecipeInfo(recipeID).learned` | `recipes.knownCount`, `recipes.totalCount` | Sütun veya tooltip: "45 / 120" |
| First craft bonusu kalan | `GetRecipeInfo().firstCraftBonus` | `recipes.firstCraftCount` | "1st: 12" veya badge |
| Skill-up verebilecek tarif sayısı | `GetRecipeInfo().canSkillUp` (veya eşdeğeri) | `recipes.skillUpCount` | "↑: 5" veya tooltip |

**Kullanıcı faydası:** Hangi karakterde kaç tarif var, first craft nerede kaldı, skill atacak tarif kaldı mı tek bakışta görür.

---

## 2. Cooldown özeti

| Veri | API | DB | UI |
|------|-----|-----|-----|
| Aktif cooldown sayısı | Zaten toplanıyor (`GetRecipeCooldown`) | `professionCooldowns[skillLineID]` / `professionData.bySkillLine[].cooldowns` | Sütun: "3 CD" veya "2 hazır" |
| Hazır olan cooldown sayısı | Aynı veri, `cooldownEnd <= time()` | Hesaplanabilir | Badge veya sayı |

**Kullanıcı faydası:** “Bu karakterde kaç cooldown var, kaçı kullanıma hazır?” tek satırda.

---

## 3. Crafting orders özeti

| Veri | API | DB | UI |
|------|-----|-----|-----|
| Kişisel / guild order sayısı | Zaten toplanıyor (`GetNumPersonalOrders`, `GetNumGuildOrders`) | `craftingOrders[skillLineID]` / `professionData.bySkillLine[].orders` | Sütun: "2 pers. / 5 guild" veya ikon+sayı |

**Kullanıcı faydası:** Order’ları hangi karakterde kullanacağını hızlı seçer.

---

## 4. Recraft / kalite özeti (isteğe bağlı)

| Veri | API | DB | UI |
|------|-----|-----|-----|
| Recraft edilebilir tarif sayısı | `GetRecipeInfo()` içinde recraft/quality alanları (varsa) | `recipes.recraftCount` veya quality dağılımı | Tooltip veya küçük sütun |

**Kullanıcı faydası:** “Bu expansion’da kaç recraft tarifim var?” (API’de alan netse eklenir.)

---

## 5. Bildirimler (DB’de zaten var, UI/ayar katmanı)

| Olay | Veri kaynağı | UI |
|------|----------------|-----|
| Concentration full | `concentration.current >= max` | Toast / chat: "Tailoring concentration full" |
| Cooldown hazır | `cooldownEnd <= time()` | "X tarif cooldown’u hazır" |
| Yeni tarif öğrenildi | `NEW_RECIPE_LEARNED` event | İsteğe bağlı toast |

**Kullanıcı faydası:** Oyunu açmadan veya sekme açmadan hatırlatma; mevcut notification altyapısına bağlanır.

---

## 6. Spec (knowledge) tab özeti

| Veri | API | DB | UI |
|------|-----|-----|-----|
| Her spec tab adı + harcanan puan | Zaten toplanıyor (`specTabs`, knowledge) | `knowledgeData[].specTabs` | Tooltip’te: "Mastery: 12, Gathering: 8" |

**Kullanıcı faydası:** Knowledge dağılımı tooltip’te daha okunaklı (veri zaten var, sadece sunum).

---

## Öncelik önerisi (uygulama sırası)

1. **Recipe özeti** – Bilinen/toplam + first craft + skill-up (API net; kullanıcı değeri yüksek).
2. **Orders sütunu** – Veri toplanıyor, UI’da sadece gösterilmeli.
3. **Cooldown özeti** – Veri toplanıyor; sütun veya tooltip: “X CD (Y hazır)”.
4. **Bildirimler** – Concentration full / cooldown ready (ayarlanabilir).
5. **Recraft/quality** – API doğrulandıktan sonra (varsa).

---

## Teknik not

- Recipe sayıları ve first craft/skill-up için **yeni collector** gerekir: `TRADE_SKILL_SHOW` / `TRADE_SKILL_LIST_UPDATE` içinde `GetAllRecipeIDs` + döngüyle `GetRecipeInfo`; sonuçlar `charData.recipes[skillLineID]` veya `professionData.bySkillLine[skillLineID].recipes` altında saklanır.
- Orders ve cooldown **zaten DB’de**; UI’da ek sütun veya tooltip satırı eklenmesi yeterli.
