-- FFR:AutoBattle. One auto-battle switch. One planner for the round, from the
-- design doc: score every enemy, chip the gauges, finish them together.
-- The characters carry out the next slot. Claims stop a second heal, a second
-- buff, or a second Ether in the same round.
-- F10 is on/off and flashes AutoBattle On or Off.
-- F9 is on/off. On flashes AutoBattle: Take it Easy! Off flashes
-- AutoBattle: No Mercy! On is Attack only:
-- no MP and no items. Off is the default. Both choices are remembered.
-- In a fight, the right trigger fires the F10 action and the left trigger
-- fires the F9 action. Outside a fight the triggers stay with the game.
--
-- known.lua is the skill book. mobs.lua is the enemy book. Saves and pak files
-- are not touched. The command goes out through Delegate.Battle.Cmd.Decide.

local TAG = "[FFRAutoBattle] "
local function log(fmt, ...)
    if select("#", ...) == 0 then
        print(TAG .. tostring(fmt) .. "\n")
        return
    end
    print(TAG .. string.format(fmt, ...) .. "\n")
end

local HAS_GAME_TIMERS = (LoopInGameThreadWithDelay ~= nil) and (ExecuteInGameThreadWithDelay ~= nil)
local function gameLoop(ms, fn)
    local function safe()
        local ok, err = pcall(fn)
        if not ok then log("timer error: %s", tostring(err)) end
    end
    if HAS_GAME_TIMERS then
        return LoopInGameThreadWithDelay(ms, safe)
    end
    LoopAsync(ms, function()
        ExecuteInGameThread(safe)
        return false
    end)
end
local function gameDelay(ms, fn)
    local function safe()
        local ok, err = pcall(fn)
        if not ok then log("timer error: %s", tostring(err)) end
    end
    if HAS_GAME_TIMERS then
        return ExecuteInGameThreadWithDelay(ms, safe)
    end
    ExecuteWithDelay(ms, function() ExecuteInGameThread(safe) end)
end

local function modDir()
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local src = ((info and info.source) or ""):gsub("^@", ""):gsub("\\", "/")
    return src:match("^(.*)/Scripts/[^/]+$") or "ue4ss/Mods/FFRAutoBattle"
end
local DIR = modDir()
local Known = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/known.lua")
    if ok and type(loaded) == "table" then
        Known = loaded
    else
        log("known list unavailable: %s", tostring(loaded))
    end
    -- Names already in known.lua keep their stagger and use. The catalog only fills gaps.
    local catOk, catalog = pcall(dofile, DIR .. "/Scripts/catalog.lua")
    if catOk and type(catalog) == "table" and type(catalog.skills) == "table" and type(Known.skills) == "table" then
        local added = 0
        for name, row in pairs(catalog.skills) do
            if Known.skills[name] == nil and type(row) == "table" then
                Known.skills[name] = row
                added = added + 1
            end
        end
        log("catalog %d added", added)
    elseif not catOk then
        log("catalog unavailable: %s", tostring(catalog))
    end
end
local function knownOf(skill)
    local map = Known.skills
    if not map or not skill or not skill.name then return nil end
    local key = skill.name:lower()
    key = key:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    return map[key]
end
local Mobs = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/mobs.lua")
    if ok and type(loaded) == "table" then
        Mobs = loaded
    else
        log("bestiary unavailable: %s", tostring(loaded))
    end
    -- Load Persistent Bestiary Memory (Weaknesses, Absorbs, Immunities, Resists)
    local okMem, mem = pcall(dofile, DIR .. "/Scripts/bestiary_memory.lua")
    if okMem and type(mem) == "table" then
        for k, aff in pairs(mem) do
            if Mobs[k] then
                Mobs[k].weak = Mobs[k].weak or {}
                if aff.weak then
                    for el in pairs(aff.weak) do
                        local found = false
                        for _, w in ipairs(Mobs[k].weak) do if w == el then found = true; break end end
                        if not found then Mobs[k].weak[#Mobs[k].weak + 1] = el end
                    end
                end
                if aff.absorb then Mobs[k].absorb = aff.absorb end
                if aff.no then Mobs[k].no = aff.no end
                if aff.half then Mobs[k].half = aff.half end
            else
                Mobs[k] = aff
            end
        end
        log("persistent bestiary memory loaded")
    end
end

-- =============================================================================
-- SMART AI PERSISTENT LEARNING ENGINE (Bestiary, Boss Patterns, DPS Rotations)
-- =============================================================================
local TacticalMemory = {
    bossThresholds = {}, -- [bossKey] = { 75, 50, 25 }
    skillYield = {},     -- [who] = { [skill] = { total = X, uses = Y, avg = Z } }
}
do
    local okTac, tmem = pcall(dofile, DIR .. "/Scripts/tactical_memory.lua")
    if okTac and type(tmem) == "table" then
        if tmem.bossThresholds then TacticalMemory.bossThresholds = tmem.bossThresholds end
        if tmem.skillYield then TacticalMemory.skillYield = tmem.skillYield end
        log("persistent tactical memory loaded")
    end
end

local function learnAffinity(enemyName, element, kind)
    if not (enemyName and element and kind and Fight) then return end
    Fight.learnedAffinity = Fight.learnedAffinity or {}
    local k = mobKey(enemyName) or foldName(enemyName)
    Fight.learnedAffinity[k] = Fight.learnedAffinity[k] or {}
    Fight.learnedAffinity[k][kind] = Fight.learnedAffinity[k][kind] or {}
    if not Fight.learnedAffinity[k][kind][element] then
        Fight.learnedAffinity[k][kind][element] = true
        Mobs[k] = Mobs[k] or {}
        Mobs[k][kind] = Mobs[k][kind] or {}
        Mobs[k][kind][element] = true
        local tag = kind:upper()
        if kind == "weak" then tag = "WEAKNESS DISCOVERED" end
        if kind == "absorb" then tag = "ABSORB AVOIDANCE (HEALS ENEMY)" end
        if kind == "no" then tag = "IMMUNITY (0 DAMAGE)" end
        local msg = string.format("[AI LEARNED] %s %s: %s!", enemyName, tag, element:upper())
        log("%s", msg)
        appendLog("  " .. msg)
        if showToast then showToast(msg) end
    end
end

local function learnBossThreshold(bossName, hpPct, turn)
    if not (bossName and hpPct and TacticalMemory) then return end
    local k = mobKey(bossName) or foldName(bossName)
    TacticalMemory.bossThresholds = TacticalMemory.bossThresholds or {}
    TacticalMemory.bossThresholds[k] = TacticalMemory.bossThresholds[k] or {}
    local rounded = math.floor((hpPct + 2.5) / 5) * 5
    local exists = false
    for _, t in ipairs(TacticalMemory.bossThresholds[k]) do
        if math.abs(t - rounded) <= 4 then exists = true; break end
    end
    if not exists and rounded > 5 and rounded < 98 then
        table.insert(TacticalMemory.bossThresholds[k], rounded)
        table.sort(TacticalMemory.bossThresholds[k], function(a, b) return a > b end)
        local msg = string.format("[AI PATTERN] %s Danger Threshold learned at %d%% HP!", bossName, rounded)
        log("%s", msg)
        appendLog("  " .. msg)
        if showToast then showToast(msg) end
    end
end

local function learnSkillYield(who, skillName, deltaHpPct)
    if not (who and skillName and deltaHpPct and deltaHpPct > 0 and TacticalMemory) then return end
    local wKey = who:lower()
    local sKey = skillName:lower()
    TacticalMemory.skillYield = TacticalMemory.skillYield or {}
    TacticalMemory.skillYield[wKey] = TacticalMemory.skillYield[wKey] or {}
    local entry = TacticalMemory.skillYield[wKey][sKey] or { total = 0, uses = 0, avg = 0 }
    entry.uses = entry.uses + 1
    entry.total = entry.total + deltaHpPct
    entry.avg = entry.total / entry.uses
    TacticalMemory.skillYield[wKey][sKey] = entry
end
local Health = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/health.lua")
    if ok and type(loaded) == "table" then
        Health = loaded
    else
        log("health unavailable: %s", tostring(loaded))
    end
end
local Debuffs = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/debuffs.lua")
    if ok and type(loaded) == "table" then
        Debuffs = loaded
    else
        log("debuffs unavailable: %s", tostring(loaded))
    end
end
local Gauges = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/gauges.lua")
    if ok and type(loaded) == "table" then
        Gauges = loaded
    else
        log("gauges unavailable: %s", tostring(loaded))
    end
end
local Espers = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/espers.lua")
    if ok and type(loaded) == "table" then
        Espers = loaded
    else
        log("espers unavailable: %s", tostring(loaded))
    end
end
local Limits = {}
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/limits.lua")
    if ok and type(loaded) == "table" then
        Limits = loaded
    else
        log("limits unavailable: %s", tostring(loaded))
    end
end
local Advisor = nil
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/advisor.lua")
    if ok and type(loaded) == "table" then
        Advisor = loaded
    else
        log("advisor unavailable: %s", tostring(loaded))
    end
end
local PartyHud = nil
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/party_hud.lua")
    if ok and type(loaded) == "table" then
        PartyHud = loaded
    else
        log("party_hud unavailable: %s", tostring(loaded))
    end
end
local Highlighter = nil
do
    local ok, loaded = pcall(dofile, DIR .. "/Scripts/highlighter.lua")
    if ok and type(loaded) == "table" then
        Highlighter = loaded
    else
        log("highlighter unavailable: %s", tostring(loaded))
    end
end
local function foldName(name)
    local n = (name or ""):lower()
    n = n:gsub("’", "'"):gsub("‘", "'"):gsub("`", "'")
    return n
end
local function mobKey(name)
    local n = foldName(name)
    if Mobs[n] then return n end
    local stem = n:gsub("%s*[a-z]$", "")
    if stem ~= n and Mobs[stem] then return stem end
    return nil
end
local function mobOf(enemy)
    if not enemy then return nil end
    local key = mobKey(enemy.name)
    return key and Mobs[key] or nil, key
end

local CONFIG_PATH = DIR .. "/config.ini"
local STATE_PATH = DIR .. "/state.txt"
local LOG_PATH = DIR .. "/battle_log.txt"

local ATTR = {
    FIGHT = 1, CHASE = 2, ABILITY = 3, MAGIC = 4, LB = 5,
    ITEM = 6, SUMMON = 7, FINISH = 9,
    MIX = 10, THROW = 11, THROW_MONEY = 12,
    DUAL = 13, MIMIC = 14, SWORD = 15, ESCAPE = 16,
}
local SKIP = {
    [ATTR.CHASE] = true, [ATTR.ITEM] = true, [ATTR.MIX] = true,
    [ATTR.THROW] = true, [ATTR.THROW_MONEY] = true, [ATTR.DUAL] = true,
    [ATTR.MIMIC] = true, [ATTR.SWORD] = true, [ATTR.ESCAPE] = true,
}
local EFF = { DAMAGE = 1, PARAM = 2, CURE = 19, REVIVE = 20, DEFEND = 26, ANALYZE = 29, COVER = 41 }
local TGT = { SELF = 0, SINGLE = 1, GROUP = 2, SPREAD = 3, ALL = 4 }
local REL = { FRIEND = 1, ENEMY = 2 }
local PARAM = { HP = 1, MP = 2, LB = 4 }
local VAR = { UP = 0, RATIO = 2 }
local ST_BREAK = 89
local GUARD_STATUS = { [34] = true, [35] = true, [36] = true }
local OUT_OF_CONTROL = { [6] = "confused", [8] = "charmed", [10] = "berserk" }
-- Sleep, silence, paralysis, confuse, petrify, charm, stop, berserk, doom.
-- Poison, blind, and stat-broken stay off this list. health.lua cures it.
local LOCK = {
    [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
    [8] = true, [9] = true, [10] = true, [11] = true,
}
local PHASE_BONUS, PHASE_FINISH = 1, 2
local DECIDE_MS = 420

local Hud = { serial = 0, toastSerial = 0, disabled = false, box = {} }
local showToast = function(msg) if Hud and Hud.toast then Hud.toast(msg) end end
local showBadge = function(msg) if Hud and Hud.badgeShow then Hud.badgeShow(msg) end end
_G.FFR_Toast = function(msg) showToast(msg) end

local Defaults = {
    Enabled = true, BattleSpeed = 2, Submit = true, AttacksOnly = false,
    TakeOverKey = "F10", MenuKey = "F9", CheapMP = true,
}
local cfg = {}
for k, v in pairs(Defaults) do cfg[k] = v end

local function parseBool(s)
    s = tostring(s or ""):lower()
    return s == "1" or s == "true" or s == "yes" or s == "on"
end

local function loadIni(path)
    local out = {}
    local f = io.open(path, "r")
    if not f then return out end
    for line in f:lines() do
        local k, v = line:match("^%s*([^;#%[=][^=]-)%s*=%s*(.-)%s*$")
        if k then out[k:lower()] = v end
    end
    f:close()
    return out
end

local function loadConfig()
    local ini = loadIni(CONFIG_PATH)
    local function take(name)
        local v = ini[name:lower()]
        if v == nil or v == "" then return end
        if type(Defaults[name]) == "boolean" then
            cfg[name] = parseBool(v)
        elseif type(Defaults[name]) == "number" then
            cfg[name] = tonumber(v) or Defaults[name]
        else
            cfg[name] = v
        end
    end
    for name in pairs(Defaults) do take(name) end
    if cfg.BattleSpeed < 1 then cfg.BattleSpeed = 1 end
    if cfg.BattleSpeed > 4 then cfg.BattleSpeed = 4 end
    local state = loadIni(STATE_PATH)
    if state.enabled then cfg.Enabled = parseBool(state.enabled) end
    if state.attacks then cfg.AttacksOnly = parseBool(state.attacks) end
end

local function saveState()
    local f = io.open(STATE_PATH, "w")
    if not f then return end
    f:write("enabled=" .. (cfg.Enabled and "true" or "false") .. "\n")
    f:write("attacks=" .. (cfg.AttacksOnly and "true" or "false") .. "\n")
    f:close()
end

-- The on-disk log keeps this many fights. A new header drops the oldest.
local function keepFights(text, keep)
    local fights, buf = {}, {}
    local function push()
        if #buf == 0 then return end
        local body = table.concat(buf, "\n")
        if body:match("%S") then fights[#fights + 1] = body end
        buf = {}
    end
    text = (text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    for row in (text .. "\n"):gmatch("([^\n]*)\n") do
        if row:match("^== battle ") then push() end
        buf[#buf + 1] = row
    end
    push()
    while #fights > keep do table.remove(fights, 1) end
    return table.concat(fights, "\n")
end

local function appendLog(line)
    if type(line) == "string" and line:match("^== battle ") then
        local read = io.open(LOG_PATH, "r")
        local text, size = "", 0
        if read then
            size = read:seek("end") or 0
            read:seek("set", 0)
            local function slurp()
                local ok, got = pcall(function() return read:read("*a") end)
                if ok and type(got) == "string" and got ~= "" then return got end
                read:seek("set", 0)
                ok, got = pcall(function() return read:read("a") end)
                if ok and type(got) == "string" and got ~= "" then return got end
                read:seek("set", 0)
                local parts = {}
                while true do
                    local block = read:read(8192)
                    if (not block) or (block == "") then break end
                    parts[#parts + 1] = block
                end
                return table.concat(parts)
            end
            local okRead, got = pcall(slurp)
            if okRead and type(got) == "string" then text = got end
            read:close()
        end
        -- A failed read must not replace a log that still has bytes.
        if text == "" and size > 0 then text = nil end
        local kept = text and keepFights(text, 4) or nil
        if kept then
            local out = io.open(LOG_PATH, "w")
            if out then
                if kept ~= "" then
                    out:write(kept)
                    if kept:sub(-1) ~= "\n" then out:write("\n") end
                end
                out:close()
            end
        end
    end
    local f = io.open(LOG_PATH, "a")
    if not f then return end
    f:write(line .. "\n")
    f:close()
end

--------------------------------------------------------------------------------
-- Game objects
--------------------------------------------------------------------------------

local function unwrap(v)
    if type(v) == "userdata" then
        local ok, inner = pcall(function() return v:get() end)
        if ok and inner ~= nil then return inner end
    end
    return v
end

local function num(v)
    v = unwrap(v)
    if type(v) == "number" then return v end
    return nil
end

local function textOf(v)
    if type(v) == "string" then
        if v:find("MISSING STRING TABLE ENTRY") then return nil end
        return v
    end
    if type(v) == "userdata" then
        local ok, s = pcall(function() return v:ToString() end)
        if ok and type(s) == "string" and s ~= "" and not s:find("MISSING STRING TABLE ENTRY") then
            return s
        end
    end
    return nil
end

local function fill(fn)
    local t = {}
    local ok, ret = pcall(fn, t)
    if not ok then return nil, tostring(ret) end
    local out = {}
    local function take(v)
        v = unwrap(v)
        if v ~= nil then out[#out + 1] = v end
    end
    for _, v in pairs(t) do take(v) end
    if type(ret) == "table" then
        for _, v in pairs(ret) do take(v) end
    elseif ret ~= nil then
        take(ret)
    end
    return out
end

local bflBattle, bflSkill
local function battleLib()
    if not (bflBattle and bflBattle:IsValid()) then
        bflBattle = StaticFindObject("/Script/mucha.Default__CPP_BFL_Battle")
    end
    return bflBattle
end
local function skillLib()
    if not (bflSkill and bflSkill:IsValid()) then
        bflSkill = StaticFindObject("/Script/mucha.Default__CPP_BFL_Skill")
    end
    return bflSkill
end

local bflItem = nil
local function itemLib()
    if not (bflItem and bflItem:IsValid()) then
        bflItem = StaticFindObject("/Script/mucha.Default__CPP_BFL_Item")
    end
    return bflItem
end

local function rowStructName(dt)
    local ok, name = pcall(function()
        local s = dt:GetRowStruct()
        if not s or not s:IsValid() then return nil end
        return s:GetFName():ToString()
    end)
    return ok and name or nil
end

local function field(row, name)
    local ok, v = pcall(function() return row[name] end)
    if not ok then return nil end
    return v
end

local SkillIdx = nil
local ItemIdx = nil
local function buildSkillIndex()
    if SkillIdx and SkillIdx._namedCount and SkillIdx._namedCount > 100 then return end
    local effects = {}
    local skills = {}
    local tables = FindAllOf("DataTable") or {}
    local effectTables, skillTables, itemTables, generalTables = {}, {}, {}, {}
    for _, dt in ipairs(tables) do
        pcall(function()
            if type(dt) ~= "userdata" or not dt:IsValid() then return end
            local struct = rowStructName(dt)
            if struct == "SKILL_EFFECT_DATA" then
                effectTables[#effectTables + 1] = dt
            elseif struct == "SKILL_DATA" then
                skillTables[#skillTables + 1] = dt
            elseif struct == "SKILL_GENERAL_DATA" then
                generalTables[#generalTables + 1] = dt
            elseif struct == "CONSUMABLES_ITEM_DATA" then
                itemTables[#itemTables + 1] = dt
            end
        end)
    end
    for _, dt in ipairs(effectTables) do
        pcall(function()
            dt:ForEachRow(function(_, row)
                local id = num(field(row, "ID"))
                if id then effects[id] = num(field(row, "statusCondition")) or 0 end
            end)
        end)
    end
    for _, dt in ipairs(skillTables) do
        pcall(function()
            dt:ForEachRow(function(rowName, row)
                local id = num(field(row, "ID"))
                if not id then return end
                local friendStatus, enemyStatus = {}, {}
                local bundles = field(row, "effectBundleList")
                if type(bundles) == "userdata" and bundles.ForEach then
                    bundles:ForEach(function(_, e)
                        local b = unwrap(e)
                        local eid = b and num(b.effectId)
                        local rel = b and num(b.targetRelation)
                        local st = eid and effects[eid]
                        if st and st > 0 then
                            if rel == REL.FRIEND then friendStatus[st] = true end
                            if rel == REL.ENEMY then enemyStatus[st] = true end
                        end
                    end)
                end
                local own = num(field(row, "statusCondition")) or 0
                local rel = num(field(row, "defaultTargetRelation")) or 0
                if own > 0 and rel == REL.FRIEND then friendStatus[own] = true end
                if own > 0 and rel == REL.ENEMY then enemyStatus[own] = true end
                local name = textOf(field(row, "Name"))
                if not name or name == "" then
                    local okR, rn = pcall(function() return rowName:ToString() end)
                    if okR and type(rn) == "string" and rn ~= "" and not rn:find("MISSING STRING TABLE ENTRY") then
                        if not rn:match("^%d+$") then name = rn end
                    end
                end
                if not name or name == "" then
                    local comm = textOf(field(row, "Comment"))
                    if comm and comm ~= "" and not comm:find("MISSING STRING TABLE ENTRY") then
                        name = comm
                    end
                end
                local rawCost = num(field(row, "Cost")) or 0
                local attr = num(field(row, "skillAttrType")) or 0
                local finalCost = rawCost
                if cfg.CheapMP ~= false and rawCost > 1 and attr ~= ATTR.LB then
                    finalCost = 1
                    pcall(function() row.Cost = 1 end)
                end
                skills[id] = {
                    id = id,
                    name = (name and name ~= "") and name or ("#" .. id),
                    cost = finalCost,
                    attr = attr,
                    effect = num(field(row, "skillEffectType")) or 0,
                    varType = num(field(row, "parameterVariationType")) or -1,
                    paramType = num(field(row, "parameterType")) or 0,
                    target = num(field(row, "TargetType")) or TGT.SINGLE,
                    rel = rel,
                    power = num(field(row, "magnification")) or 0,
                    calc = num(field(row, "damageCalcType")) or 0,
                    breakPower = num(field(row, "breakDamageValue")) or 0,
                    hits = num(field(row, "hitCount")) or 1,
                    targetState = num(field(row, "defaultTargetState")) or 0,
                    friendStatus = friendStatus,
                    enemyStatus = enemyStatus,
                }
            end)
        end)
    end
    for _, dt in ipairs(generalTables) do
        pcall(function()
            dt:ForEachRow(function(_, row)
                local overrides = field(row, "costOverrideData")
                if type(overrides) == "userdata" and overrides.ForEach then
                    pcall(function()
                        overrides:ForEach(function(_, e)
                            local b = unwrap(e)
                            local ctype = b and num(field(b, "costType")) or 0
                            local cval = b and num(field(b, "Cost")) or 0
                            if ctype == 0 and cval > 1 then
                                pcall(function() e.Cost = 1 end)
                            end
                        end)
                    end)
                elseif type(overrides) == "userdata" or type(overrides) == "table" then
                    local okN, n = pcall(function() return #overrides end)
                    if okN and type(n) == "number" then
                        for i = 1, n do
                            pcall(function()
                                local e = overrides[i]
                                local b = unwrap(e)
                                local ctype = b and num(field(b, "costType")) or 0
                                local cval = b and num(field(b, "Cost")) or 0
                                if ctype == 0 and cval > 1 then
                                    e.Cost = 1
                                end
                            end)
                        end
                    end
                end
            end)
        end)
    end
    local n, validNamed = 0, 0
    for _, s in pairs(skills) do
        n = n + 1
        if s.name and not s.name:find("^#") and not s.name:find("MISSING STRING TABLE ENTRY") then
            validNamed = validNamed + 1
        end
    end
    if n > 0 and validNamed > (n * 0.25) then
        skills._namedCount = validNamed
        SkillIdx = skills
        log("skill table: %d rows (%d named skills indexed)", n, validNamed)
    end
    local items = {}
    for _, dt in ipairs(itemTables) do
        pcall(function()
            dt:ForEachRow(function(rowName, row)
                local id = num(field(row, "ID"))
                if not id then return end
                local name = textOf(field(row, "Name"))
                if not name or name == "" then
                    local okR, rn = pcall(function() return rowName:ToString() end)
                    if okR and type(rn) == "string" and rn ~= "" and not rn:find("MISSING STRING TABLE ENTRY") then
                        if not rn:match("^%d+$") then name = rn end
                    end
                end
                local skillId = nil
                for _, key in ipairs({ "SkillId", "skillId", "SkillID", "UseSkillId", "EffectSkillId" }) do
                    skillId = num(field(row, key))
                    if skillId and skillId > 0 then break end
                    skillId = nil
                end
                items[id] = {
                    id = id,
                    name = (name and name ~= "") and name or ("item " .. id),
                    skillId = skillId,
                    rare = field(row, "Rare") == true or field(row, "IsRare") == true,
                }
            end)
        end)
    end
    local ni, validItemNames = 0, 0
    for _, item in pairs(items) do
        ni = ni + 1
        if item.name and not item.name:find("^item %d+") and not item.name:find("MISSING STRING TABLE ENTRY") then
            validItemNames = validItemNames + 1
        end
    end
    if ni > 0 and validItemNames > (ni * 0.25) then
        ItemIdx = items
        log("item table: %d rows (%d named items indexed)", ni, validItemNames)
    end
end

local function skillOf(id)
    buildSkillIndex()
    return SkillIdx and SkillIdx[id]
end

local function paramOf(uid)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return nil end
    local ok, p = pcall(function() return bfl:GetBattleUnitParameter(uid, true) end)
    if ok and p and p.IsValid and p:IsValid() then return p end
    return nil
end

local function stat(uid, kind, maximum)
    local p = paramOf(uid)
    if not p then return nil end
    local ok, v = pcall(function()
        if maximum then return p:GetMaxParameterByType(kind) end
        return p:GetParameterByType(kind, false)
    end)
    if ok then return num(v) end
    return nil
end

local function hpRatio(uid)
    local cur, maxv = stat(uid, PARAM.HP, false), stat(uid, PARAM.HP, true)
    if not cur or not maxv or maxv <= 0 then return nil end
    return cur / maxv
end

local function statuses(uid)
    local set = {}
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return set end
    local list = fill(function(t) bfl:GetStatusConditionList(t, uid) end)
    if not list then return set end
    for _, v in ipairs(list) do
        local n = num(v)
        if n then set[n] = true end
    end
    return set
end

local function outOfControl(uid)
    local set = statuses(uid)
    for id, name in pairs(OUT_OF_CONTROL) do
        if set[id] then return name end
    end
    return nil
end

local function broken(uid)
    if statuses(uid)[ST_BREAK] then return true end
    local p = paramOf(uid)
    if not p then return false end
    local ok, r = pcall(function() return p:GetBreakPointRatio() end)
    r = ok and num(r) or nil
    return r ~= nil and r <= 0.001
end

local function breakLeft(uid)
    local p = paramOf(uid)
    if not p then return 1 end
    local ok, r = pcall(function() return p:GetBreakPointRatio() end)
    r = ok and num(r) or nil
    if r == nil then return broken(uid) and 0 or 1 end
    if r > 1.5 then return r / 100 end
    return r
end

local function unitName(uid)
    local p = paramOf(uid)
    if p then
        local ok, n = pcall(function() return p:GetDuplicationUnitName() end)
        local s = ok and textOf(n) or nil
        if s and s ~= "" then return s end
        local id
        ok, id = pcall(function() return p:GetUnitId() end)
        id = ok and num(id) or nil
        if id then return "Unit " .. id end
    end
    return "Unit " .. tostring(uid)
end

local function skillCost(uid, id, isAll)
    local info = skillOf(id)
    local rawCost = info and info.cost or 0
    local bfl, sl = battleLib(), skillLib()
    if bfl and bfl:IsValid() and sl and sl:IsValid() then
        local ok, cost = pcall(function()
            local unitId = bfl:GetBattleUnitParameter(uid, true):GetUnitId()
            return sl:GetSkillCost(id, unitId, isAll and true or false)
        end)
        if ok and type(cost) == "number" and cost >= 0 then rawCost = cost end
    end
    if cfg.CheapMP ~= false and rawCost > 1 and (not info or info.attr ~= ATTR.LB) then
        return 1
    end
    return rawCost
end

-- true when the game says this unit can activate it, false when it says no,
-- nil when the call is missing. The MP check is separate: a short bar is not a seal.
local function activation(uid, id)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return nil end
    local ok, v = pcall(function() return bfl:CanUnitActivateSkill(uid, id) end)
    if ok and v == false then return false end
    if v == true then return true end
    return nil
end

local function sealed(uid, id)
    return activation(uid, id) == false
end

-- A Limit crystal is not MP. CanUnitActivateSkill stays false while the
-- crystal is filling, and also on rows the command bar will still accept.
-- IsEnableCommand stays false for the same rows, so the gauge is the check.
local function limitSkill(skill)
    if not skill then return false end
    if skill.attr == ATTR.LB then return true end
    local info = skill.known or knownOf(skill)
    local use = info and info.use
    return use == "lb-setup" or use == "lb-cash" or use == "lb-revive"
end

local function commandEnabled(uid, id)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return true end
    local ok, enabled = pcall(function() return bfl:IsEnableCommand(uid, id) end)
    if ok and enabled == false then return false end
    return true
end

local function idOf(v)
    local n = num(v)
    if n then return n end
    if type(v) ~= "userdata" then return nil end
    for _, key in ipairs({ "ID", "Id", "SkillId", "skillId", "actionId", "ActionId" }) do
        local ok, inner = pcall(function() return v[key] end)
        inner = ok and num(inner) or nil
        if inner then return inner end
    end
    return nil
end

local loggedUnits = {}
local function equippedIds(uid)
    buildSkillIndex()
    local p = paramOf(uid)
    local bfl = battleLib()
    local unitId = nil
    if p then
        local ok, v = pcall(function() return p:GetUnitId() end)
        if ok then unitId = num(v) end
    end
    local probes = {}
    if p then
        probes[#probes + 1] = { "param.GetActiveSkillListWithVision", function(t) p:GetActiveSkillListWithVision(t) end }
        probes[#probes + 1] = { "param.GetActiveSkillList", function(t) p:GetActiveSkillList(t) end }
        probes[#probes + 1] = { "param.GetActionList", function(t) p:GetActionList(t) end }
    end
    if bfl and bfl:IsValid() then
        probes[#probes + 1] = { "battle.GetActiveSkillListWithVision", function(t) bfl:GetActiveSkillListWithVision(t, uid) end }
        probes[#probes + 1] = { "battle.GetEquipSkills", function(t) bfl:GetEquipSkills(t, unitId or uid) end }
    end
    local sl = skillLib()
    if sl and sl:IsValid() then
        probes[#probes + 1] = { "skill.GetEquipSkills", function(t) sl:GetEquipSkills(t, unitId or uid) end }
    end
    local found, notes = {}, {}
    local function add(v)
        local id = idOf(v)
        if id and id > 0 then found[id] = true end
    end
    for _, probe in ipairs(probes) do
        local list, err = fill(probe[2])
        if list and #list > 0 then
            for _, v in ipairs(list) do add(v) end
            notes[#notes + 1] = string.format("%s=%d", probe[1], #list)
        elseif not loggedUnits[uid] and err then
            notes[#notes + 1] = probe[1] .. " failed"
        end
    end
    if p then
        for _, prop in ipairs({ "activeSkillIdList", "equipSkillList", "commandSkillIdList" }) do
            local ok, arr = pcall(function() return p[prop] end)
            if ok and type(arr) == "userdata" then
                local n = 0
                local walked = pcall(function()
                    arr:ForEach(function(_, e)
                        add(e)
                        n = n + 1
                    end)
                end)
                if walked and n > 0 then
                    notes[#notes + 1] = prop .. "=" .. n
                elseif not walked and not loggedUnits[uid] then
                    notes[#notes + 1] = prop .. " skipped"
                end
            end
        end
    end
    if not loggedUnits[uid] then
        loggedUnits[uid] = true
        local ids = {}
        for id in pairs(found) do ids[#ids + 1] = id end
        table.sort(ids)
        local names = {}
        for i = 1, math.min(#ids, 12) do
            local s = skillOf(ids[i])
            names[#names + 1] = s and s.name or tostring(ids[i])
        end
        log("skill list for unit %s via %s -> %s", tostring(uid),
            (#notes > 0) and table.concat(notes, ", ") or "nothing",
            (#names > 0) and table.concat(names, ", ") or "(empty)")
    end
    local ids = {}
    for id in pairs(found) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local function targetsFor(uid, skill, relation)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return {} end
    local list = fill(function(t)
        bfl:GetSkillTargetUnitUniqueIdList(t, uid, skill.id, relation, true)
    end)
    local ids = {}
    if list then
        for _, v in ipairs(list) do
            local n = num(v)
            if n then ids[#ids + 1] = n end
        end
    end
    if #ids == 0 then
        local ok, n = pcall(function() return bfl:GetDefaultSkillTargetUnitUniqueId(uid, skill.id) end)
        n = ok and num(n) or nil
        if n and n >= 0 then ids[1] = n end
    end
    return ids
end

local function members(relation)
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return {} end
    local ids, seen = {}, {}
    local function addList(list)
        if not list then return end
        for _, v in ipairs(list) do
            local n = num(v)
            if not n and type(v) == "userdata" then
                local ok, u = pcall(function() return v:GetUniqueId() end)
                n = ok and num(u) or nil
                if not n then
                    ok, u = pcall(function() return v.UniqueId end)
                    n = ok and num(u) or nil
                end
            end
            if n and not seen[n] then
                seen[n] = true
                ids[#ids + 1] = n
            end
        end
    end
    addList(fill(function(t) bfl:GetBattleUnitListByRelation(t, relation, true) end))
    addList(fill(function(t) bfl:GetBattleUnitListByRelation(t, relation, false) end))
    addList(fill(function(t) bfl:GetBattleUnitListByRelation(t, relation) end))
    return ids
end

-- During a command the relation list often contains only the actor.
local function friendIds()
    local ids, seen = {}, {}
    local function add(n)
        n = num(n)
        if n and n >= 0 and not seen[n] then
            seen[n] = true
            ids[#ids + 1] = n
        end
    end
    for _, id in ipairs(members(REL.FRIEND)) do add(id) end
    local bfl = battleLib()
    if bfl and bfl:IsValid() then
        for uid = 0, 7 do
            local ok, p = pcall(function() return bfl:GetBattleUnitParameter(uid, true) end)
            if ok and p and p.IsValid and p:IsValid() then
                local okR, rel = pcall(function() return p:GetRelation() end)
                if okR and num(rel) == REL.FRIEND then add(uid) end
            end
        end
    end
    return ids
end

--------------------------------------------------------------------------------
-- Skill math. The live row has stagger and no element. known.lua names the element.
--------------------------------------------------------------------------------

local function hitsOf(skill)
    local h = skill.hits or 1
    if h < 1 then h = 1 end
    return h
end

local function aoeOf(skill)
    return skill.target == TGT.GROUP or skill.target == TGT.SPREAD or skill.target == TGT.ALL
end

-- A party heal is the live group target, or a published "all allies" row.
local function partyOf(skill)
    if aoeOf(skill) then return true end
    local info = skill and (skill.known or knownOf(skill))
    return (info and info.party) and true or false
end

local function offenseOf(skill)
    local h = hitsOf(skill)
    local power = skill.power or 0
    if power <= 0 and skill.attr == ATTR.FIGHT then power = 18 end
    local br = skill.breakPower or 0
    local info = skill.known or knownOf(skill)
    -- The published number is the whole skill's stagger, not the stagger of one hit.
    if info and info.stagger then return power * h, info.stagger end
    return power * h, br * h
end

-- Auto-Evolve Vision Mastery: Automatically prioritizes higher-tier unlocked abilities
local function skillTierBonus(skill)
    if not skill or not skill.name then return 0 end
    local n = skill.name:lower()

    -- Tier 4: Pinnacle Arts, -ja spells, Surge variants, High Arts (+8,000)
    if n:find(" surge") or n:find(" blade") or n:find(" knife") or n:find(" slam")
        or n:find("ja$") or n:find("ja ") or n:find("curaja")
        or n:find("null moon") or n:find("infinity drive") or n:find("crimson onslaught")
        or n:find("zantetsuken") or n:find("march of the machines") or n:find("iii$") or n:find(" iii ")
        or n:find("deathblow") or n:find("dystopia") or n:find("alterna") then
        return 8000
    end

    -- Tier 3: -ga spells, High Tier Signature Arts (+4,000)
    if n:find("ga$") or n:find("ga ") or n:find("curaga")
        or n:find("dawn frost") or n:find("cross%-slash") or n:find("tranquility")
        or n:find("blitzstrahl") or n:find("ascension") or n:find("ii$") or n:find(" ii ")
        or n:find("holy ray") or n:find("radiant restoration") or n:find("flame shot")
        or n:find("lightning shot") or n:find("formation: steeled advance") then
        return 4000
    end

    -- Tier 2: -ra spells, Secondary Arts (+1,500)
    if n:find("ra$") or n:find("ra ") or n:find("cura") or n:find("regen")
        or n:find("tackle") or n:find("sparkstrike") or n:find("braver")
        or n:find("armor break") or n:find("weapon break") then
        return 1500
    end

    -- Dynamic Future-Proof Scaling: Inspects raw power, breakPower, and resource cost
    -- Handles any newly unlocked Vision, DLC skill, or uncataloged character art
    local p = skill.power or 0
    local info = skill.known or (knownOf and knownOf(skill))
    local br = skill.breakPower or (info and info.stagger) or 0
    local cost = skill.cost or (info and info.cost) or 0

    if br >= 25 or p >= 90 or (cost >= 45 and p >= 50) then
        return 8000
    end
    if br >= 20 or p >= 60 or (cost >= 28 and p >= 35) then
        return 4000
    end
    if br >= 16 or p >= 35 or cost >= 15 then
        return 1500
    end

    return 0
end

local Fight

local function checkIsLongFight(w)
    if not w then return false end
    if w.boss then return true end
    if Fight and Fight.boss then return true end
    if w.enemies then
        for _, e in ipairs(w.enemies) do
            local card = mobOf(e)
            if card and card.danger and card.danger[1] then return true end
            local n = e.name and e.name:lower() or ""
            if n:find("boss") or n:find("trial") or n:find("esper") or n:find("eidolon") or n:find("hunt") or n:find("dread") then
                return true
            end
            local g = (card and tonumber(card.gauge)) or 0
            if g >= 60 then return true end
        end
    end
    if Fight then
        if (Fight.rounds or 0) >= 2 then return true end
        if #(Fight.actions or {}) >= 6 then return true end
    end
    return false
end

-- Role Mastery Bonus: Auto-loads and prioritizes mastered abilities tailored to each character's specific role
-- Supports support best in long fights & blast dmg in short fights; Tanks tank; DPS deals max possible damage!
local function provokeTurnsRemaining()
    if not Fight or not Fight.claim or not Fight.claim.provoke then return 0 end
    local roundsElapsed = (Fight.rounds or 0) - (Fight.claim.provokeRound or -99)
    if roundsElapsed >= 3 then
        Fight.claim.provoke = false
        Fight.provokeTurnsRemaining = 0
        return 0
    end
    local turnsLeft = 3 - roundsElapsed
    if Fight.provokeTurnsRemaining ~= nil then
        turnsLeft = math.min(turnsLeft, Fight.provokeTurnsRemaining)
    end
    if turnsLeft <= 0 then
        Fight.claim.provoke = false
        Fight.provokeTurnsRemaining = 0
        return 0
    end
    return turnsLeft
end

local function roleMasteryBonus(uid, skill, w)
    if not skill or not uid then return 0 end
    local sName = skill.name and skill.name:lower() or ""
    local who = unitName(uid):lower()
    local sKind = skill.kind or ""
    local bonus = 0

    local isLongFight = checkIsLongFight(w)

    -- Check if approaching a learned boss danger threshold!
    local approachingDangerPhase = false
    if isLongFight and w and w.enemies then
        for _, e in ipairs(w.enemies) do
            local k = mobKey(e.name) or foldName(e.name)
            local thresholds = TacticalMemory and TacticalMemory.bossThresholds and TacticalMemory.bossThresholds[k]
            if thresholds then
                local curPct = math.floor((e.hp or 1) * 100)
                for _, t in ipairs(thresholds) do
                    if curPct > t and curPct <= (t + 10) then
                        approachingDangerPhase = true
                        break
                    end
                end
            end
        end
    end

    -- 1. Rain (The Sentinel Vanguard Tank) - Aggro Anchor, Mitigation & Stagger Cashout
    if who:find("rain") or who:find("cecil") or who:find("wilhelm") or who:find("charlotte") or who:find("snow") or who:find("basch") then
        local bossCharging = false
        local anyBroken = false
        if w and w.enemies then
            for _, e in ipairs(w.enemies) do
                local c = mobOf(e)
                if c and c.danger and c.danger[1] and not e.broken then bossCharging = true end
                if e.broken or (Fight and Fight.down and Fight.down[e.id]) then anyBroken = true end
            end
        end

        -- Stagger Window & Low HP Execute: When enemies are broken or executable (<= 25% HP), drop tank stance and crush them!
        local anyExecutable = false
        if w and w.enemies then
            for _, e in ipairs(w.enemies) do
                if not e.broken and (e.hp or 1) <= 0.25 and (e.hp or 1) > 0 then
                    anyExecutable = true
                    break
                end
            end
        end

        if sName:find("infinity drive") or sName:find("crimson onslaught") then
            bonus = bonus + ((anyBroken or anyExecutable) and 22000 or (isLongFight and 12000 or 15000))
        elseif sName:find("firaga blade") or sName:find("firaja blade") or sName:find("blazing") or sName:find("fire blade") then
            bonus = bonus + (bossCharging and 18000 or ((anyBroken or anyExecutable) and 14000 or 11000))
        elseif sName:find("tackle") or sName:find("counter") or sName:find("arms akimbo") or sName:find("heavy strike") then
            bonus = bonus + ((anyBroken or anyExecutable) and 12000 or 9000)
        -- Defensive Barriers: Critical mitigation when holding aggro or when boss charges danger moves
        elseif sName:find("phalanx") or sName:find("iron wall") or sName:find("royal guard") or sName:find("sentinel") then
            bonus = bonus + ((bossCharging or approachingDangerPhase) and 20000 or (isLongFight and 15000 or 5000))
        -- Provoke / Taunt / Cover: In long fights, lock down aggro! In short fights, peel if party hurt
        elseif sName:find("provoke") or sName:find("taunt") or sName:find("roar") or sKind == "provoke" or sKind == "cover" then
            local turnsLeft = provokeTurnsRemaining()
            if turnsLeft >= 1 then
                -- CRITICAL SAFETY LOCK: NEVER recast Provoke if any enemy still has >= 1 turn of Provoke active!
                -- Completely prevents Rain from wasting an action refreshing provoke when 1 turn remains.
                bonus = bonus - 50000
            else
                local partyHurt = false
                if w and w.allies then
                    for _, a in ipairs(w.allies) do
                        if not a.dead and (a.hp or 1) < 0.70 then partyHurt = true break end
                    end
                end
                if isLongFight then
                    bonus = bonus + (anyBroken and 1000 or 19000) -- Top priority in long/boss fights while boss is active!
                else
                    bonus = bonus + (partyHurt and 12000 or 1000)  -- On short fights, peel only if allies take heat
                end
            end
        end

    -- 2. Lasswell & Pure Melee DPS (Critical Boss Finisher & Damage Shredder) - MAXIMUM DAMAGE
    elseif who:find("lasswell") or who:find("cloud") or who:find("sephiroth") or who:find("squall") or who:find("tidus") then
        local anyBroken = false
        local bossCharging = false
        if w and w.enemies then
            for _, e in ipairs(w.enemies) do
                local c = mobOf(e)
                if c and c.danger and c.danger[1] and not e.broken then bossCharging = true end
                if e.broken or (Fight and Fight.down and Fight.down[e.id]) then anyBroken = true end
            end
        end

        -- Devastating Critical & High-Damage Finisher Moves
        if sName:find("null moon") or sName:find("exorcising") or sName:find("cross%-slash") then
            bonus = bonus + (anyBroken and 26000 or 15000) -- Maximizes damage output at all times!
        elseif sName:find("blade torrent") or sName:find("transient rite") or sName:find("barrage") or sName:find("splitter") then
            -- High damage multi-hit / AoE: In short fights, wipes packs immediately!
            bonus = bonus + (not isLongFight and 19000 or (anyBroken and 16000 or 11000))
        elseif sName:find("dawn frost") or sName:find("blizzaga blade") or sName:find("tranquility") then
            bonus = bonus + (bossCharging and 20000 or (anyBroken and 15000 or 10000)) -- Elemental stagger / interrupt
        elseif sName:find("scan & strike") or sName:find("strike") or sName:find("slash") then
            bonus = bonus + (anyBroken and 12000 or 8000)
        end

    -- 3. Fina & Dedicated Healers (Support / Luminary)
    -- In LONG fights: Full support, heals, revives, buffs!
    -- In SHORT fights: FOCUS ON DAMAGE (Holy Ray, Banishga, offensive magic)!
    elseif who:find("fina") or who:find("ayaka") or who:find("folka") or who:find("garnet") or who:find("aerith") then
        local allyHurt = false
        local allyMortal = false
        if w and w.allies then
            for _, a in ipairs(w.allies) do
                if not a.dead then
                    local r = a.hp or 1
                    if r < 0.50 then allyHurt = true end
                    if r < 0.35 then allyMortal = true end
                end
            end
        end
        -- Revives (Always save fallen allies)
        if sName:find("arise") or sName:find("full raise") then
            bonus = bonus + 22000
        elseif sName:find("raise") or sKind == "revive" then
            bonus = bonus + 13000
        -- Dynamic Healing: Essential when someone is wounded
        elseif sName:find("curaja") or sName:find("curaga") or sName:find("radiant restoration") then
            bonus = bonus + (allyMortal and 24000 or (allyHurt and 17000 or (isLongFight and 8000 or 2000)))
        elseif sKind == "heal" and (sName:find("cura") or sName:find("cure")) then
            bonus = bonus + (allyMortal and 19000 or (allyHurt and 14000 or (isLongFight and 5000 or 1000)))
        -- Party Buffs (Cheer, Protect, Shell, Haste, Regen):
        -- In LONG fights: Super high priority to harden party!
        -- In SHORT fights: Deprioritized (mobs will die before buffs are useful)!
        elseif sName:find("cheer") or sName:find("haste") or sName:find("shell") or sName:find("protect") or sName:find("regen") or sKind == "buff" then
            bonus = bonus + (allyHurt and 2000 or (isLongFight and 17000 or 1000))
        -- Offensive Light/Holy Magic (Holy Ray, Banishga, Banish, Dualcast):
        -- In SHORT fights: FOCUS ON DAMAGE to crush enemy mobs!
        -- In LONG fights: Secondary to party support
        elseif sName:find("holy ray") or sName:find("banishga") or sName:find("banish") or sName:find("dualcast") or sKind == "magic" or sKind == "damage" then
            bonus = bonus + (allyHurt and 1000 or (not isLongFight and 19000 or 6000))
        end

    -- 4. Lid (Mechanist & Tactical Debuffer)
    -- In LONG fights: Shred armor & debuff boss!
    -- In SHORT fights: Blast with machine AoE damage (T.R.N.D., Mechabo Hammer, March)!
    elseif who:find("lid") or who:find("rikku") or who:find("edgar") then
        if sName:find("armor break") or sName:find("mental break") or sName:find("weapon break") or sKind == "debuff" then
            bonus = bonus + (isLongFight and 19000 or 4000) -- Debuffs shine in long fights!
        elseif sName:find("t.r.n.d") or sName:find("march of the machines") or sName:find("mechabo") or sName:find("wrench") or sName:find("hammer") then
            bonus = bonus + (not isLongFight and 19000 or 9000) -- AoE machine destruction in short fights!
        end

    -- 5. Sakura & Dark Fina (Mage Nuker & Elemental Catalyst) - MAXIMUM DAMAGE
    elseif who:find("sakura") or who:find("dark fina") or who:find("archwitch") or who:find("shantotto") or who:find("rydia") then
        local anyBroken = false
        if w and w.enemies then
            for _, e in ipairs(w.enemies) do
                if e.broken or (Fight and Fight.down and Fight.down[e.id]) then anyBroken = true break end
            end
        end
        if sName:find("dystopia") or sName:find("alterna") or sName:find("thundaja") or sName:find("firaja") or sName:find("blizzaja") or sName:find("flare") or sName:find("meteor") then
            bonus = bonus + (anyBroken and 28000 or 19000) -- Pinnacle Magic Nukes deal maximum possible damage!
        elseif sName:find("surge") or sName:find("colossal") or sName:find("dualcast") or sName:find("rebel thunder") then
            bonus = bonus + (anyBroken and 22000 or 16000)
        end

    -- 6. Nichol (Tactician & Synergist)
    -- In LONG fights: Bolster / Stance party buffs!
    -- In SHORT fights: Water / Ice damage nukes!
    elseif who:find("nichol") or who:find("hope") then
        if sName:find("stance") or sName:find("charge") or sName:find("bolster") then
            bonus = bonus + (isLongFight and 17000 or 2000)
        elseif sName:find("water") or sName:find("blizzard") or sName:find("flood") or sName:find("dualcast") or sKind == "magic" or sKind == "damage" then
            bonus = bonus + (not isLongFight and 18000 or 7000)
        end

    -- 7. Jake (Corsair & Gunner) - Rapid Burst Fire
    elseif who:find("jake") or who:find("vincent") or who:find("amelia") then
        if sName:find("quick draw") or sName:find("snipe") or sName:find("bullet") or sName:find("fire") or sName:find("assault") then
            bonus = bonus + 18000 -- Maximum gun burst damage
        end
    end

    return bonus
end

local function elementFactor(skill, enemy)
    local ok, factor = pcall(function()
        local info = skill and (skill.known or knownOf(skill))
        local el = info and (info.elements or info.element)
        if not el or not enemy then return 1 end
        local elList = (type(el) == "table") and el or { el }

        local bestF = 1
        for _, e in ipairs(elList) do
            local curF = 1
            if Fight and Fight.learnedAffinity and enemy then
                local enemyKey = enemy.name and enemy.name:lower() or (enemy.id and tostring(enemy.id))
                local learned = enemyKey and Fight.learnedAffinity[enemyKey]
                if learned then
                    if learned.absorb and learned.absorb[e] then curF = 0
                    elseif learned.no and learned.no[e] then curF = 0
                    elseif learned.half and learned.half[e] then curF = 0.5
                    elseif learned.weak and learned.weak[e] then curF = 3 end
                end
            end
            if curF == 1 then
                local card = mobOf(enemy)
                if card then
                    if card.absorb and card.absorb[e] then curF = 0
                    elseif card.no and card.no[e] then curF = 0
                    elseif card.half and card.half[e] then curF = 0.5
                    elseif card.weak and card.weak[e] then curF = 3 end
                end
            end
            if curF > bestF then bestF = curF end
            if curF == 0 and #elList == 1 then return 0 end
        end
        return bestF
    end)
    if not ok or type(factor) ~= "number" then return 1 end
    return factor
end

local function counterScale(skill, enemy)
    local ok, scale = pcall(function()
        local card = mobOf(enemy)
        if not card or not card.counter then return 1 end
        local info = skill and (skill.known or knownOf(skill))
        local phys = skill.attr == ATTR.FIGHT or (info and info.phys)
        local magic = skill.attr == ATTR.MAGIC or (info and info.magic)
        local countered = false
        if card.counter == "physical" then countered = phys and not magic end
        if card.counter == "magic" then countered = magic and not phys end
        if card.counter == "hit" then countered = phys or magic end
        if not countered then return 1 end
        if elementFactor(skill, enemy) >= 3 then return 0.85 end
        return 0.2
    end)
    if not ok or type(scale) ~= "number" then return 1 end
    return scale
end

local unitKit
-- A friend, a nameless slot, or a body with no HP is not a foe.
-- The enemy-target list has included the actor. The book also has a Lasswell card at gauge 9999.
local function keepFoe(id)
    if not id or not Fight then return false end
    local function drop()
        if Fight.seenFoe then Fight.seenFoe[id] = nil end
        return false
    end
    for _, fid in ipairs(friendIds()) do
        if fid == id then return drop() end
    end
    if Fight.seenAlly and Fight.seenAlly[id] then return drop() end
    local p = paramOf(id)
    if not p then return drop() end
    local ok, n = pcall(function() return p:GetDuplicationUnitName() end)
    local s = ok and textOf(n) or nil
    if not s or s == "" then return drop() end
    if Fight.seenAlly then
        local folded = foldName(s)
        for _, name in pairs(Fight.seenAlly) do
            if foldName(name) == folded then return drop() end
        end
    end
    local r = hpRatio(id)
    if r == nil or r <= 0 then return drop() end
    return true
end
local function monoScale(skill, enemy)
    if not Fight or not Fight.elemRun or not enemy then return 1 end
    local card = mobOf(enemy)
    if not card or not card.mono then return 1 end
    local info = skill and (skill.known or knownOf(skill))
    local el = info and info.element
    if not el then return 1 end
    local run = Fight.elemRun[enemy.id]
    if run and run.el == el and run.n >= 2 then return 0.05 end
    return 1
end

local function anyKey(set)
    if not set then return false end
    for _ in pairs(set) do return true end
    return false
end

local function isGuard(skill)
    local info = skill.known or knownOf(skill)
    if info and info.use == "guard" then return true end
    local name = skill.name and skill.name:lower() or ""
    if name == "defend" or name == "guard" then return true end
    if skill.effect == EFF.DEFEND or skill.effect == EFF.COVER then return true end
    if (skill.power or 0) > 0 or (skill.breakPower or 0) > 0 then return false end
    if skill.friendStatus then
        for id in pairs(skill.friendStatus) do
            if GUARD_STATUS[id] then return true end
        end
    end
    return false
end

local function classify(skill)
    local n = (skill.name or ""):lower()
    if skill.effect == EFF.REVIVE or (skill.rel == REL.FRIEND and skill.targetState == 2)
        or n:find("raise") or n:find("arise") or n:find("revive") or n:find("phoenix")
        or (skill.known and skill.known.use == "revive") then
        return "revive"
    end
    if skill.effect == EFF.CURE or (skill.known and skill.known.use == "cure") or n:find("esuna") then return "cure" end
    if isGuard(skill) or (skill.known and skill.known.use == "guard") then return "defend" end
    if (skill.rel == REL.FRIEND and skill.effect == EFF.DAMAGE and skill.paramType == PARAM.HP
        and (skill.varType == VAR.UP or skill.varType == VAR.RATIO))
        or (skill.known and skill.known.use == "heal") or n:find("cure") or n:find("cura") or n:find("curaga") or n:find("curaja") then
        return "heal"
    end
    if anyKey(skill.friendStatus) and skill.rel == REL.FRIEND and skill.effect ~= EFF.DAMAGE then return "buff" end
    if (skill.rel == REL.FRIEND or skill.target == TGT.FRIEND or skill.target == TGT.SELF) and (skill.known and skill.known.use == "buff") then return "buff" end
    if anyKey(skill.enemyStatus) and skill.rel == REL.ENEMY and (skill.power or 0) <= 0 and (skill.breakPower or 0) <= 0 then
        return "debuff"
    end
    if skill.effect == EFF.ANALYZE and (skill.power or 0) <= 0 and (skill.breakPower or 0) <= 0 then return nil end
    if skill.rel == REL.FRIEND or skill.target == TGT.FRIEND or skill.target == TGT.SELF or friendAction(skill) then
        return "buff"
    end
    if skill.effect == EFF.DAMAGE or (skill.power or 0) > 0 or (skill.breakPower or 0) > 0
        or skill.attr == ATTR.FIGHT or skill.attr == ATTR.ABILITY or skill.attr == ATTR.MAGIC
        or skill.attr == ATTR.LB or skill.attr == ATTR.FINISH or skill.attr == ATTR.SUMMON then
        return "damage"
    end
    return nil
end

-- Filled gauges, from the live limit points. IsEnableCommand is only the
-- fallback when the battle library does not answer. A full gauge is enough.
local function limitReady(uid, skill)
    local need = (skill and skill.lbCost) or 1
    if need < 1 then need = 1 end
    local bfl = battleLib()
    local points, one, slots, unitGauges = nil, nil, nil, nil
    if bfl and bfl:IsValid() then
        local ok, v
        ok, v = pcall(function() return bfl:GetUnitLimitBurstPoint(uid) end)
        if ok then points = num(v) end
        ok, v = pcall(function() return bfl:GetLimitBurstPointOneGauge() end)
        if ok then one = num(v) end
        if (one == nil) or (one <= 0) then
            ok, v = pcall(function() return bfl:GetLimitBurstPointOneGauge(uid) end)
            if ok then one = num(v) end
        end
        ok, v = pcall(function() return bfl:GetLimitBurstPointMaxGaugeNum() end)
        if ok then slots = num(v) end
        if slots == nil then
            ok, v = pcall(function() return bfl:GetLimitBurstPointMaxGaugeNum(uid) end)
            if ok then slots = num(v) end
        end
        ok, v = pcall(function() return bfl:GetUnitLimitBurstPointGaugeNum(uid) end)
        if ok then unitGauges = num(v) end
    end
    local p = paramOf(uid)
    if (points == nil) and p then
        local ok, v = pcall(function() return p:GetLimitBurstPoint() end)
        if ok then points = num(v) end
    end
    if points == nil then points = stat(uid, PARAM.LB, false) end
    local maxv = stat(uid, PARAM.LB, true)
    if ((one == nil) or (one <= 0)) and maxv and (maxv > 0) then
        local n = slots
        if (n == nil) or (n < 1) or (n > 4) then n = 1 end
        one = maxv / n
    end
    local filled = nil
    if (points ~= nil) and (one ~= nil) and (one > 0) then
        filled = math.floor((points / one) + 1e-6)
    end
    -- GaugeNum is trusted only after it has read empty once. A call that
    -- always returns 1 is the slot count, not a full crystal.
    if (filled == nil) and (unitGauges ~= nil) and (unitGauges >= 0) and (unitGauges <= 4) and Fight then
        Fight.lbGaugeApi = Fight.lbGaugeApi or {}
        if unitGauges == 0 then Fight.lbGaugeApi[uid] = true end
        if Fight.lbGaugeApi[uid] then filled = unitGauges end
    end
    if Fight then
        Fight.lbRead = Fight.lbRead or {}
        local bucket = filled
        if (bucket == nil) and (points ~= nil) then bucket = math.floor(points) end
        local prev = Fight.lbRead[uid]
        if prev ~= bucket then
            Fight.lbRead[uid] = bucket
            log("%s limit points %s max %s one %s slots %s unit %s needs %s",
                unitName(uid), tostring(points), tostring(maxv), tostring(one),
                tostring(slots), tostring(unitGauges), tostring(need))
            if (filled ~= nil) and (filled >= need) and ((type(prev) ~= "number") or (prev < need)) then
                appendLog("  " .. unitName(uid) .. " limit ready")
            end
        end
    end
    if filled == nil then return commandEnabled(uid, skill.id) end
    return filled >= need
end

local function tagSkill(uid, id, borrowed)
    if borrowed and activation(uid, id) ~= true then return nil end
    local s = skillOf(id)
    if not s or SKIP[s.attr] then return nil end
    local lb = limitSkill(s)
    if not borrowed and sealed(uid, id) and not lb then return nil end
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    copy.known = knownOf(copy)
    local info = copy.known
    -- A player-only row stays off the kit. The damage picker never sees it.
    if info and info.use == "skip" then return nil end
    local okKind, kind = pcall(classify, copy)
    copy.kind = okKind and kind or nil
    if copy.attr == ATTR.SUMMON and Espers.lookup then
        local fact = Espers.lookup(copy.name)
        if fact then
            if copy.known then
                local merged = {}
                for k, v in pairs(copy.known) do merged[k] = v end
                for k, v in pairs(fact) do
                    if merged[k] == nil then merged[k] = v end
                end
                if not merged.use then merged.use = "summon" end
                copy.known = merged
            else
                copy.known = fact
            end
        end
        if copy.known and copy.known.role == "guard" then copy.kind = "buff" end
    end
    -- The book is the role for a Limit Burst. A shared name on an ordinary
    -- skill stays a spell. known.lua still supplies a stagger the book omits.
    if copy.attr == ATTR.LB and Limits.lookup then
        local fact = Limits.lookup(copy.name)
        if fact then
            copy.known = Limits.apply(copy.known, fact)
            info = copy.known
        else
            local defaultUse = "lb-cash"
            local defaultKind = "damage"
            if copy.effect == EFF.REVIVE then
                defaultUse = "lb-revive"
                defaultKind = "revive"
            elseif copy.effect == EFF.CURE then
                defaultUse = "heal"
                defaultKind = "heal"
            elseif copy.effect == EFF.PARAM or copy.effect == EFF.COVER then
                defaultUse = "lb-setup"
                defaultKind = "buff"
            end
            copy.known = copy.known or { use = defaultUse, stagger = 35, gauges = 1 }
            info = copy.known
            copy.kind = copy.kind or defaultKind
            if copy.name and Fight then
                Fight.limitUntagged = Fight.limitUntagged or {}
                local key = foldName(copy.name)
                if (key ~= "") and (not Fight.limitUntagged[key]) then
                    Fight.limitUntagged[key] = true
                    local line = "limit " .. copy.name .. " defaulted to " .. defaultUse
                    log("%s", line)
                    appendLog("  " .. line)
                end
            end
        end
    end
    if info then
        if info.stagger then copy.breakPower = info.stagger end
        if info.use == "guard" then copy.kind = "defend"
        elseif info.use == "opener" or info.use == "guardbuff" or info.use == "buff" or info.use == "lb-setup" then
            copy.kind = "buff"
        elseif info.use == "lb-revive" then copy.kind = "revive"
        elseif info.use == "heal" then copy.kind = "heal"
        elseif info.use == "cure" then copy.kind = "cure"
        elseif info.use == "debuff" then copy.kind = "debuff"
        elseif info.use == "scan" then copy.kind = "scan"
        elseif info.use == "steal" then copy.kind = "steal"
        elseif info.use == "provoke" then copy.kind = "provoke"
        elseif info.use == "finish" then
            if copy.kind ~= "heal" and copy.kind ~= "buff" then copy.kind = "damage" end
        elseif copy.kind ~= "heal" and copy.kind ~= "buff" and copy.kind ~= "revive"
            and copy.kind ~= "cure" and copy.kind ~= "defend" and copy.kind ~= "debuff" then
            copy.kind = "damage"
        end
    end
    if copy.effect == EFF.ANALYZE then copy.kind = "scan" end
    copy.cost = skillCost(uid, id, aoeOf(copy))
    if limitSkill(copy) then
        local gauges = nil
        if info and (type(info.gauges) == "number") and (info.gauges >= 1) then
            gauges = info.gauges
        end
        if gauges == nil then
            local raw = copy.cost or 0
            if (raw >= 1) and (raw <= 2) then gauges = raw end
        end
        if gauges == nil then gauges = 1 end
        copy.lbCost = gauges
        copy.cost = 0
        if (not borrowed) and (not limitReady(uid, copy)) then return nil end
    end
    if not copy.kind then return nil end
    return copy
end

unitKit = function(uid)
    if not Fight then return nil end
    Fight.kits = Fight.kits or {}
    local cached = Fight.kits[uid]
    if cached then return cached end
    local kit = { spells = {}, healCost = 0, healScore = 0, tankScore = 0 }
    local cureCost, raiseCost = 0, 0
    for _, id in ipairs(equippedIds(uid)) do
        local s = skillOf(id)
        if s and (s.attr == ATTR.FINISH or s.attr == ATTR.SUMMON or s.attr == ATTR.LB) then
        elseif s then
            local copy = tagSkill(uid, id, false)
            if copy and copy.attr ~= ATTR.FINISH and copy.attr ~= ATTR.SUMMON and copy.attr ~= ATTR.LB then
                kit.spells[#kit.spells + 1] = copy
                local info = copy.known
                local score = 0
                if info and info.patch then score = 1
                elseif copy.kind == "heal" or (info and info.use == "heal") then score = 50 + (copy.power or 0) end
                if score > kit.healScore then kit.healScore = score end
                if copy.kind == "heal" and score >= 50 and (copy.cost or 0) > 0 then
                    if cureCost == 0 or copy.cost < cureCost then cureCost = copy.cost end
                end
                if copy.kind == "revive" and (copy.cost or 0) > 0 then
                    if raiseCost == 0 or copy.cost < raiseCost then raiseCost = copy.cost end
                end
                local sn = copy.name and copy.name:lower() or ""
                if copy.effect == EFF.COVER or copy.effect == EFF.DEFEND
                    or copy.kind == "provoke" or copy.kind == "cover"
                    or (info and (info.use == "provoke" or info.use == "cover"))
                    or sn:find("provoke") or sn:find("cover") or sn:find("sentinel") or sn:find("roar") then
                    kit.tankScore = (kit.tankScore or 0) + 50
                end
            end
        end
    end
    local sawFight = false
    for _, s in ipairs(kit.spells) do
        if s.attr == ATTR.FIGHT then sawFight = true end
    end
    if not sawFight and SkillIdx then
        for id, s in pairs(SkillIdx) do
            if s.attr == ATTR.FIGHT then
                local copy = tagSkill(uid, id, true)
                if copy then kit.spells[#kit.spells + 1] = copy end
                break
            end
        end
    end
    kit.healCost = (cureCost > 0) and cureCost or raiseCost
    if #kit.spells > 0 then Fight.kits[uid] = kit end
    return kit
end

local function friendAction(skill)
    if skill.rel == REL.ENEMY then return false end
    if skill.rel == REL.FRIEND then return true end
    local n = skill.name and skill.name:lower() or ""
    if n:find("cover") or n:find("sentinel") then return true end
    if skill.kind == "heal" or skill.kind == "revive" or skill.kind == "buff"
        or skill.kind == "cure" or skill.kind == "defend" then
        return true
    end
    return false
end

local function legalize(uid, skill, targets, isAll)
    if skill.target == TGT.SELF then return targets, false end
    local rel = REL.ENEMY
    if friendAction(skill) then rel = REL.FRIEND end
    local legal = targetsFor(uid, skill, rel)
    if #legal == 0 then return targets, isAll end
    if isAll or aoeOf(skill) then return legal, true end
    for _, id in ipairs(targets or {}) do
        for _, l in ipairs(legal) do
            if id == l then return { id }, false end
        end
    end
    return { legal[1] }, false
end

local function finishChoice(uid, skill, reason, targets, isAll, isItem)
    local ids, all = targets, isAll
    if not isItem then
        ids, all = legalize(uid, skill, targets, isAll)
    end
    if not ids or #ids == 0 then
        log("%s: %s has no legal target", unitName(uid), skill.name)
        return nil
    end
    return {
        id = skill.id, name = skill.name, score = 1, cost = skill.cost or 0,
        kind = skill.kind, reason = reason, targets = ids, isAll = all and true or false,
        attr = skill.attr, isItem = isItem and true or false, known = skill.known,
    }
end

local function idsOf(list)
    local t = {}
    for _, u in ipairs(list or {}) do t[#t + 1] = u.id end
    return t
end

local function lowestAlly(w, pred)
    local best, bestR = nil, 2
    for _, u in ipairs(w.allies) do
        if not u.dead and (not pred or pred(u)) then
            local r = u.hp or 1
            if r < bestR then best, bestR = u, r end
        end
    end
    return best
end

local function firstDead(w, pred)
    for _, u in ipairs(w.allies) do
        if u.dead and (not pred or pred(u)) then return u end
    end
    return nil
end

local function lockedAlly(w)
    if Health.locked then return Health.locked(w.allies) end
    local body = nil
    for _, u in ipairs(w.allies) do
        if not u.dead and u.statuses then
            local hit = false
            for id in pairs(LOCK) do
                if u.statuses[id] then hit = true end
            end
            if hit then
                if u.acts ~= false then return u end
                body = body or u
            end
        end
    end
    return body
end

local itemsLogged = false
local potLogged = false

local function findPot(w)
    if not w or not w.enemies then return nil end
    for _, u in ipairs(w.enemies) do
        local n = (u.name or ""):lower()
        if n == "pot" or n:find("pot", 1, true) then
            return u
        end
    end
    return nil
end

local function potFight(w)
    local pot = findPot(w)
    if pot then
        if not potLogged then
            potLogged = true
            log("pot fight detected: %s encountered", pot.name or "Magic Pot")
        end
        return true
    end
    return false
end

local function saysYes(obj, method, id)
    if not (obj and obj.IsValid and obj:IsValid()) then return false end
    local ok, v = pcall(function() return obj[method](obj, id) end)
    return ok and (v == true or v == 1)
end

local function addItemId(ids, v)
    local n = num(v)
    if not n and type(v) == "userdata" then
        n = num(field(v, "ID")) or num(field(v, "ItemId")) or num(field(v, "itemId"))
        if not n then
            local ok, inner = pcall(function() return v:get() end)
            n = ok and num(inner) or nil
        end
    end
    if n and n > 0 then ids[n] = true end
end

local function eachItemArray(arr, ids)
    if type(arr) == "table" then
        for _, v in pairs(arr) do addItemId(ids, v) end
        return
    end
    if type(arr) ~= "userdata" then return end
    if arr.ForEach then
        pcall(function()
            arr:ForEach(function(_, e) addItemId(ids, e) end)
        end)
    end
    for i = 1, 400 do
        local ok, v = pcall(function() return arr[i] end)
        if not ok or v == nil then break end
        addItemId(ids, v)
    end
end

local function ownedRecovery(allowHeld)
    buildSkillIndex()
    local ids = {}
    local function take(list)
        if not list then return end
        for _, v in ipairs(list) do addItemId(ids, v) end
    end
    local bfl, lib = battleLib(), itemLib()
    if bfl and bfl:IsValid() then take(fill(function(t) bfl:GetConsumableItemList(t) end)) end
    if lib and lib:IsValid() then
        local ok, arr = pcall(function() return lib:GetAllItemIdListByType(1) end)
        if ok then eachItemArray(arr, ids) end
        take(fill(function(t) lib:GetAllItemIdListByType(t, 1) end))
        take(fill(function(t) lib:GetConsumableItemList(t) end))
        take(fill(function(t) lib:GetInventoryItemIdListByConsumableType(t, 1) end))
        take(fill(function(t) lib:GetInventoryAllItemIdList(t) end))
    end
    local out = {}
    local catalog = 0
    for _ in pairs(ids) do catalog = catalog + 1 end
    for id in pairs(ids) do
        local count = nil
        if lib and lib:IsValid() then
            local ok, n = pcall(function() return lib:GetInventoryItemNum(id) end)
            count = ok and num(n) or nil
            if count == nil then
                ok, n = pcall(function() return lib:GetConsumableItemNum(id) end)
                count = ok and num(n) or nil
            end
        end
        if count and count > 0 then
            local row = ItemIdx and ItemIdx[id] or nil
            local name = nil
            if lib and lib:IsValid() then
                local ok, n = pcall(function() return lib:GetItemName(id):ToString() end)
                if ok and type(n) == "string" and n ~= "" then name = n end
            end
            if not name or name == "" then name = row and row.name or ("item " .. id) end
            local lowered = name:lower()
            local listed = Known.items and Known.items[lowered]
            local heldBack = (Known.leave and Known.leave[lowered])
                or lowered:find("scroll", 1, true)
            local common = allowHeld or (not (row and row.rare) and not heldBack)
            if common then
                local hp, mp, kind, amount, mpAmount, isParty, revivePower, tier = false, false, nil, nil, nil, false, 0.2, 1
                if listed == "hp" then hp, kind = true, "heal" end
                if listed == "mp" or lowered:find("ether", 1, true) then mp = true end
                if listed == "revive" then kind = "revive" end
                if listed == "cure" then kind = "cure" end
                if row and row.skillId then
                    local s = skillOf(row.skillId)
                    if s then
                        if Health.FIXED and (s.calc == Health.FIXED) and ((s.power or 0) > 0) then
                            amount = s.power
                        end
                        if s.effect == EFF.REVIVE or (s.rel == REL.FRIEND and s.targetState == 2) then kind = "revive" end
                        if s.effect == EFF.CURE then kind = "cure" end
                        if s.rel == REL.FRIEND and s.effect == EFF.DAMAGE and s.paramType == PARAM.HP
                            and (s.varType == VAR.UP or s.varType == VAR.RATIO) then
                            hp = true
                            kind = "heal"
                        end
                        if s.rel == REL.FRIEND and s.paramType == PARAM.MP
                            and (s.varType == VAR.UP or s.varType == VAR.RATIO) then
                            mp = true
                        end
                    end
                end
                if saysYes(bfl, "IsAbleRecoverHitPoint", id) or saysYes(lib, "IsAbleRecoverHitPoint", id) then hp = true end
                if saysYes(bfl, "IsAbleRecoverMagicPoint", id) or saysYes(lib, "IsAbleRecoverMagicPoint", id) then mp = true end

                -- Match known item power metadata for mathematically optimal selection
                local kPower = Known.itemPower and (Known.itemPower[lowered] or Known.itemPower[name:lower()])
                if kPower then
                    if kPower.hp then
                        hp = true
                        kind = kind or "heal"
                        if not amount or amount <= 0 then amount = kPower.hp end
                    end
                    if kPower.mp then
                        mp = true
                        if not mpAmount or mpAmount <= 0 then mpAmount = kPower.mp end
                    end
                    if kPower.party then isParty = true end
                    if kPower.revive then
                        kind = "revive"
                        revivePower = kPower.revive
                    end
                    if kPower.cureAll then kind = "cure" end
                    tier = kPower.tier or tier
                end

                if lowered:find("mist", 1, true) or lowered:find("mega", 1, true) then
                    isParty = true
                end

                local element = nil
                if listed == "fire" or listed == "ice" or listed == "thunder"
                    or listed == "water" or listed == "earth" or listed == "wind"
                    or listed == "light" or listed == "dark" then
                    element = listed
                    kind = "offense"
                end
                if listed == "slow" then
                    kind = "tactical-debuff"
                end
                if hp or mp or kind == "revive" or kind == "cure" or element or kind == "tactical-debuff" then
                    out[#out + 1] = {
                        id = id, name = name, hp = hp, mp = mp, kind = kind,
                        element = element,
                        count = count, amount = amount, mpAmount = mpAmount,
                        party = isParty, revivePower = revivePower, tier = tier,
                    }
                end
            end
        end
    end
    if not itemsLogged then
        itemsLogged = true
        if #out == 0 then
            log("bag: no potion, ether, or phoenix down (%d item ids answered)", catalog)
        else
            local bits = {}
            for _, it in ipairs(out) do
                local tag = it.kind or (it.mp and "mp") or (it.hp and "hp") or "item"
                bits[#bits + 1] = string.format("%s x%s %s", it.name, tostring(it.count), tag)
            end
            log("bag: %s", table.concat(bits, ", "))
        end
    end
    return out
end

local function itemChoice(uid, item, reason, targetId, use)
    local isAoe = item.party or (type(targetId) == "table" and #targetId > 1)
    local targetType = isAoe and TGT.ALL or TGT.SINGLE
    local tids = type(targetId) == "table" and targetId or { targetId }
    local fake = { id = item.id, name = item.name, kind = "item", attr = ATTR.ITEM, target = targetType, cost = 0, tier = item.tier, party = item.party }
    local choice = finishChoice(uid, fake, reason, tids, isAoe, true)
    if choice then
        choice.itemUse = use
        choice.tier = item.tier
        choice.party = item.party
    end
    return choice
end

-- Magic Pot Item Discovery: Finds the best suited Ether or restorative item to satisfy the pot
local function findEtherItem()
    -- Priority 1: Common basic "Ether"
    local common = ownedRecovery(false)
    for _, it in ipairs(common) do
        local n = (it.name or ""):lower()
        if n == "ether" and (it.count == nil or it.count > 0) then return it end
    end
    -- Priority 2: Other common ethers (e.g. Hi-Ether, Mist Ether)
    for _, it in ipairs(common) do
        local n = (it.name or ""):lower()
        if n:find("ether", 1, true) and (it.count == nil or it.count > 0) then return it end
    end
    -- Priority 3: Rare/Held-back Ethers (Turbo Ether, X-Ether, Mist Turbo Ether)
    local allItems = ownedRecovery(true)
    for _, it in ipairs(allItems) do
        local n = (it.name or ""):lower()
        if n:find("ether", 1, true) and (it.count == nil or it.count > 0) then return it end
    end
    -- Priority 4: Elixir if no ethers exist in bag
    for _, it in ipairs(allItems) do
        local n = (it.name or ""):lower()
        if (n:find("elixir", 1, true) or it.mp) and (it.count == nil or it.count > 0) then return it end
    end
    return nil
end

local function pickPotGift(uid, w, pot)
    if not pot then return nil end
    local ether = findEtherItem()
    if ether then
        return itemChoice(uid, ether, string.format("pot puzzle: give %s to %s", ether.name, pot.name), pot.id, "pot")
    end
    return nil
end

local function pickTacticalItem(uid, w, foe)
    if potFight(w) or not foe then return nil end
    local items = ownedRecovery()
    for _, it in ipairs(items) do
        if it.element then
            local factor = elementFactor({ known = { element = it.element } }, foe)
            if factor >= 3 then
                return itemChoice(uid, it, string.format("tactical item %s (%s weakness) %s", it.name, it.element, foe.name), foe.id, "offense")
            end
        end
    end
    return nil
end

local function pickRecoveryItem(uid, w, want)
    if potFight(w) then return nil end
    local isBoss = w.boss or hardField or (#w.enemies == 1)

    -- In boss fights or tough encounters, always unlock all held/rare items
    local allowHeld = isBoss or false

    -- Check for party danger
    local dangerCount = 0
    local fallenCount = 0
    for _, a in ipairs(w.allies or {}) do
        if a.dead then
            fallenCount = fallenCount + 1
        elseif (a.hp or 1) < 0.35 then
            dangerCount = dangerCount + 1
        end
    end
    if dangerCount >= 1 or fallenCount >= 1 then
        allowHeld = true
    end

    local items = ownedRecovery(allowHeld)
    if #items == 0 then
        items = ownedRecovery(true)
    end
    if #items == 0 then return nil end

    if want == "revive" then
        local deadAllies = {}
        for _, u in ipairs(w.allies or {}) do
            local cur = stat(u.id, PARAM.HP, false)
            local reallyDead = (cur ~= nil and cur <= 0) or (cur == nil and u.dead and (u.hp or 0) <= 0)
            if reallyDead then deadAllies[#deadAllies + 1] = u end
        end
        if #deadAllies == 0 then return nil end

        -- Target priority: prefer unclaimed fallen allies so multiple party members revive different heroes concurrently!
        local target = nil
        for _, u in ipairs(deadAllies) do
            if not Fight.claim.revive[u.id] then
                target = u
                break
            end
        end
        if not target then
            target = (Health.fallen and Health.fallen(w.allies, unitKit, offenseOf))
                or deadAllies[1]
        end
        if not target then return nil end

        -- Absolute Live HP Guard: NEVER consume a revive item on an ally whose HP > 0!
        local targetLiveHp = stat(target.id, PARAM.HP, false)
        if targetLiveHp ~= nil and targetLiveHp > 0 then return nil end

        -- 1. If 2+ allies down, look for party revive (Mega Phoenix)
        if #deadAllies >= 2 then
            for _, it in ipairs(items) do
                if it.kind == "revive" and it.party then
                    return itemChoice(uid, it, string.format("mega revive party (%d fallen)", #deadAllies), idsOf(deadAllies), "revive")
                end
            end
        end

        -- 2. Single target revive: pick best revive item
        -- On bosses or when reviving key units, prioritize Phoenix Pinion (100% HP revive)
        local bestRevive, bestTier = nil, -1
        for _, it in ipairs(items) do
            if it.kind == "revive" and not it.party then
                local t = it.tier or 1
                if (isBoss or #deadAllies >= 2) and t >= 2 and t > bestTier then
                    bestRevive, bestTier = it, t
                elseif not bestRevive or (bestTier < 2 and t > bestTier) then
                    bestRevive, bestTier = it, t
                end
            end
        end

        if not bestRevive then
            for _, it in ipairs(items) do
                if it.kind == "revive" then bestRevive = it break end
            end
        end

        if bestRevive then
            local isParty = bestRevive.party or false
            local tids = isParty and idsOf(deadAllies) or target.id
            return itemChoice(uid, bestRevive, "item raise " .. target.name .. (bestRevive.tier and bestRevive.tier >= 2 and " (High Tier)" or ""), tids, "revive")
        end
        return nil
    end

    if want == "heal" then
        local hurt = lowestAlly(w)
        if not hurt then return nil end

        -- Count wounded allies
        local hurtCount = 0
        local totalMissing = 0
        for _, a in ipairs(w.allies or {}) do
            if not a.dead and (a.hp or 1) < 0.75 then
                hurtCount = hurtCount + 1
                local mHp = stat(a.id, PARAM.HP, true) or 2000
                totalMissing = totalMissing + (1 - (a.hp or 1)) * mHp
            end
        end

        -- 1. If 2+ allies hurt and total deficit >= 1000 HP, prioritize Mist Potion / Mist Hi-Potion / Megalixir
        if hurtCount >= 2 and totalMissing >= 1000 then
            local bestPartyHeal, bestPartyTier = nil, -1
            for _, it in ipairs(items) do
                if (it.hp or it.kind == "heal") and it.party then
                    local t = it.tier or 1
                    if totalMissing >= 3000 and t >= 2 then
                        if t > bestPartyTier then bestPartyHeal, bestPartyTier = it, t end
                    elseif not bestPartyHeal or t > bestPartyTier then
                        bestPartyHeal, bestPartyTier = it, t
                    end
                end
            end
            if bestPartyHeal then
                return itemChoice(uid, bestPartyHeal, string.format("item party heal (%d allies hurt, -%d HP)", hurtCount, math.floor(totalMissing)), idsOf(w.allies), "hp")
            end
        end

        -- 2. Single target healing: calculate missing HP
        local maxv = stat(hurt.id, PARAM.HP, true) or 2000
        local ratio = hurt.hp or 1
        local missing = math.max(0, (1 - ratio) * maxv)

        -- Check for Elixir condition: critically low HP (< 25%) AND critically low MP (< 25%)
        local curMp = stat(hurt.id, PARAM.MP, false) or 100
        local maxMp = stat(hurt.id, PARAM.MP, true) or 100
        local mpRatio = maxMp > 0 and (curMp / maxMp) or 1
        if ratio < 0.25 and mpRatio < 0.25 and (isBoss or dangerCount >= 2) then
            for _, it in ipairs(items) do
                local n = (it.name or ""):lower()
                if n:find("elixir") and not it.party then
                    return itemChoice(uid, it, string.format("emergency elixir %s (HP %d%%, MP %d%%)", hurt.name, math.floor(ratio * 100), math.floor(mpRatio * 100)), hurt.id, "hp")
                end
            end
        end

        -- 3. Select best potion matching the deficit
        local it = (Health.choosePotion and Health.choosePotion(items, missing))
        if not it then
            local bestHp, maxAmt = nil, -1
            for _, candidate in ipairs(items) do
                if (candidate.hp or candidate.kind == "heal") and not candidate.party then
                    local amt = candidate.amount or 0
                    if amt > maxAmt then bestHp, maxAmt = candidate, amt end
                end
            end
            it = bestHp
        end
        if not it then
            for _, candidate in ipairs(items) do
                if candidate.hp or candidate.kind == "heal" then it = candidate break end
            end
        end

        if it then
            local pct = math.floor((hurt.hp or 0) * 100 + 0.5)
            local isParty = it.party or false
            local tids = isParty and idsOf(w.allies) or hurt.id
            return itemChoice(uid, it, string.format("item heal %s (%s) at %d%%", hurt.name, it.name, pct), tids, "hp")
        end
        return nil
    end

    if want == "cure" then
        local who = lockedAlly(w)
        if not who then return nil end

        -- Check how many allies have status locks
        local lockedCount = 0
        for _, a in ipairs(w.allies or {}) do
            if not a.dead and lockedAllyUnit and lockedAllyUnit(a) then
                lockedCount = lockedCount + 1
            end
        end

        -- 1. If multiple allies locked, prefer party cure (Unicorn Horn)
        if lockedCount >= 2 then
            for _, it in ipairs(items) do
                if it.kind == "cure" and it.party then
                    return itemChoice(uid, it, string.format("party cure (%d allies afflicted)", lockedCount), idsOf(w.allies), "cure")
                end
            end
        end

        -- 2. Universal cure (Remedy) vs specific cure
        local remedy = nil
        local specific = nil
        for _, it in ipairs(items) do
            if it.kind == "cure" then
                local n = (it.name or ""):lower()
                if n == "remedy" then
                    remedy = it
                elseif Health.itemClears and Health.itemClears(it.name, who.statuses) then
                    specific = it
                    break
                elseif not specific then
                    specific = it
                end
            end
        end
        local it = specific or remedy
        if it then
            return itemChoice(uid, it, string.format("item cure %s (%s)", who.name, it.name), who.id, "cure")
        end
        return nil
    end

    if want == "mp" then
        local curMp = stat(uid, PARAM.MP, false) or 0
        local maxMp = stat(uid, PARAM.MP, true) or 100
        local missingMp = math.max(0, maxMp - curMp)

        -- 1. Check if multiple allies are low on MP (< 25%)
        local emptyMages = 0
        for _, a in ipairs(w.allies or {}) do
            if not a.dead then
                local c = stat(a.id, PARAM.MP, false) or 0
                local m = stat(a.id, PARAM.MP, true) or 100
                if m > 50 and (c / m) < 0.25 then emptyMages = emptyMages + 1 end
            end
        end

        if emptyMages >= 2 then
            for _, it in ipairs(items) do
                if it.mp and it.party and it.kind ~= "revive" then
                    return itemChoice(uid, it, string.format("mist ether party (%d casters low)", emptyMages), idsOf(w.allies), "mp")
                end
            end
        end

        -- 2. Choose the Ether best matching missingMp
        local it = (Health.chooseEther and Health.chooseEther(items, missingMp))
        if not it then
            local cover, coverAmt, best, bestAmt = nil, 999999, nil, -1
            for _, candidate in ipairs(items) do
                if candidate.mp and candidate.kind ~= "revive" and not candidate.party then
                    local amt = candidate.mpAmount or candidate.amount or 50
                    if amt >= missingMp and amt < coverAmt then
                        cover, coverAmt = candidate, amt
                    end
                    if amt > bestAmt then best, bestAmt = candidate, amt end
                end
            end
            it = cover or best
        end
        if not it then
            for _, candidate in ipairs(items) do
                if candidate.mp and candidate.kind ~= "revive" then it = candidate break end
            end
        end

        if it then
            local isParty = it.party or false
            local tids = isParty and idsOf(w.allies) or uid
            return itemChoice(uid, it, string.format("ether %s (%s, -%d MP)", unitName(uid), it.name, missingMp), tids, "mp")
        end
        return nil
    end
    return nil
end

--------------------------------------------------------------------------------
-- The field. The break ratio stays full, so the book gauge is the count.
--------------------------------------------------------------------------------

local function worldOf(uid, boss, summoned)
    local function gaugeOf(id, name)
        local apiLeft = breakLeft(id)
        local card = mobOf({ id = id, name = name })
        local gauge = card and tonumber(card.gauge) or nil
        if Fight then
            Fight.poured = Fight.poured or {}
            Fight.down = Fight.down or {}
            Fight.downTold = Fight.downTold or {}
            Fight.relax = Fight.relax or {}
            Fight.broke = Fight.broke or {}
            Fight.gaugeScale = Fight.gaugeScale or {}
            Fight.brokeOn = Fight.brokeOn or {}
            local scaled = Fight.gaugeScale[id]
            if scaled and (not gauge or scaled > gauge) then gauge = scaled end
        end
        local poured = (Fight and Fight.poured and Fight.poured[id]) or 0
        local down = (Fight and Fight.down and Fight.down[id]) and true or false
        local relaxed = Fight and Fight.relax and Fight.relax[id]
        local unmarked = Fight and Fight.unmarked and (not down)
        if unmarked and Fight and (not Fight.unmarkedTold) then
            Fight.unmarkedTold = true
            log("stagger counts unmarked. chipping from the book until a break shows")
            appendLog("  stagger counts unmarked")
        end
        if (not unmarked) and Fight and gauge and (gauge > 0) and (poured >= gauge) and (not relaxed) then
            Fight.down[id] = true
            Fight.brokeOn = Fight.brokeOn or {}
            Fight.brokeOn[id] = true
            down = true
            if not Fight.downSince then Fight.downSince = #(Fight.actions or {}) end
        end
        if down and Fight and not Fight.downTold[id] then
            Fight.downTold[id] = true
            local by = Fight.last and (Fight.last.who .. " (" .. Fight.last.skill .. ")") or "the party"
            Fight.broke[#Fight.broke + 1] = name .. " by " .. by
            appendLog("  broke: " .. name .. " by " .. by)
            log("%s staggered (%s/%s). bonus cashes them, next gauge is one still up",
                name, tostring(math.floor(poured + 0.5)), tostring(gauge or "?"))
        end
        local left = apiLeft
        if down then
            left = 0
        elseif unmarked then
            left = apiLeft
        elseif gauge and (gauge > 0) then
            local est = 1 - (poured / gauge)
            if est < 0 then est = 0 end
            if est > 1 then est = 1 end
            if relaxed and poured >= gauge then est = 0.15 end
            if apiLeft >= 0.99 then
                left = est
            elseif apiLeft < est then
                left = apiLeft
            else
                left = est
            end
        end
        return down and true or false, left
    end
    if Fight then Fight.gaugeOf = gaugeOf end
    local allies, enemies = {}, {}
    for _, id in ipairs(friendIds()) do
        local r = hpRatio(id)
        allies[#allies + 1] = {
            id = id, name = unitName(id), hp = r or 1,
            dead = (r ~= nil and r <= 0) or false, statuses = statuses(id),
        }
    end
    if #allies == 0 then
        local r = hpRatio(uid)
        allies[1] = { id = uid, name = unitName(uid), hp = r or 1, dead = false, statuses = statuses(uid) }
    end
    if Fight then
        if not Fight.seenAlly then Fight.seenAlly = {} end
        for _, a in ipairs(allies) do
            if not a.dead then Fight.seenAlly[a.id] = a.name end
        end
        for id, name in pairs(Fight.seenAlly) do
            local found = false
            for _, a in ipairs(allies) do
                if a.id == id then found = true break end
            end
            if not found then
                local r = hpRatio(id)
                if r == nil or r <= 0 then
                    allies[#allies + 1] = { id = id, name = name, hp = 0, dead = true, statuses = {} }
                end
            end
        end
    end
    local seenFoe = {}
    local function addEnemy(id)
        if not id or seenFoe[id] then return end
        if not keepFoe(id) then return end
        local r = hpRatio(id)
        if r ~= nil and r <= 0 then
            if Fight and Fight.seenFoe then Fight.seenFoe[id] = nil end
            return
        end
        seenFoe[id] = true
        local name = unitName(id)
        local isBroken, left = gaugeOf(id, name)
        enemies[#enemies + 1] = {
            id = id, name = name, hp = r or 1,
            broken = isBroken, breakLeft = left, statuses = statuses(id),
        }
        if Fight then
            Fight.seenFoe = Fight.seenFoe or {}
            Fight.seenFoe[id] = name
        end
    end
    for _, id in ipairs(members(REL.ENEMY)) do addEnemy(id) end
    local bfl = battleLib()
    if bfl and bfl:IsValid() then
        for n = 0, 15 do
            local ok, p = pcall(function() return bfl:GetBattleUnitParameter(n, true) end)
            if ok and p and p.IsValid and p:IsValid() then
                local okR, rel = pcall(function() return p:GetRelation() end)
                if okR and num(rel) == REL.ENEMY then addEnemy(n) end
            end
        end
    end
    if Fight and Fight.seenFoe then
        for id in pairs(Fight.seenFoe) do addEnemy(id) end
    end
    for _, a in ipairs(allies) do
        local kit = unitKit(a.id)
        a.acts = (kit and kit.spells and #kit.spells > 0) and true or false
    end
    local mp, maxMp = stat(uid, PARAM.MP, false) or 0, stat(uid, PARAM.MP, true) or 0
    return {
        selfId = uid, mp = mp, maxMp = maxMp,
        allies = allies, enemies = enemies, boss = boss, summoned = summoned,
        usedSupport = {},
    }
end

local function bossBattle()
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return false end
    local ok, v = pcall(function() return bfl:IsBossBattle() end)
    return ok and v == true
end

--------------------------------------------------------------------------------
-- Sending a command the way a menu choice does.
--------------------------------------------------------------------------------

local Menu = {
    open = false, serial = 0, actor = -1, decided = true, sub = false,
    byMod = false,
}
local Template = {}
Fight = {
    boss = false, summoned = false,
    actions = {}, casts = {}, castOrder = {}, usedSupport = {}, broke = {}, fell = {},
    scanned = {}, elemRun = {}, seenAlly = {},
    resonanceSent = false, resonanceMiss = false,
    last = nil, prev = {}, active = false, number = 0,
    poured = {}, down = {}, downTold = {}, relax = {}, gaugeScale = {}, brokeOn = {}, gaugeSure = {}, gaugeWas = {},
    downSince = nil, phaseSeen = 0, bonusSeen = false, lastHit = nil, line = false,
    prevHit = nil, building = nil, kits = {},
    claim = { heal = {}, revive = {}, hone = {}, ether = {}, scan = {}, etherRound = false, guard = false, esper = false, lb = false },
    debuffOn = {}, debuffSeen = {}, debuffTold = {},
    went = {}, rounds = 0, seenFoe = {}, planTag = nil, afterBonus = false,
    fieldTold = false, chipped = false,
    esperOut = nil, esperTold = false, esperSkip = {},
    limitUntagged = {}, limitSkip = {},
    cureHeld = false,
    healLeft = {},
}

local function currentActor()
    local ss = FindFirstOf("CPP_UI_BattleSubsystem")
    if not (ss and ss:IsValid()) then return -1 end
    return num(ss.CurrentActionUnitUniqueId) or -1
end

local function currentPhase()
    local ss = FindFirstOf("CPP_UI_BattleSubsystem")
    if not (ss and ss:IsValid()) then return 0 end
    return num(ss.BtlPhaseType) or 0
end

local function inFinishPhase()
    if currentPhase() == PHASE_FINISH then return true end
    local bfl = battleLib()
    if not (bfl and bfl:IsValid()) then return false end
    local ok, v = pcall(function() return bfl:IsFinishPhase() end)
    return ok and v == true
end

local function learn(v)
    local items = {}
    local list = v.cmdDecideDataList
    if not (list and list.ForEach) then return end
    list:ForEach(function(_, e)
        local d = unwrap(e)
        if not d then return end
        local params = {}
        if d.ParameterList and d.ParameterList.ForEach then
            d.ParameterList:ForEach(function(_, x)
                local n = num(x)
                if n then params[#params + 1] = n end
            end)
        end
        items[#items + 1] = {
            actionId = num(d.actionId),
            isUseItem = d.isUseItem and true or false,
            IsAll = d.IsAll and true or false,
            pCat = d.ParentActionKey and num(d.ParentActionKey.Category) or 1,
            pId = d.ParentActionKey and num(d.ParentActionKey.ID) or 0,
            params = params,
        }
    end)
    if #items == 0 or not items[1].actionId then return end
    local keys = {}
    if v.actionKeys and v.actionKeys.ForEach then
        v.actionKeys:ForEach(function(_, e)
            local k = unwrap(e)
            if k then keys[#keys + 1] = { num(k.Category) or 0, num(k.ID) or 0 } end
        end)
    end
    Template[items[1].actionId] = {
        CmdType = num(v.CmdType) or 0,
        isNotConsume = v.isNotConsume and true or false,
        doCalcOrder = v.doCalcOrder ~= false,
        CommandId = num(v.CommandId) or -1,
        item = items[1],
        keys = keys,
    }
end

local function send(uid, choice, phase)
    if phase == PHASE_FINISH or inFinishPhase() then
        log("SAFETY GUARD: Refusing to dispatch Delegate.Battle.Cmd.Decide during Resonance/Finish phase (prevents stack overflow crash)")
        return false
    end
    local learned = (not choice.isItem) and Template[choice.id] or nil
    local cmdType = phase
    local commandId = choice.id
    local isNotConsume, doCalcOrder = false, true
    local pCat, pId = 1, choice.id
    local keys = { { 1, choice.id } }
    if learned then
        commandId = learned.CommandId
        isNotConsume = learned.isNotConsume
        doCalcOrder = learned.doCalcOrder
        pCat = learned.item.pCat or pCat
        pId = learned.item.pId or pId
        if #learned.keys > 0 then keys = learned.keys end
    else
        local limitCast = choice.attr == ATTR.LB
        if choice.known then
            local use = choice.known.use
            if (use == "lb-setup") or (use == "lb-cash") or (use == "lb-revive") then limitCast = true end
        end
        local bfl = battleLib()
        if bfl and bfl:IsValid() and (not limitCast) and (not choice.isItem) then
            local ok, enabled = pcall(function() return bfl:IsEnableCommand(uid, choice.id) end)
            if ok and enabled == false then commandId = -1 end
        end
    end
    local cls = StaticFindObject("/Script/mucha.CPP_BtlCmdDecideDelegateVal")
    local disp = FindFirstOf("CPP_MuchaEventDispatcher")
    if not (cls and cls:IsValid() and disp and disp:IsValid()) then
        log("could not build a command")
        return false
    end
    local obj = StaticConstructObject(cls, disp)
    obj.CmdType = cmdType
    obj.isNotConsume = isNotConsume
    obj.doCalcOrder = doCalcOrder
    obj.CommandId = commandId
    obj.cmdDecideDataList[1] = { actionId = choice.id, actionUnitUniqueId = uid }
    local d = obj.cmdDecideDataList[1]
    d.actionId = choice.id
    d.actionUnitUniqueId = uid
    d.isUseItem = choice.isItem and true or false
    d.IsAll = choice.isAll and true or false
    d.ParentActionKey.Category = pCat
    d.ParentActionKey.ID = pId
    for i, tid in ipairs(choice.targets) do
        d.targetUnitUniqueIdList[i] = tid
    end
    local params = (learned and learned.item.params) or {}
    for i, p in ipairs(params) do
        d.ParameterList[i] = p
    end
    for i, k in ipairs(keys) do
        obj.actionKeys[i] = { Category = k[1], ID = k[2] }
        obj.actionKeys[i].Category = k[1]
        obj.actionKeys[i].ID = k[2]
    end
    Menu.byMod = true
    local sentOk, sentErr = pcall(function()
        disp:ExecuteEvent({ TagName = FName("Delegate.Battle.Cmd.Decide") }, obj)
    end)
    if not sentOk then
        Menu.byMod = false
        log("send failed: %s", tostring(sentErr))
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- The turn. Friends, the weakness, the gauge, then what the last actor changed.
--------------------------------------------------------------------------------

local function usableOf(uid)
    local usable = {}
    for _, id in ipairs(equippedIds(uid)) do
        local copy = tagSkill(uid, id, false)
        if copy then usable[#usable + 1] = copy end
    end
    local haveFight = false
    for _, s in ipairs(usable) do
        if s.attr == ATTR.FIGHT then haveFight = true end
    end
    if not haveFight and SkillIdx then
        for id, s in pairs(SkillIdx) do
            if s.attr == ATTR.FIGHT and activation(uid, id) == true then
                local copy = tagSkill(uid, id, true)
                if copy then usable[#usable + 1] = copy end
                break
            end
        end
    end
    return usable
end

local function pickFinish(uid, finishes, w)
    local list = {}
    for _, s in ipairs(finishes or {}) do
        if s.attr == ATTR.FINISH then list[#list + 1] = s end
    end
    if #list == 0 then return nil end

    local hurt, wounded = nil, 0
    for _, u in ipairs(w.allies or {}) do
        if not u.dead then
            if not hurt or (u.hp or 1) < (hurt.hp or 1) then hurt = u end
            if (u.hp or 1) < 0.35 then wounded = wounded + 1 end
        end
    end

    local function emit(skill, reason, targets, isAll, score)
        local choice = finishChoice(uid, skill, reason, targets, isAll)
        if choice then choice.score = score end
        return choice
    end

    -- 1. Emergency Healing / Revive Resonance Finisher:
    -- If ally is critically low (< 35% HP) or multiple allies are wounded, save the party immediately
    if hurt and ((hurt.hp or 1) < 0.35 or wounded >= 2) then
        for _, s in ipairs(list) do
            local heal = s.kind == "heal" or s.kind == "revive" or (s.known and s.known.use == "heal")
            if heal then
                local targets = partyOf(s) and idsOf(w.allies) or { hurt.id }
                local choice = emit(s, "resonance heal " .. hurt.name, targets, partyOf(s), 100000)
                if choice then return choice end
            end
        end
    end

    -- 2. Character Offensive Profile & Stat Multipliers:
    -- Physical attackers (Lasswell, Cloud, Rain, Squall) scale harder with physical finishers
    -- Magic nukers (Dark Fina, Sakura, Nichol) scale harder with magical finishers
    local uName = unitName(uid):lower()
    local isPhysDps = (uName:find("lasswell") ~= nil or uName:find("cloud") ~= nil or uName:find("sephiroth") ~= nil
        or uName:find("tidus") ~= nil or uName:find("squall") ~= nil or uName:find("rain") ~= nil or uName:find("raegen") ~= nil)
    local isMagDps = (uName:find("dark fina") ~= nil or uName:find("sakura") ~= nil or uName:find("archwitch") ~= nil
        or uName:find("shantotto") ~= nil or uName:find("rydia") ~= nil)

    local enemies = w.enemies or {}
    if #enemies == 0 then
        -- Default fallback if no enemies detected
        return emit(list[1], "resonance field", { uid }, false, 10)
    end

    -- 3. Comprehensive (Skill x Target) Multiplier & Synergy Evaluation for Maximum Damage
    local bestSkill, bestTarget, bestScore, bestReason, bestIsAll = nil, nil, -1, "", false

    for _, s in ipairs(list) do
        local support = s.kind == "heal" or s.kind == "buff" or s.kind == "revive"
            or (s.known and (s.known.use == "heal" or s.known.use == "buff" or s.known.use == "guardbuff"))
        
        if not support then
            local info = s.known or knownOf(s)
            local isPhys = (info and info.phys) or s.phys
            local isMag = (info and info.magic) or s.magic
            local basePow = offenseOf(s) or 100
            if basePow < 10 then basePow = 100 end

            -- Caster stat affinity bonus
            local casterScale = 1.0
            if isPhys and isPhysDps then casterScale = 1.35 end
            if isMag and isMagDps then casterScale = 1.35 end
            if uName:find("lasswell") ~= nil and isPhys then casterScale = casterScale * 1.25 end -- High Crit assassin burst

            local isAoE = aoeOf(s) or partyOf(s)

            if isAoE and #enemies > 1 then
                -- AoE Finisher: Evaluates total combined battle damage across all living enemies
                local totalAoeScore = 0
                local weaknessesHit = 0
                for _, u in ipairs(enemies) do
                    local factor = elementFactor(s, u)
                    if factor > 0 then
                        local enemyMult = (factor >= 3) and 2.5 or factor
                        if u.broken or broken(u.id) then enemyMult = enemyMult * 2.2 end
                        if factor >= 3 then weaknessesHit = weaknessesHit + 1 end
                        totalAoeScore = totalAoeScore + (basePow * enemyMult * casterScale)
                    end
                end
                
                if totalAoeScore > bestScore then
                    bestScore = totalAoeScore
                    bestSkill = s
                    bestTarget = enemies[1]
                    bestIsAll = true
                    bestReason = string.format("AoE Resonance Cleave (%d foes%s)",
                        #enemies, weaknessesHit > 0 and (", " .. weaknessesHit .. " weak") or "")
                end
            else
                -- Single-Target Finisher: Evaluates against each individual enemy to find optimal target
                for _, u in ipairs(enemies) do
                    local factor = elementFactor(s, u)
                    -- If target absorbs or nullifies this element, factor is 0 -> skip completely
                    if factor > 0 then
                        local mult = factor
                        local tags = {}

                        -- Elemental Weakness (3.0x in FFRS)
                        if factor >= 3 then
                            mult = mult * 2.5
                            tags[#tags + 1] = "Weakness x3"
                        elseif factor < 1.0 then
                            mult = mult * 0.4 -- Penalize resisted elements
                        end

                        -- Staggered / Broken Target Multiplier (2.2x damage & guaranteed Overkill drop payout!)
                        local isStaggered = u.broken or broken(u.id)
                        if isStaggered then
                            mult = mult * 2.2
                            tags[#tags + 1] = "STAGGERED x2.2"
                        end

                        -- Boss / High-Threat Priority (Ensures massive finisher isn't wasted on a 1-HP minion)
                        local isBoss = (Fight and Fight.boss and u.id == Fight.boss) or (u.name and u.name:lower():find("boss") ~= nil)
                        if isBoss then
                            mult = mult * 1.4
                            tags[#tags + 1] = "Boss Priority"
                        elseif (u.hp or 1) < 0.20 and not isStaggered then
                            mult = mult * 1.15
                            tags[#tags + 1] = "Execute"
                        end

                        -- Debuff Synergies (DEF Break, SPR Break)
                        local uStatuses = u.statuses or statuses(u.id) or {}
                        if isPhys and (uStatuses[32] or (Fight and Fight.debuffOn and Fight.debuffOn[u.id] and Fight.debuffOn[u.id]["def"])) then
                            mult = mult * 1.25
                            tags[#tags + 1] = "Def Broken"
                        end
                        if isMag and (uStatuses[33] or (Fight and Fight.debuffOn and Fight.debuffOn[u.id] and Fight.debuffOn[u.id]["spr"])) then
                            mult = mult * 1.25
                            tags[#tags + 1] = "Spr Broken"
                        end

                        local moveScore = basePow * mult * casterScale
                        if moveScore > bestScore then
                            bestScore = moveScore
                            bestSkill = s
                            bestTarget = u
                            bestIsAll = false
                            local tagStr = #tags > 0 and (" [" .. table.concat(tags, ", ") .. "]") or ""
                            bestReason = string.format("resonance %s on %s%s", s.name or "Finisher", u.name or "Foe", tagStr)
                        end
                    end
                end
            end
        end
    end

    if not bestSkill then
        bestSkill = list[1]
        bestTarget = enemies[1]
        bestScore = 10
        bestReason = "resonance default"
    end

    local tid = (bestTarget and bestTarget.id) or (Fight and Fight.building) or uid
    local targets = bestIsAll and idsOf(enemies) or { tid }
    return emit(bestSkill, bestReason, targets, bestIsAll, bestScore)
end

local function finishList(uid)
    local function asFinish(id)
        local s = skillOf(id)
        local copy = {}
        if s then
            for k, v in pairs(s) do copy[k] = v end
        else
            copy.id = id
            copy.name = "Resonance"
            copy.power = 1
            copy.breakPower = 0
            copy.target = TGT.SINGLE
            copy.rel = REL.ENEMY
            copy.effect = EFF.DAMAGE
            copy.hits = 1
            copy.friendStatus = {}
            copy.enemyStatus = {}
        end
        copy.attr = ATTR.FINISH
        copy.cost = 0
        copy.known = knownOf(copy)
        local okKind, kind = pcall(classify, copy)
        copy.kind = (okKind and kind) or "damage"
        local info = copy.known
        if info and info.use == "heal" then copy.kind = "heal" end
        if info and (info.use == "buff" or info.use == "guardbuff") then copy.kind = "buff" end
        if info and info.use == "finish" and copy.kind ~= "heal" and copy.kind ~= "buff" then
            copy.kind = "damage"
        end
        return copy
    end
    local function visionFinishMap()
        if Fight and Fight.visionFinish then return Fight.visionFinish end
        local map, rows = {}, 0
        local tables = FindAllOf("DataTable") or {}
        for _, dt in ipairs(tables) do
            pcall(function()
                if type(dt) ~= "userdata" or not dt:IsValid() then return end
                if rowStructName(dt) ~= "VISION_ITEM_DATA" then return end
                dt:ForEachRow(function(_, row)
                    rows = rows + 1
                    local id = num(field(row, "ID"))
                    local fin = num(field(row, "finishBlowSkill"))
                    if id and fin and fin > 0 then map[id] = fin end
                end)
            end)
        end
        local n, lo, hi = 0, nil, nil
        for id in pairs(map) do
            n = n + 1
            if not lo or id < lo then lo = id end
            if not hi or id > hi then hi = id end
        end
        log("vision finishers: %d from %d rows, ids %s-%s", n, rows, tostring(lo), tostring(hi))
        if Fight then Fight.visionFinish = map end
        return map
    end
    local function unitFinishId(who)
        local map = visionFinishMap()
        local function fromVision(v)
            local n = num(v)
            if n and map[n] then return map[n] end
            return nil
        end
        local function fromObject(obj)
            if type(obj) ~= "userdata" then return fromVision(obj) end
            for _, key in ipairs({ "equipVisionId", "EquipVisionId", "visionId", "VisionId", "VisionID" }) do
                local fin = fromVision(field(obj, key))
                if fin then return fin end
            end
            local fin = num(field(obj, "finishBlowSkill"))
            if fin and fin > 0 then return fin end
            return nil
        end
        local p = paramOf(who)
        if p then
            local fin = fromObject(p)
            if fin then return fin end
            local okd, data = pcall(function() return p.visionData end)
            if okd then
                fin = fromObject(data)
                if fin then return fin end
            end
            for _, method in ipairs({ "GetVisionId", "GetEquipVisionId" }) do
                local okm, v = pcall(function() return p[method](p) end)
                fin = okm and fromVision(v) or nil
                if fin then return fin end
            end
        end
        local hits = {}
        for _, id in ipairs(equippedIds(who)) do
            if map[id] then hits[#hits + 1] = id end
        end
        if #hits == 1 then return map[hits[1]] end
        return nil
    end
    local out, seen = {}, {}
    local function add(id)
        id = num(id)
        if not id or id <= 0 or seen[id] then return end
        seen[id] = true
        out[#out + 1] = asFinish(id)
    end
    local unknown = {}
    for _, id in ipairs(equippedIds(uid)) do
        local s = skillOf(id)
        if s and s.attr == ATTR.FINISH then add(id)
        elseif not s then unknown[#unknown + 1] = tostring(id) end
    end
    add(unitFinishId(uid))
    if Fight then
        Fight.finishNote = Fight.finishNote or {}
        Fight.finishNote[uid] = #unknown > 0 and table.concat(unknown, ",") or ""
    end
    if #out > 0 then return out end
    if Fight and Fight.finishScan and Fight.finishScan[uid] then
        for _, id in ipairs(Fight.finishScan[uid]) do add(id) end
        return out
    end
    if not SkillIdx then return out end
    local bfl = battleLib()
    local found = {}
    if bfl and bfl:IsValid() then
        for id, s in pairs(SkillIdx) do
            if s.attr == ATTR.FINISH then
                local ok, can = pcall(function() return bfl:CanUnitActivateSkill(uid, id) end)
                if ok and can == true then
                    found[#found + 1] = id
                    add(id)
                end
            end
        end
    end

    -- Universal Resonance Finisher Discovery:
    -- Any living party member can execute any equipped Vision Finisher on the Resonance wheel!
    if #out == 0 and SkillIdx then
        for id, s in pairs(SkillIdx) do
            local sn = s.name and s.name:lower() or ""
            local kn = knownOf(s)
            local isFinisher = (s.attr == ATTR.FINISH) or (kn and kn.use == "finish") or (sn == "healing wind")
            if isFinisher then
                add(id)
                found[#found + 1] = id
            end
        end
    end

    if Fight then
        Fight.finishScan = Fight.finishScan or {}
        Fight.finishScan[uid] = found
    end
    return out
end

local function markDebuff(id, effect)
    if (not id) or (not effect) or (effect == "") then return end
    Fight.debuffOn = Fight.debuffOn or {}
    local row = Fight.debuffOn[id]
    if not row then
        row = {}
        Fight.debuffOn[id] = row
    end
    row[effect] = true
    -- A fresh cast has not been seen yet. Clearing the old sighting
    -- stops a refresh from repeating until the status is back, then gone.
    if Fight.debuffSeen and Fight.debuffSeen[id] then
        Fight.debuffSeen[id][effect] = nil
    end
end

local function turn(uid, skills, w, phase)
    local isLongFight = checkIsLongFight(w)
    -- One slot of the round. Care first, then the phase the whole field is in.
    -- Damage is scored against every living gauge, using what earlier slots already claimed.
    w.usedSupport = w.usedSupport or {}
    Fight.claim = Fight.claim or {
        heal = {}, revive = {}, hone = {}, ether = {},
        guard = false, esper = false, lb = false, scan = {}, steal = {},
        provoke = false, provokeRound = -99,
        etherRound = false,
        potGiven = false,
    }
    Fight.debuffOn = Fight.debuffOn or {}
    Fight.debuffSeen = Fight.debuffSeen or {}
    Fight.debuffTold = Fight.debuffTold or {}
    Fight.scanned = Fight.scanned or {}
    Fight.poured = Fight.poured or {}
    Fight.down = Fight.down or {}
    Fight.relax = Fight.relax or {}
    Fight.gaugeScale = Fight.gaugeScale or {}
    Fight.brokeOn = Fight.brokeOn or {}

    local function pay(s)
        return (s.cost or 0) <= (w.mp or 0)
    end
    local function useOf(s)
        return s.known and s.known.use or nil
    end
    local function band()
        local maxv = w.maxMp or 0
        if maxv <= 0 then return "low" end
        local ratio = (w.mp or 0) / maxv
        if ratio > 0.50 then return "high" end
        if ratio >= 0.20 then return "mid" end
        return "low"
    end
    local function realCure(s)
        if s.kind ~= "heal" then return false end
        if s.known and s.known.patch then return false end
        return true
    end
    local function isPatch(s)
        return s.known and s.known.patch and true or false
    end
    local function isHit(s, cashing)
        local n = (s.name or ""):lower()
        if n:find("raise") or n:find("arise") or n:find("revive") or n:find("phoenix") then
            return false
        end
        if s.rel == REL.FRIEND or s.target == TGT.FRIEND or s.target == TGT.SELF or friendAction(s) then
            return false
        end
        if s.kind == "heal" or s.kind == "buff" or s.kind == "debuff" or s.kind == "cure"
            or s.kind == "revive" or s.kind == "defend" or s.kind == "scan" or s.kind == "provoke" or s.kind == "steal" then
            return false
        end
        if s.attr == ATTR.SUMMON or s.attr == ATTR.FINISH or s.attr == ATTR.ITEM then return false end
        local use = useOf(s)
        if use == "skip" or use == "opener" or use == "guardbuff" or use == "guard" or use == "scan" or use == "heal" or use == "cure" or use == "provoke" or use == "steal" or use == "revive" or use == "lb-revive" then
            return false
        end
        if (s.attr == ATTR.LB) or (use == "lb-cash") or (use == "lb-setup") then
            return true
        end
        return s.kind == "damage" or s.attr == ATTR.FIGHT or s.attr == ATTR.MAGIC or s.attr == ATTR.ABILITY
    end
    local function gaugeOfEnemy(enemy)
        local card = mobOf(enemy)
        local gauge = (card and tonumber(card.gauge)) or 100
        local scaled = Fight.gaugeScale and Fight.gaugeScale[enemy.id]
        if scaled and scaled > gauge then gauge = scaled end
        if Fight.down[enemy.id] then return gauge, 0, true, card end
        local poured = Fight.poured[enemy.id] or 0
        local remain = gauge - poured
        if remain < 0 then remain = 0 end
        return gauge, remain, remain <= 0, card
    end
    local function handOf(s, enemy)
        return (counterScale(s, enemy) or 1) * (monoScale(s, enemy) or 1)
    end
    local function staggerOf(s, enemy)
        local f = elementFactor(s, enemy)
        if f <= 0 then return 0, f end
        local _, br = offenseOf(s)
        return (br or 0) * f * handOf(s, enemy), f
    end
    local function allyCritical()
        local who = nil
        local threshold = hardField and 0.50 or 0.40
        for _, a in ipairs(w.allies) do
            if not a.dead and (a.hp or 1) < threshold and not Fight.claim.heal[a.id] then
                if not who or (a.hp or 1) < (who.hp or 1) then who = a end
            end
        end
        return who
    end

    if phase == PHASE_FINISH then
        local finishes = {}
        for _, s in ipairs(skills) do
            if s.attr == ATTR.FINISH then finishes[#finishes + 1] = s end
        end
        if #finishes == 0 then
            local ok, extra = pcall(finishList, uid)
            if ok and type(extra) == "table" then finishes = extra end
        end
        return pickFinish(uid, finishes, w)
    end

    local open, brokenPool = {}, {}
    local waitParty = 0
    for _ in pairs(Fight.seenAlly or {}) do waitParty = waitParty + 1 end
    if waitParty < 2 then waitParty = 2 end
    local actionsN = #(Fight.actions or {})
    for _, u in ipairs(w.enemies) do
        local _, remain, empty = gaugeOfEnemy(u)
        local waiting = false
        local rec = Fight.gaugeWas and Fight.gaugeWas[u.id]
        if rec and (type(rec.size) == "number") and ((actionsN - (rec.at or 0)) <= waitParty) then
            waiting = true
        end
        if u.broken or empty or waiting then brokenPool[#brokenPool + 1] = u
        else open[#open + 1] = u end
    end

    local hardField = false
    local autoProfileMode = "Speed Farm"
    local function styleOf()
        local healers = 0
        hardField = w.boss and true or false
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false then
                local kit = unitKit(a.id)
                if kit and (kit.healScore or 0) >= 50 then
                    local mp = stat(a.id, PARAM.MP, false) or 0
                    local cost = kit.healCost or 0
                    if cost <= 0 or mp >= cost then healers = healers + 1 end
                end
            end
        end
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            if card and card.danger and card.danger[1] then hardField = true end
        end
        if hardField then
            autoProfileMode = "Boss Slayer"
            if not Fight.adaptiveSpeedApplied then
                Fight.adaptiveSpeedApplied = true
                combatSpeedIdx = 1
                pcall(function() ExecuteConsoleCommand("slomo 1.0") end)
                showToast("[SPEED] Boss Encounter: 1.0x Cinematic Mode")
            end
            if healers == 0 then return "defensive" end
            return "balanced"
        end
        local totalMp, totalMax = 0, 0
        for _, a in ipairs(w.allies) do
            if not a.dead then
                local mp = stat(a.id, PARAM.MP, false) or 0
                local max = stat(a.id, PARAM.MP, true) or 100
                totalMp = totalMp + mp
                totalMax = totalMax + max
            end
        end
        if totalMax > 0 and (totalMp / totalMax) < 0.25 then
            autoProfileMode = "Conserve MP"
            return "defensive"
        end
        autoProfileMode = "Speed Farm"
        if not Fight.adaptiveSpeedApplied then
            Fight.adaptiveSpeedApplied = true
            combatSpeedIdx = 3
            pcall(function() ExecuteConsoleCommand("slomo 2.0") end)
        end
        if healers > 0 then return "aggressive" end
        return "balanced"
    end
    local style = styleOf()

    local function modeOf(list)
        if #list <= 1 then return "sync", list, nil end
        local maxGauge = 0
        for _, u in ipairs(list) do
            local gauge = gaugeOfEnemy(u)
            if gauge > maxGauge then maxGauge = gauge end
        end
        local large, small = {}, {}
        for _, u in ipairs(list) do
            local gauge = gaugeOfEnemy(u)
            if maxGauge > 0 and gauge <= maxGauge * 0.6 then
                small[#small + 1] = u
            else
                large[#large + 1] = u
            end
        end
        if #small > 0 and #large > 0 then return "adds", small, large[1] end
        return "sync", list, large[1] or list[1]
    end
    local mode, pool, bossU = modeOf(open)
    if style == "defensive" and allyCritical() and bossU then
        local card = mobOf(bossU)
        if card and card.danger and card.danger[1] then
            local _, remain, _, _ = gaugeOfEnemy(bossU)
            local gauge = gaugeOfEnemy(bossU)
            if remain < gauge * 0.40 then
                pool = { bossU }
                mode = "sync"
            end
        end
    end
    local tag = mode .. "/" .. style
    if Fight.planTag ~= tag then
        Fight.planTag = tag
        local bits = {}
        for _, u in ipairs(pool) do bits[#bits + 1] = u.name end
        local line = string.format("plan %s. pool: %s", tag, (#bits > 0) and table.concat(bits, ", ") or "none")
        log("%s", line)
        appendLog("  " .. line)
    end

    -- Live Engine HP Synchronization: If an ally has HP > 0, they are 100% ALIVE!
    for _, a in ipairs(w.allies) do
        local cur = stat(a.id, PARAM.HP, false)
        if cur and cur > 0 then
            a.dead = false
            a.hp = hpRatio(a.id) or (cur / math.max(1, stat(a.id, PARAM.HP, true) or 1))
            Fight.claim.revive[a.id] = nil
        end
    end

    Fight.downNow = {}
    for _, a in ipairs(w.allies) do
        local cur = stat(a.id, PARAM.HP, false)
        local isDead = (cur ~= nil and cur <= 0) or (cur == nil and a.dead and (a.hp or 0) <= 0)
        if isDead and a.acts ~= false and a.id ~= uid then
            a.dead = true
            Fight.downNow[#Fight.downNow + 1] = a
        end
    end

    -- All-Hands Emergency Revive Targeting:
    -- Prefer an unclaimed TRULY dead ally (live HP <= 0) so multiple party members revive different heroes concurrently!
    local dead = nil
    for _, a in ipairs(w.allies) do
        local cur = stat(a.id, PARAM.HP, false)
        local isDead = (cur ~= nil and cur <= 0) or (cur == nil and a.dead and (a.hp or 0) <= 0)
        if isDead and a.id ~= uid and not Fight.claim.revive[a.id] then
            dead = a
            break
        end
    end
    if not dead and Health.fallen then
        local candidate = Health.fallen(w.allies, unitKit, offenseOf)
        if candidate and candidate.id ~= uid then
            local cur = stat(candidate.id, PARAM.HP, false)
            if (cur ~= nil and cur <= 0) and not Fight.claim.revive[candidate.id] then
                dead = candidate
            end
        end
    end
    -- Fallback to any truly dead ally if claims are resolving
    if not dead then
        for _, a in ipairs(w.allies) do
            local cur = stat(a.id, PARAM.HP, false)
            local isDead = (cur ~= nil and cur <= 0) or (cur == nil and a.dead and (a.hp or 0) <= 0)
            if isDead and a.id ~= uid then
                dead = a
                break
            end
        end
    end

    -- Extend revive claim cooldown to prevent spamming while revival animation / HP update is resolving
    if dead and Fight.claim.revive[dead.id] then
        local at = Fight.claim.revive[dead.id]
        local waitN = math.max(4, #w.allies * 2)
        if (type(at) == "number") and ((#(Fight.actions or {}) - at) >= waitN) then
            Fight.claim.revive[dead.id] = nil
        end
    end

    -- Dedicated Healer Coordination:
    -- If a dedicated White Mage / Healer (Fina/Ayaka/Aerith/Folka) is in the party and alive,
    -- non-healers (like Lid/Lasswell) must not waste turns casting slow Revive spells
    local whoStr = unitName(uid):lower()
    local isDedicatedHealer = whoStr:find("fina") or whoStr:find("ayaka") or whoStr:find("folka")
        or whoStr:find("garnet") or whoStr:find("aerith") or whoStr:find("rosa") or whoStr:find("lenna")
    local dedicatedHealerAlive = false
    local dedicatedHealerMp = 0
    for _, a in ipairs(w.allies) do
        if not a.dead and a.id ~= uid then
            local an = a.name:lower()
            if an:find("fina") or an:find("ayaka") or an:find("folka") or an:find("garnet") or an:find("aerith") or an:find("rosa") or an:find("lenna") then
                dedicatedHealerAlive = true
                dedicatedHealerMp = stat(a.id, PARAM.MP, false) or 0
                break
            end
        end
    end

    -- Absolute Sanity Check: Never attempt revive if dead ally's live HP is > 0!
    if dead then
        local liveHp = stat(dead.id, PARAM.HP, false)
        if liveHp ~= nil and liveHp > 0 then
            dead = nil
        end
    end

    if dead and not Fight.claim.revive[dead.id] then
        local downN = #Fight.downNow
        if (downN < 1) and dead then downN = 1 end
        local isBoss = w.boss or hardField or (#w.enemies == 1)

        -- Priority 1: Multi-Target Party Revive when 2+ allies are down
        if downN >= 2 then
            -- Check for Party Revive Limit Burst / Spell (e.g. Radiant Restoration)
            if Limits.bestRaise then
                local pSpell, partyHit = Limits.bestRaise(skills, downN, pay, false)
                if pSpell and partyHit then
                    local choice = finishChoice(uid, pSpell, "raise the party", idsOf(Fight.downNow), true)
                    if choice then
                        local at = #(Fight.actions or {})
                        for _, a in ipairs(Fight.downNow) do
                            Fight.claim.revive[a.id] = at
                            Fight.claim.heal[a.id] = nil
                        end
                        return choice
                    end
                end
            end

            -- Check for Party Revive Item (Mega Phoenix)
            local partyItem = pickRecoveryItem(uid, w, "revive")
            if partyItem and (partyItem.party or partyItem.spread) then
                local at = #(Fight.actions or {})
                for _, a in ipairs(Fight.downNow) do
                    Fight.claim.revive[a.id] = at
                    Fight.claim.heal[a.id] = nil
                end
                return partyItem
            end
        end

        -- Priority 2: Superior Full HP Revive (Arise spell or Phoenix Pinion item)
        -- Check if caster has Arise (100% HP revive spell)
        local ariseSpell = nil
        for _, s in ipairs(skills) do
            if (s.kind == "revive" or useOf(s) == "revive") and pay(s) then
                local sName = (s.name or ""):lower()
                if sName:find("arise") or sName:find("full raise") then
                    ariseSpell = s
                    break
                end
            end
        end
        if ariseSpell then
            local choice = finishChoice(uid, ariseSpell, "arise " .. dead.name, { dead.id }, false)
            if choice then
                Fight.claim.revive[dead.id] = #(Fight.actions or {})
                Fight.claim.heal[dead.id] = nil
                return choice
            end
        end

        -- If caster does NOT have Arise (only basic 10% HP Raise or no spell), but we have Phoenix Pinion (100% HP item):
        -- Always prioritize Phoenix Pinion over low-tier Raise so heroes are brought back at 100% HP!
        local pinionItem = pickRecoveryItem(uid, w, "revive")
        if pinionItem and ((pinionItem.tier and pinionItem.tier >= 2) or (pinionItem.name and pinionItem.name:lower():find("pinion"))) then
            Fight.claim.revive[dead.id] = #(Fight.actions or {})
            Fight.claim.heal[dead.id] = nil
            return pinionItem
        end

        -- Priority 3: Standard Revive Spell (Raise)
        local function raiseFallen(allowOne)
            local s, partyHit = nil, false
            if Limits.bestRaise then
                s, partyHit = Limits.bestRaise(skills, downN, pay, allowOne)
            elseif not allowOne then
                for _, row in ipairs(skills) do
                    if (row.kind == "revive") and pay(row) then s = row break end
                end
            end
            if not s then return nil end
            local many = partyHit and (downN >= 2)
            local ids = (many and idsOf(Fight.downNow)) or { dead.id }
            local why = (many and "raise the party") or ("raise " .. dead.name)
            local choice = finishChoice(uid, s, why, ids, many and true or false)
            if not choice then return nil end
            local at = #(Fight.actions or {})
            Fight.claim.revive[dead.id] = at
            Fight.claim.heal[dead.id] = nil
            if many then
                for _, ally in ipairs(Fight.downNow) do
                    Fight.claim.revive[ally.id] = at
                    Fight.claim.heal[ally.id] = nil
                end
            end
            return choice
        end

        local choice = raiseFallen(false)
        if choice then return choice end

        -- Priority 4: All-Hands Revive with Items (Phoenix Pinion / Phoenix Down)
        -- EVERYONE in the party tries to revive fallen allies immediately!
        local item = pickRecoveryItem(uid, w, "revive")
        if item then
            Fight.claim.revive[dead.id] = #(Fight.actions or {})
            Fight.claim.heal[dead.id] = nil
            return item
        end

        choice = raiseFallen(true)
        if choice then return choice end
    end

    local function healNow(hurt, why, itemAt)
        if not hurt or Fight.claim.heal[hurt.id] then return nil end
        if Health.healerWaiting then
            local danger = false
            for _, u in ipairs(w.enemies) do
                local card = mobOf(u)
                if card and card.danger and card.danger[1] then
                    local _, _, empty = gaugeOfEnemy(u)
                    if (not empty) and (not u.broken) then danger = true end
                end
            end
            local mpOf = function(id)
                if id == uid then return w.mp or 0 end
                return stat(id, PARAM.MP, false) or 0
            end
            if Health.healerWaiting(uid, why, hurt.hp, danger, w.allies, unitKit, mpOf) then
                Fight.healLeft = Fight.healLeft or {}
                if not Fight.healLeft[uid] then
                    Fight.healLeft[uid] = true
                    local line = string.format("heal left, %s waits", unitName(uid))
                    log("%s", line)
                    appendLog("  " .. line)
                end
                return nil
            end
        end
        local skill, rank = nil, -1
        local hurtN = 0
        for _, a in ipairs(w.allies) do
            if not a.dead and (a.hp or 1) < 0.50 then hurtN = hurtN + 1 end
        end
        local missing = nil
        local maxv = stat(hurt.id, PARAM.HP, true)
        local ratio = hurt.hp or 1
        if maxv and (maxv > 0) and (ratio < 1) then missing = (1 - ratio) * maxv end
        for _, s in ipairs(skills) do
            if (s.kind == "heal") and pay(s) and (not isPatch(s)) then
                local party = partyOf(s)
                local r
                if Health.spellRank then
                    r = Health.spellRank(s, missing, hurtN, party)
                else
                    local cost = s.cost or 0
                    if cost < 1 then cost = 1 end
                    local power = s.power or 0
                    if power > 0 then
                        r = power / cost
                        if (hurtN >= 3) and party then r = r * 3 end
                    elseif (hurtN >= 3) and party then
                        r = 3 + (0.01 / cost)
                    elseif party then
                        r = 0.5 + (0.01 / cost)
                    else
                        r = 1 + (0.01 / cost)
                    end
                end
                -- Tier evolution & Role Mastery: Prioritizes higher tier heals (Curaja / Curaga over Cure)
                local tb = skillTierBonus(s)
                local rmb = roleMasteryBonus(uid, s, w)
                r = r + ((tb + rmb) / 1000)
                if r > rank then skill, rank = s, r end
            end
        end
        local itemLine = itemAt or 0.45
        -- Strict Role Discipline: DPS units NEVER burn potions on allies if dedicated healer is alive with MP!
        local minReserveMp = (cfg.CheapMP ~= false) and 5 or 20
        local canUseHealItem = isDedicatedHealer or (not dedicatedHealerAlive) or (dedicatedHealerMp < minReserveMp) or (hurt.id == uid and (hurt.hp or 1) < 0.25)
        if (not skill) and ((hurt.hp or 1) < itemLine) and canUseHealItem then
            local item = pickRecoveryItem(uid, w, "heal")
            if item then Fight.claim.heal[hurt.id] = true return item end
        end
        local blocked = false
        for _, s in ipairs(skills) do
            if realCure(s) then
                if pay(s) then blocked = false break end
                blocked = true
            end
        end
        if (not skill) and blocked and (not Fight.claim.ether[uid]) and (not Fight.claim.etherRound) then
            local ether = pickRecoveryItem(uid, w, "mp")
            if ether then
                ether.reason = "ether so a cure fits"
                Fight.claim.ether[uid] = true
                Fight.claim.etherRound = true
                return ether
            end
        end
        if not skill then
            for _, s in ipairs(skills) do
                if (s.kind == "heal") and pay(s) and isPatch(s) then
                    if not (w.usedSupport[s.id] and ((hurt.hp or 1) >= 0.22)) then
                        w.usedSupport[s.id] = true
                        skill = s
                        break
                    end
                end
            end
        end
        if skill then
            local spread = partyOf(skill) and (not isPatch(skill))
            local pct = math.floor((hurt.hp or 0) * 100 + 0.5)
            local choice = finishChoice(uid, skill, string.format("%s %s at %d%%", why, hurt.name, pct),
                spread and idsOf(w.allies) or { hurt.id }, spread)
            if choice then Fight.claim.heal[hurt.id] = true return choice end
        end
        return nil
    end

    -- Proactive Healer & Support Mana Reserve:
    -- Never let the primary healer run dry (< 40 MP) where they would fail to cast Curaja/Curaga!
    local whoActor = unitName(uid):lower()
    local isCasterHealer = whoActor:find("fina") or whoActor:find("ayaka") or whoActor:find("folka") or whoActor:find("aerith")
    local curActorMp = stat(uid, PARAM.MP, false) or 0
    local minHealMp = (cfg.CheapMP ~= false) and 5 or 40
    if isCasterHealer and curActorMp < minHealMp and not Fight.claim.ether[uid] and not Fight.claim.etherRound then
        local ether = pickRecoveryItem(uid, w, "mp")
        if ether then
            ether.reason = "proactive healer mana reserve"
            Fight.claim.ether[uid] = true
            Fight.claim.etherRound = true
            return ether
        end
    end

    local crit = allyCritical()
    local function deferHeal()
        if phase == PHASE_BONUS then return false end
        if crit and (crit.hp or 1) < 0.35 then return false end
        local list = (#pool > 0) and pool or open
        local function pays(spells, mp)
            for _, s in ipairs(spells) do
                if s.kind ~= "heal" and s.kind ~= "buff" and s.kind ~= "debuff"
                    and s.kind ~= "cure" and s.kind ~= "revive" and s.kind ~= "defend"
                    and s.kind ~= "scan" and (s.cost or 0) <= mp then
                    for _, u in ipairs(list) do
                        if elementFactor(s, u) >= 3 then return true end
                    end
                end
            end
            return false
        end
        if not pays(skills, w.mp or 0) then return false end
        local others, otherPays = 0, false
        for _, a in ipairs(w.allies) do
            if a.id ~= uid and not a.dead and a.acts ~= false then
                others = others + 1
                local kit = unitKit(a.id)
                local mp = stat(a.id, PARAM.MP, false) or 0
                if kit and pays(kit.spells or {}, mp) then otherPays = true end
            end
        end
        return others > 0 and not otherPays
    end
    if crit and phase ~= PHASE_BONUS and not deferHeal() then
        local choice = healNow(crit, "critical")
        if choice then return choice end
    end
    if phase == PHASE_BONUS or #brokenPool > 0 and phase == PHASE_BONUS then
        local choice = healNow(crit, "critical")
        if choice then return choice end
    end

    local who = lockedAlly(w)
    if who and phase ~= PHASE_BONUS and not Fight.claim.heal[who.id] then
        for _, s in ipairs(skills) do
            if s.kind == "cure" and pay(s) then
                local choice = finishChoice(uid, s, "cure " .. who.name, { who.id }, aoeOf(s))
                if choice then Fight.claim.heal[who.id] = true return choice end
            end
        end
        local item = pickRecoveryItem(uid, w, "cure")
        if item then Fight.claim.heal[who.id] = true return item end
    end

    local recoverAt, smallDanger = 0.50, false
    if Health.recoverAt then
        local rows = {}
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            local _, _, empty = gaugeOfEnemy(u)
            rows[#rows + 1] = {
                danger = (card and card.danger and card.danger[1]) and true or false,
                empty = empty and true or false,
                broken = u.broken and true or false,
                gauge = card and tonumber(card.gauge) or 0,
            }
        end
        recoverAt, smallDanger = Health.recoverAt(w.boss and true or false, rows)
    else
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            if card and card.danger and card.danger[1] then
                local _, _, empty = gaugeOfEnemy(u)
                if not empty and not u.broken then recoverAt = 0.65 end
            end
        end
    end
    if (not Fight.recoverTold) and ((recoverAt > 0.50) or smallDanger) then
        Fight.recoverTold = true
        if recoverAt > 0.50 then
            log("recover line 65%")
        else
            log("recover line 50%, danger gauge is small")
        end
    end
    local function underMark()
        local n, who = 0, nil
        for _, a in ipairs(w.allies) do
            if not a.dead and (a.hp or 1) < recoverAt and not Fight.claim.heal[a.id] then
                if a.acts ~= false then
                    n = n + 1
                    if not who or (a.hp or 1) < (who.hp or 1) then who = a end
                end
            end
        end
        return n, who
    end
    local halfN, halfWho = underMark()
    local recoverGate = recoverAt > 0.50 or (band() == "high"
        and (Fight.afterBonus or (style == "defensive" and halfN >= 2)))
    if halfWho and phase ~= PHASE_BONUS and not deferHeal() and recoverGate then
        local choice = healNow(halfWho, "recover", recoverAt > 0.50 and recoverAt or 0.50)
        if choice then return choice end
    end

    local foeRows, seenNoted, matterKnown, debuffOwedFlag = nil, false, nil, nil
    local function hitWouldFinish(enemy, remain)
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (a.acts ~= false) then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                local spells = skills
                if a.id ~= uid then
                    local kit = unitKit(a.id)
                    spells = (kit and kit.spells) or {}
                end
                for _, s in ipairs(spells) do
                    if isHit(s, false) and ((s.cost or 0) <= mp) then
                        local gained = staggerOf(s, enemy)
                        if (gained > 0) and (gained >= remain) then return true end
                    end
                end
            end
        end
        return false
    end
    local function debuffFoes()
        if foeRows then return foeRows end
        local rows, preferI, preferGauge, preferDanger = {}, nil, -1, false
        for _, u in ipairs(w.enemies) do
            local gauge, remain, empty = gaugeOfEnemy(u)
            local card = mobOf(u)
            local danger = (card and card.danger and card.danger[1]) and true or false
            local about = false
            if empty then
                about = true
            elseif remain > 0 then
                about = hitWouldFinish(u, remain)
            end
            rows[#rows + 1] = {
                id = u.id,
                name = u.name,
                danger = danger,
                gauge = gauge,
                counter = card and card.counter or nil,
                ail = card and card.ail or nil,
                statuses = statuses(u.id),
                empty = empty and true or false,
                broken = u.broken and true or false,
                about = about,
                prefer = false,
            }
            local row = rows[#rows]
            if (not row.empty) and (not row.broken) then
                local take = (not preferI) or (danger and (not preferDanger))
                    or ((danger == preferDanger) and (gauge > preferGauge))
                if take then preferI, preferGauge, preferDanger = #rows, gauge, danger end
            end
        end
        if preferI then rows[preferI].prefer = true end
        foeRows = rows
        return rows
    end
    local function noteDebuffSeen(foes)
        if seenNoted or (not Debuffs.STATUS) then return end
        seenNoted = true
        Fight.debuffSeen = Fight.debuffSeen or {}
        for _, foe in ipairs(foes or {}) do
            local set = foe.statuses
            if set then
                for effect, id in pairs(Debuffs.STATUS) do
                    if set[id] then
                        Fight.debuffSeen[foe.id] = Fight.debuffSeen[foe.id] or {}
                        Fight.debuffSeen[foe.id][effect] = true
                    end
                end
            end
        end
    end
    local function payableDebuffs(actorId, mp)
        local spells = skills
        if actorId ~= uid then
            local kit = unitKit(actorId)
            spells = (kit and kit.spells) or {}
        end
        local out = {}
        for _, s in ipairs(spells) do
            if ((useOf(s) == "debuff") or (s.kind == "debuff")) and ((s.cost or 0) <= mp) then
                out[#out + 1] = s
            end
        end
        return out
    end
    local function partyMatter()
        if matterKnown ~= nil then return matterKnown end
        matterKnown = false
        if not (Debuffs.matter and Debuffs.effectOf) then return false end
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (a.acts ~= false) then
                local spells = skills
                if a.id ~= uid then
                    local kit = unitKit(a.id)
                    spells = (kit and kit.spells) or {}
                end
                for _, s in ipairs(spells) do
                    if ((useOf(s) == "debuff") or (s.kind == "debuff")) and Debuffs.matter(Debuffs.effectOf(s)) then
                        matterKnown = true
                        return true
                    end
                end
            end
        end
        return false
    end
    local function debuffOwed()
        if debuffOwedFlag ~= nil then return debuffOwedFlag end
        debuffOwedFlag = false
        if Fight.chipped or (phase ~= 0) or (not hardField) or (style == "aggressive") then return false end
        if Fight.fell and (#Fight.fell > 0) then return false end
        if allyCritical() then return false end
        for _, a in ipairs(w.allies) do
            if a.dead then return false end
        end
        if not Debuffs.choose then return false end
        local foes = debuffFoes()
        noteDebuffSeen(foes)
        local fallback = not partyMatter()
        for _, a in ipairs(w.allies) do
            if (not a.dead) and (a.acts ~= false) then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                local picks = payableDebuffs(a.id, mp)
                if Debuffs.choose(picks, foes, Fight.debuffOn, Fight.debuffSeen, fallback) then
                    debuffOwedFlag = true
                    return true
                end
            end
        end
        return false
    end
    local function guardOwed()
        if phase ~= 0 or not hardField or style == "aggressive" or Fight.claim.guard then return false end
        if Fight.fell and #Fight.fell > 0 then return false end
        if allyCritical() then return false end
        for _, a in ipairs(w.allies) do
            if a.dead then return false end
        end
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false then
                local kit = unitKit(a.id)
                local mp = stat(a.id, PARAM.MP, false) or 0
                if kit then
                    for _, s in ipairs(kit.spells or {}) do
                        if useOf(s) == "guardbuff" and (s.cost or 0) <= mp then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end
    -- The weakness can sit on someone else. A setup Limit on the buffer
    -- must not be skipped because that buffer has no weakness spell.
    local function partyWeak(skipId, skipCost)
        local foes = (#pool > 0) and pool or open
        if #foes == 0 then foes = w.enemies end
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                if a.id == skipId then mp = mp - (skipCost or 0) end
                if mp >= 0 then
                    local spells = skills
                    if a.id ~= uid then
                        local kit = unitKit(a.id)
                        spells = (kit and kit.spells) or {}
                    end
                    for _, foe in ipairs(foes) do
                        for _, s in ipairs(spells) do
                            if isHit(s, false) and (elementFactor(s, foe) >= 3) and ((s.cost or 0) <= mp) then
                                return true
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    local lbOwedFlag = nil
    local function lbOwed()
        if lbOwedFlag ~= nil then return lbOwedFlag end
        lbOwedFlag = false
        if phase ~= 0 or not hardField or Fight.claim.lb or Fight.chipped then return false end
        if Fight.fell and #Fight.fell > 0 then return false end
        if allyCritical() then return false end
        for _, a in ipairs(w.allies) do
            if a.dead then return false end
        end
        for _, a in ipairs(w.allies) do
            if not a.dead and a.acts ~= false then
                local mp = (a.id == uid) and (w.mp or 0) or (stat(a.id, PARAM.MP, false) or 0)
                local ids = equippedIds(a.id)
                for _, id in ipairs(ids) do
                    local s = tagSkill(a.id, id, false)
                    if s and useOf(s) == "lb-setup" and (s.cost or 0) <= mp then
                        local keeps = partyWeak(a.id, s.cost or 0) or not partyWeak(nil, 0)
                        if keeps then lbOwedFlag = true return true end
                    end
                end
            end
        end
        return false
    end
    -- The cash belongs to the break the ledger just marked. A body the
    -- game still calls broken from an older wave does not take that hit.
    local function burstTargets()
        local held = {}
        local mark = Fight.brokeOn or {}
        for _, u in ipairs(w.enemies) do
            if mark[u.id] or Fight.down[u.id] then
                held[#held + 1] = u
            end
        end
        if #held == 0 then
            for _, u in ipairs(w.enemies) do
                if u.broken then held[#held + 1] = u end
            end
        end
        if #held > 0 then return held end
        if #brokenPool > 0 then return brokenPool end
        local best, bestScore = nil, -1
        for _, u in ipairs(w.enemies) do
            local gauge, remain = gaugeOfEnemy(u)
            local score = (gauge > 0) and ((gauge - remain) / gauge) or 0
            if score > bestScore then best, bestScore = u, score end
        end
        if best then return { best } end
        return w.enemies
    end
    local function castDamage(pool, cashing, why)
        if not pool or #pool == 0 then return nil end
        local bestS, bestU, bestScore, bestSpread = nil, nil, -1e9, false
        local function considerSkill(s, targets, spread)
            if not pay(s) then return end
            if s.rel == REL.FRIEND or s.target == TGT.FRIEND or s.target == TGT.SELF or friendAction(s) then return end
            local sName = (s.name or ""):lower()
            if s.kind == "revive" or useOf(s) == "revive" or sName:find("raise") or sName:find("arise") or sName:find("revive") or sName:find("phoenix") then return end
            local spendLb = (useOf(s) == "lb-cash") or (s.attr == ATTR.LB)
            -- An area Limit hits every living enemy. A nulled element stays off.
            if spendLb and aoeOf(s) and s.known and s.known.element and (#w.enemies > 0) then
                local blocked = false
                for _, u in ipairs(w.enemies) do
                    if elementFactor(s, u) <= 0 then blocked = true end
                end
                if blocked then
                    Fight.limitSkip = Fight.limitSkip or {}
                    local key = (s.name or "limit") .. ":" .. s.known.element
                    if not Fight.limitSkip[key] then
                        Fight.limitSkip[key] = true
                        local line = "limit " .. (s.name or "limit") .. " skipped, " .. s.known.element .. " null"
                        log("%s", line)
                        appendLog("  " .. line)
                    end
                    return
                end
            end
            if (not cashing) and (debuffOwed() or guardOwed() or lbOwed()) and ((s.cost or 0) > 0) then return end
            local b = band()
            local useful, pts, weak, finishes, early = 0, 0, false, false, false
            for _, u in ipairs(targets) do
                local gauge, remain, empty = gaugeOfEnemy(u)
                local gained, f = staggerOf(s, u)
                local held = (why == "fill")
                if f > 0 and (cashing or (((not empty) or held) and (gained > 0))) then
                    local heavy = false
                    local pow, br = offenseOf(s)
                    if br >= 25 then heavy = true end
                    local allowed = cashing or b == "high" or (s.cost or 0) <= 0 or f >= 3 or heavy
                    if not cashing and b == "low" then allowed = ((s.cost or 0) <= 0) or (f >= 3) end
                    if allowed then
                        useful = useful + 1
                        local rawDmg = (pow or 0) * (f > 0 and f or 1)
                        if cashing then
                            pts = pts + (rawDmg * 3) + (pow or 0) * f
                        else
                            local isDpsUnit = whoStr:find("lasswell") or whoStr:find("cloud") or whoStr:find("sephiroth")
                                or whoStr:find("sakura") or whoStr:find("dark fina") or whoStr:find("jake")
                                or whoStr:find("squall") or whoStr:find("tidus")
                            if not isLongFight or isDpsUnit then
                                pts = pts + (rawDmg * 5) + (gained * 2)
                            else
                                pts = pts + gained + (rawDmg * 0.5)
                            end
                        end
                        if f >= 3 then weak = true end
                        if not empty and gained >= remain then finishes = true end
                    end
                end
            end
            if useful == 0 then return end
            if finishes and not cashing and why ~= "burst" then
                for _, other in ipairs(pool) do
                    local gauge, remain, empty = gaugeOfEnemy(other)
                    local hit = false
                    for _, t in ipairs(targets) do
                        if t.id == other.id then hit = true end
                    end
                    if not hit and not empty and remain > gauge * 0.40 then early = true end
                end
            end
            if early and weak then
                local canChip = false
                for _, other in ipairs(skills) do
                    if pay(other) and isHit(other, false) then
                        for _, u in ipairs(pool) do
                            local _, remain, empty = gaugeOfEnemy(u)
                            if not empty then
                                local gained, f = staggerOf(other, u)
                                if f >= 3 and gained > 0 and gained < remain then canChip = true end
                            end
                        end
                    end
                end
                if not canChip then early = false end
            end
            local score = pts
            if weak then score = score + 5000 end
            if spread and useful > 1 then score = score + pts end
            if finishes and cashing then score = score + 4000 end
            if finishes and not cashing and not early then score = score + 8000 - (s.cost or 0) * 20 end
            if finishes and not cashing and early then score = score - 8000 end
            if handOf(s, targets[1]) < 0.5 then score = score - 2000 end
            -- Fully Situational Threat & State Scoring:
            local threat = 0
            for _, u in ipairs(targets) do
                local card = mobOf(u)
                -- 1. Boss Danger Move Threat: Massive focus fire to shatter break gauge and interrupt!
                if card and card.danger and card.danger[1] then
                    local _, remain, empty = gaugeOfEnemy(u)
                    if not empty and not u.broken then
                        threat = threat + 20000 -- URGENT: Break and interrupt boss danger attack!
                    end
                end
                if card and card.call and threat < 100 then threat = threat + 2000 end

                -- 2. Kill Confirmation: Finish off critically wounded foes (< 20% HP) to eliminate hostile turns
                local r = hpRatio(u.id)
                if r and r > 0 then
                    if r <= 0.15 then score = score + 16000
                    elseif r <= 0.30 then score = score + 9000
                    end
                end

                -- 3. Stagger Punish Window (2.0x - 3.0x Damage Amplification):
                -- When a foe is broken/staggered, heavily prioritize maximum damage output!
                if u.broken or (Fight.down and Fight.down[u.id]) then
                    score = score + 24000
                end
            end
            score = score + threat
            -- A Limit row often has no magnification. On a hard break it is the cash,
            -- so a missing power must not lose to a normal spell. Trash keeps the gauge.
            -- The matching element wins when two bursts are ready. A row with no
            -- element still gets the cash bonus. The heavier gauge wins a tie.
            if spendLb then
                score = score + 50000
                if cashing then score = score + 50000 end
                if hardField then score = score + 20000 end
                if weak then score = score + 20000 end
                score = score + ((s.lbCost or 1) * 100)
            end
            -- Active Esper Elemental Resonance Synergy (Chains lightning with Ramuh, wind with Siren)
            if Fight.esperOut and Fight.esperOut.element then
                local sEl = s.known and s.known.element
                if sEl and sEl == Fight.esperOut.element then
                    score = score + 6000
                end
            end
            -- Auto-Evolve Vision Mastery & Role Specialization:
            -- Automatically prioritizes higher ability tiers and role-defining mastery abilities (e.g. Rain Sentinel)
            local tb = skillTierBonus(s)
            local rmb = roleMasteryBonus(uid, s, w)
            if (tb + rmb) > 0 then
                score = score + tb + rmb
            end

            -- Empirical Skill Yield Reinforcement Learning:
            -- Skills that have historically produced massive HP depletion gain positive reinforcement!
            if whoStr and s.name and TacticalMemory and TacticalMemory.skillYield then
                local wYield = TacticalMemory.skillYield[whoStr]
                local sYield = wYield and wYield[s.name:lower()]
                if sYield and sYield.avg then
                    score = score + math.min(math.floor(sYield.avg * 10000), 5000)
                end
            end
            if score > bestScore then
                bestS, bestU, bestScore, bestSpread = s, targets[1], score, spread and true or false
            end
        end
        for _, s in ipairs(skills) do
            if isHit(s, cashing) then
                local safe = {}
                if aoeOf(s) then
                    local ok = true
                    for _, u in ipairs(pool) do
                        if elementFactor(s, u) <= 0 then ok = false end
                    end
                    if ok and #pool > 1 then
                        for _, u in ipairs(pool) do safe[#safe + 1] = u end
                        considerSkill(s, safe, true)
                    end
                end
                for _, u in ipairs(pool) do
                    considerSkill(s, { u }, false)
                end
            end
        end
        if not bestS then return nil end
        local targets = bestSpread and idsOf(pool) or { bestU.id }
        local el = (bestS.known and bestS.known.element) or ""
        local name = bestSpread and (#pool .. " foes") or bestU.name
        local reason = why .. " " .. name
        if el ~= "" and elementFactor(bestS, bestU) >= 3 then reason = reason .. " " .. el end
        if (not cashing) and ((bestS.cost or 0) <= 0) and (debuffOwed() or guardOwed() or lbOwed()) then
            reason = reason .. ", setup still open"
        end
        return finishChoice(uid, bestS, reason, targets, bestSpread)
    end

    if phase == PHASE_BONUS then
        return castDamage(burstTargets(), true, "burst")
    end
    if #open == 0 and #brokenPool > 0 then
        if phase == PHASE_BONUS then
            return castDamage(brokenPool, true, "burst")
        end
        return castDamage(brokenPool, false, "fill")
    end

    local function esperParty()
        local party = 0
        for _ in pairs(Fight.seenAlly or {}) do party = party + 1 end
        if party < 1 then
            for _, a in ipairs(w.allies) do
                if not a.dead then party = party + 1 end
            end
        end
        if party < 1 then party = 2 end
        return party
    end
    local function esperStill()
        local mark = Fight.esperOut
        if not mark or not Espers.stillOut then return false end
        local up = Espers.stillOut(mark.at or 0, #(Fight.actions or {}), mark.turns or 3, esperParty())
        if (not up) and (not mark.told) then
            mark.told = true
            local line = "esper " .. (mark.name or "summon") .. " finished"
            log("%s", line)
            appendLog("  " .. line)
            if showToast then
                showToast(string.format("[ESPER FINISHED] %s departs the field", mark.name or "Summon"))
            end
            Fight.claim.esper = false
            Fight.summoned = false
        end
        return up
    end
    local weaknessFits
    local function summonChoice(mode)
        if not Espers.best then return nil end
        if esperStill() then return nil end
        if Fight.claim.esper then return nil end
        local list = (#pool > 0) and pool or open
        if #list == 0 then list = w.enemies end
        if #list == 0 then return nil end
        local preferId, preferGauge, dangerGauge = nil, -1, -1
        local near, long = false, false
        for _, u in ipairs(list) do
            local card = mobOf(u)
            local gauge, remain, empty = gaugeOfEnemy(u)
            local ratio = 1
            if gauge > 0 then ratio = remain / gauge end
            if not empty then
                if gauge > preferGauge then
                    preferId, preferGauge = u.id, gauge
                end
                if card and card.danger and card.danger[1] and (gauge > dangerGauge) then
                    dangerGauge = gauge
                    preferId = u.id
                end
                if ratio <= 0.40 then near = true end
                if ratio > 0.40 then long = true end
            end
        end
        if (mode == "break") and (not near) then return nil end
        if (mode == "again") and (not Fight.esperOut) then return nil end
        if (mode == "later") and Fight.esperOut then return nil end
        if ((mode == "again") or (mode == "later")) and ((not long) or (band() ~= "high")) then return nil end
        if (mode == "break") and (band() ~= "high") and (not weaknessFits(0)) then return nil end
        local hits = {}
        -- The signature hits every living enemy, not only the current plan.
        local field = (#w.enemies > 0) and w.enemies or list
        for _, u in ipairs(field) do
            local gauge, remain = gaugeOfEnemy(u)
            local ratio = 1
            if gauge > 0 then ratio = remain / gauge end
            hits[#hits + 1] = { id = u.id, prefer = (u.id == preferId), ratio = ratio, foe = u }
        end
        local cands = {}
        for _, s in ipairs(skills) do
            if (s.attr == ATTR.SUMMON) and pay(s) and (useOf(s) ~= "skip") then
                local fact = (Espers.lookup and Espers.lookup(s.name)) or nil
                if not fact then fact = { turns = 3, role = "damage", use = "summon" } end
                local scored, blocked = {}, false
                for _, h in ipairs(hits) do
                    local factor = elementFactor({ known = fact, name = s.name }, h.foe)
                    if fact.element and (factor <= 0) then blocked = true end
                    scored[#scored + 1] = { factor = factor, prefer = h.prefer, ratio = h.ratio }
                end
                if blocked and fact.element then
                    Fight.esperSkip = Fight.esperSkip or {}
                    local key = (s.name or "summon") .. ":" .. fact.element
                    if not Fight.esperSkip[key] then
                        Fight.esperSkip[key] = true
                        local line = "esper " .. (s.name or "summon") .. " skipped, " .. fact.element .. " null"
                        log("%s", line)
                        appendLog("  " .. line)
                    end
                end
                local care = not blocked
                if care then
                    local kit = unitKit(uid)
                    local need = 0
                    if kit and (kit.healScore >= 50) then need = kit.healCost or 0 end
                    if (need > 0) and (((w.mp or 0) - (s.cost or 0)) < need) then care = false end
                end
                if care and (mode == "setup") then
                    local room = weaknessFits(s.cost or 0) or (#w.enemies >= 3) or (not weaknessFits(0))
                    if not room then care = false end
                end
                if care then
                    cands[#cands + 1] = { ref = s, fact = fact, hits = scored }
                end
            end
        end
        if #cands == 0 then return nil end
        if not Fight.esperTold then
            Fight.esperTold = true
            local names = {}
            for _, c in ipairs(cands) do
                local el = c.fact.element or c.fact.role or "summon"
                names[#names + 1] = (c.ref.name or "summon") .. " " .. el
            end
            log("esper equipped: %s", table.concat(names, ", "))
        end
        local ctx = {
            boss = w.boss and true or false,
            partyHurt = allyCritical() and true or false,
        }
        local picked = Espers.best(cands, mode, ctx)
        if not picked then return nil end
        local s, fact = picked.ref, picked.fact
        local foe = nil
        for _, h in ipairs(hits) do
            if h.prefer then foe = h.foe end
        end
        if not foe then foe = list[1] end
        local spread = aoeOf(s)
        local why = "setup esper"
        if mode == "break" then why = "esper before the break" end
        if mode == "again" then why = "esper again" end
        if mode == "later" then why = "esper" end
        why = why .. " " .. (s.name or "summon")
        if fact.element then
            why = why .. " " .. fact.element
        elseif fact.role == "guard" then
            why = why .. " support"
        end
        local choice = finishChoice(uid, s, why, spread and idsOf(list) or { foe.id }, spread)
        if choice then
            choice.esperTurns = fact.turns or 3
            Fight.claim.esper = true
        end
        return choice
    end
    weaknessFits = function(extra)
        local mp = (w.mp or 0) - (extra or 0)
        if mp < 0 then return false end
        for _, foe in ipairs(#pool > 0 and pool or open) do
            for _, s in ipairs(skills) do
                if isHit(s, false) and elementFactor(s, foe) >= 3 and (s.cost or 0) <= mp then
                    return true
                end
            end
        end
        return false
    end
    local function firstSkill(pred)
        for _, s in ipairs(skills) do
            if useOf(s) ~= "skip" and pred(s) and pay(s) then return s end
        end
        return nil
    end

    -- One setup Limit per fight. A party row lands on the allies. A stagger
    -- row lands on the danger body, or the largest gauge still open.
    local function setupLimit()
        if Fight.claim.lb then return nil end
        local s = nil
        if Limits.bestSetup then s = Limits.bestSetup(skills, pay) end
        if not s then s = firstSkill(function(x) return useOf(x) == "lb-setup" end) end
        if not s then return nil end
        if not (partyWeak(uid, s.cost or 0) or (not partyWeak(nil, 0))) then return nil end
        if s.known and s.known.party then
            local ids = {}
            for _, a in ipairs(w.allies) do
                if not a.dead then ids[#ids + 1] = a.id end
            end
            if #ids == 0 then return nil end
            local choice = finishChoice(uid, s, "setup lb " .. (s.name or "limit") .. " party", ids, true)
            if choice then Fight.claim.lb = true end
            return choice
        end
        local best, bestGauge, danger, dangerGauge = nil, -1, nil, -1
        local list = ((#open > 0) and open) or w.enemies
        for _, u in ipairs(list) do
            local gauge, _, empty = gaugeOfEnemy(u)
            if not empty then
                if gauge > bestGauge then best, bestGauge = u, gauge end
                local card = mobOf(u)
                if card and card.danger and card.danger[1] and (gauge > dangerGauge) then
                    danger, dangerGauge = u, gauge
                end
            end
        end
        local foe = danger or best or list[1]
        if not foe then return nil end
        local choice = finishChoice(uid, s, "setup lb " .. (s.name or "limit") .. " " .. foe.name, { foe.id }, false)
        if choice then Fight.claim.lb = true end
        return choice
    end

    local function castDebuff(refreshOnly)
        if (phase ~= 0) or (not hardField) or (style == "aggressive") or (not Debuffs.choose) then
            return nil
        end
        if allyCritical() then return nil end
        for _, a in ipairs(w.allies) do
            if a.dead then return nil end
        end
        local foes = debuffFoes()
        noteDebuffSeen(foes)
        local fallback = not partyMatter()
        local picks = payableDebuffs(uid, w.mp or 0)
        local s, foe, why = Debuffs.choose(picks, foes, Fight.debuffOn, Fight.debuffSeen, fallback)
        if s and foe and ((not refreshOnly) or (why == "refresh")) then
            local effect = Debuffs.effectOf(s) or "debuff"
            local spread = aoeOf(s)
            local ids = { foe.id }
            if spread then
                ids = {}
                for _, row in ipairs(foes) do
                    if (not row.empty) and (not row.broken) then ids[#ids + 1] = row.id end
                end
                if #ids == 0 then ids[1] = foe.id end
            end
            local choice = finishChoice(uid, s, why .. " debuff " .. effect .. " " .. foe.name, ids, spread)
            if choice then
                for _, id in ipairs(ids) do markDebuff(id, effect) end
                return choice
            end
        elseif (not refreshOnly) and (not s) and Debuffs.immuneEffect then
            local skipped = Debuffs.immuneEffect(picks, foes, fallback)
            if skipped and (not Fight.debuffTold[skipped]) then
                Fight.debuffTold[skipped] = true
                local line = "debuff " .. skipped .. " skipped, immune"
                log("%s", line)
                appendLog("  " .. line)
            end
        end
        return nil
    end

    local alreadyFell = Fight.fell and #Fight.fell > 0

    -- Magic Pot Encounter Puzzle Logic:
    -- Citrine Pot / Magic Pot takes 1 damage per hit and heals 99,999 HP back every turn.
    -- Dialogue Prompt: "Gimme an ether!"
    -- Using an Ether on the Pot instantly resolves the encounter with massive MRP & EXP!
    local pot = findPot(w)
    if pot then
        if not Fight.claim.potGiven then
            local potGift = pickPotGift(uid, w, pot)
            if potGift then
                Fight.claim.potGiven = true
                if Hud and Hud.toast then
                    Hud.toast(string.format("[MAGIC POT] Fed %s to %s - VICTORY!", potGift.name or "Ether", pot.name))
                end
                log("Magic Pot puzzle: %s feeds %s to %s (id %s)", unitName(uid), potGift.name or "Ether", pot.name, tostring(pot.id))
                appendLog(string.format("  [MAGIC POT PUZZLE] %s gives %s to %s -> Instant Victory Payoff!", unitName(uid), potGift.name or "Ether", pot.name))
                return potGift
            else
                if not Fight.noEtherWarned then
                    Fight.noEtherWarned = true
                    if Hud and Hud.toast then Hud.toast("[MAGIC POT] Request: Ether (None in inventory!)") end
                    log("Magic Pot puzzle: %s wants an Ether, but bag has none!", pot.name)
                    appendLog("  [MAGIC POT WARNING] " .. pot.name .. " wants an Ether, but inventory has none!")
                end
            end
        else
            -- Ether already fed/queued: Party members defend/wait instead of dealing 1 damage
            local waitSkill = firstSkill(function(s)
                local sn = s.name and s.name:lower() or ""
                return s.kind == "defend" or (s.known and s.known.use == "guard") or sn:find("defend") or sn:find("guard") or s.kind == "buff"
            end)
            if waitSkill then
                local tids = (waitSkill.rel == REL.FRIEND or waitSkill.target == TGT.FRIEND) and idsOf(w.allies) or { uid }
                local choice = finishChoice(uid, waitSkill, "pot puzzle: stand by for victory", tids, aoeOf(waitSkill) and true or false)
                if choice then return choice end
            end
        end
    end

    -- Tank Aggro / Provoke / Multi-Cover: Tank draws hostility & guards party members.
    -- Priority #1 for Tanks (Rain/Sentinel): executes on turn 1 even if high-speed allies chipped first,
    -- and refreshes every 3 rounds to keep squishy party members protected.
    -- Boss Danger Move Telegraph
    if not Fight.dangerWarned and #w.enemies > 0 then
        for _, u in ipairs(w.enemies) do
            local card = mobOf(u)
            if card and card.danger and #card.danger > 0 then
                Fight.dangerWarned = true
                local moves = table.concat(card.danger, ", ")
                if Hud.toast then Hud.toast(string.format("[DANGER] %s Threat! [%s]", u.name, moves)) end
                log("Boss danger warning: %s [%s]", u.name, moves)
                appendLog("  Boss danger warning: " .. u.name .. " [" .. moves .. "]")
                learnBossThreshold(u.name, (u.hp or 1) * 100, Fight.rounds or 0)
                break
            end
        end
    end

    -- Live Tank Aggro Indicator + Automated Profile
    -- Natural HUD: Shows initial engagement for 3.5s, then cleanly fades out for the rest of battle!
    if not Fight.engagementBadgeShown then
        Fight.engagementBadgeShown = true
        local tankStatus = "Tactical Engage"
        if Fight.claim and Fight.claim.provoke then
            tankStatus = "Aggro Secured"
        end
        showBadge(string.format("[AUTO: %s]  |  %s", (autoProfileMode or "Auto"):upper(), tankStatus:upper()), 3.5)
    end

    -- Rain / Tank Aggro & Guard Priority:
    -- Rain must ALWAYS provoke, multi-cover, and hold enemy aggro to protect the party.
    local myKit = unitKit(uid) or {}
    local myMaxHp = stat(uid, PARAM.HP, true) or 1
    local myName = unitName(uid):lower()
    local isKnownTank = (myName:find("rain") ~= nil or myName:find("cecil") ~= nil or myName:find("charlotte") ~= nil
        or myName:find("snow") ~= nil or myName:find("basch") ~= nil or myName:find("sieghard") ~= nil
        or myName:find("wilhelm") ~= nil or myName:find("gladio") ~= nil or myName:find("wol") ~= nil
        or myName:find("warrior of light") ~= nil or myName:find("cagnazzo") ~= nil or myName:find("barret") ~= nil
        or myName:find("galuf") ~= nil or myName:find("gabranth") ~= nil)

    local otherBetterTankAlive = false
    for _, a in ipairs(w.allies) do
        if a.id ~= uid and not a.dead then
            local aKit = unitKit(a.id) or {}
            local aMaxHp = stat(a.id, PARAM.HP, true) or 1
            local aName = unitName(a.id):lower()
            local aIsKnownTank = (aName:find("rain") ~= nil or aName:find("cecil") ~= nil or aName:find("charlotte") ~= nil
                or aName:find("snow") ~= nil or aName:find("basch") ~= nil or aName:find("sieghard") ~= nil
                or aName:find("wilhelm") ~= nil or aName:find("gladio") ~= nil or aName:find("wol") ~= nil
                or aName:find("warrior of light") ~= nil or aName:find("cagnazzo") ~= nil or aName:find("barret") ~= nil
                or aName:find("galuf") ~= nil or aName:find("gabranth") ~= nil)

            if aIsKnownTank and not isKnownTank then
                otherBetterTankAlive = true
                break
            elseif (aKit.tankScore or 0) > 0 and aMaxHp > myMaxHp and not isKnownTank then
                otherBetterTankAlive = true
                break
            end
        end
    end

    local isDesignatedTank = isKnownTank or ((not otherBetterTankAlive) and ((myKit.tankScore or 0) > 0 or myName:find("rain") ~= nil))

    -- Check if any non-tank ally took damage (needs immediate cover/taunt protection)
    local anyAllyHurt = false
    for _, a in ipairs(w.allies) do
        if a.id ~= uid and not a.dead then
            local r = hpRatio(a.id)
            if r and r < 0.98 then
                anyAllyHurt = true
                break
            end
        end
    end

    local myHpRatio = hpRatio(uid) or 1
    local isBoss = w.boss or hardField or (#w.enemies == 1)

    -- Dynamic Party Health Assessment
    local allyInDanger = false
    local lowestAllyHp = 1.0
    for _, a in ipairs(w.allies) do
        if a.id ~= uid and not a.dead then
            local r = hpRatio(a.id)
            if r and r < lowestAllyHp then lowestAllyHp = r end
            if r and r < 0.50 then allyInDanger = true end
        end
    end

    -- Are enemies staggered / stunned? (Staggered foes deal 0 damage and take 2.0x bonus damage!)
    local allEnemiesStaggered = true
    local anyEnemyActive = false
    for _, e in ipairs(w.enemies) do
        if not e.broken and not (Fight.down and Fight.down[e.id]) then
            allEnemiesStaggered = false
            anyEnemyActive = true
            break
        end
    end

    -- Can Rain break, exploit a 3.0x weakness, or kill an enemy right now?
    local hasBreakKill = false
    for _, s in ipairs(skills) do
        if pay(s) and isHit(s, false) then
            for _, u in ipairs(w.enemies) do
                local gained, f = staggerOf(s, u)
                local _, remain, empty = gaugeOfEnemy(u)
                if (f >= 3) or (not empty and gained >= remain) then
                    hasBreakKill = true
                    break
                end
            end
        end
        if hasBreakKill then break end
    end

    -- Strict Mathematical Provoke Conditions:
    -- 1. NEVER provoke if enemies are staggered (they cannot attack!).
    -- 2. NEVER provoke if Rain can exploit an elemental weakness or shatter a break gauge (breaking is 100% mitigation + 2.0x team DPS).
    -- 3. On Bosses: NEVER provoke unless an ally is in mortal danger (< 40% HP) and boss is active.
    -- 4. On Swarms (2+ enemies): Only provoke if allies are wounded (< 60% HP) and Rain is healthy (> 50% HP).
    -- Strict Tank Provoke / Threat Control:
    -- Mathematical Rules:
    -- 1. NEVER provoke if enemies are staggered (they cannot attack!).
    -- 2. NEVER recast Provoke if any active enemy or party already has >= 1 turn of Provoke remaining!
    --    Provoke lasts 3 full rounds (3 -> 2 -> 1 -> expires at 0).
    --    Rain must NEVER waste an action refreshing it when 1 turn remains.
    -- 3. On Bosses: Establish on turn 1, then ONLY re-provoke once aggro has completely expired (0 turns left).
    -- 4. On Swarms (2+ enemies): Only provoke if squishy allies are hurt (< 70% HP) AND Provoke has expired (0 turns left).
    local turnsLeft = provokeTurnsRemaining()
    local needProvoke = false
    if turnsLeft <= 0 and isDesignatedTank and anyEnemyActive and not allEnemiesStaggered and myHpRatio >= 0.40 then
        if isLongFight then
            -- On Bosses & Long Fights: Tank must establish and maintain aggro once completely expired
            needProvoke = not (Fight.claim and Fight.claim.provoke)
        else
            -- On short mob swarms: Provoke only if squishy allies are taking heat (< 70% HP) and Provoke has expired
            needProvoke = (lowestAllyHp < 0.70 or anyAllyHurt) and not (Fight.claim and Fight.claim.provoke)
        end
    end

    -- If tank is critically wounded (< 35% HP), prioritize self-preservation (Sentinel / Defend / Potion)
    if isDesignatedTank and myHpRatio < 0.35 and phase == 0 and not dead then
        local selfGuard = firstSkill(function(s)
            local n = s.name and s.name:lower() or ""
            return (n:find("sentinel") or n:find("defend") or s.kind == "defend") and pay(s)
        end)
        if selfGuard then
            local choice = finishChoice(uid, selfGuard, "emergency tank defense", { uid }, false)
            if choice then return choice end
        end
    end

    if needProvoke and phase == 0 and not dead then
        local provokeSkill = firstSkill(function(s)
            local n = s.name and s.name:lower() or ""
            local u = useOf(s) or (s.known and s.known.use) or ""
            return (n:find("provoke") or n:find("taunt") or n:find("roar") or u == "provoke" or s.kind == "provoke")
                and (not n:find("cover")) and pay(s)
        end)
        if not provokeSkill and myHpRatio >= 0.50 then
            provokeSkill = firstSkill(function(s)
                local n = s.name and s.name:lower() or ""
                return (n:find("multi%-cover") or n:find("multi cover") or n:find("cover") or n:find("sentinel")) and pay(s)
            end)
        end
        if provokeSkill then
            local sName = provokeSkill.name and provokeSkill.name:lower() or ""
            local isAlly = friendAction(provokeSkill) or (provokeSkill.rel == REL.FRIEND) or (provokeSkill.target == TGT.FRIEND) or (provokeSkill.target == TGT.SELF) or (sName:find("cover") ~= nil) or (sName:find("sentinel") ~= nil)
            local spread = aoeOf(provokeSkill) or partyOf(provokeSkill) or (sName:find("multi%-cover") ~= nil) or (sName:find("multi cover") ~= nil)
            local tids = nil
            local reason = "tactical aggro"
            if isAlly then
                reason = "guard party"
                tids = spread and idsOf(w.allies) or { uid }
            else
                local provokeTarget = #pool > 0 and pool[1] or (w.enemies and w.enemies[1])
                tids = provokeTarget and { provokeTarget.id } or { uid }
            end
            local choice = finishChoice(uid, provokeSkill, reason, tids, spread and true or false)
            if choice then
                Fight.claim.provoke = true
                Fight.claim.provokeRound = Fight.rounds or 0
                Fight.provokeTurnsRemaining = 3
                Fight.lastProvokeAction = #(Fight.actions or {})
                return choice
            end
        end
    end

    if not Fight.chipped and phase == 0 and not alreadyFell and not allyCritical() and not dead then
        local scanTarget = nil
        for _, u in ipairs(#pool > 0 and pool or w.enemies) do
            if not Fight.scanned[u.id] and not Fight.claim.scan[u.id] then
                local card = mobOf(u)
                if not card or card.shift then scanTarget = u break end
            end
        end
        if scanTarget then
            local spell = firstSkill(function(s) return s.kind == "scan" end)
            if spell then
                local choice = finishChoice(uid, spell, "scout " .. scanTarget.name, { scanTarget.id }, false)
                if choice then
                    Fight.scanned[scanTarget.id] = true
                    Fight.claim.scan[scanTarget.id] = true
                    Fight.learnedAffinity = Fight.learnedAffinity or {}
                    local k = scanTarget.name and scanTarget.name:lower() or tostring(scanTarget.id)
                    Fight.learnedAffinity[k] = Fight.learnedAffinity[k] or {}
                    return choice
                end
            end
        end

        -- Auto-Steal: loot un-stolen enemies for rare upgrades & materials
        Fight.stolen = Fight.stolen or {}
        Fight.claim.steal = Fight.claim.steal or {}
        local stealTarget = nil
        for _, u in ipairs(#pool > 0 and pool or w.enemies) do
            if not Fight.stolen[u.id] and not Fight.claim.steal[u.id] then
                stealTarget = u
                break
            end
        end
        if stealTarget then
            local stealSkill = firstSkill(function(s)
                local n = s.name and s.name:lower() or ""
                return (n == "steal" or n == "mug" or s.kind == "steal" or (s.known and s.known.use == "steal")) and pay(s)
            end)
            if stealSkill then
                local choice = finishChoice(uid, stealSkill, "loot " .. stealTarget.name, { stealTarget.id }, false)
                if choice then
                    Fight.stolen[stealTarget.id] = true
                    Fight.claim.steal[stealTarget.id] = true
                    Fight.stolenLoot = Fight.stolenLoot or {}
                    Fight.stolenLoot[#Fight.stolenLoot + 1] = stealTarget.name
                    _G.FFR_LootedEnemies = _G.FFR_LootedEnemies or {}
                    _G.FFR_LootedEnemies[stealTarget.id] = true
                    if stealTarget.name then _G.FFR_LootedEnemies[stealTarget.name] = true end
                    return choice
                end
            end
        else
            if not Fight.allLootedTold and #(Fight.stolenLoot or {}) > 0 then
                Fight.allLootedTold = true
                if Hud and Hud.toast then Hud.toast("[LID] All drops secured! Shifting to Breaker debuffs.") end
            end
        end

        if not Fight.claim.hone[uid] then
            local s = firstSkill(function(x) return useOf(x) == "opener" end)
            if s and weaknessFits(s.cost or 0) then
                local choice = finishChoice(uid, s, "setup opener", { uid }, false)
                if choice then Fight.claim.hone[uid] = true return choice end
            end
        end
        local bossFight = hardField
        if bossFight and style ~= "aggressive" and not Fight.claim.guard then
            local s = firstSkill(function(x) return useOf(x) == "guardbuff" end)
            if s then
                local spread = aoeOf(s)
                local choice = finishChoice(uid, s, "setup guard", spread and idsOf(w.allies) or { uid }, spread)
                if choice then Fight.claim.guard = true return choice end
            end
        end
        if bossFight and (style ~= "aggressive") then
            local choice = castDebuff(false)
            if choice then return choice end
        end
        if bossFight and not Fight.claim.lb then
            local choice = setupLimit()
            if choice then return choice end
        end
        if bossFight and style ~= "aggressive" then
            local choice = summonChoice("setup")
            if choice then return choice end
        end
    end
    if (phase == 0) and hardField and (style ~= "aggressive") and (not allyCritical()) then
        local someoneDown = false
        for _, a in ipairs(w.allies) do
            if a.dead then someoneDown = true end
        end
        if not someoneDown then
            local choice = summonChoice("break")
            if (not choice) and Fight.esperOut then choice = summonChoice("again") end
            if (not choice) and (not Fight.esperOut) then choice = summonChoice("later") end
            if choice then return choice end
        end
    end
    -- The gauge may fill after the first chip. That one setup still goes
    -- out then. It does not go out after a fall, or while someone is critical.
    if phase == 0 and not Fight.claim.lb
        and not alreadyFell and not allyCritical() and not dead then
        local choice = setupLimit()
        if choice then return choice end
    end

    if phase == 0 and not AttacksOnly and not Fight.claim.lb and not dead then
        local bestLb, bestLbTarget, bestLbSpread, bestLbScore = nil, nil, false, -1
        for _, s in ipairs(skills) do
            if limitSkill(s) and limitReady(uid, s) and pay(s) then
                local use = useOf(s)
                if use ~= "lb-revive" and use ~= "guardbuff" and use ~= "heal" then
                    local isParty = s.known and s.known.party
                    if isParty then
                        local lbScore = 40000
                        if lbScore > bestLbScore then
                            bestLb, bestLbTarget, bestLbSpread, bestLbScore = s, "party", true, lbScore
                        end
                    else
                        local spread = aoeOf(s)
                        local targets = burstTargets()
                        local t = (targets and targets[1]) or (#pool > 0 and pool[1]) or (#open > 0 and open[1]) or w.enemies[1]
                        if t then
                            local lbScore = 50000
                            local breakPct = gaugeOfEnemy(t)
                            local isNearBreak = (breakPct > 0 and breakPct <= 35)

                            -- Stagger Burst Synchronization (2.0x Boss Shredder):
                            -- If target is an elite/boss and break gauge is near breaking (<35%),
                            -- hold single-target finisher Limit Bursts until the exact moment of Stagger,
                            -- letting break-building attacks shatter them first!
                            if not t.broken and isNearBreak and (hardField or #w.enemies <= 2) and not spread then
                                lbScore = 0 -- Hold LB for 1 turn to guarantee 2.0x damage window!
                            else
                                if t.broken then
                                    lbScore = lbScore + 120000 -- Massive priority spike: 2.0x bonus damage!
                                end
                                if spread and #w.enemies >= 2 then
                                    lbScore = lbScore + (#w.enemies * 15000)
                                end
                                local f = elementFactor(s, t)
                                if f >= 3 then lbScore = lbScore + 20000 end
                                if lbScore > bestLbScore then
                                    bestLb, bestLbTarget, bestLbSpread, bestLbScore = s, t, spread, lbScore
                                end
                            end
                        end
                    end
                end
            end
        end
        if bestLb and bestLbTarget then
            local tids = nil
            if bestLbTarget == "party" then
                tids = {}
                for _, a in ipairs(w.allies) do if not a.dead then tids[#tids + 1] = a.id end end
            elseif bestLbSpread then
                tids = idsOf(w.enemies)
            else
                tids = { bestLbTarget.id }
            end
            local choice = finishChoice(uid, bestLb, "limit burst " .. (bestLb.name or "limit"), tids, bestLbSpread)
            if choice then
                Fight.claim.lb = true
                return choice
            end
        end
    end

    local function unpaidWeakness(list)
        for _, s in ipairs(skills) do
            if isHit(s, false) and (s.cost or 0) > (w.mp or 0) then
                for _, u in ipairs(list) do
                    if elementFactor(s, u) >= 3 then return true end
                end
            end
        end
        return false
    end
    if band() == "low" and not Fight.claim.ether[uid] and not Fight.claim.etherRound then
        local list = #pool > 0 and pool or open
        if unpaidWeakness(list) then
            local ether = pickRecoveryItem(uid, w, "mp")
            if ether then
                ether.reason = "ether so the weakness fits"
                Fight.claim.ether[uid] = true
                Fight.claim.etherRound = true
                return ether
            end
        end
    end

    if Fight.chipped and (phase == 0) and (not allyCritical()) and (not dead) then
        local again = castDebuff(true)
        if again then return again end
    end

    -- Dedicated Healer & Support Party Buff Routine:
    -- Only in LONG fights should supports spend turns casting ramp-up buffs (Cheer, Protect, Shell, etc.)!
    -- In short fights, supports focus entirely on DAMAGE to eliminate enemies rapidly!
    if (isDedicatedHealer or whoStr:find("nichol")) and isLongFight then
        local partyHurtCount = 0
        for _, a in ipairs(w.allies) do
            if not a.dead and (a.hp or 1) < 0.70 then
                partyHurtCount = partyHurtCount + 1
            end
        end
        if partyHurtCount == 0 and not Fight.claim.buffTurn then
            Fight.buffCooldown = Fight.buffCooldown or {}
            for _, s in ipairs(skills) do
                local sName = (s.name or ""):lower()
                local sUse = useOf(s)
                local isBuff = (s.kind == "buff") or (sUse == "buff") or (sUse == "guardbuff")
                    or sName:find("cheer") or sName:find("protect") or sName:find("shell")
                    or sName:find("haste") or sName:find("regen") or sName:find("barrier")
                if isBuff and pay(s) then
                    local lastCast = Fight.buffCooldown[sName] or -99
                    local currentRound = #(Fight.actions or {})
                    if (currentRound - lastCast) >= 3 then
                        local spread = partyOf(s) or (s.known and s.known.party)
                        local targets = spread and idsOf(w.allies) or { uid }
                        local choice = finishChoice(uid, s, string.format("support buff %s", s.name or "buff"), targets, spread)
                        if choice then
                            Fight.buffCooldown[sName] = currentRound
                            Fight.claim.buffTurn = true
                            return choice
                        end
                    end
                end
            end
        end
    end

    local chip = castDamage(#pool > 0 and pool or open, false, mode)
    if chip then return chip end
    if mode == "adds" and bossU then
        chip = castDamage({ bossU }, false, "boss")
        if chip then return chip end
    end
    chip = castDamage(w.enemies, false, "field")
    if chip then return chip end
    local tactFoe = (#pool > 0 and pool[1]) or (w.enemies and w.enemies[1])
    if tactFoe then
        local itemHit = pickTacticalItem(uid, w, tactFoe)
        if itemHit then return itemHit end
    end
    if debuffOwed() or guardOwed() then Fight.deferChip = true end
    return nil
end

local function livingSnapshot()
    local snap = {}
    for _, id in ipairs(friendIds()) do
        snap[id] = { side = "ally", name = unitName(id), hp = hpRatio(id) or 1, broken = false }
    end
    for _, id in ipairs(members(REL.ENEMY)) do
        snap[id] = { side = "enemy", name = unitName(id), hp = hpRatio(id) or 1, broken = broken(id) }
    end
    return snap
end

local function noteChanges(now)
    local last = Fight.last
    local prevHit = Fight.prevHit
    for id, was in pairs(Fight.prev) do
        local cur = now[id]
        if was.side == "ally" and was.hp > 0 and (not cur or cur.hp <= 0) then
            Fight.fell[#Fight.fell + 1] = was.name
            appendLog("  fell: " .. was.name)
        end
        if was.side == "enemy" and not was.broken and cur and cur.broken then
            Fight.downTold = Fight.downTold or {}
            if not Fight.downTold[id] then
                Fight.downTold[id] = true
                local by = last and (last.who .. " (" .. last.skill .. ")") or "the party"
                Fight.broke[#Fight.broke + 1] = was.name .. " by " .. by
                appendLog("  broke: " .. was.name .. " by " .. by)
            end
        end

        -- =====================================================================
        -- EMPIRICAL COMBAT LEARNING: Observe damage results and learn resistances!
        -- =====================================================================
        if was.side == "enemy" and cur and prevHit and prevHit.id == id then
            local deltaHp = (was.hp or 1) - (cur.hp or 1)
            local sName = prevHit.skill and prevHit.skill:lower() or ""
            local skillRow = Known and Known.skills and Known.skills[sName]
            local elem = skillRow and (skillRow.element or skillRow.elements)
            if type(elem) == "table" then elem = elem[1] end
            if not elem then
                if sName:find("fire") or sName:find("fira") or sName:find("flame") then elem = "fire"
                elseif sName:find("blizz") or sName:find("frost") or sName:find("ice") then elem = "ice"
                elseif sName:find("thund") or sName:find("bolt") or sName:find("spark") then elem = "thunder"
                elseif sName:find("water") or sName:find("aqua") or sName:find("flood") then elem = "water"
                elseif sName:find("aero") or sName:find("gale") or sName:find("wind") then elem = "wind"
                elseif sName:find("stone") or sName:find("earth") or sName:find("quake") then elem = "earth"
                elseif sName:find("holy") or sName:find("banish") or sName:find("light") then elem = "light"
                elseif sName:find("dark") or sName:find("dystopia") or sName:find("bio") then elem = "dark"
                end
            end

            if elem and type(elem) == "string" then
                if deltaHp < -0.005 then
                    -- Enemy was HEALED by this element! ABSORPTION CONFIRMED!
                    learnAffinity(was.name, elem, "absorb")
                elseif deltaHp <= 0.0005 and (was.hp or 1) > 0.05 and not was.broken and not cur.broken then
                    -- Attack dealt 0 damage: IMMUNITY / NULL CONFIRMED!
                    learnAffinity(was.name, elem, "no")
                elseif deltaHp >= 0.18 or (cur.broken and not was.broken) then
                    -- Attack chunked >= 18% HP or shattered break gauge: WEAKNESS CONFIRMED!
                    learnAffinity(was.name, elem, "weak")
                end
            end

            if deltaHp > 0.04 and prevHit.who and prevHit.skill then
                learnSkillYield(prevHit.who, prevHit.skill, deltaHp)
            end
        end
    end
    Fight.prev = now
end

local function basicAttack(uid, skills, w)
    local attack = nil
    for _, s in ipairs(skills) do
        local cost = s.cost or 0
        local basic = (s.attr == ATTR.FIGHT) and (cost <= 0) and (s.kind ~= "defend") and (not s.isItem)
        if basic then
            local named = s.name and (s.name:lower() == "attack")
            if (not attack) or named then attack = s end
            if named then break end
        end
    end
    if not attack then return nil end
    local foe, best = nil, -1
    for _, e in ipairs(w.enemies or {}) do
        if not e.broken then
            local left = e.breakLeft or 0
            if left > best then
                foe = e
                best = left
            end
        end
    end
    if not foe then foe = w.enemies and w.enemies[1] end
    if not foe then return nil end
    return finishChoice(uid, attack, "attack " .. foe.name, { foe.id }, false)
end

local function kitFallback(uid)
    if cfg.AttacksOnly then return nil end
    local mp = stat(uid, PARAM.MP, false) or 0
    local usable = {}
    local ids = {}
    pcall(function() ids = equippedIds(uid) end)
    for _, id in ipairs(ids) do
        local ok, s = pcall(skillOf, id)
        if ok and s and not SKIP[s.attr] and s.attr ~= ATTR.FINISH and s.attr ~= ATTR.SUMMON and s.attr ~= ATTR.ITEM then
            local copy = {}
            for k, v in pairs(s) do copy[k] = v end
            copy.known = knownOf(copy)
            local use = copy.known and copy.known.use
            local cost = 0
            pcall(function() cost = skillCost(uid, id, false) or 0 end)
            copy.cost = cost
            local okKind, kind = pcall(classify, copy)
            local name = copy.name and copy.name:lower() or ""
            local plain = (name == "attack") or ((copy.attr == ATTR.FIGHT) and (cost <= 0) and (kind ~= "defend"))
            local tagged = (use == "break") or (use == "cash")
            local damage = tagged or plain or (okKind and kind == "damage")
            local held = (use == "skip") or (use == "opener") or (use == "guardbuff") or (use == "guard")
                or (use == "scan") or (use == "heal") or (use == "cure") or (use == "debuff")
                or (use == "buff") or (use == "lb-setup") or (use == "lb-revive") or (use == "lb-cash")
                or (use == "provoke") or (use == "steal")
                or (copy.attr == ATTR.LB)
            if damage and not held and (cost <= mp) and not (Fight.deferChip and (cost > 0)) then
                copy.kind = "damage"
                usable[#usable + 1] = copy
            end
        end
    end
    local best, bestR = nil, -1
    for _, s in ipairs(usable) do
        local okOff, pow, br = pcall(offenseOf, s)
        local score = 0
        if okOff then score = (br or 0) * 1000 + (pow or 0) end
        local name = s.name and s.name:lower() or ""
        local use = s.known and s.known.use
        local plain = (name == "attack") or ((s.attr == ATTR.FIGHT) and ((s.cost or 0) <= 0))
        local tagged = (use == "break") or (use == "cash")
        -- Plain Attack and a published damage row beat an unlabeled skill.
        if plain or tagged then score = score + 1000000 end
        if score > bestR then best, bestR = s, score end
    end
    if not best and SkillIdx then
        for id, s in pairs(SkillIdx) do
            if (not best) and (s.attr == ATTR.FIGHT) and (activation(uid, id) == true) then
                local copy = tagSkill(uid, id, true)
                if copy and ((not copy.known) or (copy.known.use ~= "skip")) and ((copy.cost or 0) <= mp) then
                    best = copy
                end
            end
        end
    end
    if not best then return nil end
    local tid = nil
    pcall(function()
        local list = members(REL.ENEMY)
        tid = list[1]
    end)
    if not tid then
        pcall(function()
            local probe = targetsFor(uid, best, REL.ENEMY)
            tid = probe and probe[1]
        end)
    end
    if not tid then return nil end
    return finishChoice(uid, best, "kit " .. unitName(tid), { tid }, false)
end

local function consider(uid)
    if outOfControl(uid) then
        log("%s is %s; leaving this turn", unitName(uid), outOfControl(uid))
        return nil
    end
    local usable = usableOf(uid)
    if #usable == 0 then
        log("%s: no usable skill", unitName(uid))
        return nil
    end
    local w = worldOf(uid, Fight.boss, Fight.summoned)
    if not Fight.usedSupport[uid] then Fight.usedSupport[uid] = {} end
    w.usedSupport = Fight.usedSupport[uid]
    local function addFoe(id)
        if not keepFoe(id) then return end
        for _, e in ipairs(w.enemies) do
            if e.id == id then return end
        end
        local name = unitName(id)
        local r = hpRatio(id)
        if r ~= nil and r <= 0 then return end
        local isBroken, left = broken(id), breakLeft(id)
        if Fight and Fight.gaugeOf then isBroken, left = Fight.gaugeOf(id, name) end
        w.enemies[#w.enemies + 1] = {
            id = id, name = name, hp = r or 1,
            broken = isBroken, breakLeft = left, statuses = statuses(id),
        }
        Fight.seenFoe = Fight.seenFoe or {}
        Fight.seenFoe[id] = name
    end
    for _, s in ipairs(usable) do
        if s.kind == "damage" or s.attr == ATTR.FIGHT or s.attr == ATTR.MAGIC or s.attr == ATTR.ABILITY then
            for _, id in ipairs(targetsFor(uid, s, REL.ENEMY)) do addFoe(id) end
        end
    end
    if Fight and not Fight.fieldTold and #w.enemies > 0 then
        Fight.fieldTold = true
        local actors = 0
        for _, a in ipairs(w.allies) do
            if a.acts and not a.dead then actors = actors + 1 end
        end
        local bits = {}
        for _, e in ipairs(w.enemies) do
            local card = mobOf(e)
            local weak = " unknown"
            if card and card.weak then
                local els = {}
                for el, on in pairs(card.weak) do
                    if on then els[#els + 1] = el end
                end
                table.sort(els)
                weak = (#els > 0) and (" weak " .. table.concat(els, ",")) or ""
            end
            local gauge = card and card.gauge and (" gauge " .. tostring(card.gauge)) or ""
            bits[#bits + 1] = e.name .. weak .. gauge
        end
        local line = string.format("field: %d foes, %d who can act. %s",
            #w.enemies, actors, table.concat(bits, "; "))
        log("%s", line)
        appendLog("  " .. line)
        if Advisor and not Fight.advisorDone and #w.allies > 0 then
            Fight.advisorDone = true
            local advSummary, advHud = Advisor.analyzeParty(w.allies, equippedIds, skillOf, knownOf, DIR .. "/mathematical_advisor.txt")
            if advHud then
                lastAdvisorHudText = advHud
                if advisorVisible then
                    Hud.advisorShow(advHud)
                end
            end
            if advSummary then
                log("[MATH ADVISOR] %s", advSummary)
                appendLog("  [MATH ADVISOR] " .. advSummary)
                if Hud.toast then Hud.toast("[RADAR] " .. advSummary) end
            end
        end
    end
    for _, s in ipairs(usable) do
        if s.kind == "revive" then
            for _, id in ipairs(targetsFor(uid, s, REL.FRIEND)) do
                local curHp = stat(id, PARAM.HP, false)
                -- Live HP Check: NEVER flag an ally as dead if they are alive (HP > 0)!
                if curHp ~= nil and curHp <= 0 then
                    local seen = false
                    for _, a in ipairs(w.allies) do
                        if a.id == id then a.dead = true seen = true end
                    end
                    if not seen then
                        w.allies[#w.allies + 1] = { id = id, name = unitName(id), hp = 0, dead = true, statuses = {}, acts = true }
                    end
                end
            end
        end
    end
    local phase = currentPhase()
    if phase ~= PHASE_FINISH and inFinishPhase() then phase = PHASE_FINISH end
    if cfg.AttacksOnly then
        if phase == PHASE_FINISH then return nil end
        return basicAttack(uid, usable, w)
    end
    local okChoice, choice = pcall(turn, uid, usable, w, phase)
    if not okChoice then
        log("choice failed: %s", tostring(choice))
        choice = nil
    end
    if choice then return choice end
    local foe = w.enemies and w.enemies[1]
    if foe then
        local tact = pickTacticalItem(uid, w, foe)
        if tact then return tact end
        local swing, swingR = nil, -1
        for _, s in ipairs(usable) do
            local playerOnly = s.known and s.known.use == "skip"
            local damage = (s.kind == "damage" or s.attr == ATTR.FIGHT) and not playerOnly
            if damage and s.kind ~= "heal" and s.kind ~= "buff" and s.attr ~= ATTR.FINISH
                and (s.cost or 0) <= (w.mp or 0)
                and not (Fight.deferChip and ((s.cost or 0) > 0)) then
                local _, br = offenseOf(s)
                local score = (br or 0) * 1000 + (s.power or 0)
                if score > swingR then swing, swingR = s, score end
            end
        end
        if swing then
            return finishChoice(uid, swing, "kit " .. foe.name, { foe.id }, false)
        end
    end
    if Fight.deferChip then
        for _, s in ipairs(usable) do
            if s.kind == "defend" and (s.cost or 0) <= (w.mp or 0) then
                return finishChoice(uid, s, "hold for debuff", { uid }, false)
            end
        end
        log("%s: holding the chip until the debuff lands", unitName(uid))
        return nil
    end
    local hurt = lowestAlly(w, function(u) return u.acts ~= false end)
    if (not foe) and hurt and (hurt.hp or 1) < 0.30 then
        for _, s in ipairs(usable) do
            if s.kind == "defend" then
                return finishChoice(uid, s, "defend", { uid }, false)
            end
        end
    end
    log("%s: nothing legal this turn", unitName(uid))
    return nil
end

local combatSpeeds = { 1.0, 1.5, 2.0 }
local combatSpeedIdx = 1

local function toggleCombatSpeed()
    combatSpeedIdx = (combatSpeedIdx % #combatSpeeds) + 1
    local spd = combatSpeeds[combatSpeedIdx]
    pcall(function()
        ExecuteConsoleCommand(string.format("slomo %.1f", spd))
    end)
    local tag = (spd == 1.0) and "Normal" or ((spd == 1.5) and "Fast" or "Turbo")
    showToast(string.format("[SPEED] Combat Speed: %.1fx (%s)", spd, tag))
    log("Combat speed set to %.1fx (%s)", spd, tag)
end

local function resetCombatSpeed()
    if combatSpeedIdx ~= 1 then
        combatSpeedIdx = 1
        pcall(function() ExecuteConsoleCommand("slomo 1.0") end)
    end
end

local function finishBattle()
    if not Fight.active then return end
    Fight.active = false
    if Hud and Hud.advisorShow then Hud.advisorShow(nil) end
    lastAdvisorHudText = ""
    local turns = #Fight.actions
    local broke = (#Fight.broke > 0) and table.concat(Fight.broke, ", ") or "nobody broken"
    local fell = (#Fight.fell > 0) and table.concat(Fight.fell, ", ") or "no one fell"
    for _, who in ipairs(Fight.castOrder) do
        local rec = Fight.casts[who]
        if rec then
            local parts = {}
            for _, name in ipairs(rec.order) do
                local n = rec.n[name]
                parts[#parts + 1] = (n > 1) and (name .. " x" .. n) or name
            end
            appendLog("  " .. who .. ": " .. table.concat(parts, ", "))
        end
    end
    local line = string.format("Auto, %d commands. %s. %s.", turns, broke, fell)
    appendLog("-- " .. line)
    appendLog("")
    log("battle %d done: %s", Fight.number, line)
    local bonusTag = Fight.resonanceSent and " [Overkill Drop Bonus]" or ""
    if Fight.stolenLoot and #Fight.stolenLoot > 0 then
        local names = table.concat(Fight.stolenLoot, ", ")
        if Hud.toast then Hud.toast("[VICTORY]" .. bonusTag .. " Loot Stolen from: " .. names) end
    else
        if Hud.toast then Hud.toast(string.format("[VICTORY]%s Battle %d Cleared (%d actions)", bonusTag, Fight.number, turns)) end
    end
    showBadge(nil)
    resetCombatSpeed()
    Fight.adaptiveSpeedApplied = false
    _G.FFR_LootedEnemies = {}

    -- 1. Save learned bestiary weaknesses & affinities persistently
    pcall(function()
        if Fight and Fight.learnedAffinity and next(Fight.learnedAffinity) then
            local lines = { "-- Persistent Bestiary Memory for Final Fantasy Resonance", "return {" }
            for k, aff in pairs(Fight.learnedAffinity) do
                local parts = {}
                if aff.weak and next(aff.weak) then
                    local wList = {}
                    for el in pairs(aff.weak) do wList[#wList + 1] = string.format("[%q]=true", el) end
                    parts[#parts + 1] = "weak={" .. table.concat(wList, ",") .. "}"
                end
                if aff.absorb and next(aff.absorb) then
                    local aList = {}
                    for el in pairs(aff.absorb) do aList[#aList + 1] = string.format("[%q]=true", el) end
                    parts[#parts + 1] = "absorb={" .. table.concat(aList, ",") .. "}"
                end
                if aff.no and next(aff.no) then
                    local nList = {}
                    for el in pairs(aff.no) do nList[#nList + 1] = string.format("[%q]=true", el) end
                    parts[#parts + 1] = "no={" .. table.concat(nList, ",") .. "}"
                end
                if aff.half and next(aff.half) then
                    local hList = {}
                    for el in pairs(aff.half) do hList[#hList + 1] = string.format("[%q]=true", el) end
                    parts[#parts + 1] = "half={" .. table.concat(hList, ",") .. "}"
                end
                if #parts > 0 then
                    lines[#lines + 1] = string.format("  [%q] = { %s },", k, table.concat(parts, ", "))
                end
            end
            lines[#lines + 1] = "}"
            local f = io.open(DIR .. "/Scripts/bestiary_memory.lua", "w")
            if f then
                f:write(table.concat(lines, "\n"))
                f:close()
                log("saved persistent bestiary memory")
            end
        end
    end)

    -- 2. Save learned tactical memory (boss danger thresholds & skill yields)
    pcall(function()
        if TacticalMemory and (next(TacticalMemory.bossThresholds or {}) or next(TacticalMemory.skillYield or {})) then
            local lines = { "-- Persistent Tactical & Pattern Memory for Final Fantasy Resonance", "return {" }
            lines[#lines + 1] = "  bossThresholds = {"
            for bName, thresh in pairs(TacticalMemory.bossThresholds or {}) do
                lines[#lines + 1] = string.format("    [%q] = { %s },", bName, table.concat(thresh, ", "))
            end
            lines[#lines + 1] = "  },"
            lines[#lines + 1] = "  skillYield = {"
            for wName, skills in pairs(TacticalMemory.skillYield or {}) do
                lines[#lines + 1] = string.format("    [%q] = {", wName)
                for sName, dat in pairs(skills) do
                    lines[#lines + 1] = string.format("      [%q] = { total=%.2f, uses=%d, avg=%.2f },", sName, dat.total or 0, dat.uses or 1, dat.avg or 0)
                end
                lines[#lines + 1] = "    },"
            end
            lines[#lines + 1] = "  },"
            lines[#lines + 1] = "}"
            local f = io.open(DIR .. "/Scripts/tactical_memory.lua", "w")
            if f then
                f:write(table.concat(lines, "\n"))
                f:close()
                log("saved persistent tactical memory")
            end
        end
    end)

    -- Outworld Auto-Camp & MP Low Reserves Alert
    pcall(function()
        local totalCurMp, totalMaxMp = 0, 0
        local allies = friendIds()
        for _, aid in ipairs(allies or {}) do
            local cur = stat(aid, PARAM.MP, false) or 0
            local max = stat(aid, PARAM.MP, true) or 1
            totalCurMp = totalCurMp + cur
            totalMaxMp = totalMaxMp + max
        end
        if totalMaxMp > 0 and (totalCurMp / totalMaxMp) < 0.30 then
            local b = bag()
            local healItem = nil
            for _, it in ipairs(b or {}) do
                local iname = (it.name or ""):lower()
                if iname:find("tent") or iname:find("cottage") or iname:find("ether") then
                    healItem = it
                    break
                end
            end
            if healItem and Hud and Hud.toast then
                Hud.toast(string.format("[AUTO-RECOVERY] Party MP Low (<30%%) | Bag: %s (%d left)", healItem.name, healItem.count or 1))
            elseif Hud and Hud.toast then
                Hud.toast("[AUTO-RECOVERY] Party MP Low (<30%%) | Tip: Rest at campfire or save point!")
            end
        end
    end)

    Fight.actions, Fight.casts, Fight.castOrder = {}, {}, {}
    Fight.broke, Fight.fell, Fight.prev, Fight.last = {}, {}, {}, nil
end

local function ensureBattle()
    if Fight.active then return end
    Fight.active = true
    Fight.engagementBadgeShown = false
    Fight.number = Fight.number + 1
    Fight.boss = bossBattle()
    Fight.summoned = false
    Fight.usedSupport = {}
    Fight.actions, Fight.casts, Fight.castOrder = {}, {}, {}
    Fight.broke, Fight.fell, Fight.prev = {}, {}, livingSnapshot()
    Fight.scanned, Fight.stolen, Fight.elemRun, Fight.seenAlly = {}, {}, {}, {}
    Fight.resonanceSent = false
    Fight.resonanceMiss = false
    Fight.poured, Fight.down, Fight.downTold, Fight.relax, Fight.gaugeScale, Fight.brokeOn, Fight.gaugeSure, Fight.gaugeWas = {}, {}, {}, {}, {}, {}, {}, {}
    Fight.downSince, Fight.phaseSeen, Fight.bonusSeen, Fight.lastHit = nil, 0, false, nil
    Fight.line = false
    Fight.prevHit = nil
    Fight.building = nil
    Fight.kits = {}
    Fight.claim = { heal = {}, revive = {}, hone = {}, ether = {}, scan = {}, steal = {}, etherRound = false, guard = false, esper = false, lb = false, provoke = false, provokeRound = -99, provokeTurnsRemaining = 0 }
    Fight.lastProvokeAction = -99
    Fight.learnedAffinity = Fight.learnedAffinity or {}
    Fight.debuffOn, Fight.debuffSeen, Fight.debuffTold = {}, {}, {}
    Fight.went, Fight.rounds, Fight.seenFoe = {}, 0, {}
    Fight.planTag, Fight.afterBonus = nil, false
    Fight.fieldTold = false
    Fight.chipped = false
    Fight.esperOut = nil
    Fight.esperTold = false
    Fight.esperSkip = {}
    Fight.limitUntagged = {}
    Fight.limitSkip = {}
    Fight.cureHeld = false
    Fight.healLeft = {}
    Fight.downNow = {}
    Fight.lbRead = {}
    Fight.lbGaugeApi = {}
    Fight.unmarked = false
    Fight.unmarkedTold = false
    Fight.recoverTold = false
    Fight.finishNote = {}
    Fight.finishScan = nil
    itemsLogged = false
    potLogged = false
    appendLog(string.format("== battle %d%s ==", Fight.number, Fight.boss and ", boss" or ""))
    log("battle %d%s", Fight.number, Fight.boss and ", boss" or "")
end

local function rememberCast(who, skill)
    local rec = Fight.casts[who]
    if not rec then
        rec = { order = {}, n = {} }
        Fight.casts[who] = rec
        Fight.castOrder[#Fight.castOrder + 1] = who
    end
    if not rec.n[skill] then rec.order[#rec.order + 1] = skill end
    rec.n[skill] = (rec.n[skill] or 0) + 1
end

local function settleGauges()
    Fight.poured = Fight.poured or {}
    Fight.down = Fight.down or {}
    Fight.downTold = Fight.downTold or {}
    Fight.relax = Fight.relax or {}
    Fight.gaugeScale = Fight.gaugeScale or {}
    Fight.brokeOn = Fight.brokeOn or {}
    local phaseNow = currentPhase()
    local prevPhase = Fight.phaseSeen or 0
    if prevPhase ~= 0 and phaseNow == 0 then
        local ids = {}
        for id in pairs(Fight.down) do ids[#ids + 1] = id end
        for _, id in ipairs(ids) do
            Fight.poured[id] = 0
            Fight.down[id] = nil
            Fight.downTold[id] = nil
            Fight.relax[id] = nil
        end
        Fight.bonusSeen = false
        Fight.downSince = nil
        Fight.afterBonus = true
        Fight.brokeOn = {}
    end
    if phaseNow == PHASE_BONUS or phaseNow == PHASE_FINISH then
        Fight.bonusSeen = true
        Fight.unmarked = false
        Fight.gaugeSure = Fight.gaugeSure or {}
        Fight.gaugeWas = Fight.gaugeWas or {}
        local caught = {}
        for id in pairs(Fight.gaugeWas) do caught[#caught + 1] = id end
        local party = 0
        for _ in pairs(Fight.seenAlly or {}) do party = party + 1 end
        if party < 2 then party = 2 end
        for _, id in ipairs(caught) do
            local rec = Fight.gaugeWas[id]
            local old = rec and rec.size
            local at = (rec and rec.at) or 0
            local fresh = (type(old) == "number") and ((#(Fight.actions or {}) - at) <= party)
            if fresh and Fight.brokeOn[id] then
                Fight.gaugeScale[id] = old
                Fight.gaugeSure[id] = old
                Fight.down[id] = true
                Fight.downTold[id] = true
                Fight.relax[id] = nil
                Fight.poured[id] = 0
                Fight.gaugeWas[id] = nil
                log("%s bonus caught the release. working gauge restored %d", unitName(id), old)
            elseif not fresh then
                Fight.gaugeWas[id] = nil
            end
        end
        local function rememberSure(id)
            if not id or Fight.gaugeSure[id] then return end
            local scaled = Fight.gaugeScale and Fight.gaugeScale[id]
            local poured = Fight.poured[id] or 0
            local card = mobOf({ id = id, name = unitName(id) })
            local book = card and tonumber(card.gauge) or nil
            local size = (((type(scaled) == "number") and (scaled > 0) and scaled) or book)
            if (type(scaled) == "number") and (scaled > 0) and (poured > 0) and (poured < scaled) then
                local proved = math.floor(poured + 0.5)
                if (type(book) == "number") and (proved < book) then proved = book end
                Fight.gaugeScale[id] = proved
                Fight.down[id] = true
                Fight.downTold[id] = true
                Fight.relax[id] = nil
                Fight.poured[id] = 0
                size = proved
                log("%s bonus proved the poured stagger. working gauge %d", unitName(id), proved)
            end
            if (type(size) == "number") and (size > 0) then Fight.gaugeSure[id] = size end
        end
        for id, on in pairs(Fight.down) do
            if on then rememberSure(id) end
        end
        for id, on in pairs(Fight.brokeOn) do
            if on then rememberSure(id) end
        end
        local any = false
        for _, on in pairs(Fight.down) do
            if on then any = true break end
        end
        local last = Fight.lastHit
        if not any and last and #last > 0 then
            local best, bestScore = nil, -1
            for _, tid in ipairs(last) do
                local poured = Fight.poured[tid] or 0
                local card = mobOf({ id = tid, name = unitName(tid) })
                local gauge = card and tonumber(card.gauge) or 0
                local scaled = Fight.gaugeScale and Fight.gaugeScale[tid]
                if scaled and scaled > gauge then gauge = scaled end
                local score = (gauge > 0) and (poured / gauge) or 0
                if score > bestScore then best, bestScore = tid, score end
            end
            if best and bestScore >= 1 then
                Fight.down[best] = true
                Fight.brokeOn = Fight.brokeOn or {}
                Fight.brokeOn[best] = true
                if not Fight.downSince then Fight.downSince = #Fight.actions end
            end
        end
    end
    Fight.phaseSeen = phaseNow
    if not Fight.bonusSeen and Fight.downSince then
        local allies = 0
        for _ in pairs(Fight.seenAlly or {}) do allies = allies + 1 end
        if allies < 2 then allies = 2 end
        if (#Fight.actions - Fight.downSince) >= allies then
            local ids = {}
            for id in pairs(Fight.down) do ids[#ids + 1] = id end
            for _, id in ipairs(ids) do
                Fight.down[id] = nil
                Fight.downTold[id] = nil
                Fight.relax[id] = true
                local sure = Fight.gaugeSure and Fight.gaugeSure[id]
                if (type(sure) == "number") then
                    Fight.poured[id] = 0
                    log("%s break held. working gauge stays %d", unitName(id), sure)
                else
                    local poured = Fight.poured[id] or 0
                    local card = mobOf({ id = id, name = unitName(id) })
                    local book = (card and tonumber(card.gauge)) or 100
                    local grown = math.floor((poured / 0.72) + 0.5)
                    if grown < (book + 1) then grown = book + 1 end
                    if Gauges.rise then grown = Gauges.rise(book, poured) end
                    local prev = Fight.gaugeScale[id] or book
                    if grown > prev then
                        Fight.gaugeWas = Fight.gaugeWas or {}
                        Fight.gaugeWas[id] = { size = prev, at = #(Fight.actions or {}) }
                        Fight.gaugeScale[id] = grown
                    end
                    log("%s gauge estimate released, no bonus phase. working gauge %d",
                        unitName(id), Fight.gaugeScale[id] or grown)
                end
            end
            Fight.downSince = nil
        end
    end
end

local function noteRound(uid)
    Fight.went = Fight.went or {}
    if uid and (uid >= 0) then Fight.went[uid] = true end
    local actors, went = 0, 0
    for _, id in ipairs(friendIds()) do
        local ratio = hpRatio(id)
        if (ratio == nil) or (ratio > 0) then
            local kit = unitKit(id)
            if kit and kit.spells and (#kit.spells > 0) then
                actors = actors + 1
                if Fight.went[id] then went = went + 1 end
            end
        end
    end
    if (actors > 0) and (went >= actors) then
        Fight.went = {}
        Fight.healLeft = {}
        Fight.rounds = (Fight.rounds or 0) + 1
        if Fight.claim then
            Fight.claim.heal = {}
            Fight.claim.ether = {}
            Fight.claim.etherRound = false
            -- Decrement Provoke remaining turns with each completed round:
            if Fight.provokeTurnsRemaining and Fight.provokeTurnsRemaining > 0 then
                Fight.provokeTurnsRemaining = Fight.provokeTurnsRemaining - 1
            end
            local roundsElapsed = (Fight.rounds or 0) - (Fight.claim.provokeRound or -99)
            if (Fight.provokeTurnsRemaining or 0) <= 0 or roundsElapsed >= 3 then
                Fight.claim.provoke = false
                Fight.provokeTurnsRemaining = 0
            end
        end
        Fight.afterBonus = false
    end
end

local function markSummon(skill, turns)
    if not (skill and skill.attr == ATTR.SUMMON) then return end
    local fact = (Espers.lookup and Espers.lookup(skill.name)) or nil
    local stay = turns or (fact and fact.turns) or 3
    Fight.esperOut = {
        at = #(Fight.actions or {}),
        turns = stay,
        name = skill.name or "summon",
        element = fact and fact.element or nil,
        role = fact and fact.role or nil,
        told = false,
    }
    Fight.summoned = true
    Fight.claim = Fight.claim or {}
    Fight.claim.esper = true
    if showToast then
        local elName = fact and fact.element and (" (" .. fact.element:upper() .. " Resonance)") or ""
        showToast(string.format("[ESPER ACTIVE] %s Summoned!%s", skill.name or "Summon", elName))
    end
end

local function act(serial)
    if not cfg.Enabled then return end
    if (not Menu.open) or (Menu.serial ~= serial) or Menu.sub or Menu.decided then return end
    local uid = currentActor()
    if uid < 0 then uid = Menu.actor end
    if uid < 0 then return end
    pcall(ensureBattle)
    -- A wipe puts the party back on its opening MP without a raise we sent.
    -- The stagger book and the one-time setup belong to the attempt that fell.
    local function noteMp(who)
        local mp = stat(who, PARAM.MP, false)
        if (not mp) or (mp <= 0) or (not Fight) or (not Fight.active) then return end
        Fight.mpAnchor = Fight.mpAnchor or {}
        Fight.mpLow = Fight.mpLow or {}
        Fight.mpBack = Fight.mpBack or {}
        local anchor = Fight.mpAnchor[who]
        if (not anchor) or (mp > anchor) then
            Fight.mpAnchor[who] = mp
            anchor = mp
        end
        if mp < (anchor * 0.8) then
            Fight.mpLow[who] = true
            Fight.mpBack[who] = nil
        elseif Fight.mpLow[who] and (mp >= (anchor * 0.95)) then
            Fight.mpBack[who] = true
        end
        local n, party = 0, 0
        for _, on in pairs(Fight.mpBack) do
            if on then n = n + 1 end
        end
        for _ in pairs(Fight.seenAlly or {}) do party = party + 1 end
        local need = 3
        if party == 2 then need = 2 end
        if n < need then return end
        Fight.mpBack = {}
        Fight.mpLow = {}
        Fight.poured, Fight.down, Fight.downTold = {}, {}, {}
        Fight.relax, Fight.gaugeScale, Fight.brokeOn = {}, {}, {}
        Fight.gaugeSure, Fight.gaugeWas = {}, {}
        Fight.broke, Fight.fell = {}, {}
        Fight.downSince, Fight.bonusSeen, Fight.planTag = nil, false, nil
        Fight.chipped = false
        Fight.claim = Fight.claim or {}
        Fight.claim.lb = false
        Fight.claim.guard = false
        Fight.claim.hone = {}
        Fight.claim.esper = false
        Fight.esperOut = nil
        Fight.debuffOn, Fight.debuffSeen = {}, {}
        local line = "party restored. ledger cleared"
        log("%s", line)
        appendLog("  " .. line)
    end
    pcall(noteMp, uid)
    local actorName = unitName(uid)
    if Espers.lookup and Espers.lookup(actorName) then
        local line = actorName .. " acts on its own"
        log("%s", line)
        appendLog("  " .. line)
        return
    end
    local finishingEarly = false
    pcall(function() finishingEarly = inFinishPhase() end)
    if finishingEarly and Fight.resonanceSent then return end
    pcall(function() noteChanges(livingSnapshot()) end)
    pcall(settleGauges)
    Fight.deferChip = false
    local okPlan, choice = pcall(consider, uid)
    if not okPlan then
        log("plan failed: %s", tostring(choice))
        choice = nil
    end
    if not choice then
        local okKit, hit = pcall(kitFallback, uid)
        if okKit then
            choice = hit
        else
            log("kit fallback failed: %s", tostring(hit))
        end
    end
    if not choice then
        log("%s: no command sent", unitName(uid))
        return
    end
    local finishing = false
    pcall(function() finishing = inFinishPhase() end)
    if finishing then
        -- During FinishPhase, normal command submission must NEVER run!
        -- Resonance is handled exclusively by resonanceWatch using native CPP_VM_BtlCmd:DecideActionKey
        return
    end
    if not Menu.open or Menu.serial ~= serial then return end
    local who = unitName(uid)
    local phase = finishing and PHASE_FINISH or currentPhase()
    local mpNow = stat(uid, PARAM.MP, false)
    local line = string.format("%s p%d mp%s: %s -> %s", who, phase, tostring(mpNow or "?"), choice.name, choice.reason)
    if not cfg.Submit then
        appendLog("  (not sent) " .. line)
        log("(not sent) %s", line)
        return
    end
    local ok, sent = pcall(send, uid, choice, phase)
    if not ok then
        log("send failed: %s", tostring(sent))
        return
    end
    if not sent then return end
    if choice.attr == ATTR.FINISH then Fight.resonanceSent = true end
    if phase == 0 and choice.kind == "damage" and not choice.isItem then
        Fight.line = true
        local reason = choice.reason or ""
        if (choice.cost or 0) > 0 and (not reason:find("^setup")) and (choice.attr ~= ATTR.SUMMON) then
            Fight.chipped = true
        end
    end
    local limitCast = choice.attr == ATTR.LB
    if choice.known then
        local use = choice.known.use
        if (use == "lb-setup") or (use == "lb-cash") or (use == "lb-revive") then limitCast = true end
    end
    if phase == 0 and choice.targets and ((choice.kind == "damage") or limitCast) and not choice.isItem
        and (choice.attr ~= ATTR.SUMMON) then
        Fight.poured = Fight.poured or {}
        Fight.down = Fight.down or {}
        Fight.relax = Fight.relax or {}
        Fight.gaugeScale = Fight.gaugeScale or {}
        Fight.lastHit = choice.targets
        local row = skillOf(choice.id)
        local _, br = offenseOf(row or choice)
        if br > 0 then
            for _, tid in ipairs(choice.targets) do
                if not Fight.down[tid] then
                    if Fight.relax[tid] then
                        Fight.relax[tid] = nil
                    end
                    local enemy = { id = tid, name = unitName(tid) }
                    local card = mobOf(enemy)
                    local gauge = card and tonumber(card.gauge) or nil
                    local scaled = Fight.gaugeScale[tid]
                    if scaled and (not gauge or scaled > gauge) then gauge = scaled end
                    local factor = elementFactor(row or choice, enemy)
                    if gauge and gauge > 0 and factor > 0 then
                        Fight.poured[tid] = (Fight.poured[tid] or 0) + br * factor
                    end
                end
            end
        end
    end
    if Fight.elemRun and choice.targets and choice.known and choice.known.element
        and (choice.attr ~= ATTR.SUMMON) then
        local el = choice.known.element
        for _, tid in ipairs(choice.targets) do
            local run = Fight.elemRun[tid]
            if run and run.el == el then run.n = run.n + 1
            else Fight.elemRun[tid] = { el = el, n = 1 } end
        end
    end
    Fight.actions[#Fight.actions + 1] = line
    if choice.attr == ATTR.SUMMON then markSummon(choice, choice.esperTurns) end
    rememberCast(who, choice.name)
    Fight.last = { who = who, skill = choice.name }
    Fight.prevHit = {
        who = who, skill = choice.name, kind = choice.kind,
        id = choice.targets and choice.targets[1],
    }
    if choice.kind == "damage" and Fight.prevHit.id then
        Fight.building = Fight.prevHit.id
    end
    noteRound(uid)
    appendLog("  " .. line)
    log("%s", line)
end

--------------------------------------------------------------------------------
-- A command the player chose. The same ledger the mod writes for its own sends.
--------------------------------------------------------------------------------

local function noteHand(v)
    if not (Fight and v) then return end
    pcall(ensureBattle)
    if not Fight.active then return end
    pcall(function() noteChanges(livingSnapshot()) end)
    pcall(settleGauges)
    local uid = Menu.actor
    if (not uid) or (uid < 0) then uid = currentActor() end
    local actionId, isItem, targets, rowObj = nil, false, {}, nil
    local function readIds(list)
        local out = {}
        if not (list and list.ForEach) then return out end
        pcall(function()
            list:ForEach(function(_, x)
                local n = num(unwrap(x))
                if n and (n >= 0) then out[#out + 1] = n end
            end)
        end)
        return out
    end
    local list = v.cmdDecideDataList
    if list and list.ForEach then
        list:ForEach(function(_, e)
            if actionId then return end
            local d = unwrap(e)
            if not d then return end
            rowObj = d
            actionId = num(d.actionId)
            isItem = d.isUseItem and true or false
            for _, key in ipairs({ "targetUnitUniqueIdList", "TargetUnitUniqueIdList", "targetUniqueIdList" }) do
                if #targets == 0 then
                    local raw = nil
                    pcall(function() raw = d[key] end)
                    targets = readIds(raw)
                end
            end
        end)
    end
    if not actionId then return end
    local skill = (not isItem) and skillOf(actionId) or nil
    local name = (skill and skill.name) or ("command " .. tostring(actionId))
    if isItem then
        local row = ItemIdx and ItemIdx[actionId] or nil
        name = (row and row.name) or ("item " .. tostring(actionId))
    end
    local info = skill and knownOf(skill) or nil
    local use = info and info.use or nil
    local kind = nil
    if skill then
        local okKind, got = pcall(classify, skill)
        if okKind then kind = got end
    end
    if isItem then
        local listed = Known.items and Known.items[name:lower()]
        if listed == "hp" then kind = "heal" end
        if listed == "mp" then kind = "ether" end
        if listed == "revive" then kind = "revive" end
        if listed == "cure" then kind = "cure" end
    end
    if (use == "heal") or (use == "patch") then kind = "heal" end
    if use == "cure" then kind = "cure" end
    if use == "debuff" then kind = "debuff" end
    if (not kind) and ((use == "break") or (use == "cash")) then kind = "damage" end
    local phase = currentPhase()
    local who = (uid and (uid >= 0)) and unitName(uid) or "you"
    local line = string.format("player %s p%d: %s", who, phase, name)
    if #targets > 0 then
        local bits = {}
        for _, tid in ipairs(targets) do bits[#bits + 1] = unitName(tid) end
        line = line .. " -> " .. table.concat(bits, ", ")
    end
    log("%s", line)
    appendLog("  " .. line)
    rememberCast(who, name)
    Fight.actions[#Fight.actions + 1] = line
    Fight.last = { who = who, skill = name }
    Fight.prevHit = { who = who, skill = name, kind = kind, id = targets[1] }
    if (kind == "damage") and targets[1] then Fight.building = targets[1] end
    Fight.claim = Fight.claim or {}
    Fight.claim.heal = Fight.claim.heal or {}
    Fight.claim.revive = Fight.claim.revive or {}
    Fight.claim.ether = Fight.claim.ether or {}
    Fight.claim.hone = Fight.claim.hone or {}
    local function eachAlly(pred)
        local ids = {}
        for _, id in ipairs(friendIds()) do
            local ratio = hpRatio(id)
            local dead = (ratio ~= nil) and (ratio <= 0)
            if pred(id, dead) then ids[#ids + 1] = id end
        end
        if (#ids == 0) and uid and (uid >= 0) then ids[1] = uid end
        return ids
    end
    if (kind == "heal") or (kind == "cure") then
        local ids = (#targets > 0) and targets or eachAlly(function(_, dead) return not dead end)
        for _, id in ipairs(ids) do Fight.claim.heal[id] = true end
    end
    if kind == "revive" then
        local ids = (#targets > 0) and targets or eachAlly(function(_, dead) return dead end)
        for _, id in ipairs(ids) do Fight.claim.revive[id] = #Fight.actions end
    end
    if (kind == "ether") and uid and (uid >= 0) then
        Fight.claim.ether[uid] = true
        Fight.claim.etherRound = true
    end
    if (kind == "debuff") and info and info.effect then
        if #targets > 0 then
            for _, id in ipairs(targets) do markDebuff(id, info.effect) end
        end
    end
    if use == "guardbuff" then Fight.claim.guard = true end
    if (use == "opener") and uid and (uid >= 0) then Fight.claim.hone[uid] = true end
    if use == "lb-setup" then Fight.claim.lb = true end
    if use == "provoke" then
        Fight.claim.provoke = true
        Fight.claim.provokeRound = Fight.rounds or 0
        Fight.provokeTurnsRemaining = 3
        Fight.lastProvokeAction = #(Fight.actions or {})
    end
    if skill and (skill.attr == ATTR.SUMMON) then markSummon(skill) end
    if skill and (skill.attr == ATTR.FINISH) then Fight.resonanceSent = true end
    if phase == PHASE_FINISH then Fight.resonanceSent = true end
    local cost = 0
    if skill and uid and (uid >= 0) then
        pcall(function() cost = skillCost(uid, actionId, false) or 0 end)
    end
    if (phase == 0) and (kind == "damage") and (not isItem) and (cost > 0) then
        Fight.line = true
        Fight.chipped = true
    end
    if (phase == 0) and (kind == "damage") and (not isItem) and skill and (#targets > 0) then
        Fight.poured = Fight.poured or {}
        Fight.down = Fight.down or {}
        Fight.relax = Fight.relax or {}
        Fight.gaugeScale = Fight.gaugeScale or {}
        Fight.lastHit = targets
        local _, br = offenseOf(skill)
        if br > 0 then
            for _, tid in ipairs(targets) do
                if not Fight.down[tid] then
                    Fight.relax[tid] = nil
                    local enemy = { id = tid, name = unitName(tid) }
                    local card = mobOf(enemy)
                    local gauge = card and tonumber(card.gauge) or nil
                    local scaled = Fight.gaugeScale[tid]
                    if scaled and ((not gauge) or (scaled > gauge)) then gauge = scaled end
                    local factor = elementFactor(skill, enemy)
                    if gauge and (gauge > 0) and (factor > 0) then
                        Fight.poured[tid] = (Fight.poured[tid] or 0) + (br * factor)
                    end
                end
            end
        end
    elseif (phase == 0) and (kind == "damage") and (not isItem) and (#targets == 0) then
        Fight.unmarked = true
        if rowObj and (not Fight.targetTold) then
            Fight.targetTold = true
            log("player command had no target ids")
        end
        log("stagger from %s was not counted", name)
    end
    if skill and info and info.element and (#targets > 0) then
        Fight.elemRun = Fight.elemRun or {}
        local el = info.element
        for _, tid in ipairs(targets) do
            local run = Fight.elemRun[tid]
            if run and (run.el == el) then run.n = run.n + 1
            else Fight.elemRun[tid] = { el = el, n = 1 } end
        end
    end
    if uid and (uid >= 0) then noteRound(uid) end
end

local function scheduleAct()
    if Menu.sub or Menu.decided or (not Menu.open) then return end
    if not cfg.Enabled then return end
    Menu.due = (Menu.due or 0) + 1
    local due = Menu.due
    local serial = Menu.serial
    gameDelay(DECIDE_MS, function()
        if Menu.due ~= due then return end
        act(serial)
    end)
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

local function inFight()
    if Fight and Fight.active then return true end
    local ok, u = pcall(function() return FindFirstOf("CPP_BtlUnit") end)
    return (ok and u and u.IsValid and u:IsValid()) and true or false
end

local function hookDecide()
    RegisterHook("/Script/mucha.CPP_BtlDelEventCmd:OnExecuteDecideCommand", function(_, value)
        if not inFight() then return end
        pcall(function()
            if not value then return end
            local v = value:get()
            if not v or type(v) ~= "userdata" then return end
            local fromMod = (Menu.byMod == true)
            Menu.byMod = false
            learn(v)
            Menu.decided = true
            Menu.sub = false
            if not fromMod then
                local okNote, errNote = pcall(noteHand, v)
                if not okNote then log("player command was not recorded: %s", tostring(errNote)) end
            end
        end)
    end)
end

local function hookMenu()
    RegisterHook("/Script/mucha.CPP_MuchaEventDispatcher:ExecuteEvent", function(_, tag)
        if not inFight() then return end
        if not tag then return end
        local ok, name = pcall(function()
            local v = tag:get()
            if not v or type(v) ~= "userdata" then return nil end
            local tn = v.TagName
            if not tn or type(tn) ~= "userdata" then return nil end
            return tn:ToString()
        end)
        if not (ok and name and type(name) == "string") then return end
        if name == "Delegate.Battle.Cmd.List.Begin" then
            local actor = currentActor()
            Menu.sub = (actor == Menu.actor) and (not Menu.decided)
            Menu.actor = actor
            Menu.decided = false
            Menu.open = true
            Menu.serial = Menu.serial + 1
            if Menu.sub then return end
            scheduleAct()
        elseif name == "Delegate.Battle.Cmd.List.End" then
            Menu.open = false
        end
    end)
end

local function hookSkillCost()
    RegisterHook("/Script/mucha.CPP_BFL_Skill:GetSkillCost", function() end, function(self, ret, skillId, unitId, isAll)
        if cfg.CheapMP == false then return end
        pcall(function()
            if not ret then return end
            local c = ret:get()
            if type(c) == "number" and c > 1 then
                local sid = nil
                if skillId then
                    local okS, sv = pcall(function() return skillId:get() end)
                    sid = okS and num(sv) or num(skillId)
                end
                local info = sid and skillOf(sid)
                if not (info and info.attr == ATTR.LB) then
                    ret:set(1)
                end
            end
        end)
    end)
end

local function findClass(path)
    local cls = StaticFindObject(path)
    if not (cls and cls:IsValid()) then error("missing " .. path) end
    return cls
end

local function makeWidget(kind, ax, ay, alx, aly, size)
    local gi = FindFirstOf("GameInstance")
    if not (gi and gi:IsValid()) then error("no GameInstance") end
    Hud.serial = Hud.serial + 1
    local base = string.format("FFRAutoBattle_%s_%d", kind, Hud.serial)
    local widget = StaticConstructObject(findClass("/Script/UMG.UserWidget"), gi, FName(base))
    local tree = StaticConstructObject(findClass("/Script/UMG.WidgetTree"), widget, FName(base .. "_Tree"))
    widget.WidgetTree = tree
    local canvas = StaticConstructObject(findClass("/Script/UMG.CanvasPanel"), tree, FName(base .. "_Canvas"))
    tree.RootWidget = canvas
    local border = StaticConstructObject(findClass("/Script/UMG.Border"), tree, FName(base .. "_Border"))
    local text = StaticConstructObject(findClass("/Script/UMG.TextBlock"), tree, FName(base .. "_Text"))
    border:SetContent(text)
    if kind == "badge" then
        -- Ultra-sleek, seamless in-game JRPG tactical HUD:
        border:SetBrushColor({ R = 0.015, G = 0.025, B = 0.055, A = 0.68 })
        border:SetPadding({ Left = 10, Top = 3, Right = 10, Bottom = 3 })
    else
        border:SetBrushColor({ R = 0.02, G = 0.03, B = 0.05, A = 0.72 })
        border:SetPadding({ Left = 14, Top = 6, Right = 14, Bottom = 6 })
    end
    local slot = canvas:AddChildToCanvas(border)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = ax, Y = ay }, Maximum = { X = ax, Y = ay } })
    slot:SetAlignment({ X = alx, Y = aly })
    slot:SetPosition({ X = 0, Y = 0 })
    local font = text.Font
    font.Size = size
    text:SetFont(font)
    if kind == "badge" then
        -- Subtle champagne gold text
        text:SetColorAndOpacity({ SpecifiedColor = { R = 0.94, G = 0.88, B = 0.68, A = 0.95 }, ColorUseRule = 0 })
    else
        text:SetColorAndOpacity({ SpecifiedColor = { R = 0.93, G = 0.86, B = 0.62, A = 1 }, ColorUseRule = 0 })
    end
    pcall(function() widget:SetIsFocusable(false) end)
    pcall(function() text:SetIsFocusable(false) end)
    widget:SetVisibility(1)
    widget:AddToViewport(kind == "toast" and 9999 or 1000)
    return { widget = widget, text = text }
end

local function widget(kind)
    local w = Hud.box[kind]
    if w and w.widget:IsValid() and w.text:IsValid() then
        if not w.widget:IsInViewport() then w.widget:AddToViewport(kind == "toast" and 9999 or 1000) end
        return w
    end
    if kind == "toast" then
        w = makeWidget(kind, 0.5, 0.16, 0.5, 0.5, 20)
    elseif kind == "advisor" then
        w = makeWidget(kind, 0.98, 0.04, 1.0, 0.0, 13)
    else
        w = makeWidget(kind, 0.012, 0.91, 0.0, 1.0, 11)
    end
    Hud.box[kind] = w
    return w
end

Hud.toast = function(msg)
    if Hud.disabled then return end
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local w = widget("toast")
            w.text:SetText(FText(msg))
            w.widget:SetVisibility(3)
            Hud.toastSerial = Hud.toastSerial + 1
            local serial = Hud.toastSerial
            gameDelay(2500, function()
                if serial == Hud.toastSerial and w.widget:IsValid() then w.widget:SetVisibility(1) end
            end)
        end)
        if not ok then
            Hud.disabled = true
            log("overlay off: %s", tostring(err))
        end
    end)
end

Hud.badgeSerial = 0
Hud.lastBadgeMsg = ""

Hud.badgeShow = function(msg, duration)
    if Hud.disabled then return end
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local w = widget("badge")
            if not msg or msg == "" then
                Hud.lastBadgeMsg = ""
                if w and w.widget:IsValid() then w.widget:SetVisibility(1) end
                return
            end

            -- Only trigger display & auto-fade timer on initial engagement or status change
            if msg ~= Hud.lastBadgeMsg then
                Hud.lastBadgeMsg = msg
                w.text:SetText(FText(msg))
                w.widget:SetVisibility(3)
                Hud.badgeSerial = (Hud.badgeSerial or 0) + 1
                local serial = Hud.badgeSerial
                -- Auto-fades after 3.5 seconds so player knows how it engages, then fades away!
                gameDelay(math.floor((duration or 3.5) * 1000), function()
                    if serial == Hud.badgeSerial and w and w.widget:IsValid() then
                        w.widget:SetVisibility(1)
                    end
                end)
            end
        end)
        if not ok then
            Hud.disabled = true
            log("overlay off: %s", tostring(err))
        end
    end)
end

-- In-game Build Guide removed (migrated to live Google Doc)
Hud.buildGuideShow = function(text) end
local function toggleBuildGuide() end

local advisorVisible = false
local lastAdvisorHudText = ""

Hud.advisorShow = function(msg)
    if Hud.disabled then return end
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local w = widget("advisor")
            if not msg or msg == "" then
                w.widget:SetVisibility(1)
                return
            end
            w.text:SetText(FText(msg))
            w.widget:SetVisibility(3)
        end)
        if not ok then
            log("advisor overlay off: %s", tostring(err))
        end
    end)
end

local function toggleAdvisorHud()
    advisorVisible = not advisorVisible
    if advisorVisible then
        local txt = lastAdvisorHudText ~= "" and lastAdvisorHudText or "== MATHEMATICAL ADVISOR ==\nEvaluating party loadout..."
        Hud.advisorShow(txt)
        Hud.toast("Math Advisor HUD: ON")
    else
        Hud.advisorShow(nil)
        Hud.toast("Math Advisor HUD: OFF")
    end
end

local function fmtHudNum(n)
    if not n then return "0" end
    local s = tostring(math.floor(math.abs(n)))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if n < 0 then return "-" .. formatted end
    return formatted
end

local function updatePartyCombatHud()
    if not (Fight and Fight.active) then
        if lastAdvisorHudText ~= "" then
            Hud.advisorShow(nil)
            lastAdvisorHudText = ""
        end
        return
    end

    local allies = friendIds()
    if not allies or #allies == 0 then return end

    -- Seamless Natural Party HUD Update:
    -- Injects Level, Max HP, HP %, Max MP, and Alerts directly into the native bottom party frames!
    if PartyHud and PartyHud.tick then
        PartyHud.tick(allies, stat, paramOf, unitName, broken)
    end

    if not advisorVisible then return end

    local lines = {}
    lines[#lines + 1] = "================ PARTY TACTICAL INTEL ================"
    for _, uid in ipairs(allies) do
        local name = unitName(uid)
        local curHp = stat(uid, PARAM.HP, false) or 0
        local maxHp = stat(uid, PARAM.HP, true) or 1
        local hpPct = math.floor((curHp / maxHp) * 100 + 0.5)

        local curMp = stat(uid, PARAM.MP, false) or 0
        local maxMp = stat(uid, PARAM.MP, true) or 1

        local curLb = stat(uid, PARAM.LB, false) or 0
        local maxLb = stat(uid, PARAM.LB, true) or 100
        if maxLb <= 0 then maxLb = 100 end
        local lbPct = math.min(100, math.floor((curLb / maxLb) * 100 + 0.5))

        local lbStatus = (lbPct >= 100) and "[LB READY!]" or string.format("LB: %d%%", lbPct)
        local alert = ""
        if hpPct <= 0 then alert = " [FALLEN]"
        elseif hpPct <= 25 then alert = " [DANGER!]" end

        local p = paramOf(uid)
        local lvl = nil
        if p then
            local okL, l = pcall(function() return p:GetLevel() end)
            if okL and type(l) == "number" and l > 0 then lvl = l end
        end
        local lvlStr = lvl and string.format("(Lv.%2d)", lvl) or ""

        lines[#lines + 1] = string.format(" %-8s %-7s: HP %5s/%-5s (%3d%%%s) | MP %3d/%-3d | %s",
            name, lvlStr, fmtHudNum(curHp), fmtHudNum(maxHp), hpPct, alert, curMp, maxMp, lbStatus)
    end

    -- Live Enemy Threat Radar
    local enemyList = members(REL.ENEMY)
    if enemyList and #enemyList > 0 then
        lines[#lines + 1] = "---------------- ENEMY THREAT RADAR ------------------"
        for _, eid in ipairs(enemyList) do
            local eName = unitName(eid)
            local eCurHp = stat(eid, PARAM.HP, false) or 0
            local eMaxHp = stat(eid, PARAM.HP, true) or 1
            local eHpPct = math.floor((eCurHp / eMaxHp) * 100 + 0.5)

            local p = paramOf(eid)
            local eLvl = nil
            if p then
                local okL, l = pcall(function() return p:GetLevel() end)
                if okL and type(l) == "number" and l > 0 then eLvl = l end
            end
            local eLvlStr = eLvl and string.format("[Lv.%2d] ", eLvl) or ""

            local isStaggered = broken(eid)
            local statusTag = isStaggered and "[STAGGERED! x2.0 DMG]" or ""
            if not isStaggered and eHpPct <= 25 and eHpPct > 0 then
                statusTag = "[EXECUTE!]"
            end

            lines[#lines + 1] = string.format(" %s%-16s: HP %5s/%-5s (%3d%%) %s",
                eLvlStr, eName, fmtHudNum(eCurHp), fmtHudNum(eMaxHp), eHpPct, statusTag)
        end
    end
    lines[#lines + 1] = "======================================================"

    local fullText = table.concat(lines, "\n")
    if fullText ~= lastAdvisorHudText then
        lastAdvisorHudText = fullText
        Hud.advisorShow(fullText)
    end
end

local speedDone = false
local function applySpeed()
    if speedDone or cfg.BattleSpeed == 1 then speedDone = true return end
    local tables = FindAllOf("DataTable")
    if not tables then return end
    local applied = false
    for _, dt in ipairs(tables) do
        pcall(function()
            if type(dt) ~= "userdata" or not dt:IsValid() then return end
            if rowStructName(dt) ~= "BTL_GENERAL_DATA" then return end
            dt:ForEachRow(function(_, row)
                local list = row.GameSpeedList
                if not (list and list.ForEach) then return end
                local first
                list:ForEach(function(i, e)
                    if i == 1 then first = num(e) end
                end)
                if not first or math.abs(first - 1) > 0.05 then
                    log("battle speed left as it is (first step %s)", tostring(first))
                    speedDone = true
                    return
                end
                list:ForEach(function(_, e)
                    local v = num(e)
                    if v then e:set(v * cfg.BattleSpeed) end
                end)
                applied = true
            end)
        end)
    end
    if applied then
        speedDone = true
        log("battle speed x%s", tostring(cfg.BattleSpeed))
    end
end

local function watchField()
    if not (Fight and Fight.active) then return end
    pcall(function() noteChanges(livingSnapshot()) end)
    pcall(settleGauges)
end

local function resonanceWatch()
    if not (Fight and Fight.active) then return end
    if not cfg.Enabled then
        watchField()
        return
    end
    local okPhase, phase = pcall(inFinishPhase)
    local finishing = okPhase and phase == true
    if not finishing then
        Fight.resonanceSent = false
        Fight.resonanceMiss = false
        Fight.resonanceWait = false
        Fight.finishScan = nil
        Fight.attackWheel = false
        return
    end
    if cfg.AttacksOnly then
        -- Even in AttacksOnly ("Take it Easy") mode, always select the proper Resonance finisher
        -- because Resonance costs 0 MP and is the defining climax combat mechanic.
        if not Fight.attackWheel then
            Fight.attackWheel = true
            log("resonance phase (auto-selecting optimal finisher)")
        end
    end
    if Fight.resonanceSent then
        -- Retry safety: If finish command was sent but game remains in finish phase for > 1.2s, retry!
        local now = os.clock and os.clock() or 0
        if Fight.resonanceSentTime and (now - Fight.resonanceSentTime > 1.2) then
            Fight.resonanceSent = false
        else
            return
        end
    end
    if not Fight.resonanceWait then
        Fight.resonanceWait = true
        return
    end
    pcall(buildSkillIndex)
    local bestUid, bestChoice, bestScore = nil, nil, -1e9
    local names = {}
    for _, uid in ipairs(friendIds()) do
        local ratio = hpRatio(uid)
        if (ratio == nil or ratio > 0) and not outOfControl(uid) then
            names[#names + 1] = unitName(uid)
            local okW, w = pcall(worldOf, uid, Fight.boss, Fight.summoned)
            if okW and w then
                local skills = {}
                local okS, got = pcall(finishList, uid)
                if okS and type(got) == "table" then skills = got end
                local okPick, choice = pcall(pickFinish, uid, skills, w)
                if okPick and choice and (choice.score or 0) > bestScore then
                    bestUid, bestChoice, bestScore = uid, choice, choice.score or 0
                end
            end
        end
    end
    if not bestChoice then
        if not Fight.resonanceMiss then
            Fight.resonanceMiss = true
            local detail = {}
            if Fight.finishNote then
                for id, note in pairs(Fight.finishNote) do
                    if note ~= "" then detail[#detail + 1] = unitName(id) .. " bar " .. note end
                end
            end
            log("resonance phase, no finisher on %s%s",
                (#names > 0) and table.concat(names, ", ") or "the party",
                (#detail > 0) and (" (" .. table.concat(detail, "; ") .. ")") or "")
            appendLog("  resonance phase, no finisher equipped")
        end
        return
    end
    local who = unitName(bestUid)
    local cleanReason = bestChoice.reason and bestChoice.reason:gsub("^resonance ", "") or ""
    local line = string.format("resonance %s by %s -> %s", bestChoice.name, who, cleanReason)
    log("%s", line)
    appendLog("  " .. line)
    if Hud and Hud.toast then
        Hud.toast(string.format("[RESONANCE] %s: %s (%s)", who, bestChoice.name, cleanReason))
    end

    -- Safely execute finisher via game's native UI command router (never fires Delegate.Battle.Cmd.Decide)
    local executed = false
    local okExec, errExec = pcall(function()
        local ui = FindFirstOf("CPP_UI_BtlCmdManager")
        local cmd = FindFirstOf("CPP_VM_BtlCmd")
        if ui and ui:IsValid() and cmd and cmd:IsValid() then
            ui.SpecificActionUnitUniqueId = bestUid
            cmd:DecideActionKey({ Category = 1, ID = tonumber(bestChoice.id) })
            if ui.CmdState == 1 then
                if cmd.UnitSelectVM and cmd.UnitSelectVM:IsValid() then
                    cmd.UnitSelectVM:DecideCmd()
                elseif cmd.DecideTarget and bestChoice.targets and #bestChoice.targets > 0 then
                    local tids = {}
                    for _, tid in ipairs(bestChoice.targets) do tids[#tids + 1] = tonumber(tid) end
                    cmd:DecideTarget(tids, false)
                end
            end
            executed = true
        end
    end)
    if not okExec then
        log("resonance native dispatch notice: %s", tostring(errExec))
    end

    Fight.resonanceSent = true
    Fight.resonanceSentTime = os.clock and os.clock() or 0
    rememberCast(who, bestChoice.name)
    Fight.actions[#Fight.actions + 1] = line
    Fight.last = { who = who, skill = bestChoice.name }
end

local absent = 0
gameLoop(400, resonanceWatch)
gameLoop(300, updatePartyCombatHud)
gameLoop(700, function()
    applySpeed()
    buildSkillIndex()
    if not Fight.active then return end
    local u = FindFirstOf("CPP_BtlUnit")
    if u and u:IsValid() then
        absent = 0
        return
    end
    absent = absent + 1
    if absent >= 2 then finishBattle() end
end)

local function bind(name, fn)
    local keyName = cfg[name]
    local key = keyName and Key[keyName]
    if key == nil then
        log("unknown key %s for %s", tostring(keyName), name)
        return
    end
    RegisterKeyBind(key, function()
        ExecuteInGameThread(fn)
    end)
end

local function pressAuto()
    cfg.Enabled = not cfg.Enabled
    saveState()
    local msg = cfg.Enabled and "AutoBattle: ON" or "AutoBattle: OFF"
    log(msg)
    showToast(msg)
    if Hud and Hud.badgeShow then Hud.badgeShow(msg, 3.0) end
    if cfg.Enabled then scheduleAct() end
end

local function pressBasic()
    cfg.AttacksOnly = not cfg.AttacksOnly
    saveState()
    local msg = cfg.AttacksOnly and "AutoBattle: Take it Easy!" or "AutoBattle: No Mercy!"
    log(msg)
    showToast(msg)
    if Hud and Hud.badgeShow then Hud.badgeShow(msg, 3.0) end
end

local function inFight()
    if Fight and Fight.active then return true end
    local ok, u = pcall(function() return FindFirstOf("CPP_BtlUnit") end)
    return (ok and u and u.IsValid and u:IsValid()) and true or false
end

local padTold, padLeft, padRight, padR3 = false, false, false, false
local function pollTriggers()
    local okPc, pc = pcall(function() return FindFirstOf("PlayerController") end)
    if not (okPc and pc and pc.IsValid and pc:IsValid()) then return end
    local function down(name)
        local ok, hit = pcall(function()
            return pc:IsInputKeyDown({ KeyName = FName(name) })
        end)
        if not (ok and (type(hit) == "boolean")) then
            ok, hit = pcall(function()
                return pc:IsInputKeyDown(FName(name))
            end)
        end
        if ok and (type(hit) == "boolean") then return hit end
        return nil
    end
    local left = down("Gamepad_LeftTrigger")
    local right = down("Gamepad_RightTrigger")
    if (left == nil) and (right == nil) then
        if not padTold then
            padTold = true
            log("could not read the triggers")
        end
        return
    end
    local function rose(now, was)
        if now == nil then return false, was end
        return (now and not was) and true or false, now
    end
    -- Gamepad_Special_Left (View button) unintercepted
    -- Overworld tick removed from 16ms controller poll; gameLoop(1200) handles it

    local r3Combat = down("Gamepad_RightThumbstick")
    local r3CombatRose
    r3CombatRose, padR3Combat = rose(r3Combat, padR3Combat)
    if r3CombatRose and inFight() then toggleCombatSpeed() end

    local leftRose, rightRose
    leftRose, padLeft = rose(left, padLeft)
    rightRose, padRight = rose(right, padRight)
    if not (leftRose or rightRose) then return end
    if not inFight() then return end
    if leftRose then pressBasic() end
    if rightRose then pressAuto() end
end

loadConfig()

bind("TakeOverKey", pressAuto)
bind("MenuKey", pressBasic)
pcall(function()
    RegisterKeyBind(Key.F10, function() ExecuteInGameThread(pressAuto) end)
    RegisterKeyBind(Key.F9, function() ExecuteInGameThread(pressBasic) end)
    RegisterKeyBind(Key.F1, function() ExecuteInGameThread(pressAuto) end)
    RegisterKeyBind(Key.ONE, function() ExecuteInGameThread(pressAuto) end)
    RegisterKeyBind(Key.F2, function() ExecuteInGameThread(pressBasic) end)
    RegisterKeyBind(Key.TWO, function() ExecuteInGameThread(pressBasic) end)
    RegisterKeyBind(Key.F12, function()
        ExecuteInGameThread(function()
            local ok, loaded = pcall(dofile, DIR .. "/Scripts/highlighter.lua")
            if ok and type(loaded) == "table" then
                Highlighter = loaded
                log("highlighter reloaded successfully!")
            else
                log("highlighter reload failed: %s", tostring(loaded))
            end
            local okP, loadedP = pcall(dofile, DIR .. "/Scripts/party_hud.lua")
            if okP and type(loadedP) == "table" then
                PartyHud = loadedP
                log("party_hud reloaded successfully!")
            end
        end)
    end)
    RegisterKeyBind(Key.F8, function() ExecuteInGameThread(toggleAdvisorHud) end)
    RegisterKeyBind(Key.F6, function() ExecuteInGameThread(toggleCombatSpeed) end)
end)
gameLoop(16, pollTriggers)
gameLoop(1200, function()
    if Highlighter and not Fight.active then
        Highlighter.tick()
    end
end)

local okHook, errHook = pcall(function()
    hookDecide()
    hookMenu()
    hookSkillCost()
end)
if not okHook then log("hook failed: %s", tostring(errHook)) end

local mobCount = 0
for _ in pairs(Mobs) do mobCount = mobCount + 1 end
log("loaded. planner v0.1.14. %s. %s toggles auto battle. %s basic attacks %s. In a fight, left trigger toggles basic attacks and right trigger toggles auto battle. Bestiary %d. Submit=%s, battle speed x%s.",
    cfg.Enabled and "on" or "off",
    cfg.TakeOverKey,
    cfg.MenuKey,
    cfg.AttacksOnly and "on" or "off",
    mobCount,
    tostring(cfg.Submit), tostring(cfg.BattleSpeed))
