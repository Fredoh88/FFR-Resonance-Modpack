# FFRS Modpack Live GitHub Sync Script
# Author: Fredoh (aqalfred88@gmail.com)
# Synchronizes live game mods and configurations with this GitHub repository

param(
    [string]$CommitMessage = ""
)

$ErrorActionPreference = "Stop"
$repoDir = "C:\Users\Alfredo\Documents\FFR Modding Tools\FFR-Resonance-Modpack"
$gameModsDir = "D:\SteamLibrary\steamapps\common\FINAL FANTASY RESONANCE\FFRS\Binaries\Win64\ue4ss\Mods"
$engineIniSrc = "C:\Users\Alfredo\AppData\Local\FFRS\Saved\Config\WindowsNoEditor\Engine.ini"

Write-Host "=== FFRS Modpack Sync Starting ===" -ForegroundColor Cyan

# 1. Sync Engine.ini configuration
if (Test-Path $engineIniSrc) {
    Copy-Item $engineIniSrc (Join-Path $repoDir "config\Engine.ini") -Force
    Write-Host "[OK] Synced Engine.ini visual clarity profile" -ForegroundColor Green
}

# 2. Mod names to sync
$activeMods = @(
    "FFR_AI_Optimizer",
    "FFRAutoBattle",
    "CombatTag",
    "LibraScanAll",
    "FFR_EnemyHPNumbers",
    "AutoRestoreHPManaAfterBattle"
)

# 3. Synchronize each mod directory cleanly
foreach ($mod in $activeMods) {
    $srcPath = Join-Path $gameModsDir $mod
    $dstPath = Join-Path $repoDir "mods\$mod"
    
    if (-not (Test-Path $srcPath)) {
        Write-Host "[WARN] Mod folder not found: $srcPath" -ForegroundColor Yellow
        continue
    }

    if (-not (Test-Path $dstPath)) {
        New-Item -ItemType Directory -Force -Path $dstPath | Out-Null
    }

    # Clean copy while filtering out runtime logs, state dumps, and recursive folder artifacts
    $files = Get-ChildItem -Path $srcPath -Recurse -File | Where-Object {
        $_.Extension -notin @(".log", ".tmp") -and
        $_.Name -notin @("battle_log.txt", "state.txt", "AGENT-CHAT.txt") -and
        $_.FullName -notmatch "\\$mod\\$mod\\" -and # skip nested duplicate copies
        $_.Name -notmatch "^__folder_managed"
    }

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($srcPath.Length).TrimStart("\/")
        # Also skip if relative path starts with the mod name as a nested duplicate
        if ($relative -match "^$mod[\\/]") { continue }
        
        $targetFile = Join-Path $dstPath $relative
        $targetDir = Split-Path $targetFile -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }
        Copy-Item $file.FullName $targetFile -Force
    }

    # Ensure enabled.txt exists
    $enabledFile = Join-Path $dstPath "enabled.txt"
    if (-not (Test-Path $enabledFile)) {
        Set-Content -Path $enabledFile -Value "" -Encoding utf8
    }

    Write-Host "[OK] Synced mod: $mod" -ForegroundColor Green
}

# 4. Check git status
Set-Location $repoDir
git status --short

# 5. Commit and push if there are changes
$status = git status --porcelain
if ($status) {
    if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $CommitMessage = "Update modpack files ($timestamp)"
    }
    Write-Host "Staging and committing: $CommitMessage" -ForegroundColor Yellow
    git add -A
    git commit -m "$CommitMessage"
    Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
    git push origin main
    Write-Host "=== Sync complete! Pushed live to GitHub ===" -ForegroundColor Green
} else {
    Write-Host "Repository is already up to date with live mods. No changes to push." -ForegroundColor Cyan
}
