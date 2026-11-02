# LibraScanAll

## Overview
**LibraScanAll** automatically reveals enemy elemental affinities, status immunities, and weaknesses for all enemies on the battlefield without requiring players to spend manual turns or MP casting the Libra ability repeatedly.

---

## Features
* **Universal Weakness Reveal**: Scans all active enemies instantly at the beginning of each encounter.
* **Elemental Affinity HUD**: Displays Fire, Ice, Lightning, Water, Wind, Earth, Light, and Dark affinities cleanly.
* **Works with AI Modules**: Seamlessly feeds scanned weakness data directly into `FFRAutoBattle` so auto-combat algorithms immediately exploit optimal vulnerabilities.

---

## File Structure
* `Scripts/main.lua`: Encounter initialization hook and scan coordinator.
* `Scripts/details.lua`: Enemy database formatting and weakness display widget.
* `Scripts/config.lua`: Scan timing and UI position settings.
