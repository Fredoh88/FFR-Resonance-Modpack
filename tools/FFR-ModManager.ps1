<#
.SYNOPSIS
    FF Resonance Standalone Mod Manager
    Allows managing pak mods and UE4SS script mods without Vortex.

.EXAMPLE
    .\FFR-ModManager.ps1 -Action List
    .\FFR-ModManager.ps1 -Action Backup
    .\FFR-ModManager.ps1 -Action TogglePak -ModName "AAE-Cactuars"
    .\FFR-ModManager.ps1 -Action ToggleScript -ModName "CombatTag" -State 1
    .\FFR-ModManager.ps1 -Action CleanJunk
#>

param(
    [ValidateSet("List", "Backup", "Restore", "TogglePak", "ToggleScript", "CleanJunk")]
    [string]$Action = "List",
    [string]$ModName = "",
    [string]$State = "",
    [string]$BackupName = ""
)

$ErrorActionPreference = "Stop"

$gameDir = "D:\SteamLibrary\steamapps\common\FINAL FANTASY RESONANCE\FFRS"
$paksDir = "$gameDir\Content\Paks\~mods"
$ue4ssDir = "$gameDir\Binaries\Win64\ue4ss"
$modsTxt = "$ue4ssDir\Mods\mods.txt"
$backupBase = "C:\Users\Alfredo\.gemini\antigravity\scratch\FFR-Mods\Backups"

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "     FINAL FANTASY RESONANCE - MOD MANAGER" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

switch ($Action) {
    "List" {
        Write-Host "--- [Pak Mods in Content\Paks\~mods] ---" -ForegroundColor Yellow
        if (Test-Path $paksDir) {
            $folders = Get-ChildItem -Path $paksDir -Directory | Sort-Object Name
            foreach ($f in $folders) {
                $status = if ($f.Name -match '\.disabled$') { "[DISABLED]" } else { "[ENABLED] " }
                $color = if ($f.Name -match '\.disabled$') { "DarkGray" } else { "Green" }
                Write-Host ("  {0} {1}" -f $status, $f.Name) -ForegroundColor $color
            }
        } else {
            Write-Host "  ~mods folder does not exist." -ForegroundColor Red
        }

        Write-Host "`n--- [UE4SS Script Mods in mods.txt] ---" -ForegroundColor Yellow
        if (Test-Path $modsTxt) {
            Get-Content $modsTxt | Where-Object { $_ -match '^\s*([A-Za-z0-9_]+)\s*:\s*([01])' } | ForEach-Object {
                $name = $Matches[1].Trim()
                $val = $Matches[2].Trim()
                $status = if ($val -eq "1") { "[ENABLED] " } else { "[DISABLED]" }
                $color = if ($val -eq "1") { "Green" } else { "DarkGray" }
                Write-Host ("  {0} {1}" -f $status, $name) -ForegroundColor $color
            }
        }
    }

    "Backup" {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd_HHmmss")
        $targetDir = "$backupBase\Backup_$timestamp"
        New-Item -ItemType Directory -Force "$targetDir\Paks" | Out-Null
        New-Item -ItemType Directory -Force "$targetDir\UE4SS" | Out-Null

        Write-Host "Creating backup to: $targetDir ..." -ForegroundColor Cyan
        if (Test-Path $paksDir) {
            Copy-Item -Path "$paksDir\*" -Destination "$targetDir\Paks" -Recurse -Force
        }
        if (Test-Path "$ue4ssDir\Mods") {
            Copy-Item -Path "$ue4ssDir\Mods\*" -Destination "$targetDir\UE4SS" -Recurse -Force
        }
        if (Test-Path "$ue4ssDir\UE4SS-settings.ini") {
            Copy-Item -Path "$ue4ssDir\UE4SS-settings.ini" -Destination "$targetDir\" -Force
        }
        Write-Host "Backup completed successfully!" -ForegroundColor Green
    }

    "TogglePak" {
        if (-not $ModName) { throw "Please specify -ModName" }
        $match = Get-ChildItem -Path $paksDir -Directory | Where-Object { $_.Name -like "*$ModName*" } | Select-Object -First 1
        if (-not $match) {
            Write-Host "No matching pak mod folder found for '$ModName'." -ForegroundColor Red
            return
        }
        if ($match.Name -match '\.disabled$') {
            $newName = $match.Name -replace '\.disabled$', ''
            Rename-Item -Path $match.FullName -NewName $newName
            Write-Host "ENABLED Pak Mod: $newName" -ForegroundColor Green
        } else {
            $newName = $match.Name + ".disabled"
            Rename-Item -Path $match.FullName -NewName $newName
            Write-Host "DISABLED Pak Mod: $newName" -ForegroundColor Yellow
        }
    }

    "ToggleScript" {
        if (-not $ModName) { throw "Please specify -ModName" }
        if (-not (Test-Path $modsTxt)) { throw "mods.txt not found!" }
        $lines = Get-Content $modsTxt
        $updated = $false
        $newLines = @()
        foreach ($line in $lines) {
            if ($line -match "^\s*$([regex]::Escape($ModName))\s*:\s*([01])") {
                $cur = $Matches[1]
                $targetState = if ($State -ne "") { $State } else { if ($cur -eq "1") { "0" } else { "1" } }
                $newLines += "$ModName : $targetState"
                $updated = $true
                Write-Host "Set $ModName to $targetState in mods.txt" -ForegroundColor Green
            } else {
                $newLines += $line
            }
        }
        if (-not $updated) {
            $targetState = if ($State -ne "") { $State } else { "1" }
            $newLines += "$ModName : $targetState"
            Write-Host "Added $ModName : $targetState to mods.txt" -ForegroundColor Green
        }
        [IO.File]::WriteAllLines($modsTxt, $newLines)
    }

    "CleanJunk" {
        Write-Host "Cleaning crash dumps and leftover disabled DLLs..." -ForegroundColor Cyan
        $dumps = Get-ChildItem -Path $ue4ssDir -Filter "*.dmp" -ErrorAction SilentlyContinue
        foreach ($d in $dumps) {
            Remove-Item $d.FullName -Force
            Write-Host "  Removed dump: $($d.Name)" -ForegroundColor Yellow
        }
        $disabledDll = "$gameDir\Binaries\Win64\dxgi.dll.disabled"
        if (Test-Path $disabledDll) {
            Remove-Item $disabledDll -Force
            Write-Host "  Removed dxgi.dll.disabled" -ForegroundColor Yellow
        }
        Write-Host "Cleanup completed!" -ForegroundColor Green
    }
}
Write-Host ""
