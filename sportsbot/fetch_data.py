#!/usr/bin/env python3
"""Download historical match results from football-data.co.uk.

Pulls one CSV per league per season into sportsbot/data/. Files already on
disk are skipped unless --refresh is passed (use --refresh for the current
season, which grows every week).
"""
import argparse
import os
import sys
import time

import requests

BASE = "https://www.football-data.co.uk/mmz4281/{season}/{league}.csv"
HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "data")

LEAGUES = {
    "E0": "Premier League",
    "E1": "Championship",
    "SP1": "La Liga",
    "D1": "Bundesliga",
    "I1": "Serie A",
    "F1": "Ligue 1",
}


def season_codes(first=2005, last=2026):
    """2005 -> '0506', ..., 2026 -> '2627'."""
    return [f"{y % 100:02d}{(y + 1) % 100:02d}" for y in range(first, last + 1)]


def fetch(season, league, refresh=False):
    path = os.path.join(DATA_DIR, f"{league}_{season}.csv")
    if os.path.exists(path) and not refresh:
        return "cached"
    url = BASE.format(season=season, league=league)
    for attempt in range(4):
        try:
            r = requests.get(url, timeout=30)
            if r.status_code == 404:
                return "missing"
            r.raise_for_status()
            if len(r.content) < 500:
                return "empty"
            with open(path, "wb") as f:
                f.write(r.content)
            return "downloaded"
        except requests.RequestException as e:
            if attempt == 3:
                return f"error: {e}"
            time.sleep(2 ** attempt)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--first", type=int, default=2005)
    ap.add_argument("--last", type=int, default=2026)
    ap.add_argument("--leagues", default=",".join(LEAGUES))
    ap.add_argument("--refresh-current", action="store_true",
                    help="re-download the most recent season even if cached")
    args = ap.parse_args()

    os.makedirs(DATA_DIR, exist_ok=True)
    codes = season_codes(args.first, args.last)
    leagues = args.leagues.split(",")
    bad = 0
    for season in codes:
        for league in leagues:
            refresh = args.refresh_current and season == codes[-1]
            status = fetch(season, league, refresh)
            print(f"{league} {season}: {status}")
            if status.startswith("error"):
                bad += 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
