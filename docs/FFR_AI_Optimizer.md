# FFR_AI_Optimizer

## Overview
**FFR_AI_Optimizer** is the core quality-of-life, overworld movement, and graphics engine optimization module for *Final Fantasy Resonance*. It enhances traversal speed, eliminates tedious overworld backtracking, applies live visual clarity settings, and maintains game UI integrity.

---

## 🌟 Key Features

### 1. Multi-Tier Movement Speed Toggles
Cycle through movement speeds seamlessly during overworld and dungeon exploration without breaking cutscenes, physics, or collision:
* **Normal Walk (Default 600)**: Original game exploration pace.
* **Fast Sprint (950 / +58% Speed)**: Crisp, fluid sprint for comfortably navigating towns and dungeons.
* **Hyper-Dash (1400 / +133% Turbo Speed)**: Ultra-fast overworld traversal speed that lets you cross large maps in seconds.

### 2. Auto-Fading Bottom-Center Speed HUD
* **Zero Screen Obstruction**:
  * Cleanly positioned at **Bottom-Center** (`x: 0.5, y: 0.88`).
  * Completely avoids top-screen quest objectives and chapter banners (e.g., *"Chapter 2 - Eternal Blue"*), minimaps, timers, and subtitle areas.
* **1.8-Second Auto-Fade**:
  * When you toggle speeds with **`F5`** or **`L3`** (Controller Left Stick Click), the notification appears briefly and **automatically fades away after 1.8 seconds**.
  * Never stays on screen permanently and never clutters your exploration view.
* **Crisp Typography (Zero Broken Glyphs / Question Marks)**:
  * `[ >>> HYPER-DASH: 1400 (TURBO +133%) ]` *(Cyan)*
  * `[ >> FAST SPRINT: 950 (+58%) ]` *(Gold)*
  * `[ > NORMAL WALK: 600 ]` *(Silver)*

### 3. Live Pixel Art Clarity Engine (Hotkey: `F7`)
* Injects Unreal Engine console settings directly into the live game thread to optimize 2D pixel sprites and 3D backgrounds:
  * `r.MipMapLodBias -1.0`: Eliminates blurry texture mipmapping on character sprites.
  * `r.Tonemapper.Sharpen 1.75`: Razor-sharp pixel contours and clean edges.
  * `r.TemporalAA.Sharpness 1.4` & `r.TemporalAAFilterSize 0.75`: Eliminates ghosting and sprite bleeding during motion.
  * `r.MotionBlurQuality 0`, `r.DepthOfFieldQuality 0`, `r.FilmGrain 0`: Completely disables camera smudge and grain.
  * `r.ScreenPercentage 125`: 125% internal supersampling for tack-sharp pixel definition.
* Pressing **`F7`** in-game instantly refreshes the visual clarity preset live.

---

## 🎮 Controls
| Action | Keybind / Controller | Description |
| :--- | :--- | :--- |
| **Cycle Movement Speed** | **`F5`** or **`L3` (Left Stick Click)** | Cycles Normal (600) -> Fast Sprint (950) -> Hyper-Dash (1400) |
| **Refresh Visual Clarity** | **`F7`** | Re-applies the Ultra-Sharp Pixel Clarity profile live |

---

## File Structure
* `scripts/main.lua`: Speed controller, bottom-center HUD, hotkey listener, and live clarity injector.
* `scripts/config.lua`: Customizable speed thresholds and hotkey bindings.
* `scripts/userdata_guard.lua`: Safety guard preventing nil-pointer crashes during level transitions.
* `enabled.txt`: Controls whether UE4SS loads this mod on startup.
