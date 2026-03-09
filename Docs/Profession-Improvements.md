# Profession Modülü: İyileştirmeler ve Diğer Addon Karşılaştırması

## Mevcut Özellikler (Özet)

- **Concentration**: Toplama (TRADE_SKILL_SHOW), tooltip enjeksiyonu, 1 dk ticker, bar + recharge sütunu.
- **Knowledge**: Spec tree bilgisi (unspent/spent/max), C_ProfSpecs/C_Traits zinciri.
- **Recipe sayıları**: Known/total, first craft bonus, skill-up recipe sayıları.
- **Cooldown**: Aktif cooldown’lar tarama anında kaydediliyor; UI’da kalan süre `remaining - (now - scannedAt)` ile hesaplanıyor.
- **Crafting orders**: Claims remaining, personal pending; **public order sayısı implemente değil** (yorumda "GetCrafterBuckets async" deniyor).
- **Profession equipment**: Tool + 2 accessory, slot 20/21/22; login’de ve pencere açıldığında toplanıyor.
- **Recipe Companion**: Reagent listesi, “kimde var” (GetCraftersForRecipe), quality tier ikonları.
- **Expansion alt-profesyonlar**: Her expansion için skill level (GetChildProfessionInfos / login refresh).

---

## Eksik veya Hatalı Olanlar

### 1. Public crafting orders sayısı (eksik)

- **Durum**: `CollectOrderData()` içinde `claimsRemaining` ve `personalPending` dolduruluyor; `publicAvailable` hiç set edilmiyor (yorum: "GetCrafterBuckets is async").
- **Diğer addonlar**: Profession Shopping List / TSM tarzı eklentiler genelde “kaç public order var” veya “crafter bucket” bilgisini gösterir.
- **Öneri**: `C_CraftingOrders.GetCrafterBuckets` veya ilgili API ile public order/crafter bucket sayısını doldurmak; async ise callback veya event (örn. `CRAFTINGORDERS_*`) ile güncellemek.

### 2. Cooldown verisi sadece pencere açıkken taranıyor

- **Durum**: Cooldown’lar yalnızca TRADE_SKILL_SHOW (ve ilgili güncellemeler) sırasında toplanıyor. Pencere kapalıyken “X dakika sonra hazır” geri sayımı UI’da hesaplanıyor ama yeni tarama yok.
- **Diğer addonlar**: Profession Cooldown gibi addonlar cooldown’ları takip edip “Cooldown ready” bildirimi verebiliyor.
- **Öneri**: İsteğe bağlı “cooldown ready” bildirimi; veya cooldown verisini periyodik (ör. 60 sn) veya uygun event ile güncellemek (API izin veriyorsa).

### 3. Recipe storage key tutarsızlığı

- **Durum**: `charData.recipes[storeKey]` bazen `skillLineID` (number) bazen `professionName` (string) ile yazılıyor (`storeKey = skillLineID or professionName`). UI `GetRecipeCount`/`GetCraftStats` içinde `professionName` ile arama + fallback (pairs + professionName eşleşmesi) yapıyor.
- **Risk**: Locale değişince veya API’nin döndüğü isim farklılaşınca çift giriş veya eşleşmeme olabilir.
- **Öneri**: Mümkünse tek tip key kullanmak (tercihen `professionName`; skillLineID’yi sadece yardımcı alan olarak saklamak). Migration ile eski sayısal key’leri professionName’e taşımak.

### 4. PROFESSION_NAME_TO_ENUM eksik girişler

- **Durum**: `ProfessionService.lua` içinde `PROFESSION_NAME_TO_ENUM` sadece klasik profesyonlarla tanımlı (First Aid, Blacksmithing, … Archaeology). TWW/Midnight’ta yeni profesyon veya `Enum.Profession` değişikliği varsa eşleşmeyebilir.
- **Öneri**: Güncel `Enum.Profession` değerlerini kontrol edip eksik profesyonları eklemek; veya API’den enum/isim eşlemesini dinamik almak (varsa).

### 5. Archaeology (GetProfessions) atlanıyor

- **Durum**: `CollectEquipmentByDetection()` içinde `local prof1, prof2, _arch, fish, cook = GetProfessions()`; `_arch` kullanılmıyor, sadece `prof1, prof2, fish, cook` dolaştırılıyor.
- **Öneri**: Archaeology kullanılıyorsa `profIndices` içine ekleyip equipment toplamak; yoksa yorumla belirtmek (bilinçli hariç tutma).

### 6. Veri yalnızca profesyon penceresi açıldığında

- **Durum**: Recipe, cooldown, orders, detaylı knowledge/concentration verisi TRADE_SKILL_SHOW’a bağlı. Kullanıcı hiç profesyon penceresini açmazsa o karakterde bu veriler boş kalıyor.
- **Diğer addonlar**: Bazıları login’de veya arka planda sınırlı veri toplar (ör. sadece skill level).
- **Öneri**: Davranışı dokümante etmek (“Profesyon penceresini her karakterde en az bir kez açın”). İleride API izin verirse login’de minimal recipe/cooldown özeti (ör. sadece sayı) eklenebilir.

### 7. UI standardı (ProfessionsUI)

- **Durum**: Concentration bar için `CreateFrame("Frame", nil, parent)` kullanılıyor (ProfessionsUI.lua ~195). Proje standardına göre container’lar `ns.UI.Factory:CreateContainer` ile oluşturulmalı.
- **Öneri**: Bar container’ı Factory’den üretmek; görsel (fill, border) aynı kalabilir.

### 8. Recraft / recipe quality özeti

- **Durum**: Recipe Companion’da kalite tier ikonları var; ana Professions sekmesinde “recraft edilebilir recipe sayısı” veya “quality tier dağılımı” yok.
- **Diğer addonlar**: CraftSim vb. quality, recraft, optimal reagent bilgisini vurgular.
- **Öneri**: İsteğe bağlı sütun veya tooltip: “X recraft recipe”, “Y adet 3. tier” gibi (API’den mevcut ise).

### 9. Filtreleme ve sıralama

- **Durum**: Karakter sıralama (isim, level, ilvl, gold, manual) var; “sadece şu profesyona sahip karakterler”, “en az 1 first craft bonusu kalanlar” gibi filtreler yok.
- **Öneri**: İsteğe bağlı filtre: profesyon adı, “first craft var”, “cooldown’u olan” vb. Sütun bazlı sıralama (recipe sayısına, concentration’a göre) eklenebilir.

### 10. Bildirimler

- **Durum**: Concentration/recharge tooltip ve profession tab’da görsel bilgi var; “Concentration full”, “Cooldown ready”, “Yeni recipe öğrenildi” gibi toast/uyarı yok.
- **Öneri**: Ayarlanabilir bildirimler (mevcut notification altyapısına bağlanabilir): concentration full, belirli cooldown hazır, (isteğe bağlı) yeni recipe.

### 11. Midnight 12.0 / issecretvalue

- **Durum**: Profession API’leri (isim, recipe name vb.) şu an doğrudan string olarak kullanılıyor. Genelde event/UI bağlamında secret dönmüyor ama tooltip veya başka yerlerde API’den gelen metinlerde guard güvenliği kuralına uymak iyi olur.
- **Öneri**: `GetBaseProfessionInfo`, `GetRecipeInfo`.name, `GetProfessionInfo` gibi dönen stringleri tooltip veya karşılaştırmada kullanmadan önce `Utilities:IsSecretValue` / `SafeString` ile korumak (risk düşük olsa da tutarlılık için).

---

## Diğer Addonlarda Olup Bizde Olmayanlar (Özet)

| Özellik | Bizde | Not |
|--------|--------|-----|
| Public order sayısı | Hayır | CollectOrderData’da boş bırakılmış. |
| Cooldown “ready” bildirimi | Hayır | Sadece tab’da kalan süre; bildirim yok. |
| Concentration full bildirimi | Hayır | Tooltip var, toast yok. |
| Recipe/cooldown verisi penceresiz | Kısmen | Sadece expansion/skill; recipe/cooldown için pencere gerekli. |
| Recraft / quality özeti (tab) | Hayır | Companion’da quality var; tab’da özet yok. |
| Profesyon / first craft filtre | Hayır | Filtre yok. |
| Sütun bazlı sıralama (recipe, conc.) | Hayır | Sadece karakter sıralaması var. |
| Archaeology equipment | Belirsiz | GetProfessions’ta _arch kullanılmıyor. |
| Recipe key tek tip (professionName) | Kısmen | Fallback ile çalışıyor; key’i standardize etmek daha sağlam. |

---

## Öncelik Önerisi

1. **Yüksek**: Public order sayısını doldurmak (veya “N/A”/“—” ile açıkça göstermek); recipe storage key’i professionName’e standardize etmek.
2. **Orta**: Concentration bar’ı Factory container’a taşımak; PROFESSION_NAME_TO_ENUM ve Archaeology’yi gözden geçirmek; cooldown/concentration (ve isteğe bağlı recipe) bildirimleri.
3. **Düşük**: Recraft/quality özeti, filtreler, sütun bazlı sıralama; profession API çıktılarında issecretvalue guard’ları.

Bu doküman, profession modülünde yapılabilecek iyileştirmeleri ve diğer addonlarla farkları tek yerde toplar; geliştirme sırası için referans olarak kullanılabilir.
