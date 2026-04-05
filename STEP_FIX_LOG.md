# Warband Nexus — adım adım düzeltme günlüğü

Küçük, güvenli değişiklikler ve Midnight/taint kurallarıyla hizalama. Her adım bağımsız commitlenebilir.

---

## Adım 1 — `ENCOUNTER_END` / tooltip feed: secret-safe isim ve anahtarlar

**Tarih:** 2026-04-04  

**Amaç:** `encounterName` ve `encounterID` için `issecretvalue` sonrası string/tablo işlemleri; sentetik kill anahtarında gizli isim birleştirmesini kaldırma.

**Dosyalar:**

- `Modules/TooltipService.lua` — `_feedEncounterKill`: girişte `not encounterName or (issecretvalue and issecretvalue(encounterName))`; `sourceDB.encounters[encounterID]` yalnızca ID secret değilse.
- `Modules/TryCounterService.lua` — `OnTryCounterEncounterEnd`: `safeEncounterDisplayName` (tip + boşluk + secret kontrolü); tooltip feed yalnızca güvenli isim varken; `recentKills` ve `useNameFallback` sentetik GUID: isim yoksa `Encounter-Fallback-<npcID>-<now>`.

**Davranış değişikliği:** Boss adı API tarafından secret dönerse tooltip isim önbelleği bu kill için doldurulmaz; try-counter sentetik giriş yine oluşur (`Encounter-Fallback-...`).

**Sonraki adım adayları (güncel):** Adım 2–5 tamamlandı; isteğe bağlı maddeler günlük sonunda.

---

## Adım 2 — `CheckTargetDrops` debug çıktısı: secret-safe `safeStr` ve isim

**Tarih:** 2026-04-04  

**Amaç:** `/wn` drop-check yardımcısında `tostring`/birleştirme öncesi secret kontrolü; `UnitName` dönüşünde `or "Unknown"` kaldırılarak Midnight’da yasak boolean/`or` kısa devresi riskinin azaltılması.

**Dosya:** `Modules/TryCounterService.lua` — `WarbandNexus:CheckTargetDrops`

**Değişiklikler:**

- `safeStr`: `nil` → `"nil"`, secret → `"(secret)"`, aksi `tostring` (`TryCounterDebugReport` ile aynı mantık).
- `unitName`: yalnızca `type == "string"`, boş değil ve secret değilse kullanılır; aksi halde `"Unknown"`.

**Sonraki adım adayları (güncel):** isteğe bağlı — `encounterDB` debug (düşük öncelik).

---

## Adım 3 — Periyodik ticker’larda erken çıkış (CPU / gereksiz API)

**Tarih:** 2026-04-04  

**Amaç:** 60 sn’de bir çalışan döngülerde iş yokken `GetSecondsUntilWeeklyReset` ve `pairs` tam taramalarını atlamak.

**Dosyalar:**

- `Modules/DailyQuestManager.lua` — haftalık reset ticker: `plans` modülü kapalıysa veya `db.global.plans` içinde hiç `type == "daily_quests"` yoksa çıkış (haftalık API ve plan güncellemesi yok).
- `Modules/TryCounterService.lua` — try-counter cleanup ticker: `processedGUIDs`, `recentKills`, `mergedLootTryCountedAt` üçünün de boş olduğu tick’lerde tamamen çıkış.

**Not:** Try-counter modülü kapalı olsa bile tablolarda eski kayıt varsa cleanup çalışmaya devam eder (bellek sızıntısını önler).

**Sonraki adım adayları (güncel):** bkz. Adım 4.

---

## Adım 4 — `daily_quests` varlığı: mesajla senkron önbellek

**Tarih:** 2026-04-04  

**Amaç:** 60 sn ticker’da her seferinde `plans` üzerinde tam tarama yerine O(1) bayrak; plan ekleme/silme sonrası `WN_PLANS_UPDATED` ile güncelleme.

**Dosya:** `Modules/DailyQuestManager.lua`

**Değişiklikler:**

- `DailyQuestManagerEvents` + `SyncHasDailyQuestPlanCache()`: `db.global.plans` içinde en az bir `daily_quests` var mı → `WarbandNexus._hasDailyQuestPlanCache`.
- `InitializeDailyQuestManager`: ilk `Sync` + `RegisterMessage("WN_PLANS_UPDATED", Sync)`.
- Haftalık ticker: `daily_quests` kontrolü yalnızca `_hasDailyQuestPlanCache` (iç döngü kaldırıldı).
- `OnDailyQuestLogin`: girişte bir kez `Sync` (SV/kenar sırası sonrası tutarlılık).

**Sonraki adım adayları (güncel):** bkz. Adım 5.

---

## Adım 5 — `daily_quests` karakter indeksi + mesaj debounce

**Tarih:** 2026-04-04  

**Amaç:** Mevcut karakter için `daily_quests` planlarına O(1) erişim (liste başına); `QUEST_TURNED_IN` / `QUEST_LOG_UPDATE` / haftalık reset yollarında tüm `plans` dizisini taramayı bırakmak.

**Dosya:** `Modules/DailyQuestManager.lua`

**Değişiklikler:**

- `SyncDailyQuestPlanIndexes()`: tek geçişte hem `_hasDailyQuestPlanCache` hem `_dailyQuestPlansByCharKey` ( `[charKey] = { plan, ... }` , plan referansları `db.global.plans` ile aynı nesneler).
- `GetDailyQuestPlansForCharKey(charKey)`: yardımcı.
- Haftalık ticker, `OnDailyQuestLogin`, `OnDailyQuestCompleted`, `OnDailyQuestUpdate` içi döngüler bu listeyi kullanır.
- `WN_PLANS_UPDATED` dinleyicisi artık doğrudan tam tarama yapmaz: `UpdateDailyPlanProgress` ardışık mesajları birleştirmek için `C_Timer.After(0, …)` ile **tek karelik debounce** (`RequestDailyQuestIndexRebuild`).
- `OnDailyQuestCompleted` / `OnDailyQuestUpdate`: `self.db` nil kontrolleri.

**Sonraki adım adayları (güncel):** bkz. Adım 6–8.

**Özet:** Zorunlu performans/taint hattı Adım 1–5; isteğe bağlı tamamlamalar Adım 6–8.

---

## Adım 6 — `HasActiveDailyPlan` / `GetDailyPlan`: indeks + geri dönüş

**Tarih:** 2026-04-04  

**Dosya:** `Modules/DailyQuestManager.lua`  

**Değişiklikler:**

- `FindDailyPlanForCharacter(name, realm)`: önce `_dailyQuestPlansByCharKey[GetCharacterKey(...)]`, bulunamazsa tam `plans` taraması (indeks debounce gecikmesi / ilk kare).
- `HasActiveDailyPlan` ve `GetDailyPlan` bu yardımcıyı kullanır.

---

## Adım 7 — `weekly_vault` planları: `RefreshPlanCache` indeksi + `OnPvEUpdateCheckPlans`

**Tarih:** 2026-04-04  

**Dosya:** `Modules/PlansManager.lua`  

**Değişiklikler:**

- `RefreshPlanCache`: `_weeklyVaultPlansByCharKey[charKey] = { plan, ... }` (mevcut `plans` döngüsünde, ek geçiş yok).
- `OnPvEUpdateCheckPlans`: önce bu liste; yoksa eski `ipairs(plans)` geri dönüşü. `self.db` nil kontrolü.

---

## Adım 8 — `encounterDB` debug (değerlendirme)

**Sonuç:** `encounterDB` anahtarları eklenti statik verisi (API secret değil). Ek kod gerekmedi; Midnight guard şu an loot/event yollarında yeterli.

**Kalan (çok düşük öncelik):** `PlansManager` içindeki diğer `ipairs(self.db.global.plans)` kullanımları (farklı plan türleri); ihtiyaç halinde tür bazlı ikincil indeksler.

---

## Adım 9 — `PlansManager`: vault listesi + `GetPlanByID` O(1)

**Tarih:** 2026-04-04  

**Dosya:** `Modules/PlansManager.lua`  

**Değişiklikler:**

- `RefreshPlanCache`: `_weeklyVaultPlansList` (tüm `weekly_vault` planları, `GetCharacterKey` olmadan da); `_plansById[plan.id]` (`plans` + `customPlans`, çakışmada custom son yazar — önceki `GetPlanByID` sırasıyla uyumlu).
- `ResetWeeklyPlans`: `resetOneVaultPlan` yardımcısı; önce `_weeklyVaultPlansList`, yoksa tam tarama.
- `CheckWeeklyReset`: önce `_weeklyVaultPlansList` ile eşik kontrolü; yoksa eski döngü.
- `HasActiveWeeklyPlan`: `_weeklyVaultPlansByCharKey` + geri dönüş taraması; `self.db` koruması.
- `GetPlanByID`: `_plansById` + geri dönüş; `planID` / `self.db` koruması.

**Hâlâ tam tarama:** `CheckPlansForCompletion` / `OnPlanCollectionUpdated` eşleme (satır ~315, ~368) — koleksiyon olayı başına; ayrı indeks istenirse sonraki tur.

---

## Adım 10 — `TryCompletePlanFromCollectibleObtained`: `_plansByCollectibleKey`

**Tarih:** 2026-04-04  

**Dosya:** `Modules/PlansManager.lua`  

**Değişiklikler:**

- `RefreshPlanCache`: `mount` / `pet` / `toy` / `achievement` / `illusion` / `title` altında `[entityId] = { plan… }` (`illusion` için hem `illusionID` hem `sourceID`).
- `TryCompletePlanFromCollectibleObtained`: önce kova + `tryBucket`; illusion’da `idIll` ve `data.sourceID`; sonra eski tam tarama (bilinmeyen `dType`, soğuk önbellek, isim eşlemesi, illusion `sourceID` uçları).

**Not:** `CheckPlansForCompletion` hâlâ tüm planlarda `CheckPlanProgress` — maliyet API; ileride yalnız “aktif” plan listesi + tampon temizliği ayrı iş.

---

## Adım 11 — `CheckPlansForCompletion`: `_incompleteTodoPlansList` + senkron

**Tarih:** 2026-04-04  

**Dosya:** `Modules/PlansManager.lua`  

**Amaç:** Tamamlanmamış ve henüz bildirilmemiş planlar için tek geçişte liste; `CheckPlanProgress` yalnız bu alt kümede (liste boş/ yoksa eski `ipairs(plans)` geri dönüşü). Koleksiyon olayında `TryCompletePlanFromCollectibleObtained` sonrası ve tamamlama sonrası liste tazelenir.

**Değişiklikler:**

- `RefreshPlanCache`: `_incompleteTodoPlansList` doldurma (`not completed` ve `not completionNotified`, yalnız `db.global.plans`).
- `RebuildIncompleteTodoPlansList()`: orta oyunda tamamlama sonrası tam liste yeniden kurulumu.
- `CheckPlansForCompletion`: önce liste; en az bir tamamlama olduysa `RebuildIncompleteTodoPlansList`.
- `TryCompletePlanFromCollectibleObtained`: `applyCollectibleCompletion` → `RebuildIncompleteTodoPlansList`.
- `ResetWeeklyPlans`: sıfırlama sonrası `RefreshPlanCache()` (vault `completed`/`completionNotified` geri alınınca eski `_incompleteTodoPlansList` tutarlı kalsın).

**Sonraki adım:** bkz. Adım 12.

---

## Adım 12 — Plans UI: allocation azaltma + `ipairs` → sayısal döngü

**Tarih:** 2026-04-04  

**Amaç:** Plans sekmesi / tracker’da gereksiz birleşik plan tablosu tahsisini kaldırmak; başlık sayacı ve tracker toplamı için hafif okuyucular; kurallara uygun `for i = 1, #t` kullanımı.

**Dosyalar:**

- `Modules/PlansManager.lua` — `GetActivePlanTotalCount()`, `GetActiveNonDailyIncompleteCount()` (mevcut başlık sayımı ile aynı semantik: `daily_quests` hariç, `IsActivePlanComplete` ile “aktif”).
- `Modules/UI/PlansUI.lua` — `DrawPlansTab` başlık sayısı yeni yardımcıyla; `DrawActivePlans`: `daily_tasks` için doğrudan iki DB listesinden toplama (tam `GetActivePlans` + filtre yok); gereksiz `category == "active"` kopya döngüsü kaldırıldı; arama filtresi `ipairs` → sayısal döngü.
- `Modules/UI/PlansTrackerWindow.lua` — sayaç satırında `#GetActivePlans()` yerine `GetActivePlanTotalCount()`.
- `Modules/UI/SearchResultsRenderer.lua` — `PrepareContainer` çocuk temizliği `ipairs` → sayısal döngü (ortak yardımcı).

**Kalan (isteğe bağlı):** bkz. Adım 13; `StorageUI` zaten `currentTab == "storage"` + debounce kullanıyor.

---

## Adım 13 — Currency / Reputation: mesajda tam çizim yalnız aktif sekmede

**Tarih:** 2026-04-04  

**Amaç:** Paylaşılan scroll child `parent:IsVisible()` ile “görünür” kalabildiği için yanlış sekmedeyken bile tam `DrawCurrencyTab` / `DrawReputationTab` tetiklenmesini önlemek; pencere kapalıyken CPU/israfı kesmek.

**Dosyalar:**

- `Modules/UI/CurrencyUI.lua` — `IsCurrencyTabActive()` (`mainFrame:IsShown()` ve `currentTab == "currency"`). `WN_CURRENCY_LOADING_STARTED`, `WN_CURRENCY_CACHE_READY`, `WN_CURRENCY_CACHE_CLEARED`, `WN_CURRENCY_UPDATED` yalnız bu durumda tam çizim.
- `Modules/UI/ReputationUI.lua` — `IsReputationTabActive()` (`currentTab == "reputations"`). `WN_REPUTATION_LOADING_STARTED`, `WN_REPUTATION_CACHE_CLEARED` (yük paneli + çocuk gizleme), `WN_REPUTATION_CACHE_READY` (çizim kısmı), `REPUTATION_UPDATED` aynı kontrol; `WN_REPUTATION_CACHE_READY` içinde `HideLoading` sekme dışındayken de çalışmaya devam eder.

**Not:** Sekmeye geçişte `PopulateContent` zaten ilgili `Draw*Tab` çağırır; veri güncel kalır.

---

## Adım 14 — Characters / Professions: `RefreshUI` yalnız pencere açıkken

**Tarih:** 2026-04-04  

**Amaç:** Ana çerçeve gizliyken `currentTab` hâlâ son sekmede kalabildiği için `WN_CHARACTER_TRACKING_CHANGED` ve Professions `Refresh()` gereksiz `RefreshUI` tetiklemesin.

**Dosyalar:**

- `Modules/UI/CharactersUI.lua` — `mf:IsShown()` eklendi (`currentTab == "chars"` ile birlikte).
- `Modules/UI/ProfessionsUI.lua` — `CHARACTER_UPDATED` / `WN_CHARACTER_TRACKING_CHANGED` için `Refresh()` içinde `mf:IsShown()` (`currentTab == "professions"`).

**Not:** `UI.lua` içindeki `SchedulePopulateContent` dinleyicileri zaten `f:IsShown()` kullanıyor; bu iki modül ek yol olarak `RefreshUI` çağırıyordu.

---

## Adım 15 — Plans: `IsStillOnTab` + banka günlüğü popup

**Tarih:** 2026-04-04  

**Amaç:** Ana pencere gizliyken `currentTab` eski kalabildiğinden `IsStillOnTab` yalnızca sekme değil `mainFrame:IsShown()` de istesin (Plans koleksiyon mesajları / `OnPlansUpdated`). Para günlüğü popup’ında mesaj yalnız çerçeve açıkken yenilesin.

**Dosyalar:**

- `Core.lua` — `WarbandNexus:IsStillOnTab`: `mf:IsShown() and mf.currentTab == expectedTab` (kullanım yalnız `PlansUI.lua`).
- `Modules/UI/CharacterBankMoneyLogPopup.lua` — `WN_CHARACTER_BANK_MONEY_LOG_UPDATED` içinde `dialog:IsShown()` koruması.

**Not:** `ProfessionInfoWindow` / `RecipeCompanionWindow` zaten kendi `frame:IsShown()` korumalarını kullanıyor; servis katmanı (`EventManager`, `GearService`, `DailyQuestManager` …) UI çizmediği için bu tura dahil edilmedi.

---

## Tur özeti (tamamlandı)

Bu günlükteki performans / taint hizası çalışması kapsamı kapatıldı:


| Alan                                                              | Adımlar |
| ----------------------------------------------------------------- | ------- |
| Secret / encounter / tooltip / try-counter                        | 1–2     |
| Ticker erken çıkış, günlük plan indeksleri                        | 3–6     |
| Vault / plan önbellek, `TryComplete`, tamamlanma listesi          | 7–11    |
| Plans UI allocation, Currency/Reputation/Chars/Prof tab mesajları | 12–14   |
| Plans `IsStillOnTab`, banka günlüğü popup                         | 15      |


**Bilerek dokunulmayanlar:** Tam `StorageUI` / `CollectionsUI` içi tüm `ipairs` → sayısal döngü geçişi (devasa diff, düşük getiri); `encounterDB` statik veri (Adım 8). İleride tek dosya seçilerek devam edilebilir.