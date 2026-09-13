# Breachline — progress checklist

Legend: **[x]** implemented and verified (unit test, headless match, server+client session or
rendered screenshot) · **[~]** implemented, only partially verified · **[ ]** not done.

## Tooling & pipeline
- [x] Godot 4.4 project scaffold, autoloads, input map, physics layers
- [x] Blender pipeline: shared helpers, naming validation, transforms, LOD, collision, batch GLB export, `.blend` sources
- [x] Weapons generator (16 firearms, knife, 5 grenades, charge, kit, shell) — verified in gallery render
- [x] Rigged characters for both factions + FP arms with animations — pose directions verified numerically, gallery render
- [x] Environment kit (28 pieces) — gallery render
- [x] Foundry map generator + layout JSON (spawns, 2 sites, buy zones, 16 callouts, ladders, cover, patrol points, lights, occluders)
- [x] Procedural original audio (91 clips) — loads in game
- [x] Weapon balance table → `.tres` resources (24) — validated by tests
- [x] Headless test runner (295 checks): economy, damage/hitboxes, weapon config/state/inventory, net protocol/validation/lag-comp, match state machine

## Gameplay
- [x] Movement: run, walk, crouch, jump, air accel, ladders, fall damage, footsteps, movement inaccuracy — simulated in smoke matches (bots use it); ladders exercised via Area triggers only [~ for human feel]
- [x] Mouse look, sensitivity, raw input, invert, zoom sensitivity, FOV, view-model FOV
- [x] Hitscan weapons with magazine/reserve, reload, switching, equip/first-fire delays, falloff, armor penetration, head/torso/arm/leg zones, recoil patterns + recovery, first-shot accuracy, move/jump/crouch modifiers, spread, pellets, burst/pump/bolt modes
- [x] Lag-compensated hit resolution on the server
- [~] Muzzle flash, tracers, shells, impacts, decals, blood (toggle) — implemented, seen only in code review + no runtime errors (effects run on clients)
- [x] Camera and view-model recoil, sway, bob, reduced-motion option
- [~] Inspect animation, pickup/drop/swap, dropped weapons as physics entities
- [x] Grenades: frag (damage + occlusion), flash (angle/LOS based), smoke (blocks bot vision), incendiary (area damage), decoy (fake gunfire)
- [x] Bomb: plant/defuse with progress, timer, kit, explosion damage, beeping
- [x] Match flow: warmup, freeze, buy phase, live, planted, round end, halftime swap, match end, overtime blocks, surrender, rematch, return to lobby — unit tested
- [x] Economy: start money, purchases, refunds, buy-zone restriction, win/loss rewards, loss streaks, plant/defuse/kill rewards, team-kill penalty — unit tested
- [x] Spectator: follow teammates / free camera — screenshot-verified following a bot (docs/images/screenshot_spectator.png)
- [x] Bots: navmesh navigation, FSM (BUY, ROAM, PUSH, DEFEND, INVESTIGATE, ENGAGE, SEEK_COVER, PLANT, RETAKE, DEFUSE, FETCH_BOMB), buying, grenades, 4 difficulty profiles — smoke match shows fights, kills, purchases
- [x] Bots plant — observed in a dedicated-server run (`[match] charge planted at B by [BOT] Cinder`); defuse logic shares the same objective path (unit tested through `server_defuse_bomb`)

## Multiplayer
- [x] ENet host/join/dedicated server, lobby, teams, ready check, spawning, match-state sync, latency display — verified with headless client vs dedicated server
- [~] Client prediction & reconciliation, remote interpolation — run under simulated 120 ms latency / 10% loss / 40 ms jitter without errors while receiving replicated match state; feel not yet tuned on real networks
- [x] Server-side validation of inputs/purchases/objectives
- [x] Reconnect (persisted token + 60 s grace) — verified: a restarted client reattached to its player (`[net] Operator reconnected: peer ... took over player ...`)
- [x] LAN server browser foundation (UDP discovery)
- [x] Network simulation (latency/loss/jitter)
- [ ] Anti-cheat (out of scope; architecture documented)

## Presentation
- [x] Main menu, settings (video/audio/controls remap/gameplay/accessibility/network/crosshair editor), lobby, team select, buy menu, HUD, scoreboard, pause, kill feed, damage indicators, hit markers, round-end and match-results screens — main menu/lobby/HUD/buy menu screenshot-verified; others exercised in code paths
- [x] Accessibility: colour-vision palettes, subtitles, UI scale/large text, reduced motion, blood toggle, flash intensity, separate audio sliders
- [x] Spatial audio for footsteps, gunshots (near/distant), reloads, grenades, ambience, announcer hooks with subtitle

## Documentation
- [x] README, SETUP, CONTROLS, ARCHITECTURE, MULTIPLAYER, BLENDER_PIPELINE, ASSET_LICENSES, KNOWN_LIMITATIONS

## Verification log
- `tests/run_tests.gd`: 295 checks passing (economy 30, damage 29, weapon config 104, net protocol 31, match state 101)
- Headless smoke (`--smoke-test 70 --fast`): map loads, navmesh 1002 polygons, spawn validation OK, bots buy/fight/kill, rounds end and advance
- Dedicated server + headless client: client connects, receives snapshots, auto-readies, match goes live, replicated players/kills visible on the client
- Rendered under Xvfb (OpenGL3/llvmpipe): in-game HUD + view model, spectator view with kill feed, main menu, lobby, buy menu, asset galleries (docs/images)
- Client vs dedicated server with `--net-sim 120,0.1,40`: no script errors, state and entities replicated
- Two 5-minute bots-only matches (`--spectate --round-time 115`, difficulty 1 and 2): 5 and 7 rounds decided by elimination, time and a plant + detonation, money ranging $200–$10550, no script errors
- Reconnect: client restarted with the same token within the grace period took over its player
