# Final Fantasy Resonance — Modular Enhancement Suite & AI Modpack
> **Author:** Fredoh  
> **Collaborator:** TortilaFury (Titan)  
> **Target Game:** *FINAL FANTASY RESONANCE* (UE4SS / Steam)  
> **Repository:** [https://github.com/Fredoh88/FFR-Resonance-Modpack](https://github.com/Fredoh88/FFR-Resonance-Modpack)

---

## Welcome, Tortilla! 🎮
This repository contains the complete, up-to-date collection of quality-of-life enhancements, combat AI systems, and visual clarity tweaks developed for *Final Fantasy Resonance*.

Every mod in this suite is built to be **100% modular**. You can either install the entire suite in one go, or pick and choose individual mods based on how you like to play.

---

## 📦 What's Inside: Categorized Mod Breakdown

```
FFR-Resonance-Modpack/
├── mods/
│   ├── FFR_AI_Optimizer/             ⚡ Speed Toggles, Auto-Fade HUD, Live Clarity Engine
│   ├── FFRAutoBattle/                ⚔️ Battle AI, Stagger Logic, Magic Pot Puzzle Solver
│   ├── CombatTag/                    🎯 Target Tracking & Combat Indicators
│   ├── LibraScanAll/                 👁️ Instant Universal Weakness & Affinity Scanner
│   ├── FFR_EnemyHPNumbers/           📊 Floating Numerical HP & Stagger Overlays
│   └── AutoRestoreHPManaAfterBattle/ 💖 Full Post-Battle HP/MP Auto-Recovery
├── config/
│   └── Engine.ini                    🎨 Crisp HD-2D Pixel Art & Visual Engine Tweaks
├── docs/                             📖 In-Depth Guides For Every Mod
├── INSTALLATION.md                   🛠️ Installation & Hand-Pick Instructions
└── sync_to_github.bat                🔄 One-Click Script To Push Live Updates
```

---

## 🎯 Quick Mod Overview

| Mod Name | Category | Summary | Documentation |
| :--- | :--- | :--- | :--- |
| **`FFR_AI_Optimizer`** | Traversal & Visuals | Normal (600), Fast Sprint (950), and Hyper-Dash (1400) speed modes. Auto-fades after 3s at top-center. Injects crisp visual settings and includes an **`F7`** live refresh hotkey. | [Read Docs](docs/FFR_AI_Optimizer.md) |
| **`FFRAutoBattle`** | Combat AI | Intelligent auto-battle engine. Automatically exploits elemental weaknesses, maintains tank/DPS/healer roles based on equipped Visions, and **auto-solves Magic Pot / Citrine Pot puzzle encounters** by feeding them requested items while commanding party to Guard. | [Read Docs](docs/FFRAutoBattle.md) |
| **`CombatTag`** | Combat UI | Real-time target acquisition highlighting and action synchronization. | [Read Docs](docs/CombatTag.md) |
| **`LibraScanAll`** | Combat Intel | Automatically reveals elemental weaknesses and status vulnerabilities for all enemies at encounter start without spending turns or MP on Libra. | [Read Docs](docs/LibraScanAll.md) |
| **`FFR_EnemyHPNumbers`** | Combat UI | Overlays exact numerical HP numbers (e.g. `14,250 / 25,000`) and precise stagger progress percentages over enemy health bars. | [Read Docs](docs/FFR_EnemyHPNumbers.md) |
| **`AutoRestoreHPManaAfterBattle`** | Quality of Life | Instantly restores party HP & MP to 100% upon battle victory, removing post-combat menu potion spam. | [Read Docs](docs/AutoRestoreHPManaAfterBattle.md) |
| **Visual Clarity Profile** | Graphics Engine | Stops Unreal Engine from smudging 2.5D pixel sprites. Negative mipmap bias (`-1.0`), tonemapper sharpening (`1.75`), and tight temporal anti-aliasing. | [Read Docs](docs/VisualClarity_Engine_Tweaks.md) |

---

## 🚀 How to Install & Hand-Pick

### Quickest Way: Install Everything
1. Copy all folders in [`mods/`](mods/) directly into your game's `ue4ss/Mods/` directory:
   ```
   <SteamLibrary>\steamapps\common\FINAL FANTASY RESONANCE\FFRS\Binaries\Win64\ue4ss\Mods\
   ```
2. Copy [`config/Engine.ini`](config/Engine.ini) into:
   ```
   %LOCALAPPDATA%\FFRS\Saved\Config\WindowsNoEditor\
   ```
3. Boot the game!

### How to Hand-Pick Only What You Want
If you only want certain mods (for example, just the traversal speed boost + visual clarity, or just the auto-battle AI):
* **Option 1**: Simply copy only the specific mod folder you want from [`mods/`](mods/) into `ue4ss/Mods/`.
* **Option 2**: In any installed mod folder, delete the file `enabled.txt` to turn that mod off, or create an empty `enabled.txt` to turn it back on.

See [INSTALLATION.md](INSTALLATION.md) for full instructions and configuration options.

---

## ⌨️ Controls & Keybinds Cheat-Sheet

* **`Shift` / Speed Key**: Cycle movement speeds:
  * `[ >>> HYPER-DASH: 1400 (TURBO +133%) ]`
  * `[ >> FAST SPRINT: 950 (+58%) ]`
  * `[ > NORMAL WALK: 600 ]`
  *(Badge automatically fades after 3 seconds)*
* **`F7`**: Re-apply / refresh Ultra-Crisp Pixel Art clarity profile live in-game.

---

## 🔄 Live Sync Workflow
Whenever updates, bug fixes, or new features are developed:
1. Running `sync_to_github.bat` (or `sync_to_github.ps1`) automatically gathers the latest verified scripts from the live game install and pushes them directly to this repository.
2. The GitHub repository will always reflect the exact current build of the mods.
