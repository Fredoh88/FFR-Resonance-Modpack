# Installation & Hand-Pick Guide

This guide explains how to install the entire modpack, or easily pick and choose only the specific mods you want.

---

## Prerequisites
1. **UE4SS (Unreal Engine 4/5 Scripting System)** installed for *Final Fantasy Resonance*.
   * Standard installation location:
     ```
     <SteamLibrary>\steamapps\common\FINAL FANTASY RESONANCE\FFRS\Binaries\Win64\ue4ss\
     ```

---

## Installing Paired Vortex PAK Mods
If you also want to use the curated PAK mods that Fredoh pairs with this suite (like 4 Accessory Slots, 100% Steal, Item/Chest Markers, etc.):
1. Install [Vortex Mod Manager](https://www.nexusmods.com/about/vortex/) and manage *Final Fantasy Resonance*.
2. Open **[docs/VORTEX_RECOMMENDED_LOADOUT.md](docs/VORTEX_RECOMMENDED_LOADOUT.md)** and click the Nexus links for any mods you'd like.
3. Click "Vortex Download" on Nexus to install and enable them.
4. Vortex places the `.pak` files into `FFRS/Content/Paks/~mods/`. These run side-by-side with UE4SS with 0 conflicts!

---

## Option A: Install Everything (Recommended)
1. Download or clone this repository.
2. Copy all folders from the [`mods/`](mods/) directory into your game's `ue4ss/Mods/` directory:
   ```
   <SteamLibrary>\steamapps\common\FINAL FANTASY RESONANCE\FFRS\Binaries\Win64\ue4ss\Mods\
   ```
3. Copy [`config/Engine.ini`](config/Engine.ini) into:
   ```
   %LOCALAPPDATA%\FFRS\Saved\Config\WindowsNoEditor\
   ```
4. Launch the game and enjoy!

---

## Option B: Hand-Pick Specific Mods
Every mod in this repository is completely independent and self-contained. You can install only the features you care about:

### Method 1: Only Copy the Folders You Want
Simply choose the folder(s) from [`mods/`](mods/) that you want, and copy only those into your `ue4ss/Mods/` folder.

| Mod Folder | What It Does | Who Should Install It |
| :--- | :--- | :--- |
| **`FFR_AI_Optimizer`** | Movement speed modes (Walk/Sprint/Hyper-Dash), auto-fading HUD, and `F7` pixel clarity hotkey. | **Essential** for everyone who wants smooth traversal and crisp graphics. |
| **`FFRAutoBattle`** | Intelligent auto-combat, weakness exploitation, and Citrine/Magic Pot puzzle solver. | Anyone who wants smart auto-battling and effortless Magic Pot puzzle solving. |
| **`CombatTag`** | Target lock-on and combat indicators. | Players who want clear visual targeting in chaotic fights. |
| **`LibraScanAll`** | Instant weakness scan on all enemies at the start of battle. | Players who want enemy elemental affinities visible without casting Libra. |
| **`FFR_EnemyHPNumbers`** | Floating numerical HP and stagger gauge percentages over enemies. | Players who want exact numbers instead of vague health bars. |
| **`AutoRestoreHPManaAfterBattle`** | Automatically restores 100% HP & MP after winning a battle. | Players who dislike opening menus to heal up between fights. |

### Method 2: Enable / Disable via `enabled.txt`
If you already copied all folders, you can disable any individual mod at any time:
1. Open the mod's folder inside `ue4ss/Mods/<ModName>/`.
2. Delete the file named `enabled.txt` (or rename it to `disabled.txt`).
3. UE4SS will ignore that mod on the next game launch. To turn it back on, simply create an empty file named `enabled.txt` inside that mod folder.
