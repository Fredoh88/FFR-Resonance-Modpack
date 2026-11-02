# CombatTag

## Overview
**CombatTag** provides real-time battle tracking and target status indicators for all combatants on the field in *Final Fantasy Resonance*.

---

## Features
* **Visual Target Lock**: Clearly highlights the currently focused target across all party members.
* **Combat State Synchronization**: Tracks active turn meters, casting states, and incoming enemy telegraphs.
* **Seamless Overlay**: Lightweight UI overlay that updates smoothly without frame drops.

---

## File Structure
* `Scripts/main.lua`: Target tracker and visual tag controller.
* `Scripts/userdata_guard.lua`: Safety guard preventing nil-pointer crashes.
* `tag_bridge.dll`: High-speed memory bridge for UE4SS entity indexing.
* `settings.ini`: Tag visual properties, colors, and font scaling.
