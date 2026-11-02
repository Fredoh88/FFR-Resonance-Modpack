# FFRAutoBattle

## Overview
**FFRAutoBattle** is an advanced, high-efficiency AI combat module designed to optimize party decision-making in *Final Fantasy Resonance*. It eliminates repetitive grinding while executing complex combat rotations, elemental weakness exploitation, mathematical build synergies, and special puzzle encounters.

---

## 🌟 Key Features

### 1. Magic Pot & Citrine Pot Puzzle Encounter Solver
* **Encounter Detection**: Automatically recognizes rare puzzle encounters like Magic Pots and Citrine Pots.
* **Consumable Delivery**: Reads the Pot's dialogue prompt (e.g., *"Gimme an ether!"*) and automatically uses the requested item (`Ether`, `Hi-Ether`, `Elixir`) from the party inventory, targeting the Pot.
* **Party Guard Protocol**: Instructs all other party members to **Guard / Hold** rather than attacking or casting spells, preventing accidental 1-damage chipping or wasted ATB.
* **Instant Victory**: Giving the Pot its requested item immediately wins the battle, awarding maximum MRP (Mastery Points) and EXP to level up your equipped Visions!

### 2. Maximum-Damage Resonance Move Optimizer
When the battle enters the **Resonance Wheel / Finisher phase**, the AI evaluates every combat factor to choose the ideal character, skill, and target for maximum burst damage and tactical payoff:
* **Staggered / Broken Target Multiplier (`2.2x` Priority & Overkill Drop Lock)**:
  * Detects enemies in Break/Stagger state (which take 200%+ damage in FFRS).
  * Prioritizes staggered enemies to maximize total burst damage and lock in the **Overkill drop rate bonus** for rare gear and Visions.
* **Universal Weakness Matching (`3.0x` Multiplier) & Hard Absorb Filtering (`0x`)**:
  * Cross-references universal enemy affinities from Libra.
  * Targets elemental vulnerabilities with a massive **`2.5x` score multiplier**.
  * **Hard-filters absorbed or immune elements (`0x`)**: your team will *never* fire an elemental Resonance move into an enemy that absorbs or nullifies it.
* **Boss & High-Threat Prioritization (`1.4x` Multiplier)**:
  * Prevents wasting a 50,000 damage finisher on a 1-HP minion when a full-health Boss or Elite enemy is on the field.
* **Caster Stat Scaling (Physical ATK vs. Magic MAG)**:
  * Physical finishers (*True Octaslash*, *Armiger Unleashed*, *Blitz Ace*) are paired with high-ATK/Crit physical assassins (Lasswell, Cloud, Rain).
  * Magical finishers (*Errand's End*, *Colossal Shantotto II*, *Hibernal Fury*) are paired with high-MAG nukers (Dark Fina, Sakura).
* **Debuff Synergies (DEF Break, SPR Break, Imperil)**:
  * Leverages active DEF breaks (+25% physical damage) and SPR breaks (+25% magical damage) on targets.
* **Smart AoE vs. Single-Target Logic**:
  * For multi-enemy packs (3+ foes), AoE finishers (*Crimson Onslaught*, *Colossal Shantotto*) sum total damage across all living targets to achieve a clean field wipe.
* **Emergency Rescue Protocol**:
  * If party members are critically low (< 35% HP or multiple allies down), healing/revival Resonances (*Healing Wind*, *Angelic Embrace*, *Resolute Bastion*) immediately take priority to save the run.

### 3. Redesigned In-Combat Tactical HUD
* **Native Game Aesthetics**:
  * Downsized to a razor-sharp **`11pt`** font scale that matches in-game battle text.
  * Styled with a frosted, translucent dark slate navy background (`A = 0.68`) and champagne-gold typography (`#F0E0AE`).
  * Compact pill profile (`10px × 3px` padding) cleanly positioned in the corner without dominating the battle screen.
* **Real-Time Tank Aggro Telemetry**:
  * `[AUTO: SPEED FARM]  |  THREAT: CLEAR`: Vanguard has enemies pacified or agro is safe.
  * `[AUTO: SPEED FARM]  |  AGGRO SECURED (R1)`: Tank has successfully provoked and established hostility lock.
  * `[AUTO: BOSS BURST]  |  AGGRO SECURED (R2)`: High-efficiency boss focus active.
* **Zero Missing Glyphs**:
  * All broken emojis and corrupted character encodings (`âšï,`, `?`) have been replaced with standard, crisp ASCII typography.

### 4. Vision Synergy & Dynamic Role Optimization
* Adapts dynamically based on which Vision is equipped to each character (e.g., Cloud, Warrior of Light, White Mage, Thief, etc.).
* Casts role-appropriate buffs, taunts, and counters without manual intervention:
  * **Sentinel (Tank)**: Rain, Cecil, and Charlotte maintain `Multi-Cover`, Provoke, and damage reduction.
  * **DPS / Striker**: Lasswell, Cloud, and Squall chain high-potency abilities during stagger windows.
  * **Healer**: Fina, Ayaka, and Folka proactively cast Curaja/Arise when party members take heavy damage.

### 5. Mathematical Safety & Game-Thread Isolation
* All engine hooks are strictly wrapped in `ExecuteInGameThread` and safe `pcall` boundaries.
* Zero stutter or thread race conditions during combat transitions, cutscene triggers, and victory animations.

---

## File Structure
* `Scripts/main.lua`: Core battle loop, tick handlers, turn execution, and Resonance wheel solver.
* `Scripts/mobs.lua`: Enemy database, affinities, and puzzle encounter recognition (Citrine / Magic Pot).
* `Scripts/catalog.lua`: Item and ability IDs, consumable lookup table.
* `Scripts/debuffs.lua`: Status effect tracker (Poison, Blind, Silence, Stun, Break).
* `Scripts/health.lua`: Dynamic party health monitoring and auto-heal thresholds.
* `Scripts/espers.lua` & `Scripts/limits.lua`: Summon and Limit Break management.
* `Scripts/advisor.lua` & `Scripts/highlighter.lua`: Tactical suggestions and live HUD.
