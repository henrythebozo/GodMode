# Breachline — Architecture

Breachline is an original 5v5 tactical bomb-defusal FPS built in Godot 4.4 (GDScript) with all 3D
assets produced by Blender Python scripts (`blender/scripts`). This document is the map of the code.

## Top-level layout

```
breachline/            Godot project (open this folder in Godot 4.4)
  project.godot
  src/core             Autoload singletons: Settings, Events, DebugConsole, AudioBus
  src/net              NetworkManager, snapshot/input protocol, lag compensation, lobby
  src/match            MatchManager (round state machine), Economy, ObjectiveState (bomb)
  src/player           PlayerBody (shared movement sim), PlayerController (input), Spectator
  src/weapons          WeaponConfig resource, Firearm, Melee, Grenades, DamageModel, RecoilPattern
  src/ai               BotBrain finite-state machine + navigation
  src/ui               Main menu, settings, lobby, buy menu, HUD, scoreboard, round/match end
  src/world            Map loader, layout JSON → spawns/sites/buy zones/callouts/ladders
  src/data             .tres resources: weapons, economy, match rules
  tests                Headless test runner + test suites
  server               Dedicated server launcher script
  assets/models        GLB exports from Blender (never edit by hand — regenerate)
  assets/audio         Procedurally generated original WAV audio
blender/scripts        bpy automation (asset generators, validation, batch export)
blender/source         Editable .blend files written by the generators
docs                   This file, SETUP.md, CONTROLS.md, MULTIPLAYER.md, ASSET_LICENSES.md, KNOWN_LIMITATIONS.md
```

## Separation of concerns

| Layer            | Owner                                   | Rule                                                        |
|------------------|-----------------------------------------|-------------------------------------------------------------|
| Data             | `src/data/*.tres`, `WeaponConfig`       | All balance numbers live in resources, never in code.       |
| Gameplay rules   | `MatchManager`, `Economy`, `DamageModel`| Pure logic, server-only mutation, unit-tested.              |
| Networking       | `NetworkManager`, `NetProtocol`         | Owns peers, RPC routing, snapshots, lag compensation.       |
| Player control   | `PlayerBody`, `PlayerInput`             | One movement simulation used by server, client prediction, and bots. |
| Weapons          | `WeaponBase` + subclasses               | Server resolves hits; clients only render.                  |
| AI               | `BotBrain`                              | Produces `InputCmd`s exactly like a client would.           |
| Presentation     | `src/ui`, `Fx`                          | Reads state via `Events` signals; never mutates game state. |

## Authority model

* The server (dedicated or listen-server host) is the only writer of health, money, ammo, position,
  round state, and objective state.
* Clients send `InputCmd {tick, move, yaw, pitch, buttons, weapon_slot}` every physics tick.
* The server runs `PlayerBody.simulate(cmd, delta)` for each player and broadcasts a `Snapshot`.
* The local client predicts with the same `simulate()` and reconciles against server snapshots.
* Remote players are interpolated 2 ticks behind the newest snapshot.
* Shots carry the client's `view_tick`; the server rewinds hurtboxes analytically
  (`LagCompensation`) before resolving the ray. Wall occlusion is checked against live world geometry.
* Every client-originated value is range-checked (`NetValidation`) before use.

## Match state machine (MatchManager)

```
WARMUP → FREEZE → LIVE → (PLANTED) → ROUND_END → FREEZE ...
                                     ↘ HALFTIME (teams swap) → FREEZE
                                     ↘ MATCH_END (rematch/return to lobby)
                                     ↘ OVERTIME (MR3 blocks, repeat until decided)
```
Buy phase = FREEZE plus the first `buy_time` seconds of LIVE while inside a buy zone.

## Bot FSM

BUY → ROAM → (INVESTIGATE | ENGAGE | SEEK_COVER | PLANT | DEFEND | RETAKE | DEFUSE) → ... see `src/ai/BotBrain.gd`.

## Asset pipeline

`blender/scripts/export_all.py` regenerates every model deterministically. Naming rules are enforced by
`bl_common.validate_scene()`. Suffix conventions follow Godot's glTF importer:
`-col` (trimesh collision), `-convcol` (convex), `-colonly`, `-navmesh`, `-occ` (occluder), `_LOD1/_LOD2`.
