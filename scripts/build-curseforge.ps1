# Warband Nexus - CurseForge Build Script
# Creates a clean build package with only addon-required files.
# Run from repo root: .\scripts\build-curseforge.ps1

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $RootDir "build"
$OutputDir = Join-Path $BuildDir "WarbandNexus"

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

Write-Host "Warband Nexus - CurseForge Build" -ForegroundColor Cyan
Write-Host "Root: $RootDir" -ForegroundColor Gray
Write-Host ""

# Clean build dir
if (Test-Path $OutputDir) {
    Remove-Item -Path $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Core files
Write-Host "Copying core files..." -ForegroundColor Yellow
@("WarbandNexus.toc", "embeds.xml", "Core.lua", "Config.lua", "LICENSE") | ForEach-Object {
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

# Create zip for CurseForge
$ZipPath = Join-Path $BuildDir "WarbandNexus.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Write-Host ""
Write-Host "Creating zip: $ZipPath" -ForegroundColor Yellow
Compress-Archive -Path $OutputDir -DestinationPath $ZipPath -Force

Write-Host ""
Write-Host "Build complete!" -ForegroundColor Green
Write-Host "  Output: $OutputDir" -ForegroundColor Gray
Write-Host "  Zip:    $ZipPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Upload WarbandNexus.zip to CurseForge." -ForegroundColor Cyan
