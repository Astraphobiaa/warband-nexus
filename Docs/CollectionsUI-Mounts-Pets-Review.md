# Collections UI: Mounts & Pets Sub-tabs — Baştan Sona İnceleme

## 1. Genel Akış

```
Sub-tab tıklama (Mounts/Pets)
  → DrawMountsContent(contentFrame) / DrawPetsContent(contentFrame)
  → Busy guard (_draw*ContentBusy), drawGen++
  → Layout: cw/ch, listContentWidth, viewerWidth
  → Diğer sub-tab container'ları Hide
  → Liste container + ScrollFrame + scrollChild + scrollBarContainer (yoksa oluştur)
  → Model viewer (paylaşımlı; yoksa oluştur)
  → onSelectMount / onSelectPet closure
  → Veri: _cachedMountsData / _cachedPetsData veya nil
  → isLoading ? loading panel göster + C_Timer.After(COLLECTION_HEAVY_DELAY, fetch+BuildGrouped+Populate)
              : listeyi göster + C_Timer.After(COLLECTION_HEAVY_DELAY, BuildGrouped + C_Timer.After(0, Populate*List))
  → _draw*ContentBusy = nil
```

- **COLLECTION_HEAVY_DELAY (0.1s):** Sekme tıklanınca ağır iş (GetAll*Data, BuildGrouped, Populate) bu süre sonra çalışıyor; tıklama frame’i hafif kalıyor.
- **currentSubTab kontrolü:** Tüm ertelenen callback’lerde `currentSubTab == "mounts"` / `"pets"` bakılıyor; sekme değiştiyse iş yapılmıyor.

---

## 2. Veri Katmanı

| Bileşen | Mounts | Pets |
|--------|--------|------|
| Kategori listesi | `SOURCE_CATEGORIES` (12) | `PET_SOURCE_CATEGORIES` (14; petbattle, puzzle ekstra) |
| Sınıflandırma | `ClassifyMountSource(sourceText)` | `ClassifyPetSource(sourceText)` |
| Ham veri | `WarbandNexus:GetAllMountsData()` | `WarbandNexus:GetAllPetsData()` |
| Cache | `collectionsState._cachedMountsData` | `collectionsState._cachedPetsData` |
| Cache temizleme | WN_COLLECTION_SCAN_COMPLETE, WN_COLLECTION_UPDATED | Aynı |
| Gruplu veri | `BuildGroupedMountData(search, showC, showU, optionalMounts)` | `BuildGroupedPetData(..., optionalPets)` |
| Cache yokken API | `C_MountJournal.GetMountIDs` + döngü | `C_PetJournal.GetNumPets` + `GetPetInfoByIndex` |
| Güvenli API | `SafeGetMountCollected`, `SafeGetMountInfoExtra` | `SafeGetPetCollected`, `SafeGetPetInfoExtra` (issecretvalue korumalı) |

- **BuildGrouped*:** `optionalMounts`/`optionalPets` verilirse API/DB çağrısı yok; aksi halde GetAll*Data veya journal API kullanılıyor.
- **BuildFlat*List:** Gruplu veriden header+row flat list + totalHeight; SOURCE_CATEGORIES / PET_SOURCE_CATEGORIES sırasına göre.

---

## 3. UI Bileşenleri

| Öğe | Mounts | Pets | Not |
|-----|--------|------|-----|
| Liste container | `mountListContainer` | `petListContainer` | Factory:CreateContainer |
| ScrollFrame | `mountListScrollFrame` | `petListScrollFrame` | Factory:CreateScrollFrame, UIPanelScrollFrameTemplate |
| ScrollChild | `mountListScrollChild` | `petListScrollChild` | CreateFrame("Frame") — Factory dışı |
| ScrollBar container | `mountListScrollBarContainer` | `petListScrollBarContainer` | CreateFrame — liste ile viewer arasında |
| Model viewer | `modelViewer` | (aynı) | Paylaşımlı; CreateModelViewer |
| Loading panel | `loadingPanel` | (aynı) | Paylaşımlı; CreateLoadingPanel |

- Mounts’ta: `mountListContainer` var ama `mountListScrollBarContainer` yoksa else dalında oluşturuluyor. Pets’te scrollBarContainer her zaman liste ile birlikte (if/else tutarlı). Küçük fark, işlev aynı.

---

## 4. Sanal Liste (Virtual Scroll)

- **PopulateMountList / PopulatePetList:**
  - ScrollChild’ı temizler, `BuildFlat*List` ile flat list + totalHeight alır.
  - Sadece **header**’ları oluşturur (`Factory:CreateSectionHeader`).
  - Satırlar **sanal:** `_mountFlatList` / `_petFlatList` + `UpdateMountListVisibleRange` / `UpdatePetListVisibleRange` ile görünür aralıkta pool’dan row alınır (`AcquireMountRow` / `AcquirePetRow` → `AcquireCollectionRow`).
  - `OnVerticalScroll` → C_Timer.After(0, Update*VisibleRange) (debounce).
  - Populate sonunda `C_Timer.After(0, UpdateMountListVisibleRange)` ile ilk görünür satırlar ertesi frame’de çizilir.

- **Header toggle:** Collapse/expand → `_mountTogglePending`/`_petTogglePending` debounce → `PopulateMountList`/`PopulatePetList` `_lastGroupedMountData`/`_lastGroupedPetData` ile tekrar çağrılıyor (BuildGrouped tekrarlanmıyor).

---

## 5. Tetikleyiciler

| Olay | Davranış |
|------|----------|
| Sub-tab tıklama | Aynı sekme ise sadece SetActiveTab; değiştiyse Draw*Content. Mounts/Pets için ağır iş COLLECTION_HEAVY_DELAY ile ertelenir. |
| Search OnTextChanged | Her tuşta Draw*Content(collectionsState.contentFrame). Mounts/Pets yine 0.1s gecikmeli ağır iş. |
| Filter (Collected/Uncollected) OnClick | Draw*Content doğrudan. |
| WN_COLLECTION_SCAN_PROGRESS | mainFrame collections + contentFrame varsa Draw*Content (hangi sub-tab ise o). Debounce yok; tarama sırasında sık tetiklenebilir. |
| WN_COLLECTION_SCAN_COMPLETE | Cache temizlenir, RefreshUI. |
| WN_COLLECTION_UPDATED(updatedType) | Cache temizlenir; updatedType mount/pet/achievement’a göre ilgili sub-tab için Draw*Content. |

---

## 6. Tutarlılık Özeti

- **Mounts ve Pets** aynı deseni kullanıyor: Draw*Content → layout → loading/dataReady → ertelenmiş BuildGrouped + Populate, currentSubTab ve drawGen ile iptal.
- **Farklar:** Sadece kategori seti (SOURCE vs PET_SOURCE), sınıflandırma (ClassifyMountSource vs ClassifyPetSource), API (mount vs pet), state alan adları (_cachedMountsData vs _cachedPetsData, _mountsDrawGen vs _petDrawGen). Yapı birebir paralel.
- **Achievements:** BuildGroupedAchievementData + PopulateAchievementList senkron; veri/kategori yapısı farklı (GetCategoryList, hierarchy). Mounts/Pets’e göre daha az veri olduğu için donma yok.

---

## 7. Olası İyileştirmeler

1. **Search debounce:** OnTextChanged her tuşta Draw*Content çağırıyor. 200–300 ms debounce ile sadece yazma durduğunda tek Draw*Content çağrılabilir (özellikle Mounts/Pets’te 0.1s’lik ağır iş tekrarını azaltır).
2. **WN_COLLECTION_SCAN_PROGRESS:** Sadece `currentSubTab == "mounts"` / `"pets"` iken ilgili Draw*Content çağrılabilir; gereksiz Achievements çizimi önlenir. İsteğe bağlı: throttle (örn. 0.5 s) eklenebilir.
3. **ScrollBar container:** Mounts’taki “container var scrollBar yok” else dalı, Pets ile aynı olacak şekilde sadeleştirilebilir (ilk oluşturmada her zaman scrollBarContainer da oluşturulur).

Bu doküman, Mounts ve Pets sub-tab’lerinin baştan sona akışını, veri/UI/olay tutarlılığını ve küçük iyileştirme noktalarını özetler.
