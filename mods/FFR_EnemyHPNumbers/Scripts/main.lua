--[[----------------------------------------------------------------------------
    FFR_EnemyHPNumbers v1.2.6 -- FINAL FANTASY RESONANCE (UE 5.6, UE4SS 3.0.1)

    Shows each ENEMY's true HP and Break (stun) value as numbers directly above
    its own HP bar. Party bars are never touched.

        HP 3738/3888
        [================ HP bar ===============        ]
        Break 64/480
        [==== Break bar ====                            ]

    HOW
      Every enemy bar is a WBP_Btl_EnemyUI_C. Inside it, WBP_Btl_NPCUI holds the
      HP gauge (WBP_HitPointGauge), and the enemy's view model
      CPP_VM_BtlUnitParam holds the real integers:
          HitPointVM.CurrentPoint / MaxPoint      HP
          BreakPointVM.CurrentPoint / MaxPoint    Break
      One TextBlock is added INSIDE each of the game's own gauges (HP, Break),
      in a row reserved above that bar (gauge slot top padding). They are part of the bar's widget
      tree, so they move, scale, fade and hide together with the bar. No screen
      projection, no per-frame positioning.

    SAFETY
      * Game state is only read. The only writes are to widgets: our TextBlocks
        and the two gauge slot paddings (restored to asset values when off).
      * All UObject work runs on the game thread (ExecuteInGameThread).
      * Enemy bars are found with FindAllOf every tick, which returns only
        objects that still exist. A remembered bar missing from that list is
        forgotten without being touched: after a battle its memory can be freed
        and reused, UE4SS's IsValid() can still say true, and the next property
        read crashed the game inside UE4SS (pcall cannot catch that). v1.2.
        No NotifyOnNewObject: its callbacks can run on the loading thread.
      * Outside a battle no bar is touched at all: after a battle the bars are
        torn down while still listed, and a property read crashed. v1.2.5.
      * A bar seen in a battle that has ended is never touched again, not even
        when it is still listed in the next battle (it is freed while that
        battle loads, and that crashed). v1.2.6.
      * SetText is called only when the string changes.

    TOGGLE: F7 (CONFIG.TOGGLE_KEY) cycles three modes:
      1 numbers         text + HP bar damage-preview flash
      2 bar flash only  no text, the HP bar still flashes the predicted damage
      3 vanilla         the mod touches nothing
    ----------------------------------------------------------------------------]]

local CONFIG = {
    START_MODE    = 1,           -- 1 numbers, 2 bar flash only, 3 vanilla (F7 cycles)
    TOGGLE_KEY    = Key.F7,
    TICK_MS       = 100,

    FONT_PATH     = "/Game/UI/Font/UnipueText.UnipueText",
    FONT_SIZE     = 12,          -- UMG points, in the bar's own (DPI-scaled) space
    ROW_GAP       = 1,           -- space between text and the top of the bar frame
    BAR_H         = 4,           -- HP bar fill height (WBP_Btl_PointGauge SizeBox)
    FRAME         = 3,           -- frame padding around the fill (WBP_ProgressBG)

    COLOR_HP      = { R = 0.25, G = 1.00, B = 0.55, A = 1.00 },  -- Emerald Green matching party HUD
    COLOR_CAUTION = { R = 1.00, G = 0.82, B = 0.22, A = 1.00 },  -- Caution Amber matching party HUD
    COLOR_DANGER  = { R = 1.00, G = 0.22, B = 0.22, A = 1.00 },  -- Danger Ruby Red matching party HUD
    COLOR_BREAK   = { R = 1.00, G = 0.74, B = 0.25, A = 1.00 },  -- break bar colour
    SHADOW        = { R = 0.00, G = 0.00, B = 0.00, A = 0.90 },

    -- DAMAGE PREVIEW (while a skill is aimed at an enemy, before confirming)
    PREVIEW       = true,
    ARROW         = "→",       -- set to ">" if your font shows a box instead
    SAMPLES       = 10,          -- calc rolls averaged per target (game adds +-5% random)
    COLOR_HP_PREV = { R = 1.00, G = 0.62, B = 0.72, A = 1.00 },
    COLOR_KILL    = { R = 1.00, G = 0.22, B = 0.22, A = 1.00 },
    COLOR_BRK_PREV= { R = 1.00, G = 0.55, B = 0.20, A = 1.00 },
    COLOR_BREAK_ON= { R = 1.00, G = 0.92, B = 0.35, A = 1.00 },

    DEBUG         = false,       -- true = log attach/toggle events
}

local VIS_SHOWN, VIS_COLLAPSED = 3, 1    -- ESlateVisibility HitTestInvisible / Collapsed
local HALIGN_LEFT, VALIGN_TOP = 1, 1
local JUSTIFY_LEFT = 0

local MODE_NAMES = { "numbers", "bar flash only", "vanilla" }
local mode = CONFIG.START_MODE
local enabled = mode ~= 3     -- mod active (numbers or flash)
local textOn = mode == 1      -- numbers visible
local applyToggle = false
local entries = {}     -- address -> { ui, name, hpSlot, brkSlot, hp, brk, hpStr, brkStr }
local failed = {}      -- address -> name of a bar attach() gave up on
local logged = {}

local function say(fmt, ...)
    print("[FFR_EnemyHPNumbers] " .. string.format(fmt, ...) .. "\n")
end
local function log(fmt, ...)
    if CONFIG.DEBUG then say(fmt, ...) end
end
-- Problems are always logged (once each), so a user's UE4SS.log is a usable bug report.
local function logOnce(key, fmt, ...)
    if logged[key] then return end
    logged[key] = true
    say(fmt, ...)
end

local function valid(o)
    if type(o) ~= "userdata" then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end

local function get(o, name)
    if not valid(o) then return nil end
    local ok, v = pcall(function() return o[name] end)
    if ok then return v end
    return nil
end

local function int(o, name)
    local v = get(o, name)
    if type(v) == "number" then return math.floor(v) end
    return nil
end

local function className(o)
    local ok, s = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and s or nil
end

local function objName(o)
    local ok, s = pcall(function() return o:GetFName():ToString() end)
    return ok and s or ""
end

local function addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

-- Row height in UMG units. 1pt = 96/72 slate units; line height ~1.2 em.
local ROW_H = math.ceil(CONFIG.FONT_SIZE * 96 / 72 * 1.2)

-- ------------------------------------------------------------- widget building

local textClass, fontObj = nil, nil

local function newText(outerTree, overlay, halign, justify, color)
    textClass = valid(textClass) and textClass or StaticFindObject("/Script/UMG.TextBlock")
    if not valid(textClass) then return nil end
    local tb = StaticConstructObject(textClass, outerTree)
    if not valid(tb) then return nil end

    fontObj = valid(fontObj) and fontObj or StaticFindObject(CONFIG.FONT_PATH)
    if valid(fontObj) then
        tb:SetFont({ FontObject = fontObj, Size = CONFIG.FONT_SIZE })
    else
        logOnce("nofont", "font %s not loaded, using engine default", CONFIG.FONT_PATH)
        tb:SetFont({ Size = CONFIG.FONT_SIZE })
    end
    tb:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    tb:SetShadowOffset({ X = 1, Y = 1 })
    tb:SetShadowColorAndOpacity(CONFIG.SHADOW)
    tb:SetJustification(justify)
    tb:SetAutoWrapText(false)
    tb:SetVisibility(textOn and VIS_SHOWN or VIS_COLLAPSED)

    local slot = overlay:AddChildToOverlay(tb)
    if not valid(slot) then return nil end
    -- The overlay is the bar fill, inside a SizeBox with a fixed height, so the
    -- text can never stretch the bar. Text box = a ROW_H band ending ROW_GAP
    -- above the frame: negative top padding lifts it out, bottom padding
    -- cancels the fill + frame. Nothing in this chain clips.
    slot:SetPadding({
        Left = 0, Right = 0,
        Top = -(ROW_H + CONFIG.ROW_GAP + CONFIG.FRAME),
        Bottom = CONFIG.BAR_H + CONFIG.FRAME + CONFIG.ROW_GAP,
    })
    slot:SetHorizontalAlignment(halign)
    slot:SetVerticalAlignment(VALIGN_TOP)
    return tb
end

-- Vanilla top padding of each gauge's VerticalBoxSlot (from the assets):
-- HP gauge in WBP_Btl_NPCUI = 0, break gauge in WBP_Btl_EnemyUI = 4.
local HP_BASE_PAD, BRK_BASE_PAD = 0, 4

local function reserveRow(slot, base, on)
    -- Push the gauge down by one text row so nothing above it overlaps the
    -- numbers. Off = the asset's own padding, i.e. pure vanilla layout.
    pcall(function()
        slot:SetPadding({ Left = 0, Right = 0, Bottom = 0,
                          Top = base + (on and (ROW_H + CONFIG.ROW_GAP) or 0) })
    end)
end

local function applyRows(e)
    reserveRow(e.hpSlot, HP_BASE_PAD, textOn)
    reserveRow(e.brkSlot, BRK_BASE_PAD, textOn)
end

-- Bar fill overlay and outer slot of a WBP_Btl_PointGauge_C. `outer` is the
-- widget whose VerticalBoxSlot gets the reserved row.
local function gaugeParts(gauge, outer)
    local overlay = get(get(get(gauge, "Bar_Back"), "Slot"), "Parent")
    local slot = get(outer, "Slot")
    if not (valid(overlay) and valid(slot)) then return nil end      -- not built yet
    if className(overlay) ~= "Overlay" or className(slot) ~= "VerticalBoxSlot" then
        logOnce("layout", "unexpected layout: overlay=%s slot=%s -- skipping",
            tostring(className(overlay)), tostring(className(slot)))
        return false
    end
    return { tree = get(gauge, "WidgetTree"), overlay = overlay, slot = slot }
end

local function attach(ui)
    -- HP: the gauge inside WBP_Btl_NPCUI. Break: the gauge inside
    -- WBP_BreakPointGauge, whose own slot sits in the EnemyUI VerticalBox.
    local hpGauge = get(get(ui, "WBP_Btl_NPCUI"), "WBP_HitPointGauge")
    local brkWidget = get(ui, "WBP_BreakPointGauge")
    local h = gaugeParts(hpGauge, hpGauge)
    local b = gaugeParts(get(brkWidget, "WBP_PointGauge"), brkWidget)
    if h == false or b == false then return false end
    if not (h and b) then return nil end

    local ok, e = pcall(function()
        return {
            ui = ui, hpSlot = h.slot, brkSlot = b.slot,
            prog = get(hpGauge, "WBP_PredictProgress"),   -- HP bar's preview layer
            hp  = newText(h.tree, h.overlay, HALIGN_LEFT, JUSTIFY_LEFT, CONFIG.COLOR_HP),
            brk = newText(b.tree, b.overlay, HALIGN_LEFT, JUSTIFY_LEFT, CONFIG.COLOR_BREAK),
        }
    end)
    if not ok or not (valid(e.hp) and valid(e.brk)) then
        logOnce("attachfail", "attach failed: %s", tostring(e))
        return false
    end
    applyRows(e)
    return e
end

-- --------------------------------------------------------------------- update

local function viewModel(e)
    local vm = get(e.ui, "CPP_VM_BtlUnitParam")
    if valid(vm) then return vm end
    return get(get(e.ui, "WBP_Btl_NPCUI"), "CPP_VM_BtlUnitParam")
end

local function setText(e, field, tb, s, color)
    if not textOn then return end          -- bar flash only mode: no text
    if e[field] ~= s then
        tb:SetText(FText(s))
        e[field] = s
    end
    if color and e[field .. "Col"] ~= color then
        tb:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        e[field .. "Col"] = color
    end
end

--[[ ------------------------------------------------------------ damage preview

    TARGETS: the game itself previews Break on every enemy the highlighted
    skill will hit (BreakPointVM.bEnablePredict = true, PredictPointVM holds
    the exact Break value after the action). That flag is the target list,
    and its lifetime is the preview's lifetime.

    BREAK: the game's own prediction, shown as is. It matched the real result
    in every in-game test.

    HP: the game has no HP prediction, so it is computed with the game's own
    damage function, UCPP_BFL_UnitParameterCalc::CalcDamageRecovery. The game's
    enemy AI calls the same function to evaluate attacks, and in-game checks
    showed it changes nothing (HP, Break, attacker unchanged after calls).
    Notes from reverse engineering and testing:
      * It returns one hit; a multi-hit skill is the sum over hit = 1..hitCount.
      * A random +-5% (DT_UnitParameterCalc.atkDefRandomMag) is rolled per
        call, and crits (x1.5) can occur, so SAMPLES rolls are averaged
        (misses dropped; crits dropped unless the skill always crits; see
        averageDamage). Shown with "~": it is an estimate.
      * Aiming a single-target spell at all enemies makes the game use a
        different skill (skillIdAfterModeChange, e.g. Blizzard 220050 ->
        225030), which deals 40% (allDamageMagnification). Detected here as
        "Single skill + several targets".
    Verified in game: predicted 298-314 vs real 309 (2 hits), 113-115 vs
    real 112-113 (Fire on all), 215-238 vs 218, 295-324 vs 311.
]]

local RANDOM_MAG = 0.05          -- DT_UnitParameterCalc.atkDefRandomMag
local TARGET_SINGLE = 1          -- eSkillTargetType::Single
local TARGET_RANDOM = 5          -- eSkillTargetType::Random: targets not known in advance

local calcLib, skillLib = nil, nil
local skillCache = {}
local previewCache = { sig = nil, res = {} }

local function skillInfo(id)
    if skillCache[id] then return skillCache[id] end
    skillLib = valid(skillLib) and skillLib or StaticFindObject("/Script/mucha.Default__CPP_BFL_Skill")
    if not valid(skillLib) then return nil end
    local d = skillLib:GetSkillDataById(id)
    local function field(k) local ok, v = pcall(function() return d[k] end); if ok then return v end end
    local info = {
        target = field("TargetType"),
        after  = field("skillIdAfterModeChange"),
        hits   = field("hitCount"),
    }
    skillCache[id] = info
    return info
end

-- Average HP damage of `skill` from `actor` on one target, or nil.
--
-- Each "sample" asks the game for every hit of the skill once and adds the
-- hits up. Samples are sorted into two piles:
--   normal = no hit missed, no hit crit
--   crit   = no hit missed, at least one crit
-- Samples with a miss are thrown away: the preview answers "what happens IF
-- the attack lands". The normal pile is used when it has anything in it (crits
-- are luck, not something to plan on). Only skills that ALWAYS crit (e.g.
-- Deathblow: Crit 100%) leave the normal pile empty; then the crit pile is
-- the honest answer. Low-accuracy skills can miss a lot, so up to
-- MAX_TRIES samples are taken until SAMPLES landed ones exist.
--
-- DAMAGE IS READ FROM r.VariationValue, NOT before - after.
-- The game stores afterVariationValue = max(0, HP - damage) (seen in the
-- native code at 0x14522694d), so before - after can never exceed the
-- enemy's current HP. v1.1 used before - after: every overkill hit became
-- exactly "HP" damage, the kill test landed on its edge, and huge hits on
-- weak enemies showed "KILL?" instead of "KILL". VariationValue is the full
-- damage number, uncapped.
local MAX_TRIES_FACTOR = 4

local function averageDamage(actor, targetParam, skill, hits, isAll)
    calcLib = valid(calcLib) and calcLib or StaticFindObject("/Script/mucha.Default__CPP_BFL_UnitParameterCalc")
    if not valid(calcLib) or not valid(targetParam) then return nil end
    local normalSum, normalN, critSum, critN = 0, 0, 0, 0
    for _ = 1, CONFIG.SAMPLES * MAX_TRIES_FACTOR do
        local total, crit, miss = 0, false, false
        for hit = 1, hits do
            local r = calcLib:CalcDamageRecovery(actor, targetParam, skill, hit, {},
                false, isAll, false, 0, 1.0, false)
            if r.isMiss then miss = true end
            if r.isCritical then crit = true end
            -- VariationValue has no sign. A heal (HP goes up) counts as negative
            -- damage, so a heal never shows up as a kill.
            if r.afterVariationValue > r.beforeVariationValue then
                total = total - r.VariationValue
            else
                total = total + r.VariationValue
            end
        end
        if not miss then
            if crit then critSum, critN = critSum + total, critN + 1
            else normalSum, normalN = normalSum + total, normalN + 1 end
        end
        if normalN + critN >= CONFIG.SAMPLES then break end
    end
    if normalN > 0 then return normalSum / normalN end
    if critN > 0 then return critSum / critN end
    return nil
end

--[[ ACTIVE SKILL TARGETS (v1.2.3)

    Some damage passives read the attacker's target list,
    UCPP_UnitParameter::m_ActiveSkillTargets (+0x270). The game fills it when an
    action runs, so while a command is being chosen it is EMPTY. Found with
    Ghidra (all 181 ContFx overrides decompiled):
      * TakeInitiative (Preemptive Strike, +30% vs an enemy that has not acted
        this round), 0x1451464e0: if the list has fewer than 2 entries it reads
        entry [0] without checking for 0 entries. Empty list = null read = the
        game crashed (every version before this one, any Preemptive Strike
        holder aiming). It follows holder -> m_pOwnerBtlUnit (+0x360) ->
        m_pUnitParameter (+0x838) -> list, and entry [0] -> owner -> param ->
        +0x4E0 (actions taken this round), none of them null-checked.
      * DmgMulAllToSingle (count == 1), DmgMulByMissingTgt (P0 - count),
        DmgMulByTargetNum (count * P0): no crash, but an empty list gives a
        wrong preview.
    So for the length of the preview calculation the list holds exactly the
    targets the game itself highlights (the bEnablePredict set), then it is
    emptied again: the same state the game sets up when the action runs. All
    of it happens inside one game-thread call, so the game never sees it.
    Every pointer the native code follows is checked first. If anything is
    missing, the list cannot be filled, or a target holds Preemptive Strike
    itself, the HP estimate is skipped (the Break preview stays).
]]

local function ownerParam(param)
    return get(get(param, "m_pOwnerBtlUnit"), "m_pUnitParameter")
end

-- Every Preemptive Strike effect the calculation could reach (it sits in the
-- attacker's effect list, was granted by the attacker, or belongs to a target)
-- must lead to the attacker's own list (which gets filled) or to a list that
-- is already non-empty. The hook reads the list of holder -> owner -> param,
-- where holder = the effect's m_pTargetUnitParameter (+0x30).
local function takeInitiativeSafe(actor, targetSet)
    local a = addr(actor)
    local mine = {}
    local okL = pcall(function()
        get(actor, "m_ContEffectList"):ForEach(function(_, fx) mine[addr(fx:get()) or 0] = true end)
    end)
    if not okL then return false end
    for _, fx in ipairs(FindAllOf("CPP_ContFxTakeInitiative") or {}) do
        local holder = get(fx, "m_pTargetUnitParameter")
        local h = addr(holder)
        if mine[addr(fx)] or (h and targetSet[h]) or addr(get(fx, "m_pActionUnitParameter")) == a then
            local owner = ownerParam(holder)
            if addr(owner) ~= a then
                local list = get(owner, "m_ActiveSkillTargets")
                local ok, n = pcall(function() return list:GetArrayNum() end)
                if not (ok and type(n) == "number" and n > 0) then return false end
            end
        end
    end
    return true
end

-- Runs fn() with actor.m_ActiveSkillTargets = params, then empties the list
-- again. Does not run fn at all when that is not safe.
local function withActiveTargets(actor, params, fn)
    local a = addr(actor)
    if not a or #params == 0 or addr(ownerParam(actor)) ~= a then return end
    for _, p in ipairs(params) do
        if not valid(ownerParam(p)) then return end
    end
    local list = get(actor, "m_ActiveSkillTargets")
    local okN, n = pcall(function() return list:GetArrayNum() end)
    if not (okN and type(n) == "number") then return end
    if n > 0 then return fn() end              -- the game set it: leave it alone

    local filled = pcall(function()
        for i, p in ipairs(params) do list[i] = p end
    end)
    local okC, num = pcall(function() return list:GetArrayNum() end)
    filled = filled and okC and num == #params
    if filled then
        for i, p in ipairs(params) do
            if addr(list[i]) ~= addr(p) then filled = false; break end
        end
    end
    local ok, err = true, nil
    if filled then ok, err = pcall(fn) end
    pcall(function() list:Empty() end)
    if not filled then logOnce("fill", "could not set the target list, HP estimate skipped") end
    if not ok then error(err, 0) end
end

-- vm address -> { hpAfter, kill = "yes"|"maybe"|nil, brkAfter }, or {}.
local function computePreview()
    -- Targets = view models the game is previewing Break on (deduplicated:
    -- every enemy has two EnemyUI instances bound to the same view model).
    -- (`all` = `targets` in this edition; the Libra edition shows analyzed ones only.)
    local targets, all, total, anyUi = {}, {}, 0, nil
    for _, e in pairs(entries) do
        local vm = viewModel(e)
        local a = addr(vm)
        if a and not all[a] and get(get(vm, "BreakPointVM"), "bEnablePredict") == true then
            all[a] = vm
            total = total + 1
            targets[a] = vm
            anyUi = anyUi or e.ui
        end
    end
    if not anyUi then previewCache.sig = nil; return {} end

    local vmBattle = get(anyUi:GetOuter(), "CPP_VM_Battle")
    local skill = get(vmBattle, "FocusSkillId")
    local actorVm = valid(vmBattle) and vmBattle:GetCurrentActionUnitParamVM() or nil
    local actor = get(actorVm, "BtlUnitParam")

    -- Recompute only when something relevant changed.
    local parts = { tostring(skill), tostring(addr(actor)), "n" .. total }
    for a, vm in pairs(targets) do
        parts[#parts + 1] = string.format("%s:%s:%s", tostring(a),
            tostring(int(get(vm, "HitPointVM"), "CurrentPoint")),
            tostring(int(get(get(vm, "BreakPointVM"), "PredictPointVM"), "CurrentPoint")))
    end
    table.sort(parts)
    local sig = table.concat(parts, "|")
    if sig == previewCache.sig then return previewCache.res end

    local res = {}
    for a, vm in pairs(targets) do
        local brkVm = get(vm, "BreakPointVM")
        res[a] = { brkAfter = int(get(brkVm, "PredictPointVM"), "CurrentPoint") }
    end

    -- HP part: only with a valid actor + skill; never guessed otherwise.
    if valid(actor) and type(skill) == "number" and skill > 0 then
        local params, paramSet = {}, {}
        for _, vm in pairs(all) do
            local p = get(vm, "BtlUnitParam")
            local pa = addr(p)
            if not pa then params = {}; break end
            params[#params + 1], paramSet[pa] = p, true
        end
        local ok, err = pcall(function()
            local info = skillInfo(skill)
            if not info or info.target == TARGET_RANDOM then return end
            if not takeInitiativeSafe(actor, paramSet) then
                logOnce("ti-other", "another unit's Preemptive Strike has no target list, HP estimate skipped")
                return
            end
            local used = skill
            if total > 1 and info.target == TARGET_SINGLE and type(info.after) == "number" and info.after > 0 then
                used = info.after
                info = skillInfo(used) or info
            end
            local hits = (type(info.hits) == "number" and info.hits > 0) and info.hits or 1
            withActiveTargets(actor, params, function()
                for a, vm in pairs(targets) do
                    local hpVm = get(vm, "HitPointVM")
                    local hp = int(hpVm, "CurrentPoint")
                    local dmg = averageDamage(actor, get(vm, "BtlUnitParam"), used, hits, total > 1)
                    if hp and dmg then
                        local p = res[a]
                        p.hpAfter = math.max(0, math.floor(hp - dmg + 0.5))
                        p.hpMax = int(hpVm, "MaxPoint")
                        if dmg * (1 - RANDOM_MAG) >= hp then p.kill = "yes"
                        elseif dmg * (1 + RANDOM_MAG) >= hp then p.kill = "maybe" end
                    end
                end
            end)
        end)
        if not ok then logOnce("preview:" .. tostring(err), "HP preview failed: %s", tostring(err)) end
    end

    previewCache.sig, previewCache.res = sig, res
    return res
end

-- HP bar preview: the gauge's own WBP_PredictProgress layer (the same one the
-- Break bar uses). SetEnablePredict(true) pushes PredictPercent into the bar
-- material, false restores CurrentPercent (which the game keeps in sync), so
-- turning it off leaves the bar exactly as the game drew it.
local function setBarPreview(e, pct)
    if not valid(e.prog) then return end
    if pct then
        e.prog.PredictPercent = pct
        e.prog:SetEnablePredict(true)
        e.barOn = true
    elseif e.barOn then
        e.prog:SetEnablePredict(false)
        e.barOn = false
    end
end

local MobsTable = nil
local function loadMobs()
    if MobsTable then return MobsTable end
    local ok, res = pcall(dofile, "D:/SteamLibrary/steamapps/common/FINAL FANTASY RESONANCE/FFRS/Binaries/Win64/ue4ss/Mods/FFRAutoBattle/scripts/mobs.lua")
    if ok and type(res) == "table" then
        MobsTable = res
    else
        MobsTable = {}
    end
    return MobsTable
end

local function safeText(v)
    if v == nil then return nil end
    local s = nil
    if type(v) == "string" then
        s = v
    elseif type(v) == "userdata" then
        local ok, res = pcall(function() return v:ToString() end)
        if ok and type(res) == "string" then s = res end
    end
    if not s or s == "" or s:find("MISSING STRING TABLE ENTRY") then
        return nil
    end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return (s ~= "") and s or nil
end

local function enemyInfoOf(e)
    if e.unitName and e.unitLevel then return e.unitName, e.unitLevel end
    local vm = viewModel(e)
    local p = get(vm, "BtlUnitParam")
    local name = e.unitName
    local level = e.unitLevel

    if valid(p) then
        if not name then
            local ok1, n1 = pcall(function() return p:GetDuplicationUnitName() end)
            name = ok1 and safeText(n1) or nil
            if not name then
                local ok2, n2 = pcall(function() return p:GetUnitName() end)
                name = ok2 and safeText(n2) or nil
            end
            if not name then
                local ok3, n3 = pcall(function() return p.m_UnitName or p.UnitName end)
                name = ok3 and safeText(n3) or nil
            end
            if name then
                e.unitName = name
            end
        end

        if not level then
            local okL, lvl = pcall(function() return p:GetLevel() end)
            if okL and type(lvl) == "number" and lvl > 0 then
                level = lvl
            else
                local okL2, lvl2 = pcall(function() return p.m_Level or p.Level end)
                if okL2 and type(lvl2) == "number" and lvl2 > 0 then
                    level = lvl2
                end
            end
            if level then
                e.unitLevel = level
            end
        end
    end
    return name, level
end

local ELEMENT_TAGS = {
    ["fire"] = "Fire",
    ["ice"] = "Ice",
    ["thunder"] = "Thn",
    ["water"] = "Wtr",
    ["earth"] = "Erth",
    ["wind"] = "Wnd",
    ["light"] = "Lgt",
    ["dark"] = "Drk",
}

local function weaknessTag(name)
    if not name then return "" end
    local mobs = loadMobs()
    if not mobs then return "" end
    local key = name:lower():gsub("[0-9%s%-%_]+$", ""):gsub("[']", "")
    local card = mobs[key] or mobs[name:lower()]
    if card and card.weak then
        local tags = {}
        for el, isWeak in pairs(card.weak) do
            if isWeak then
                local tag = ELEMENT_TAGS[el] or el
                tags[#tags + 1] = tag
            end
        end
        if #tags > 0 then
            table.sort(tags)
            return "[" .. table.concat(tags, "/") .. "]"
        end
    end
    return ""
end

local function fmtNum(n)
    if not n then return "0" end
    local s = tostring(math.floor(math.abs(n)))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if n < 0 then return "-" .. formatted end
    return formatted
end

local function update(e, pv)
    local vm = viewModel(e)
    local hpVm, brkVm = get(vm, "HitPointVM"), get(vm, "BreakPointVM")
    local hp, hpMax = int(hpVm, "CurrentPoint"), int(hpVm, "MaxPoint")
    local brk, brkMax = int(brkVm, "CurrentPoint"), int(brkVm, "MaxPoint")
    local p = pv[addr(vm)]

    local wTag = ""
    local name, level = enemyInfoOf(e)
    if name then wTag = weaknessTag(name) end

    -- Clean enemy card, styled like the friendly party cards:
    --   line 1:  BasiliskC Lv18  2,061 (64%)     (no HP label, no pipes, no max HP)
    --   line 2:  Break 120/192  Weak Ice/Lgt
    local nameTag = (name and name ~= "") and name or ""
    local lvlTag = (level and level > 0) and string.format("Lv%d", level) or ""
    local enemyHeader = nameTag
    if lvlTag ~= "" then
        enemyHeader = (enemyHeader ~= "") and (enemyHeader .. " " .. lvlTag) or lvlTag
    end
    if enemyHeader ~= "" then enemyHeader = enemyHeader .. "  " end

    local lootTag = ""
    if _G.FFR_LootedEnemies then
        if (name and _G.FFR_LootedEnemies[name]) or (addr(vm) and _G.FFR_LootedEnemies[addr(vm)]) then
            lootTag = "Looted"
        end
    end

    local hpPct = (hp and hpMax and hpMax > 0) and math.floor((hp / hpMax) * 100 + 0.5) or 0

    -- Weakness and loot ride on the break line so the name line stays short.
    local weakTxt = (wTag ~= "") and ("Weak " .. wTag:gsub("[%[%]]", "")) or ""
    local brkExtra = ""
    if weakTxt ~= "" and lootTag ~= "" then
        brkExtra = "  " .. weakTxt .. "  " .. lootTag
    elseif weakTxt ~= "" then
        brkExtra = "  " .. weakTxt
    elseif lootTag ~= "" then
        brkExtra = "  " .. lootTag
    end

    -- Line 1: name, level, current HP (percent).
    if p and p.hpAfter and hp then
        local dmg = math.max(0, hp - p.hpAfter)
        local afterPct = (hpMax and hpMax > 0) and math.floor((p.hpAfter / hpMax) * 100 + 0.5) or 0
        if p.kill == "yes" then
            setText(e, "hpStr", e.hp, string.format("%s%s LETHAL", enemyHeader, fmtNum(hp)), CONFIG.COLOR_KILL)
        elseif p.kill == "maybe" then
            setText(e, "hpStr", e.hp, string.format("%s%s " .. CONFIG.ARROW .. " ~%s (%d%%) KILL?", enemyHeader, fmtNum(hp), fmtNum(p.hpAfter), afterPct), CONFIG.COLOR_KILL)
        else
            setText(e, "hpStr", e.hp, string.format("%s%s " .. CONFIG.ARROW .. " ~%s (-%s)", enemyHeader, fmtNum(hp), fmtNum(p.hpAfter), fmtNum(dmg)), CONFIG.COLOR_HP_PREV)
        end
        setBarPreview(e, (hpMax and hpMax > 0) and (p.hpAfter / hpMax) or nil)
    else
        local hpColor = CONFIG.COLOR_HP
        local suffix = ""
        if hpPct <= 25 and hpPct > 0 then
            hpColor = CONFIG.COLOR_DANGER or { R = 1.0, G = 0.22, B = 0.22, A = 1.0 }
            suffix = "  EXECUTE"
        elseif hpPct <= 50 then
            hpColor = CONFIG.COLOR_CAUTION or { R = 1.0, G = 0.82, B = 0.22, A = 1.0 }
        end
        local hpTxt = ""
        if hp and hpMax then
            hpTxt = (hpPct >= 100) and fmtNum(hp) or string.format("%s (%d%%)", fmtNum(hp), hpPct)
        end
        setText(e, "hpStr", e.hp, (hpTxt ~= "") and (enemyHeader .. hpTxt .. suffix) or "", hpColor)
        setBarPreview(e, nil)
    end

    -- Line 2: break gauge, stagger state, weakness, loot.
    if p and p.brkAfter and brk and p.brkAfter ~= brk then
        if p.brkAfter <= 0 then
            setText(e, "brkStr", e.brk, string.format("Break %s " .. CONFIG.ARROW .. " STAGGER!%s", fmtNum(brk), brkExtra), CONFIG.COLOR_BREAK_ON)
        else
            setText(e, "brkStr", e.brk, string.format("Break %s " .. CONFIG.ARROW .. " %s%s", fmtNum(brk), fmtNum(p.brkAfter), brkExtra), CONFIG.COLOR_BRK_PREV)
        end
    else
        if brk and brk <= 0 and (brkMax and brkMax > 0) then
            setText(e, "brkStr", e.brk, "STAGGERED! x2.0 DMG" .. brkExtra, CONFIG.COLOR_BREAK_ON)
        else
            setText(e, "brkStr", e.brk, (brk and brkMax) and string.format("Break %s/%s%s", fmtNum(brk), fmtNum(brkMax), brkExtra) or "", CONFIG.COLOR_BREAK)
        end
    end
end

local function isRuntimeEnemyUI(o)
    -- Runtime instances are named WBP_Btl_EnemyUI_C_<n>. Class templates and
    -- the CDO are not, and must never be modified.
    return valid(o) and objName(o):match("^WBP_Btl_EnemyUI_C_%d+$") ~= nil
end

-- Enemy bars alive right now: address -> { o, name }. Only these may be called
-- into. Names differ per instance (_C_<n>), so a new bar at a reused address
-- is told apart from the old one.
--
-- v1.2.6: bars of a battle that has ended are retired: "address|name" in `retired`,
-- never looked at again. 2026-10-29 crash: v1.2.5 forgot them at battle end, then at
-- the next battle start re-attached to the previous battle's bars (still listed,
-- IsValid true) and the GC of that battle load freed them under update().
local seen, retired = {}, {}
local pHud = nil
local lastHudCheck = 0

local function liveBars()
    local live = {}
    for _, o in ipairs(FindAllOf("WBP_Btl_EnemyUI_C") or {}) do
        if isRuntimeEnemyUI(o) then
            local a, name = addr(o), objName(o)
            local k = a and (tostring(a) .. "|" .. name)
            if k and not retired[k] then
                seen[k] = true
                live[a] = { o = o, name = name }
            end
        end
    end
    return live
end

-- v1.2.5: the battle UI is garbage collected some seconds after a battle ends
-- (2026-10-28 crash, after an escape). While that runs, FindAllOf still lists the
-- bars and IsValid says true, but their Blueprint class is already half freed: any
-- property read on a bar (here get(ui, "WBP_Btl_NPCUI") in attach) crashed inside
-- UE4SS, where pcall cannot catch it. So bars are touched only while a battle unit
-- is alive: a native CPP_BtlUnitParameter whose m_pOwnerBtlUnit is valid (the
-- signal FFR_BattleSwap logs as "battle over", seconds before that teardown).
-- CPP_BtlManager.m_BattleLevelList was tried first: it is empty in normal battles.
local function inBattle()
    for _, p in ipairs(FindAllOf("CPP_BtlUnitParameter") or {}) do
        if valid(get(p, "m_pOwnerBtlUnit")) then return true end
    end
    return false
end

local function tick()
    if not inBattle() then
        for k in pairs(seen) do retired[k] = true end
        seen, entries, failed = {}, {}, {}
        return
    end
    -- Forget dead bars BEFORE anything touches them (see SAFETY).
    local live = liveBars()

    -- Clean Party HUD: ensure character names stay pristine and numbers fit naturally
    local nowClock = os.clock()
    if nowClock - lastHudCheck >= 0.3 then
        lastHudCheck = nowClock
        if not pHud then
            local okH, modH = pcall(dofile, "D:/SteamLibrary/steamapps/common/FINAL FANTASY RESONANCE/FFRS/Binaries/Win64/ue4ss/Mods/FFRAutoBattle/Scripts/party_hud.lua")
            if okH and type(modH) == "table" then pHud = modH end
        end
        if pHud and pHud.tick then pcall(pHud.tick) end
    end
    for a, e in pairs(entries) do
        if not live[a] or live[a].name ~= e.name then entries[a] = nil end
    end
    for a, b in pairs(live) do
        if not entries[a] and failed[a] ~= b.name then
            local e = attach(b.o)
            if e == false then
                failed[a] = b.name
            elseif e then
                e.name = b.name
                entries[a] = e
                log("attached to %s", b.name)
            end
        end
    end

    -- Preview problems must never take the plain numbers down with them.
    local pv = {}
    if enabled and CONFIG.PREVIEW then
        local ok, res = pcall(computePreview)
        if ok then pv = res else logOnce("pv:" .. tostring(res), "preview error: %s", tostring(res)) end
    end

    for a, e in pairs(entries) do
        if not (valid(e.ui) and valid(e.hp) and valid(e.brk)
                and className(e.hp) == "TextBlock" and className(e.brk) == "TextBlock") then
            -- Our text is gone from a live bar: forget it, the next tick re-attaches.
            entries[a] = nil
        else
            if applyToggle then
                local vis = textOn and VIS_SHOWN or VIS_COLLAPSED
                e.hp:SetVisibility(vis)
                e.brk:SetVisibility(vis)
                applyRows(e)
                if not enabled then pcall(setBarPreview, e, nil) end
            end
            if enabled then
                local ok, err = pcall(update, e, pv)
                if not ok then logOnce("upd:" .. tostring(err), "update error: %s", tostring(err)) end
            end
        end
    end
    applyToggle = false
end

-- ----------------------------------------------------------------------- loop
-- Game thread only (v1.2.1). LoopAsync and RegisterKeyBind run their Lua on UE4SS's
-- own thread, inside the same Lua state as the game-thread tick, and an overlap can
-- corrupt the Lua VM and crash the game (FFR_MapMarkers v0.4/v0.5 did). The
-- experimental UE4SS build has LoopInGameThreadWithDelay: the tick runs there, and
-- keys are read on the game thread from a player controller found fresh every poll.
-- Stable UE4SS 3.0.1 lacks it, so the old way stays as the fallback there.
local GAME_THREAD = type(LoopInGameThreadWithDelay) == "function"
say("timers: %s", GAME_THREAD and "game thread" or "LoopAsync fallback (stable UE4SS)")

local function every(ms, fn)
    if GAME_THREAD then
        LoopInGameThreadWithDelay(ms, function() pcall(fn) end)
        return
    end
    local queued = false
    LoopAsync(ms, function()
        if not queued then
            queued = true
            ExecuteInGameThread(function()
                pcall(fn)
                queued = false
            end)
        end
        return false
    end)
end

-- key: Key.X for the fallback; keyName: the same key's FKey name ("F8") for polling
local function onKey(key, keyName, fn)
    if not GAME_THREAD then
        RegisterKeyBind(key, function() ExecuteInGameThread(function() pcall(fn) end) end)
        return
    end
    local wasDown = false
    LoopInGameThreadWithDelay(50, function()
        for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
            local okN, n = pcall(function() return pc:GetFullName() end)
            if okN and type(n) == "string" and not n:find("Default__", 1, true) then
                local ok, down = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(keyName) }) end)
                if not ok then return end
                down = down == true
                if down and not wasDown then pcall(fn) end
                wasDown = down
                return
            end
        end
    end)
end

every(CONFIG.TICK_MS, function()
    local ok, err = pcall(tick)
    if not ok then logOnce("tick:" .. tostring(err), "tick error: %s", tostring(err)) end
end)

onKey(CONFIG.TOGGLE_KEY, "F7", function()
    mode = mode % 3 + 1
    enabled, textOn = mode ~= 3, mode == 1
    applyToggle = true
    say("mode: %s", MODE_NAMES[mode])
end)

say("v1.2.6 loaded (mode: %s, toggle key in CONFIG)", MODE_NAMES[mode])
