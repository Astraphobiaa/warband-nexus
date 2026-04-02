# Warband Nexus - CurseForge / release zip build
# Creates build\WarbandNexus\ with addon files, then:
#   - build\WarbandNexus.zip          (CurseForge upload)
#   - build\WarbandNexus-<version>.zip (versioned, e.g. for Discord / testers)
# Run: .\scripts\build-curseforge.ps1   (from repo root or any cwd — script resolves root)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RootDir "build"
$OutputDir = Join-Path $BuildDir "WarbandNexus"

function Get-AddonVersion {
    $constantsPath = Join-Path $RootDir "Modules\Constants.lua"
    if (-not (Test-Path $constantsPath)) { return "0.0.0" }
    $raw = Get-Content -Path $constantsPath -Raw
    $m = [regex]::Match($raw, 'ADDON_VERSION\s*=\s*"([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return "0.0.0"
}

Write-Host "Warband Nexus - CurseForge Build" -ForegroundColor Cyan
Write-Host "Root: $RootDir" -ForegroundColor Gray

$AddonVersion = Get-AddonVersion
Write-Host "Version: $AddonVersion (from Modules\Constants.lua)" -ForegroundColor DarkGray
Write-Host ""

# Files/folders to exclude (per .pkgmeta and dev artifacts)
$ExcludeLibs = @(
    "README.md", "README.textile", "changelog.txt", "LICENSE.txt",
    "Changelog-libdatabroker-1-1-v1.1.4.txt", "Ace3.toc", "LibDBIcon-1.0.toc"
)

function Copy-DirFiltered {
    param([string]$Source, [string]$Dest, [string[]]$ExcludeNames = @())
    if (-not (Test-Path $Source)) { return }
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    Get-ChildItem -Path $Source -Recurse | ForEach-Object {
        $rel = $_.FullName.Substring($Source.Length).TrimStart("\")
        $destPath = Join-Path $Dest $rel
        if ($ExcludeNames -contains $_.Name) { return }
        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Path $destPath -Force | Out-Null
        } else {
            $destDir = Split-Path -Parent $destPath
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item $_.FullName -Destination $destPath -Force
        }
    }
}

function Copy-Dir {
    param([string]$Source, [string]$Dest)
    if (-not (Test-Path $Source)) { return }
    Copy-Item -Path $Source -Destination $Dest -Recurse -Force
}

# Clean build dir
if (Test-Path $OutputDir) {
    Remove-Item -Path $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Core files
Write-Host "Copying core files..." -ForegroundColor Yellow
@("WarbandNexus.toc", "embeds.xml", "Core.lua", "Config.lua", "LICENSE", "RARITY_IMPORT_README.txt") | ForEach-Object {
    $src = Join-Path $RootDir $_
    if (Test-Path $src) { Copy-Item $src -Destination $OutputDir -Force }
}

# Libraries (with exclusions)
Write-Host "Copying libs..." -ForegroundColor Yellow
Copy-DirFiltered -Source (Join-Path $RootDir "libs") -Dest (Join-Path $OutputDir "libs") -ExcludeNames $ExcludeLibs

# Locales
Write-Host "Copying Locales..." -ForegroundColor Yellow
Copy-Dir -Source (Join-Path $RootDir "Locales") -Dest (Join-Path $OutputDir "Locales")

# Modules
Write-Host "Copying Modules..." -ForegroundColor Yellow
Copy-Dir -Source (Join-Path $RootDir "Modules") -Dest (Join-Path $OutputDir "Modules")

# Media
Write-Host "Copying Media..." -ForegroundColor Yellow
Copy-Dir -Source (Join-Path $RootDir "Media") -Dest (Join-Path $OutputDir "Media")

# Fonts (if used by addon)
if (Test-Path (Join-Path $RootDir "Fonts")) {
    Write-Host "Copying Fonts..." -ForegroundColor Yellow
    Copy-Dir -Source (Join-Path $RootDir "Fonts") -Dest (Join-Path $OutputDir "Fonts")
}

# Create zips (versioned + stable name for CurseForge)
$ZipPathCf = Join-Path $BuildDir "WarbandNexus.zip"
$ZipPathVersioned = Join-Path $BuildDir "WarbandNexus-$AddonVersion.zip"
foreach ($z in @($ZipPathCf, $ZipPathVersioned)) {
    if (Test-Path $z) { Remove-Item $z -Force }
}
Write-Host ""
Write-Host "Creating zip archives..." -ForegroundColor Yellow
Compress-Archive -Path $OutputDir -DestinationPath $ZipPathVersioned -Force
Copy-Item -Path $ZipPathVersioned -Destination $ZipPathCf -Force

Write-Host ""
Write-Host "Build complete!" -ForegroundColor Green
Write-Host "  Folder:  $OutputDir" -ForegroundColor Gray
Write-Host "  Zip (CF): $ZipPathCf" -ForegroundColor Gray
Write-Host "  Zip (v):  $ZipPathVersioned" -ForegroundColor Gray
Write-Host ""
Write-Host "Upload build\WarbandNexus.zip to CurseForge (or use the versioned file)." -ForegroundColor Cyan
