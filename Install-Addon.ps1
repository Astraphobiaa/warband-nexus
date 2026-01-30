# Warband Nexus - Otomatik Kurulum Scripti
# Bu script addon'u otomatik olarak WoW AddOns klasörüne kurar

param(
    [string]$WowPath = "C:\Program Files (x86)\World of Warcraft"
)

Write-Host "=== Warband Nexus Otomatik Kurulum ===" -ForegroundColor Cyan
Write-Host ""

# WoW yolunu kontrol et
if (-not (Test-Path $WowPath)) {
    Write-Host "HATA: WoW yolu bulunamadi: $WowPath" -ForegroundColor Red
    Write-Host "Lutfen dogru yolu girin:" -ForegroundColor Yellow
    $WowPath = Read-Host "WoW klasoru yolu"
    
    if (-not (Test-Path $WowPath)) {
        Write-Host "Gecersiz yol! Kurulum iptal edildi." -ForegroundColor Red
        exit 1
    }
}

# AddOns klasorunu bul
$AddOnsPath = Join-Path $WowPath "_retail_\Interface\AddOns"

if (-not (Test-Path $AddOnsPath)) {
    Write-Host "HATA: AddOns klasoru bulunamadi: $AddOnsPath" -ForegroundColor Red
    exit 1
}

Write-Host "WoW AddOns klasoru bulundu: $AddOnsPath" -ForegroundColor Green

# Kaynak ve hedef klasorler
$SourcePath = $PSScriptRoot
$DestPath = Join-Path $AddOnsPath "WarbandNexus"

Write-Host "Kaynak: $SourcePath" -ForegroundColor Gray
Write-Host "Hedef: $DestPath" -ForegroundColor Gray
Write-Host ""

# Eski versiyonu sil
if (Test-Path $DestPath) {
    Write-Host "Eski versiyon siliniyor..." -ForegroundColor Yellow
    Remove-Item -Path $DestPath -Recurse -Force
}

# Yeni klasor olustur
Write-Host "Yeni klasor olusturuluyor..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $DestPath -Force | Out-Null

# Kopyalanacak dosya ve klasorler
$ItemsToCopy = @(
    "WarbandNexus.toc",
    "Core.lua",
    "Config.lua",
    "embeds.xml",
    "Modules",
    "Locales",
    "Fonts",
    "Media",
    "libs"
)

Write-Host "Dosyalar kopyalaniyor..." -ForegroundColor Yellow

foreach ($item in $ItemsToCopy) {
    $source = Join-Path $SourcePath $item
    $dest = Join-Path $DestPath $item
    
    if (Test-Path $source) {
        Write-Host "  - $item" -ForegroundColor Gray
        Copy-Item -Path $source -Destination $dest -Recurse -Force
    } else {
        Write-Host "  - UYARI: $item bulunamadi" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== KURULUM TAMAMLANDI ===" -ForegroundColor Green
Write-Host ""
Write-Host "Addon konumu: $DestPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Simdi yapmaniz gerekenler:" -ForegroundColor White
Write-Host "1. World of Warcraft'i baslatin" -ForegroundColor White
Write-Host "2. Karakter secim ekraninda 'AddOns' butonuna tiklayin" -ForegroundColor White
Write-Host "3. 'Warband Nexus' addon'unu aktif edin" -ForegroundColor White
Write-Host "4. Oyuna girin ve /wn yazarak addon'u test edin" -ForegroundColor White
Write-Host ""
Write-Host "Basarilar!" -ForegroundColor Green

# Dosya sayisi kontrolu
$fileCount = (Get-ChildItem -Path $DestPath -Recurse -File).Count
Write-Host ""
Write-Host "Toplam $fileCount dosya kopyalandi." -ForegroundColor Gray
