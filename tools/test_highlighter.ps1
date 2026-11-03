param(
    [string]$ScriptPath = "D:\SteamLibrary\steamapps\common\FINAL FANTASY RESONANCE\FFRS\Binaries\Win64\ue4ss\Mods\FFRAutoBattle\Scripts\highlighter.lua"
)

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "    FFRAutoBattle - Highlighter.lua Test Harness" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

$passed = 0
$failed = 0

function Assert-Test([string]$desc, [bool]$condition, [string]$details = "") {
    if ($condition) {
        Write-Host "  [PASS] $desc" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $desc $details" -ForegroundColor Red
        $script:failed++
    }
}

# 1. File existence & encoding
Assert-Test "File exists" (Test-Path $ScriptPath)
$bytes = [IO.File]::ReadAllBytes($ScriptPath)
Assert-Test "No UTF-8 BOM" ($bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF)

$text = [Text.Encoding]::UTF8.GetString($bytes)
$bareLf = ([regex]::Matches($text, '(?<!\r)\n')).Count
Assert-Test "Consistent Windows CRLF line endings" ($bareLf -eq 0) ("(bare LF count: $bareLf)")

# 2. Block balance check
$code = [regex]::Replace($text, '--[^\n]*', '') # strip comments
$code = [regex]::Replace($code, '"(?:[^"\\\n]|\\.)*"', '""') # strip string literals
$code = [regex]::Replace($code, "'(?:[^'\\\n]|\\.)*'", "''")

$opens = ([regex]::Matches($code, '\b(function|if|for|while|do)\b')).Count - 
         ([regex]::Matches($code, '\bfor\b[^\n]*\bdo\b')).Count - 
         ([regex]::Matches($code, '\bwhile\b[^\n]*\bdo\b')).Count
$ends = ([regex]::Matches($code, '\bend\b')).Count
Assert-Test "Lua block structures balanced" ($opens -eq $ends) ("(openers: $opens vs ends: $ends)")

# 3. Accessory Slot Configuration & Keywords
Assert-Test "ACC_SLOTS is defined" ($text -match '\bACC_SLOTS\s*=\s*4\b')
$accWords = @("ring", "bangle", "belt", "earring", "ribbon", "rosary", "pendant", "amulet", "bracer", "boots", "sandals", "wrist", "vest", "safety bit")
$foundWords = 0
foreach ($w in $accWords) {
    if ($text -match [regex]::Escape($w)) { $foundWords++ }
}
Assert-Test "All standard accessory keywords covered" ($foundWords -eq $accWords.Count) ("($foundWords / $($accWords.Count) found)")

# 4. Roster coverage
$roster = @("Rain", "Lasswell", "Fina", "Lid", "Nichol", "Jake", "Sakura")
$foundChars = 0
foreach ($c in $roster) {
    if ($text -match '\["' + $c + '"\]\s*=' -or $text -match "\['" + $c + "'\]\s*=") { $foundChars++ }
}
Assert-Test "All main party members defined in CHAR_PROFILES" ($foundChars -eq $roster.Count) ("($foundChars / $($roster.Count) found)")

# 5. Role coverage
$roles = @("Sentinel", "Breaker", "Luminary", "Mechanist", "Saboteur", "Sage", "Tactician", "Corsair")
$foundRoles = 0
foreach ($r in $roles) {
    if ($text -match 'role\s*==\s*"' + $r + '"') { $foundRoles++ }
}
Assert-Test "All 8 combat archetypes supported" ($foundRoles -eq $roles.Count) ("($foundRoles / $($roles.Count) found)")

# 6. Two-pass slot budgeting loop integrity
Assert-Test "Pass 1 candidates and equipped collection exists" ($text -match 'seenCand\[base\]' -and $text -match 'equippedAccScores')
Assert-Test "Pass 2 floor scoring and slot limit filter exists" ($text -match 'free\s*=\s*ACC_SLOTS' -and $text -match 'floorScore')
Assert-Test "Pass 3 row update respects allowed slots" ($text -match 'row\.isAcc\s+and\s+rec\s+and\s+not\s+allowed\[row\.base\]')

Write-Host "`n-------------------------------------------------------" -ForegroundColor Cyan
Write-Host ("Tests Passed: {0} | Tests Failed: {1}" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "=======================================================`n" -ForegroundColor Cyan
