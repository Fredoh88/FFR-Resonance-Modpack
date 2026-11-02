# FFRS Modpack Live GitHub Sync Script
# Author: Fredoh (aqalfred88@gmail.com)
# Synchronizes live game mods and configurations with:
# 1. TortilaFury/brotherly-bond (Shared Private Collaboration Repo with Titan)
# 2. Fredoh88/FFR-Resonance-Modpack (Standalone Public Modpack Repo)

param(
    [string]$CommitMessage = ""
)

$ErrorActionPreference = "Stop"
$standaloneRepoDir = "C:\Users\Alfredo\Documents\FFR Modding Tools\FFR-Resonance-Modpack"
$sharedRepoDir     = "C:\Users\Alfredo\Documents\FFR Modding Tools\brotherly-bond"
$sharedModpackDir  = Join-Path $sharedRepoDir "FFR\ResonanceModpack"
$gameModsDir       = "D:\SteamLibrary\steamapps\common\FINAL FANTASY RESONANCE\FFRS\Binaries\Win64\ue4ss\Mods"
$engineIniSrc      = "C:\Users\Alfredo\AppData\Local\FFRS\Saved\Config\WindowsNoEditor\Engine.ini"

Write-Host "=== FFRS Modpack Live Sync Starting ===" -ForegroundColor Cyan

# 1. Sync Engine.ini configuration to standalone repo
if (Test-Path $engineIniSrc) {
    Copy-Item $engineIniSrc (Join-Path $standaloneRepoDir "config\Engine.ini") -Force
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

# 3. Synchronize each mod directory cleanly to standalone repo
foreach ($mod in $activeMods) {
    $srcPath = Join-Path $gameModsDir $mod
    $dstPath = Join-Path $standaloneRepoDir "mods\$mod"
    
    if (-not (Test-Path $srcPath)) {
        Write-Host "[WARN] Mod folder not found: $srcPath" -ForegroundColor Yellow
        continue
    }

    if (-not (Test-Path $dstPath)) {
        New-Item -ItemType Directory -Force -Path $dstPath | Out-Null
    }

    $files = Get-ChildItem -Path $srcPath -Recurse -File | Where-Object {
        $_.Extension -notin @(".log", ".tmp") -and
        $_.Name -notin @("battle_log.txt", "state.txt", "AGENT-CHAT.txt") -and
        $_.FullName -notmatch "\\$mod\\$mod\\" -and
        $_.Name -notmatch "^__folder_managed"
    }

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($srcPath.Length).TrimStart("\/")
        if ($relative -match "^$mod[\\/]") { continue }
        
        $targetFile = Join-Path $dstPath $relative
        $targetDir = Split-Path $targetFile -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }
        Copy-Item $file.FullName $targetFile -Force
    }

    $enabledFile = Join-Path $dstPath "enabled.txt"
    if (-not (Test-Path $enabledFile)) {
        Set-Content -Path $enabledFile -Value "" -Encoding utf8
    }

    Write-Host "[OK] Synced mod: $mod" -ForegroundColor Green
}

# 4. Mirror all files to shared brotherly-bond repository
if (Test-Path $sharedRepoDir) {
    if (-not (Test-Path $sharedModpackDir)) {
        New-Item -ItemType Directory -Force -Path $sharedModpackDir | Out-Null
    }
    Get-ChildItem -Path $standaloneRepoDir -Exclude ".git" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $sharedModpackDir -Recurse -Force
    }
    Write-Host "[OK] Mirrored files to shared brotherly-bond/FFR/ResonanceModpack" -ForegroundColor Green
}

# 5. Push to Standalone Repo (Fredoh88/FFR-Resonance-Modpack)
Set-Location $standaloneRepoDir
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $CommitMessage = "Update modpack files ($timestamp)"
}

$status1 = git status --porcelain
if ($status1) {
    Write-Host "Pusshing updates to Fredoh88/FFR-Resonance-Modpack..." -ForegroundColor Cyan
    git add -A
    git commit -m "$CommitMessage"
    git push origin main
}

# 6. Push to Shared Collaboration Repo (TortilaFury/brotherly-bond)
if (Test-Path $sharedRepoDir) {
    Set-Location $sharedRepoDir
    $status2 = git status --porcelain
    if ($status2) {
        Write-Host "Pushing updates to shared TortilaFury/brotherly-bond..." -ForegroundColor Cyan
        git add -A
        git commit -m "$CommitMessage"
        git pull --rebase origin main
        git push origin main
        Write-Host "[OK] Pushed live to TortilaFury/brotherly-bond!" -ForegroundColor Green
    }
}

Write-Host "=== Sync complete across all repositories! ===" -ForegroundColor Green
