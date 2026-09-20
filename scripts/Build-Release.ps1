<#
  Packages the addon into a distributable zip.
  Reads AlternativeClassicActionBars.toc for the authoritative file list, so any
  file added to the .toc is automatically included in future releases.

  Usage:
    ./scripts/Build-Release.ps1 -Version 1.0.0-beta
    ./scripts/Build-Release.ps1                      # defaults to today's date
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$addonFolderName = "AlternativeClassicActionBars"
$tocPath = Join-Path $repoRoot "$addonFolderName.toc"

if (-not (Test-Path $tocPath)) {
    throw "Could not find $tocPath"
}

# .toc lines that aren't blank or ## metadata are the addon's own load list.
$addonFiles = @()
foreach ($line in (Get-Content $tocPath)) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("##")) { continue }
    $addonFiles += $trimmed
}

if ($addonFiles.Count -eq 0) {
    throw "No file entries found in $tocPath"
}

# Shipped alongside the .toc-listed files but not themselves in the .toc.
$extraFiles = @("LICENSE")
$extraDirs = @("Textures")

if ($Version -eq "") {
    $Version = Get-Date -Format "yyyy-MM-dd"
}

$stageRoot = Join-Path $repoRoot ".release-stage"
$stageAddonDir = Join-Path $stageRoot $addonFolderName

if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
New-Item -ItemType Directory -Path $stageAddonDir -Force | Out-Null

$stagedTocPath = Join-Path $stageAddonDir "$addonFolderName.toc"
Copy-Item $tocPath -Destination $stagedTocPath

# Stamp the staged .toc's ## Version line with the release version so the shipped
# zip always matches the tag, even if the committed .toc lagged behind.
$tocContent = Get-Content $stagedTocPath
if ($tocContent -match '^## Version:') {
    $tocContent = $tocContent -replace '^## Version:.*$', "## Version: $Version"
} else {
    $tocContent = @($tocContent[0]) + @("## Version: $Version") + $tocContent[1..($tocContent.Count - 1)]
}
Set-Content -Path $stagedTocPath -Value $tocContent

foreach ($file in $addonFiles) {
    $src = Join-Path $repoRoot $file
    if (-not (Test-Path $src)) {
        throw "Missing file listed in .toc: $file"
    }
    $destParent = Join-Path $stageAddonDir (Split-Path $file -Parent)
    if ($destParent -and -not (Test-Path $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }
    Copy-Item $src -Destination (Join-Path $stageAddonDir $file) -Force
}

foreach ($file in $extraFiles) {
    $src = Join-Path $repoRoot $file
    if (Test-Path $src) {
        Copy-Item $src -Destination (Join-Path $stageAddonDir $file) -Force
    }
}

foreach ($dir in $extraDirs) {
    $src = Join-Path $repoRoot $dir
    if (Test-Path $src) {
        Copy-Item $src -Destination (Join-Path $stageAddonDir $dir) -Recurse -Force
    }
}

$outDirFull = Join-Path $repoRoot $OutputDir
if (-not (Test-Path $outDirFull)) {
    New-Item -ItemType Directory -Path $outDirFull -Force | Out-Null
}

$zipName = "$addonFolderName-$Version.zip"
$zipPath = Join-Path $outDirFull $zipName

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Compress-Archive -Path $stageAddonDir -DestinationPath $zipPath -CompressionLevel Optimal

Remove-Item $stageRoot -Recurse -Force

Write-Host "Built $zipPath"
