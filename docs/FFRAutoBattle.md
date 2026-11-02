# FFRAutoBattle

## Overview
**FFRAutoBattle** is an advanced, high-efficiency AI combat module designed to optimize party decision-making in *Final Fantasy Resonance*. It eliminates repetitive grinding while executing complex combat rotations, elemental weakness exploitation, and special puzzle encounters.

---

## Key Features

### 1. Magic Pot & Citrine Pot Puzzle Solver
* **Encounter Detection**: Automatically recognizes special puzzle encounters like Magic Pots and Citrine Pots.
* **Consumable Delivery**: Reads the Pot's dialogue prompt (e.g., *"Gimme an ether!"*) and automatically uses the requested item (`Ether`, `Hi-Ether`, `Elixir`) from the party inventory, targeting the Pot.
* **Party Guard Protocol**: Instructs the other party members to **Guard / Hold** rather than attacking or casting spells, preventing accidental party wipes or wasted ATB.
* **Instant Victory**: Giving the Pot its requested item immediately wins the battle, awarding maximum MRP (Mastery Points) and EXP to level up your equipped Visions.

### 2. Intelligent Weakness & Stagger Prioritization
* Integrates with scanned enemy affinities to automatically cast the optimal elemental spell or physical ability.
* Focuses staggered and vulnerable enemies to maximize team DPS multipliers.
* Prioritizes high-threat add mobs (e.g. healers, bomb timers) before focusing boss targets.

### 3. Vision Synergy & Role Optimization
* Adapts dynamically based on which Vision is equipped to each character (e.g., Cloud, Warrior of Light, White Mage, Thief, etc.).
* Casts role-appropriate buffs, taunts, and counters without manual intervention:
  * **Sentinel (Tank)**: Keeps `Multi-Cover` and damage reduction active.
  * **DPS / Striker**: Chains highest-potency abilities during stagger windows.
  * **Healer**: Triggers heals proactively when party health drops below 50%, saving party members before fatal hits.

### 4. Mathematical Safety & Game-Thread Isolation
* All Lua calls are guarded with `ExecuteInGameThread` and `pcall` wrappers.
* Protects against null pointers during battle transitions, cutscene triggers, and victory animations.

---

## File Structure
* `Scripts/main.lua`: Core battle loop, tick handlers, and turn execution.
* `Scripts/mobs.lua`: Enemy data catalog, mob types, and puzzle encounter recognition (Citrine / Magic Pot).
* `Scripts/catalog.lua`: Item and ability IDs, consumable lookup table.
* `Scripts/debuffs.lua`: Status effect tracker (Poison, Blind, Silence, Stun).
* `Scripts/health.lua`: Dynamic party health monitoring and auto-heal thresholds.
* `Scripts/espers.lua` & `Scripts/limits.lua`: Summon and Limit Break management.
* `Scripts/advisor.lua` & `Scripts/highlighter.lua`: Tactical suggestions and target highlighting.
