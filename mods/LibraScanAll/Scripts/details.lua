--[[----------------------------------------------------------------------------
    Libra detail numbers module (shared by LibraScanAll and LibraAutoScan)
    Based on FFR_LibraPlus ("Libra Plus") v0.5 -- see README for credit.

    Adds real numbers to the Libra DETAIL screen (WBP_Btl_LibraInfoDetailLayout):
      * Items Dropped / Rare Drop / Stealable Items / Rare Stealable:
            "Mist Potion"  ->  "Mist Potion  8.3%"
      * Resistances: an extra line under the icons with every ailment
        resistance, grouped by value, e.g. "80%   Blind · Sleep".
      * Info line: "EXP 120 · Gil 45 · Defeated 12" and "HP 1234 / 5000 · Break 30 / 100".
      * Danger line (bosses): the enemy's high-risk skills, and which one it
        has scheduled next, e.g. "!! Dangerous: Meteor, Flare  > NEXT: Meteor".
    And on the spell target panel (WBP_BtlSkillResistPredict): the damage
    multiplier next to "WEAK!" etc., e.g. "WEAK!  x1.5".

    NUMBERS
      Ailment: chance = base rate * (100 - resist) / 100; resist 100 = immune.
      Steal:   success = 1 / StealItemRate; on success the rare item is taken
               (STEAL_RARE - 1) / 99 of the time. Per plain Steal, no passives.
      Drop:    1 / DropNormalItemRate, 1 / DropRareItemRate (rate 1 = always).

    SAFETY
      Game state is only read (GetRawParameter, GetResistanceToStatusCondition).
      Writes go to Libra detail widgets only, on the game thread.
      No widget is kept between ticks except as an address: a freed widget's
      memory can be reused while IsValid() still says true, so our text is
      always found again through the live row.
    ----------------------------------------------------------------------------]]

local M = {}

local function defaults()
    return {
        FONT_PATH  = "/Game/UI/Font/UnipueText.UnipueText",
        FONT_SIZE  = 12,
        COLOR      = { R = 1.00, G = 0.86, B = 0.45, A = 1.00 },
        SHADOW     = { R = 0.00, G = 0.00, B = 0.00, A = 0.90 },
        STEAL_RARE = 25,       -- DT_UnitParameterCalc.stealRareItemRate
        SHOW_ITEM_CHANCES = true,
        SHOW_RESISTANCES  = true,
        SHOW_INFO         = true,     -- EXP / Gil / defeated count
        SHOW_HP           = true,     -- current / max HP and break gauge
        SHOW_DANGER       = true,     -- boss high-risk skills + the next one
        SHOW_MULTIPLIER   = true,     -- "x1.5" on the spell target panel
        DANGER_COLOR      = { R = 1.00, G = 0.42, B = 0.38, A = 1.00 },
        SHOW_RARE_MARKER  = true,     -- marker after the name of enemies with rare loot
        RARE_MARKER       = "★",
        RARE_MARKER_NEEDS_SCAN = true, -- only on enemies you have scanned
    }
end
local CFG = defaults()

local VIS_SHOWN, HALIGN_FILL, JUSTIFY_LEFT = 3, 0, 0

-- eUnitStatusCondition values and short names, in display order
local AILMENTS = {
    { 1, "Poison" }, { 2, "Blind" }, { 3, "Sleep" }, { 4, "Silence" },
    { 5, "Paralysis" }, { 6, "Confusion" }, { 7, "Petrify" }, { 8, "Charm" },
    { 10, "Berserk" }, { 11, "Doom" }, { 12, "Slow" }, { 13, "Death" },
    { 14, "Gravity" }, { 15, "ATK Down" }, { 16, "DEF Down" },
    { 17, "INT Down" }, { 18, "MND Down" },
}

local say, sayOnce = print, print

local function valid(o)
    if type(o) ~= "userdata" then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end
local function get(o, name)
    if not valid(o) then return nil end
    local ok, v = pcall(function() return o[name] end)
    if ok then return v end
end
local function objName(o)
    local ok, s = pcall(function() return o:GetFName():ToString() end)
    return ok and s or ""
end
local function className(o)
    local ok, s = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and s or "?"
end
local function addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

---------------------------------------------------------------------------- numbers
local function pct(p)
    if p >= 99.95 then return "100%" end
    if p >= 10 then return string.format("%.0f%%", p) end
    if p > 0 then return string.format("%.1f%%", p) end
    return "0%"
end
local function oneIn(n) return (n and n > 0) and 100 / n or 0 end

local function chances(raw)
    local stealOk = (raw.StealNormalItem ~= -1 or raw.StealRareItem ~= -1)
    local steal = stealOk and math.min(100, oneIn(raw.StealItemRate)) or 0
    local rareShare = (CFG.STEAL_RARE - 1) / 99
    if raw.StealNormalItem == -1 then rareShare = 1 end
    if raw.StealRareItem == -1 then rareShare = 0 end
    return {
        NormalDrop  = oneIn(raw.DropNormalItemRate),
        RareDrop    = oneIn(raw.DropRareItemRate),
        NormalSteal = steal * (1 - rareShare),
        RareSteal   = steal * rareShare,
    }
end

local function resistLine(param)
    local groups, values = {}, {}
    for _, a in ipairs(AILMENTS) do
        local ok, v = pcall(function() return param:GetResistanceToStatusCondition(a[1]) end)
        if ok and type(v) == "number" and v > 0 then
            v = math.floor(v)
            if not groups[v] then groups[v] = {}; values[#values + 1] = v end
            table.insert(groups[v], a[2])
        end
    end
    if #values == 0 then return "Other ailments 0%" end
    table.sort(values, function(x, y) return x > y end)
    local lines = {}
    for _, v in ipairs(values) do lines[#lines + 1] = v .. "%   " .. table.concat(groups[v], " · ") end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------- widgets
local textClass, fontObj

local function newText(outer, color)
    textClass = valid(textClass) and textClass or StaticFindObject("/Script/UMG.TextBlock")
    if not valid(textClass) then return nil end
    local tb = StaticConstructObject(textClass, outer)
    if not valid(tb) then return nil end
    fontObj = valid(fontObj) and fontObj or StaticFindObject(CFG.FONT_PATH)
    tb:SetFont(valid(fontObj) and { FontObject = fontObj, Size = CFG.FONT_SIZE } or { Size = CFG.FONT_SIZE })
    tb:SetColorAndOpacity({ SpecifiedColor = color or CFG.COLOR, ColorUseRule = 0 })
    tb:SetShadowOffset({ X = 1, Y = 1 })
    tb:SetShadowColorAndOpacity(CFG.SHADOW)
    tb:SetJustification(JUSTIFY_LEFT)
    tb:SetVisibility(VIS_SHOWN)
    return tb
end

local function childCount(box)
    local ok, n = pcall(function() return box:GetChildrenCount() end)
    return (ok and type(n) == "number") and n or nil
end

local function childAt(box, a)
    local n = childCount(box)
    if not n then return nil end
    for i = 0, n - 1 do
        local okC, c = pcall(function() return box:GetChildAt(i) end)
        if okC and addr(c) == a then return c end
    end
    return nil
end

local function tagMap(map)
    local out = {}
    if not map then return out end
    pcall(function()
        map:ForEach(function(k, v)
            out[k:get().TagName:ToString():match("([^%.]+)$")] = v:get()
        end)
    end)
    return out
end

-- "Mist Potion" -> "Mist Potion  8.3%". Idempotent: an existing "  N%" suffix
-- (ours or the standalone Libra Plus') is replaced, never stacked.
local function setItemChance(row, chance, tagName)
    local content = get(row, "ContentWidget")
    local tb = get(content, "CommonTextBlock_194")
    if not valid(tb) then
        sayOnce("noitem:" .. tagName .. className(content), "%s row content is %s (no item text)", tagName, className(content))
        return
    end
    local ok, cur = pcall(function() return tb:GetText():ToString() end)
    if not ok or not cur then return end
    local base = cur:gsub("  [%d%.]+%%$", "")
    if base == "" or base == "-" then return end
    local want = chance and (base .. "  " .. pct(chance)) or base
    if cur ~= want then tb:SetText(FText(want)) end
end

---------------------------------------------------------------------- lookups
local function lib(path)
    local o = StaticFindObject(path)
    return valid(o) and o or nil
end

-- DataTables by row struct name, read once (skill names, AI risk lists, multipliers)
local tablesByStruct = nil
local function tableOf(structName)
    if not tablesByStruct then
        tablesByStruct = {}
        for _, dt in ipairs(FindAllOf("DataTable") or {}) do
            local okN, full = pcall(function() return dt:GetFullName() end)
            if okN and full and not full:find("Default__", 1, true) then
                local ok, rs = pcall(function() return dt:GetRowStruct():GetFName():ToString() end)
                if ok and rs and not tablesByStruct[rs] then tablesByStruct[rs] = dt end
            end
        end
    end
    local dt = tablesByStruct[structName]
    if dt and not valid(dt) then tablesByStruct = nil; return nil end
    return dt
end
local function eachRow(dt, fn)
    if not dt then return end
    pcall(function() dt:ForEachRow(function(name, row) fn(row) end) end)
end

local function num(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v) end
    if type(v) == "userdata" or type(v) == "table" then
        local ok, x = pcall(function() return v:get() end)
        if ok and type(x) == "number" then return x end
    end
    return nil
end
local function str(v)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    local ok, s = pcall(function() return v:ToString() end)
    return (ok and type(s) == "string") and s or tostring(v)
end
-- numbers of a TArray (userdata or Lua table), or {}
local function numbers(arr)
    local out = {}
    if type(arr) == "table" then
        for _, v in ipairs(arr) do local n = num(v); if n then out[#out + 1] = n end end
    elseif arr ~= nil then
        local okN, n = pcall(function() return #arr end)
        if okN and type(n) == "number" then
            for i = 1, n do
                local okE, e = pcall(function() return arr[i] end)
                local x = okE and num(e)
                if x then out[#out + 1] = x end
            end
        end
    end
    return out
end

local skillNames = nil      -- skill id -> name
local skillElems = {}       -- skill id -> eElement
local function loadSkills()
    if skillNames then return true end
    local dt = tableOf("SKILL_DATA")
    if not dt then return false end
    skillNames = {}
    eachRow(dt, function(row)
        local ok, i = pcall(function() return row.ID end)
        if ok and num(i) then
            skillNames[num(i)] = str(row.Name)
            local okE, e = pcall(function() return row.element end)
            if okE and num(e) then skillElems[num(i)] = num(e) end
        end
    end)
    return true
end
local function skillName(id)
    if not loadSkills() then return "#" .. id end
    local n = skillNames[id]
    return (n and n ~= "") and n or ("#" .. id)
end
local function skillElement(id)
    if not id or not loadSkills() then return nil end
    return skillElems[id]
end

local aiRisk = nil          -- AI parameter id -> { skill ids }
local function riskFromTable(id)
    if not aiRisk then
        aiRisk = {}
        eachRow(tableOf("BTL_UNIT_AI_PARAMETER"), function(row)
            local okI, i = pcall(function() return row.ID end)
            local okL, l = pcall(function() return row.highRiskSkillIdList end)
            if okI and num(i) and okL then aiRisk[num(i)] = numbers(l) end
        end)
    end
    return aiRisk[id] or {}
end

-- High-risk skill ids of a battle unit. Candidates come from the game's
-- GetHighRiskSkillIdList and the AI table, but only ids the game itself confirms
-- with IsHighRiskSkill(id) are kept (v1.2.0 showed a list on every enemy: the
-- candidates alone are not reliable). Without that check nothing is shown.
local riskLogged = {}
local function highRisk(param)
    local cand, seen = {}, {}
    local function add(list, src)
        for _, id in ipairs(list) do
            if id > 0 and not seen[id] then seen[id] = src; cand[#cand + 1] = id end
        end
    end
    pcall(function()
        local out = {}
        local r = param:GetHighRiskSkillIdList(out)
        add(numbers(out), "func")
        add(numbers(r), "func")
    end)
    local okU, uid = pcall(function() return param:GetUnitId() end)
    uid = okU and num(uid) or nil
    if uid then add(riskFromTable(uid), "table") end

    local ids, checked = {}, true
    for _, id in ipairs(cand) do
        local ok, yes = pcall(function() return param:IsHighRiskSkill(id) end)
        if not ok then checked = false; break end
        if yes == true then ids[#ids + 1] = id end
    end
    if not checked then
        sayOnce("riskcheck", "IsHighRiskSkill not callable on this build; danger line disabled")
        return {}
    end
    if uid and not riskLogged[uid] then
        riskLogged[uid] = true
        local c = {}
        for _, id in ipairs(cand) do c[#c + 1] = id .. "(" .. seen[id] .. ")" end
        say("danger check unit %d: %d candidate(s) [%s], %d confirmed", uid, #cand, table.concat(c, " "), #ids)
    end
    return ids
end

-- "next" = the game's own timeline warning (IsScheduledHighRiskSkill on the unit's
-- battle UI data), named from the AI's scheduled skill
local function nextSkill(param, vm)
    local okS, sched = pcall(function() return vm:IsScheduledHighRiskSkill() end)
    if not (okS and sched == true) then return nil end
    local ok, id = pcall(function() return param.m_pOwnerBtlUnit:GetUnitAI().m_ScheduledSkillId end)
    return (ok and num(id)) or -1
end

local multipliers = nil     -- eResistance -> damage multiplier
local function multiplierOf(res)
    if not multipliers then
        local dt = tableOf("UNIT_PARAMETER_CALC_DATA")
        if not dt then return nil end
        multipliers = {}
        local first = true
        eachRow(dt, function(row)
            if not first then return end
            first = false
            pcall(function()
                row.elementResistanceValues:ForEach(function(k, v)
                    local key, val = num(k), num(v)
                    if key and val then multipliers[key] = val end
                end)
            end)
        end)
    end
    return multipliers[res]
end

---------------------------------------------------------------------- lines
local function group(n)
    local s = tostring(math.floor(n))
    while true do
        local t, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        s = t
        if k == 0 then return s end
    end
end

local function infoLine(param, raw)
    local parts = {}
    if CFG.SHOW_INFO and raw then
        local exp, gil = num(raw.Experience), num(raw.Money)
        if exp then parts[#parts + 1] = "EXP " .. group(exp) end
        if gil then parts[#parts + 1] = "Gil " .. group(gil) end
        local save = num(raw.SaveId)
        local L = lib("/Script/mucha.Default__CPP_BFL_SaveDataUnit")
        if save and L then
            local ok, n = pcall(function() return L:GetDefeatEnemyUnitNum(save) end)
            if ok and num(n) then parts[#parts + 1] = "Defeated " .. group(num(n)) end
        end
    end
    local line1 = table.concat(parts, " · ")
    local hp = {}
    if CFG.SHOW_HP then
        local function pair(t, label)
            local okC, c = pcall(function() return param:GetParameterByType(t, false) end)
            local okM, m = pcall(function() return param:GetMaxParameterByType(t) end)
            if okC and okM and num(c) and num(m) and num(m) > 0 then
                hp[#hp + 1] = string.format("%s %s / %s", label, group(num(c)), group(num(m)))
            end
        end
        pair(1, "HP"); pair(3, "Break")
    end
    local line2 = table.concat(hp, " · ")
    if line1 ~= "" and line2 ~= "" then return line1 .. "\n" .. line2 end
    return line1 ~= "" and line1 or line2
end

local function dangerLine(param, vm)
    if not CFG.SHOW_DANGER then return "" end
    local ids = highRisk(param)
    if #ids == 0 then return "" end
    local names, isRisk = {}, {}
    for _, id in ipairs(ids) do
        if not isRisk[id] then isRisk[id] = true; names[#names + 1] = skillName(id) end
    end
    local s = "!! Dangerous: " .. table.concat(names, ", ")
    local nx = nextSkill(param, vm)
    if nx then s = s .. "\n>> NEXT: " .. (nx > 0 and skillName(nx) or "a dangerous skill") end
    return s
end

---------------------------------------------------------------------- row ownership
-- The Resistances row (WBP_BattleLibraEntry_C) is a VerticalBox with 2 children
-- [EntryTop, IconGrid]. Our lines become extra children: resist, info, danger.
-- Several copies of this module can run (LibraScanAll, LibraAutoScan) and the
-- standalone Libra Plus may add its own resist line, so:
--   2 children            -> we own the row: add resist + info + danger
--   3, 3rd = resist text  -> Libra Plus got there: add info + danger only
--   anything else         -> another copy of this module owns it: hands off
local rows = {}             -- row address -> { foreign, resist, info, danger } (addresses)
local VIS_COLLAPSED = 1

local function textOf(w)
    local ok, t = pcall(function() return w:GetText():ToString() end)
    return ok and t or nil
end
local function isResistText(t)
    return t ~= nil and (t:match("^%d+%%   ") ~= nil or t:match("^Other ailments") ~= nil)
end

local function addLine(root, tree, color, wrap)
    local tb = newText(tree, color)
    if not tb then return nil end
    local slot = root:AddChildToVerticalBox(tb)
    if not valid(slot) then return nil end
    slot:SetPadding({ Left = 12, Top = 3, Right = 12, Bottom = 6 })
    slot:SetHorizontalAlignment(HALIGN_FILL)
    if wrap then tb:SetAutoWrapText(true) end
    return addr(tb)
end

local function claimRow(row)
    local a = addr(row)
    local r = rows[a]
    local tree = get(row, "WidgetTree")
    local root = get(tree, "RootWidget")
    if not (valid(root) and className(root) == "VerticalBox") then
        sayOnce("rlayout", "resistance row root is %s, not VerticalBox; skipping", className(root))
        return nil
    end
    -- known row whose widgets still exist?
    if r then
        if r.foreign then return r, root end
        local ok = (not r.resist or childAt(root, r.resist)) and (not r.info or childAt(root, r.info))
        if ok then return r, root end
    end
    local n = childCount(root) or 0
    r = {}
    if n == 2 then
        r.resist = addLine(root, tree, nil, true)
    elseif n == 3 and isResistText(textOf(select(2, pcall(function() return root:GetChildAt(2) end)))) then
        sayOnce("lp", "standalone Libra Plus resistance line found; adding only the info lines")
    else
        sayOnce("dupe", "resistance row already extended by another copy of the detail module; leaving it")
        rows[a] = { foreign = true }
        return rows[a], root
    end
    r.info = addLine(root, tree, nil, true)
    r.danger = addLine(root, tree, CFG.DANGER_COLOR, true)
    r.str = {}
    rows[a] = r
    return r, root
end

local function setLine(root, r, key, s)
    local w = r[key] and childAt(root, r[key])
    if not w then return end
    if r.str[key] == s then return end
    r.str[key] = s
    pcall(function()
        w:SetText(FText(s))
        w:SetVisibility(s == "" and VIS_COLLAPSED or VIS_SHOWN)
    end)
end

---------------------------------------------------------------------- update
local function update(layout)
    local vm = get(layout, "CPP_VM_BtlUnitParam")
    local param = get(vm, "BtlUnitParam")
    if not valid(param) then return end
    local okA, analyzed = pcall(function() return param:IsAnalyzed() end)
    if not (okA and analyzed) then return end

    local okR, raw = pcall(function() return param:GetRawParameter() end)
    if not okR then sayOnce("raw", "GetRawParameter failed: %s", tostring(raw)); raw = nil end

    if raw then
        local c = chances(raw)
        for tagName, row in pairs(tagMap(get(layout, "DropTagEntryMap"))) do
            if c[tagName] and valid(row) then setItemChance(row, CFG.SHOW_ITEM_CHANCES and c[tagName] or nil, tagName) end
        end
    end

    local row = tagMap(get(get(layout, "WBP_Btl_LibraInfo"), "TagEntryMap")).Invalid
    if not valid(row) then sayOnce("norrow", "no Resistances row in the detail screen"); return end
    local r, root = claimRow(row)
    if not r or r.foreign then return end
    if r.resist then setLine(root, r, "resist", CFG.SHOW_RESISTANCES and resistLine(param) or "") end
    setLine(root, r, "info", infoLine(param, raw))
    setLine(root, r, "danger", dangerLine(param, vm))
end

---------------------------------------------------------------------- spell target panel
-- "WEAK!" -> "WEAK!  x1.5" while the resist-prediction panel is shown
local RES_NAMES = { [1] = "Weakness", [2] = "Halved", [3] = "Invalid", [4] = "Absorb", [5] = "Reflect" }
local function fmtMul(m)
    if m == math.floor(m) then return string.format("x%d", m) end
    return (string.format("x%.2f", m):gsub("0+$", ""))
end

-- one line per distinct reason, so a test run shows exactly where it stops
local function why(key, fmt, ...) sayOnce("pw:" .. key, "spell panel: " .. fmt, ...) end

-- resistance type whose label (DA_BtlSkillResistPredict.TypePropertyMap[res].TextData.Text)
-- matches the text on screen: works even when the element is unknown
local function resFromLabel(vm, label)
    local found
    pcall(function()
        vm.SkillResistPredictDA.TypePropertyMap:ForEach(function(k, v)
            local res = num(k:get())
            local t = str(v:get().TextData.Text)
            if res and t ~= "" and t == label then found = res end
        end)
    end)
    return found
end

local function updatePredict(w)
    local vm = get(w, "VM_BtlSkillResistPredict")
    if not valid(vm) then return why("novm", "no view model on %s", objName(w)) end
    local tb = get(get(w, "WBP_BtlSkillResistPredictAppearance"), "Text_EffectName")
    if not valid(tb) then return why("notb", "label widget Text_EffectName not found") end
    local cur = textOf(tb)
    if not cur or cur == "" then return why("notext", "label is empty") end
    local base = cur:gsub("  x[%-%d%.]+$", "")
    local skill = num(get(vm, "SkillId"))

    -- 1) the label itself tells which resistance is shown
    local res, how = resFromLabel(vm, base), "label"
    -- 2) else element (view model, then skill table) + the target's affinity list
    if not res then
        how = "element"
        local el = num(get(vm, "SkillElement"))
        if not (el and el > 0) then el = skillElement(skill) end
        if not (el and el > 0) then return why("el" .. tostring(skill), "label '%s' not matched and skill %s has no element", base, tostring(skill)) end
        local target = get(vm, "TargetUnitParamVM")
        if not valid(target) then return why("notarget", "no target data") end
        pcall(function()
            local list = target.ElemResistDataList
            for i = 1, #list do
                local d = list[i]
                if num(d.element) == el then res = num(d.resistance) end
            end
        end)
        if res == nil then return why("nores" .. el, "element %d is neutral on this target", el) end
    end
    if res == 0 or res == 5 then return why("res" .. res, "'%s' is %s: no multiplier shown", base, res == 0 and "neutral" or "reflect") end
    local m = multiplierOf(res)
    if not m then return why("nomul", "damage multipliers not found (UNIT_PARAMETER_CALC_DATA)") end
    local want = base .. "  " .. fmtMul(m)
    if cur ~= want then pcall(function() tb:SetText(FText(want)) end) end
    why("ok" .. res, "'%s' -> '%s' (%s, found by %s, skill %s)", base, want, RES_NAMES[res] or tostring(res), how, tostring(skill))
end

---------------------------------------------------------------------- rare-loot marker
-- "Human Trap" -> "Human Trap ★" on the target-cursor name (WBP_Btl_UnitSelectName) and
-- the Libra panel name (WBP_Btl_LibraUnitName) when the enemy has a rare drop or rare
-- steal. The game does not record a stolen rare item, so the marker stays all battle.
-- Markers stripped before adding ours: the configured one, common ones, and any used
-- this session. Another copy of this module (the other Libra mod) may have added its
-- marker already, so stripping repeats until nothing is left: never "Trap ★ ★".
local usedMarkers = { ["★"] = true, ["[Rare]"] = true, ["*"] = true, ["+"] = true }
local function hasItem(id) id = num(id); return id ~= nil and id > 0 end
local function stripMarkers(t)
    if CFG.RARE_MARKER and CFG.RARE_MARKER ~= "" then usedMarkers[CFG.RARE_MARKER] = true end
    local changed = true
    while changed do
        changed = false
        for m in pairs(usedMarkers) do
            local suffix = " " .. m
            if #t > #suffix and t:sub(-#suffix) == suffix then t = t:sub(1, -#suffix - 1); changed = true end
        end
    end
    return t
end
local markerLogged = {}
local function updateName(w)
    local tb = get(w, "Text_Name")
    if not valid(tb) then return end
    local cur = textOf(tb)
    if not cur or cur == "" then return end
    local base = stripMarkers(cur)
    local want = base
    if CFG.SHOW_RARE_MARKER and CFG.RARE_MARKER and CFG.RARE_MARKER ~= "" then
        local param = get(get(w, "CPP_VM_BtlUnitParam"), "BtlUnitParam")
        if valid(param) and num(select(2, pcall(function() return param:GetRelation() end))) == 2 then
            local scanned = (not CFG.RARE_MARKER_NEEDS_SCAN) or select(2, pcall(function() return param:IsAnalyzed() end)) == true
            local okR, raw = pcall(function() return param:GetRawParameter() end)
            if scanned and okR and raw and (hasItem(raw.DropRareItem) or hasItem(raw.StealRareItem)) then
                usedMarkers[CFG.RARE_MARKER] = true
                want = base .. " " .. CFG.RARE_MARKER
                if not markerLogged[base] then
                    markerLogged[base] = true
                    say("rare marker on %s (rare drop %s, rare steal %s)", base, tostring(raw.DropRareItem), tostring(raw.StealRareItem))
                end
            end
        end
    end
    if cur ~= want then pcall(function() tb:SetText(FText(want)) end) end
end
local NAME_CLASSES = { "WBP_Btl_UnitSelectName_C", "WBP_Btl_LibraUnitName_C" }

-- after a reload turned the spell multiplier off: put the labels back once
local stripMultiplier = false
local function stripPredictLabels(all)
    for _, w in ipairs(all) do
        local tb = get(get(w, "WBP_BtlSkillResistPredictAppearance"), "Text_EffectName")
        local cur = valid(tb) and textOf(tb)
        if cur then
            local base = cur:gsub("  x[%-%d%.]+$", "")
            if base ~= cur then pcall(function() tb:SetText(FText(base)) end) end
        end
    end
end

local function isRuntimeLayout(o)
    return valid(o) and objName(o):match("^WBP_Btl_LibraInfoDetailLayout_C_%d+$") ~= nil
end

function M.tick()
    for _, cls in ipairs(NAME_CLASSES) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            if valid(w) and not objName(w):find("Default__", 1, true) then
                local okV, vis = pcall(function() return w:IsVisible() end)
                if okV and vis then
                    local ok, err = pcall(updateName, w)
                    if not ok then sayOnce("nm:" .. tostring(err), "rare marker error: %s", tostring(err)) end
                end
            end
        end
    end
    if CFG.SHOW_MULTIPLIER or stripMultiplier then
        -- the prediction widget lives inside each enemy's UI (WBP_Btl_EnemyUI); a direct
        -- search found nothing in game (v1.2.1), so it is reached through its parent
        local all, seenW, nDirect, nParent = {}, {}, 0, 0
        local function addW(w, kind)
            local a = valid(w) and addr(w)
            if a and not seenW[a] then
                seenW[a] = true; all[#all + 1] = w
                if kind == "d" then nDirect = nDirect + 1 else nParent = nParent + 1 end
            end
        end
        for _, ui in ipairs(FindAllOf("WBP_Btl_EnemyUI_C") or {}) do
            if valid(ui) and not objName(ui):find("Default__", 1, true) then addW(get(ui, "WBP_BtlSkillResistPredict"), "p") end
        end
        for _, w in ipairs(FindAllOf("WBP_BtlSkillResistPredict_C") or {}) do addW(w, "d") end
        if #all > 0 then sayOnce("pfound", "spell panel: %d prediction widget(s) found (%d via enemy UI, %d direct)", #all, nParent, nDirect) end
        if not CFG.SHOW_MULTIPLIER then stripPredictLabels(all); stripMultiplier = false; all = {} end
        for _, w in ipairs(all) do
            if valid(w) and not objName(w):find("Default__", 1, true) then
                local okV, vis = pcall(function() return w:IsVisible() end)
                if not (okV and vis) then sayOnce("pvis", "spell panel: widget %s not visible (yet)", objName(w)) end
                if okV and vis then
                    local ok, err = pcall(updatePredict, w)
                    if not ok then sayOnce("pr:" .. tostring(err), "spell panel update error: %s", tostring(err)) end
                end
            end
        end
    end
    for _, l in ipairs(FindAllOf("WBP_Btl_LibraInfoDetailLayout_C") or {}) do
        if isRuntimeLayout(l) then
            local okV, vis = pcall(function() return l:IsVisible() end)
            if okV and vis then
                local ok, err = pcall(update, l)
                if not ok then sayOnce("upd:" .. tostring(err), "detail update error: %s", tostring(err)) end
            end
        end
    end
end

-- opts: overrides from config.lua; logger functions from main.lua
function M.init(opts, sayFn, sayOnceFn)
    say, sayOnce = sayFn or say, sayOnceFn or sayOnce
    for k, v in pairs(opts or {}) do if CFG[k] ~= nil then CFG[k] = v end end
    -- UE4SS exposes these as callable objects, not always plain Lua functions,
    -- so only check that they exist.
    if StaticConstructObject == nil or FText == nil then
        say("detail numbers disabled: this UE4SS build lacks StaticConstructObject/FText")
        return false
    end
    return true
end

-- F7: settings from config.lua again. Lines already drawn are refreshed on the next
-- tick; new font size / colors apply to lines created after the reload.
function M.reload(opts)
    local wasMul = CFG.SHOW_MULTIPLIER
    CFG = defaults()
    for k, v in pairs(opts or {}) do if CFG[k] ~= nil then CFG[k] = v end end
    for _, r in pairs(rows) do if r.str then r.str = {} end end
    if wasMul and not CFG.SHOW_MULTIPLIER then stripMultiplier = true end
    markerLogged = {}
end

return M
