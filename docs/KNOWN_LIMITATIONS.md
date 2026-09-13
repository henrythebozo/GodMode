# Known limitations and remaining work

Verified means "exercised by the automated tests, the headless smoke match, a dedicated-server +
client session, or a rendered screenshot under Xvfb" during development. Human play-testing with a
mouse and keyboard on real hardware has **not** been possible in the development environment.

## Gameplay
* Bots do not use ladders (Godot navmesh has no ladder links); they use the stairs to reach the catwalk.
* Bot grenade usage is simple (smoke/flash toward the objective path when no enemy is visible).
* No wall penetration for bullets. Bullets stop at the first world surface.
* Third-person animation is state-based (idle/walk/run/crouch/jump/death/plant/defuse) with a chest
  pitch layer; no aim-offset blend tree or foot IK.
* Reload/draw/inspect animations on the first-person arms are simple keyframed motions; the weapon
  mesh does not animate its own parts (magazine stays attached).
* Smoke volumes block bot vision and are rendered as sphere clusters; they do not occlude player
  vision physically (visual cloud only). Incendiary fire does not spread.
* Decoy grenade plays synthesised gunfire; it does not show on a radar (no radar/minimap yet).
* No radar/minimap, no voice chat, no demo recording.

## Multiplayer
* Prediction/interpolation are prototypes (see docs/MULTIPLAYER.md); no extrapolation on packet loss.
* No internet master server; LAN discovery + direct IP only.
* Anti-cheat is not implemented; only server authority and sanity checks.
* Grenade physics on clients is mirrored from snapshots (not predicted).

## Presentation
* Materials are flat PBR colours (no texture painting). Textured art can be added in Blender and
  exported through the same pipeline.
* Lighting is tuned for the Compatibility renderer on llvmpipe; Forward+ on a GPU may need exposure
  tweaks in `MapLoader._build_environment`.
* Announcer lines are tonal stingers with subtitles; drop `wav` voice files into
  `assets/audio/announcer/vo/<event>.wav` to override them.
* Attacker spawn view faces the ramp but the yard wall is close; map art is kit-based and sparse.

## Tooling
* Godot must re-import (`--import` or open the editor) after regenerating GLBs.
* The Blender generators overwrite `blender/source/*.blend`; hand edits must be kept as the new source.
* `Xvfb` + Mesa llvmpipe is required for the gallery/screenshot tools on a machine without a display.

## Not yet done from the original brief
* Weapon-part animations (bolt/slide/magazine) and per-weapon reload sounds beyond the shared set.
* Occlusion culling beyond the merged wall occluders (`-occonly`) and visibility ranges on props.
* Steam/console input, gamepad support.
