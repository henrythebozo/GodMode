"""Generate all original Breachline audio procedurally (numpy synthesis, no external samples).

    python tools/gen_audio.py

Writes 16-bit mono 44.1 kHz WAVs into breachline/assets/audio/. Every sound is synthesised from
noise, oscillators and envelopes, so the whole audio set is original and re-generatable.
"""
import math
import os
import wave
import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "breachline", "assets", "audio")
rng = np.random.default_rng(1337)


def write(path, data, gain=0.9):
    data = np.asarray(data, dtype=np.float64)
    peak = np.max(np.abs(data)) or 1.0
    data = data / peak * gain
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype(np.int16).tobytes())


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(dur, attack=0.001, decay=0.1, curve=4.0):
    x = t(dur)
    a = np.clip(x / max(attack, 1e-5), 0, 1)
    d = np.exp(-x / decay * curve / 4)
    return a * d


def noise(dur):
    return rng.standard_normal(int(SR * dur))


def lowpass(x, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    alpha = (1 / SR) / (rc + 1 / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def gunshot(dur, body_hz, crack, tail, lp):
    x = t(dur)
    crack_part = noise(dur) * env(dur, 0.0005, 0.02) * crack
    body = np.sin(2 * math.pi * body_hz * x * np.exp(-x * 8)) * env(dur, 0.001, 0.08) * 1.2
    tail_part = lowpass(noise(dur), lp) * env(dur, 0.002, tail) * 0.8
    sig = crack_part + body + tail_part
    return np.tanh(sig * 2.0)


def mix(*parts):
    """Sum signals of different lengths (zero-padded to the longest)."""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def click(dur=0.05, hz=2400):
    return np.sin(2 * math.pi * hz * t(dur)) * env(dur, 0.0005, 0.01) + noise(dur) * env(dur, 0.0005, 0.006) * 0.4


def main():
    # weapons: class -> (dur, body_hz, crack, tail, lowpass)
    classes = {
        "pistol": (0.35, 180, 0.9, 0.12, 3000), "smg": (0.28, 160, 0.8, 0.09, 2600),
        "shotgun": (0.6, 90, 1.0, 0.3, 1800), "rifle": (0.45, 120, 1.0, 0.18, 2400),
        "sniper": (0.9, 70, 1.1, 0.45, 1600), "lmg": (0.5, 100, 1.0, 0.22, 2000),
    }
    for name, params in classes.items():
        write(os.path.join(OUT, "weapons", f"shot_{name}.wav"), gunshot(*params))
        write(os.path.join(OUT, "weapons", f"shot_{name}_distant.wav"), lowpass(gunshot(*params), 600) * env(params[0], 0.01, 0.4))
    write(os.path.join(OUT, "weapons", "dry_fire.wav"), click(0.06, 1800))
    # reload: mag out (click+slide), mag in (thunk), bolt (double click)
    mag_out = np.concatenate([click(0.05, 1200), lowpass(noise(0.15), 900) * env(0.15, 0.002, 0.06)])
    mag_in = np.concatenate([np.zeros(int(SR * 0.02)), lowpass(noise(0.08), 500) * env(0.08, 0.001, 0.03) * 1.5, click(0.04, 900)])
    bolt = np.concatenate([click(0.05, 2600), np.zeros(int(SR * 0.06)), click(0.06, 2100)])
    write(os.path.join(OUT, "weapons", "reload_mag_out.wav"), mag_out)
    write(os.path.join(OUT, "weapons", "reload_mag_in.wav"), mag_in)
    write(os.path.join(OUT, "weapons", "reload_bolt.wav"), bolt)
    write(os.path.join(OUT, "weapons", "draw.wav"), np.concatenate([lowpass(noise(0.12), 1500) * env(0.12, 0.01, 0.05), click(0.04, 2000)]))
    write(os.path.join(OUT, "weapons", "knife_swing.wav"), highpass(noise(0.18), 1200) * env(0.18, 0.02, 0.06))
    write(os.path.join(OUT, "weapons", "knife_hit.wav"), mix(lowpass(noise(0.15), 700) * env(0.15, 0.001, 0.04), click(0.05, 600)))
    write(os.path.join(OUT, "weapons", "shell_drop.wav"), mix(np.sin(2 * math.pi * 5200 * t(0.09)) * env(0.09, 0.0005, 0.02), click(0.03, 4000) * 0.5))
    write(os.path.join(OUT, "weapons", "bullet_impact_concrete.wav"), lowpass(noise(0.12), 2500) * env(0.12, 0.0005, 0.03))
    write(os.path.join(OUT, "weapons", "bullet_impact_metal.wav"), np.sin(2 * math.pi * 3100 * t(0.2)) * env(0.2, 0.0005, 0.06) + noise(0.2) * env(0.2, 0.0005, 0.02) * 0.6)
    write(os.path.join(OUT, "weapons", "bullet_impact_flesh.wav"), lowpass(noise(0.14), 600) * env(0.14, 0.001, 0.05))
    write(os.path.join(OUT, "weapons", "bullet_whiz.wav"), highpass(noise(0.25), 3000) * np.hanning(int(SR * 0.25)))
    write(os.path.join(OUT, "weapons", "headshot_ding.wav"), np.sin(2 * math.pi * 1900 * t(0.35)) * env(0.35, 0.001, 0.12) + np.sin(2 * math.pi * 2850 * t(0.35)) * env(0.35, 0.001, 0.08) * 0.5)
    # footsteps: surface -> (lowpass, tone)
    for surf, (lp, tone) in {"concrete": (1200, 0), "metal": (2500, 380), "wood": (900, 140), "gravel": (2000, 0)}.items():
        for i in range(4):
            dur = 0.16
            sig = lowpass(noise(dur), lp) * env(dur, 0.003, 0.05 + 0.01 * i)
            if tone:
                sig += np.sin(2 * math.pi * (tone + i * 15) * t(dur)) * env(dur, 0.001, 0.05) * 0.4
            write(os.path.join(OUT, "foot", f"step_{surf}_{i}.wav"), sig, 0.6)
        write(os.path.join(OUT, "foot", f"land_{surf}.wav"), lowpass(noise(0.3), lp * 0.6) * env(0.3, 0.002, 0.1) * 1.5)
    write(os.path.join(OUT, "foot", "jump.wav"), lowpass(noise(0.12), 800) * env(0.12, 0.005, 0.05))
    write(os.path.join(OUT, "foot", "ladder.wav"), np.sin(2 * math.pi * 420 * t(0.1)) * env(0.1, 0.001, 0.03) + noise(0.1) * env(0.1, 0.001, 0.01) * 0.3)
    write(os.path.join(OUT, "foot", "fall_damage.wav"), lowpass(noise(0.4), 400) * env(0.4, 0.002, 0.12) * 2)
    # grenades
    x = t(1.4)
    boom = np.sin(2 * math.pi * 45 * x * np.exp(-x * 2)) * env(1.4, 0.002, 0.5) + lowpass(noise(1.4), 900) * env(1.4, 0.001, 0.35) * 1.3 + noise(1.4) * env(1.4, 0.0005, 0.03)
    write(os.path.join(OUT, "grenades", "frag_explode.wav"), np.tanh(boom * 2.5))
    x = t(0.9)
    flash = noise(0.9) * env(0.9, 0.0005, 0.08) * 1.5 + np.sin(2 * math.pi * 2600 * x) * env(0.9, 0.001, 0.4) * 0.6
    write(os.path.join(OUT, "grenades", "flash_pop.wav"), np.tanh(flash * 2))
    write(os.path.join(OUT, "grenades", "flash_ring.wav"), np.sin(2 * math.pi * 3200 * t(2.5)) * np.exp(-t(2.5) * 1.2), 0.5)
    write(os.path.join(OUT, "grenades", "smoke_pop.wav"), mix(lowpass(noise(0.4), 700) * env(0.4, 0.002, 0.1), click(0.05, 700)))
    write(os.path.join(OUT, "grenades", "smoke_loop.wav"), lowpass(noise(3.0), 500) * (0.7 + 0.3 * np.sin(2 * math.pi * 0.5 * t(3.0))), 0.35)
    write(os.path.join(OUT, "grenades", "fire_ignite.wav"), lowpass(noise(0.5), 1500) * env(0.5, 0.01, 0.2) * 1.2 + np.tanh(lowpass(noise(0.5), 300) * env(0.5, 0.001, 0.1) * 4))
    fire = lowpass(noise(3.0), 900) * (0.6 + 0.4 * lowpass(noise(3.0), 8) / (np.max(np.abs(lowpass(noise(3.0), 8))) + 1e-9))
    write(os.path.join(OUT, "grenades", "fire_loop.wav"), fire, 0.5)
    write(os.path.join(OUT, "grenades", "pin_pull.wav"), click(0.06, 3000))
    write(os.path.join(OUT, "grenades", "bounce.wav"), mix(np.sin(2 * math.pi * 900 * t(0.12)) * env(0.12, 0.0005, 0.03), click(0.04, 1500) * 0.5))
    for i in range(3):
        write(os.path.join(OUT, "grenades", f"decoy_shot_{i}.wav"), gunshot(0.3, 150, 0.8, 0.1, 2200) * (0.8 + 0.1 * i))
    # bomb
    write(os.path.join(OUT, "grenades", "bomb_beep.wav"), np.sin(2 * math.pi * 2200 * t(0.08)) * env(0.08, 0.001, 0.04))
    write(os.path.join(OUT, "grenades", "bomb_plant_key.wav"), click(0.04, 2800) * 0.7)
    write(os.path.join(OUT, "grenades", "bomb_planted.wav"), np.concatenate([np.sin(2 * math.pi * 1800 * t(0.1)) * env(0.1, 0.001, 0.05), np.zeros(int(SR * 0.05)), np.sin(2 * math.pi * 1800 * t(0.25)) * env(0.25, 0.001, 0.1)]))
    write(os.path.join(OUT, "grenades", "bomb_defuse_loop.wav"), (np.sin(2 * math.pi * 60 * t(1.0)) * 0.3 + lowpass(noise(1.0), 2000) * 0.15 * (1 + np.sign(np.sin(2 * math.pi * 6 * t(1.0))))), 0.5)
    write(os.path.join(OUT, "grenades", "bomb_defused.wav"), np.concatenate([np.sin(2 * math.pi * 900 * t(0.15)) * env(0.15, 0.001, 0.08), np.sin(2 * math.pi * 1350 * t(0.35)) * env(0.35, 0.001, 0.15)]))
    x = t(3.0)
    big = np.sin(2 * math.pi * 30 * x * np.exp(-x * 1.2)) * env(3.0, 0.002, 1.2) * 1.5 + lowpass(noise(3.0), 600) * env(3.0, 0.001, 0.9) * 1.5 + noise(3.0) * env(3.0, 0.0005, 0.05)
    write(os.path.join(OUT, "grenades", "bomb_explode.wav"), np.tanh(big * 3))
    # UI
    write(os.path.join(OUT, "ui", "click.wav"), click(0.05, 1500) * 0.6)
    write(os.path.join(OUT, "ui", "hover.wav"), np.sin(2 * math.pi * 1100 * t(0.04)) * env(0.04, 0.001, 0.015), 0.3)
    write(os.path.join(OUT, "ui", "buy.wav"), np.concatenate([np.sin(2 * math.pi * 880 * t(0.08)) * env(0.08, 0.001, 0.05), np.sin(2 * math.pi * 1320 * t(0.14)) * env(0.14, 0.001, 0.08)]), 0.5)
    write(os.path.join(OUT, "ui", "deny.wav"), np.sin(2 * math.pi * 220 * t(0.18)) * env(0.18, 0.001, 0.1) * np.sign(np.sin(2 * math.pi * 30 * t(0.18))), 0.5)
    write(os.path.join(OUT, "ui", "hitmarker.wav"), click(0.05, 2200) * 0.8)
    write(os.path.join(OUT, "ui", "kill_confirm.wav"), np.sin(2 * math.pi * 660 * t(0.12)) * env(0.12, 0.001, 0.06) + np.sin(2 * math.pi * 990 * t(0.12)) * env(0.12, 0.02, 0.06))
    write(os.path.join(OUT, "ui", "round_start.wav"), np.concatenate([np.sin(2 * math.pi * f * t(0.2)) * env(0.2, 0.005, 0.12) for f in (523, 659, 784)]), 0.6)
    write(os.path.join(OUT, "ui", "round_win.wav"), np.concatenate([np.sin(2 * math.pi * f * t(0.25)) * env(0.25, 0.005, 0.15) for f in (523, 659, 784, 1046)]), 0.6)
    write(os.path.join(OUT, "ui", "round_lose.wav"), np.concatenate([np.sin(2 * math.pi * f * t(0.3)) * env(0.3, 0.005, 0.2) for f in (392, 349, 311)]), 0.6)
    write(os.path.join(OUT, "ui", "timer_warning.wav"), np.sin(2 * math.pi * 1500 * t(0.1)) * env(0.1, 0.001, 0.05), 0.5)
    write(os.path.join(OUT, "ui", "damage_taken.wav"), lowpass(noise(0.2), 400) * env(0.2, 0.001, 0.08), 0.7)
    write(os.path.join(OUT, "ui", "armor_hit.wav"), np.sin(2 * math.pi * 1400 * t(0.1)) * env(0.1, 0.001, 0.04) + noise(0.1) * env(0.1, 0.001, 0.02) * 0.4, 0.6)
    # announcer stingers (tonal cues used by the announcer hook system; VO can be dropped in later)
    stingers = {"bomb_planted": (440, 330), "bomb_defused": (330, 495), "attackers_win": (392, 523), "defenders_win": (349, 466),
                "match_point": (523, 523), "overtime": (466, 622), "halftime": (392, 392), "last_player": (294, 294), "round_start": (392, 494)}
    for name, (f1, f2) in stingers.items():
        sig = np.concatenate([np.sin(2 * math.pi * f1 * t(0.18)) * env(0.18, 0.005, 0.1), np.sin(2 * math.pi * f2 * t(0.3)) * env(0.3, 0.005, 0.18)])
        sig += np.sin(2 * math.pi * f2 * 0.5 * t(0.48)) * env(0.48, 0.01, 0.2) * 0.4
        write(os.path.join(OUT, "announcer", f"{name}.wav"), sig, 0.6)
    # ambience loops
    x = t(8.0)
    hum = np.sin(2 * math.pi * 50 * x) * 0.4 + np.sin(2 * math.pi * 100 * x) * 0.2 + lowpass(noise(8.0), 250) * 0.5
    write(os.path.join(OUT, "ambient", "foundry_hum.wav"), hum * (0.8 + 0.2 * np.sin(2 * math.pi * 0.2 * x)), 0.35)
    wind = lowpass(noise(8.0), 400) * (0.5 + 0.5 * np.abs(np.sin(2 * math.pi * 0.12 * x + 0.5)))
    write(os.path.join(OUT, "ambient", "wind.wav"), wind, 0.3)
    clank = np.zeros(int(SR * 8.0))
    for pos in (0.7, 2.9, 5.1, 6.8):
        i = int(pos * SR)
        c = np.sin(2 * math.pi * 620 * t(0.5)) * env(0.5, 0.001, 0.2)
        clank[i:i + len(c)] += c
    write(os.path.join(OUT, "ambient", "metal_clanks.wav"), clank, 0.3)
    write(os.path.join(OUT, "ambient", "menu_theme.wav"), sum(np.sin(2 * math.pi * f * t(12.0)) * (0.5 + 0.5 * np.sin(2 * math.pi * (0.07 * k) * t(12.0))) for k, f in enumerate((110, 165, 220, 277))) + lowpass(noise(12.0), 200) * 0.4, 0.3)
    count = sum(len(files) for _, _, files in os.walk(OUT))
    print(f"generated {count} wav files in {OUT}")


if __name__ == "__main__":
    main()
