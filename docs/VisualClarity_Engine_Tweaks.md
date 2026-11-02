# Visual Clarity & HD-2D Crispness Profile

## Overview
By default in Unreal Engine, 2.5D / HD-2D games often suffer from blurry, smudged pixel art because the 3D perspective camera samples 2D sprite sheets at reduced mipmap levels, and default Temporal Anti-Aliasing (TAA) blends adjacent frames into a watercolor smudge.

This visual clarity profile completely fixes sprite and world blur, producing razor-sharp, well-defined pixel sprites and UI text.

---

## What the Tweaks Do

| Setting | Value | What It Fixes |
| :--- | :--- | :--- |
| `r.MipMapLodBias` | `-1.0` | **Forces Full-Resolution Sprite Mips**: Stops the GPU from downsampling sprites in 3D perspective; eliminates blurry character sprites. |
| `r.Tonemapper.Sharpen` | `1.75` | **Edge Definition**: Restores crisp pixel contours and makes sprite borders and details pop. |
| `r.TemporalAAFilterSize` | `0.75` | **Anti-Smudge Filter**: Tightens TAA sample window so camera panning doesn't smear pixel edges. |
| `r.TemporalAA.Sharpness` | `1.4` | **Motion Sharpness**: Preserves pixel grid clarity when characters move or run. |
| `r.ScreenPercentage` | `125` | **125% Super-Sampling**: Renders internal buffers with extra geometric clarity, eliminating jagged edges. |
| `r.MotionBlurQuality` | `0` | **Disabled**: Removes motion blur that smudges pixel animations. |
| `r.DepthOfFieldQuality` | `0` | **Disabled**: Stops the camera from artificially blurring backgrounds or foreground sprites. |
| `r.SceneColorFringeQuality` | `0` | **Disabled**: Removes chromatic aberration (rainbow fringing around sprite silhouettes). |
| `r.FilmGrain` | `0` | **Disabled**: Removes noisy post-processing grain for a clean visual presentation. |

---

## How to Apply

### Method 1: Engine.ini (Persistent on Game Startup)
Copy the provided [`config/Engine.ini`](../config/Engine.ini) into:
```
%LOCALAPPDATA%\FFRS\Saved\Config\WindowsNoEditor\Engine.ini
```

### Method 2: Live In-Game via Hotkey
If you have `FFR_AI_Optimizer` installed, the mod automatically injects these console commands on game startup. You can also press **`F7`** at any time while playing to re-apply and refresh the clarity preset live!
