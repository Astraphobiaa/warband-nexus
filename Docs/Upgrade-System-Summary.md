# Upgrade Sistemi — Kod Akış Özeti

Bu belge, kodun gerçekte nasıl çalıştığını adım adım tanımlar (GearService + GearUI). Varsayıma dayanmaz; dosyalardaki akış doğrulanarak yazılmıştır.

---

## 1. Veri Kaynağı

- **Ekipman verisi**: `db.global.gearData[charKey]`. `GetDB()` = `WarbandNexus.db.global.gearData`; `GetEquippedGear(charKey)` bu tablodan `db[charKey]` döner (version, lastScan, slots).
- **Upgrade bilgisi**: API kullanılmaz. Tüm upgrade durumu **sadece bu gear verisi + ilvl** ile hesaplanır; `GetPersistedUpgradeInfo(charKey)` tek kaynaktır.

---

## 2. Tarama (Scan) — GearService

- **ScanEquippedGear**: Sadece takip edilen karakter için çalışır (`CharacterService:IsCharacterTracked`).
- Her slot için: `GetInventoryItemLink("player", slotID)` ile link alınır; `GetEffectiveIlvl(itemLink)` ile ilvl hesaplanır.
- **Track/level**: `C_ItemUpgrade` çağrılmaz. Sadece **InferUpgradeFromIlvl(ilvl)** kullanılır:
  - Sabit tablo **ILVL_TO_UPGRADE** (220–289): ilvl → (trackName, currUpgrade 1–6, maxUpgrade 6).
  - Tabloda yoksa en yakın ilvl’e göre clamp edilir; 220’den küçük veya 289’dan büyükse `nil` (upgrade yok).
- Slot kaydı: `currUpgrade`, `maxUpgrade`, `upgradeTrack` ilvl’den yazılır; ilvl 220–289 dışındaysa `notUpgradeable = true` yazılır.
- Sonuç `db.global.gearData[charKey]` olarak kaydedilir (charKey = `Utilities:GetCharacterKey()`).

---

## 3. Upgrade Bilgisinin Üretilmesi — GetPersistedUpgradeInfo

- Girdi: `GetEquippedGear(charKey)` → `gearData.slots`.
- Her slot için:
  - `itemLevel` slot’tan; track/level için önce `slot.upgradeTrack`, `slot.currUpgrade`, `slot.maxUpgrade` kullanılır; yoksa veya maxUpgrade 0 ise **InferUpgradeFromIlvl(itemLevel)** ile doldurulur.
  - `slot.notUpgradeable` ise: `canUpgrade = false`, `costs = {}`, slot upgrade listesine “upgrade yok” olarak eklenir.
  - Track/level varsa: `hasNext = (currUpgrade < maxUpgrade)`. **Maliyet her zaman sabit**: `hasNext` ise `TRACK_NAME_TO_CURRENCY_ID` ile track’e göre currency ID + **ns.UPGRADE_CREST_PER_LEVEL** (20) + **ns.UPGRADE_GOLD_PER_LEVEL_COPPER** (10g = 100000 copper).
- Dönen yapı: `[slotID] = { canUpgrade, currentIlvl, nextIlvl, maxIlvl, trackName, currUpgrade, maxUpgrade, costs, moneyCost, statEffects }`. (nextIlvl/maxIlvl burada ilvl artışı hesaplanmadığı için mevcut ilvl ile doldurulur; sadece tier bilgisi kullanılır.)

---

## 4. Para / Crest Miktarları — GearUI + GearService

- **BuildCurrencyAmountMap(charKey)** (GearUI):
  - Karakter **şu anki karakter** ise: **GetGearUpgradeCurrencies(charKey)** → canlı API (C_CurrencyInfo.GetCurrencyInfo + GetMoney).
  - Diğer karakterler: **GetGearUpgradeCurrenciesFromDB(charKey)** → Currency tab’ın kaynağı (GetCurrenciesForUI) + db.global.characters’tan gold; mevcut karakter ise gold için yine GetMoney() kullanılır.
- Sonuç: `currencyID → amount` map’i. Gold = `currencyAmounts[0]` (gold cinsinden; copper’a çevirirken ×10000 kullanılıyor).

---

## 5. “Ödeyebilir” ve Ok Görünürlüğü — GearUI

- **CanAffordUpgrade(costs, currencyAmounts, moneyCost)**:
  - `currencyAmounts` yoksa false.
  - Gold: `(currencyAmounts[0] or 0) * 10000 >= moneyCost` (copper) gerekli; değilse false.
  - `costs` nil veya boşsa **false**.
  - Her cost için: `currencyAmounts[cid] >= amount`; birinde yetersizse false.
- **IsUpgradable(slotID)** (Paperdoll ve Equipment listesi):
  - `up = upgradeInfo[slotID]`
  - **true** sadece: `up and up.canUpgrade and CanAffordUpgrade(up.costs, currencyAmounts, up.moneyCost)`.
- Yeşil ok: **sadece** `isUpgradable == true` iken gösterilir; yani hem upgrade açık hem maliyet (20 crest + 10g) karşılanıyor olmalı.

---

## 6. Gear Sekmesi Çizim Akışı

- `charKey` = dropdown’dan seçilen karakter; `canonicalKey = GetCanonicalCharacterKey(charKey)`.
- Veri:
  - `gearData = GetEquippedGear(canonicalKey)`
  - `upgradeInfo = GetPersistedUpgradeInfo(canonicalKey)`
  - `currencyAmounts = BuildCurrencyAmountMap(canonicalKey)`
- **DrawPaperDollCard**: Paperdoll slot’ları için `IsUpgradable(slotID)` ve `GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts)` ile slot butonları oluşturulur; yeşil ok `isUpgradable` true ise çizilir.
- **DrawEquipmentCard**: Her satır için `canUpgradeThis = upInfo.canUpgrade`, `canAfford = CanAffordUpgrade(upInfo.costs, currencyAmounts, upInfo.moneyCost)`; satır rengi buna göre (yeşil / turuncu / max mavi).

---

## 7. Slot Metni ve Tooltip

- **GetSlotTrackText**: Track + "X/Y" + (eğer `up.canUpgrade` ve `currencyAmounts` verilmişse) **UpgradesAffordableCount** ile " (N more)" eklenir.
- **UpgradesAffordableCount**: crest’e göre kaç seviye, gold’a göre kaç seviye, slot’ta kalan seviye; minimumu döner; costs boş veya canUpgrade false ise 0.
- Tooltip: Upgrade açıksa "Upgrade: Track cur/max -> next/max", cost satırı (crest + gold), ve “X more upgrade(s) possible (to Y/6)” (UpgradesAffordableCount > 0 ise).

---

## 8. Debug Komutu — /wn gearupgradedebug

- **GearUpgradeDebugReport**: Mevcut karakter için:
  - Upgrade bilgisi: **GetPersistedUpgradeInfo(currentKey)** (DB/ilvl, API yok).
  - Para/crest: **GetGearUpgradeCurrencies(currentKey)** (canlı API).
  - Her slot için: tier, track, cost (need/have), gold need/have, **afford** ve **showArrow** yazdırılır.
  - **showArrow = up.canUpgrade and canAfford**; **canAfford** artık costs boşsa false (UI ile uyumlu).

---

## 9. Sabitler

- **GearService**: `ns.UPGRADE_CREST_PER_LEVEL = 20`, `ns.UPGRADE_GOLD_PER_LEVEL_COPPER = 10 * 10000`; `TRACK_NAME_TO_CURRENCY_ID`: Adventurer=3391, Veteran=3342, Champion=3343, Hero=3345, Myth=3347.
- **GearUI**: `CREST_PER_LEVEL`, `GOLD_PER_LEVEL` ns’ten veya 20/10 fallback; maliyet mantığı GearService ile aynı.

---

## 10. Özet Akış (Tek Cümleler)

1. Tarama: Sadece ilvl → ILVL_TO_UPGRADE ile track/level; DB’e yazılır.
2. Sekme açılınca: GetEquippedGear + GetPersistedUpgradeInfo(canonicalKey) → ilvl/slot’tan track/level, maliyet hep 20 crest + 10g.
3. Para: Mevcut karakter için API, diğerleri için DB.
4. Ok: Sadece `canUpgrade` ve `CanAffordUpgrade` (costs dolu + yeterli crest + yeterli gold) ise gösterilir.
5. Hiçbir adımda C_ItemUpgrade kullanılmaz; sistem tamamen offline/DB + ilvl ile çalışır.

---

*Son güncelleme: Kod incelemesi ile doğrulanmıştır (GearService.lua, GearUI.lua).*
