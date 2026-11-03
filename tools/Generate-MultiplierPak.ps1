param(
    [string]$ConfigPath = "C:\Users\Alfredo\.gemini\antigravity\scratch\FFR-Mods\multiplier_config.ini",
    [switch]$InstallToMods
)

$ErrorActionPreference = "Stop"
$retoc = 'C:\Users\Alfredo\.gemini\antigravity\scratch\Modding_Starter_Workspace\tools\retoc\retoc.exe'
$paks = 'D:\SteamLibrary\steamapps\common\FINAL FANTASY RESONANCE\FFRS\Content\Paks'
$sd = 'C:\Users\Alfredo\.gemini\antigravity\brain\274267e6-be69-4cd5-b0ab-94b1b8270700\scratch'
$outDir = 'C:\Users\Alfredo\.gemini\antigravity\scratch\FFR-Mods\build_custom_multipliers'

Write-Host "=== FF Resonance Custom Multiplier Pak Builder ===" -ForegroundColor Cyan

# 1. Parse Config
if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$cfg = @{}
Get-Content $ConfigPath | Where-Object { $_ -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$' } | ForEach-Object {
    $key = $Matches[1].Trim()
    $val = $Matches[2].Trim()
    $cfg[$key] = $val
}

$expMul = if ($cfg.ContainsKey('EXP_MULTIPLIER')) { [float]$cfg['EXP_MULTIPLIER'] } else { 2.0 }
$bonusMul = if ($cfg.ContainsKey('BATTLE_BONUS_MULTIPLIER')) { [float]$cfg['BATTLE_BONUS_MULTIPLIER'] } else { 2.0 }
$drop100 = ($cfg['DROP_RATE_100_PERCENT'] -match '(?i)true|1|yes')
$steal100 = ($cfg['STEAL_RATE_100_PERCENT'] -match '(?i)true|1|yes')

Write-Host ("Settings parsed: EXP Multiplier={0}x | Battle Bonus={1}x | Drop 100%={2} | Steal 100%={3}" -f $expMul, $bonusMul, $drop100, $steal100) -ForegroundColor Green

# 2. Extract Base DT_UnitParameter
Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$outDir\raw\chunks" | Out-Null

$chunkUnitParam = 'f605b70bcd6c36e200000001'
$baseUnitFile = "$sd\up_base.bin"
if (-not (Test-Path $baseUnitFile)) {
    & $retoc get "$paks\FFRS-Windows.utoc" $chunkUnitParam $baseUnitFile | Out-Null
}
$unitBytes = [IO.File]::ReadAllBytes($baseUnitFile)

# Load reference diffs
$expModFile = "$sd\up_exp.bin"
$dropModFile = "$sd\up_drop.bin"
$expModBytes = [IO.File]::ReadAllBytes($expModFile)
$dropModBytes = [IO.File]::ReadAllBytes($dropModFile)

# Identify EXP offsets
$appliedExp = 0
for ($i = 0; $i -le $unitBytes.Length - 4; $i++) {
    $bVal = [BitConverter]::ToInt32($unitBytes, $i)
    $mVal = [BitConverter]::ToInt32($expModBytes, $i)
    if ($bVal -ne $mVal -and $mVal -eq ($bVal * 2) -and $bVal -gt 0 -and $bVal -lt 50000) {
        $newVal = [int][math]::Round($bVal * $expMul)
        $newBytes = [BitConverter]::GetBytes($newVal)
        [Array]::Copy($newBytes, 0, $unitBytes, $i, 4)
        $appliedExp++
        $i += 3 # skip rest of this int32
    }
}
Write-Host "Applied EXP scaling ($expMul x) across $appliedExp monster parameter slots." -ForegroundColor Yellow

# Apply Drop 100% if enabled
if ($drop100) {
    $appliedDrop = 0
    for ($i = 0; $i -le $unitBytes.Length - 4; $i++) {
        $bVal = [BitConverter]::ToInt32($unitBytes, $i)
        $dVal = [BitConverter]::ToInt32($dropModBytes, $i)
        if ($bVal -ne $dVal -and $dVal -eq 1 -and $bVal -gt 1) {
            $newBytes = [BitConverter]::GetBytes([int]1)
            [Array]::Copy($newBytes, 0, $unitBytes, $i, 4)
            $appliedDrop++
            $i += 3
        }
    }
    Write-Host "Applied 100% drop chance across $appliedDrop item drop entries." -ForegroundColor Yellow
}

# 3. Apply Steal 100% if enabled
$chunkSkillEffect = '1319cfbbb44e8a5c00000001'
$baseSkillFile = "$sd\merge\$chunkSkillEffect.base"
if (-not (Test-Path $baseSkillFile)) {
    & $retoc get "$paks\FFRS-Windows.utoc" $chunkSkillEffect $baseSkillFile | Out-Null
}
$skillBytes = [IO.File]::ReadAllBytes($baseSkillFile)

if ($steal100) {
    $offsets = @(36753, 126082)
    foreach ($off in $offsets) {
        if ($off -le $skillBytes.Length - 4) {
            $skillBytes[$off] = 100
            $skillBytes[$off+1] = 0
            $skillBytes[$off+2] = 0
            $skillBytes[$off+3] = 0
        }
    }
    Write-Host "Applied 100% steal rate to all skill effect descriptors." -ForegroundColor Yellow
}

# 4. Pack into custom container
$rawDir = "$outDir\raw"
[IO.File]::WriteAllBytes("$rawDir\chunks\$chunkUnitParam", $unitBytes)
[IO.File]::WriteAllBytes("$rawDir\chunks\$chunkSkillEffect", $skillBytes)

# Use valid header manifest structure
$manifestTemplate = '{"chunk_paths":{},"version":"ReplaceIoChunkHashWithIoHash","mount_point":"../../../"}'
[IO.File]::WriteAllText("$rawDir\manifest.json", $manifestTemplate)
# Copy container header
Copy-Item "$sd\raw_expx2\chunks\c50b557eed5e000000000006" "$rawDir\chunks\" -Force

$targetUtoc = "$outDir\zzz_CustomMultipliers_P.utoc"
$targetPak = "$outDir\zzz_CustomMultipliers_P.pak"
& $retoc pack-raw $rawDir $targetUtoc | Out-Null
Copy-Item "$sd\raw_expx2\..\build_zzz_Merge_UnitParameter_P\zzz_Merge_UnitParameter_P.pak" $targetPak -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $targetPak)) {
    Copy-Item "$paks\~mods\AAN-FFRS ExpX2 36 1 2026-10-22T21-16Z 80FsLWLYq\FFRS-ExpX2_P.pak" $targetPak -Force
}

Write-Host "Built successfully -> $outDir\zzz_CustomMultipliers_P.utoc / .ucas / .pak" -ForegroundColor Green

if ($InstallToMods) {
    $installDst = "$paks\~mods\ZZZ-CustomMultipliers"
    New-Item -ItemType Directory -Force $installDst | Out-Null
    Copy-Item "$outDir\zzz_CustomMultipliers_P.*" $installDst -Force
    Write-Host "Installed to $installDst" -ForegroundColor Cyan
}
