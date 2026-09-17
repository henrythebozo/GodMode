# Setup

## Requirements

* **Godot 4.4.x** (standard build; the Compatibility renderer works on llvmpipe, Forward+ on real GPUs).
  Download from https://godotengine.org/download — no export templates needed to play from the editor.
* **Blender 4.2+** only if you want to regenerate assets. Alternatively `pip install bpy==4.2.0`
  (Python 3.11) runs every generator without the Blender GUI.
* Python 3 + numpy for the audio and weapon-data generators (`tools/`).

## Playing

1. Open Godot, *Import* `breachline/project.godot`, press Play (F5), or run `godot --path breachline`.
2. The first import takes ~1 minute (GLB import + shader compilation).
3. Main menu → **PLAY WITH BOTS**: hosts a local listen server, fills both teams with bots and opens the
   lobby. Press **READY** or **START MATCH**.
4. **HOST MATCH** hosts on the port from Settings → Network (default 27015) and waits in the lobby.
   Friends on the LAN see it in the main menu's auto-discovered server list; others type the IP.

## Browser build (localhost or GitHub Pages)

A Web export lives in `play/`. It is bots-only (browsers cannot open the ENet sockets used for
online play) but the full match loop, buy menu, settings and bots work.

```
./serve_web.sh            # then open http://localhost:8080/play/
./serve_web.sh 9000       # custom port
```

Hosted copy (GitHub Pages, this branch): https://henrythebozo.github.io/GodMode/play/

Rebuild it after code or asset changes (needs the Godot export templates installed once via
Editor → Manage Export Templates, or the `.tpz` unpacked into `~/.local/share/godot/export_templates/4.4.1.stable/`):

```
godot --headless --path breachline --export-release Web ../play/index.html
```

Click the canvas once so the game can capture the mouse; Esc releases it. The export uses the
no-threads template so it runs from any static host without cross-origin isolation headers.

## Command line

```
godot --path breachline -- --connect IP:PORT          # join a server directly
godot --headless --path breachline -- --server --port 27015 --map foundry --bots 8 [--autostart]
godot --headless --path breachline -- --smoke-test 60 --fast    # run a bot match for 60 s, print a report
godot --headless --path breachline -s tests/run_tests.gd       # unit/integration tests
server/run_server.sh --bots 8                                    # dedicated server helper (Linux/macOS)
server\run_server.bat --bots 8                                   # Windows
```

Arguments after `--` go to the game; `--fast` shortens the timers for testing, `--round-time N`,
`--bot-difficulty 0..3`, `--screenshot PATH` (with `--smoke-test` or `--screenshot-delay S`).

## Regenerating assets

```
python -m venv .venv && .venv/bin/pip install bpy==4.2.0 numpy   # or use a desktop Blender
python blender/scripts/export_all.py           # weapons, characters, environment kit, map (~10 s)
python tools/gen_audio.py                      # 91 original WAV files
python tools/gen_weapon_data.py                # weapon .tres resources from the balance table
godot --headless --path breachline --import    # IMPORTANT: re-import so Godot picks up the new GLBs
```

Godot only re-imports changed GLBs when the editor is open or `--import` is run; the game itself
uses the cached import in `breachline/.godot/` (ignored by git). See docs/BLENDER_PIPELINE.md.

## Headless / CI verification used during development

```
godot --headless --path breachline -s tests/run_tests.gd
godot --headless --path breachline -- --smoke-test 60 --fast
xvfb-run -a godot --path breachline --rendering-driver opengl3 -s tools/render_gallery.gd -- --out ../docs/images
```
