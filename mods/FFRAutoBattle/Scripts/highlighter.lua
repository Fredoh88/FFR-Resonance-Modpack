-- Complete Roster Equipment & Abilities Highlighter for Final Fantasy Resonance
-- Fully supports all 8 Playable Characters, all 26 Visions, all Gear Tiers
-- Individual Character Specialization & Intelligent Anti-Overlap Upgrade Scoring
-- Crash-Hardened: Zero recursion, Zero unsafe UStruct reflection, 100% Game-Thread Safe

local M = {}

pcall(function()
    local ok, ph = pcall(dofile, "D:/SteamLibrary/steamapps/common/FINAL FANTASY RESONANCE/FFRS/Binaries/Win64/ue4ss/Mods/FFRAutoBattle/Scripts/party_hud.lua")
    if ok and ph and ph.tick then
        ph.tick()
    end
end)

local STAR = "\226\152\133 " -- Unicode Black Star (★)

-- Priority tiers:
-- 5 = Signature BiS / Essential Role Defining
-- 4 = High Priority Upgrade
-- 3 = Solid Role Upgrade
-- 2 = Neutral / Generic Filler
-- 1 = Off-Role / Suboptimal
-- 0 = Incompatible

local CHAR_PROFILES = {
    ["Rain"] = {
        role = "Sentinel",
        gear = {
            -- Heavy Armor & Plate (Sentinel Tank EHP)
            ["blessed cuirass"]    = { score = 5, tag = "[CHOOSE THIS - BEST EARLY TANK]" },
            ["iron armor"]         = { score = 3, tag = "[CHOOSE THIS - DEF UPGRADE]" },
            ["steel armor"]        = { score = 3, tag = "[CHOOSE THIS - DEF UPGRADE]" },
            ["mythril plate"]      = { score = 4, tag = "[CHOOSE THIS - TANK BiS]" },
            ["knight's armor"]     = { score = 4, tag = "[CHOOSE THIS - TANK BiS]" },
            ["gold armor"]         = { score = 4, tag = "[CHOOSE THIS - TANK BiS]" },
            ["diamond armor"]      = { score = 4, tag = "[CHOOSE THIS - TANK BiS]" },
            ["flame mail"]         = { score = 4, tag = "[CHOOSE THIS - FIRE DEF]" },
            ["ice armor"]          = { score = 4, tag = "[CHOOSE THIS - ICE DEF]" },
            ["dragon mail"]        = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["demon mail"]         = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["genji armor"]        = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["crystal armor"]      = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["force armor"]        = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["maximilian"]         = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["phalanx"]            = { score = 4, tag = "[CHOOSE THIS - TANK MITIGATION]" },

            -- Tank Shields
            ["buckler"]            = { score = 3, tag = "[CHOOSE THIS - SHIELD]" },
            ["iron shield"]        = { score = 3, tag = "[CHOOSE THIS - SHIELD]" },
            ["mythril shield"]     = { score = 4, tag = "[CHOOSE THIS - TANK BiS]" },
            ["knight's shield"]    = { score = 4, tag = "[CHOOSE THIS - TANK BiS]" },
            ["flame shield"]       = { score = 4, tag = "[CHOOSE THIS - ELEM SHIELD]" },
            ["ice shield"]         = { score = 4, tag = "[CHOOSE THIS - ELEM SHIELD]" },
            ["aegis shield"]       = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["genji shield"]       = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },

            -- Tank Accessories
            ["bulletproof vest"]   = { score = 5, tag = "[CHOOSE THIS - TANK DEF+]" },
            ["earrings of health"] = { score = 4, tag = "[CHOOSE THIS - TANK HP+]" },
            ["titan's bangle"]     = { score = 5, tag = "[CHOOSE THIS - TANK BiS]" },
            ["muscle belt"]        = { score = 4, tag = "[CHOOSE THIS - HP+]" },
            ["barrier ring"]       = { score = 4, tag = "[CHOOSE THIS - MAG DEF+]" },
            ["protect ring"]       = { score = 4, tag = "[CHOOSE THIS - AUTO-PROTECT]" },
            ["safety bit"]         = { score = 5, tag = "[CHOOSE THIS - DEATH IMMUNE]" },

            -- Greatswords & Weapons
            ["crimson saber"]      = { score = 4, tag = "[CHOOSE THIS - BALANCED]" },
            ["iron sword"]         = { score = 3, tag = "[CHOOSE THIS - WEAPON]" },
            ["broadsword"]         = { score = 3, tag = "[CHOOSE THIS - WEAPON]" },
            ["mythril blade"]      = { score = 3, tag = "[CHOOSE THIS - ATK+]" },
            ["flametongue"]        = { score = 5, tag = "[CHOOSE THIS - FIRE BiS]" },
            ["coral sword"]        = { score = 4, tag = "[CHOOSE THIS - THUNDER+]" },
            ["buster sword"]       = { score = 4, tag = "[CHOOSE THIS - HIGH ATK]" },
            ["excalibur"]          = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["save the queen"]     = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["ragnarok"]           = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["ultima weapon"]      = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },

            -- Visions
            ["warrior of light"]   = { score = 5, tag = "[CHOOSE THIS - BEST TANK VISION]" },
            ["cecil"]              = { score = 5, tag = "[CHOOSE THIS - BEST TANK VISION]" },
            ["wilhelm"]            = { score = 5, tag = "[CHOOSE THIS - PURE TANK BiS]" },
            ["charlotte"]          = { score = 5, tag = "[CHOOSE THIS - SENTINEL / ICE TANK]" },
            ["knight of grandshelt charlotte"] = { score = 5, tag = "[CHOOSE THIS - SENTINEL / ICE TANK]" },
            ["camille"]            = { score = 4, tag = "[CHOOSE THIS - LB / BREAK TANK]" },
            ["firion"]             = { score = 4, tag = "[CHOOSE THIS - COUNTER TANK]" },
            ["cloud"]              = { score = 3, tag = "[CHOOSE THIS - EARLY ATK/DEF]" },

            -- Recommended Abilities & Mastered Sentinel Passives (Auto-Prioritized for Rain)
            ["sentinel"]           = { score = 5, tag = "[CHOOSE THIS - BEST SENTINEL TRAIT]" },
            ["sentinel guard"]     = { score = 5, tag = "[CHOOSE THIS - SENTINEL REDUCTION]" },
            ["sentinel's guard"]   = { score = 5, tag = "[CHOOSE THIS - SENTINEL REDUCTION]" },
            ["multi cover"]        = { score = 5, tag = "[CHOOSE THIS - BiS SENTINEL COVER]" },
            ["multi-cover"]        = { score = 5, tag = "[CHOOSE THIS - BiS SENTINEL COVER]" },
            ["arms akimbo"]        = { score = 5, tag = "[CHOOSE THIS - SENTINEL DUAL SHIELD]" },
            ["double action"]      = { score = 4, tag = "[CHOOSE THIS - AGGRO / SHIELD]" },
            ["half mp"]            = { score = 4, tag = "[CHOOSE THIS - MP CONSERVATION]" },
            ["physical counter"]   = { score = 5, tag = "[CHOOSE THIS - COUNTER STAGGER]" },
            ["magic counter"]      = { score = 5, tag = "[CHOOSE THIS - COUNTER STAGGER]" },
            ["counter burst"]      = { score = 4, tag = "[CHOOSE THIS - COUNTER DAMAGE]" },
            ["phalanx"]            = { score = 5, tag = "[CHOOSE THIS - SENTINEL MITIGATION]" },
            ["phalanx stance"]     = { score = 5, tag = "[CHOOSE THIS - SENTINEL MITIGATION]" },
            ["iron wall"]          = { score = 5, tag = "[CHOOSE THIS - DEFENSE +30%]" },
            ["royal guard"]        = { score = 5, tag = "[CHOOSE THIS - DEFENSE +30%]" },
            ["shield wall"]        = { score = 5, tag = "[CHOOSE THIS - PARTY COVER]" },
            ["stance mastery"]     = { score = 5, tag = "[CHOOSE THIS - FAST SENTINEL STANCE]" },
            ["break mastery"]      = { score = 5, tag = "[CHOOSE THIS - BREAK RESISTANCE]" },
            ["hp +30%"]            = { score = 5, tag = "[CHOOSE THIS - MAX EHP UPGRADE]" },
            ["hp +20%"]            = { score = 4, tag = "[CHOOSE THIS - TANK HP UPGRADE]" },
            ["hp +10%"]            = { score = 3, tag = "[CHOOSE THIS - TANK HP UPGRADE]" },
            ["def +30%"]           = { score = 5, tag = "[CHOOSE THIS - TANK DEF UPGRADE]" },
            ["def +20%"]           = { score = 4, tag = "[CHOOSE THIS - TANK DEF UPGRADE]" },
            ["def +10%"]           = { score = 3, tag = "[CHOOSE THIS - TANK DEF UPGRADE]" },
            ["auto-protect"]       = { score = 5, tag = "[CHOOSE THIS - PERMANENT SHIELD]" },
            ["auto-barrier"]       = { score = 5, tag = "[CHOOSE THIS - PERMANENT SHIELD]" },
            ["undying will"]       = { score = 5, tag = "[CHOOSE THIS - SURVIVE FATAL HIT]" },
            ["guts"]               = { score = 5, tag = "[CHOOSE THIS - SURVIVE FATAL HIT]" },
            ["last stand"]         = { score = 5, tag = "[CHOOSE THIS - SURVIVE FATAL HIT]" },
            ["draw attacks"]       = { score = 5, tag = "[CHOOSE THIS - PASSIVE AGGRO LOCK]" },
            ["taunt"]              = { score = 5, tag = "[CHOOSE THIS - PASSIVE AGGRO LOCK]" },
            ["vanguard roar"]      = { score = 5, tag = "[CHOOSE THIS - AGGRO / STAGGER]" },
            ["firaga blade"]       = { score = 4, tag = "[CHOOSE THIS - FIRE 3.0x BREAK]" },
            ["tackle"]             = { score = 5, tag = "[CHOOSE THIS - HIGH STAGGER INTERRUPT]" },
            ["provoke"]            = { score = 5, tag = "[CHOOSE THIS - BiS TANK AGGRO]" },
        }
    },

    ["Lasswell"] = {
        role = "Breaker",
        gear = {
            -- Katanas & Blades (Crit & Boss Finisher)
            ["shiden"]             = { score = 4, tag = "[CHOOSE THIS - HIGH ATK]" },
            ["kotetsu"]            = { score = 3, tag = "[CHOOSE THIS - ATK+]" },
            ["kazekiri"]           = { score = 4, tag = "[CHOOSE THIS - WIND BLADE]" },
            ["osafune"]            = { score = 3, tag = "[CHOOSE THIS - ATK+]" },
            ["murasame"]           = { score = 5, tag = "[CHOOSE THIS - CRIT BiS]" },
            ["kiku-ichimonji"]     = { score = 4, tag = "[CHOOSE THIS - HIGH ATK]" },
            ["icebrand"]           = { score = 5, tag = "[CHOOSE THIS - ICE BiS]" },
            ["ashura"]             = { score = 4, tag = "[CHOOSE THIS - ATK+]" },
            ["zanmato"]            = { score = 4, tag = "[CHOOSE THIS - HIGH ATK]" },
            ["masamune"]           = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["muramasa"]           = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["chirijiraden"]       = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },

            -- Light Armor / Ninja Gear (Speed & Crit)
            ["leather armor"]      = { score = 2, tag = "[CHOOSE THIS - EARLY ARMOR]" },
            ["kenpogi"]            = { score = 3, tag = "[CHOOSE THIS - ATK+]" },
            ["black gi"]           = { score = 4, tag = "[CHOOSE THIS - ATK UPGRADE]" },
            ["ninja garb"]         = { score = 4, tag = "[CHOOSE THIS - SPEED/ATK]" },
            ["shinobi gear"]       = { score = 5, tag = "[CHOOSE THIS - CRIT/SPEED]" },
            ["mirage vest"]        = { score = 4, tag = "[CHOOSE THIS - EVASION]" },
            ["assassins vest"]     = { score = 5, tag = "[CHOOSE THIS - CRIT BiS]" },
            ["dark gear"]          = { score = 4, tag = "[CHOOSE THIS - ATK+]" },
            ["brave suit"]         = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },

            -- Crit & Physical Accessories
            ["power wrist"]        = { score = 5, tag = "[CHOOSE THIS - ATK+ BiS]" },
            ["hyper wrist"]        = { score = 5, tag = "[CHOOSE THIS - ATK BiS]" },
            ["hero ring"]          = { score = 5, tag = "[CHOOSE THIS - ATK/CRIT+]" },
            ["black belt"]         = { score = 4, tag = "[CHOOSE THIS - CRIT/COUNTER]" },
            ["hermes sandals"]     = { score = 4, tag = "[CHOOSE THIS - SPEED+]" },
            ["sprint shoes"]       = { score = 4, tag = "[CHOOSE THIS - SPEED+]" },
            ["monarch's ring"]     = { score = 5, tag = "[CHOOSE THIS - STATS+]" },
            ["genji glove"]        = { score = 5, tag = "[CHOOSE THIS - DUAL-WIELD BiS]" },
            ["celestial glove"]    = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["earrings of health"] = { score = 2, tag = "[CHOOSE THIS - HP UPGRADE]" },

            -- Visions
            ["cloud"]              = { score = 5, tag = "[CHOOSE THIS - BEST PHYS CRIT VISION]" },
            ["sephiroth"]          = { score = 5, tag = "[CHOOSE THIS - BURST DPS BiS]" },
            ["tidus"]              = { score = 4, tag = "[CHOOSE THIS - STAGGER / MULTI-HIT]" },
            ["firion"]             = { score = 4, tag = "[CHOOSE THIS - COMBO SCALING]" },
            ["noctis"]             = { score = 4, tag = "[CHOOSE THIS - CRIT AND SCAN]" },

            -- Recommended Abilities & Mastered Breaker Passives (Auto-Prioritized for Lasswell)
            ["cloud soul"]         = { score = 5, tag = "[CHOOSE THIS - BEST CRIT PASSIVE]" },
            ["rearguard"]          = { score = 5, tag = "[CHOOSE THIS - BACKSTAB CRIT]" },
            ["improvement"]        = { score = 4, tag = "[CHOOSE THIS - ATK SCALING]" },
            ["scan & strike"]      = { score = 5, tag = "[CHOOSE THIS - WEAKNESS CRIT BiS]" },
            ["scan and strike"]    = { score = 5, tag = "[CHOOSE THIS - WEAKNESS CRIT BiS]" },
            ["crit rate +30%"]     = { score = 5, tag = "[CHOOSE THIS - CRIT CHANCE +30%]" },
            ["crit rate +20%"]     = { score = 4, tag = "[CHOOSE THIS - CRIT CHANCE +20%]" },
            ["atk +30%"]           = { score = 5, tag = "[CHOOSE THIS - ATK +30% BiS]" },
            ["atk +20%"]           = { score = 4, tag = "[CHOOSE THIS - ATK +20%]" },
            ["speed +20%"]         = { score = 4, tag = "[CHOOSE THIS - TURN SPEED+]" },
            ["blade mastery"]      = { score = 5, tag = "[CHOOSE THIS - +50% KATANA ATK]" },
            ["katana mastery"]     = { score = 5, tag = "[CHOOSE THIS - +50% KATANA ATK]" },
            ["ice mastery"]        = { score = 5, tag = "[CHOOSE THIS - +50% ICE DAMAGE]" },
            ["stagger surge"]      = { score = 5, tag = "[CHOOSE THIS - +50% STAGGER DMG]" },
            ["double action"]      = { score = 4, tag = "[CHOOSE THIS - DUAL HIT]" },
            ["dual-wield"]         = { score = 5, tag = "[CHOOSE THIS - DUAL WIELD BiS]" },
            ["half mp"]            = { score = 4, tag = "[CHOOSE THIS - MP CONSERVATION]" },
            ["null moon"]          = { score = 5, tag = "[CHOOSE THIS - CRIT FINISHER]" },
            ["dawn frost"]         = { score = 5, tag = "[CHOOSE THIS - STAGGER 27 BREAK]" },
            ["blizzaga blade"]     = { score = 4, tag = "[CHOOSE THIS - ICE 3.0x BREAK]" },
            ["barrage"]            = { score = 5, tag = "[CHOOSE THIS - MULTI-HIT COMBO]" },
            ["blade torrent"]      = { score = 4, tag = "[CHOOSE THIS - WIND COMBO]" },
        }
    },

    ["Fina"] = {
        role = "Luminary",
        gear = {
            -- Staves & Recovery
            ["wooden staff"]       = { score = 2, tag = "[CHOOSE THIS - STAFF]" },
            ["staff of wrath"]     = { score = 3, tag = "[CHOOSE THIS - SPR+]" },
            ["golden staff"]       = { score = 3, tag = "[CHOOSE THIS - SPR+]" },
            ["mage's staff"]       = { score = 3, tag = "[CHOOSE THIS - SPR+]" },
            ["rune staff"]         = { score = 4, tag = "[CHOOSE THIS - SPR+]" },
            ["seraphim staff"]     = { score = 5, tag = "[CHOOSE THIS - HEAL BiS]" },
            ["holy wand"]          = { score = 5, tag = "[CHOOSE THIS - DUALCAST/SPR]" },
            ["nirvana"]            = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },

            -- Robes
            ["cotton robe"]        = { score = 2, tag = "[CHOOSE THIS - ROBE]" },
            ["silken robe"]        = { score = 3, tag = "[CHOOSE THIS - SPR+]" },
            ["mage's habit"]       = { score = 3, tag = "[CHOOSE THIS - SPR+]" },
            ["white robe"]         = { score = 4, tag = "[CHOOSE THIS - SPR/DEF]" },
            ["minerva bustier"]    = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["rainbow robe"]       = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },

            -- Accessories
            ["rosary"]             = { score = 5, tag = "[CHOOSE THIS - HEAL SPR+]" },
            ["gold ring"]          = { score = 3, tag = "[CHOOSE THIS - DEF/SPR]" },
            ["earrings of health"] = { score = 3, tag = "[CHOOSE THIS - HP UPGRADE]" },
            ["angel earrings"]     = { score = 4, tag = "[CHOOSE THIS - REGEN/SPR]" },
            ["star pendant"]       = { score = 3, tag = "[CHOOSE THIS - POISON IMMUNE]" },
            ["fairy ring"]         = { score = 5, tag = "[CHOOSE THIS - HEAL+]" },
            ["ribbon"]             = { score = 5, tag = "[CHOOSE THIS - STATUS IMMUNE]" },

            -- Visions
            ["leah"]               = { score = 5, tag = "[CHOOSE THIS - BEST HEALER VISION]" },
            ["ayaka"]              = { score = 5, tag = "[CHOOSE THIS - REGEN / HEAL BiS]" },
            ["tronn"]              = { score = 4, tag = "[CHOOSE THIS - HEAL + BREAK UTILITY]" },
            ["amelia"]             = { score = 3, tag = "[CHOOSE THIS - SUPPORT / BREAK]" },
            ["onion knight"]       = { score = 4, tag = "[CHOOSE THIS - LB TRIPLE CHARGE]" },

            -- Recommended Abilities & Mastered Healer Passives (Auto-Prioritized for Fina)
            ["dualcast"]           = { score = 5, tag = "[CHOOSE THIS - BEST HEALER PASSIVE]" },
            ["half mp"]            = { score = 4, tag = "[CHOOSE THIS - MP CONSERVATION]" },
            ["lb triple charge"]   = { score = 5, tag = "[CHOOSE THIS - FAST REVIVE LB]" },
            ["charge lb on heal"]  = { score = 4, tag = "[CHOOSE THIS - LB CYCLING]" },
            ["spr +30%"]           = { score = 5, tag = "[CHOOSE THIS - HEALING SPR +30%]" },
            ["spr +20%"]           = { score = 4, tag = "[CHOOSE THIS - HEALING SPR +20%]" },
            ["spirit +30%"]        = { score = 5, tag = "[CHOOSE THIS - HEALING SPR +30%]" },
            ["white magic mastery"]= { score = 5, tag = "[CHOOSE THIS - +50% HEAL POTENCY]" },
            ["auto-regen"]         = { score = 5, tag = "[CHOOSE THIS - PASSIVE REGEN]" },
            ["auto-shell"]         = { score = 4, tag = "[CHOOSE THIS - PASSIVE SHELL]" },
            ["curaja"]             = { score = 5, tag = "[CHOOSE THIS - 100% FULL PARTY HEAL]" },
            ["cura"]               = { score = 4, tag = "[CHOOSE THIS - PARTY HEAL]" },
            ["arise"]              = { score = 5, tag = "[CHOOSE THIS - 100% REVIVE]" },
            ["cheer"]              = { score = 4, tag = "[CHOOSE THIS - PARTY ATK/DEF BUFF]" },
            ["holy ray"]           = { score = 4, tag = "[CHOOSE THIS - LIGHT BREAK NUKER]" },
        }
    },

    ["Archwitch Fina"] = {
        role = "Saboteur",
        gear = {
            -- Magic Rods & Whips
            ["black mage rod"]     = { score = 3, tag = "[CHOOSE THIS - MAG+]" },
            ["demon rod"]          = { score = 4, tag = "[CHOOSE THIS - MAG+]" },
            ["thorned whip"]       = { score = 4, tag = "[CHOOSE THIS - MAG/POISON]" },
            ["lilith rod"]         = { score = 5, tag = "[CHOOSE THIS - DARK/MAG BiS]" },
            ["dark rod"]           = { score = 4, tag = "[CHOOSE THIS - DARK ELEM+]" },
            ["meteor wand"]        = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },

            -- Robes
            ["cotton robe"]        = { score = 2, tag = "[CHOOSE THIS - ROBE]" },
            ["black robe"]         = { score = 4, tag = "[CHOOSE THIS - MAG+]" },
            ["sorcerer's robe"]    = { score = 4, tag = "[CHOOSE THIS - MAG+]" },
            ["dark robe"]          = { score = 5, tag = "[CHOOSE THIS - DARK ELEM+]" },
            ["mystic garb"]        = { score = 4, tag = "[CHOOSE THIS - MAG BiS]" },
            ["lordly robe"]        = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },

            -- Accessories
            ["earrings"]           = { score = 4, tag = "[CHOOSE THIS - MAG+]" },
            ["mage's earring"]     = { score = 5, tag = "[CHOOSE THIS - MAG BiS]" },
            ["crystal ring"]       = { score = 4, tag = "[CHOOSE THIS - MAG/HP]" },
            ["soul of thamasa"]    = { score = 5, tag = "[CHOOSE THIS - DUALCAST BiS]" },
            ["ribbon"]             = { score = 5, tag = "[CHOOSE THIS - STATUS IMMUNE]" },

            -- Visions
            ["terra"]              = { score = 5, tag = "[CHOOSE THIS - BEST BLACK MAGE VISION]" },
            ["kefka"]              = { score = 5, tag = "[CHOOSE THIS - AOE NUKE BiS]" },
            ["exdeath"]            = { score = 5, tag = "[CHOOSE THIS - DARK MAGIC BiS]" },
            ["dark fina"]          = { score = 5, tag = "[CHOOSE THIS - SIGNATURE VISION]" },
            ["archwitch fina"]     = { score = 5, tag = "[CHOOSE THIS - SIGNATURE VISION]" },

            -- Recommended Abilities & Passives
            ["dual black magic"]   = { score = 5, tag = "[CHOOSE THIS - DOUBLE NUKE]" },
            ["dualcast"]           = { score = 5, tag = "[CHOOSE THIS - DUALCAST]" },
            ["half mp"]            = { score = 4, tag = "[CHOOSE THIS - MP CONSERVATION]" },
            ["dystopia"]           = { score = 5, tag = "[CHOOSE THIS - DARK NUKE]" },
            ["firaga"]             = { score = 4, tag = "[CHOOSE THIS - FIRE 3.0x]" },
            ["blizzaga"]           = { score = 4, tag = "[CHOOSE THIS - ICE 3.0x]" },
            ["thundaga"]           = { score = 4, tag = "[CHOOSE THIS - THUNDER 3.0x]" },
        }
    },

    ["Nichol"] = {
        role = "Tactician",
        gear = {
            ["tactician's grimoire"] = { score = 5, tag = "[CHOOSE THIS - TACTICIAN BiS]" },
            ["book of wisdom"]       = { score = 4, tag = "[CHOOSE THIS - SPR/MAG]" },
            ["tactician coat"]       = { score = 5, tag = "[CHOOSE THIS - TACTICIAN BiS]" },
            ["scholar's robe"]       = { score = 4, tag = "[CHOOSE THIS - SPR/DEF]" },
            ["sage's ring"]          = { score = 5, tag = "[CHOOSE THIS - MP REGEN/SPR]" },
            ["nichol"]               = { score = 5, tag = "[CHOOSE THIS - SIGNATURE VISION]" },
            ["hope"]                 = { score = 4, tag = "[CHOOSE THIS - STANCE BUFF+]" },
            ["dualcast"]             = { score = 5, tag = "[CHOOSE THIS - DOUBLE STANCE/BUFF]" },
            ["soul of stance"]       = { score = 5, tag = "[CHOOSE THIS - STANCE EXTENSION]" },
            ["stance mastery"]       = { score = 5, tag = "[CHOOSE THIS - FAST STANCE]" },
        }
    },

    ["Lid"] = {
        role = "Mechanist",
        gear = {
            ["mechanist's wrench"]   = { score = 5, tag = "[CHOOSE THIS - SIGNATURE WEAPON]" },
            ["heavy wrench"]         = { score = 4, tag = "[CHOOSE THIS - BREAK POWER]" },
            ["iron hammer"]          = { score = 4, tag = "[CHOOSE THIS - HIGH STAGGER]" },
            ["mythril wrench"]       = { score = 4, tag = "[CHOOSE THIS - ATK/BREAK]" },
            ["power hammer"]         = { score = 5, tag = "[CHOOSE THIS - STAGGER BiS]" },
            ["mechanist overalls"]   = { score = 5, tag = "[CHOOSE THIS - SIGNATURE ARMOR]" },
            ["lid"]                  = { score = 5, tag = "[CHOOSE THIS - SIGNATURE VISION]" },
            ["cid"]                  = { score = 5, tag = "[CHOOSE THIS - BREAK POWER BiS]" },
            ["rikku"]                = { score = 4, tag = "[CHOOSE THIS - ITEM & STEAL MASTER]" },
            -- Recommended Abilities & Mastered Mechanist Passives (Auto-Prioritized for Lid)
            ["break mastery"]        = { score = 5, tag = "[CHOOSE THIS - BREAK SPEED BiS]" },
            ["armor break"]          = { score = 5, tag = "[CHOOSE THIS - SHRED DEF]" },
            ["mental break"]         = { score = 5, tag = "[CHOOSE THIS - SHRED SPR]" },
            ["weapon break"]         = { score = 5, tag = "[CHOOSE THIS - SHRED ATK]" },
            ["speed +30%"]           = { score = 5, tag = "[CHOOSE THIS - FIRST TURN ACTION]" },
            ["speed +20%"]           = { score = 4, tag = "[CHOOSE THIS - FAST GAUGE ACCUM]" },
            ["thunder mastery"]      = { score = 5, tag = "[CHOOSE THIS - +50% THUNDER DMG]" },
            ["t.r.n.d"]              = { score = 5, tag = "[CHOOSE THIS - STAGGER 27 BURST]" },
            ["march of the machines"] = { score = 5, tag = "[CHOOSE THIS - AOE MACHINE CLEAVE]" },
            ["quick draw"]           = { score = 4, tag = "[CHOOSE THIS - ATB ACCELERATION]" },
            ["half mp"]              = { score = 4, tag = "[CHOOSE THIS - MP CONSERVATION]" },
        }
    },

    ["Jake"] = {
        role = "Corsair",
        gear = {
            ["handgun"]              = { score = 3, tag = "[CHOOSE THIS - WEAPON]" },
            ["silver rifle"]         = { score = 3, tag = "[CHOOSE THIS - ATK+]" },
            ["mythril gun"]          = { score = 4, tag = "[CHOOSE THIS - CRIT/ATK BiS]" },
            ["quicksilver"]          = { score = 4, tag = "[CHOOSE THIS - SPEED/ATK]" },
            ["aldore rifle"]         = { score = 4, tag = "[CHOOSE THIS - HIGH ATK]" },
            ["death penalty"]        = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["corsair coat"]         = { score = 5, tag = "[CHOOSE THIS - ATK/SPEED]" },
            ["jake"]                 = { score = 5, tag = "[CHOOSE THIS - SIGNATURE VISION]" },
            ["amelia"]               = { score = 5, tag = "[CHOOSE THIS - BEST GUNNER CRIT]" },
            ["vincent"]              = { score = 5, tag = "[CHOOSE THIS - GUN BURST BiS]" },
            ["quick draw"]           = { score = 5, tag = "[CHOOSE THIS - SPEED / RELOAD]" },
            ["arms akimbo"]          = { score = 4, tag = "[CHOOSE THIS - DUAL WIELD ATK]" },
        }
    },

    ["Sakura"] = {
        role = "Sage",
        gear = {
            ["sage's staff"]         = { score = 5, tag = "[CHOOSE THIS - SAGE BiS]" },
            ["thunder rod"]          = { score = 4, tag = "[CHOOSE THIS - THUNDER+]" },
            ["lightning rod"]        = { score = 4, tag = "[CHOOSE THIS - THUNDER+]" },
            ["stardust rod"]         = { score = 5, tag = "[CHOOSE THIS - ENDGAME BiS]" },
            ["sage's robe"]          = { score = 5, tag = "[CHOOSE THIS - SAGE BiS]" },
            ["sakura"]               = { score = 5, tag = "[CHOOSE THIS - SIGNATURE VISION]" },
            ["terra"]                = { score = 5, tag = "[CHOOSE THIS - MAG ELEM BiS]" },
            ["vivi"]                 = { score = 4, tag = "[CHOOSE THIS - DOUBLE BLACK MAGIC]" },
            ["dualcast"]             = { score = 5, tag = "[CHOOSE THIS - DOUBLE SPELL]" },
            ["thunder mastery"]      = { score = 5, tag = "[CHOOSE THIS - +50% THUNDER DMG]" },
            ["rebel thunder"]        = { score = 5, tag = "[CHOOSE THIS - SIGNATURE NUKE]" },
        }
    }
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
    s = s:gsub("^[%s%*★]+", ""):gsub("[%s%*★]+$", "")
    s = s:gsub("â˜…", ""):gsub("★", "")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local lastConfirmedChar = "Rain"

local function detectActiveCharacter(allTextBlocks)
    -- Priority 1: Check ROLE on screen (each character has a unique Role)
    for _, tb in ipairs(allTextBlocks) do
        local str = textOf(tb)
        if str and #str < 35 then
            local t = str:gsub("^%s+", ""):gsub("%s+$", "")
            if t == "Sentinel" then lastConfirmedChar = "Rain"; return "Rain" end
            if t == "Breaker" then lastConfirmedChar = "Lasswell"; return "Lasswell" end
            if t == "Luminary" or t == "Medic" or t == "Healer" then lastConfirmedChar = "Fina"; return "Fina" end
            if t == "Mechanist" then lastConfirmedChar = "Lid"; return "Lid" end
            if t == "Tactician" or t == "Synergist" then lastConfirmedChar = "Nichol"; return "Nichol" end
            if t == "Saboteur" or t == "Archwitch" or t == "Dark Fina" then lastConfirmedChar = "Archwitch Fina"; return "Archwitch Fina" end
            if t == "Corsair" then lastConfirmedChar = "Jake"; return "Jake" end
            if t == "Sage" then lastConfirmedChar = "Sakura"; return "Sakura" end
        end
    end

    -- Priority 2: Check for "Lv. %d+" paired with character name in center status panel
    for i, tb in ipairs(allTextBlocks) do
        local str = textOf(tb)
        if str and str:find("Lv%s*%.?%s*%d+") then
            for j = math.max(1, i - 2), math.min(#allTextBlocks, i + 3) do
                local nStr = textOf(allTextBlocks[j])
                if nStr then
                    local cleanN = nStr:gsub("^%s+", ""):gsub("%s+$", "")
                    if cleanN == "Rain" then lastConfirmedChar = "Rain"; return "Rain" end
                    if cleanN == "Lasswell" then lastConfirmedChar = "Lasswell"; return "Lasswell" end
                    if cleanN == "Fina" then lastConfirmedChar = "Fina"; return "Fina" end
                    if cleanN == "Lid" then lastConfirmedChar = "Lid"; return "Lid" end
                    if cleanN == "Nichol" then lastConfirmedChar = "Nichol"; return "Nichol" end
                    if cleanN == "Jake" then lastConfirmedChar = "Jake"; return "Jake" end
                    if cleanN == "Sakura" then lastConfirmedChar = "Sakura"; return "Sakura" end
                    if cleanN == "Archwitch Fina" or cleanN == "Dark Fina" then lastConfirmedChar = "Archwitch Fina"; return "Archwitch Fina" end
                end
            end
        end
    end

    -- Priority 3: Fall back to last reliably confirmed character
    return lastConfirmedChar or "Rain"
end

-- Get score and tag for a specific item and character
-- Includes Dynamic Role-Based Fallback: Evaluates newly swapped Visions, unlocked Masteries, and uncataloged gear
local function getItemData(rawItemBase, charName)
    local prof = CHAR_PROFILES[charName]
    if not prof then return 0, nil end
    if prof.gear then
        local entry = prof.gear[rawItemBase]
        if entry then
            return entry.score or 0, entry.tag
        end
    end

    -- Dynamic Role-Based Auto-Selection Fallback:
    -- When Visions are swapped or new mastery nodes unlock, automatically score and recommend the best role abilities!
    local s = rawItemBase:lower()
    local role = prof.role or ""

    if role == "Sentinel" then
        -- Rain / Tank: Aggro, Mitigation, EHP, Shields, Cover, Counters
        if s:find("sentinel") or s:find("cover") or s:find("provoke") or s:find("taunt")
           or s:find("phalanx") or s:find("iron wall") or s:find("royal guard") or s:find("shield wall")
           or s:find("undying") or s:find("guts") or s:find("last stand") or s:find("draw attacks")
           or s:find("arms akimbo") or s:find("counter") or s:find("barrier") then
            return 5, "[CHOOSE THIS - BEST SENTINEL TRAIT]"
        elseif s:find("hp %+%d+") or s:find("def %+%d+") or s:find("guard") or s:find("defend")
           or s:find("shield") or s:find("cuirass") or s:find("plate") or s:find("armor")
           or s:find("bunker") or s:find("bulwark") or s:find("mitigat") or s:find("tackle") then
            return 4, "[CHOOSE THIS - SENTINEL BiS]"
        elseif s:find("wilhelm") or s:find("cecil") or s:find("charlotte") or s:find("warrior of light") then
            return 5, "[CHOOSE THIS - BEST TANK VISION]"
        end

    elseif role == "Breaker" then
        -- Lasswell / Physical DPS: Crit, Blade, Stagger, Speed, Break
        if s:find("null moon") or s:find("dawn frost") or s:find("blade mastery") or s:find("katana mastery")
           or s:find("crit rate") or s:find("scan & strike") or s:find("rearguard") or s:find("cloud soul")
           or s:find("stagger surge") or s:find("dual%-wield") or s:find("chirijiraden") or s:find("masamune") then
            return 5, "[CHOOSE THIS - BREAKER BiS]"
        elseif s:find("crit") or s:find("katana") or s:find("blade") or s:find("stagger") or s:find("ice")
           or s:find("frost") or s:find("atk %+%d+") or s:find("speed %+%d+") or s:find("barrage")
           or s:find("cross") or s:find("slash") or s:find("pierce") or s:find("shinobi") then
            return 4, "[CHOOSE THIS - BREAKER UPGRADE]"
        elseif s:find("cloud") or s:find("sephiroth") or s:find("tidus") or s:find("noctis") then
            return 5, "[CHOOSE THIS - BEST PHYS CRIT VISION]"
        end

    elseif role == "Luminary" then
        -- Fina / Healers: Full Party Heals, Revives, SPR, Regen
        if s:find("curaja") or s:find("curaga") or s:find("arise") or s:find("dualcast")
           or s:find("white magic mastery") or s:find("lb triple charge") or s:find("auto%-regen")
           or s:find("spr %+%d+") or s:find("spirit %+%d+") or s:find("nirvana") or s:find("holy wand") then
            return 5, "[CHOOSE THIS - LUMINARY BiS]"
        elseif s:find("cura") or s:find("cure") or s:find("heal") or s:find("raise") or s:find("revive")
           or s:find("regen") or s:find("cleanse") or s:find("esuna") or s:find("staff") or s:find("robe")
           or s:find("rosary") or s:find("cheer") then
            return 4, "[CHOOSE THIS - HEALER UPGRADE]"
        elseif s:find("leah") or s:find("ayaka") or s:find("folka") or s:find("aerith") then
            return 5, "[CHOOSE THIS - BEST HEALER VISION]"
        end

    elseif role == "Mechanist" then
        -- Lid: Armor Break, Mental Break, Machine, Stagger
        if s:find("break mastery") or s:find("armor break") or s:find("mental break") or s:find("weapon break")
           or s:find("t%.r%.n%.d") or s:find("march of the machines") or s:find("speed %+%d+") then
            return 5, "[CHOOSE THIS - MECHANIST BiS]"
        elseif s:find("break") or s:find("wrench") or s:find("hammer") or s:find("machine") or s:find("shred")
           or s:find("thunder") or s:find("stagger") then
            return 4, "[CHOOSE THIS - MECHANIST UPGRADE]"
        elseif s:find("cid") or s:find("rikku") or s:find("edgar") then
            return 5, "[CHOOSE THIS - BREAK POWER BiS]"
        end

    elseif role == "Saboteur" then
        -- Dark Fina: Dark magic, Dystopia, Rod, MAG+
        if s:find("dystopia") or s:find("dual black magic") or s:find("dualcast") or s:find("mag %+%d+") then
            return 5, "[CHOOSE THIS - SABOTEUR BiS]"
        elseif s:find("dark") or s:find("nuke") or s:find("rod") or s:find("whip") or s:find("firaga") or s:find("blizzaga") or s:find("thundaga") then
            return 4, "[CHOOSE THIS - MAGIC UPGRADE]"
        end

    elseif role == "Sage" then
        -- Sakura: Thunder, Lightning, Sage BiS, MAG+
        if s:find("sage") or s:find("thunder mastery") or s:find("rebel thunder") or s:find("dualcast") or s:find("mag %+%d+") then
            return 5, "[CHOOSE THIS - SAGE BiS]"
        elseif s:find("thunder") or s:find("lightning") or s:find("staff") or s:find("rod") then
            return 4, "[CHOOSE THIS - SAGE UPGRADE]"
        end

    elseif role == "Tactician" then
        if s:find("tactician") or s:find("stance") or s:find("grimoire") or s:find("dualcast") then
            return 5, "[CHOOSE THIS - TACTICIAN BiS]"
        end

    elseif role == "Corsair" then
        if s:find("gun") or s:find("rifle") or s:find("corsair") or s:find("quick draw") or s:find("crit") then
            return 5, "[CHOOSE THIS - CORSAIR BiS]"
        end
    end

    return 0, nil
end

-- Inspect whether row is currently equipped, and try to find WHO has it equipped
local function getRowEquippedInfo(tb, activeChar)
    local okPar, par = pcall(function() return tb:GetParent() end)
    if not (okPar and par and par:IsValid()) then return false, nil end

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
                        local isBadge = name:find("face") or name:find("chara") or name:find("unit") 
                                     or name:find("portrait") or name:find("head") or name:find("member")
                                     or name:find("icon_e") or name:find("badge") or name:find("equip")
                        if isBadge then
                            local owner = nil

                            -- Check texture / brush for character identifier
                            local okB, brush = pcall(function() return child.Brush end)
                            if okB and brush then
                                local okTex, tex = pcall(function() return brush.ResourceObject:GetName():lower() end)
                                if okTex and tex then
                                    if tex:find("rain") or tex:find("unit_01") or tex:find("chara_01") then owner = "Rain"
                                    elseif tex:find("lasswell") or tex:find("unit_02") or tex:find("chara_02") then owner = "Lasswell"
                                    elseif tex:find("dark") or tex:find("archwitch") then owner = "Archwitch Fina"
                                    elseif tex:find("fina") or tex:find("unit_03") or tex:find("chara_03") then owner = "Fina"
                                    elseif tex:find("lid") or tex:find("unit_04") or tex:find("chara_04") then owner = "Lid"
                                    elseif tex:find("nichol") or tex:find("unit_05") or tex:find("chara_05") then owner = "Nichol"
                                    elseif tex:find("jake") or tex:find("unit_06") or tex:find("chara_06") then owner = "Jake"
                                    elseif tex:find("sakura") or tex:find("unit_07") or tex:find("chara_07") then owner = "Sakura"
                                    end
                                end
                            end

                            -- Check badge text
                            if not owner then
                                local okTxt, cTxt = pcall(function() return child:GetText():ToString():lower() end)
                                if okTxt and cTxt and #cTxt > 0 then
                                    if cTxt:find("rain") then owner = "Rain"
                                    elseif cTxt:find("lasswell") then owner = "Lasswell"
                                    elseif cTxt:find("fina") then owner = "Fina"
                                    elseif cTxt:find("lid") then owner = "Lid"
                                    elseif cTxt:find("nichol") then owner = "Nichol"
                                    elseif cTxt:find("jake") then owner = "Jake"
                                    elseif cTxt:find("sakura") then owner = "Sakura"
                                    end
                                end
                            end

                            return true, owner
                        end
                    end
                end
            end
        end
    end

    -- Check outer properties
    local okOut, outer = pcall(function() return tb:GetOuter() end)
    if okOut and outer and outer:IsValid() then
        local okEq, isEq = pcall(function() return outer.bIsEquipped or outer.bEquipped end)
        if okEq and isEq == true then return true, activeChar end
        local okOth, isOth = pcall(function() return outer.bEquippedOther or outer.bIsEquippedOther end)
        if okOth and isOth == true then
            return true, nil
        end
    end

    return false, nil
end

-- Core Recommendation Evaluator:
-- 1. Must pertain specifically to the active character.
-- 2. Never overlaps with already equipped gear UNLESS it is a strictly bigger upgrade for the active character.
local function evaluateRecommendation(baseItem, activeChar, isEquipped, equippedOwner)
    local activeScore, activeTag = getItemData(baseItem, activeChar)

    -- Case 1: Incompatible or not a notable upgrade for active character
    if activeScore < 3 or not activeTag then
        return nil
    end

    -- Case 2: Unequipped (in inventory) -> Clean, direct recommendation!
    if not isEquipped then
        return STAR .. activeTag
    end

    -- Case 3: Already equipped on the active character in this slot -> Clean, no redundant spam
    if equippedOwner == activeChar then
        return nil
    end

    -- Case 4: Already equipped on another character
    -- Find other character's score
    local otherScore = 0
    if equippedOwner and equippedOwner ~= "" then
        otherScore = getItemData(baseItem, equippedOwner)
    else
        -- If specific owner isn't identified, baseline comparison score is 3
        otherScore = 3
    end

    -- User Rule: "dont let it overlap with already equipped unless its a bigger upgrade for one than the rest of the characters"
    if activeScore > otherScore then
        -- Active character gains a higher tier upgrade from this gear!
        local who = (equippedOwner and equippedOwner ~= "") and ("TAKE FROM " .. equippedOwner:upper()) or "BIGGER UPGRADE"
        return STAR .. string.format("[CHOOSE THIS - %s (+%d TIER)]", who, activeScore - otherScore)
    else
        -- Not a bigger upgrade; current owner needs it just as much or more.
        -- DO NOT OVERLAP!
        return nil
    end
end

local lastScanTime = 0

local printedWidgets = false

function M.tick()
    if not printedWidgets then
        printedWidgets = true
        pcall(function()
            local all = FindAllOf("UserWidget")
            local found = {}
            for _, w in ipairs(all or {}) do
                local n = w:GetClass():GetName()
                if n:find("Btl") or n:find("Party") or n:find("Gauge") or n:find("Unit") then
                    found[n] = (found[n] or 0) + 1
                end
            end
            print("=== LIVE WIDGETS FOUND IN GAME ===")
            local keys = {}
            for k in pairs(found) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                print(string.format("  [WIDGET] %s : %d", k, found[k]))
            end
        end)
    end
    local now = os.clock()
    if now - lastScanTime < 1.0 then return end
    lastScanTime = now

    pcall(function()
        -- Cutscene / Outworld Gate: Only scan when equipment / ability / vision / mastery UI widgets are active
        local inMenu = false
        local menuWidgets = {
            "WBP_UnitEquippedList_C",
            "WBP_UnitEquippedSkillList_C",
            "WBP_VisionList_C",
            "WBP_UnitSkillList_C",
            "WBP_UnitSkillTree_C",
            "WBP_UnitEnhance_C",
            "WBP_Mastery_C",
            "WBP_AbilityTree_C",
            "WBP_UnitList_C",
            "WBP_CharaMenu_C",
            "WBP_PartyMenu_C",
            "WBP_Equipment_C",
        }
        for _, mwName in ipairs(menuWidgets) do
            local mw = FindFirstOf(mwName)
            if mw and mw:IsValid() then
                inMenu = true
                break
            end
        end
        if not inMenu then
            -- Fallback: inspect UserWidgets on screen
            local allW = FindAllOf("UserWidget")
            for _, uw in ipairs(allW or {}) do
                local un = uw:GetClass():GetName()
                if (un:find("Equip") or un:find("Vision") or un:find("Skill") or un:find("Mastery") or un:find("Enhance"))
                   and not un:find("Btl") then
                    inMenu = true
                    break
                end
            end
        end
        if not inMenu then return end

        local allTBs = FindAllOf("TextBlock")
        if not allTBs or #allTBs == 0 then return end

        local activeChar = detectActiveCharacter(allTBs)

        for _, tb in ipairs(allTBs) do
            if tb and tb:IsValid() then
                local str = textOf(tb)
                if str and str ~= "" and #str < 75 then
                    local rawItem = clean(str)
                    local base = rawItem:lower():gsub("^%s+", ""):gsub("%s+$", "")
                    
                    local hasTag = str:lower():find("%[choose this") ~= nil
                    local isEquipped, equippedOwner = getRowEquippedInfo(tb, activeChar)

                    local recString = evaluateRecommendation(base, activeChar, isEquipped, equippedOwner)

                    if recString then
                        local want = rawItem .. " " .. recString
                        if str ~= want then
                            pcall(function() tb:SetText(FText(want)) end)
                        end
                    elseif hasTag then
                        -- Remove old or invalid tag
                        pcall(function() tb:SetText(FText(rawItem)) end)
                    end
                end
            end
        end
    end)
end

return M
