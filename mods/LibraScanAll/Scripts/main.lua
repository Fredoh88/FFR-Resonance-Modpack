--[[----------------------------------------------------------------------------
    LibraScanAll v1.3.1 -- FINAL FANTASY RESONANCE (UE 5.6, UE4SS 3.0.1 experimental)

    Libra, Analyze and Mecha Mogscan scan ONE enemy in vanilla. This mod makes
    them scan EVERY enemy on the field.

    HOW
      Skill targeting is data: each row of the skill DataTable (row struct
      SKILL_DATA) has TargetType (eSkillTargetType: 1 Single ... 4 All).
      Scan skills are rows whose skillEffectType is a scan effect
      (eSkillEffectType 29 Analyze, 142 MechaMogscan) -- or, optionally, rows
      that carry a scan effect in effectBundleList (effect ids resolved through
      the SKILL_EFFECT_DATA table).
      The mod sets TargetType to All on those rows, in memory, once the tables
      are loaded. The game's own Analyze / Mogscan code then runs on every
      target, so the save flags (bestiary "analyzed"), the Libra window and
      element reveals all work exactly as vanilla, just for all enemies.
      Items that cast these skills (via their SkillId) are covered too.

    DETAIL NUMBERS (details.lua, optional)
      Drop/steal chances and ailment resistances on the Libra detail screen,
      based on FFR_LibraPlus ("Libra Plus").

    SAFETY
      * Nothing is written to disk or to your save. Only the in-memory copy of
        the skill table changes; remove the mod and restart to undo.
      * Everything runs on the game thread (LoopInGameThreadWithDelay).
    ----------------------------------------------------------------------------]]

local MOD = "LibraScanAll"
local VERSION = "1.3.1"

-- Settings. Read through applyConfig so the reload key (F7) can re-apply them.
local CONFIG, SCAN, NEW_TARGET, FROM, MIXED, SKIP_FRIENDLY, LOG_EACH
local MULTI_FOCUS, SAMPLES, BATTLE_LOG, DETAILS, RELOAD_KEY, SOUND
local function readConfig()
    package.loaded["config"] = nil
    local ok, c = pcall(require, "config")
    return (ok and type(c) == "table") and c or {}, ok and type(c) == "table"
end
local function applyConfig(c)
    CONFIG     = c
    SCAN       = c.SCAN_EFFECT_TYPES or { [29] = true, [142] = true }
    NEW_TARGET = c.NEW_TARGET_TYPE or 2
    FROM       = c.RETARGET_FROM or { [1] = true, [3] = true, [5] = true, [7] = true }
    MIXED      = c.INCLUDE_MIXED_SKILLS ~= false
    SKIP_FRIENDLY = c.SKIP_FRIENDLY_TARGETED ~= false
    LOG_EACH   = c.LOG_EACH_SKILL ~= false
    MULTI_FOCUS = c.ALLOW_MULTI_FOCUS ~= false
    SAMPLES    = c.LOG_TARGET_TYPE_SAMPLES ~= false
    BATTLE_LOG = c.LOG_BATTLE_SCAN ~= false
    DETAILS    = c.SHOW_DETAIL_NUMBERS ~= false
    RELOAD_KEY = (c.RELOAD_KEY == nil and "F7") or (type(c.RELOAD_KEY) == "string" and c.RELOAD_KEY) or nil
    SOUND      = (c.RELOAD_SOUND == nil and "Sound.UI.Battle.Cmd.LimitBurstList.Open")
                 or (type(c.RELOAD_SOUND) == "string" and c.RELOAD_SOUND) or nil
end
applyConfig((readConfig()))

local FAST_MS, SLOW_MS = 2000, 15000
local RELATION_FRIENDLIES = 1

-- enum names, for builds that hand rows to Lua as plain tables with enum strings
local TARGET_NAMES = { Self = 0, Single = 1, Group = 2, Spread = 3, All = 4, Random = 5,
                       SkillTarget = 6, SingleAndGroup = 7 }
local EFFECT_NAMES = { Analyze = 29, MechaMogscan = 142 }
local RELATION_NAMES = { None = 0, Friendlies = 1, Enemies = 2, All = 3 }

local function say(fmt, ...)
    print(string.format("[%s] " .. fmt .. "\n", MOD, ...))
end
local logged = {}
local function sayOnce(key, fmt, ...)
    if logged[key] then return end
    logged[key] = true
    say(fmt, ...)
end

if type(LoopInGameThreadWithDelay) ~= "function" then
    say("ERROR: needs the UE4SS EXPERIMENTAL build (LoopInGameThreadWithDelay missing). Mod inactive.")
    return
end

---------------------------------------------------------------------------- helpers
local function str(v)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == "string" then return s end
    return tostring(v)
end

-- enum value as integer, whatever form the binding returns
local function enum(v, names)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber(v)
        if n then return n end
        local tail = v:match("::(%w+)$") or v
        return names and names[tail] or nil
    end
    return nil
end

local function field(row, name)
    local ok, v = pcall(function() return row[name] end)
    if ok then return v end
    return nil
end

local function setField(row, name, value)
    return pcall(function() row[name] = value end)
end

-- iterate a TArray userdata or a Lua array; fn(index, element)
local function each(arr, fn)
    if arr == nil then return end
    if type(arr) == "table" then
        for i, v in ipairs(arr) do fn(i, v) end
        return
    end
    local okN, n = pcall(function() return #arr end)
    if not okN or type(n) ~= "number" then return end
    for i = 1, n do
        local okE, e = pcall(function() return arr[i] end)
        if okE and e ~= nil then fn(i, e) end
    end
end

local function hasMethod(obj, name)
    local ok, m = pcall(function() return obj[name] end)
    return ok and (type(m) == "function" or (type(m) == "userdata" and getmetatable(m) and getmetatable(m).__call ~= nil))
end

local function valid(o)
    if type(o) ~= "userdata" and type(o) ~= "table" then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end

local function fullName(o)
    local ok, s = pcall(function() return o:GetFullName() end)
    return ok and s or "?"
end

local function rowStructName(dt)
    local ok, n = pcall(function() return dt:GetRowStruct():GetFName():ToString() end)
    return ok and n or nil
end

-- calls fn(rowName, row) for every row; row may be a live struct (userdata) or a copy (table)
local function forEachRow(dt, fn)
    if hasMethod(dt, "ForEachRow") then
        local ok, err = pcall(function()
            dt:ForEachRow(function(name, row) fn(str(name), row) end)
        end)
        if ok then return true end
        sayOnce("fer", "ForEachRow failed (%s), trying GetAllRows", tostring(err))
    end
    if hasMethod(dt, "GetAllRows") then
        local ok, all = pcall(function() return dt:GetAllRows() end)
        if ok and type(all) == "table" then
            for k, v in pairs(all) do
                if type(v) == "table" and v.Name ~= nil and v.Data ~= nil then fn(str(v.Name), v.Data)
                else fn(str(k), v) end
            end
            return true
        end
    end
    sayOnce("noapi", "ERROR: this UE4SS build has no Lua DataTable API (ForEachRow/GetAllRows). Mod inactive.")
    return false
end

---------------------------------------------------------------------------- effect table
local effectType = {}       -- effect id -> eSkillEffectType
local effectTables = {}     -- full name -> true

local function readEffectTable(dt, name)
    local n = 0
    forEachRow(dt, function(_, row)
        local id = tonumber(field(row, "ID"))
        local t = enum(field(row, "EffectType"), EFFECT_NAMES)
        if id and t then effectType[id] = t; n = n + 1 end
    end)
    effectTables[name] = true
    say("read effect table %s (%d effects)", name, n)
end

---------------------------------------------------------------------------- skill table
local done = {}             -- "<table>|<row>" -> true (patched or decided to skip)
local stats = { patched = 0, already = 0, mixedSkipped = 0, failed = 0 }
local replaceMode = nil     -- nil = untested, true = AddRow replacement works, false = broken

-- Which scan skill a row is: "LIBRA" (Analyze effect, 29) or "MECHAMOG" (MechaMogscan, 142).
local KIND_OF_EFFECT = { [29] = "LIBRA", [142] = "MECHAMOG" }
local function scanInfo(row)
    local primaryType = enum(field(row, "skillEffectType"), EFFECT_NAMES) or -1
    local primary = SCAN[primaryType] == true
    local kind = primary and KIND_OF_EFFECT[primaryType] or nil
    local bundleScan = false
    each(field(row, "effectBundleList"), function(_, b)
        local id = tonumber(field(b, "effectId"))
        local t = id and effectType[id]
        if t and SCAN[t] then
            bundleScan = true
            kind = kind or KIND_OF_EFFECT[t]
        end
    end)
    return primary, bundleScan, kind or "OTHER"
end

-- per-skill settings: SKILLS.LIBRA / SKILLS.MECHAMOG / SKILLS.OTHER (custom scan effects)
local function skillCfg(kind)
    local c = (CONFIG.SKILLS or {})[kind] or {}
    return {
        all  = c.ALL_TARGETS ~= false,
        cost = tonumber(c.MP_COST),            -- nil = leave the game's cost alone
    }
end

-- the changes wanted for a row: { TargetType = n?, Cost = n?, bundles = bool }
local function wanted(row, cfg)
    local w, any = {}, false
    local before = enum(field(row, "TargetType"), TARGET_NAMES)
    if cfg.all and before ~= nil and before ~= NEW_TARGET and FROM[before] then
        w.TargetType = NEW_TARGET; w.bundles = true; any = true
    end
    local cost = tonumber(field(row, "Cost"))
    if cfg.cost and cost ~= nil and cost ~= cfg.cost then w.Cost = cfg.cost; any = true end
    return any and w or nil, before, cost
end

-- applies the change to a row object (live or copy)
local function applyTo(row, w)
    if w.TargetType then setField(row, "TargetType", w.TargetType) end
    if w.Cost then setField(row, "Cost", w.Cost) end
    if w.bundles then
        each(field(row, "effectBundleList"), function(_, b)
            local id = tonumber(field(b, "effectId"))
            local bt = enum(field(b, "TargetType"), TARGET_NAMES)
            if id and SCAN[effectType[id] or -1] and bt and FROM[bt] then
                setField(b, "TargetType", w.TargetType)
            end
        end)
    end
end

-- current values of the fields we change, read through FindRow when possible
local function current(dt, rowName, fallbackRow)
    local r = fallbackRow
    if hasMethod(dt, "FindRow") then
        local ok, x = pcall(function() return dt:FindRow(rowName) end)
        if ok and x ~= nil then r = x end
    end
    return { TargetType = enum(field(r, "TargetType"), TARGET_NAMES), Cost = tonumber(field(r, "Cost")) }, r
end
local function matches(cur, w)
    return (w.TargetType == nil or cur.TargetType == w.TargetType) and (w.Cost == nil or cur.Cost == w.Cost)
end

-- Writes a change: in place on the row we were handed, then on the row FindRow
-- returns, then (if the binding hands out copies) by replacing the row with AddRow.
-- mut(rowObject) applies the change, check(cur) says whether it is in the table.
local function writeRow(dt, rowName, row, skillName, mut, check)
    mut(row)
    local cur, live = current(dt, rowName, row)
    if not check(cur) and live ~= nil and live ~= row then
        mut(live)
        cur = current(dt, rowName, row)
    end
    if not check(cur) and replaceMode ~= false and hasMethod(dt, "AddRow") then
        local ok, copy = pcall(function() return dt:FindRow(rowName) end)
        if ok and copy ~= nil then
            mut(copy)
            local okA, errA = pcall(function() dt:AddRow(rowName, copy) end)
            local after, chk = current(dt, rowName, row)
            local sameName = str(field(chk, "Name")) == skillName
            if okA and check(after) and sameName then
                replaceMode = true
                cur = after
            else
                replaceMode = false
                say("WARNING: row replacement does not round-trip on this build (%s); stopped using it.",
                    okA and ("name now '" .. str(field(chk, "Name")) .. "'") or tostring(errA))
            end
        end
    end
    return cur, check(cur)
end

-- original values of every row this mod changed, so a reload can put them back
local orig = {}             -- key -> { dt, rowName, name, TargetType, Cost, bundles = { [i] = TargetType } }
local function remember(key, dt, rowName, row, skillName, before, costBefore)
    if orig[key] then return end
    local b = {}
    each(field(row, "effectBundleList"), function(i, x) b[i] = enum(field(x, "TargetType"), TARGET_NAMES) end)
    orig[key] = { dt = dt, rowName = rowName, name = skillName, TargetType = before, Cost = costBefore, bundles = b }
end

-- MP cost overrides: SKILL_GENERAL_DATA.costOverrideData holds { SkillId, costType, Cost }
-- entries that replace a skill's own Cost (v1.3.0 changed only SKILL_DATA.Cost, and Libra
-- still cost 1 MP in game). costType 0 = MP.
local generalTable = nil
local ovOrig = {}           -- { rowName, index, Cost }
local function patchOverrides(skillId, newCost, label)
    if not (generalTable and valid(generalTable)) then
        sayOnce("nogeneral", "MP cost: SKILL_GENERAL_DATA table not found yet (overrides not checked)")
        return 0
    end
    local n = 0
    forEachRow(generalTable, function(rowName, row)
        each(field(row, "costOverrideData"), function(i, e)
            if tonumber(field(e, "SkillId")) == skillId and (enum(field(e, "costType"), {}) or 0) == 0 then
                local before = tonumber(field(e, "Cost"))
                if before ~= newCost then
                    ovOrig[#ovOrig + 1] = { rowName = rowName, index = i, Cost = before }
                    setField(e, "Cost", newCost)
                    local after = tonumber(field(e, "Cost"))
                    say("%s: MP cost override %s -> %s%s", label, tostring(before), tostring(after),
                        after == newCost and "" or " (FAILED: this build hands out copies)")
                    n = n + 1
                end
            end
        end)
    end)
    return n
end
local function restoreOverrides()
    if not (generalTable and valid(generalTable)) then ovOrig = {}; return 0 end
    local n = 0
    for _, o in ipairs(ovOrig) do
        pcall(function()
            local row = generalTable:FindRow(o.rowName)
            local e = row.costOverrideData[o.index]
            setField(e, "Cost", o.Cost); n = n + 1
        end)
    end
    ovOrig = {}
    return n
end

local function patchRow(dt, tableName, rowName, row)
    local key = tableName .. "|" .. rowName
    if done[key] then return end

    local primary, bundleScan, kind = scanInfo(row)
    if not primary and not bundleScan then return end            -- not a scan skill
    local skillName = str(field(row, "Name"))
    if not primary and not MIXED then
        done[key] = true
        stats.mixedSkipped = stats.mixedSkipped + 1
        if LOG_EACH then say("skipped %s '%s' (scan is an added effect; INCLUDE_MIXED_SKILLS=false)", rowName, skillName) end
        return
    end
    local rel = enum(field(row, "defaultTargetRelation"), RELATION_NAMES)
    if SKIP_FRIENDLY and rel == RELATION_FRIENDLIES then done[key] = true; return end

    local cfg = skillCfg(kind)
    local w, before, costBefore = wanted(row, cfg)
    if cfg.cost then
        local id = tonumber(field(row, "ID"))
        local nOv = id and patchOverrides(id, cfg.cost, string.format("%s '%s'", rowName, skillName)) or 0
        if LOG_EACH then
            say("%s '%s' [%s]: MP_COST %d wanted; skill Cost field reads %s; %d override(s) changed",
                rowName, skillName, kind, cfg.cost, tostring(costBefore), nOv)
        end
    end
    if not w then
        done[key] = true
        if before == NEW_TARGET then stats.already = stats.already + 1 end
        if LOG_EACH then
            say("%s '%s' [%s]: nothing to change (target %s, cost %s%s)", rowName, skillName, kind,
                tostring(before), tostring(costBefore), cfg.all and "" or ", ALL_TARGETS off")
        end
        return
    end

    remember(key, dt, rowName, row, skillName, before, costBefore)
    local cur = writeRow(dt, rowName, row, skillName,
        function(r) applyTo(r, w) end,
        function(c) return matches(c, w) end)

    done[key] = true
    if matches(cur, w) then
        stats.patched = stats.patched + 1
        if LOG_EACH then
            local dmg = enum(field(row, "DamageType"), { None = 0, Physic = 1, Magic = 2 })
            local parts = {}
            if w.TargetType then parts[#parts + 1] = string.format("target %d -> %d", before, w.TargetType) end
            if w.Cost then parts[#parts + 1] = string.format("cost %s -> %d", tostring(costBefore), w.Cost) end
            say("%s '%s' [%s]: %s (main effect %s, deals damage: %s)", rowName, skillName, kind,
                table.concat(parts, ", "), tostring(enum(field(row, "skillEffectType"), EFFECT_NAMES)),
                (dmg and dmg ~= 0) and "yes" or "no")
        end
    else
        stats.failed = stats.failed + 1
        say("FAILED to change %s '%s' (target %s, cost %s)", rowName, skillName, tostring(cur.TargetType), tostring(cur.Cost))
    end
end

local skillTables = {}      -- full name -> true

local sampled = false
local function logSamples(dt)
    if sampled or not SAMPLES then return end
    sampled = true
    local by = {}
    forEachRow(dt, function(rowName, row)
        if enum(field(row, "defaultTargetRelation"), RELATION_NAMES) ~= 2 then return end
        local t = enum(field(row, "TargetType"), TARGET_NAMES)
        if t == nil then return end
        by[t] = by[t] or { n = 0, names = {} }
        by[t].n = by[t].n + 1
        local nm = str(field(row, "Name"))
        if #by[t].names < 8 and nm ~= "" then by[t].names[#by[t].names + 1] = nm end
    end)
    for t = 0, 7 do
        if by[t] then say("enemy-targeted skills with target type %d: %d (e.g. %s)", t, by[t].n, table.concat(by[t].names, ", ")) end
    end
end

local function patchSkillTable(dt, name)
    logSamples(dt)
    local first = not skillTables[name]
    skillTables[name] = true
    local p0, f0 = stats.patched, stats.failed
    forEachRow(dt, function(rowName, row) patchRow(dt, name, rowName, row) end)
    if first or stats.patched ~= p0 or stats.failed ~= f0 then
        say("skill table %s: %d changed, %d already all-target, %d mixed skipped, %d failed (totals)",
            name, stats.patched, stats.already, stats.mixedSkipped, stats.failed)
    end
end

---------------------------------------------------------------------------- loop
local seen = {}             -- data table full name -> row struct name
local lastEffectCount = 0

-- The Libra info window (VM_BtlLibra) reads its options from CPP_DA_BtlLibra.
-- bIsAllowMultiUnitFocus lets it handle several focused units at once, which an
-- all-enemy scan produces. Checked every pass: the asset may load only in battle.
local daChanged = {}        -- Libra window data assets this mod switched on
local function fixLibraWindow()
    for _, da in ipairs(FindAllOf("CPP_DA_BtlLibra") or {}) do
        if valid(da) and not fullName(da):find("Default__", 1, true) then
            local ok, cur = pcall(function() return da.bIsAllowMultiUnitFocus end)
            if ok and cur == false and setField(da, "bIsAllowMultiUnitFocus", true) then
                daChanged[fullName(da)] = true
                say("Libra window: multi-unit focus enabled (%s)", fullName(da))
            end
        end
    end
end

-- Reload: put every changed skill back to its original values, forget what was done,
-- and let the next pass apply the new settings from config.lua.
local function restoreAll()
    local n, bad = 0, 0
    for key, o in pairs(orig) do
        local ok = pcall(function()
            local row = o.dt:FindRow(o.rowName)
            local mut = function(r)
                if o.TargetType then setField(r, "TargetType", o.TargetType) end
                if o.Cost then setField(r, "Cost", o.Cost) end
                each(field(r, "effectBundleList"), function(i, x)
                    if o.bundles[i] then setField(x, "TargetType", o.bundles[i]) end
                end)
            end
            local _, done2 = writeRow(o.dt, o.rowName, row, o.name, mut, function(c)
                return (o.TargetType == nil or c.TargetType == o.TargetType) and (o.Cost == nil or c.Cost == o.Cost)
            end)
            if not done2 then error("not restored") end
        end)
        if ok then n = n + 1 else bad = bad + 1 end
    end
    orig = {}
    n = n + restoreOverrides()
    return n, bad
end

-- Battle check: "Goblin A yes, Goblin B no ..." logged when it changes.
local lastBattle = ""
local function battleReport()
    local parts, nEnemy, nScanned = {}, 0, 0
    for _, u in ipairs(FindAllOf("CPP_BtlUnit") or {}) do
        if valid(u) and not fullName(u):find("Default__", 1, true) then
            local okP, p = pcall(function() return u:GetUnitParameter() end)
            if okP and valid(p) then
                local rel = select(2, pcall(function() return p:GetRelation() end))
                rel = enum(rel, RELATION_NAMES)
                local dead = select(2, pcall(function() return p:IsDead() end)) == true
                if rel == 2 and not dead then
                    local an = select(2, pcall(function() return p:IsAnalyzed() end)) == true
                    local nm = str(select(2, pcall(function() return p:GetUnitName() end)))
                    nEnemy = nEnemy + 1
                    if an then nScanned = nScanned + 1 end
                    parts[#parts + 1] = nm .. (an and " yes" or " no")
                end
            end
        end
    end
    local line = nEnemy == 0 and "" or string.format("battle: %d/%d enemies analyzed (%s)", nScanned, nEnemy, table.concat(parts, ", "))
    if line ~= lastBattle then
        lastBattle = line
        if line ~= "" then say("%s", line) end
    end
end

local function tick()
    local tables = FindAllOf("DataTable") or {}
    local skills = {}
    for _, dt in ipairs(tables) do
        if valid(dt) then
            local name = fullName(dt)
            if not name:find("Default__", 1, true) then
                local rs = seen[name]
                if rs == nil then rs = rowStructName(dt) or ""; seen[name] = rs end
                if rs == "SKILL_EFFECT_DATA" and not effectTables[name] then
                    readEffectTable(dt, name)
                elseif rs == "SKILL_DATA" then
                    skills[#skills + 1] = { dt = dt, name = name }
                elseif rs == "SKILL_GENERAL_DATA" then
                    generalTable = dt
                end
            end
        end
    end
    -- effect ids learned since last pass: re-check rows we skipped as "not a scan skill"
    local nEff = 0
    for _ in pairs(effectType) do nEff = nEff + 1 end
    local newEffects = nEff ~= lastEffectCount
    lastEffectCount = nEff
    for _, s in ipairs(skills) do
        if newEffects or not skillTables[s.name] then patchSkillTable(s.dt, s.name) end
    end
    return #skills > 0
end

say("v%s loaded (scan effects -> target type %d; mixed skills %s; detail numbers %s%s)", VERSION, NEW_TARGET,
    MIXED and "on" or "off", DETAILS and "on" or "off", RELOAD_KEY and ("; reload key " .. RELOAD_KEY) or "")

-- Libra detail screen numbers (details.lua), own 150 ms game-thread timer. Loaded even
-- when switched off, so the reload key can turn it on.
local D = nil
do
    local okD, mod = pcall(require, "details")
    if okD and type(mod) == "table" and mod.init(CONFIG.DETAILS, say, sayOnce) then
        D = mod
        LoopInGameThreadWithDelay(150, function()
            if not DETAILS then return end
            local ok, err = pcall(D.tick)
            if not ok then sayOnce("dt:" .. tostring(err), "detail numbers error: %s", tostring(err)) end
        end)
    elseif not okD then
        say("detail numbers module failed to load: %s", tostring(mod))
    end
end

local nextAt = 0
local function reload()
    local c, ok = readConfig()
    if not ok then say("reload: config.lua could not be read; keeping the current settings"); return end
    local n, bad = restoreAll()
    applyConfig(c)
    done, skillTables = {}, {}
    stats = { patched = 0, already = 0, mixedSkipped = 0, failed = 0 }
    nextAt = 0                                   -- re-patch on the next pass
    if not MULTI_FOCUS then
        for _, da in ipairs(FindAllOf("CPP_DA_BtlLibra") or {}) do
            if valid(da) and daChanged[fullName(da)] then setField(da, "bIsAllowMultiUnitFocus", false) end
        end
        daChanged = {}
    end
    if D then D.reload(CONFIG.DETAILS) end
    say("settings reloaded: %d skill(s) restored%s, new settings apply now (detail numbers %s)",
        n, bad > 0 and string.format(", %d FAILED to restore", bad) or "", DETAILS and "on" or "off")
    if SOUND then
        pcall(function()
            local snd = StaticFindObject("/Script/mucha.Default__CPP_BFL_Sound")
            if valid(snd) then snd:PlaySound2DByTag({ TagName = FName(SOUND) }) end
        end)
    end
end

-- Reload key, read on the game thread. The game can have several player controllers
-- that answer in turns (v1.3.0: one F7 press reloaded ~8 times), so the key counts as
-- down if ANY controller says so, and it must be released for 3 polls before it fires again.
local key = { armed = true, up = 0 }
local function anyKeyDown(name)
    local down = false
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        local okN, nm = pcall(function() return pc:GetFName():ToString() end)
        if okN and type(nm) == "string" and not nm:find("Default__", 1, true) then
            local okK, d = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(name) }) end)
            if okK and d == true then down = true end
        end
    end
    return down
end
LoopInGameThreadWithDelay(50, function()
    if not RELOAD_KEY then return end
    local ok, down = pcall(anyKeyDown, RELOAD_KEY)
    if not ok then return end
    if down then
        key.up = 0
        if key.armed then key.armed = false; reload() end
    else
        key.up = key.up + 1
        if key.up >= 3 then key.armed = true end
    end
end)

local found, warned = false, false
local elapsed = 0
LoopInGameThreadWithDelay(FAST_MS, function()
    elapsed = elapsed + FAST_MS
    if MULTI_FOCUS then
        local okF, errF = pcall(fixLibraWindow)
        if not okF then sayOnce("da:" .. tostring(errF), "Libra window fix error: %s", tostring(errF)) end
    end
    if BATTLE_LOG then
        local okB, errB = pcall(battleReport)
        if not okB then sayOnce("bt:" .. tostring(errB), "battle check error: %s", tostring(errB)) end
    end
    if elapsed < nextAt then return end
    local ok, r = pcall(tick)
    if not ok then
        sayOnce("tick:" .. tostring(r), "error: %s", tostring(r))
    else
        found = found or r
        if not found and not warned and elapsed > 600000 then
            warned = true
            say("no SKILL_DATA table found after 10 minutes; please report with UE4SS.log")
        end
    end
    nextAt = elapsed + (found and SLOW_MS or 0)
end)
