# Item Upgrade API (Midnight 12.0 / TWW)

Referans: [warcraft.wiki.gg – C_ItemUpgrade.GetItemUpgradeItemInfo](https://warcraft.wiki.gg/wiki/API_C_ItemUpgrade.GetItemUpgradeItemInfo), [Item upgrading](https://warcraft.wiki.gg/wiki/Item_upgrading).

## Kullanım

- **Equipped item:** `ItemLocation:CreateFromEquipmentSlot(slotID)` (slotID 1–17).
- **Çağrı:** `C_ItemUpgrade.GetItemUpgradeItemInfo(location)` — wiki bazen parametresiz gösterse de 10.1+ sürümlerde `ItemLocation` alır.
- **Önce kontrol:** `location:IsValid()` ve (isteğe bağlı) `C_Item.DoesItemExist(location)`.

## Dönüş: ItemUpgradeItemInfo

| Alan | Tip | Açıklama |
|------|-----|----------|
| `iconID` | number | İkon file ID |
| `name` | string | **Upgrade track adı** (Explorer, Adventurer, Veteran, Champion, Hero, Myth) |
| `itemUpgradeable` | boolean | Eşya upgrade edilebilir mi |
| `displayQuality` | number | Kalite (rarity) |
| `highWatermarkSlot` | number | 10.1.0 |
| `currUpgrade` | number | **Mevcut upgrade seviyesi** (0..maxUpgrade) |
| `maxUpgrade` | number | **Maksimum upgrade seviyesi** (ör. 6 veya 8) |
| `minItemLevel` | number | 10.1.0 – track minimum ilvl |
| `maxItemLevel` | number | 10.1.0 – track maksimum ilvl |
| `upgradeLevelInfos` | ItemUpgradeLevelInfo[] | Her seviye için ilvl artışı ve maliyetler |
| `customUpgradeString` | string? | 10.1.0 – alternatif track/özel metin |
| `upgradeCostTypesForSeason` | ItemUpgradeSeasonalCostType[] | 10.1.0 |

## ItemUpgradeLevelInfo (upgradeLevelInfos[i])

| Alan | Tip | Açıklama |
|------|-----|----------|
| `upgradeLevel` | number | Seviye indeksi |
| `displayQuality` | number | Kalite |
| `itemLevelIncrement` | number | Bu adımda +ilvl |
| `levelStats` | ItemUpgradeStat[] | İstatistik bilgisi |
| `currencyCostsToUpgrade` | ItemUpgradeCurrencyCost[] | 10.0.5 – **bir sonraki upgrade maliyeti** |
| `itemCostsToUpgrade` | ItemUpgradeItemCost[] | 10.0.5 |
| `moneyCost` | number? | 12.0.1 – WOWMONEY (copper) |
| `failureMessage` | string? | Hata mesajı |

## ItemUpgradeCurrencyCost

| Alan | Tip |
|------|-----|
| `currencyID` | number |
| `cost` | number |

## İlgili API’ler

- **Mevcut ilvl (upgrade dahil):** `C_Item.GetCurrentItemLevel(location)` — doğru ilvl için bunu kullan; sadece `GetItemInfo` base ilvl verir.
- **Detaylı ilvl (link’ten):** `C_Item.GetDetailedItemLevelInfo(itemLink)` — bonus ID’ler dahil.

## TWW (Midnight) track’ler

Wiki: *Upgrade levels: Explorer - Adventurer - Veteran - Champion - Hero - Myth*.  
Dawncrest currency’ler (GearService.UPGRADE_CURRENCY_IDS): Adventurer → Veteran → Champion → Hero → Myth.

## Notlar

- `GetItemUpgradeItemInfo()` bazen “upgrade UI’daki seçili eşya” için parametresiz çağrılıyor (eski davranış); addon’da **her slot için** `ItemLocation:CreateFromEquipmentSlot(slotID)` ile çağrı yapıyoruz.
- 10.0.5’te `costsToUpgrade` kaldırıldı; maliyetler `upgradeLevelInfos[].currencyCostsToUpgrade` içinde.
- Track adı boş dönerse `customUpgradeString` (10.1.0+) fallback olarak kullanılabilir.
