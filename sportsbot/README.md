# Sports analytics bot

A football (soccer) match-prediction bot. It is trained on ~50,000 matches
from six leagues (Premier League, Championship, La Liga, Bundesliga, Serie A,
Ligue 1) since 2005 and runs entirely in the browser on GitHub Pages:
open `index.html` and ask it things like `Arsenal vs Chelsea`,
`table premier league`, `form Liverpool` or `model`.

## What it does

For any fixture between two tracked teams it returns:

* win / draw / loss probabilities and the matching fair odds
* expected goals for each side and the most likely scorelines
* over/under 2.5 and both-teams-to-score probabilities
* both teams' Elo rating, recent form and season record
* head-to-head history

## The three tabs

* **Chat**: ask about fixtures, teams, tables, rankings, head-to-head, or `model`.
* **Tables**: current standings and Elo power rankings for each league.
* **Make the bot better**: a tuning lab, your graded prediction log and a
  roadmap. The trainer exports two seasons the model never learned from
  (2024/25 to tune on, 2025/26 to check on) with the model's raw outputs and
  the bookmaker's probabilities. Three knobs (confidence, draw bias, home
  bias) re-score every match live; "Auto-tune" grid-searches them on the
  tune season and the test column shows whether the gain is real. "Apply"
  saves the knobs in the browser and every prediction uses them. Fixtures
  you ask about are logged and graded once the weekly retrain brings in
  the result.

## How it is trained

`train.py` walks every match in date order and, for each fixture, builds
features **only from matches played before it**:

| feature | description |
| --- | --- |
| `elo_h`, `elo_a`, `elo_diff` | Elo ratings (K=20, margin-of-victory scaled, 60 pt home advantage, 20% regression to the mean each summer; promoted teams inherit the mean rating of the teams that went down) |
| `ppg5`, `ppg10` | points per game over the last 5 / 10 matches |
| `gf10`, `ga10` | goals for / against per game, last 10 |
| `sot10`, `sota10` | shots on target for / against per game, last 10 |
| `sppg`, `sgd` | season-to-date points and goal difference per game |
| `rest` | days since the previous match (capped at 21) |
| `lg_*` | league indicator |

Two models are fitted on those features:

* a multinomial **logistic regression** for home / draw / away
* two **Poisson regressions** for expected home and away goals, which the
  page turns into a scoreline matrix

Regularisation is chosen on the 2024/25 season, the model is evaluated on
the untouched 2025/26 season, and then refitted on everything for export.
`model.json` carries the coefficients, a per-team feature snapshot, league
context, head-to-head records and the evaluation metrics, so the page needs
no server.

## How good is it?

Held-out 2025/26 season, 2,284 matches (lower is better for the first three
columns):

| model | log loss | Brier | RPS | accuracy |
| --- | --- | --- | --- | --- |
| always the base rate | 1.075 | 0.651 | 0.230 | 43.4% |
| Elo difference only | 1.014 | 0.607 | 0.208 | 49.7% |
| gradient boosting (reference) | 1.008 | 0.602 | 0.206 | 50.1% |
| **this model** | **1.006** | **0.602** | **0.206** | **50.4%** |
| bookmaker (Bet365 implied) | 0.995 | 0.594 | 0.202 | 51.6% |

So the bot beats naive baselines comfortably and matches a tuned
gradient-boosting model, but it still trails the betting market, which prices
in injuries, line-ups and news the public result data does not contain. A
50/50 blend with the market does not beat the market either. Treat the
output as analysis, not as a betting edge.

The current numbers are always in `model.json` under `metrics` and in the
page via the `model` command.

## Retraining

```bash
pip install -r sportsbot/requirements.txt
python sportsbot/fetch_data.py --refresh-current   # pull the latest results
python sportsbot/train.py                          # rebuilds model.json
python sportsbot/predict.py "Arsenal" "Chelsea"    # CLI check
```

`.github/workflows/retrain-sportsbot.yml` does the same every Tuesday and
commits the refreshed `model.json`, so the bot keeps up with the season.
Raw CSVs live in `sportsbot/data/` and are not committed.

Data: [football-data.co.uk](https://www.football-data.co.uk/).
