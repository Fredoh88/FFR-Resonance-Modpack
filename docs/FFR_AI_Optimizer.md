# FFR_AI_Optimizer

## Overview
**FFR_AI_Optimizer** is the core quality-of-life and performance engine for *Final Fantasy Resonance*. It enhances player movement speed, eliminates tedious overworld backtracking, applies live visual clarity settings, and maintains game UI integrity.

---

## Key Features

### 1. Movement Speed Modes
Cycle through movement speeds seamlessly during overworld and dungeon exploration without breaking cutscenes or physics.
* **Normal Walk (Default 600)**: Original game exploration pace.
* **Fast Sprint (950 / +58% Speed)**: Crisp, fluid sprint for navigating towns and dungeons comfortably.
* **Hyper-Dash (1400 / +133% Speed)**: Ultra-fast overworld traversal speed that lets you cross large maps in seconds.

### 2. Auto-Fading Top-Center Speed HUD
* **Clean Placement**: Positioned at top-center (`x: 0.5, y: 0.06`), fully clear of quest titles (e.g. *"Chapter 2 - Eternal Blue"*), minimaps, and dialogue boxes.
* **Auto-Fade Timer**: Shows for 3.0 seconds when you change movement speeds, then fades away completely so your screen remains immersive and clutter-free.
* **Clean ASCII Indicators**:
  * `[ >>> HYPER-DASH: 1400 (TURBO +133%) ]` *(Cyan)*
  * `[ >> FAST SPRINT: 950 (+58%) ]` *(Gold)*
  * `[ > NORMAL WALK: 600 ]` *(Silver)*

### 3. Live Pixel Art Clarity Engine (Hotkey: `F7`)
* Injects Unreal Engine console settings directly into the live game thread to optimize 2D sprites and 3D backgrounds.
* Forces crisp sprite sampling, removes artificial temporal blur, and sharpens outlines.
* Pressing **`F7`** in-game instantly refreshes the visual clarity preset live.

---

## Controls
| Action | Keybind | Description |
| :--- | :--- | :--- |
| **Cycle Speed** | `Shift` / Custom Key | Cycles through Normal (600) -> Fast Sprint (950) -> Hyper-Dash (1400) |
| **Refresh Visuals** | `F7` | Re-applies the Ultra-Sharp Pixel Clarity profile live |

---

## File Structure
* `scripts/main.lua`: Speed controller, HUD management, hotkey listener, and visual preset injector.
* `scripts/config.lua`: Customizable speed thresholds and hotkey bindings.
* `scripts/userdata_guard.lua`: Safety guard preventing nil-pointer crashes during level transitions.
* `enabled.txt`: Controls whether UE4SS loads this mod on startup.
