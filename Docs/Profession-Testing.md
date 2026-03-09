# Profession Modülü — Test Rehberi

Bu doküman, profession ile ilgili yapılan değişikliklerin nasıl test edileceğini adım adım açıklar.

---

## 1. Profesyon ekipmanının anlık güncellenmesi

**Değişiklik:** `WN_PROFESSION_EQUIPMENT_UPDATED` mesajı UI.lua’da dinleniyor; ekipman değişince açık olan Professions veya Characters sekmesi yenileniyor.

### Nasıl test edilir

1. Addonu aç, **Professions** sekmesine geç.
2. Karakterinde profesyon ekipmanı (slot 20/21/22) takılı olsun; listede ilgili karakterin ekipman ikonları görünsün.
3. **Pencere açık ve Professions sekmesi görünürken** profesyon ekipmanını değiştir (ör. alet çıkar veya başka alet tak).
4. **Beklenen:** Birkaç yüz ms içinde satır güncellenir; yeni ekipman ikonu/boş slot görünür, yenileme butonuna basmaya gerek kalmaz.
5. Aynı testi **Characters** sekmesinde tekrarla: Characters sekmesi açıkken profesyon ekipmanını değiştir; o sekmedeki profession equipment alanı anında güncellenmeli.

### Regresyon

- Ekipman değiştirdikten sonra **başka bir sekmedeysen** (Items, Currency vb.) o sekme değişmemeli; sadece Professions/Chars açıkken yenilenme olmalı.

---

## 2. Recipe storage (skillLineID) ve migration

**Değişiklik:** Recipe verisi artık `skillLineID` ile saklanıyor (expansion başına ayrı kayıt). Eski professionName/string key'leri ilk toplamada `skillLineID` key'ine taşınıyor; aynı profession altında farklı expansion'ların üst üste yazılması engellendi.

### Nasıl test edilir

1. **Yeni veri:** Bir karakterde profesyon penceresini aç (K). Bir profesyon seç (ör. Tailoring). Birkaç saniye bekle.
2. Addonu aç → **Professions** sekmesi. Sağ üstten expansion filtresini **Midnight** yap. İlgili karakterde o expansion'a ait recipe sayısı (known/total) görünmeli.
3. **Eski veri (migration):** Daha önce aynı karakterde profesyon açıp recipe verisi toplandıysa (eski addonla), o karakterde profesyon penceresini tekrar açıp bir profesyon seç. Addon veriyi toplarken eski sayısal key’i professionName key’ine taşır.
4. **Beklenen:** Recipe sayıları doğru (known/total), First Craft / Skill Ups sütunları anlamlı. Hiçbir profesyonda “0 / 0” veya boş görünmemeli (en az bir kez pencere açıldıysa).

### Regresyon

- Birden fazla expansion alt-profesyonu olan (ör. Dragon Isles + Khaz Algar) bir profesyonda tek satır görünmeli; recipe sayıları birleşik/doğru olmalı (UI zaten professionName ile okuyordu, sadece depolama key’i değişti).

---

## 3. Archaeology equipment toplama

**Değişiklik:** `CollectEquipmentByDetection()` artık `GetProfessions()` dönüşündeki Archaeology index’ini de (`arch`) kullanıyor; Archaeology bilen karakterlerin profesyon ekipmanı da taranıyor.

### Nasıl test edilir

1. **Archaeology bilen bir karakterle** giriş yap.
2. O karakterde profesyon ekipman slotlarından en az birini (20/21/22) doldur (herhangi bir profesyon aleti/aksesuarı).
3. Addonu aç → **Characters** sekmesi → ilgili karakteri bul → profession equipment alanına bak **veya** **Professions** sekmesinde o karakterin satırına bak.
4. **Beklenen:** Ekipman listesinde Archaeology ile ilişkili slotlar da (varsa) görünür. Archaeology bilmeyen karakterde davranış değişmez.

### Not

- WoW’da Archaeology’nin kendi ekipman slotları olmayabilir; bu durumda görsel değişiklik olmayabilir. Test, “arch” index’inin artık döngüye dahil edildiği ve `GetProfessionInfo(arch)` ile “Archaeology” alındığı için enum eşleşmesinin çalıştığını doğrulamak içindir.

---

## 4. Public orders (davranış değişmedi)

**Değişiklik:** Sadece kod içi yorum güncellendi; `publicAvailable` alanı senkron API olmadığı için 0 kalmaya devam ediyor.

### Nasıl test edilir

1. Profesyon penceresini aç, crafting order kullanılabilir bir profesyon seç (masa yakınında ol).
2. Addon → **Professions** sekmesi → Orders sütununa bak.
3. **Beklenen:** Claims remaining / personal pending sayıları (varsa) doğru; public order sayısı 0 veya “—” gibi görünebilir. Önceki davranışla aynı olmalı.

---

## 5. Concentration bar (Factory container)

**Değişiklik:** Concentration bar container’ı `CreateFrame` yerine `ns.UI.Factory:CreateContainer` ile oluşturuluyor.

### Nasıl test edilir

1. Addonu aç → **Professions** sekmesi.
2. En az bir karakterde concentration verisi olan bir profesyon satırı seç (profesyon penceresi açılıp concentration toplanmış olmalı).
3. **Beklenen:** Concentration sütununda bar görünür; doluluk oranı (current/max) doğru, renkler (yeşil/sarı/turuncu) ve kenarlık normal.
4. Bar üzerine gelince tooltip (varsa) düzgün çıksın.

### Regresyon

- Bar kaybolmamalı, çift çerçeve veya layout bozukluğu olmamalı. Factory container border’sız kullanıldığı için görünüm öncekiyle aynı olmalı.

---

## 6. Expansion filter (sağ üst dropdown)

**Değişiklik:** Professions sekmesi başlık kartında expansion filtresi artık **dinamik** olarak oluşturuluyor. Karakterlerin sahip olduğu expansion'lar tespit edilip dropdown'a sadece onlar (ve "All") ekleniyor. Seçilen expansion dışındaki veri gösterilmez; Recipes, 1st Craft, Skill Ups, Skill, Concentration, Knowledge sütunları sadece seçili expansion'a göre doldurulur.

### Nasıl test edilir

1. Addonu aç → **Professions** sekmesi. Sağ üstte expansion dropdown'u gör.
2. Sadece karakterlerinizin gerçekten sahip olduğu expansion'ların listelendiğini doğrulayın (hiç veri yoksa statik Midnight, Khaz Algar, vb. çıkar).
3. **Midnight** seçiliyken: Tüm karakter satırlarında sadece Midnight expansion'ına ait recipe/first craft/skill değerleri görünmeli. Khaz Algar verisi karışmamalı.
4. **Khaz Algar** seç: Aynı karakterlerde değerler Khaz Algar'a göre değişmeli (veya o expansion verisi yoksa --).
5. **All** seç: En güncel / ilgili expansion verisi gösterilir. **Önemli:** Recipe sütununun üzerine geldiğinizde açılan tooltip'te tarif sayıları (*Learned / Total*) expansion'lar arası **toplanmamalı**, her expansion için ayrı bir satır olarak katı bir şekilde ayrıştırılıp gösterilmelidir.
6. Filtre değişimi profile'da saklanır; addon yeniden açıldığında son seçim korunmalı.

### Doğrulama

- TRADE_SKILL_LIST_UPDATE tetiklendiğinde `CollectRecipeData`, API'den gelen category hiyerarşisini kullanarak tüm tarifleri ait oldukları expansion'a (skillLineID) göre gruplar ve ayrı kayıtlar olarak kaydeder. Active tab'den bağımsız olarak tüm tarifler doğru yerlerine gider.

---

## 7. Genel profession akışı (smoke test)

1. **Profesyon penceresi (K):** Aç → concentration / knowledge / recipe sayıları güncellenmeli.
2. **Professions sekmesi:** Tüm takip edilen karakterler listelenmeli; skill, concentration, knowledge, recipes, orders sütunları anlamlı.
3. **Characters sekmesi:** Karakter detayında profession equipment bölümü doğru.
4. **Recipe Companion:** Profesyon penceresinde bir recipe seç → Companion açılsın, reagent listesi ve “kimde var” bilgisi görünsün.
5. **Ekipman değişimi:** Professions veya Characters sekmesi açıkken slot 20/21/22’yi değiştir → liste anında güncellenmeli (madde 1).

---

## Hızlı kontrol listesi

| Test | Ne yapılır | Beklenen |
|------|------------|----------|
| Ekipman anlık güncelleme | Professions/Chars açıkken slot 20/21/22 değiştir | Liste 1 sn içinde güncellenir |
| Recipe (skillLineID) | Profesyon aç, expansion seç → Professions + expansion filtresi | Recipe/1st Craft seçili expansion'a göre |
| Expansion filter | Sağ üst dropdown: Midnight / Khaz Algar / All | Sütunlar sadece seçili expansion; filter persist |
| Archaeology | Arch bilen char, ekipman tak → Characters/Professions | Ekipman (varsa) görünür |
| Public orders | Profesyon + masa → Orders sütunu | 0 veya mevcut davranış |
| Concentration bar | Professions sekmesi, concentration’lı satır | Bar görünür, layout bozuk değil |
| Genel | K aç, sekme geç, companion, ekipman değiştir | Tüm akışlar sorunsuz |

Bu adımlar, yapılan profession değişikliklerinin doğrulanması ve regresyonların önlenmesi için kullanılabilir.
