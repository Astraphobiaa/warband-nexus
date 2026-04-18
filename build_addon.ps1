#Requires -Version 5.1
# Mirrors build_addon.py — use when `python build_addon.py` is unavailable.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RepoRoot

$ConstantsPath = Join-Path $RepoRoot 'Modules\Constants.lua'
$raw = Get-Content -LiteralPath $ConstantsPath -Raw -Encoding UTF8
if ($raw -notmatch 'ADDON_VERSION\s*=\s*"([^"]+)"') { throw 'ADDON_VERSION not found in Modules\Constants.lua' }
$Version = $Matches[1]

$BuildDir = Join-Path $RepoRoot 'build'
$StageName = 'WarbandNexus'
$StageDir = Join-Path $BuildDir $StageName

$ExcludeRoot = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('.git', '.cursor', '.vscode', '.claude', '.tmp', 'build', 'scripts', 'Screenshots',
        '.tmp-addon-db-audit', $StageName, 'tests', 'docs'))
$ExcludeDirAnywhere = [System.Collections.Generic.HashSet[string]]::new([string[]]@('AceComm-3.0', 'AceTab-3.0'))
$RootFilesSkip = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('.gitignore', '.gitattributes', '.pkgmeta', 'README.md', 'CHANGELOG.md', 'CHANGES.txt',
        'VERSION_CURSEFORGE.md', 'VERSION_DISCORD.md', '_enc_w.html', 'TOS_COMPLIANCE.md', 'OPTIMIZATION_SUMMARY.md',
        'DEAD_CODE_AUDIT.md', 'EVENTS_AUDIT.md', 'STEP_FIX_LOG.md', 'build_addon.py', 'build_addon.ps1', 'CONTRIBUTORS.md'))

function Test-SkipRootShipFile([string]$name) {
    if ($RootFilesSkip.Contains($name)) { return $true }
    if ($name -eq 'update_locales.lua') { return $true }
    if ($name.EndsWith('.lua') -and $name.StartsWith('test')) { return $true }
    return $false
}

function Test-AnyPartInSet([string[]]$Parts, $Set) {
    foreach ($p in $Parts) { if ($Set.Contains($p)) { return $true } }
    return $false
}

if (Test-Path -LiteralPath $StageDir) { Remove-Item -LiteralPath $StageDir -Recurse -Force }
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

Get-ChildItem -LiteralPath $RepoRoot -Force | ForEach-Object {
    $name = $_.Name
    if ($_.PSIsContainer -and $ExcludeRoot.Contains($name)) { return }
    if (-not $_.PSIsContainer -and (Test-SkipRootShipFile $name)) { return }
    if ($_.PSIsContainer) {
        Get-ChildItem -LiteralPath $_.FullName -Recurse -Force | ForEach-Object {
            $rel = $_.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')
            $relParts = $rel -split '[\\/]'
            if (Test-AnyPartInSet -Parts $relParts -Set $ExcludeDirAnywhere) { return }
            $leaf = Split-Path -Leaf $rel
            if ($relParts.Count -eq 1 -and (Test-SkipRootShipFile $leaf)) { return }
            $dst = Join-Path $StageDir $rel
            if ($_.PSIsContainer) {
                if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
            } else {
                $parent = Split-Path -Parent $dst
                if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
            }
        }
    } else {
        $dst = Join-Path $StageDir $name
        Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
    }
}

$LibJunk = @(
    'libs/README.md', 'libs/README.textile', 'libs/changelog.txt', 'libs/CHANGES.txt', 'libs/LICENSE.txt',
    'libs/Changelog-libdatabroker-1-1-v1.1.4.txt', 'libs/Ace3.toc', 'libs/LibDBIcon-1.0.toc', 'libs/embeds.xml',
    'libs/Bindings.xml', 'libs/Ace3.lua', 'libs/LibDeflate/.xml'
)
foreach ($rel in $LibJunk) {
    $p = Join-Path $StageDir $rel
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}

$ZipPath = Join-Path $BuildDir "$StageName-$Version.zip"
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $StageDir -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($StageDir.Length).TrimStart('\', '/')
        $arc = ($StageName + '/' + ($rel -replace '\\', '/'))
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $arc) | Out-Null
    }
} finally { $zip.Dispose() }

$read = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    if ($read.Entries.Count -eq 0) { throw 'ZIP is empty' }
    foreach ($e in $read.Entries) {
        if ($e.FullName -match '\\') { throw "ZIP entries must use '/': $($e.FullName)" }
        if (-not $e.FullName.StartsWith("$StageName/")) { throw "ZIP entries must start with ${StageName}/: $($e.FullName)" }
    }
} finally { $read.Dispose() }

Write-Host "OK version $Version"
Write-Host $StageDir
Write-Host $ZipPath
