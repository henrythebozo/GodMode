"""Generate Godot WeaponConfig .tres resources from one balance table.

    python tools/gen_weapon_data.py

Editing values here and re-running keeps every weapon resource consistent; the .tres files are
also editable directly in the Godot inspector.
"""
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "breachline", "src", "data", "weapons")
FM = {"auto": 0, "semi": 1, "burst": 2, "bolt": 3, "pump": 4, "melee": 5, "throw": 6, "none": 7}

# id: fields
W = {
    # ------------- pistols
    "p9": dict(display_name="P9 Sidearm", category="pistol", slot="secondary", price=0, kill_reward=300, damage=32, armor_penetration=0.55, range_modifier=0.86,
               fire_mode="semi", fire_rate_rpm=400, mag_size=12, reserve_ammo=36, reload_time=2.2, reload_time_empty=2.6, equip_time=0.6, move_speed=5.8,
               spread_base=0.35, inaccuracy_stand=0.9, inaccuracy_crouch=0.6, inaccuracy_move=2.6, inaccuracy_fire=0.9, recoil_recovery_time=0.3, recoil_magnitude=1.2, recoil_seed=11, sound_class="pistol"),
    "kestrel": dict(display_name="Kestrel .45", category="pistol", slot="secondary", price=500, kill_reward=300, damage=38, armor_penetration=0.6, range_modifier=0.84,
                    fire_mode="semi", fire_rate_rpm=340, mag_size=8, reserve_ammo=32, reload_time=2.3, reload_time_empty=2.7, equip_time=0.6, move_speed=5.8,
                    spread_base=0.3, inaccuracy_stand=0.8, inaccuracy_crouch=0.5, inaccuracy_move=2.8, inaccuracy_fire=1.1, recoil_recovery_time=0.32, recoil_magnitude=1.5, recoil_seed=12, sound_class="pistol"),
    "hornet": dict(display_name="Hornet Auto", category="pistol", slot="secondary", price=600, kill_reward=300, damage=22, armor_penetration=0.5, range_modifier=0.8,
                   fire_mode="auto", fire_rate_rpm=800, mag_size=20, reserve_ammo=60, reload_time=2.5, reload_time_empty=2.9, equip_time=0.6, move_speed=5.8,
                   spread_base=0.5, inaccuracy_stand=1.4, inaccuracy_crouch=1.0, inaccuracy_move=3.2, inaccuracy_fire=0.7, recoil_recovery_time=0.35, recoil_magnitude=1.1, recoil_seed=13, sound_class="pistol"),
    "warden": dict(display_name="Warden .357", category="pistol", slot="secondary", price=750, kill_reward=300, damage=70, armor_penetration=0.9, range_modifier=0.92,
                   fire_mode="semi", fire_rate_rpm=150, mag_size=6, reserve_ammo=18, reload_time=3.0, reload_time_empty=3.0, equip_time=0.75, move_speed=5.7,
                   spread_base=0.2, inaccuracy_stand=0.5, inaccuracy_crouch=0.3, inaccuracy_move=4.0, inaccuracy_fire=2.0, recoil_recovery_time=0.5, recoil_magnitude=3.0, recoil_seed=14, sound_class="pistol", head_mult=3.5),
    # ------------- smgs
    "viper": dict(display_name="Viper SMG", category="smg", slot="primary", price=1250, kill_reward=600, damage=27, armor_penetration=0.55, range_modifier=0.82,
                  fire_mode="auto", fire_rate_rpm=860, mag_size=30, reserve_ammo=120, reload_time=2.3, reload_time_empty=2.7, equip_time=0.9, move_speed=5.9,
                  spread_base=0.4, inaccuracy_stand=1.0, inaccuracy_crouch=0.7, inaccuracy_move=2.2, inaccuracy_fire=0.45, recoil_recovery_time=0.35, recoil_magnitude=1.0, recoil_seed=21, sound_class="smg"),
    "reed": dict(display_name="Reed PDW", category="smg", slot="primary", price=1050, kill_reward=600, damage=25, armor_penetration=0.6, range_modifier=0.8,
                 fire_mode="auto", fire_rate_rpm=950, mag_size=25, reserve_ammo=100, reload_time=2.1, reload_time_empty=2.5, equip_time=0.85, move_speed=6.0,
                 spread_base=0.45, inaccuracy_stand=1.1, inaccuracy_crouch=0.8, inaccuracy_move=2.0, inaccuracy_fire=0.4, recoil_recovery_time=0.3, recoil_magnitude=0.9, recoil_seed=22, sound_class="smg"),
    "bulldog": dict(display_name="Bulldog 9", category="smg", slot="primary", price=1700, kill_reward=600, damage=30, armor_penetration=0.65, range_modifier=0.85,
                    fire_mode="auto", fire_rate_rpm=750, mag_size=30, reserve_ammo=120, reload_time=2.6, reload_time_empty=3.0, equip_time=0.95, move_speed=5.7,
                    spread_base=0.35, inaccuracy_stand=0.9, inaccuracy_crouch=0.6, inaccuracy_move=2.4, inaccuracy_fire=0.5, recoil_recovery_time=0.38, recoil_magnitude=1.15, recoil_seed=23, sound_class="smg"),
    # ------------- shotguns
    "breaker": dict(display_name="Breaker Pump", category="shotgun", slot="primary", price=1100, kill_reward=900, damage=26, armor_penetration=0.5, range_modifier=0.6, pellets=9,
                    fire_mode="pump", fire_rate_rpm=70, mag_size=7, reserve_ammo=32, reload_time=0.55, reload_time_empty=0.55, equip_time=1.0, move_speed=5.6,
                    spread_base=3.5, inaccuracy_stand=0.5, inaccuracy_crouch=0.3, inaccuracy_move=1.5, inaccuracy_fire=1.0, recoil_recovery_time=0.5, recoil_magnitude=4.0, recoil_seed=31, sound_class="shotgun", max_range=60, head_mult=2.5),
    "salvo": dict(display_name="Salvo Auto", category="shotgun", slot="primary", price=1800, kill_reward=900, damage=17, armor_penetration=0.5, range_modifier=0.62, pellets=8,
                  fire_mode="auto", fire_rate_rpm=240, mag_size=8, reserve_ammo=32, reload_time=3.2, reload_time_empty=3.6, equip_time=1.0, move_speed=5.5,
                  spread_base=4.2, inaccuracy_stand=0.6, inaccuracy_crouch=0.4, inaccuracy_move=1.6, inaccuracy_fire=1.4, recoil_recovery_time=0.45, recoil_magnitude=3.0, recoil_seed=32, sound_class="shotgun", max_range=55, head_mult=2.5),
    # ------------- rifles
    "corsair": dict(display_name="Corsair AR", category="rifle", slot="primary", team="attackers", price=2700, kill_reward=300, damage=36, armor_penetration=0.78, range_modifier=0.9,
                    fire_mode="auto", fire_rate_rpm=600, mag_size=30, reserve_ammo=90, reload_time=2.4, reload_time_empty=2.9, equip_time=1.0, move_speed=5.4,
                    spread_base=0.22, inaccuracy_stand=0.55, inaccuracy_crouch=0.35, inaccuracy_move=3.6, inaccuracy_fire=0.55, recoil_recovery_time=0.45, recoil_magnitude=1.7, recoil_seed=41, sound_class="rifle"),
    "lynx": dict(display_name="Lynx Carbine", category="rifle", slot="primary", team="defenders", price=3100, kill_reward=300, damage=33, armor_penetration=0.72, range_modifier=0.92,
                 fire_mode="auto", fire_rate_rpm=660, mag_size=30, reserve_ammo=90, reload_time=2.3, reload_time_empty=2.8, equip_time=1.0, move_speed=5.4,
                 spread_base=0.2, inaccuracy_stand=0.5, inaccuracy_crouch=0.3, inaccuracy_move=3.4, inaccuracy_fire=0.5, recoil_recovery_time=0.42, recoil_magnitude=1.5, recoil_seed=42, sound_class="rifle", zoom_levels=[1.6]),
    "falcon": dict(display_name="Falcon Burst", category="rifle", slot="primary", team="defenders", price=2900, kill_reward=300, damage=34, armor_penetration=0.75, range_modifier=0.92,
                   fire_mode="burst", fire_rate_rpm=900, burst_count=3, burst_delay=0.28, mag_size=30, reserve_ammo=90, reload_time=2.5, reload_time_empty=3.0, equip_time=1.0, move_speed=5.35,
                   spread_base=0.2, inaccuracy_stand=0.5, inaccuracy_crouch=0.3, inaccuracy_move=3.6, inaccuracy_fire=0.5, recoil_recovery_time=0.4, recoil_magnitude=1.3, recoil_seed=43, sound_class="rifle", zoom_levels=[1.6]),
    "raptor": dict(display_name="Raptor DMR", category="rifle", slot="primary", price=3300, kill_reward=300, damage=52, armor_penetration=0.85, range_modifier=0.95,
                   fire_mode="semi", fire_rate_rpm=300, mag_size=20, reserve_ammo=80, reload_time=2.8, reload_time_empty=3.2, equip_time=1.1, move_speed=5.2,
                   spread_base=0.15, inaccuracy_stand=0.4, inaccuracy_crouch=0.25, inaccuracy_move=4.5, inaccuracy_fire=1.4, recoil_recovery_time=0.5, recoil_magnitude=2.4, recoil_seed=44, sound_class="rifle", zoom_levels=[2.5]),
    # ------------- snipers
    "longbow": dict(display_name="Longbow BA", category="sniper", slot="primary", price=4750, kill_reward=100, damage=115, armor_penetration=0.98, range_modifier=0.99,
                    fire_mode="bolt", fire_rate_rpm=41, mag_size=10, reserve_ammo=30, reload_time=3.6, reload_time_empty=3.6, equip_time=1.25, move_speed=4.9,
                    spread_base=0.1, inaccuracy_stand=8.0, inaccuracy_crouch=6.0, inaccuracy_move=20.0, inaccuracy_fire=4.0, recoil_recovery_time=0.6, recoil_magnitude=5.0, recoil_seed=51, sound_class="sniper", zoom_levels=[4.0, 8.0], head_mult=4.0, leg_mult=0.75),
    "marksman": dict(display_name="Marksman SR", category="sniper", slot="primary", price=4200, kill_reward=100, damage=78, armor_penetration=0.9, range_modifier=0.97,
                     fire_mode="semi", fire_rate_rpm=240, mag_size=10, reserve_ammo=40, reload_time=3.1, reload_time_empty=3.1, equip_time=1.2, move_speed=5.0,
                     spread_base=0.12, inaccuracy_stand=6.0, inaccuracy_crouch=4.5, inaccuracy_move=16.0, inaccuracy_fire=2.5, recoil_recovery_time=0.55, recoil_magnitude=3.2, recoil_seed=52, sound_class="sniper", zoom_levels=[3.0, 6.0]),
    # ------------- lmg
    "anvil": dict(display_name="Anvil LMG", category="lmg", slot="primary", price=5200, kill_reward=300, damage=35, armor_penetration=0.8, range_modifier=0.9,
                  fire_mode="auto", fire_rate_rpm=750, mag_size=100, reserve_ammo=200, reload_time=5.5, reload_time_empty=5.5, equip_time=1.4, move_speed=4.8,
                  spread_base=0.4, inaccuracy_stand=1.2, inaccuracy_crouch=0.6, inaccuracy_move=5.0, inaccuracy_fire=0.45, recoil_recovery_time=0.5, recoil_magnitude=1.9, recoil_seed=61, sound_class="lmg"),
    # ------------- melee
    "knife": dict(display_name="Combat Knife", category="melee", slot="melee", price=0, kill_reward=1500, fire_mode="melee", fire_rate_rpm=150, mag_size=1, reserve_ammo=0,
                  equip_time=0.5, move_speed=6.2, melee_range=1.7, melee_damage_light=40, melee_damage_heavy=65, backstab_mult=3.0, sound_class="knife", tracer=False, ejects_shells=False),
    # ------------- grenades
    "frag": dict(display_name="Frag Grenade", category="grenade", slot="grenade", price=300, kill_reward=300, fire_mode="throw", equip_time=0.7, move_speed=6.0,
                 throw_speed=24, fuse_time=1.8, effect_radius=8.0, effect_power=98.0, max_carry=1, damage=98, armor_penetration=0.6, sound_class="grenade", tracer=False, ejects_shells=False),
    "flash": dict(display_name="Flash Grenade", category="grenade", slot="grenade", price=200, kill_reward=300, fire_mode="throw", equip_time=0.7, move_speed=6.0,
                  throw_speed=24, fuse_time=1.6, effect_radius=18.0, effect_duration=4.5, effect_power=1.0, max_carry=2, sound_class="grenade", tracer=False, ejects_shells=False),
    "smoke": dict(display_name="Smoke Grenade", category="grenade", slot="grenade", price=300, kill_reward=300, fire_mode="throw", equip_time=0.7, move_speed=6.0,
                  throw_speed=24, fuse_time=1.2, effect_radius=4.0, effect_duration=16.0, max_carry=1, sound_class="grenade", tracer=False, ejects_shells=False),
    "incendiary": dict(display_name="Thermite Charge", category="grenade", slot="grenade", price=500, kill_reward=300, fire_mode="throw", equip_time=0.7, move_speed=6.0,
                       throw_speed=22, fuse_time=1.5, effect_radius=4.5, effect_duration=7.0, effect_power=10.0, max_carry=1, damage=10, armor_penetration=0.9, sound_class="grenade", tracer=False, ejects_shells=False),
    "decoy": dict(display_name="Decoy Grenade", category="grenade", slot="grenade", price=50, kill_reward=300, fire_mode="throw", equip_time=0.7, move_speed=6.0,
                  throw_speed=24, fuse_time=1.0, effect_radius=1.0, effect_duration=14.0, max_carry=1, sound_class="grenade", tracer=False, ejects_shells=False),
    # ------------- objective
    "bomb": dict(display_name="Demolition Charge", category="objective", slot="bomb", team="attackers", price=0, kill_reward=0, fire_mode="none", equip_time=0.8, move_speed=6.0,
                 sound_class="none", tracer=False, ejects_shells=False),
    "defuse_kit": dict(display_name="Defusal Kit", category="objective", slot="kit", team="defenders", price=400, kill_reward=0, fire_mode="none", equip_time=0.1, move_speed=6.0,
                       sound_class="none", tracer=False, ejects_shells=False),
}


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(float(v))
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, list):
        return "PackedFloat32Array(%s)" % ", ".join(repr(float(x)) for x in v)
    raise TypeError(v)


def main():
    os.makedirs(OUT, exist_ok=True)
    for wid, f in W.items():
        f = dict(f)
        f["id"] = wid
        f["model"] = "res://assets/models/weapons/%s.glb" % wid
        f["fire_mode"] = FM[f["fire_mode"]]
        lines = ['[gd_resource type="Resource" script_class="WeaponConfig" load_steps=2 format=3]', "",
                 '[ext_resource type="Script" path="res://src/weapons/WeaponConfig.gd" id="1"]', "", "[resource]", 'script = ExtResource("1")']
        for k in sorted(f):
            v = f[k]
            if k in ("damage", "armor_penetration", "range_modifier", "max_range", "head_mult", "chest_mult", "stomach_mult", "arm_mult", "leg_mult",
                     "fire_rate_rpm", "burst_delay", "reload_time", "reload_time_empty", "equip_time", "first_fire_delay", "move_speed", "spread_base",
                     "inaccuracy_stand", "inaccuracy_crouch", "inaccuracy_move", "inaccuracy_jump", "inaccuracy_ladder", "inaccuracy_fire", "recoil_recovery_time",
                     "move_inaccuracy_speed", "recoil_magnitude", "recoil_camera_ratio", "view_kick", "melee_range", "melee_damage_light", "melee_damage_heavy",
                     "backstab_mult", "melee_heavy_delay", "throw_speed", "fuse_time", "effect_radius", "effect_duration", "effect_power"):
                v = float(v)
            lines.append("%s = %s" % (k, fmt(v)))
        with open(os.path.join(OUT, wid + ".tres"), "w") as fh:
            fh.write("\n".join(lines) + "\n")
    print("wrote %d weapon resources to %s" % (len(W), OUT))


if __name__ == "__main__":
    main()
