
--[[
    Auto Restore HP And Mana After Battle
    Version: 1.1

    Game: FINAL FANTASY RESONANCE
    Framework: UE4SS 3.0.1

    Automatically restores party HP and/or MP
    after every detected battle.

    FEATURES
    --------
    - Independent HP and MP restoration
    - Restore TO or BY a percentage of maximum
    - Optional resurrection of KO'd members
	- Optional restore only on level up
    - Native full recovery for resurrection
    - Original HP/MP preserved before recovery
    - Integer-only HP/MP setter values
    - Maximum HP/MP enforcement
    - Configurable enable/disable hotkey

    See Scripts/config.lua for configuration.
]]

-- ==================================================
-- 1. CONFIGURATION
-- ==================================================

local settings = require("config")

local POLL_INTERVAL = 500
local POST_BATTLE_DELAY = 2000
local DEBUG = false

local PREFIX = "[AutoRestoreHPManaAfterBattle] "

local function log(message)
    print(PREFIX .. tostring(message) .. "\n")
end

local function debug(message)
    if DEBUG then
        log(message)
    end
end

local function isEnabled(value)
    return value == 1 or value == true
end

local function normalizePercentage(value)
    if value == nil then
        return 100
    end

    value = tonumber(value)

    if not value or value ~= value then
        return 0
    end

    if value <= 0 then
        return 0
    end

    if value >= 100 then
        return 100
    end

    return math.ceil(value)
end

local function normalizeType(value)
    return tonumber(value) == 2 and 2 or 1
end

local options = {
    active = isEnabled(settings.enable_mod),
    onlyOnLevelUp = isEnabled(settings.restore_only_on_levelup),

    resurrection = isEnabled(
        settings.allow_resurrection
    ),

    health = isEnabled(settings.restore_health),
    healthType = normalizeType(
        settings.restore_health_type
    ),
    healthPercentage = normalizePercentage(
        settings.restore_health_percentage
    ),

    mana = isEnabled(settings.restore_mana),
    manaType = normalizeType(
        settings.restore_mana_type
    ),
    manaPercentage = normalizePercentage(
        settings.restore_mana_percentage
    ),

    toggleKey = settings.toggle_key or "DEL",
}

local function restoreHealthEnabled()
    return options.health
        and options.healthPercentage > 0
end

local function restoreManaEnabled()
    return options.mana
        and options.manaPercentage > 0
end

local function hasWork()
    return options.resurrection
        or restoreHealthEnabled()
        or restoreManaEnabled()
end

-- ==================================================
-- 2. UNREAL ENGINE ACCESS
-- ==================================================

local function isValid(object)
    if type(object) ~= "userdata" then
        return false
    end

    local ok, result = pcall(
        object.IsValid,
        object
    )

    return ok and result == true
end

local libraryCache = {}

local function getLibrary(name)
    local object = libraryCache[name]

    if not isValid(object) then
        object = StaticFindObject(
            "/Script/mucha.Default__" .. name
        )

        libraryCache[name] = object
    end

    return isValid(object) and object or nil
end

local function invoke(libraryName, method, ...)
    local object = getLibrary(libraryName)

    if not object then
        return false, nil
    end

    local args = {...}

    return pcall(function()
        return object[method](
            object,
            table.unpack(args)
        )
    end)
end

-- ==================================================
-- 3. BATTLE DETECTION
-- ==================================================

local cachedBattleManager = nil

local function isEncounterStarting()
    local ok, active = invoke(
        "CPP_BFL_Map",
        "IsDuringEncount"
    )

    return ok and active == true
end

local function hasActiveBattleLevels()
    -- Fast exit if not in encounter and not observed
    if not battleObserved and not isEncounterStarting() then
        return false
    end

    if not isValid(cachedBattleManager) then
        cachedBattleManager = FindFirstOf(
            "CPP_BtlManager"
        )
    end

    if not isValid(cachedBattleManager) then
        return false
    end

    local ok, count = pcall(function()
        return cachedBattleManager
            .m_BattleLevelList:GetArrayNum()
    end)

    return ok
        and type(count) == "number"
        and count > 0
end

local function isBattleActive()
    return isEncounterStarting()
        or hasActiveBattleLevels()
end

-- ==================================================
-- 4. FIELD AVAILABILITY
-- ==================================================

local function isFieldAvailable()
    local ok, player = invoke(
        "CPP_BFL_Map",
        "GetPlayerMapUnit"
    )

    if not ok or not isValid(player) then
        return false
    end

    local eventOk, playingEvent = invoke(
        "CPP_BFL_TalkEvent",
        "IsPlayingEvent"
    )

    return not (
        eventOk and playingEvent == true
    )
end

-- ==================================================
-- 5. PARTY DATA
-- ==================================================

local function getParameter(parameters, method)
    local ok, value = pcall(function()
        return parameters[method](parameters)
    end)

    if ok
        and type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge then

        return value
    end

    return nil
end

-- Obtain each unique party member's ID and
-- current parameter object.
local function getPartyMembers()
    local ok, partySize = invoke(
        "CPP_BFL_SaveDataParty",
        "GetPartyMax"
    )

    if not ok or type(partySize) ~= "number" then
        return nil
    end

    local members = {}
    local registered = {}

    for slot = 0, partySize - 1 do
        local found, unitId = invoke(
            "CPP_BFL_SaveDataParty",
            "GetPartyUnitIdFromIndex",
            slot
        )

        if found
            and type(unitId) == "number"
            and unitId > 0
            and not registered[unitId] then

            registered[unitId] = true

            local paramOk, parameters = invoke(
                "CPP_BFL_Map",
                "GetMapUnitParameter",
                unitId
            )

            if paramOk and isValid(parameters) then
                members[#members + 1] = {
                    id = unitId,
                    parameters = parameters,
                }
            end
        end
    end

    return #members > 0 and members or nil
end

-- ==================================================
-- 6. PARTY SNAPSHOT
-- ==================================================

local battleStartLevels = nil

-- Store numbers keyed by unit ID, never parameter objects across battles.
local function capturePartyLevels()
    local members = getPartyMembers()
    local levels = {}
    for _, member in ipairs(members or {}) do
        levels[member.id] = getParameter(member.parameters, "GetLevel")
    end
    return levels
end

-- Capture resource values BEFORE any recovery.
-- Every target is calculated from this snapshot.
local function capturePartySnapshot()
    local members = getPartyMembers()

    if not members then
        return nil, "Unable to retrieve party"
    end

    local snapshot = {}
    local containsKO = false

    for _, member in ipairs(members) do
        local param = member.parameters

        local hp = getParameter(
            param, "GetHitPoint"
        )

        local maxHP = getParameter(
            param, "GetMaxHitPoint"
        )

        local mp = getParameter(
            param, "GetMagicPoint"
        )

        local maxMP = getParameter(
            param, "GetMaxMagicPoint"
        )

        -- Do not perform a potentially destructive
        -- recovery with incomplete snapshot data.
        if hp == nil or maxHP == nil
            or mp == nil or maxMP == nil
            or maxHP <= 0 or maxMP < 0 then

            return nil, "Invalid party resources for "
                .. tostring(member.id)
        end

        local isKO = hp <= 0
        local leveledUp = false
        if options.onlyOnLevelUp then
            local before = battleStartLevels and battleStartLevels[member.id]
            local after = getParameter(param, "GetLevel")
            leveledUp = before ~= nil and after ~= nil and after > before
        end

        if isKO then
            containsKO = true
        end

        snapshot[#snapshot + 1] = {
            id = member.id,

            hp = hp,
            maxHP = maxHP,

            mp = mp,
            maxMP = maxMP,

            isKO = isKO,
            leveledUp = leveledUp,
        }
    end

    return {
        members = snapshot,
        containsKO = containsKO,
    }
end

-- ==================================================
-- 7. RESTORATION CALCULATIONS
-- ==================================================

-- Convert a calculated resource to an integer.
-- Maximum values are treated as whole-number caps.
local function clampResource(value, maximum)
    local cap = math.floor(maximum)

    return math.max(
        0,
        math.min(cap, math.ceil(value))
    )
end

-- Type 1: Restore TO percentage of maximum.
-- Type 2: Restore BY percentage of maximum.
--
-- Calculations always use original values.
local function calculateTarget(
    current,
    maximum,
    percentage,
    restoreType
)
    local currentValue = clampResource(
        current, maximum
    )

    local maxValue = math.floor(maximum)

    if maxValue <= 0 or percentage <= 0 then
        return currentValue
    end

    local amount = math.ceil(
        maxValue * percentage / 100
    )

    local target

    if restoreType == 1 then
        target = math.max(
            currentValue,
            amount
        )
    else
        target = currentValue + amount
    end

    return clampResource(target, maxValue)
end

-- ==================================================
-- 8. PREPARE RESTORATION PLAN
-- ==================================================

-- Build all target values before invoking the
-- native full-party recovery function.
local function buildRestorationPlan(snapshot)
    local plan = {}

    local healHP = restoreHealthEnabled()
    local healMP = restoreManaEnabled()

    local needsResurrection =
        options.resurrection
    if options.onlyOnLevelUp then
        needsResurrection = false
    end

    for _, member in ipairs(snapshot.members) do
        local targetHP = clampResource(
            member.hp, member.maxHP
        )

        local targetMP = clampResource(
            member.mp, member.maxMP
        )

        local eligible =
            not member.isKO or options.resurrection
        eligible = eligible
            and (not options.onlyOnLevelUp or member.leveledUp)

        if options.onlyOnLevelUp and eligible and member.isKO then
            needsResurrection = true
        end

        if eligible then
            if healHP then
                targetHP = calculateTarget(
                    member.hp,
                    member.maxHP,
                    options.healthPercentage,
                    options.healthType
                )

            elseif member.isKO and options.resurrection then
                -- Resurrection remains available
                -- even when HP restoration is disabled.
                targetHP = 1
            end

            if healMP then
                targetMP = calculateTarget(
                    member.mp,
                    member.maxMP,
                    options.manaPercentage,
                    options.manaType
                )
            end
        end

        plan[#plan + 1] = {
            id = member.id,

            originalHP = member.hp,
            originalMP = member.mp,

            targetHP = targetHP,
            targetMP = targetMP,

            isKO = member.isKO,
            eligible = eligible,
        }
    end

    return plan, needsResurrection
end

-- ==================================================
-- 9. NATIVE RESOURCE ACCESS
-- ==================================================

local function readCurrentResources(unitId)
    local ok, param = invoke(
        "CPP_BFL_Map",
        "GetMapUnitParameter",
        unitId
    )

    if not ok or not isValid(param) then
        return nil, nil
    end

    return getParameter(param, "GetHitPoint"),
           getParameter(param, "GetMagicPoint")
end

local function writeHP(unitId, value)
    return invoke(
        "CPP_BFL_Unit",
        "SetPlayableUnitHitPoint",
        unitId,
        value
    )
end

local function writeMP(unitId, value)
    return invoke(
        "CPP_BFL_Unit",
        "SetPlayableUnitMagicPoint",
        unitId,
        value
    )
end

local function performNativeResurrection()
    return invoke(
        "CPP_BFL_Map",
        "FullRecoveryMapUnit"
    )
end

-- ==================================================
-- 10. APPLY RESTORATION PLAN
-- ==================================================

local function applyRestorationPlan(
    plan,
    usedNativeRecovery
)
    local success = true

    for _, member in ipairs(plan) do

        -- In level-up mode, undo the party-wide recovery for excluded
        -- members too, including restoring excluded KO members to 0 HP.
        -- Without native recovery, excluded members are never written to.
        if member.eligible or (usedNativeRecovery and options.onlyOnLevelUp) then

            local currentHP, currentMP =
                readCurrentResources(member.id)

            if currentHP == nil or currentMP == nil then
                log(
                    "Unable to read unit "
                    .. tostring(member.id)
                )

                success = false
            else
                -- Native full recovery also heals
                -- living members. Restore each member
                -- to the calculated target.
                --
                -- When native recovery was not used,
                -- only write values that increase.
                local needsHPWrite =
                    usedNativeRecovery
                    and currentHP ~= member.targetHP
                    or (
                        not usedNativeRecovery
                        and member.targetHP > currentHP
                    )

                if needsHPWrite then
                    if not writeHP(
                        member.id,
                        member.targetHP
                    ) then

                        success = false

                        log(
                            "HP write failed for unit "
                            .. tostring(member.id)
                        )
                    end
                end

                local needsMPWrite =
                    usedNativeRecovery
                    and currentMP ~= member.targetMP
                    or (
                        not usedNativeRecovery
                        and member.targetMP > currentMP
                    )

                if needsMPWrite then
                    if not writeMP(
                        member.id,
                        member.targetMP
                    ) then

                        success = false

                        log(
                            "MP write failed for unit "
                            .. tostring(member.id)
                        )
                    end
                end
            end
        end
    end

    return success
end

-- ==================================================
-- 11. RESTORE PARTY
-- ==================================================

local function restoreParty()
    if not hasWork() then
        return true
    end

    -- Always capture original resources first.
    local snapshot, errorMessage =
        capturePartySnapshot()

    if not snapshot then
        log(errorMessage or "Snapshot failed")
        return false
    end

    local plan, needsResurrection =
        buildRestorationPlan(snapshot)

    local usedNativeRecovery = false

    -- Use native full recovery ONLY if
    -- resurrection is permitted and at least
    -- one party member was originally KO'd.
    if needsResurrection then
        debug("Performing native resurrection")

        local ok, err =
            performNativeResurrection()

        if not ok then
            log(
                "Native recovery failed: "
                .. tostring(err)
            )

            return false
        end

        usedNativeRecovery = true
    end

    local success = applyRestorationPlan(
        plan,
        usedNativeRecovery
    )

    if success then
        debug("Party restoration completed")
    else
        log("Party restoration incomplete")
    end

    return success
end

-- ==================================================
-- 12. POST-BATTLE MONITOR
-- ==================================================

local battleObserved = false
local fieldStableTicks = 0

local requiredStableTicks = math.ceil(
    POST_BATTLE_DELAY / POLL_INTERVAL
)

local function clearBattleState()
    battleObserved = false
    fieldStableTicks = 0
    battleStartLevels = nil
end

local function monitorBattle()
    if not options.active then
        return
    end

    if not hasWork() then
        return
    end

    if isBattleActive() then
        if not battleObserved then
            debug("Battle started")
            if options.onlyOnLevelUp then
                battleStartLevels = capturePartyLevels()
            end
        end

        battleObserved = true
        fieldStableTicks = 0
        return
    end

    if not battleObserved then
        return
    end

    if not isFieldAvailable() then
        fieldStableTicks = 0
        return
    end

    fieldStableTicks = fieldStableTicks + 1

    if fieldStableTicks < requiredStableTicks then
        return
    end

    debug("Battle completed")

    if restoreParty() then
        clearBattleState()
    end
end

-- ==================================================
-- 13. MOD TOGGLE
-- ==================================================

local function toggleAutoRestore()
    options.active = not options.active

    -- Discard pending restoration when toggled.
    clearBattleState()

    log(
        options.active
        and "Auto restore ENABLED"
        or "Auto restore DISABLED"
    )
end

local keyName = options.toggleKey
local keyCode = Key[keyName]

if not keyCode then
    log(
        "Invalid toggle key: "
        .. tostring(keyName)
    )

    keyName = "DEL"
    keyCode = Key.DEL
end

RegisterKeyBind(keyCode, function()
    ExecuteInGameThread(toggleAutoRestore)
end)

-- ==================================================
-- 14. MONITOR INITIALIZATION
-- ==================================================

LoopInGameThreadWithDelay(
    POLL_INTERVAL,
    function()
        local ok, err = pcall(monitorBattle)

        if not ok then
            log(
                "Monitor error: "
                .. tostring(err)
            )
        end
    end
)

-- ==================================================
-- 15. STARTUP INFORMATION
-- ==================================================

log("v1.1 initialized")
log("Enabled: " .. tostring(options.active))
log("Restore only on level-up: " .. tostring(options.onlyOnLevelUp))

log(
    "Allow resurrection: "
    .. tostring(options.resurrection)
)

log(
    "Restore health: "
    .. tostring(restoreHealthEnabled())
    .. " | Type: " .. options.healthType
    .. " | Percentage: "
    .. options.healthPercentage .. "%"
)

log(
    "Restore mana: "
    .. tostring(restoreManaEnabled())
    .. " | Type: " .. options.manaType
    .. " | Percentage: "
    .. options.manaPercentage .. "%"
)

log("Toggle key: " .. keyName)
