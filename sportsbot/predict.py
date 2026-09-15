#!/usr/bin/env python3
"""Score a fixture from model.json. Same arithmetic as the web page.

    python predict.py "Arsenal" "Chelsea"            # Arsenal at home
    python predict.py "Arsenal" "Chelsea" --json
"""
import argparse
import json
import math
import os
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))


def load_model(path=os.path.join(HERE, "model.json")):
    with open(path) as f:
        return json.load(f)


def resolve(model, name):
    teams = model["teams"]
    if name in teams:
        return name
    low = name.lower()
    hits = [t for t in teams if t.lower() == low] or [t for t in teams if low in t.lower()]
    if len(hits) == 1:
        return hits[0]
    if not hits:
        sys.exit(f"unknown team: {name!r}")
    sys.exit(f"ambiguous team {name!r}: {hits}")


def side_features(model, team, prefix, on=None):
    t = model["teams"][team]
    fill = model["fill"]
    rest = model["rest_default"]
    if on and t["last_match"]:
        y, mo, d = map(int, t["last_match"].split("-"))
        rest = max(0, min(model["rest_cap"], (on - date(y, mo, d)).days))
    f = {
        f"elo_{prefix}": t["elo"],
        f"ppg5_{prefix}": t["ppg5"], f"ppg10_{prefix}": t["ppg10"],
        f"gf10_{prefix}": t["gf10"], f"ga10_{prefix}": t["ga10"],
        f"sot10_{prefix}": t["sot10"], f"sota10_{prefix}": t["sota10"],
        f"sppg_{prefix}": t["sppg"], f"sgd_{prefix}": t["sgd"],
        f"rest_{prefix}": rest,
    }
    return {k: (fill[k] if v is None else v) for k, v in f.items()}


def feature_vector(model, home, away, league=None, on=None):
    f = {}
    f.update(side_features(model, home, "h", on))
    f.update(side_features(model, away, "a", on))
    f["elo_diff"] = f["elo_h"] - f["elo_a"]
    league = league or model["teams"][home]["league"]
    for lg in model["leagues"]:
        f[f"lg_{lg}"] = 1.0 if lg == league else 0.0
    return [f[name] for name in model["features"]], league


def standardise(x, mean, scale):
    return [(v - m) / s for v, m, s in zip(x, mean, scale)]


def outcome_probs(model, x):
    o = model["outcome"]
    z = standardise(x, o["mean"], o["scale"])
    logits = [b + sum(w * v for w, v in zip(row, z)) for row, b in zip(o["coef"], o["intercept"])]
    mx = max(logits)
    e = [math.exp(l - mx) for l in logits]
    s = sum(e)
    return dict(zip(o["classes"], [v / s for v in e]))


def expected_goals(model, x):
    g = model["goals"]
    z = standardise(x, g["mean"], g["scale"])
    lh = math.exp(g["home"]["intercept"] + sum(w * v for w, v in zip(g["home"]["coef"], z)))
    la = math.exp(g["away"]["intercept"] + sum(w * v for w, v in zip(g["away"]["coef"], z)))
    return lh, la


def score_matrix(lh, la, n=8):
    def pois(lmb, k):
        return math.exp(-lmb) * lmb ** k / math.factorial(k)
    return [[pois(lh, i) * pois(la, j) for j in range(n + 1)] for i in range(n + 1)]


def predict(model, home, away, on=None):
    x, league = feature_vector(model, home, away, on=on)
    p = outcome_probs(model, x)
    lh, la = expected_goals(model, x)
    M = score_matrix(lh, la)
    scores = sorted(((i, j, M[i][j]) for i in range(len(M)) for j in range(len(M))), key=lambda t: -t[2])[:5]
    over25 = 1 - sum(M[i][j] for i in range(len(M)) for j in range(len(M)) if i + j <= 2)
    btts = 1 - sum(M[0]) - sum(M[i][0] for i in range(len(M))) + M[0][0]
    return {
        "home": home, "away": away, "league": league,
        "probs": p, "fair_odds": {k: round(1 / v, 2) for k, v in p.items()},
        "xg": {"home": round(lh, 2), "away": round(la, 2)},
        "top_scores": [{"score": f"{i}-{j}", "p": round(pr, 4)} for i, j, pr in scores],
        "over_2_5": round(over25, 4), "btts": round(btts, 4),
        "elo": {"home": model["teams"][home]["elo"], "away": model["teams"][away]["elo"]},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("home"); ap.add_argument("away")
    ap.add_argument("--on", help="fixture date YYYY-MM-DD (for rest-day features)")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    model = load_model()
    home, away = resolve(model, a.home), resolve(model, a.away)
    on = date.fromisoformat(a.on) if a.on else None
    r = predict(model, home, away, on)
    if a.json:
        print(json.dumps(r, indent=2)); return
    p = r["probs"]
    print(f"{home} (Elo {r['elo']['home']}) vs {away} (Elo {r['elo']['away']})  [{model['leagues'][r['league']]['name']}]")
    print(f"  home win {p['H']:.1%}   draw {p['D']:.1%}   away win {p['A']:.1%}")
    print(f"  expected goals {r['xg']['home']} - {r['xg']['away']}   over 2.5: {r['over_2_5']:.1%}   BTTS: {r['btts']:.1%}")
    print("  likely scores: " + ", ".join(f"{s['score']} ({s['p']:.1%})" for s in r["top_scores"]))


if __name__ == "__main__":
    main()
