# Warband Nexus - Merkezi Collection Mimarisi

## Tek Kaynak: db.global.collectionStore

Tüm collection verileri (mount, pet, toy, achievement, title, illusion) tek DB yapısında:

```lua
collectionStore = {
  version = CACHE_VERSION,
  lastBuilt = 0,
  mount   = { [id] = { id, name, icon, source, description, collected, creatureDisplayID, ... } },
  pet     = { [id] = { id, name, icon, source, description, collected, creatureDisplayID, ... } },
  toy     = { [id] = { id, name, icon, source, collected, ... } },
  achievement = { [id] = { id, name, icon, points, description, collected, rewardItemID, rewardTitle, ... } },
  title   = { [id] = { id, name, icon, rewardText, collected, ... } },
  illusion = { [id] = { id, name, icon, source, collected, ... } },
}
```

## API Kullanımı

- **Sadece** veri yoksa veya versiyon uyumsuzsa API taraması tetiklenir
- Aksi halde tüm veri DB'den okunur

## Collections Sekmesi

- **GetAllMountsData**, **GetAllPetsData**, **GetAllToysData**, **GetAllAchievementsData**
- Hepsi `collectionStore` üzerinden tam liste döner (collected + uncollected)
- UI filtreleri: Collected / Uncollected checkbox'ları ile gösterim

## Plans Sekmesi

- **GetUncollectedMounts**, **GetUncollectedPets**, **GetUncollectedToys**, **GetUncollectedAchievements**, **GetUncollectedIllusions**, **GetUncollectedTitles**
- Hepsi `collectionStore` üzerinden `collected == false` filtresi ile döner

## Ortak Eventler (Collections + Plans aynı eventleri dinler)

- `WN_COLLECTIBLE_OBTAINED` → RemoveFromUncollected (collectionStore güncelle), SaveCollectionStore, `WN_COLLECTION_UPDATED`
- `WN_COLLECTION_UPDATED` → Collections + Plans refresh (tab görünürse)
- `WN_COLLECTION_SCAN_COMPLETE` → Collections + Plans refresh
- `WN_COLLECTION_SCAN_PROGRESS` → Loading state güncelle
