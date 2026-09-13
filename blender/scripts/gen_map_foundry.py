"""Original bomb-defusal map "Foundry" for Breachline.

The layout is authored as a 60 x 50 grid of 2 m cells (120 m x 100 m). `design()` carves rooms,
corridors, props, catwalks and stairs into the grid; the grid is printed as ASCII for review,
then turned into merged Blender geometry (chunked per 20 m tile for culling) and a JSON layout
file consumed by Godot (spawns, bomb sites, buy zones, callouts, ladders, cover hints, zones).

Coordinates: grid column -> +X (east), grid row -> -Y (row 0 is the north edge), Z up.
Godot import converts to Y-up automatically; the layout JSON is written in Godot space
(x, y_up, z) with z = -blender_y so the loader needs no conversion.

Legend:
  #  wall (4 m)        .  floor            A/D attacker/defender spawn floor
  a/b bomb site floor  =  catwalk (3 m)    ^v<> stairs rising 1 m per cell in that direction
  c crate  C tall crate  x barrier  s sandbag  B barrel  g generator  p pillar  v vent  k console
  F furnace  O silo  K conveyor  L ladder  h low wall  w window wall  l lamp post  P pipe
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402
import bl_common as B  # noqa: E402
import gen_environment_kit as K  # noqa: E402

W, H = 60, 50
CELL = 2.0
WALL_H = 4.0
CATWALK_Z = 3.0

grid = [["#"] * W for _ in range(H)]
callouts = {}   # name -> (x0, y0, x1, y1) inclusive cell rects
spawns = {"attackers": [], "defenders": []}
sites = {}
buy_zones = {}


def carve(x0, y0, x1, y1, ch=".", name=None):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            grid[y][x] = ch
    if name:
        callouts[name] = (x0, y0, x1, y1)


def put(x, y, ch):
    grid[y][x] = ch


def wall(x0, y0, x1, y1):
    carve(x0, y0, x1, y1, "#")


# ---------------------------------------------------------------------------------- the design
def design():
    # --- Defender side (north)
    carve(23, 1, 36, 5, "D", "Admin")                    # defender spawn
    carve(28, 6, 31, 6, ".")                              # admin exit
    carve(4, 7, 55, 9, ".", "Back Hall")                  # rotation corridor behind both sites
    for x in (12, 20, 30, 40, 48):
        put(x, 8, "p")
    # --- Site A "Furnace" (west)
    carve(3, 11, 16, 21, "a", "Furnace")
    carve(6, 10, 8, 10, "a")                              # A back door
    carve(4, 12, 6, 13, "F")                              # furnace prop
    put(10, 14, "C"); put(11, 14, "c"); put(13, 17, "c"); put(9, 18, "x"); put(10, 18, "x")
    put(6, 19, "s"); put(14, 12, "B"); put(15, 12, "B"); put(4, 20, "g")
    # --- Site B "Silo" (east)
    carve(43, 11, 56, 21, "b", "Silo")
    carve(50, 10, 52, 10, "b")                            # B back door
    carve(52, 12, 53, 13, "O")                            # silo prop
    put(45, 14, "c"); put(45, 15, "C"); put(49, 17, "c"); put(47, 19, "x"); put(48, 19, "x")
    put(54, 19, "s"); put(44, 12, "B"); put(50, 20, "v"); put(55, 15, "g")
    # --- Mid "Yard" (centre, contested) with the catwalk ("Heaven") along its north edge
    carve(22, 12, 37, 30, ".", "Yard")
    carve(22, 12, 37, 13, "=", "Heaven")                  # elevated catwalk
    carve(19, 12, 21, 13, ".")                            # stair landing west
    carve(38, 12, 40, 13, ".")                            # stair landing east
    for i, x in enumerate((19, 20, 21)):
        put(x, 12, ">"); put(x, 13, ">")                  # stairs rise eastward onto catwalk
    for i, x in enumerate((40, 39, 38)):
        put(x, 12, "<"); put(x, 13, "<")
    carve(20, 10, 21, 11, ".")                            # west stairs connect to back hall
    carve(38, 10, 39, 11, ".")                            # east stairs connect to back hall
    put(26, 18, "c"); put(27, 18, "C"); put(32, 18, "c"); put(33, 18, "c")
    put(29, 22, "g"); put(24, 24, "x"); put(25, 24, "x"); put(34, 24, "x"); put(35, 24, "x")
    put(29, 26, "p"); put(30, 26, "p"); put(23, 15, "B"); put(36, 15, "B")
    put(28, 29, "s"); put(31, 29, "s")
    put(24, 14, "L"); put(35, 14, "L")                    # ladders from the yard up onto Heaven
    # --- A Short: yard west door -> Furnace
    carve(17, 16, 21, 18, ".", "A Short")
    put(17, 15, "h"); put(17, 19, "h")
    # --- Control Room between yard and B, windows facing B
    carve(38, 16, 42, 20, ".", "Control Room")
    put(40, 17, "k"); put(43, 17, "w"); put(43, 18, "w")   # window wall onto site B
    carve(43, 20, 43, 20, ".")                            # door into B
    carve(37, 17, 37, 18, ".")                            # door from yard
    # --- Long routes
    carve(1, 22, 4, 40, ".", "A Long")
    carve(3, 22, 6, 22, "a")                              # A long entrance
    put(2, 30, "x"); put(3, 34, "B"); put(2, 38, "c")
    carve(55, 22, 58, 40, ".", "Dock")
    carve(53, 22, 56, 22, "b")
    put(57, 30, "x"); put(56, 34, "c"); put(56, 26, "C")
    # --- Flank halls linking long routes to the yard at mid height
    carve(5, 26, 21, 27, ".", "Pipes")
    put(8, 26, "P"); put(12, 26, "P"); put(16, 26, "P"); put(19, 27, "h")
    carve(38, 26, 54, 27, ".", "Conveyor")
    carve(44, 27, 46, 27, "K"); put(50, 26, "c")
    # --- Attacker approach to mid
    carve(27, 31, 32, 41, ".", "Ramp")
    put(28, 33, "x"); put(31, 33, "x"); put(29, 37, "c"); put(30, 37, "c"); put(27, 39, "h"); put(32, 39, "h")
    # --- Attacker spawn "Rail Yard" (south)
    carve(8, 42, 51, 48, "A", "Rail Yard")
    carve(1, 41, 8, 43, ".", "Tunnel")                    # to A long
    carve(51, 41, 58, 43, ".", "Loading")                 # to dock
    for x in (14, 20, 38, 44):
        put(x, 45, "c")
    put(24, 47, "l"); put(35, 47, "l"); put(10, 47, "g")
    # site anchors & buy zones
    sites["A"] = (9, 16)
    sites["B"] = (49, 16)
    buy_zones["attackers"] = callouts["Rail Yard"]
    buy_zones["defenders"] = callouts["Admin"]
    # spawn points (cell coords, facing yaw degrees; 0 = north)
    # attackers face the ramp entrance (cols 27-32, row 41); defenders face their exit (row 6)
    for i in range(10):
        sx, sy = 12 + i * 4, 44 + (i % 2) * 2
        spawns["attackers"].append((sx, sy, yaw_towards(sx, sy, 29.5, 40)))
        dx, dy = 24 + (i % 5) * 3, 2 + (i // 5) * 2
        spawns["defenders"].append((dx, dy, yaw_towards(dx, dy, 29.5, 8)))


def yaw_towards(x, y, tx, ty):
    """Godot yaw (degrees) so that a player at cell (x, y) faces cell (tx, ty). Yaw 0 = north (-Z)."""
    gx, gz = tx - x, ty - y            # grid dx (east), dz (south) == Godot x, z deltas
    return round(math.degrees(math.atan2(-gx, -gz)), 1)


# ---------------------------------------------------------------------------------- helpers
def cell_center(x, y, z=0.0):
    return Vector(((x + 0.5) * CELL, -(y + 0.5) * CELL, z))


def is_wall(x, y):
    return x < 0 or y < 0 or x >= W or y >= H or grid[y][x] == "#"


def is_floor(ch):
    return ch != "#"


def greedy_rects(pred):
    """Merge cells satisfying pred into maximal rectangles (row-major greedy)."""
    used = [[False] * W for _ in range(H)]
    rects = []
    for y in range(H):
        for x in range(W):
            if used[y][x] or not pred(x, y):
                continue
            x1 = x
            while x1 + 1 < W and pred(x1 + 1, y) and not used[y][x1 + 1]:
                x1 += 1
            y1 = y
            while y1 + 1 < H and all(pred(xx, y1 + 1) and not used[y1 + 1][xx] for xx in range(x, x1 + 1)):
                y1 += 1
            for yy in range(y, y1 + 1):
                for xx in range(x, x1 + 1):
                    used[yy][xx] = True
            rects.append((x, y, x1, y1))
    return rects


def rect_box(name, x0, y0, x1, y1, z0, z1, material, col):
    sx = (x1 - x0 + 1) * CELL
    sy = (y1 - y0 + 1) * CELL
    return B.box(name, (sx, sy, z1 - z0), (x0 * CELL + sx / 2, -(y0 * CELL) - sy / 2, (z0 + z1) / 2), material=material, collection=col)


def tile_of(x, y):
    return (int(x // 10), int(y // 10))


def ladder_dir(x, y):
    """Grid direction from a ladder cell to the catwalk cell it climbs onto."""
    for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < W and 0 <= ny < H and grid[ny][nx] == "=":
            return dx, dy
    raise RuntimeError(f"ladder at {x},{y} is not next to a catwalk")


def stairs_info(x, y):
    """Return (direction vector, base height) for a stairs cell by walking back along the run."""
    ch = grid[y][x]
    d = {">": (1, 0), "<": (-1, 0), "^": (0, -1), "v": (0, 1)}[ch]
    k = 0
    cx, cy = x - d[0], y - d[1]
    while 0 <= cx < W and 0 <= cy < H and grid[cy][cx] == ch:
        k += 1
        cx, cy = cx - d[0], cy - d[1]
    return d, float(k)


# ---------------------------------------------------------------------------------- geometry
def build_geometry(col):
    P = K.init_palette()
    chunks = {}   # (kind, tile) -> [objects]

    def add(kind, x, y, obj):
        chunks.setdefault((kind, tile_of(x, y)), []).append(obj)

    # walls (merged rectangles) + occluders for long runs
    occluders = []
    for (x0, y0, x1, y1) in greedy_rects(lambda x, y: grid[y][x] == "#"):
        # skip solid interior blocks that no floor touches (saves geometry)
        touches = any(not is_wall(xx, yy) for yy in range(y0 - 1, y1 + 2) for xx in range(x0 - 1, x1 + 2)
                      if (yy in (y0 - 1, y1 + 1) or xx in (x0 - 1, x1 + 1)))
        if not touches:
            continue
        mat = P["brick"] if (x0 + y0) % 3 == 0 else P["concrete"]
        w = rect_box("wall", x0, y0, x1, y1, 0.0, WALL_H, mat, col)
        add("walls", x0, y0, w)
        if (x1 - x0 + 1) * (y1 - y0 + 1) >= 6:
            o = rect_box("occ", x0, y0, x1, y1, 0.0, WALL_H, None, col)
            o.name = f"wall_{x0}_{y0}-occonly"
            occluders.append(o)
    # floors
    for (x0, y0, x1, y1) in greedy_rects(lambda x, y: grid[y][x] != "#"):
        ch = grid[y0][x0]
        mat = P["floor_metal"] if ch in "=" else (P["concrete_dark"] if ch in "ab" else P["floor"])
        f = rect_box("floor", x0, y0, x1, y1, -0.2, 0.0, mat, col)
        add("floor", x0, y0, f)
        if ch in "ab":   # painted site marker (slightly inset)
            sx = (x1 - x0 + 1) * CELL
            sy = (y1 - y0 + 1) * CELL
            m = B.box("site_paint", (sx * 0.9, sy * 0.9, 0.01), (x0 * CELL + sx / 2, -(y0 * CELL) - sy / 2, 0.005), material=P["hazard"], collection=col)
            add("floor", x0, y0, m)
    # catwalk decks (merged) + railings along edges facing non-catwalk floor
    for (x0, y0, x1, y1) in greedy_rects(lambda x, y: grid[y][x] == "="):
        deck = rect_box("catwalk", x0, y0, x1, y1, CATWALK_Z - 0.12, CATWALK_Z, P["floor_metal"], col)
        add("catwalk", x0, y0, deck)
        sx = (x1 - x0 + 1) * CELL
        sy = (y1 - y0 + 1) * CELL
        beam = B.box("beam", (sx, sy * 0.15, 0.28), (x0 * CELL + sx / 2, -(y0 * CELL) - sy / 2, CATWALK_Z - 0.26), material=P["rust"], collection=col)
        add("catwalk", x0, y0, beam)
    for y in range(H):
        for x in range(W):
            if grid[y][x] != "=":
                continue
            for (dx, dy, rot) in ((0, 1, 0), (0, -1, 0), (1, 0, 90), (-1, 0, 90)):
                nx, ny = x + dx, y + dy
                nch = grid[ny][nx] if 0 <= nx < W and 0 <= ny < H else "#"
                if nch in "=#L" or nch in "<>^v":
                    continue
                r = K.piece_railing(col, CELL, f"railing_{x}_{y}_{dx}_{dy}")
                c = cell_center(x, y, CATWALK_Z)
                r.location = c + Vector((dx * CELL * 0.5, -dy * CELL * 0.5, 0)) + (Vector((-CELL * 0.5, 0, 0)) if rot == 0 else Vector((0, CELL * 0.5, 0)))
                r.rotation_euler = (0, 0, math.radians(-rot))
                add("railings", x, y, r)
            # support pillars under catwalk corners
            if (x + y) % 4 == 0:
                s = B.box("support", (0.25, 0.25, CATWALK_Z - 0.4), cell_center(x, y, (CATWALK_Z - 0.4) / 2), material=P["rust"], collection=col)
                add("catwalk", x, y, s)
    # stairs
    for y in range(H):
        for x in range(W):
            if grid[y][x] in "<>^v":
                (dx, dy), base = stairs_info(x, y)
                st = K.piece_stairs(col, CELL, 1.0, CELL, f"stairs_{x}_{y}")
                ang = {(1, 0): 0, (-1, 0): 180, (0, -1): 90, (0, 1): -90}[(dx, dy)]
                st.rotation_euler = (0, 0, math.radians(ang))
                # piece runs +X from its origin with width along +Y: put the origin at the rotated back-left corner
                c = cell_center(x, y, base)
                st.location = c + Matrix.Rotation(math.radians(ang), 3, "Z") @ Vector((-CELL / 2, -CELL / 2, 0))
                B.sync()
                ramp = [ch for ch in st.children if ch.name.endswith("-colonly")][0]
                ramp_world = ramp.matrix_world.copy()
                ramp.parent = None
                ramp.matrix_world = ramp_world
                ramp.name = f"ramp_{x}_{y}"
                add("stairs_col", x, y, ramp)
                add("stairs", x, y, st)
    # props
    prop_builders = {
        "c": lambda n: K.piece_crate(col, 1.6, n), "C": lambda n: K.piece_crate_tall(col, n),
        "x": lambda n: K.piece_barrier(col, n), "s": lambda n: K.piece_sandbag(col, n),
        "B": lambda n: K.piece_barrel(col, n), "g": lambda n: K.piece_generator(col, n),
        "p": lambda n: K.piece_pillar(col, n), "v": lambda n: K.piece_vent(col, n),
        "k": lambda n: K.piece_control_console(col, n), "l": lambda n: K.piece_lamp_post(col, n),
        "P": lambda n: K.piece_pipe(col, CELL, 0.25, n),
    }
    big_done = set()
    for y in range(H):
        for x in range(W):
            ch = grid[y][x]
            if ch in prop_builders:
                ob = prop_builders[ch](f"prop_{ch}_{x}_{y}")
                ob.location = cell_center(x, y)
                if ch == "P":
                    ob.location += Vector((-CELL / 2, 0, 0.6))
                if ch == "x" and (is_wall(x - 1, y) or is_wall(x + 1, y)):
                    ob.rotation_euler = (0, 0, math.radians(90))
                add("props", x, y, ob)
            elif ch in "FOK" and (x, y) not in big_done:
                # find the connected region and place one big prop at its centroid
                cells = [(xx, yy) for yy in range(H) for xx in range(W) if grid[yy][xx] == ch and abs(xx - x) <= 3 and abs(yy - y) <= 3]
                big_done.update(cells)
                cx = sum(c[0] for c in cells) / len(cells)
                cy = sum(c[1] for c in cells) / len(cells)
                ob = {"F": lambda n: K.piece_furnace(col, n), "O": lambda n: K.piece_silo(col, n),
                      "K": lambda n: K.piece_conveyor(col, len(cells) * CELL, n)}[ch](f"prop_{ch}_{x}_{y}")
                ob.location = Vector(((cx + 0.5) * CELL, -(cy + 0.5) * CELL, 0))
                if ch == "K":
                    ob.location.x -= len(cells) * CELL / 2
                add("props", x, y, ob)
            elif ch == "L":
                dx, dy = ladder_dir(x, y)
                ld = K.piece_ladder(col, CATWALK_Z, f"ladder_{x}_{y}")
                ld.location = cell_center(x, y) + Vector((dx * CELL * 0.42, -dy * CELL * 0.42, 0))
                ld.rotation_euler = (0, 0, math.radians(90 if dy else 0))
                add("props", x, y, ld)
            elif ch == "h":
                along_x = is_wall(x - 1, y) or is_wall(x + 1, y) or grid[y][max(x - 1, 0)] == "h"
                lw = K.piece_wall_low(col, CELL, f"lowwall_{x}_{y}")
                c = cell_center(x, y)
                if along_x:
                    lw.location = c + Vector((-CELL / 2, 0, 0))
                else:
                    lw.rotation_euler = (0, 0, math.radians(90))
                    lw.location = c + Vector((0, -CELL / 2, 0))
                add("props", x, y, lw)
            elif ch == "w":
                along_x = not (is_wall(x, y - 1) or is_wall(x, y + 1))
                ww = K.piece_wall_window(col, CELL, f"window_{x}_{y}")
                c = cell_center(x, y)
                if along_x:
                    ww.location = c + Vector((-CELL / 2, 0, 0))
                else:
                    ww.rotation_euler = (0, 0, math.radians(90))
                    ww.location = c + Vector((0, -CELL / 2, 0))
                add("walls", x, y, ww)
    # lights on ceilings of the covered areas + lamp posts elsewhere handled as props
    lights = []
    for name, (x0, y0, x1, y1) in callouts.items():
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        lights.append({"pos": _godot((cx + 0.5) * CELL, -(cy + 0.5) * CELL, 3.6), "name": name})
        if (x1 - x0) > 8:
            for fx in (x0 + (x1 - x0) * 0.25, x0 + (x1 - x0) * 0.75):
                lights.append({"pos": _godot((fx + 0.5) * CELL, -(cy + 0.5) * CELL, 3.6), "name": name})
    # merge chunks
    merged = []
    for (kind, (tx, ty)), objs in sorted(chunks.items()):
        name = f"{kind}_t{tx}_{ty}"
        if kind == "stairs_col":
            name = f"stairs_ramp_t{tx}_{ty}-colonly"
        elif kind != "stairs":
            name += "-col"
        # bake child collision helpers of kit pieces away (we use trimesh on the merged mesh)
        for o in objs:
            for ch in list(o.children):
                bpy.data.objects.remove(ch, do_unlink=True)
        m = B.join(objs, name)
        if kind == "stairs_col":
            m.data.materials.clear()
            m.display_type = "WIRE"
        B.box_uv(m, 2.0)
        B.apply_transforms(m)
        m["zone"] = f"t{tx}_{ty}"
        merged.append(m)
    for o in occluders:
        B.apply_transforms(o)
        o.data.materials.clear()
    return merged + occluders, lights


def _godot(x, y, z):
    """Blender (x, y, z) Z-up  ->  Godot (x, z, -y) Y-up."""
    return [round(x, 3), round(z, 3), round(-y, 3)]


def build_layout(lights):
    def rect(r):
        x0, y0, x1, y1 = r
        return {"min": _godot(x0 * CELL, -(y1 + 1) * CELL, 0), "max": _godot((x1 + 1) * CELL, -y0 * CELL, 4.0)}

    def fix_rect(d):
        # after conversion min/max z may be swapped
        mn, mx = d["min"], d["max"]
        return {"min": [min(mn[i], mx[i]) for i in range(3)], "max": [max(mn[i], mx[i]) for i in range(3)]}

    layout = {
        "name": "Foundry",
        "cell_size": CELL,
        "size": [W * CELL, H * CELL],
        "spawns": {t: [{"pos": _godot((x + 0.5) * CELL, -(y + 0.5) * CELL, 0.1), "yaw": yaw} for (x, y, yaw) in pts] for t, pts in spawns.items()},
        "sites": {k: {"pos": _godot((x + 0.5) * CELL, -(y + 0.5) * CELL, 0), "radius": 9.0, "callout": "Furnace" if k == "A" else "Silo"} for k, (x, y) in sites.items()},
        "buy_zones": {t: fix_rect(rect(r)) for t, r in buy_zones.items()},
        "callouts": {n: fix_rect(rect(r)) for n, r in callouts.items()},
        "ladders": [], "cover": [], "lights": lights, "zones": {},
        "patrol_points": [],
    }
    for y in range(H):
        for x in range(W):
            ch = grid[y][x]
            if ch == "L":
                dx, dy = ladder_dir(x, y)
                layout["ladders"].append({"pos": _godot((x + 0.5) * CELL + dx * CELL * 0.42, -(y + 0.5) * CELL - dy * CELL * 0.42, 0),
                                          "top": _godot((x + dx + 0.5) * CELL, -(y + dy + 0.5) * CELL, CATWALK_Z),
                                          "height": CATWALK_Z, "climb_dir": [dx, 0, dy]})
            if ch in "cCxsgvkK":
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and grid[ny][nx] in ".abAD":
                        # direction from the standing point towards the object providing cover (Godot space)
                        layout["cover"].append({"pos": _godot((nx + 0.5) * CELL, -(ny + 0.5) * CELL, 0),
                                                "cover_dir": [-dx, 0, -dy],
                                                "height": "low" if ch in "xs" else "high"})
    for name, r in callouts.items():
        x0, y0, x1, y1 = r
        layout["patrol_points"].append({"pos": _godot(((x0 + x1) / 2 + 0.5) * CELL, -((y0 + y1) / 2 + 0.5) * CELL, 0), "callout": name})
        layout["zones"][name] = fix_rect(rect(r))
    return layout


def print_ascii():
    out = []
    for y in range(H):
        out.append("".join(grid[y]))
    return "\n".join(out)


def main():
    design()
    ascii_map = print_ascii()
    print(ascii_map)
    B.reset_scene()
    col = B.ensure_collection("map_foundry")
    objs, lights = build_geometry(col)
    B.validate_scene()
    out_dir = os.path.join(B.GODOT_MODELS, "map")
    B.export_glb(os.path.join(out_dir, "foundry.glb"), objs, animations=False)
    layout = build_layout(lights)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "foundry_layout.json"), "w") as f:
        json.dump(layout, f, indent=1)
    with open(os.path.join(B.ROOT, "docs", "MAP_FOUNDRY.txt"), "w") as f:
        f.write(__doc__ + "\n" + ascii_map + "\n")
    print(f"[layout] {len(layout['cover'])} cover points, {len(layout['ladders'])} ladders, {len(callouts)} callouts")
    B.save_blend("map_foundry.blend")


if __name__ == "__main__":
    main()
