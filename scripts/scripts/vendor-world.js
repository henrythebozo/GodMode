/**
 * Rebuilds docs/vendor/ — the two third-party libraries the World page loads.
 *
 * They are committed rather than pulled from a CDN because the page holds API
 * keys in localStorage: nothing it runs should be fetched from someone else's
 * server at load time.
 *
 * Usage: npm run vendor:world   (needs network access to the npm registry)
 * To upgrade a library, change its version below and run this again.
 */
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const VERSIONS = {
	three: '0.187.0',
	'@anthropic-ai/sdk': '1.7.0',
	esbuild: '0.28.2',
};

const BUNDLES = [
	{
		out: 'three.min.js',
		banner: `three.js ${VERSIONS.three} with OrbitControls | MIT | https://threejs.org`,
		entry: [
			"export * from 'three';",
			"export { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';",
		],
	},
	{
		out: 'anthropic-sdk.min.js',
		banner: `@anthropic-ai/sdk ${VERSIONS['@anthropic-ai/sdk']} | MIT | https://github.com/anthropics/anthropic-sdk-typescript`,
		entry: [
			"export { default } from '@anthropic-ai/sdk';",
			"export * from '@anthropic-ai/sdk';",
		],
	},
];

const OUT = path.join(__dirname, '..', '..', 'docs', 'vendor');
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'vendor-world-'));

try {
	fs.writeFileSync(
		path.join(work, 'package.json'),
		JSON.stringify({ private: true, dependencies: VERSIONS }),
	);
	execFileSync('npm', ['install', '--no-audit', '--no-fund', '--silent'], {
		cwd: work,
		stdio: 'inherit',
	});
	const esbuild = require(path.join(work, 'node_modules', 'esbuild'));
	fs.mkdirSync(OUT, { recursive: true });
	for (const bundle of BUNDLES) {
		const entry = path.join(work, 'entry-' + bundle.out);
		fs.writeFileSync(entry, bundle.entry.join('\n') + '\n');
		esbuild.buildSync({
			entryPoints: [entry],
			outfile: path.join(OUT, bundle.out),
			bundle: true,
			format: 'esm',
			platform: 'browser',
			target: 'es2020',
			minify: true,
			legalComments: 'none',
			banner: { js: `/*! ${bundle.banner} */` },
		});
		const kb = Math.round(fs.statSync(path.join(OUT, bundle.out)).size / 1024);
		console.log(`  docs/vendor/${bundle.out}  ${kb} KB`);
	}
} finally {
	fs.rmSync(work, { recursive: true, force: true });
}
