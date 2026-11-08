-- Complete Roster Equipment, Abilities & Mastery Recommender for Final Fantasy Resonance
-- Fully supports all 8 Playable Characters, all 26 Visions, all Gear Tiers & Mastery Nodes
-- Replaces clunky '[CHOOSE THIS]' tags with sleek, authentic JRPG badges: ★ [BiS], ▲ [Recommended], ▲ [Upgrade]
-- Intelligent Fuzzy Matching: Matches enhanced gear (+1, +2), variant names, and mastery trees
-- Intelligent Anti-Overlap: Prevents redundant gear conflict unless strictly a higher tier for active hero
-- 100% Game-Thread Safe: Crash-hardened, zero recursion, zero unsafe reflection

local M = {}

pcall(function()
    local ok, ph = pcall(dofile, "D:/SteamLibrary/steamapps/common/FINAL FANTASY RESONANCE/FFRS/Binaries/Win64/ue4ss/Mods/FFRAutoBattle/Scripts/party_hud.lua")
    if ok and ph and ph.tick then
        ph.tick()
    end
end)

local STAR = "\226\152\133 " -- ★
local UP_TRI = "\226\150\178 " -- ▲

-- Priority tiers:
-- 5 = Signature BiS / Role Defining
-- 4 = High Priority Recommended Upgrade
-- 3 = Solid Role Upgrade
-- 2 = Neutral / Generic Filler
-- 1 = Off-Role / Suboptimal
-- 0 = Incompatible

local CHAR_PROFILES = {
    ["Rain"] = {
        role = "Sentinel",
        roleTag = "Sentinel",
        gear = {
            -- Heavy Armor & Plate (Sentinel Tank EHP)
            ["blessed cuirass"]    = { score = 5, tag = "BiS: Tank" },
            ["iron armor"]         = { score = 3, tag = "Upgrade: DEF" },
            ["steel armor"]        = { score = 3, tag = "Upgrade: DEF" },
            ["mythril plate"]      = { score = 4, tag = "Recommended: Plate" },
            ["knight's armor"]     = { score = 4, tag = "Recommended: Plate" },
            ["gold armor"]         = { score = 4, tag = "Recommended: Plate" },
            ["diamond armor"]      = { score = 4, tag = "Recommended: Plate" },
            ["flame mail"]         = { score = 4, tag = "Resist: Fire" },
            ["ice armor"]          = { score = 4, tag = "Resist: Ice" },
            ["dragon mail"]        = { score = 5, tag = "BiS: Heavy Armor" },
            ["demon mail"]         = { score = 5, tag = "BiS: Heavy Armor" },
            ["genji armor"]        = { score = 5, tag = "BiS: Heavy Armor" },
            ["crystal armor"]      = { score = 5, tag = "BiS: Heavy Armor" },
            ["force armor"]        = { score = 5, tag = "BiS: Heavy Armor" },
            ["maximilian"]         = { score = 5, tag = "BiS: Heavy Armor" },
            ["phalanx"]            = { score = 5, tag = "BiS: Mitigation" },

            -- Tank Shields
            ["buckler"]            = { score = 3, tag = "Upgrade: Shield" },
            ["iron shield"]        = { score = 3, tag = "Upgrade: Shield" },
            ["mythril shield"]     = { score = 4, tag = "Recommended: Shield" },
            ["knight's shield"]    = { score = 4, tag = "Recommended: Shield" },
            ["flame shield"]       = { score = 4, tag = "Resist: Fire Shield" },
            ["ice shield"]         = { score = 4, tag = "Resist: Ice Shield" },
            ["aegis shield"]       = { score = 5, tag = "BiS: Aegis Shield" },
            ["genji shield"]       = { score = 5, tag = "BiS: Genji Shield" },

            -- Tank Accessories
            ["bulletproof vest"]   = { score = 5, tag = "BiS: Tank DEF" },
            ["earrings of health"] = { score = 4, tag = "Recommended: HP" },
            ["titan's bangle"]     = { score = 5, tag = "BiS: Tank HP" },
            ["muscle belt"]        = { score = 4, tag = "Recommended: HP" },
            ["barrier ring"]       = { score = 4, tag = "Recommended: M.DEF" },
            ["protect ring"]       = { score = 5, tag = "BiS: Auto-Protect" },
            ["safety bit"]         = { score = 5, tag = "BiS: Death Immune" },

            -- Greatswords & Weapons
            ["crimson saber"]      = { score = 4, tag = "Ch.1 BiS: Saber" },
            ["enhancer"]           = { score = 5, tag = "Ch.5 BiS: Hybrid Blade" },
            ["iron sword"]         = { score = 3, tag = "Upgrade: Sword" },
            ["broadsword"]         = { score = 3, tag = "Upgrade: Sword" },
            ["mythril blade"]      = { score = 3, tag = "Upgrade: Blade" },
            ["flametongue"]        = { score = 5, tag = "BiS: Fire Blade" },
            ["coral sword"]        = { score = 4, tag = "Recommended: Thunder" },
            ["buster sword"]       = { score = 4, tag = "Recommended: High ATK" },
            ["excalibur"]          = { score = 5, tag = "BiS: Holy Greatsword" },
            ["save the queen"]     = { score = 5, tag = "BiS: Tank Greatsword" },
            ["ragnarok"]           = { score = 5, tag = "BiS: Greatsword" },
            ["ultima weapon"]      = { score = 5, tag = "BiS: Ultimate Blade" },

            -- Visions
            ["warrior of light"]   = { score = 5, tag = "BiS: Tank Vision" },
            ["cecil"]              = { score = 5, tag = "BiS: Tank Vision" },
            ["wilhelm"]            = { score = 5, tag = "BiS: Pure Tank" },
            ["charlotte"]          = { score = 5, tag = "BiS: Sentinel Vision" },
            ["knight of grandshelt charlotte"] = { score = 5, tag = "BiS: Sentinel Vision" },
            ["golem"]              = { score = 5, tag = "BiS: Earth Shield" },
            ["titan"]              = { score = 4, tag = "Recommended: EHP" },
            ["alexander"]          = { score = 5, tag = "BiS: Holy Bastion" },
            ["camille"]            = { score = 4, tag = "Recommended: Break Tank" },
            ["firion"]             = { score = 4, tag = "Recommended: Counter Tank" },
            ["snow"]               = { score = 4, tag = "Recommended: Brawler Tank" },
            ["basch"]              = { score = 5, tag = "BiS: Vanguard" },
            ["cloud"]              = { score = 3, tag = "Upgrade: ATK/DEF" },

            -- Recommended Abilities & Mastered Sentinel Passives (Auto-Prioritized for Rain)
            ["sentinel"]           = { score = 5, tag = "BiS: Sentinel Trait" },
            ["sentinel guard"]     = { score = 5, tag = "BiS: Guard Stance" },
            ["sentinel's guard"]   = { score = 5, tag = "BiS: Guard Stance" },
            ["multi cover"]        = { score = 5, tag = "BiS: Team Cover" },
            ["multi-cover"]        = { score = 5, tag = "BiS: Team Cover" },
            ["arms akimbo"]        = { score = 5, tag = "BiS: Dual Shield" },
            ["double action"]      = { score = 4, tag = "Recommended: Action" },
            ["half mp"]            = { score = 4, tag = "Recommended: Half MP" },
            ["physical counter"]   = { score = 5, tag = "BiS: Counter Stagger" },
            ["magic counter"]      = { score = 5, tag = "BiS: Counter Stagger" },
            ["counter burst"]      = { score = 4, tag = "Recommended: Counter" },
            ["phalanx"]            = { score = 5, tag = "BiS: Mitigation" },
            ["phalanx stance"]     = { score = 5, tag = "BiS: Mitigation" },
            ["iron wall"]          = { score = 5, tag = "BiS: DEF +30%" },
            ["royal guard"]        = { score = 5, tag = "BiS: DEF +30%" },
            ["shield wall"]        = { score = 5, tag = "BiS: Party Guard" },
            ["stance mastery"]     = { score = 5, tag = "BiS: Fast Stance" },
            ["break mastery"]      = { score = 5, tag = "BiS: Break Resist" },
            ["hp +30%"]            = { score = 5, tag = "BiS: EHP Boost" },
            ["hp +20%"]            = { score = 4, tag = "Recommended: HP" },
            ["hp +10%"]            = { score = 3, tag = "Upgrade: HP" },
            ["def +30%"]           = { score = 5, tag = "BiS: DEF Boost" },
            ["def +20%"]           = { score = 4, tag = "Recommended: DEF" },
            ["def +10%"]           = { score = 3, tag = "Upgrade: DEF" },
            ["auto-protect"]       = { score = 5, tag = "BiS: Auto-Protect" },
            ["auto-barrier"]       = { score = 5, tag = "BiS: Auto-Barrier" },
            ["undying will"]       = { score = 5, tag = "BiS: Survive Lethal" },
            ["guts"]               = { score = 5, tag = "BiS: Survive Lethal" },
            ["last stand"]         = { score = 5, tag = "BiS: Survive Lethal" },
            ["draw attacks"]       = { score = 5, tag = "BiS: Aggro Lock" },
            ["taunt"]              = { score = 5, tag = "BiS: Aggro Lock" },
            ["vanguard roar"]      = { score = 5, tag = "BiS: Aggro Roar" },
            ["firaga blade"]       = { score = 4, tag = "Recommended: Fire Break" },
            ["tackle"]             = { score = 5, tag = "BiS: Stagger Interrupt" },
            ["provoke"]            = { score = 5, tag = "BiS: Tank Provoke" },
        }
    },

    ["Lasswell"] = {
        role = "Breaker",
        roleTag = "Breaker",
        gear = {
            ["shiden"]             = { score = 4, tag = "Recommended: Katana" },
            ["kotetsu"]            = { score = 3, tag = "Upgrade: Katana" },
            ["kazekiri"]           = { score = 4, tag = "Recommended: Wind Blade" },
            ["osafune"]            = { score = 3, tag = "Upgrade: Katana" },
            ["murasame"]           = { score = 5, tag = "BiS: Crit Katana" },
            ["kiku-ichimonji"]     = { score = 4, tag = "Recommended: High ATK" },
            ["icebrand"]           = { score = 5, tag = "BiS: Ice Blade" },
            ["ashura"]             = { score = 4, tag = "Recommended: Katana" },
            ["zanmato"]            = { score = 4, tag = "Recommended: High ATK" },
            ["masamune"]           = { score = 5, tag = "BiS: Legendary Blade" },
            ["muramasa"]           = { score = 5, tag = "BiS: Demon Katana" },
            ["chirijiraden"]       = { score = 5, tag = "Ch.7 BiS: Fire Katana" },
            ["genji glove"]        = { score = 5, tag = "Ch.6 BiS: Dual-Wield" },
            ["celestial glove"]    = { score = 5, tag = "Ch.7 BiS: All Stats +30" },
            ["hero ring"]          = { score = 5, tag = "Ch.2 BiS: ATK/MAG+10%" },
            ["black cowl"]         = { score = 5, tag = "Ch.7 BiS: ATK Headgear" },
            ["tiger mask"]         = { score = 4, tag = "Ch.4 BiS: ATK Mask" },
            ["brave suit"]         = { score = 5, tag = "Ch.6 BiS: ATK Body Armor" },

            ["leather armor"]      = { score = 2, tag = "Basic: Armor" },
            ["kenpogi"]            = { score = 3, tag = "Upgrade: ATK" },
            ["black gi"]           = { score = 4, tag = "Recommended: ATK Gi" },
            ["ninja garb"]         = { score = 4, tag = "Recommended: Speed Garb" },
            ["shinobi gear"]       = { score = 5, tag = "BiS: Crit Garb" },

            ["wristband"]          = { score = 2, tag = "Basic: Wrist" },
            ["hyper wrist"]        = { score = 5, tag = "BiS: ATK+30" },
            ["hero's ring"]        = { score = 5, tag = "BiS: ATK/MAG+10%" },
            ["critical ring"]      = { score = 5, tag = "BiS: Crit Rate" },
            ["black belt"]         = { score = 4, tag = "Recommended: Counter" },
            ["hermes sandals"]     = { score = 4, tag = "Recommended: Auto-Haste" },

            ["cloud"]              = { score = 5, tag = "BiS: Crit & Stagger" },
            ["sephiroth"]          = { score = 5, tag = "BiS: Dark Katana" },
            ["tidus"]              = { score = 5, tag = "BiS: Speed & Crit" },
            ["squall"]             = { score = 4, tag = "Recommended: Stagger" },
            ["noctis"]             = { score = 5, tag = "BiS: Armiger" },
            ["chocobo"]            = { score = 3, tag = "Upgrade: Speed" },

            ["null moon"]          = { score = 5, tag = "BiS: Guaranteed Crit" },
            ["dawn frost"]         = { score = 5, tag = "BiS: Stagger 27" },
            ["blade mastery"]      = { score = 5, tag = "BiS: Katana ATK+50%" },
            ["katana mastery"]     = { score = 5, tag = "BiS: Katana ATK+50%" },
            ["ice mastery"]        = { score = 5, tag = "BiS: Ice Dmg+50%" },
            ["crit rate +15%"]     = { score = 5, tag = "BiS: Crit Rate" },
            ["crit rate +10%"]     = { score = 4, tag = "Recommended: Crit" },
            ["crit rate +5%"]      = { score = 3, tag = "Upgrade: Crit" },
            ["scan & strike"]      = { score = 5, tag = "BiS: Weakness Piercing" },
            ["rearguard"]          = { score = 5, tag = "BiS: Back Attack Crit" },
            ["cloud soul"]         = { score = 5, tag = "BiS: High Morale Atk" },
            ["stagger surge"]      = { score = 5, tag = "BiS: Stagger Finish" },
            ["cross-slash"]        = { score = 4, tag = "Recommended: Cross-Slash" },
            ["blizzaga blade"]     = { score = 4, tag = "Recommended: Ice Blade" },
            ["barrage"]            = { score = 4, tag = "Recommended: 4-Hit Barrage" },
        }
    },

    ["Fina"] = {
        role = "Luminary",
        roleTag = "Luminary",
        gear = {
            ["wooden staff"]       = { score = 2, tag = "Basic: Staff" },
            ["staff of healing"]   = { score = 4, tag = "Recommended: Heal Staff" },
            ["staff of wrath"]     = { score = 4, tag = "Ch.2 BiS: Colosseum Staff" },
            ["rune staff"]         = { score = 4, tag = "Ch.3 BiS: SPR Staff" },
            ["golden staff"]       = { score = 4, tag = "Ch.4 BiS: SPR Staff" },
            ["holy wand"]          = { score = 5, tag = "Ch.5 BiS: Dualcast Wand" },
            ["nirvana"]            = { score = 5, tag = "Ch.7 BiS: Ultimate Staff" },

            ["cotton robe"]        = { score = 2, tag = "Basic: Robe" },
            ["silk robe"]          = { score = 3, tag = "Upgrade: Robe" },
            ["sage's robe"]        = { score = 4, tag = "Recommended: Sage Robe" },
            ["white robe"]         = { score = 5, tag = "BiS: SPR Robe" },
            ["robe of lords"]      = { score = 5, tag = "BiS: Endgame Robe" },
            ["minerva bustier"]    = { score = 5, tag = "Ch.5 BiS: Elem Resist Robe" },
            ["rainbow robe"]       = { score = 5, tag = "Ch.7 BiS: Ultimate Robe" },

            ["silver glasses"]     = { score = 2, tag = "Basic: Accessory" },
            ["angel ring"]         = { score = 4, tag = "Recommended: Auto-Regen" },
            ["angel earrings"]     = { score = 4, tag = "Ch.2 BiS: Auto-Regen" },
            ["star pendant"]       = { score = 3, tag = "Ch.1 BiS: Poison Immune" },
            ["fairy ring"]         = { score = 4, tag = "Ch.3 BiS: Status Immune" },
            ["rosary"]             = { score = 4, tag = "Recommended: SPR+" },
            ["ribbon"]             = { score = 5, tag = "BiS: Status Immune" },
            ["soul ring"]          = { score = 4, tag = "Recommended: MP/SPR" },

            ["leah"]               = { score = 3, tag = "Early: Healer" },
            ["ayaka"]              = { score = 5, tag = "BiS: Pure Healing" },
            ["folka"]              = { score = 5, tag = "BiS: Status Shield" },
            ["aerith"]             = { score = 5, tag = "BiS: Full Revival" },
            ["garnet"]             = { score = 4, tag = "Recommended: Summon" },
            ["lenna"]              = { score = 4, tag = "Recommended: Pure Healer" },

            ["curaja"]             = { score = 5, tag = "BiS: Full Party Heal" },
            ["curaga"]             = { score = 4, tag = "Recommended: Curaga" },
            ["arise"]              = { score = 5, tag = "BiS: 100% HP Revive" },
            ["raise"]              = { score = 3, tag = "Upgrade: Revive" },
            ["dualcast"]           = { score = 5, tag = "BiS: Dual White Magic" },
            ["white magic mastery"]= { score = 5, tag = "BiS: Heal Potency+50%" },
            ["radiant restoration"]= { score = 5, tag = "BiS: Instant Cleanse" },
            ["lb triple charge"]   = { score = 5, tag = "BiS: Fast LB Meter" },
            ["auto-regen"]         = { score = 4, tag = "Recommended: Auto-Regen" },
            ["cheer"]              = { score = 4, tag = "Recommended: Party ATK" },
            ["haste"]              = { score = 4, tag = "Recommended: Haste" },
        }
    },

    ["Lid"] = {
        role = "Mechanist",
        roleTag = "Mechanist",
        gear = {
            ["heavy wrench"]       = { score = 4, tag = "Recommended: Wrench" },
            ["hammer"]             = { score = 3, tag = "Upgrade: Hammer" },
            ["thor's hammer"]      = { score = 5, tag = "BiS: Thunder Hammer" },
            ["battle hammer"]      = { score = 4, tag = "Ch.4 BiS: Heavy Hammer" },
            ["mighty hammer"]      = { score = 4, tag = "Ch.6 BiS: Hammer" },
            ["gigantaxe"]          = { score = 5, tag = "Ch.7 BiS: Grand Axe" },
            ["t.r.n.d."]           = { score = 5, tag = "BiS: Signature Gun" },

            ["leather vest"]       = { score = 2, tag = "Basic: Vest" },
            ["miner's gear"]       = { score = 3, tag = "Upgrade: Gear" },
            ["engineer's suit"]    = { score = 4, tag = "Recommended: Suit" },
            ["machinist's jacket"] = { score = 5, tag = "BiS: Break Jacket" },
            ["mechanic overalls"]  = { score = 3, tag = "Ch.4 BiS: Overalls" },
            ["power vest"]         = { score = 4, tag = "Ch.6 BiS: ATK Vest" },
            ["grand armor"]        = { score = 5, tag = "Ch.7 BiS: Grand Armor" },

            ["goggles"]            = { score = 2, tag = "Basic: Goggles" },
            ["speed belt"]         = { score = 4, tag = "Recommended: Speed" },
            ["hermes boots"]       = { score = 5, tag = "BiS: Turn Priority" },
            ["thief's bracer"]     = { score = 5, tag = "BiS: 100% Steal Rate" },
            ["champion's belt"]    = { score = 5, tag = "Ch.6 BiS: ATK/DEF+20%" },
            ["titan's bangle"]     = { score = 4, tag = "Ch.4 BiS: HP Bangle" },
            ["muscle belt"]        = { score = 4, tag = "Ch.4 BiS: HP Belt" },

            ["edgar"]              = { score = 5, tag = "BiS: Tools Master" },
            ["cid"]                = { score = 5, tag = "BiS: Machine Power" },
            ["rikku"]              = { score = 5, tag = "BiS: Al Bhed Tech" },
            ["prompto"]            = { score = 4, tag = "Recommended: Trigger" },

            ["break mastery"]      = { score = 5, tag = "BiS: Break Speed" },
            ["armor break"]        = { score = 5, tag = "BiS: -40% Enemy DEF" },
            ["mental break"]       = { score = 5, tag = "BiS: -40% Enemy SPR" },
            ["weapon break"]       = { score = 5, tag = "BiS: -40% Enemy ATK" },
            ["march of the machines"] = { score = 5, tag = "BiS: Stagger AoE" },
            ["speed +15%"]         = { score = 5, tag = "BiS: Speed Boost" },
            ["steal"]              = { score = 4, tag = "Recommended: Loot" },
            ["mug"]                = { score = 4, tag = "Recommended: Attack+Loot" },
        }
    },

    ["Nichol"] = {
        role = "Tactician",
        roleTag = "Tactician",
        gear = {
            ["tome of secrets"]    = { score = 4, tag = "Recommended: Grimoire" },
            ["scholarly book"]     = { score = 5, tag = "BiS: Grimoire" },
            ["scholar's book"]    = { score = 4, tag = "Ch.5 BiS: Scholar Book" },
            ["platinum staff"]     = { score = 5, tag = "Ch.5 BiS: High SPR Staff" },
            ["scholar's robe"]    = { score = 4, tag = "Ch.5 BiS: Scholar Robe" },
            ["siren's robe"]      = { score = 5, tag = "Ch.7 BiS: Water/Dark Robe" },
            ["hermes sandals"]     = { score = 5, tag = "Ch.5 BiS: Auto-Haste" },
            ["sprint shoes"]       = { score = 4, tag = "Ch.5 BiS: Turn Speed" },
            ["barrier ring"]       = { score = 4, tag = "Ch.5 BiS: M.DEF" },
            ["victoria"]           = { score = 5, tag = "Ch.5 BiS: Buff Duration" },
            ["aileen"]             = { score = 5, tag = "Ch.5 BiS: Turn Order" },
            ["tactician's robe"]   = { score = 5, tag = "BiS: Tactician Robe" },
            ["strategist's glasses"]= { score = 5, tag = "BiS: MP Regen" },
            ["hope"]               = { score = 5, tag = "BiS: Synergist" },
            ["alphinaud"]          = { score = 5, tag = "BiS: Scholar" },
            ["tactician stance"]   = { score = 5, tag = "BiS: Team Boost" },
            ["shellga"]            = { score = 4, tag = "Recommended: M.Shield" },
            ["protectga"]          = { score = 4, tag = "Recommended: P.Shield" },
        }
    },

    ["Sakura"] = {
        role = "Sage",
        roleTag = "Sage",
        gear = {
            ["thunder rod"]        = { score = 4, tag = "Recommended: Rod" },
            ["storm wand"]         = { score = 5, tag = "BiS: Thunder Wand" },
            ["wizard's rod"]      = { score = 4, tag = "Ch.5 BiS: High MAG Rod" },
            ["stardust rod"]       = { score = 5, tag = "Ch.6 BiS: Astral Rod" },
            ["omnirod"]            = { score = 5, tag = "Ch.7 BiS: Ultimate Rod" },
            ["black robe"]         = { score = 4, tag = "Ch.5 BiS: MAG Robe" },
            ["lordly robe"]        = { score = 5, tag = "Ch.7 BiS: MAG/SPR Robe" },
            ["hero ring"]          = { score = 4, tag = "Ch.5 BiS: MAG+10%" },
            ["hero's ring"]       = { score = 4, tag = "Ch.5 BiS: MAG+10%" },
            ["magistral crest"]    = { score = 5, tag = "Ch.7 BiS: MAG/SPR+30%" },
            ["terra"]              = { score = 5, tag = "Ch.5 BiS: Magic Scaling" },
            ["clive"]              = { score = 5, tag = "Ch.5 BiS: Fire/Lightning" },
            ["magician's robe"]    = { score = 4, tag = "Recommended: Robe" },
            ["celestial robe"]     = { score = 5, tag = "BiS: MAG Robe" },
            ["earrings"]           = { score = 4, tag = "Recommended: MAG+" },
            ["mage's armlet"]      = { score = 5, tag = "BiS: MAG+20%" },
            ["vivi"]               = { score = 5, tag = "BiS: Black Magic" },
            ["ramuh"]              = { score = 5, tag = "BiS: Lightning" },
            ["thunder mastery"]    = { score = 5, tag = "BiS: Thunder+50%" },
            ["rebel thunder"]      = { score = 5, tag = "BiS: Signature Nuke" },
            ["dualcast"]           = { score = 5, tag = "BiS: Double Spell" },
        }
    },

    ["Jake"] = {
        role = "Corsair",
        roleTag = "Corsair",
        gear = {
            ["revolver"]           = { score = 4, tag = "Recommended: Gun" },
            ["sniper rifle"]       = { score = 5, tag = "BiS: Rifle" },
            ["silver rifle"]       = { score = 3, tag = "Ch.6 BiS: Sniper Rifle" },
            ["mythril gun"]        = { score = 4, tag = "Ch.6 BiS: Gun" },
            ["quicksilver"]        = { score = 5, tag = "Ch.7 BiS: Sniper Rifle" },
            ["romandan pistol"]    = { score = 5, tag = "Ch.7 BiS: Dual Handgun" },
            ["corsair coat"]       = { score = 4, tag = "Ch.6 BiS: Corsair Coat" },
            ["brave suit"]         = { score = 5, tag = "Ch.7 BiS: Crit Body Armor" },
            ["desch's earring"]   = { score = 5, tag = "Ch.7 BiS: ATK+45" },
            ["hyper wrist"]        = { score = 4, tag = "Ch.6 BiS: ATK+30" },
            ["amelia"]             = { score = 5, tag = "Ch.6 BiS: Gun Mastery" },
            ["corsair jacket"]     = { score = 5, tag = "BiS: Crit Jacket" },
            ["bandana"]            = { score = 4, tag = "Recommended: Crit" },
            ["vincent"]            = { score = 5, tag = "BiS: Gunner" },
            ["balthier"]           = { score = 5, tag = "BiS: Leading Man" },
            ["quick draw"]         = { score = 5, tag = "BiS: Pre-emptive" },
        }
    },

    ["Archwitch Fina"] = {
        role = "Saboteur",
        roleTag = "Saboteur",
        gear = {
            ["demon rod"]          = { score = 5, tag = "BiS: Dark Rod" },
            ["demon's rod"]       = { score = 5, tag = "Ch.6 BiS: Demon Rod" },
            ["lilith rod"]         = { score = 4, tag = "Ch.5 BiS: Dark Rod" },
            ["stardust rod"]       = { score = 5, tag = "Ch.6 BiS: Astral Rod" },
            ["omnirod"]            = { score = 5, tag = "Ch.7 BiS: Ultimate Rod" },
            ["black robe"]         = { score = 4, tag = "Ch.5 BiS: Robe" },
            ["lordly robe"]        = { score = 5, tag = "Ch.7 BiS: Endgame Robe" },
            ["siren's robe"]      = { score = 5, tag = "Ch.7 BiS: Water/Dark Robe" },
            ["earrings"]           = { score = 4, tag = "Ch.5 BiS: MAG+20%" },
            ["magistral crest"]    = { score = 5, tag = "Ch.7 BiS: MAG+30%" },
            ["colossal shantotto"] = { score = 5, tag = "Ch.5 BiS: Ancient Magic" },
            ["dark robe"]          = { score = 5, tag = "BiS: Dark Robe" },
            ["skull ring"]         = { score = 4, tag = "Recommended: MAG" },
            ["diabolos"]           = { score = 5, tag = "BiS: Dark Esper" },
            ["dystopia"]           = { score = 5, tag = "BiS: Dark Nuke" },
            ["dual black magic"]   = { score = 5, tag = "BiS: Dual Cast" },
        }
    }
}

-- Strip old tags, new tags, symbols, and extra whitespace
local function clean(s)
    if not s or s == "" then return "" end
    s = s:gsub("%s*★%s*%[.-%]", "")
    s = s:gsub("%s*▲%s*%[.-%]", "")
    s = s:gsub("%s*%[CHOOSE THIS.-%]", "")
    s = s:gsub("%s*%[choose this.-%]", "")
    s = s:gsub("%s*%[BiS.-%]", "")
    s = s:gsub("%s*%[Recommended.-%]", "")
    s = s:gsub("%s*%[Upgrade.-%]", "")
    s = s:gsub("%s*%[Best on.-%]", "")
    s = s:gsub("%s*%[Resist.-%]", "")
    s = s:gsub("^[★▲%s*]+", ""):gsub("[★▲%s*]+$", "")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Fuzzy normalizer: strips +1/+2, roman numerals (I, II, III), and suffixes like (Mastery)
local function normalizeItemName(s)
    if not s then return "" end
    local base = clean(s):lower()
    base = base:gsub("%s*%+%d+", "")
    base = base:gsub("%s+[ivx]+$", "")
    base = base:gsub("%s*%(.-%)", "")
    return base:gsub("^%s+", ""):gsub("%s+$", "")
end

local function textOf(tb)
    if not (tb and tb:IsValid()) then return nil end
    local ok, txt = pcall(function() return tb:GetText():ToString() end)
    if ok and txt and #txt > 0 then return txt end
    return nil
end

local lastConfirmedChar = "Rain"

-- Detects active character accurately across all menu types
local function detectActiveCharacter(allTextBlocks)
    -- Check for explicit role names
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

    -- Check for character name in header or status blocks
    for _, tb in ipairs(allTextBlocks) do
        local str = textOf(tb)
        if str and #str < 25 then
            local t = str:gsub("^%s+", ""):gsub("%s+$", "")
            if t == "Rain" then lastConfirmedChar = "Rain"; return "Rain" end
            if t == "Lasswell" then lastConfirmedChar = "Lasswell"; return "Lasswell" end
            if t == "Fina" then lastConfirmedChar = "Fina"; return "Fina" end
            if t == "Lid" then lastConfirmedChar = "Lid"; return "Lid" end
            if t == "Nichol" then lastConfirmedChar = "Nichol"; return "Nichol" end
            if t == "Sakura" then lastConfirmedChar = "Sakura"; return "Sakura" end
            if t == "Jake" then lastConfirmedChar = "Jake"; return "Jake" end
        end
    end

    return lastConfirmedChar or "Rain"
end

-- Deep Archetype Recommender: Evaluates gear, visions, and mastery nodes
local function getItemData(rawItemBase, charName)
    local prof = CHAR_PROFILES[charName]
    if not prof then return 0, nil end

    local norm = normalizeItemName(rawItemBase)

    -- 1. Exact or normalized table lookup
    if prof.gear then
        local noApos = norm:gsub("'", ""):gsub("%-", " ")
        local entry = prof.gear[rawItemBase] or prof.gear[norm] or prof.gear[noApos]
        if entry then
            return entry.score or 0, entry.tag
        end
        for k, v in pairs(prof.gear) do
            local cleanK = k:gsub("'", ""):gsub("%-", " ")
            if cleanK == noApos or cleanK == norm then
                return v.score or 0, v.tag
            end
        end
    end

    -- 2. Dynamic Archetype Pattern Matching
    local s = norm:lower()
    local role = prof.role or ""

    if role == "Sentinel" then
        -- Rain / Tank: ALL Equipment Slots (Main Hand, Off-Hand, Headgear, Body Armor, Accessories, Visions, Masteries)
        -- 1. Essential Passives & Command Arts
        if s:find("sentinel") or s:find("cover") or s:find("provoke") or s:find("taunt")
           or s:find("phalanx") or s:find("iron wall") or s:find("royal guard") or s:find("shield wall")
           or s:find("undying") or s:find("guts") or s:find("last stand") or s:find("draw attacks")
           or s:find("arms akimbo") or s:find("counter") or s:find("barrier") then
            return 5, "BiS: Sentinel"

        -- 2. Heavy Headgear (Helmets, Great Helms)
        elseif s:find("helm") or s:find("helmet") or s:find("grand helm") or s:find("genji helm")
           or s:find("dragon helm") or s:find("iron helm") or s:find("mythril helm") or s:find("heavy helm") then
            return 5, "BiS: Helm"

        -- 3. Heavy Body Armor & Plate (Max EHP)
        elseif s:find("cuirass") or s:find("maximilian") or s:find("genji armor") or s:find("crystal armor")
           or s:find("force armor") or s:find("dragon mail") or s:find("demon mail") then
            return 5, "BiS: Heavy Armor"
        elseif s:find("plate") or s:find("mail") or s:find("heavy") or s:find("armor") then
            return 4, "Recommended: Armor"

        -- 4. Tank Shields (Off-Hand)
        elseif s:find("aegis shield") or s:find("genji shield") or s:find("force shield") then
            return 5, "BiS: Shield"
        elseif s:find("shield") or s:find("buckler") or s:find("escutcheon") then
            return 4, "Recommended: Shield"

        -- 5. Tank Accessories (DEF, HP, Mitigation)
        elseif s:find("titan's bangle") or s:find("bulletproof vest") or s:find("safety bit") or s:find("protect ring") then
            return 5, "BiS: Tank Acc"
        elseif s:find("bangle") or s:find("muscle belt") or s:find("barrier ring") or s:find("earring") or s:find("hp %+%d+") or s:find("def %+%d+") then
            return 4, "Recommended: Tank Acc"

        -- 6. Tank Visions & Espers
        elseif s:find("wilhelm") or s:find("cecil") or s:find("charlotte") or s:find("warrior of light")
           or s:find("golem") or s:find("titan") or s:find("alexander") or s:find("basch") or s:find("snow") then
            return 5, "BiS: Tank Vision"

        -- 7. Weapons (Greatswords, Sabers, Heavy Blades)
        elseif s:find("flametongue") or s:find("excalibur") or s:find("ragnarok") or s:find("ultima weapon") or s:find("save the queen") then
            return 5, "BiS: Greatsword"
        elseif s:find("greatsword") or s:find("broadsword") or s:find("saber") or s:find("sword") or s:find("blade") then
            return 4, "Recommended: Blade"
        end

    elseif role == "Breaker" then
        -- Lasswell / Physical DPS: ALL Equipment Slots
        -- 1. Passives & Signature Skills
        if s:find("null moon") or s:find("dawn frost") or s:find("blade mastery") or s:find("katana mastery")
           or s:find("crit rate") or s:find("scan & strike") or s:find("rearguard") or s:find("cloud soul")
           or s:find("stagger surge") or s:find("dual%-wield") or s:find("chirijiraden") or s:find("masamune") or s:find("murasame") then
            return 5, "BiS: Breaker"

        -- 2. DPS Headgear (Masks, Cowls, Headbands)
        elseif s:find("tiger mask") or s:find("black cowl") or s:find("shinobi headband") or s:find("ninja cap") or s:find("mask") or s:find("cowl") or s:find("bandana") then
            return 5, "BiS: Mask"

        -- 3. Light Armor & Ninja Gear
        elseif s:find("shinobi gear") or s:find("ninja garb") or s:find("black gi") then
            return 5, "BiS: Light Armor"
        elseif s:find("gi") or s:find("garb") or s:find("kenpogi") or s:find("leather armor") then
            return 4, "Recommended: Armor"

        -- 4. Katanas & Blades
        elseif s:find("icebrand") or s:find("muramasa") or s:find("shiden") or s:find("zanmato") then
            return 5, "BiS: Katana"
        elseif s:find("katana") or s:find("blade") or s:find("cross") or s:find("slash") then
            return 4, "Recommended: Katana"

        -- 5. Crit & ATK Accessories
        elseif s:find("hyper wrist") or s:find("hero's ring") or s:find("critical ring") or s:find("hermes sandals") then
            return 5, "BiS: Crit Acc"
        elseif s:find("wrist") or s:find("belt") or s:find("atk %+%d+") or s:find("speed %+%d+") then
            return 4, "Recommended: DPS Acc"

        -- 6. Visions
        elseif s:find("cloud") or s:find("sephiroth") or s:find("tidus") or s:find("noctis") or s:find("squall") then
            return 5, "BiS: DPS Vision"
        end

    elseif role == "Luminary" then
        -- Fina / Healers: ALL Equipment Slots
        -- 1. Passives & Signature Heals
        if s:find("curaja") or s:find("curaga") or s:find("arise") or s:find("dualcast")
           or s:find("white magic mastery") or s:find("lb triple charge") or s:find("auto%-regen")
           or s:find("spr %+%d+") or s:find("spirit %+%d+") or s:find("nirvana") or s:find("holy wand") then
            return 5, "BiS: Luminary"

        -- 2. Healer Headgear (Circlets, Hairpins, Brims, Crowns)
        elseif s:find("circlet") or s:find("hairpin") or s:find("white brim") or s:find("crown") or s:find("tiara") or s:find("priest's hat") or s:find("sage's hat") then
            return 5, "BiS: Circlet"

        -- 3. Robes & Gowns
        elseif s:find("robe of lords") or s:find("white robe") or s:find("sage's robe") then
            return 5, "BiS: White Robe"
        elseif s:find("robe") or s:find("gown") or s:find("vestment") then
            return 4, "Recommended: Robe"

        -- 4. Staves & Wands
        elseif s:find("staff of healing") or s:find("staff") or s:find("wand") or s:find("cane") then
            return 4, "Recommended: Staff"

        -- 5. SPR & Status Accessories
        elseif s:find("ribbon") or s:find("rosary") or s:find("angel ring") or s:find("soul ring") then
            return 5, "BiS: Healer Acc"
        elseif s:find("ring") or s:find("pendant") or s:find("amulet") then
            return 4, "Recommended: Acc"

        -- 6. Visions
        elseif s:find("ayaka") or s:find("folka") or s:find("aerith") or s:find("garnet") or s:find("lenna") then
            return 5, "BiS: Healer Vision"
        end

    elseif role == "Mechanist" then
        -- Lid: ALL Equipment Slots
        -- 1. Passives & Debuffs
        if s:find("break mastery") or s:find("armor break") or s:find("mental break") or s:find("weapon break")
           or s:find("t%.r%.n%.d") or s:find("march of the machines") or s:find("speed %+%d+") or s:find("thief") then
            return 5, "BiS: Mechanist"

        -- 2. Headgear (Goggles, Visors, Safety Caps)
        elseif s:find("goggles") or s:find("visor") or s:find("safety hat") or s:find("mechanic cap") or s:find("miner's cap") then
            return 5, "BiS: Goggles"

        -- 3. Machinist Armor & Vests
        elseif s:find("machinist's jacket") or s:find("engineer's suit") then
            return 5, "BiS: Tech Armor"
        elseif s:find("jacket") or s:find("vest") or s:find("suit") or s:find("overalls") then
            return 4, "Recommended: Armor"

        -- 4. Wrenches & Hammers
        elseif s:find("thor's hammer") or s:find("heavy wrench") or s:find("wrench") or s:find("hammer") then
            return 5, "BiS: Tool"

        -- 5. Speed & Steal Accessories
        elseif s:find("thief's bracer") or s:find("hermes boots") or s:find("speed belt") then
            return 5, "BiS: Steal/Speed"

        -- 6. Visions
        elseif s:find("edgar") or s:find("cid") or s:find("rikku") or s:find("prompto") then
            return 5, "BiS: Tech Vision"
        end

    elseif role == "Saboteur" then
        if s:find("dystopia") or s:find("dual black magic") or s:find("dualcast") or s:find("mag %+%d+") or s:find("dark") then
            return 5, "BiS: Saboteur"
        end

    elseif role == "Sage" then
        if s:find("sage") or s:find("thunder mastery") or s:find("rebel thunder") or s:find("dualcast") or s:find("mag %+%d+") then
            return 5, "BiS: Sage"
        end

    elseif role == "Tactician" then
        if s:find("tactician") or s:find("stance") or s:find("grimoire") or s:find("dualcast") then
            return 5, "BiS: Tactician"
        end

    elseif role == "Corsair" then
        if s:find("gun") or s:find("rifle") or s:find("corsair") or s:find("quick draw") or s:find("crit") then
            return 5, "BiS: Corsair"
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
-- Formats sleek, clean badges:
-- Score 5: ★ [BiS: Sentinel]
-- Score 4: ▲ [Recommended]
-- Score 3: ▲ [Upgrade]
-- Overlap upgrade: ★ [Best on Rain]
local function evaluateRecommendation(baseItem, activeChar, isEquipped, equippedOwner)
    local activeScore, activeTag = getItemData(baseItem, activeChar)

    if activeScore < 3 or not activeTag then
        return nil
    end

    -- Already equipped on this character: do not clutter
    if isEquipped and equippedOwner == activeChar then
        return nil
    end

    -- Equipped on another party member: only recommend if strictly higher tier
    if isEquipped and equippedOwner and equippedOwner ~= activeChar then
        local otherScore = getItemData(baseItem, equippedOwner)
        if activeScore > otherScore then
            return STAR .. string.format("[Best on %s]", activeChar)
        else
            return nil
        end
    end

    -- In inventory or unequipped
    if activeScore >= 5 then
        return STAR .. string.format("[%s]", activeTag)
    elseif activeScore == 4 then
        return UP_TRI .. string.format("[%s]", activeTag)
    else
        return UP_TRI .. string.format("[%s]", activeTag)
    end
end

-- Number of accessory slots a hero has (Equip 4 Accessories mod = 4, vanilla = 2).
local ACC_SLOTS = 4

-- Is this item an accessory? Decided by name keywords or by a known accessory badge tag.
local ACC_WORDS = {
    "ring", "bangle", "belt", "earring", "ribbon", "rosary", "pendant", "amulet",
    "bracer", "boots", "sandals", "wrist", "vest", "safety bit", "glasses", "charm",
    "talisman", "brooch", "choker", "anklet", "gauntlet",
}
local function isAccessoryItem(base, tag)
    if tag and (tag:find("Acc") or tag:find("Auto%-Protect") or tag:find("Death Immune")
        or tag:find("Tank DEF") or tag:find("Tank HP") or tag:find("Steal/Speed")) then
        return true
    end
    local b = normalizeItemName(base):lower()
    for _, w in ipairs(ACC_WORDS) do
        if b:find(w, 1, true) then return true end
    end
    return false
end

local lastScanTime = 0

function M.tick()
    local now = os.clock()
    if now - lastScanTime < 1.0 then return end
    lastScanTime = now

    pcall(function()
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
        -- Overworld Fast Path: if no menu widget is open, exit immediately (zero overworld lag)
        if not inMenu then return end

        local allTBs = FindAllOf("TextBlock")
        if not allTBs or #allTBs == 0 then return end

        local activeChar = detectActiveCharacter(allTBs)

        -- Pass 1: classify every row. Accessories are ranked together so that only the
        -- best ACC_SLOTS items are badged (equipped ones count toward the slot total).
        local rows = {}
        local equippedAccScores = {}
        local seenEquipped = {}
        local candidates = {}
        local seenCand = {}

        for _, tb in ipairs(allTBs) do
            if tb and tb:IsValid() then
                local str = textOf(tb)
                if str and str ~= "" and #str < 75 then
                    local rawItem = clean(str)
                    local base = rawItem:lower():gsub("^%s+", ""):gsub("%s+$", "")
                    local hasTag = (str:find("★") or str:find("▲") or str:lower():find("%[bis") or str:lower():find("%[recommended") or str:lower():find("%[choose this")) ~= nil
                    local isEquipped, equippedOwner = getRowEquippedInfo(tb, activeChar)
                    local score, tag = getItemData(base, activeChar)
                    local row = { tb = tb, str = str, rawItem = rawItem, base = base, hasTag = hasTag,
                                  isEquipped = isEquipped, owner = equippedOwner, score = score, tag = tag }
                    row.isAcc = (score >= 3 and tag and isAccessoryItem(base, tag)) or false
                    row.rec = evaluateRecommendation(base, activeChar, isEquipped, equippedOwner)
                    rows[#rows + 1] = row

                    if row.isAcc then
                        if isEquipped and equippedOwner == activeChar then
                            if not seenEquipped[base] then
                                seenEquipped[base] = true
                                equippedAccScores[#equippedAccScores + 1] = score
                            end
                        elseif row.rec and not seenCand[base] then
                            seenCand[base] = true
                            candidates[#candidates + 1] = row
                        end
                    end
                end
            end
        end

        -- Pass 2: decide which accessory rows keep their badge.
        table.sort(candidates, function(a, b) return a.score > b.score end)
        local free = ACC_SLOTS - #equippedAccScores
        local floorScore = 0
        if free <= 0 and #equippedAccScores > 0 then
            floorScore = math.huge
            for _, sc in ipairs(equippedAccScores) do if sc < floorScore then floorScore = sc end end
        end
        local allowed = {}
        local taken = 0
        for _, c in ipairs(candidates) do
            if free > 0 then
                if taken < free then allowed[c.base] = true; taken = taken + 1 end
            elseif c.score > floorScore and taken < ACC_SLOTS then
                -- all slots are full: only suggest a swap if it beats the weakest equipped one
                allowed[c.base] = true; taken = taken + 1
            end
        end

        -- Pass 3: write the text.
        for _, row in ipairs(rows) do
            local rec = row.rec
            if row.isAcc and rec and not allowed[row.base] then rec = nil end
            if rec then
                local want = row.rawItem .. " " .. rec
                if row.str ~= want then
                    pcall(function() row.tb:SetText(FText(want)) end)
                end
            elseif row.hasTag then
                pcall(function() row.tb:SetText(FText(row.rawItem)) end)
            end
        end
    end)
end

return M
