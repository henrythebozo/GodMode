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

	function outcomeProbs(model, x) {
		const o = model.outcome;
		const z = standardise(x, o.mean, o.scale);
		const logits = o.coef.map((row, r) => o.intercept[r] + row.reduce((s, w, i) => s + w * z[i], 0));
		const mx = Math.max.apply(null, logits);
		const e = logits.map((l) => Math.exp(l - mx));
		const sum = e.reduce((a, b) => a + b, 0);
		const p = {};
		o.classes.forEach((c, i) => (p[c] = e[i] / sum));
		return p;
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
		const fv = featureVector(model, home, away, opts);
		const probs = outcomeProbs(model, fv.x);
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

	return { predict: predict, featureVector: featureVector, outcomeProbs: outcomeProbs, expectedGoals: expectedGoals, scoreMatrix: scoreMatrix };
});
