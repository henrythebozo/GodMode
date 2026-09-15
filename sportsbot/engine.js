/* Scoring engine for the sports bot. Mirrors predict.py exactly.
   Works in the browser (window.SportsEngine) and in Node (module.exports). */
(function (root, factory) {
	if (typeof module === "object" && module.exports) module.exports = factory();
	else root.SportsEngine = factory();
})(typeof self !== "undefined" ? self : this, function () {
	"use strict";

	function sideFeatures(model, team, prefix, onDate) {
		const t = model.teams[team];
		const fill = model.fill;
		let rest = model.rest_default;
		if (onDate && t.last_match) {
			const last = new Date(t.last_match + "T00:00:00Z");
			const days = Math.round((onDate - last) / 86400000);
			rest = Math.max(0, Math.min(model.rest_cap, days));
		}
		const raw = {
			elo: t.elo, ppg5: t.ppg5, ppg10: t.ppg10, gf10: t.gf10, ga10: t.ga10,
			sot10: t.sot10, sota10: t.sota10, sppg: t.sppg, sgd: t.sgd, rest: rest,
		};
		const out = {};
		for (const k in raw) {
			const name = k + "_" + prefix;
			out[name] = raw[k] == null ? fill[name] : raw[k];
		}
		return out;
	}

	function featureVector(model, home, away, opts) {
		opts = opts || {};
		const f = Object.assign({}, sideFeatures(model, home, "h", opts.on), sideFeatures(model, away, "a", opts.on));
		f.elo_diff = f.elo_h - f.elo_a;
		const league = opts.league || model.teams[home].league;
		for (const lg in model.leagues) f["lg_" + lg] = lg === league ? 1 : 0;
		return { x: model.features.map((n) => f[n]), league: league };
	}

	function standardise(x, mean, scale) {
		return x.map((v, i) => (v - mean[i]) / scale[i]);
	}

	function outcomeLogits(model, x) {
		const o = model.outcome;
		const z = standardise(x, o.mean, o.scale);
		return o.coef.map((row, r) => o.intercept[r] + row.reduce((s, w, i) => s + w * z[i], 0));
	}

	// knobs: {temp, draw, home}. temp > 1 flattens, draw/home shift the draw/home logits.
	const DEFAULT_KNOBS = { temp: 1, draw: 0, home: 0 };
	function probsFromLogits(logits, classes, knobs) {
		const k = Object.assign({}, DEFAULT_KNOBS, knobs || {});
		const adj = logits.map((l, i) => l / k.temp + (classes[i] === "D" ? k.draw : classes[i] === "H" ? k.home : 0));
		const mx = Math.max.apply(null, adj);
		const e = adj.map((l) => Math.exp(l - mx));
		const sum = e.reduce((a, b) => a + b, 0);
		const p = {};
		classes.forEach((c, i) => (p[c] = e[i] / sum));
		return p;
	}

	function outcomeProbs(model, x, knobs) {
		return probsFromLogits(outcomeLogits(model, x), model.outcome.classes, knobs);
	}

	// rows: [date, home, away, y(0=H,1=D,2=A), logits[3], bookmaker[3]|null]
	function scoreProbs(P, y) {
		let ll = 0, brier = 0, rps = 0, acc = 0;
		for (let i = 0; i < P.length; i++) {
			const p = P[i], o = [0, 0, 0]; o[y[i]] = 1;
			ll += -Math.log(Math.max(p[y[i]], 1e-9));
			brier += (p[0] - o[0]) ** 2 + (p[1] - o[1]) ** 2 + (p[2] - o[2]) ** 2;
			const c1 = p[0] - o[0], c2 = p[0] + p[1] - o[0] - o[1];
			rps += (c1 * c1 + c2 * c2) / 2;
			const best = p[0] >= p[1] && p[0] >= p[2] ? 0 : p[1] >= p[2] ? 1 : 2;
			acc += best === y[i] ? 1 : 0;
		}
		const n = P.length || 1;
		return { log_loss: ll / n, brier: brier / n, rps: rps / n, accuracy: acc / n, n: P.length };
	}

	function evaluate(rows, knobs, classes) {
		classes = classes || ["H", "D", "A"];
		const P = rows.map((r) => { const p = probsFromLogits(r[4], classes, knobs); return classes.map((c) => p[c]); });
		return scoreProbs(P, rows.map((r) => r[3]));
	}

	function evaluateBookmaker(rows) {
		const keep = rows.filter((r) => r[5]);
		return scoreProbs(keep.map((r) => r[5]), keep.map((r) => r[3]));
	}

	function autoTune(rows, classes) {
		const trial = (t, d, h) => ({ temp: +t.toFixed(3), draw: +d.toFixed(3), home: +h.toFixed(3) });
		let best = { knobs: Object.assign({}, DEFAULT_KNOBS), score: evaluate(rows, DEFAULT_KNOBS, classes).log_loss };
		const search = (center, span, step) => {
			for (let t = center.temp - span; t <= center.temp + span + 1e-9; t += step) {
				if (t < 0.5) continue;
				for (let d = center.draw - span; d <= center.draw + span + 1e-9; d += step) {
					for (let h = center.home - span; h <= center.home + span + 1e-9; h += step) {
						const k = trial(t, d, h);
						const s = evaluate(rows, k, classes).log_loss;
						if (s < best.score - 1e-9) best = { knobs: k, score: s };
					}
				}
			}
		};
		search(DEFAULT_KNOBS, 0.4, 0.1);                 // coarse: 9 x 9 x 9
		search(best.knobs, 0.1, 0.02);                   // fine, around the coarse optimum (slider-representable)
		return best;
	}

	function expectedGoals(model, x) {
		const g = model.goals;
		const z = standardise(x, g.mean, g.scale);
		const lin = (m) => m.intercept + m.coef.reduce((s, w, i) => s + w * z[i], 0);
		return { home: Math.exp(lin(g.home)), away: Math.exp(lin(g.away)) };
	}

	function poisson(lambda, k) {
		let f = 1;
		for (let i = 2; i <= k; i++) f *= i;
		return (Math.exp(-lambda) * Math.pow(lambda, k)) / f;
	}

	function scoreMatrix(lh, la, n) {
		n = n || 8;
		const M = [];
		for (let i = 0; i <= n; i++) {
			M.push([]);
			for (let j = 0; j <= n; j++) M[i].push(poisson(lh, i) * poisson(la, j));
		}
		return M;
	}

	function predict(model, home, away, opts) {
		opts = opts || {};
		const fv = featureVector(model, home, away, opts);
		const probs = outcomeProbs(model, fv.x, opts.knobs);
		const xg = expectedGoals(model, fv.x);
		const M = scoreMatrix(xg.home, xg.away);
		const n = M.length;
		const scores = [];
		let under25 = 0, noBtts = 0;
		for (let i = 0; i < n; i++) {
			for (let j = 0; j < n; j++) {
				scores.push({ score: i + "-" + j, p: M[i][j] });
				if (i + j <= 2) under25 += M[i][j];
				if (i === 0 || j === 0) noBtts += M[i][j];
			}
		}
		scores.sort((a, b) => b.p - a.p);
		const fair = {};
		for (const k in probs) fair[k] = 1 / probs[k];
		return {
			home: home, away: away, league: fv.league,
			probs: probs, fair_odds: fair, xg: xg,
			top_scores: scores.slice(0, 5),
			over_2_5: 1 - under25, btts: 1 - noBtts,
			elo: { home: model.teams[home].elo, away: model.teams[away].elo },
		};
	}

	return { predict: predict, featureVector: featureVector, outcomeProbs: outcomeProbs, outcomeLogits: outcomeLogits,
		probsFromLogits: probsFromLogits, expectedGoals: expectedGoals, scoreMatrix: scoreMatrix,
		evaluate: evaluate, evaluateBookmaker: evaluateBookmaker, autoTune: autoTune, DEFAULT_KNOBS: DEFAULT_KNOBS };
});
