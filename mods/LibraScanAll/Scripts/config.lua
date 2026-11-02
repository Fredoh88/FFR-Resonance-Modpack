-- LibraScanAll settings. Edit, save, restart the game.
return {
    -- Key that reloads this file while playing, so changes apply without a
    -- restart (nil = no key). Both Libra mods use F7 by default.
    RELOAD_KEY = "F7",

    -- Effect types that count as "scan" (eSkillEffectType values from the game):
    --   29  = Analyze       (Libra, Analyze, and any item that uses those skills)
    --   142 = MechaMogscan  (Mecha Mog's scan)
    SCAN_EFFECT_TYPES = { [29] = true, [142] = true },

    -- What scan skills target after the patch (eSkillTargetType):
    --   2 = Group (one whole side = all enemies, default)
    --   4 = All   (everyone on the field, your party included)
    NEW_TARGET_TYPE = 2,

    -- Let the Libra info window handle several focused units at once
    -- (CPP_DA_BtlLibra.bIsAllowMultiUnitFocus). Without it the window can show
    -- the wrong unit with an empty page when a scan targets several enemies.
    ALLOW_MULTI_FOCUS = true,

    -- Once per session, list some enemy-targeted skills per target type in
    -- UE4SS.log (helps confirm which type means "all enemies").
    LOG_TARGET_TYPE_SAMPLES = true,

    -- Per scan skill:
    --   ALL_TARGETS  true  = hits every enemy (this mod's main feature)
    --                false = vanilla single target
    --   MP_COST      EXPERIMENTAL - currently has NO visible effect in game: the
    --                battle menu takes the cost from elsewhere. Leave it nil.
    -- LIBRA = Libra and other "Analyze" skills; MECHAMOG = Mechamog Scan (which
    -- also deals damage - with ALL_TARGETS that damage hits every enemy too).
    SKILLS = {
        LIBRA    = { ALL_TARGETS = true, MP_COST = nil },
        MECHAMOG = { ALL_TARGETS = true, MP_COST = nil },
    },

    -- Only skills currently using one of these target types are changed:
    --   1 = Single   3 = Spread   5 = Random   7 = SingleAndGroup
    RETARGET_FROM = { [1] = true, [3] = true, [5] = true, [7] = true },

    -- Also change skills that carry the scan as an added effect rather than as
    -- their main effect type. In this game Libra and Mechamog Scan are both
    -- built that way, so this must stay true for them to be changed. If such a
    -- skill also deals damage, that damage hits all enemies too (UE4SS.log says
    -- "deals damage: yes" for those).
    INCLUDE_MIXED_SKILLS = true,

    -- Leave skills alone whose default target is your own party (eRelation 1).
    SKIP_FRIENDLY_TARGETED = true,

    -- In battle, log each enemy's "analyzed" state whenever it changes
    -- (proves the scan reached every enemy).
    LOG_BATTLE_SCAN = true,

    -- Libra DETAIL screen numbers (based on "Libra Plus"): drop / steal chances
    -- next to each item, and a line listing every ailment resistance in %.
    SHOW_DETAIL_NUMBERS = true,
    -- If both LibraScanAll and LibraAutoScan are installed, whichever opens the
    -- detail screen first draws these lines: keep these settings the same in both.
    DETAILS = {
        SHOW_ITEM_CHANCES = true,   -- "Mist Potion  8.3%"
        SHOW_RESISTANCES  = true,   -- "80%   Blind · Sleep"
        SHOW_INFO         = true,   -- "EXP 120 · Gil 45 · Defeated 12"
        SHOW_HP           = true,   -- "HP 1,234 / 5,000 · Break 30 / 100"
        SHOW_DANGER       = true,   -- bosses: "!! Dangerous: ...  >> NEXT: ..."
        SHOW_MULTIPLIER   = true,   -- spell target panel: "WEAK!  x1.5"
        FONT_SIZE         = 12,
        COLOR             = { R = 1.00, G = 0.86, B = 0.45, A = 1.00 },
        DANGER_COLOR      = { R = 1.00, G = 0.42, B = 0.38, A = 1.00 },
        -- Marker after the name of enemies with a rare drop or rare steal, on the
        -- target cursor and the Libra panel: "Human Trap ★". Try "[Rare]" if the
        -- star shows as a box. The game does not record a stolen rare item, so the
        -- marker stays for the whole battle.
        SHOW_RARE_MARKER       = true,
        RARE_MARKER            = "★",
        RARE_MARKER_NEEDS_SCAN = true,  -- only on enemies you have scanned
    },

    -- Print every skill that was changed to UE4SS.log.
    LOG_EACH_SKILL = true,
}
