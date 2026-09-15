#!/usr/bin/env python3
"""Train the football match-prediction model and export it to model.json.

Pipeline
--------
1. Load every CSV in data/ (football-data.co.uk format), normalise columns.
2. Walk matches in date order, maintaining per-team Elo ratings, rolling
   form, season-to-date records and rest days. Features for a match are
   computed strictly from matches played BEFORE it (no leakage).
3. Train:
   * multinomial logistic regression -> P(home win), P(draw), P(away win)
   * two Poisson regressions        -> expected home goals, expected away goals
4. Evaluate on a held-out season against baselines, including the
   bookmaker's own implied probabilities (the benchmark that matters).
5. Refit on everything and export coefficients + a per-team feature snapshot
   so the browser page can score any fixture without a server.
"""
import argparse
import glob
import json
import math
import os
from collections import defaultdict, deque
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression, PoissonRegressor
from sklearn.preprocessing import StandardScaler

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "data")
MODEL_PATH = os.path.join(HERE, "model.json")

LEAGUES = ["E0", "E1", "SP1", "D1", "I1", "F1"]
LEAGUE_NAMES = {
    "E0": "Premier League", "E1": "Championship", "SP1": "La Liga",
    "D1": "Bundesliga", "I1": "Serie A", "F1": "Ligue 1",
}

# Elo hyper-parameters
ELO_START = 1500.0
ELO_K = 20.0
ELO_HOME_ADV = 60.0
ELO_SEASON_REGRESS = 0.20      # pull 20% of the way back to 1500 each summer
ELO_UNKNOWN_FALLBACK = 1450.0  # promoted team with no history and no relegated peers

REST_CAP = 21

# football-data.co.uk renamed a few clubs over the years; unify them.
TEAM_ALIASES = {
    "Middlesboro": "Middlesbrough",
    "Man Utd": "Man United",
    "Sheffield Weds": "Sheffield Weds",
    "Nott'm Forest": "Nott'm Forest",
}

CLASSES = ["H", "D", "A"]


# --------------------------------------------------------------------------- #
# loading
# --------------------------------------------------------------------------- #
def load_matches():
    frames = []
    for path in sorted(glob.glob(os.path.join(DATA_DIR, "*.csv"))):
        name = os.path.basename(path)[:-4]
        league, season = name.split("_")
        df = pd.read_csv(path, encoding="latin-1", on_bad_lines="skip")
        df.columns = [c.replace("﻿", "").strip() for c in df.columns]
        need = ["Date", "HomeTeam", "AwayTeam", "FTHG", "FTAG", "FTR"]
        if any(c not in df.columns for c in need):
            print(f"skip {name}: missing columns")
            continue
        df = df.dropna(subset=need)
        df = df[df["FTR"].isin(CLASSES)]
        out = pd.DataFrame({
            "league": league,
            "season": season,
            "date": pd.to_datetime(df["Date"], dayfirst=True, format="mixed", errors="coerce"),
            "home": df["HomeTeam"].astype(str).str.strip().map(lambda t: TEAM_ALIASES.get(t, t)),
            "away": df["AwayTeam"].astype(str).str.strip().map(lambda t: TEAM_ALIASES.get(t, t)),
            "hg": df["FTHG"].astype(int),
            "ag": df["FTAG"].astype(int),
            "result": df["FTR"],
        })
        for src, dst in [("HST", "hst"), ("AST", "ast"), ("HS", "hs"), ("AS", "as_")]:
            out[dst] = pd.to_numeric(df[src], errors="coerce") if src in df.columns else np.nan
        # bookmaker odds: Bet365, falling back to market average columns
        for k in ["H", "D", "A"]:
            col = None
            for cand in [f"B365{k}", f"Avg{k}", f"BbAv{k}"]:
                if cand in df.columns:
                    col = pd.to_numeric(df[cand], errors="coerce")
                    break
            out[f"odds_{k}"] = col if col is not None else np.nan
        frames.append(out)
    m = pd.concat(frames, ignore_index=True)
    m = m.dropna(subset=["date"])
    m = m.sort_values(["date", "league"], kind="stable").reset_index(drop=True)
    return m


# --------------------------------------------------------------------------- #
# sequential feature construction
# --------------------------------------------------------------------------- #
class TeamState:
    __slots__ = ("elo", "recent", "season", "s_pts", "s_gf", "s_ga", "s_p",
                 "s_w", "s_d", "s_l", "last_date", "league", "played")

    def __init__(self):
        self.elo = None
        self.recent = deque(maxlen=10)   # dicts: pts, gf, ga, sot_f, sot_a
        self.season = None
        self.s_pts = self.s_gf = self.s_ga = self.s_p = 0
        self.s_w = self.s_d = self.s_l = 0
        self.last_date = None
        self.league = None
        self.played = 0

    def form(self, n):
        rec = list(self.recent)[-n:]
        if not rec:
            return None
        k = len(rec)
        sot_f = [r["sot_f"] for r in rec if r["sot_f"] is not None]
        sot_a = [r["sot_a"] for r in rec if r["sot_a"] is not None]
        return {
            "ppg": sum(r["pts"] for r in rec) / k,
            "gf": sum(r["gf"] for r in rec) / k,
            "ga": sum(r["ga"] for r in rec) / k,
            "sot_f": (sum(sot_f) / len(sot_f)) if sot_f else None,
            "sot_a": (sum(sot_a) / len(sot_a)) if sot_a else None,
        }


def expected_home(elo_h, elo_a):
    return 1.0 / (1.0 + 10 ** ((elo_a - elo_h - ELO_HOME_ADV) / 400.0))


def team_features(st, date, prefix):
    """Feature dict for one side of a fixture, from state BEFORE the match."""
    f5 = st.form(5) or {"ppg": None, "gf": None, "ga": None}
    f10 = st.form(10) or {"ppg": None, "gf": None, "ga": None, "sot_f": None, "sot_a": None}
    rest = REST_CAP if st.last_date is None else min(REST_CAP, (date - st.last_date).days)
    sp = st.s_p
    return {
        f"elo_{prefix}": st.elo,
        f"ppg5_{prefix}": f5["ppg"],
        f"ppg10_{prefix}": f10["ppg"],
        f"gf10_{prefix}": f10["gf"],
        f"ga10_{prefix}": f10["ga"],
        f"sot10_{prefix}": f10.get("sot_f"),
        f"sota10_{prefix}": f10.get("sot_a"),
        f"sppg_{prefix}": (st.s_pts / sp) if sp else None,
        f"sgd_{prefix}": ((st.s_gf - st.s_ga) / sp) if sp else None,
        f"rest_{prefix}": rest,
        f"played_{prefix}": st.played,
    }


def build_features(matches):
    """Walk matches chronologically; return (feature frame, final team states)."""
    states = defaultdict(TeamState)
    # who is in each (league, season)? used to seed promoted teams' Elo
    members = matches.groupby(["league", "season"]).apply(
        lambda g: set(g["home"]) | set(g["away"]), include_groups=False).to_dict()
    seasons_by_league = {lg: sorted(s for (l, s) in members if l == lg) for lg in LEAGUES}
    league_seeded = set()
    rows = []

    for r in matches.itertuples(index=False):
        key = (r.league, r.season)
        if key not in league_seeded:
            league_seeded.add(key)
            # seed Elo for newcomers to this league this season
            idx = seasons_by_league[r.league].index(r.season)
            prev = members.get((r.league, seasons_by_league[r.league][idx - 1])) if idx > 0 else set()
            gone = [states[t].elo for t in (prev - members[key]) if states[t].elo is not None]
            seed = (sum(gone) / len(gone)) if gone else (ELO_START if idx == 0 else ELO_UNKNOWN_FALLBACK)
            for t in members[key]:
                if states[t].elo is None:
                    states[t].elo = seed

        sh, sa = states[r.home], states[r.away]
        for st in (sh, sa):
            if st.season != r.season:
                if st.season is not None:
                    st.elo = ELO_START + (st.elo - ELO_START) * (1 - ELO_SEASON_REGRESS)
                st.season = r.season
                st.s_pts = st.s_gf = st.s_ga = st.s_p = st.s_w = st.s_d = st.s_l = 0
            st.league = r.league

        feat = {"league": r.league, "season": r.season, "date": r.date,
                "home": r.home, "away": r.away, "hg": r.hg, "ag": r.ag,
                "result": r.result, "odds_H": r.odds_H, "odds_D": r.odds_D, "odds_A": r.odds_A}
        feat.update(team_features(sh, r.date, "h"))
        feat.update(team_features(sa, r.date, "a"))
        rows.append(feat)

        # ---- update state with the result ----
        exp_h = expected_home(sh.elo, sa.elo)
        score_h = 1.0 if r.result == "H" else 0.5 if r.result == "D" else 0.0
        gd = abs(r.hg - r.ag)
        k = ELO_K * (math.sqrt(gd) if gd > 0 else 1.0)
        delta = k * (score_h - exp_h)
        sh.elo += delta
        sa.elo -= delta

        hst = None if pd.isna(r.hst) else float(r.hst)
        ast = None if pd.isna(r.ast) else float(r.ast)
        pts_h = 3 if r.result == "H" else 1 if r.result == "D" else 0
        pts_a = 3 if r.result == "A" else 1 if r.result == "D" else 0
        sh.recent.append({"pts": pts_h, "gf": r.hg, "ga": r.ag, "sot_f": hst, "sot_a": ast})
        sa.recent.append({"pts": pts_a, "gf": r.ag, "ga": r.hg, "sot_f": ast, "sot_a": hst})
        for st, pts, gf, ga in ((sh, pts_h, r.hg, r.ag), (sa, pts_a, r.ag, r.hg)):
            st.s_pts += pts; st.s_gf += gf; st.s_ga += ga; st.s_p += 1
            st.s_w += pts == 3; st.s_d += pts == 1; st.s_l += pts == 0
            st.last_date = r.date
            st.played += 1

    return pd.DataFrame(rows), states


# --------------------------------------------------------------------------- #
# model matrix
# --------------------------------------------------------------------------- #
NUMERIC = [
    "elo_diff", "elo_h", "elo_a",
    "ppg5_h", "ppg5_a", "ppg10_h", "ppg10_a",
    "gf10_h", "ga10_h", "gf10_a", "ga10_a",
    "sot10_h", "sota10_h", "sot10_a", "sota10_a",
    "sppg_h", "sppg_a", "sgd_h", "sgd_a",
    "rest_h", "rest_a",
]
FEATURES = NUMERIC + [f"lg_{lg}" for lg in LEAGUES]


def design(df, fill):
    X = pd.DataFrame(index=df.index)
    X["elo_diff"] = df["elo_h"] - df["elo_a"]
    for c in NUMERIC[1:]:
        X[c] = df[c]
    for lg in LEAGUES:
        X[f"lg_{lg}"] = (df["league"] == lg).astype(float)
    X = X.fillna(value=fill)
    return X[FEATURES].astype(float).values


def fit_fill(df):
    """Column means used to impute missing rolling stats (early-season, no SOT data)."""
    X = pd.DataFrame({"elo_diff": df["elo_h"] - df["elo_a"]})
    for c in NUMERIC[1:]:
        X[c] = df[c]
    return {c: float(X[c].mean()) for c in NUMERIC}


# --------------------------------------------------------------------------- #
# metrics
# --------------------------------------------------------------------------- #
def rps(P, y_idx):
    """Ranked probability score for ordered outcomes H<D<A (lower is better)."""
    O = np.zeros_like(P)
    O[np.arange(len(y_idx)), y_idx] = 1
    cp, co = np.cumsum(P, axis=1), np.cumsum(O, axis=1)
    return float(np.mean(np.sum((cp - co)[:, :-1] ** 2, axis=1) / (P.shape[1] - 1)))


def score(P, y_idx):
    P = np.clip(P, 1e-6, 1)
    P = P / P.sum(axis=1, keepdims=True)
    n = len(y_idx)
    ll = -float(np.mean(np.log(P[np.arange(n), y_idx])))
    O = np.zeros_like(P); O[np.arange(n), y_idx] = 1
    brier = float(np.mean(np.sum((P - O) ** 2, axis=1)))
    acc = float(np.mean(P.argmax(axis=1) == y_idx))
    return {"log_loss": round(ll, 4), "brier": round(brier, 4),
            "rps": round(rps(P, y_idx), 4), "accuracy": round(acc, 4), "n": int(n)}


def bookmaker_probs(df):
    inv = np.stack([1 / df["odds_H"].values, 1 / df["odds_D"].values, 1 / df["odds_A"].values], axis=1)
    return inv / inv.sum(axis=1, keepdims=True)


# --------------------------------------------------------------------------- #
# training
# --------------------------------------------------------------------------- #
def fit_outcome(X, y, C):
    sc = StandardScaler().fit(X)
    lr = LogisticRegression(C=C, max_iter=2000)
    lr.fit(sc.transform(X), y)
    return sc, lr


def fit_goals(X, hg, ag, alpha):
    sc = StandardScaler().fit(X)
    Xs = sc.transform(X)
    ph = PoissonRegressor(alpha=alpha, max_iter=1000).fit(Xs, hg)
    pa = PoissonRegressor(alpha=alpha, max_iter=1000).fit(Xs, ag)
    return sc, ph, pa


def poisson_outcome_probs(lh, la, max_goals=10):
    """P(H), P(D), P(A) from independent Poisson goal models (for comparison)."""
    out = np.zeros((len(lh), 3))
    g = np.arange(max_goals + 1)
    for i, (a, b) in enumerate(zip(lh, la)):
        ph = np.exp(-a) * a ** g / np.array([math.factorial(k) for k in g])
        pa = np.exp(-b) * b ** g / np.array([math.factorial(k) for k in g])
        M = np.outer(ph, pa)
        out[i] = [np.tril(M, -1).sum(), np.trace(M), np.triu(M, 1).sum()]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test-season", default="2526", help="season held out for the honest eval")
    ap.add_argument("--val-season", default="2425", help="season used to pick regularisation")
    ap.add_argument("--burn-in", default="0506", help="first season, used only to warm up Elo")
    ap.add_argument("--min-played", type=int, default=5, help="drop rows where a side has fewer prior matches")
    args = ap.parse_args()

    print("loading…")
    matches = load_matches()
    print(f"{len(matches)} matches, {matches['season'].nunique()} seasons, {matches['league'].nunique()} leagues")

    print("building features (sequential Elo / form)…")
    feats, states = build_features(matches)
    usable = feats[(feats["season"] != args.burn_in)
                   & (feats["played_h"] >= args.min_played)
                   & (feats["played_a"] >= args.min_played)].copy()
    y_all = usable["result"].map({c: i for i, c in enumerate(CLASSES)}).values

    seasons = sorted(usable["season"].unique())
    train_mask = usable["season"].values < args.val_season
    val_mask = usable["season"].values == args.val_season
    test_mask = usable["season"].values == args.test_season
    print(f"train seasons {seasons[0]}–{max(s for s in seasons if s < args.val_season)}: {train_mask.sum()} | "
          f"val {args.val_season}: {val_mask.sum()} | test {args.test_season}: {test_mask.sum()}")

    fill = fit_fill(usable[train_mask])
    X_all = design(usable, fill)

    # ---- pick C on the validation season ----
    best = None
    for C in [0.003, 0.01, 0.03, 0.1, 0.3, 1.0]:
        sc, lr = fit_outcome(X_all[train_mask], y_all[train_mask], C)
        m = score(lr.predict_proba(sc.transform(X_all[val_mask])), y_all[val_mask])
        print(f"  C={C:<6} val log_loss={m['log_loss']} rps={m['rps']}")
        if best is None or m["log_loss"] < best[1]:
            best = (C, m["log_loss"])
    C = best[0]
    best_a = None
    for alpha in [0.01, 0.1, 1.0, 10.0]:
        sc, ph, pa = fit_goals(X_all[train_mask], usable["hg"].values[train_mask], usable["ag"].values[train_mask], alpha)
        Xv = sc.transform(X_all[val_mask])
        dev = -np.mean(np.log(np.clip(poisson_outcome_probs(ph.predict(Xv), pa.predict(Xv)), 1e-9, 1))[np.arange(val_mask.sum()), y_all[val_mask]])
        if best_a is None or dev < best_a[1]:
            best_a = (alpha, dev)
    alpha = best_a[0]
    print(f"chosen C={C}, poisson alpha={alpha}")

    # ---- honest evaluation: train on train+val, test on the held-out season ----
    fit_mask = train_mask | val_mask
    fill = fit_fill(usable[fit_mask])
    X_all = design(usable, fill)
    sc, lr = fit_outcome(X_all[fit_mask], y_all[fit_mask], C)
    Xt = sc.transform(X_all[test_mask]); yt = y_all[test_mask]
    test_df = usable[test_mask]

    metrics = {}
    metrics["model"] = score(lr.predict_proba(Xt), yt)

    gsc, ph, pa = fit_goals(X_all[fit_mask], usable["hg"].values[fit_mask], usable["ag"].values[fit_mask], alpha)
    Xg = gsc.transform(X_all[test_mask])
    lh, la = ph.predict(Xg), pa.predict(Xg)
    metrics["poisson_goals"] = score(poisson_outcome_probs(lh, la), yt)
    metrics["poisson_goals"]["mae_home_goals"] = round(float(np.mean(np.abs(lh - test_df["hg"].values))), 4)
    metrics["poisson_goals"]["mae_away_goals"] = round(float(np.mean(np.abs(la - test_df["ag"].values))), 4)

    # baseline: always the training base rates
    base = np.bincount(y_all[fit_mask], minlength=3) / fit_mask.sum()
    metrics["base_rate"] = score(np.tile(base, (len(yt), 1)), yt)

    # baseline: Elo difference only
    e_sc, e_lr = fit_outcome(X_all[fit_mask][:, :1], y_all[fit_mask], 1.0)
    metrics["elo_only"] = score(e_lr.predict_proba(e_sc.transform(X_all[test_mask][:, :1])), yt)

    # reference: gradient boosting (not exported; is the linear model leaving much on the table?)
    hgb = HistGradientBoostingClassifier(max_iter=300, learning_rate=0.03, max_leaf_nodes=15,
                                         l2_regularization=1.0, random_state=0)
    hgb.fit(X_all[fit_mask], y_all[fit_mask])
    metrics["gradient_boosting_ref"] = score(hgb.predict_proba(X_all[test_mask]), yt)

    # benchmark: bookmaker implied probabilities, on the rows where odds exist
    has_odds = test_df[["odds_H", "odds_D", "odds_A"]].notna().all(axis=1).values
    if has_odds.sum():
        metrics["bookmaker"] = score(bookmaker_probs(test_df[has_odds]), yt[has_odds])
        metrics["model_on_bookmaker_rows"] = score(lr.predict_proba(Xt[has_odds]), yt[has_odds])
        # 50/50 blend of model and market: is our model adding anything the market lacks?
        blend = 0.5 * lr.predict_proba(Xt[has_odds]) + 0.5 * bookmaker_probs(test_df[has_odds])
        metrics["blend_model_bookmaker"] = score(blend, yt[has_odds])

    # ---- out-of-sample rows for the in-browser tuning lab ----
    # tune season: scored by a model that never saw it (train only)
    # test season: scored by the train+val model (same one the metrics above use)
    def eval_rows(mask, lr_, sc_):
        d = usable[mask]
        logits = lr_.decision_function(sc_.transform(X_all[mask]))
        rows = []
        for i, r in enumerate(d.itertuples(index=False)):
            bk = [r.odds_H, r.odds_D, r.odds_A]
            if all(isinstance(v, float) and v == v and v > 1 for v in bk):
                inv = [1 / v for v in bk]; tot = sum(inv); bk = [round(v / tot, 4) for v in inv]
            else:
                bk = None
            rows.append([r.date.strftime("%Y-%m-%d"), r.home, r.away, int(y_all[mask][i]),
                         [round(float(v), 3) for v in logits[i]], bk])
        return rows
    t_sc, t_lr = fit_outcome(X_all[train_mask], y_all[train_mask], C)
    eval_sets = {
        "tune": {"season": f"20{args.val_season[:2]}/{args.val_season[2:]}", "rows": eval_rows(val_mask, t_lr, t_sc)},
        "test": {"season": f"20{args.test_season[:2]}/{args.test_season[2:]}", "rows": eval_rows(test_mask, lr, sc)},
    }

    print("\n=== held-out season", args.test_season, "===")
    for k, v in metrics.items():
        print(f"  {k:<26} " + "  ".join(f"{kk}={vv}" for kk, vv in v.items()))

    # ---- final refit on everything for deployment ----
    fill = fit_fill(usable)
    X_all = design(usable, fill)
    sc, lr = fit_outcome(X_all, y_all, C)
    gsc, ph, pa = fit_goals(X_all, usable["hg"].values, usable["ag"].values, alpha)

    # ---- per-team snapshot so the browser can build the same feature vector ----
    latest_season = matches["season"].max()
    active = matches[matches["season"] >= sorted(matches["season"].unique())[-2]]
    active_teams = set(active["home"]) | set(active["away"])
    now = matches["date"].max()
    latest = matches[matches["season"] == latest_season]
    current_members = set(latest["home"]) | set(latest["away"])
    teams = {}
    for t in sorted(active_teams):
        st = states[t]
        f = team_features(st, now, "x")
        teams[t] = {
            "league": st.league,
            "current": t in current_members,
            "elo": round(st.elo, 1),
            "ppg5": f["ppg5_x"], "ppg10": f["ppg10_x"],
            "gf10": f["gf10_x"], "ga10": f["ga10_x"],
            "sot10": f["sot10_x"], "sota10": f["sota10_x"],
            "sppg": f["sppg_x"], "sgd": f["sgd_x"],
            "last_match": st.last_date.strftime("%Y-%m-%d") if st.last_date is not None else None,
            "season": {"p": st.s_p, "w": st.s_w, "d": st.s_d, "l": st.s_l,
                       "gf": st.s_gf, "ga": st.s_ga, "pts": st.s_pts} if st.season == latest_season
                      else {"p": 0, "w": 0, "d": 0, "l": 0, "gf": 0, "ga": 0, "pts": 0},
            "recent": [f"{r['gf']}-{r['ga']}" for r in list(st.recent)[-5:]],
        }

    # head-to-head: last 6 meetings between currently active pairs
    h2h = {}
    pair_rows = matches[matches["home"].isin(active_teams) & matches["away"].isin(active_teams)]
    for r in pair_rows.itertuples(index=False):
        a, b = sorted([r.home, r.away])
        h2h.setdefault(f"{a}|{b}", []).append([r.date.strftime("%Y-%m-%d"), r.home, int(r.hg), int(r.ag)])
    h2h = {k: v[-6:] for k, v in h2h.items()}

    # league home-advantage context for the UI
    league_stats = {}
    recent5 = usable[usable["season"] >= sorted(usable["season"].unique())[-5]]
    for lg in LEAGUES:
        g = recent5[recent5["league"] == lg]
        league_stats[lg] = {
            "name": LEAGUE_NAMES[lg],
            "home_win": round(float((g["result"] == "H").mean()), 3),
            "draw": round(float((g["result"] == "D").mean()), 3),
            "away_win": round(float((g["result"] == "A").mean()), 3),
            "goals_per_game": round(float((g["hg"] + g["ag"]).mean()), 2),
        }

    model = {
        "meta": {
            "trained_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "data_through": now.strftime("%Y-%m-%d"),
            "n_matches_total": int(len(matches)),
            "n_matches_trained": int(len(usable)),
            "seasons": [f"20{s[:2]}/{s[2:]}" for s in sorted(matches["season"].unique())],
            "leagues": LEAGUE_NAMES,
            "test_season": f"20{args.test_season[:2]}/{args.test_season[2:]}",
            "C": C, "poisson_alpha": alpha,
            "elo": {"k": ELO_K, "home_adv": ELO_HOME_ADV, "season_regress": ELO_SEASON_REGRESS},
            "source": "https://www.football-data.co.uk/",
        },
        "metrics": metrics,
        "features": FEATURES,
        "fill": fill,
        "rest_default": 7,
        "rest_cap": REST_CAP,
        "outcome": {
            "classes": [CLASSES[i] for i in lr.classes_],
            "mean": sc.mean_.tolist(), "scale": sc.scale_.tolist(),
            "coef": lr.coef_.tolist(), "intercept": lr.intercept_.tolist(),
        },
        "goals": {
            "mean": gsc.mean_.tolist(), "scale": gsc.scale_.tolist(),
            "home": {"coef": ph.coef_.tolist(), "intercept": float(ph.intercept_)},
            "away": {"coef": pa.coef_.tolist(), "intercept": float(pa.intercept_)},
        },
        "leagues": league_stats,
        "eval_sets": eval_sets,
        "teams": teams,
        "h2h": h2h,
    }
    with open(MODEL_PATH, "w") as f:
        json.dump(model, f, separators=(",", ":"))
    print(f"\nwrote {MODEL_PATH} ({os.path.getsize(MODEL_PATH) / 1024:.0f} KB), {len(teams)} teams")


if __name__ == "__main__":
    main()
