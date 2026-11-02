-- Complete Roster Equipment & Abilities Highlighter for Final Fantasy Resonance
-- Fully supports all 8 Playable Characters, all 26 Visions, all Gear Tiers (Early -> Mid -> Late -> Endgame BiS)
-- Crash-Hardened: Zero recursion, Zero unsafe UStruct reflection, 100% Game-Thread Safe

local M = {}

local STAR = "\226\152\133 "

local CHAR_TAGS = {
    ["Rain"] = {
        -- Heavy Armor & Plate (Sentinel Tank EHP)
        ["blessed cuirass"]    = STAR .. "[CHOOSE THIS - BEST EARLY TANK]",
        ["iron armor"]         = STAR .. "[CHOOSE THIS - DEF UPGRADE]",
        ["steel armor"]        = STAR .. "[CHOOSE THIS - DEF UPGRADE]",
        ["mythril plate"]      = STAR .. "[CHOOSE THIS - TANK BiS]",
        ["knight's armor"]     = STAR .. "[CHOOSE THIS - TANK BiS]",
        ["gold armor"]         = STAR .. "[CHOOSE THIS - TANK BiS]",
        ["diamond armor"]      = STAR .. "[CHOOSE THIS - TANK BiS]",
        ["flame mail"]         = STAR .. "[CHOOSE THIS - FIRE DEF]",
        ["ice armor"]          = STAR .. "[CHOOSE THIS - ICE DEF]",
        ["dragon mail"]        = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["demon mail"]         = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["genji armor"]        = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["crystal armor"]      = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["force armor"]        = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["maximilian"]         = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Tank Shields
        ["buckler"]            = STAR .. "[CHOOSE THIS - SHIELD]",
        ["iron shield"]        = STAR .. "[CHOOSE THIS - SHIELD]",
        ["mythril shield"]     = STAR .. "[CHOOSE THIS - TANK BiS]",
        ["knight's shield"]    = STAR .. "[CHOOSE THIS - TANK BiS]",
        ["flame shield"]       = STAR .. "[CHOOSE THIS - ELEM SHIELD]",
        ["ice shield"]         = STAR .. "[CHOOSE THIS - ELEM SHIELD]",
        ["aegis shield"]       = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["genji shield"]       = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Tank Accessories
        ["bulletproof vest"]   = STAR .. "[CHOOSE THIS - TANK DEF+]",
        ["earrings of health"] = STAR .. "[CHOOSE THIS - TANK HP+]",
        ["titan's bangle"]     = STAR .. "[CHOOSE THIS - TANK BiS]",
        ["muscle belt"]        = STAR .. "[CHOOSE THIS - HP+]",
        ["barrier ring"]       = STAR .. "[CHOOSE THIS - MAG DEF+]",
        ["protect ring"]       = STAR .. "[CHOOSE THIS - AUTO-PROTECT]",
        ["safety bit"]         = STAR .. "[CHOOSE THIS - DEATH IMMUNE]",

        -- Greatswords & Weapons
        ["crimson saber"]      = STAR .. "[CHOOSE THIS - BALANCED]",
        ["iron sword"]         = STAR .. "[CHOOSE THIS - WEAPON]",
        ["broadsword"]         = STAR .. "[CHOOSE THIS - WEAPON]",
        ["mythril blade"]      = STAR .. "[CHOOSE THIS - ATK+]",
        ["flametongue"]        = STAR .. "[CHOOSE THIS - FIRE BiS]",
        ["coral sword"]        = STAR .. "[CHOOSE THIS - THUNDER+]",
        ["buster sword"]       = STAR .. "[CHOOSE THIS - HIGH ATK]",
        ["excalibur"]          = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["save the queen"]     = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["ragnarok"]           = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["ultima weapon"]      = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Visions (Role-Optimal)
        ["warrior of light"]   = STAR .. "[CHOOSE THIS - BEST TANK VISION]",
        ["cecil"]              = STAR .. "[CHOOSE THIS - BEST TANK VISION]",
        ["wilhelm"]            = STAR .. "[CHOOSE THIS - PURE TANK BiS]",
        ["charlotte"]          = STAR .. "[CHOOSE THIS - SENTINEL / ICE TANK]",
        ["knight of grandshelt charlotte"] = STAR .. "[CHOOSE THIS - SENTINEL / ICE TANK]",
        ["camille"]            = STAR .. "[CHOOSE THIS - LB / BREAK TANK]",
        ["firion"]             = STAR .. "[CHOOSE THIS - COUNTER TANK]",

        -- Recommended Abilities & Passives
        ["multi cover"]        = STAR .. "[CHOOSE THIS - BEST TANK PASSIVE]",
        ["multi-cover"]        = STAR .. "[CHOOSE THIS - BEST TANK PASSIVE]",
        ["arms akimbo"]        = STAR .. "[CHOOSE THIS - TANK PASSIVE]",
        ["double action"]      = STAR .. "[CHOOSE THIS - AGGRO / SHIELD]",
        ["half mp"]            = STAR .. "[CHOOSE THIS - MP CONSERVATION]",
        ["physical counter"]   = STAR .. "[CHOOSE THIS - COUNTER STAGGER]",
        ["magic counter"]      = STAR .. "[CHOOSE THIS - COUNTER STAGGER]",
        ["firaga blade"]       = STAR .. "[CHOOSE THIS - FIRE 3.0x BREAK]",
        ["tackle"]             = STAR .. "[CHOOSE THIS - HIGH STAGGER]",
        ["provoke"]            = STAR .. "[CHOOSE THIS - TANK AGGRO]",
    },

    ["Lasswell"] = {
        -- Katanas & Blades (Crit & Boss Finisher)
        ["shiden"]             = STAR .. "[CHOOSE THIS - HIGH ATK]",
        ["kotetsu"]            = STAR .. "[CHOOSE THIS - ATK+]",
        ["kazekiri"]           = STAR .. "[CHOOSE THIS - WIND BLADE]",
        ["osafune"]            = STAR .. "[CHOOSE THIS - ATK+]",
        ["murasame"]           = STAR .. "[CHOOSE THIS - CRIT BiS]",
        ["kiku-ichimonji"]     = STAR .. "[CHOOSE THIS - HIGH ATK]",
        ["icebrand"]           = STAR .. "[CHOOSE THIS - ICE BiS]",
        ["ashura"]             = STAR .. "[CHOOSE THIS - ATK+]",
        ["zanmato"]            = STAR .. "[CHOOSE THIS - HIGH ATK]",
        ["masamune"]           = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["muramasa"]           = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["chirijiraden"]       = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Light Armor / Ninja Gear (Speed & Crit)
        ["leather armor"]      = STAR .. "[CHOOSE THIS - EARLY ARMOR]",
        ["kenpogi"]            = STAR .. "[CHOOSE THIS - ATK+]",
        ["black gi"]           = STAR .. "[CHOOSE THIS - ATK UPGRADE]",
        ["ninja garb"]         = STAR .. "[CHOOSE THIS - SPEED/ATK]",
        ["shinobi gear"]       = STAR .. "[CHOOSE THIS - CRIT/SPEED]",
        ["mirage vest"]        = STAR .. "[CHOOSE THIS - EVASION]",
        ["assassins vest"]     = STAR .. "[CHOOSE THIS - CRIT BiS]",
        ["dark gear"]          = STAR .. "[CHOOSE THIS - ATK+]",
        ["brave suit"]         = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Crit & Physical Accessories (Includes Early Game Options)
        ["power wrist"]        = STAR .. "[CHOOSE THIS - ATK+ BiS]",
        ["hairband"]           = STAR .. "[CHOOSE THIS - EARLY DEF/HP]",
        ["earrings of health"] = STAR .. "[CHOOSE THIS - HP UPGRADE]",
        ["hyper wrist"]        = STAR .. "[CHOOSE THIS - ATK BiS]",
        ["hero ring"]          = STAR .. "[CHOOSE THIS - ATK/CRIT+]",
        ["black belt"]         = STAR .. "[CHOOSE THIS - CRIT/COUNTER]",
        ["hermes sandals"]     = STAR .. "[CHOOSE THIS - SPEED+]",
        ["sprint shoes"]       = STAR .. "[CHOOSE THIS - SPEED+]",
        ["monarch's ring"]     = STAR .. "[CHOOSE THIS - STATS+]",
        ["genji glove"]        = STAR .. "[CHOOSE THIS - DUAL-WIELD BiS]",
        ["celestial glove"]    = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Visions (Role-Optimal)
        ["cloud"]              = STAR .. "[CHOOSE THIS - BEST PHYS CRIT VISION]",
        ["sephiroth"]          = STAR .. "[CHOOSE THIS - BURST DPS BiS]",
        ["tidus"]              = STAR .. "[CHOOSE THIS - STAGGER / MULTI-HIT]",
        ["firion"]             = STAR .. "[CHOOSE THIS - COMBO SCALING]",
        ["noctis"]             = STAR .. "[CHOOSE THIS - CRIT AND SCAN]",

        -- Recommended Abilities & Passives
        ["cloud soul"]         = STAR .. "[CHOOSE THIS - BEST CRIT PASSIVE]",
        ["rearguard"]          = STAR .. "[CHOOSE THIS - BACKSTAB CRIT]",
        ["improvement"]        = STAR .. "[CHOOSE THIS - ATK SCALING]",
        ["scan & strike"]      = STAR .. "[CHOOSE THIS - WEAKNESS CRIT]",
        ["scan and strike"]    = STAR .. "[CHOOSE THIS - WEAKNESS CRIT]",
        ["double action"]      = STAR .. "[CHOOSE THIS - DUAL HIT]",
        ["half mp"]            = STAR .. "[CHOOSE THIS - MP CONSERVATION]",
        ["null moon"]          = STAR .. "[CHOOSE THIS - CRIT FINISHER]",
        ["dawn frost"]         = STAR .. "[CHOOSE THIS - ICE STAGGER]",
        ["blizzaga blade"]     = STAR .. "[CHOOSE THIS - ICE 3.0x BREAK]",
        ["barrage"]            = STAR .. "[CHOOSE THIS - MULTI-HIT]",
        ["aero blade"]         = STAR .. "[CHOOSE THIS - WIND BREAK]",
    },

    ["Fina"] = {
        -- Staves & Recovery
        ["wooden staff"]       = STAR .. "[CHOOSE THIS - STAFF]",
        ["staff of wrath"]     = STAR .. "[CHOOSE THIS - SPR+]",
        ["golden staff"]       = STAR .. "[CHOOSE THIS - SPR+]",
        ["mage's staff"]       = STAR .. "[CHOOSE THIS - SPR+]",
        ["rune staff"]         = STAR .. "[CHOOSE THIS - SPR+]",
        ["seraphim staff"]     = STAR .. "[CHOOSE THIS - HEAL BiS]",
        ["holy wand"]          = STAR .. "[CHOOSE THIS - DUALCAST/SPR]",
        ["nirvana"]            = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Robes
        ["cotton robe"]        = STAR .. "[CHOOSE THIS - ROBE]",
        ["silken robe"]        = STAR .. "[CHOOSE THIS - SPR+]",
        ["mage's habit"]       = STAR .. "[CHOOSE THIS - SPR+]",
        ["white robe"]         = STAR .. "[CHOOSE THIS - SPR/DEF]",
        ["minerva bustier"]    = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["rainbow robe"]       = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Accessories
        ["rosary"]             = STAR .. "[CHOOSE THIS - HEAL SPR+]",
        ["gold ring"]          = STAR .. "[CHOOSE THIS - DEF/SPR]",
        ["earrings of health"] = STAR .. "[CHOOSE THIS - HP UPGRADE]",
        ["hairband"]           = STAR .. "[CHOOSE THIS - DEF/HP]",
        ["angel earrings"]     = STAR .. "[CHOOSE THIS - REGEN/SPR]",
        ["star pendant"]       = STAR .. "[CHOOSE THIS - POISON IMMUNE]",
        ["fairy ring"]         = STAR .. "[CHOOSE THIS - HEAL+]",
        ["ribbon"]             = STAR .. "[CHOOSE THIS - STATUS IMMUNE]",

        -- Visions (Role-Optimal)
        ["leah"]               = STAR .. "[CHOOSE THIS - BEST HEALER VISION]",
        ["ayaka"]              = STAR .. "[CHOOSE THIS - REGEN / HEAL BiS]",
        ["tronn"]              = STAR .. "[CHOOSE THIS - HEAL + BREAK UTILITY]",
        ["amelia"]             = STAR .. "[CHOOSE THIS - SUPPORT / BREAK]",
        ["onion knight"]       = STAR .. "[CHOOSE THIS - LB TRIPLE CHARGE]",

        -- Recommended Abilities & Passives
        ["dualcast"]           = STAR .. "[CHOOSE THIS - BEST HEALER PASSIVE]",
        ["half mp"]            = STAR .. "[CHOOSE THIS - MP CONSERVATION]",
        ["lb triple charge"]   = STAR .. "[CHOOSE THIS - FAST REVIVE LB]",
        ["charge lb on heal"]  = STAR .. "[CHOOSE THIS - LB CYCLING]",
        ["auto-regen"]         = STAR .. "[CHOOSE THIS - PASSIVE REGEN]",
        ["curaja"]             = STAR .. "[CHOOSE THIS - FULL PARTY HEAL]",
        ["cura"]               = STAR .. "[CHOOSE THIS - PARTY HEAL]",
        ["arise"]              = STAR .. "[CHOOSE THIS - 100% REVIVE]",
        ["cheer"]              = STAR .. "[CHOOSE THIS - PARTY BUFF]",
    },

    ["Archwitch Fina"] = {
        -- Magic Rods & Whips
        ["black mage rod"]     = STAR .. "[CHOOSE THIS - MAG+]",
        ["demon rod"]          = STAR .. "[CHOOSE THIS - MAG+]",
        ["whip"]               = STAR .. "[CHOOSE THIS - WHIP]",
        ["thorned whip"]       = STAR .. "[CHOOSE THIS - MAG/POISON]",
        ["lilith rod"]         = STAR .. "[CHOOSE THIS - DARK/MAG BiS]",
        ["dark rod"]           = STAR .. "[CHOOSE THIS - DARK ELEM+]",
        ["meteor wand"]        = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Robes
        ["cotton robe"]        = STAR .. "[CHOOSE THIS - ROBE]",
        ["black robe"]         = STAR .. "[CHOOSE THIS - MAG+]",
        ["sorcerer's robe"]    = STAR .. "[CHOOSE THIS - MAG+]",
        ["dark robe"]          = STAR .. "[CHOOSE THIS - DARK ELEM+]",
        ["mystic garb"]        = STAR .. "[CHOOSE THIS - MAG BiS]",
        ["lordly robe"]        = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Accessories
        ["earrings"]           = STAR .. "[CHOOSE THIS - MAG+]",
        ["mage's earring"]     = STAR .. "[CHOOSE THIS - MAG BiS]",
        ["crystal ring"]       = STAR .. "[CHOOSE THIS - MAG/HP]",
        ["gold ring"]          = STAR .. "[CHOOSE THIS - DEF/SPR]",
        ["soul of thamasa"]    = STAR .. "[CHOOSE THIS - DUALCAST BiS]",
        ["ribbon"]             = STAR .. "[CHOOSE THIS - STATUS IMMUNE]",

        -- Visions
        ["terra"]              = STAR .. "[CHOOSE THIS - BEST BLACK MAGE VISION]",
        ["kefka"]              = STAR .. "[CHOOSE THIS - AOE NUKE BiS]",
        ["exdeath"]            = STAR .. "[CHOOSE THIS - DARK MAGIC BiS]",
        ["dark fina"]          = STAR .. "[CHOOSE THIS - SIGNATURE VISION]",
        ["archwitch fina"]     = STAR .. "[CHOOSE THIS - SIGNATURE VISION]",
        ["rinoa"]              = STAR .. "[CHOOSE THIS - MAG BURST]",

        -- Recommended Abilities & Passives
        ["dual black magic"]   = STAR .. "[CHOOSE THIS - DOUBLE NUKE]",
        ["dualcast"]           = STAR .. "[CHOOSE THIS - DUALCAST]",
        ["half mp"]            = STAR .. "[CHOOSE THIS - MP CONSERVATION]",
        ["improvement"]        = STAR .. "[CHOOSE THIS - MAG SCALING]",
        ["magic counter"]      = STAR .. "[CHOOSE THIS - RETALIATION]",
        ["dystopia"]           = STAR .. "[CHOOSE THIS - DARK NUKE]",
        ["firaga"]             = STAR .. "[CHOOSE THIS - FIRE 3.0x]",
        ["blizzaga"]           = STAR .. "[CHOOSE THIS - ICE 3.0x]",
        ["thundaga"]           = STAR .. "[CHOOSE THIS - THUNDER 3.0x]",
        ["osmose"]             = STAR .. "[CHOOSE THIS - MP SIPHON]",
    },

    ["Nichol"] = {
        -- Grimoires & Staves
        ["tactician's grimoire"] = STAR .. "[CHOOSE THIS - TACTICIAN BiS]",
        ["book of wisdom"]     = STAR .. "[CHOOSE THIS - SPR/MAG]",
        ["silver rod"]         = STAR .. "[CHOOSE THIS - STATS+]",
        ["platinum rod"]       = STAR .. "[CHOOSE THIS - SPR+]",
        ["rune rod"]           = STAR .. "[CHOOSE THIS - STATS+]",

        -- Robes & Coats
        ["tactician coat"]     = STAR .. "[CHOOSE THIS - TACTICIAN BiS]",
        ["scholar's robe"]     = STAR .. "[CHOOSE THIS - SPR/DEF]",
        ["silken robe"]        = STAR .. "[CHOOSE THIS - SPR+]",
        ["mystic garb"]        = STAR .. "[CHOOSE THIS - DEF/SPR]",
        ["wise man's robe"]    = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Accessories
        ["sage's ring"]        = STAR .. "[CHOOSE THIS - MP REGEN/SPR]",
        ["hero ring"]          = STAR .. "[CHOOSE THIS - STATS+]",
        ["gold ring"]          = STAR .. "[CHOOSE THIS - DEF/SPR]",
        ["protect ring"]       = STAR .. "[CHOOSE THIS - DEF+]",
        ["ribbon"]             = STAR .. "[CHOOSE THIS - STATUS IMMUNE]",

        -- Visions
        ["nichol"]             = STAR .. "[CHOOSE THIS - SIGNATURE VISION]",
        ["hope"]               = STAR .. "[CHOOSE THIS - STANCE BUFF+]",
        ["amelia"]             = STAR .. "[CHOOSE THIS - SUPPORT UTILITY]",
        ["edward"]             = STAR .. "[CHOOSE THIS - PARTY BUFF]",
        ["ignis"]              = STAR .. "[CHOOSE THIS - COOK / STATS]",

        -- Recommended Abilities & Passives
        ["dualcast"]           = STAR .. "[CHOOSE THIS - DOUBLE STANCE/BUFF]",
        ["soul of stance"]     = STAR .. "[CHOOSE THIS - STANCE EXTENSION]",
        ["stance mastery"]     = STAR .. "[CHOOSE THIS - FAST STANCE]",
        ["magic infusion"]     = STAR .. "[CHOOSE THIS - PARTY MP REFILL]",
        ["half mp"]            = STAR .. "[CHOOSE THIS - MP CONSERVATION]",
        ["barfira"]            = STAR .. "[CHOOSE THIS - 70% FIRE SHIELD]",
        ["barblizzara"]        = STAR .. "[CHOOSE THIS - 70% ICE SHIELD]",
        ["barthundara"]        = STAR .. "[CHOOSE THIS - 70% THUNDER SHIELD]",
    },

    ["Lid"] = {
        -- Wrenches & Hammers
        ["mechanist's wrench"] = STAR .. "[CHOOSE THIS - SIGNATURE WEAPON]",
        ["heavy wrench"]       = STAR .. "[CHOOSE THIS - BREAK POWER]",
        ["iron hammer"]        = STAR .. "[CHOOSE THIS - HIGH STAGGER]",
        ["mythril wrench"]     = STAR .. "[CHOOSE THIS - ATK/BREAK]",
        ["power hammer"]       = STAR .. "[CHOOSE THIS - STAGGER BiS]",

        -- Overalls & Light Armor
        ["mechanist overalls"] = STAR .. "[CHOOSE THIS - SIGNATURE ARMOR]",
        ["leather armor"]      = STAR .. "[CHOOSE THIS - EARLY ARMOR]",
        ["black gi"]           = STAR .. "[CHOOSE THIS - ATK+]",
        ["ninja garb"]         = STAR .. "[CHOOSE THIS - SPEED+]",
        ["mirage vest"]        = STAR .. "[CHOOSE THIS - EVASION]",
        ["brave suit"]         = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Accessories
        ["power wrist"]        = STAR .. "[CHOOSE THIS - ATK+]",
        ["hyper wrist"]        = STAR .. "[CHOOSE THIS - ATK+]",
        ["titan's bangle"]     = STAR .. "[CHOOSE THIS - HP/DEF]",
        ["hermes sandals"]     = STAR .. "[CHOOSE THIS - SPEED+]",
        ["black belt"]         = STAR .. "[CHOOSE THIS - COUNTER BREAK]",

        -- Visions
        ["lid"]                = STAR .. "[CHOOSE THIS - SIGNATURE VISION]",
        ["camille"]            = STAR .. "[CHOOSE THIS - RAPID BREAK]",
        ["edgar"]              = STAR .. "[CHOOSE THIS - MECH SLAYER]",
        ["cid"]                = STAR .. "[CHOOSE THIS - BREAK POWER BiS]",
        ["rikku"]              = STAR .. "[CHOOSE THIS - ITEM & STEAL MASTER]",

        -- Recommended Abilities & Passives
        ["break mastery"]      = STAR .. "[CHOOSE THIS - BREAK SPEED]",
        ["overdrive"]          = STAR .. "[CHOOSE THIS - MECH SLAYER]",
        ["half mp"]            = STAR .. "[CHOOSE THIS - MP CONSERVATION]",
        ["armor break"]        = STAR .. "[CHOOSE THIS - SHRED DEF]",
        ["weapon break"]       = STAR .. "[CHOOSE THIS - SHRED ATK]",
        ["mind break"]         = STAR .. "[CHOOSE THIS - SHRED MAG]",
        ["magic break"]        = STAR .. "[CHOOSE THIS - SHRED MAG]",
    },

    ["Jake"] = {
        -- Guns & Rifles
        ["handgun"]            = STAR .. "[CHOOSE THIS - WEAPON]",
        ["silver rifle"]       = STAR .. "[CHOOSE THIS - ATK+]",
        ["mythril gun"]        = STAR .. "[CHOOSE THIS - CRIT/ATK BiS]",
        ["quicksilver"]        = STAR .. "[CHOOSE THIS - SPEED/ATK]",
        ["aldore rifle"]       = STAR .. "[CHOOSE THIS - HIGH ATK]",
        ["death penalty"]      = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Coats & Light Armor
        ["corsair coat"]       = STAR .. "[CHOOSE THIS - ATK/SPEED]",
        ["leather armor"]      = STAR .. "[CHOOSE THIS - EARLY ARMOR]",
        ["black gi"]           = STAR .. "[CHOOSE THIS - ATK+]",
        ["ninja garb"]         = STAR .. "[CHOOSE THIS - SPEED+]",
        ["assassins vest"]     = STAR .. "[CHOOSE THIS - CRIT BiS]",
        ["mirage vest"]        = STAR .. "[CHOOSE THIS - EVASION]",

        -- Accessories
        ["power wrist"]        = STAR .. "[CHOOSE THIS - ATK+]",
        ["hyper wrist"]        = STAR .. "[CHOOSE THIS - ATK+]",
        ["hero ring"]          = STAR .. "[CHOOSE THIS - CRIT+]",
        ["hermes sandals"]     = STAR .. "[CHOOSE THIS - SPEED+]",
        ["black belt"]         = STAR .. "[CHOOSE THIS - COUNTER+]",
        ["genji glove"]        = STAR .. "[CHOOSE THIS - DUAL-WIELD BiS]",

        -- Visions
        ["jake"]               = STAR .. "[CHOOSE THIS - SIGNATURE VISION]",
        ["amelia"]             = STAR .. "[CHOOSE THIS - BEST GUNNER CRIT]",
        ["cecil"]              = STAR .. "[CHOOSE THIS - SURVIVABILITY]",
        ["cloud"]              = STAR .. "[CHOOSE THIS - ATK+ CRIT BURST]",
        ["vincent"]            = STAR .. "[CHOOSE THIS - GUN BURST BiS]",

        -- Recommended Abilities & Passives
        ["quick draw"]         = STAR .. "[CHOOSE THIS - SPEED / RELOAD]",
        ["arms akimbo"]        = STAR .. "[CHOOSE THIS - DUAL WIELD ATK]",
        ["half mp"]            = STAR .. "[CHOOSE THIS - SUSTAIN]",
        ["flame shot"]         = STAR .. "[CHOOSE THIS - FIRE BREAK]",
        ["lightning shot"]     = STAR .. "[CHOOSE THIS - THUNDER BREAK]",
        ["assault shot"]       = STAR .. "[CHOOSE THIS - CRIT SHOT]",
    },

    ["Sakura"] = {
        -- Lightning Rods & Staves
        ["sage's staff"]       = STAR .. "[CHOOSE THIS - SAGE BiS]",
        ["thunder rod"]        = STAR .. "[CHOOSE THIS - THUNDER+]",
        ["lightning rod"]      = STAR .. "[CHOOSE THIS - THUNDER+]",
        ["rune rod"]           = STAR .. "[CHOOSE THIS - MAG+]",
        ["stardust rod"]       = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Sage Robes
        ["sage's robe"]        = STAR .. "[CHOOSE THIS - SAGE BiS]",
        ["cotton robe"]        = STAR .. "[CHOOSE THIS - ROBE]",
        ["silken robe"]        = STAR .. "[CHOOSE THIS - SPR+]",
        ["sorcerer's robe"]    = STAR .. "[CHOOSE THIS - MAG+]",
        ["lordly robe"]        = STAR .. "[CHOOSE THIS - ENDGAME BiS]",
        ["rainbow robe"]       = STAR .. "[CHOOSE THIS - ENDGAME BiS]",

        -- Accessories
        ["earrings"]           = STAR .. "[CHOOSE THIS - MAG+]",
        ["mage's earring"]     = STAR .. "[CHOOSE THIS - MAG BiS]",
        ["crystal ring"]       = STAR .. "[CHOOSE THIS - MAG/HP]",
        ["soul of thamasa"]    = STAR .. "[CHOOSE THIS - DUALCAST BiS]",
        ["ribbon"]             = STAR .. "[CHOOSE THIS - STATUS IMMUNE]",

        -- Visions
        ["sakura"]             = STAR .. "[CHOOSE THIS - SIGNATURE VISION]",
        ["terra"]              = STAR .. "[CHOOSE THIS - MAG ELEM BiS]",
        ["vivi"]               = STAR .. "[CHOOSE THIS - DOUBLE BLACK MAGIC]",
        ["kefka"]              = STAR .. "[CHOOSE THIS - THUNDER NUKE]",
        ["shantotto"]          = STAR .. "[CHOOSE THIS - MULTI-ELEM BURST]",

        -- Recommended Abilities & Passives
        ["dualcast"]           = STAR .. "[CHOOSE THIS - DOUBLE SPELL]",
        ["thunder mastery"]    = STAR .. "[CHOOSE THIS - +50% THUNDER DMG]",
        ["half mp"]            = STAR .. "[CHOOSE THIS - MP CONSERVATION]",
        ["quick combo"]        = STAR .. "[CHOOSE THIS - CHAIN COMBO]",
        ["thundaja"]           = STAR .. "[CHOOSE THIS - SCALING THUNDER]",
        ["rebel thunder"]      = STAR .. "[CHOOSE THIS - SIGNATURE NUKE]",
    },
}

local function textOf(tb)
    if not (tb and tb:IsValid()) then return nil end
    local ok, txt = pcall(function() return tb:GetText():ToString() end)
    if ok and txt and #txt > 0 then return txt end
    return nil
end

local function clean(s)
    if not s or s == "" then return "" end
    local idx = s:lower():find("%[choose this")
    if idx then
        s = s:sub(1, idx - 1)
    end
    s = s:gsub("^[%s%*â˜…]+", ""):gsub("[%s%*â˜…]+$", "")
    s = s:gsub("Ã¢Ëœâ€¦", ""):gsub("ÃƒÂ¢Ã‹Å“Ã¢â‚¬Â¦", "")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function detectActiveCharacter(allTextBlocks)
    -- Pass 1: Check ROLE on screen
    for _, tb in ipairs(allTextBlocks) do
        local str = textOf(tb)
        if str and #str < 40 then
            local t = str:gsub("^%s+", ""):gsub("%s+$", "")
            if t == "Breaker" then return "Lasswell" end
            if t == "Sentinel" then return "Rain" end
            if t == "Luminary" or t == "Medic" or t == "Healer" then return "Fina" end
            if t == "Saboteur" or t == "Archwitch" or t == "Dark Fina" or t == "Witch" then return "Archwitch Fina" end
            if t == "Tactician" or t == "Synergist" then return "Nichol" end
            if t == "Mechanist" then return "Lid" end
            if t == "Corsair" then return "Jake" end
            if t == "Sage" then return "Sakura" end
        end
    end

    -- Pass 2: Check Character Name
    for _, tb in ipairs(allTextBlocks) do
        local str = textOf(tb)
        if str and #str < 30 then
            local t = str:gsub("^%s+", ""):gsub("%s+$", "")
            if t == "Lasswell" then return "Lasswell" end
            if t == "Rain" then return "Rain" end
            if t == "Fina" then return "Fina" end
            if t == "Archwitch Fina" or t == "Dark Fina" then return "Archwitch Fina" end
            if t == "Sakura" then return "Sakura" end
            if t == "Nichol" then return "Nichol" end
            if t == "Lid" then return "Lid" end
            if t == "Jake" then return "Jake" end
        end
    end

    -- Pass 3: Check Equipped Weapon/Gear unique to hero
    for _, tb in ipairs(allTextBlocks) do
        local str = textOf(tb)
        if str and #str < 40 then
            local c = clean(str):lower()
            if c == "shiden" or c == "kotetsu" or c == "kazekiri" or c == "murasame" then return "Lasswell" end
            if c == "crimson saber" or c == "blessed cuirass" then return "Rain" end
            if c == "staff of wrath" or c == "seraphim staff" then return "Fina" end
            if c == "black mage rod" or c == "thorned whip" then return "Archwitch Fina" end
            if c == "tactician's grimoire" or c == "tactician coat" then return "Nichol" end
            if c == "mechanist's wrench" or c == "mechanist overalls" then return "Lid" end
            if c == "handgun" or c == "silver rifle" or c == "corsair coat" then return "Jake" end
            if c == "sage's staff" or c == "sage's robe" then return "Sakura" end
        end
    end

    return "Rain"
end

-- Shallow, 100% crash-safe sibling inspection inside row container
local function isRowAlreadyEquippedBySomeone(tb)
    local okPar, par = pcall(function() return tb:GetParent() end)
    if not (okPar and par and par:IsValid()) then return false end

    -- Check direct children of the row container (No recursion, No UStruct reflection)
    local count = 0
    pcall(function() count = par:GetChildrenCount() end)
    if count > 0 then
        for i = 0, count - 1 do
            local child = nil
            pcall(function() child = par:GetChildAt(i) end)
            if child and child:IsValid() and child ~= tb then
                local okVis, vis = pcall(function() return child:GetVisibility() end)
                if okVis and (vis == 0 or vis == 3 or vis == 4) then
                    local okName, name = pcall(function() return child:GetFName():ToString():lower() end)
                    if okName and name then
                        if name:find("face") or name:find("chara") or name:find("unit") 
                           or name:find("portrait") or name:find("head") or name:find("member")
                           or name:find("icon_e") or name:find("badge") or name:find("equip") then
                            return true
                        end
                    end
                end
            end
        end
    end

    -- Check outer properties if available
    local okOut, outer = pcall(function() return tb:GetOuter() end)
    if okOut and outer and outer:IsValid() then
        local okEq, isEq = pcall(function() return outer.bIsEquipped or outer.bEquipped end)
        if okEq and isEq == true then return true end
        local okOth, isOth = pcall(function() return outer.bEquippedOther or outer.bIsEquippedOther end)
        if okOth and isOth == true then return true end
    end

    return false
end

local lastScanTime = 0

function M.tick()
    local now = os.clock()
    if now - lastScanTime < 1.0 then return end
    lastScanTime = now

    pcall(function()
        -- Cutscene / Outworld Fast Gate: Only scan when equipment / ability UI widgets are active
        local menu = FindFirstOf("WBP_UnitEquippedList_C")
        if not (menu and menu:IsValid()) then
            menu = FindFirstOf("WBP_UnitEquippedSkillList_C")
        end
        if not (menu and menu:IsValid()) then
            menu = FindFirstOf("WBP_VisionList_C")
        end
        if not (menu and menu:IsValid()) then return end

        local allTBs = FindAllOf("TextBlock")
        if not allTBs or #allTBs == 0 then return end

        local activeChar = detectActiveCharacter(allTBs)
        local tagTable = CHAR_TAGS[activeChar] or CHAR_TAGS["Rain"]

        for _, tb in ipairs(allTBs) do
            if tb and tb:IsValid() then
                local str = textOf(tb)
                if str and str ~= "" and #str < 65 then
                    local rawItem = clean(str)
                    local base = rawItem:lower():gsub("^%s+", ""):gsub("%s+$", "")
                    local recommendedTag = tagTable[base]

                    local hasTag = str:lower():find("%[choose this") ~= nil
                    local alreadyEquippedByOther = isRowAlreadyEquippedBySomeone(tb)

                    -- Only recommend if role-recommended AND NOT in use by someone else!
                    if recommendedTag and not alreadyEquippedByOther then
                        local want = rawItem .. " " .. recommendedTag
                        if str ~= want then
                            pcall(function() tb:SetText(FText(want)) end)
                        end
                    elseif hasTag and (alreadyEquippedByOther or not recommendedTag) then
                        pcall(function() tb:SetText(FText(rawItem)) end)
                    end
                end
            end
        end
    end)
end

return M