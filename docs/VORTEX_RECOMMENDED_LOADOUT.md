# Vortex Companion Mod Loadout (Paired PAK Mods)

This document details the exact **Vortex / Nexus PAK mods** currently paired with the UE4SS AI & Optimization Modpack. 

While the mods in [`mods/`](../mods/) handle live script execution, movement hotkeys, battle automation, and visual clarity via UE4SS, the Vortex mods handle balance alterations, game rules, and asset tweaks via Unreal Engine `.pak` files in `Content/Paks/~mods`. 

Together, they form the complete *Final Fantasy Resonance* loadout.

---

## 🏆 Mod Categorization & Direct Nexus Links

### 💎 Progression, Gear & Economy
Mods that streamline grinding and unlock full build flexibility.

| Mod Name | Nexus Link | Version | What It Does & Why It's Used |
| :--- | :--- | :--- | :--- |
| **Equip 4 Accessories** | [Nexus #105](https://www.nexusmods.com/finalfantasyresonance/mods/105) | `1.12` | Expands accessory slots from 2 to 4 for all party members, allowing deeper mathematical builds and status immunities. |
| **Free AP Ability Permanent** | [Nexus #57](https://www.nexusmods.com/finalfantasyresonance/mods/57) | `1.0` | Equipping mastered permanent abilities costs 0 AP budget, letting you equip all earned passive traits without restriction. |
| **Half Price Shop and Sell Higher** | [Nexus #6](https://www.nexusmods.com/finalfantasyresonance/mods/6) | `1.0` | Reduces shop buy prices by 50% and raises item sell-back value to eliminate gil shortages. |
| **Item Shop Sells Everything in All Places** | [Nexus #4](https://www.nexusmods.com/finalfantasyresonance/mods/4) | `1.2` | Universal shop inventory so you never have to backtrack across the world map to buy consumable supplies. |
| **Half EXP Required All Characters** | [Nexus #7](https://www.nexusmods.com/finalfantasyresonance/mods/7) | `1.1` | Halves total EXP needed to level characters, keeping party members evenly leveled. |
| **Half EXP Vision MR** | [Nexus #8](https://www.nexusmods.com/finalfantasyresonance/mods/8) | `1.1` | Halves EXP required to rank up Visions to MR 8, unlocking card abilities much faster. |
| **FFRS ExpX2** | [Nexus #36](https://www.nexusmods.com/finalfantasyresonance/mods/36) | `1.0` | Multiplies combat EXP by 2x for smooth pacing. |
| **MRP Multiplier x2** | [Nexus #37](https://www.nexusmods.com/finalfantasyresonance/mods/37) | `1.0` | Multiplies battle MRP (Mastery Points) by 2x to master abilities faster. |
| **More Bonuses 2x Variant** | [Nexus #34](https://www.nexusmods.com/finalfantasyresonance/mods/34) | `1.0` | Multiplies post-combat tactical bonuses by 2x. |

---

### 🗺️ World Exploration & Quality of Life
Mods that eliminate backtracking, reveal secrets, and respect your time.

| Mod Name | Nexus Link | Version | What It Does & Why It's Used |
| :--- | :--- | :--- | :--- |
| **Item and Chest Markers** | [Nexus #25](https://www.nexusmods.com/finalfantasyresonance/mods/25) | `1.5` | Adds minimap indicators for hidden treasure chests, items, and gather points so you never miss secret loot. |
| **Area Level Indicator** | [Nexus #33](https://www.nexusmods.com/finalfantasyresonance/mods/33) | `1.1` | Displays the recommended party level for each zone on the map, preventing accidental over-leveled wipes. |
| **SaveAnywhere Pak** | [Nexus #95](https://www.nexusmods.com/finalfantasyresonance/mods/95) | `1.0` | Allows manual saving at any time from the pause menu without needing a save crystal point. |
| **FFRS SkipLogos** | [Nexus #42](https://www.nexusmods.com/finalfantasyresonance/mods/42) | `1.0` | Skips unskippable publisher and engine intro splash logos on startup, launching the game instantly. |

---

### ⚔️ Combat Mechanics & Loot
Mods that enhance battle flow and reward execution.

| Mod Name | Nexus Link | Version | What It Does & Why It's Used |
| :--- | :--- | :--- | :--- |
| **Steal Always 100%** | [Nexus #52](https://www.nexusmods.com/finalfantasyresonance/mods/52) | `1.0` | Guarantees steal attempts succeed 100% of the time, eliminating wasted turns. |
| **Enemies Drop 100% Item** | [Nexus #61](https://www.nexusmods.com/finalfantasyresonance/mods/61) | `1.0` | Defeated foes always drop their item drop table loot. |
| **Cactuars NEVER ESCAPE** | [Nexus #45](https://www.nexusmods.com/finalfantasyresonance/mods/45) | `1.1` | Prevents rare Cactuar mobs from fleeing before you can finish them for massive rewards. |
| **LimitBurst Enhanced JULINOS** | [Nexus #27](https://www.nexusmods.com/finalfantasyresonance/mods/27) | `1.0` | Enhances Limit Burst scaling, recharge mechanics, and passive bonuses. |

---

### 📜 UI, Details & Readability
Mods that make stats, scaling, and damage transparent.

| Mod Name | Nexus Link | Version | What It Does & Why It's Used |
| :--- | :--- | :--- | :--- |
| **Detailed Skill and Item For English Language** | [Nexus #3](https://www.nexusmods.com/finalfantasyresonance/mods/3) | `1.51` | Replaces vague in-game descriptions (*"Deals moderate damage"*) with exact mathematical scaling, damage formulas, and buff percentages. |
| **Display HP Damage Prediction & Break Numbers** | [Nexus #16](https://www.nexusmods.com/finalfantasyresonance/mods/16) | `1.4` | Displays predicted damage and numerical break progress on targets before committing actions. |

---

## 🧩 How They Pair with the UE4SS Modpack

| Feature | Vortex PAK Mod | Paired UE4SS Mod in This Repo | Synergy |
| :--- | :--- | :--- | :--- |
| **Movement Speed** | *(None)* | `FFR_AI_Optimizer` | Traversal speed (Fast Sprint 950 / Hyper-Dash 1400) + auto-fading top-center HUD. |
| **Graphics Clarity** | *(None)* | `Engine.ini` + `F7` Hotkey | Fixes Unreal Engine sprite mipmap blur, sharpens pixel edges, and removes smudging. |
| **Magic Pot Puzzles** | *(None)* | `FFRAutoBattle` | Automatically detects Pot dialogue, feeds requested Ether/Elixir, and guards party for instant win. |
| **Enemy Weaknesses** | *(None)* | `LibraScanAll` | Auto-reveals elemental weaknesses instantly at combat start. |
| **Enemy HP Display** | Damage Prediction (#16) | `FFR_EnemyHPNumbers` | Real-time exact numerical floating HP and stagger percentage gauges. |
| **Post-Combat Recovery** | *(None)* | `AutoRestoreHPManaAfterBattle` | Restores 100% HP & MP after every fight so you don't waste items between encounters. |
| **Free Ability Equipping** | Free AP Mod (#57) | `FFRAutoBattle` | AI knows how to execute all equipped high-tier abilities and role-based passives seamlessly. |
