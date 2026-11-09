/**
 * Procedural low-poly meshes for the town: the island, the plaza beacon, the
 * six buildings and their villagers. Everything is built from primitives at
 * load time, so the page ships no models or textures.
 *
 * Conventions: y is up, the island's surface is y = 0, and a building is
 * modelled at the origin with its door facing +z. The scene turns each one to
 * face the plaza.
 */
import * as THREE from '../vendor/three.min.js';

export const RING_RADIUS = 7.6; // distance from the plaza centre to a building
export const PLAZA_RADIUS = 2.6;
export const ISLAND_RADIUS = 11.8;

const DARK = '#14152a';

/** Small deterministic PRNG, so the island looks the same on every load. */
export function seeded(seed) {
	let s = seed >>> 0;
	return () => {
		s = (s + 0x6d2b79f5) >>> 0;
		let t = s;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

/* ------------------------------ geometry kit ------------------------------ */

/** Bakes a list of placed geometries into one, so a material is one draw. */
export function mergeParts(parts) {
	const arrays = [];
	let total = 0;
	for (const { geo, matrix } of parts) {
		const flat = geo.index ? geo.toNonIndexed() : geo;
		if (matrix) flat.applyMatrix4(matrix);
		const { array } = flat.getAttribute('position');
		arrays.push(array);
		total += array.length;
		if (flat !== geo) flat.dispose();
		geo.dispose();
	}
	const positions = new Float32Array(total);
	let offset = 0;
	for (const array of arrays) {
		positions.set(array, offset);
		offset += array.length;
	}
	const merged = new THREE.BufferGeometry();
	merged.setAttribute('position', new THREE.BufferAttribute(positions, 3));
	merged.computeVertexNormals();
	return merged;
}

const _pos = new THREE.Vector3();
const _quat = new THREE.Quaternion();
const _one = new THREE.Vector3(1, 1, 1);
const _up = new THREE.Vector3(0, 1, 0);

/** Collects parts into named buckets; each bucket becomes one mesh. */
class Kit {
	constructor() {
		this.buckets = {};
	}

	/** Place a geometry at (x, y, z), turned `ry` radians about the y axis. */
	put(bucket, geo, x, y, z, ry = 0) {
		_pos.set(x, y, z);
		_quat.setFromAxisAngle(_up, ry);
		const matrix = new THREE.Matrix4().compose(_pos, _quat, _one);
		(this.buckets[bucket] ||= []).push({ geo, matrix });
	}

	/** A box whose bottom face sits at height y. */
	box(bucket, w, h, d, x, y, z, ry = 0) {
		this.put(bucket, new THREE.BoxGeometry(w, h, d), x, y + h / 2, z, ry);
	}

	/** An upright cylinder (or prism, for few sides) standing at height y. */
	cyl(bucket, rTop, rBottom, h, sides, x, y, z, ry = 0) {
		const geo = new THREE.CylinderGeometry(rTop, rBottom, h, sides);
		this.put(bucket, geo, x, y + h / 2, z, ry);
	}

	/**
	 * A window lying on a wall. (x, y, z) is the bottom centre of the window on
	 * the wall's surface and `ry` the direction the wall faces.
	 */
	win(bucket, w, h, x, y, z, ry = 0, arched = false) {
		const t = 0.09;
		if (!arched) return this.box(bucket, w, h, t, x, y, z, ry);
		const r = w / 2;
		this.box(bucket, w, h - r, t, x, y, z, ry);
		const cap = new THREE.CylinderGeometry(
			r,
			r,
			t,
			8,
			1,
			false,
			Math.PI / 2,
			Math.PI,
		);
		cap.rotateX(Math.PI / 2);
		this.put(bucket, cap, x, y + h - r, z, ry);
	}

	/** A flat glowing disc on a wall, facing `ry`. */
	disc(bucket, r, x, y, z, ry = 0) {
		const geo = new THREE.CylinderGeometry(r, r, 0.08, 10);
		geo.rotateX(Math.PI / 2);
		this.put(bucket, geo, x, y, z, ry);
	}

	/** A lantern on a short post, used to line the path to the plaza. */
	lantern(x, z) {
		this.box('trim', 0.08, 0.5, 0.08, x, 0, z);
		this.box('glow', 0.17, 0.17, 0.17, x, 0.5, z);
	}

	build(materials) {
		const group = new THREE.Group();
		for (const [bucket, parts] of Object.entries(this.buckets)) {
			const mesh = new THREE.Mesh(mergeParts(parts), materials[bucket]);
			mesh.name = bucket;
			group.add(mesh);
		}
		return group;
	}
}

function trianglesGeo(vertices) {
	const geo = new THREE.BufferGeometry();
	geo.setAttribute(
		'position',
		new THREE.BufferAttribute(new Float32Array(vertices), 3),
	);
	geo.computeVertexNormals();
	return geo;
}

/** A gable: a triangle of width w and height h, extruded d along z. */
function prismGeo(w, h, d) {
	const x = w / 2;
	const z = d / 2;
	// prettier-ignore
	return trianglesGeo([
		-x, 0, z,   x, 0, z,   0, h, z,
		x, 0, -z,   -x, 0, -z,   0, h, -z,
		x, 0, z,   x, 0, -z,   0, h, -z,
		x, 0, z,   0, h, -z,   0, h, z,
		-x, 0, -z,   -x, 0, z,   0, h, z,
		-x, 0, -z,   0, h, z,   0, h, -z,
		-x, 0, -z,   x, 0, -z,   x, 0, z,
		-x, 0, -z,   x, 0, z,   -x, 0, z,
	]);
}

/** One tooth of a saw-tooth roof: upright on its -x side, sloping to +x. */
function sawGeo(w, h, d) {
	const x = w / 2;
	const z = d / 2;
	// prettier-ignore
	return trianglesGeo([
		-x, 0, z,   x, 0, z,   -x, h, z,
		x, 0, -z,   -x, 0, -z,   -x, h, -z,
		-x, 0, -z,   -x, 0, z,   -x, h, z,
		-x, 0, -z,   -x, h, z,   -x, h, -z,
		x, 0, z,   x, 0, -z,   -x, h, -z,
		x, 0, z,   -x, h, -z,   -x, h, z,
		-x, 0, -z,   x, 0, -z,   x, 0, z,
		-x, 0, -z,   x, 0, z,   -x, 0, z,
	]);
}

/* -------------------------------- materials ------------------------------- */

const PALETTES = {
	townhall: { wall: '#8a8eae', roof: '#3d3f63', trim: '#b9bcd4' },
	library: { wall: '#766589', roof: '#372f50', trim: '#a698ba' },
	observatory: { wall: '#677d8f', roof: '#a3b4c2', trim: '#8799a8' },
	workshop: { wall: '#85685a', roof: '#3f3848', trim: '#a08c7f' },
	printshop: { wall: '#a0958a', roof: '#6b3f59', trim: '#75645a' },
	watchtower: { wall: '#7d8194', roof: '#42395c', trim: '#a0a3b6' },
};

function matte(color) {
	return new THREE.MeshLambertMaterial({ color, flatShading: true });
}

let sharedGlow = null;
/** A soft round sprite texture, drawn once and shared by every glow. */
export function glowTexture() {
	if (sharedGlow) return sharedGlow;
	const size = 64;
	const canvas = document.createElement('canvas');
	canvas.width = canvas.height = size;
	const ctx = canvas.getContext('2d');
	const gradient = ctx.createRadialGradient(
		size / 2,
		size / 2,
		0,
		size / 2,
		size / 2,
		size / 2,
	);
	gradient.addColorStop(0, 'rgba(255,255,255,1)');
	gradient.addColorStop(0.25, 'rgba(255,255,255,0.55)');
	gradient.addColorStop(0.6, 'rgba(255,255,255,0.12)');
	gradient.addColorStop(1, 'rgba(255,255,255,0)');
	ctx.fillStyle = gradient;
	ctx.fillRect(0, 0, size, size);
	sharedGlow = new THREE.CanvasTexture(canvas);
	sharedGlow.colorSpace = THREE.SRGBColorSpace;
	return sharedGlow;
}

/* -------------------------------- buildings ------------------------------- */

const SIDE = Math.PI / 2;

function townhall(k) {
	k.box('trim', 4.6, 0.18, 3.6, 0, 0, 0.15);
	k.box('trim', 4.2, 0.18, 3.2, 0, 0.18, 0.1);
	k.box('wall', 3.6, 2.0, 2.2, 0, 0.36, -0.3);
	for (const x of [-1.5, -0.5, 0.5, 1.5]) {
		k.cyl('trim', 0.15, 0.17, 1.9, 6, x, 0.36, 1.25);
		k.box('trim', 0.42, 0.1, 0.42, x, 2.26, 1.25);
	}
	k.box('trim', 4.0, 0.26, 3.2, 0, 2.36, 0.05);
	k.put('roof', prismGeo(4.0, 0.95, 3.2), 0, 2.62, 0.05);
	k.disc('glow', 0.24, 0, 2.98, 1.66);
	k.box('dark', 0.7, 1.3, 0.09, 0, 0.36, 0.8);
	for (const x of [-1.05, 1.05])
		k.win('glow', 0.44, 1.05, x, 0.85, 0.8, 0, true);
	for (const z of [-0.95, 0.05]) {
		k.win('glow', 0.4, 0.9, 1.8, 0.95, z, SIDE, true);
		k.win('glow', 0.4, 0.9, -1.8, 0.95, z, -SIDE, true);
	}
	// clock tower
	k.box('wall', 0.95, 1.5, 0.95, 0, 3.0, -0.2);
	k.box('trim', 1.15, 0.12, 1.15, 0, 4.5, -0.2);
	k.cyl('roof', 0, 0.82, 0.85, 4, 0, 4.62, -0.2, Math.PI / 4);
	k.disc('glow', 0.31, 0, 3.95, 0.28);
	k.disc('glow', 0.31, 0.48, 3.95, -0.2, SIDE);
	k.disc('glow', 0.31, -0.48, 3.95, -0.2, -SIDE);
	k.disc('glow', 0.31, 0, 3.95, -0.68, Math.PI);
	for (const x of [-1.1, 0, 1.1])
		k.win('glow', 0.42, 0.95, x, 0.95, -1.4, Math.PI, true);
	return { height: 5.5, moteOrigin: [0, 5.3, -0.2], pick: [4.6, 4.4] };
}

function library(k) {
	k.box('trim', 3.5, 0.3, 2.9, 0, 0, 0);
	k.box('wall', 3.1, 3.5, 2.5, 0, 0.3, 0);
	for (const x of [-1.45, 1.45]) k.box('trim', 0.26, 3.5, 0.26, x, 0.3, 1.2);
	k.box('trim', 3.4, 0.2, 2.8, 0, 3.8, 0);
	k.box('roof', 3.0, 0.32, 2.4, 0, 4.0, 0);
	k.box('roof', 2.3, 0.32, 1.8, 0, 4.32, 0);
	k.box('roof', 1.6, 0.32, 1.2, 0, 4.64, 0);
	k.box('glow', 0.5, 0.32, 0.5, 0, 4.96, 0);
	for (const x of [-0.82, 0, 0.82])
		k.win('glow', 0.5, 0.98, x, 2.35, 1.25, 0, true);
	for (const x of [-0.82, 0.82])
		k.win('glow', 0.5, 0.98, x, 0.9, 1.25, 0, true);
	k.win('dark', 0.66, 1.3, 0, 0.3, 1.25, 0, true);
	for (const z of [-0.6, 0.6]) {
		for (const y of [0.9, 2.35]) {
			k.win('glow', 0.46, 0.95, 1.55, y, z, SIDE, true);
			k.win('glow', 0.46, 0.95, -1.55, y, z, -SIDE, true);
		}
	}
	for (const x of [-0.82, 0, 0.82]) {
		for (const y of [0.9, 2.35])
			k.win('glow', 0.5, 0.98, x, y, -1.25, Math.PI, true);
	}
	return { height: 5.3, moteOrigin: [0, 5.3, 0], pick: [3.8, 4.2] };
}

function observatory(k) {
	k.cyl('trim', 1.75, 1.85, 0.3, 10, 0, 0, 0);
	k.cyl('wall', 1.5, 1.55, 1.7, 10, 0, 0.3, 0);
	k.cyl('trim', 1.62, 1.62, 0.18, 10, 0, 2.0, 0);
	const dome = new THREE.SphereGeometry(
		1.5,
		10,
		5,
		0,
		Math.PI * 2,
		0,
		Math.PI / 2,
	);
	k.put('roof', dome, 0, 2.18, 0);
	// the slit the telescope looks through: an arc from the front up over the top
	const slit = new THREE.TorusGeometry(1.5, 0.13, 4, 8, Math.PI * 0.62);
	k.put('glow', slit, 0, 2.18, 0, -SIDE);
	const tilt = (50 * Math.PI) / 180;
	const tube = new THREE.CylinderGeometry(0.24, 0.31, 1.9, 7);
	tube.rotateX(tilt);
	k.put('trim', tube, 0, 2.18 + Math.cos(tilt) * 1.45, Math.sin(tilt) * 1.45);
	const lens = new THREE.CylinderGeometry(0.2, 0.2, 0.06, 8);
	lens.rotateX(tilt);
	k.put('glow', lens, 0, 2.18 + Math.cos(tilt) * 2.42, Math.sin(tilt) * 2.42);
	k.box('dark', 0.6, 1.1, 0.09, 0, 0.3, 1.52);
	for (const a of [-1.0, 1.0, -2.1, 2.1, Math.PI]) {
		k.win(
			'glow',
			0.42,
			0.7,
			Math.sin(a) * 1.52,
			0.9,
			Math.cos(a) * 1.52,
			a,
			true,
		);
	}
	return { height: 4.2, moteOrigin: [0, 3.7, 0.6], pick: [4.0, 4.4] };
}

/** The workshop's gear is its own mesh so it can turn while the agent works. */
function gearGeo() {
	const parts = [{ geo: new THREE.TorusGeometry(0.4, 0.11, 5, 10) }];
	for (let i = 0; i < 8; i++) {
		const a = (i / 8) * Math.PI * 2;
		const tooth = new THREE.BoxGeometry(0.17, 0.2, 0.2);
		const matrix = new THREE.Matrix4()
			.makeRotationZ(a)
			.multiply(new THREE.Matrix4().makeTranslation(0, 0.56, 0));
		parts.push({ geo: tooth, matrix });
	}
	for (let i = 0; i < 2; i++) {
		const spoke = new THREE.BoxGeometry(0.72, 0.09, 0.1);
		parts.push({
			geo: spoke,
			matrix: new THREE.Matrix4().makeRotationZ((i * Math.PI) / 2),
		});
	}
	return mergeParts(parts);
}

function workshop(k) {
	k.box('trim', 3.9, 0.2, 2.9, 0, 0, 0);
	k.box('wall', 3.6, 1.7, 2.6, 0, 0.2, 0);
	for (const x of [-1.2, 0, 1.2]) {
		k.put('roof', sawGeo(1.2, 0.9, 2.6), x, 1.9, 0);
		k.box('glow', 0.09, 0.46, 2.1, x - 0.6, 2.1, 0);
	}
	k.box('trim', 0.55, 3.4, 0.55, 1.35, 0.2, -0.85);
	k.box('dark', 0.72, 0.16, 0.72, 1.35, 3.6, -0.85);
	k.box('dark', 1.5, 1.25, 0.09, -0.8, 0.2, 1.3);
	k.box('glow', 1.2, 0.13, 0.12, -0.8, 1.1, 1.3);
	k.win('glow', 0.7, 0.55, 0.95, 0.55, 1.3);
	for (const z of [-0.6, 0.6]) k.win('glow', 0.5, 0.5, -1.8, 0.8, z, -SIDE);
	for (const x of [-1.0, 0.1])
		k.win('glow', 0.75, 0.55, x, 0.85, -1.3, Math.PI);
	k.box('glow', 0.42, 0.1, 0.42, 1.35, 3.72, -0.85);
	return {
		height: 4.0,
		moteOrigin: [1.35, 3.8, -0.85],
		pick: [4.2, 4.2],
		gear: [0.95, 1.86, 1.42],
	};
}

function printshop(k) {
	k.box('trim', 3.3, 0.2, 2.9, 0, 0, 0);
	k.box('wall', 3.0, 1.8, 2.5, 0, 0.2, 0);
	k.put('wall', prismGeo(3.0, 1.19, 2.52), 0, 2.0, 0);
	// two roof slabs that overhang the gable
	const pitch = Math.atan2(1.35, 1.7);
	for (const side of [1, -1]) {
		const slab = new THREE.BoxGeometry(2.3, 0.15, 3.0);
		slab.rotateZ(-side * pitch);
		k.put('roof', slab, side * 0.86, 2.74, 0);
	}
	k.box('trim', 0.18, 0.16, 3.1, 0, 3.36, 0);
	// shop front: one big lit window with a sign above it
	k.box('trim', 1.72, 1.12, 0.1, -0.55, 0.62, 1.25);
	k.box('glow', 1.5, 0.9, 0.16, -0.55, 0.73, 1.25);
	k.box('trim', 0.07, 0.9, 0.2, -0.55, 0.73, 1.25);
	k.box('trim', 1.5, 0.07, 0.2, -0.55, 1.18, 1.25);
	k.box('glow', 1.5, 0.22, 0.12, -0.55, 1.78, 1.27);
	k.box('dark', 0.62, 1.3, 0.09, 0.95, 0.2, 1.25);
	k.box('glow', 0.3, 0.3, 0.12, 0.95, 1.0, 1.25);
	k.disc('glow', 0.27, 0, 2.5, 1.27);
	k.box('trim', 0.42, 1.2, 0.42, -0.95, 2.4, -0.6);
	for (const z of [-0.55, 0.55]) {
		k.win('glow', 0.5, 0.6, 1.5, 0.85, z, SIDE);
		k.win('glow', 0.5, 0.6, -1.5, 0.85, z, -SIDE);
	}
	for (const x of [-0.7, 0.7])
		k.win('glow', 0.55, 0.65, x, 0.85, -1.25, Math.PI);
	k.disc('glow', 0.27, 0, 2.5, -1.27, Math.PI);
	return { height: 3.8, moteOrigin: [-0.95, 3.7, -0.6], pick: [3.9, 4.2] };
}

function watchtower(k) {
	k.box('trim', 1.9, 0.4, 1.9, 0, 0, 0);
	const shaft = new THREE.CylinderGeometry(0.71, 0.96, 4.3, 4);
	shaft.rotateY(Math.PI / 4);
	k.put('wall', shaft, 0, 0.4 + 2.15, 0);
	k.box('trim', 1.9, 0.28, 1.9, 0, 4.7, 0);
	for (const [x, z] of [
		[-0.77, -0.77],
		[0, -0.77],
		[0.77, -0.77],
		[-0.77, 0],
		[0.77, 0],
		[-0.77, 0.77],
		[0, 0.77],
		[0.77, 0.77],
	]) {
		k.box('trim', 0.36, 0.36, 0.36, x, 4.98, z);
	}
	k.cyl('trim', 0.1, 0.13, 0.5, 6, 0, 4.98, 0);
	k.put('glow', new THREE.IcosahedronGeometry(0.34, 0), 0, 5.8, 0);
	for (const x of [-0.42, 0.42]) {
		for (const z of [-0.42, 0.42]) k.box('trim', 0.07, 1.2, 0.07, x, 4.98, z);
	}
	k.cyl('roof', 0, 0.86, 0.62, 4, 0, 6.18, 0, Math.PI / 4);
	// half the shaft's width at a given height; the tower tapers
	const half = (y) => 0.68 - ((y - 0.4) / 4.3) * 0.18 + 0.01;
	for (const y of [1.55, 2.65, 3.75]) {
		k.box('glow', 0.18, 0.5, 0.09, 0, y, half(y));
		k.box('glow', 0.18, 0.5, 0.09, 0, y, -half(y));
		k.box('glow', 0.09, 0.5, 0.18, half(y), y, 0);
		k.box('glow', 0.09, 0.5, 0.18, -half(y), y, 0);
	}
	k.box('dark', 0.5, 0.9, 0.09, 0, 0.4, half(0.8));
	return { height: 6.9, moteOrigin: [0, 6.3, 0], haloY: 5.8, pick: [2.8, 3.6] };
}

const BUILDERS = {
	townhall,
	library,
	observatory,
	workshop,
	printshop,
	watchtower,
};

/**
 * Builds one building in its agent's colour.
 * Returns the group plus the handles the scene animates.
 */
export function makeBuilding(kind, color) {
	const build = BUILDERS[kind] || BUILDERS.printshop;
	const palette = PALETTES[kind] || PALETTES.printshop;
	const kit = new Kit();
	const info = build(kit);
	for (const x of [-0.66, 0.66]) {
		kit.lantern(x, 2.5);
		kit.lantern(x, 4.0);
	}
	const materials = {
		wall: matte(palette.wall),
		roof: matte(palette.roof),
		trim: matte(palette.trim),
		dark: matte(DARK),
		glow: new THREE.MeshLambertMaterial({
			color: '#0d0d16',
			emissive: color,
			emissiveIntensity: 0.16,
			flatShading: true,
		}),
	};
	const group = kit.build(materials);
	const spin = [];
	if (info.gear) {
		const gear = new THREE.Mesh(gearGeo(), materials.glow);
		gear.position.set(...info.gear);
		group.add(gear);
		spin.push(gear);
	}
	return {
		group,
		spin,
		materials,
		height: info.height,
		haloY: info.haloY ?? info.height * 0.45,
		moteOrigin: new THREE.Vector3(...info.moteOrigin),
		pickSize: info.pick,
		// the colours to return to after a skipped or failed mission
		base: {
			wall: new THREE.Color(palette.wall),
			roof: new THREE.Color(palette.roof),
			trim: new THREE.Color(palette.trim),
		},
	};
}

/** The small figure standing by each door. */
export function makeVillager(color) {
	const group = new THREE.Group();
	const bodyMaterial = new THREE.MeshLambertMaterial({
		color,
		emissive: color,
		emissiveIntensity: 0.3,
		flatShading: true,
	});
	const body = new THREE.Mesh(
		new THREE.CapsuleGeometry(0.21, 0.3, 2, 7),
		bodyMaterial,
	);
	body.position.y = 0.36;
	const head = new THREE.Mesh(
		new THREE.IcosahedronGeometry(0.19, 1),
		matte('#f2dcc4'),
	);
	head.position.y = 0.86;
	group.add(body, head);
	group.scale.setScalar(1.2);
	return { group, bodyMaterial };
}

/** The floating tick shown over a building whose agent has finished. */
export function makeCheck() {
	const material = new THREE.MeshBasicMaterial({
		color: '#4be36a',
		toneMapped: false,
	});
	const short = new THREE.BoxGeometry(0.34, 0.13, 0.08);
	const long = new THREE.BoxGeometry(0.66, 0.13, 0.08);
	const geo = mergeParts([
		{
			geo: short,
			matrix: new THREE.Matrix4()
				.makeTranslation(-0.2, -0.08, 0)
				.multiply(new THREE.Matrix4().makeRotationZ(-Math.PI / 4)),
		},
		{
			geo: long,
			matrix: new THREE.Matrix4()
				.makeTranslation(0.12, 0.04, 0)
				.multiply(new THREE.Matrix4().makeRotationZ(Math.PI / 3.6)),
		},
	]);
	const group = new THREE.Group();
	group.add(new THREE.Mesh(geo, material));
	const halo = new THREE.Sprite(
		new THREE.SpriteMaterial({
			map: glowTexture(),
			color: '#32d74b',
			transparent: true,
			opacity: 0.55,
			depthWrite: false,
			blending: THREE.AdditiveBlending,
		}),
	);
	halo.scale.setScalar(1.9);
	group.add(halo);
	return group;
}

/* --------------------------------- island --------------------------------- */

function ringGeo(rings, colorAt, ref) {
	const positions = [];
	const colors = [];
	const a = new THREE.Vector3();
	const b = new THREE.Vector3();
	const normal = new THREE.Vector3();
	const want = new THREE.Vector3();
	const shade = new THREE.Color();
	const tri = (p, q, r) => {
		// wind each face so its normal points the way `ref` says it should
		a.subVectors(q, p);
		b.subVectors(r, p);
		normal.crossVectors(a, b);
		want.copy(p).add(q).add(r).divideScalar(3);
		ref(want);
		const [u, v] = normal.dot(want) < 0 ? [r, q] : [q, r];
		colorAt(shade, p, q, r);
		for (const point of [p, u, v]) {
			positions.push(point.x, point.y, point.z);
			colors.push(shade.r, shade.g, shade.b);
		}
	};
	for (let i = 1; i < rings.length; i++) {
		const inner = rings[i - 1];
		const outer = rings[i];
		const n = Math.max(inner.length, outer.length);
		for (let j = 0; j < n; j++) {
			const i0 = inner[j % inner.length];
			const i1 = inner[(j + 1) % inner.length];
			const o0 = outer[j % outer.length];
			const o1 = outer[(j + 1) % outer.length];
			if (outer.length > 1) tri(i0, o0, o1);
			if (inner.length > 1) tri(i0, o1, i1);
		}
	}
	const geo = new THREE.BufferGeometry();
	geo.setAttribute(
		'position',
		new THREE.BufferAttribute(new Float32Array(positions), 3),
	);
	geo.setAttribute(
		'color',
		new THREE.BufferAttribute(new Float32Array(colors), 3),
	);
	geo.computeVertexNormals();
	return geo;
}

/** The floating island: faceted ground, rock underneath, paths, trees. */
export function makeIsland(angles) {
	const rand = seeded(7);
	const SEGMENTS = 18;
	const group = new THREE.Group();
	const ring = (radius, y, wobble = 0, drop = 0) =>
		Array.from({ length: SEGMENTS }, (_, j) => {
			const a = (j / SEGMENTS) * Math.PI * 2;
			const r = radius + (rand() - 0.5) * wobble;
			return new THREE.Vector3(
				Math.sin(a) * r,
				y + (rand() - 0.5) * drop,
				-Math.cos(a) * r,
			);
		});
	const centre = (y) => [new THREE.Vector3(0, y, 0)];

	// the ground is flat out to where the buildings stand, then breaks up
	const rim = ring(ISLAND_RADIUS, -0.28, 1.3, 0.25);
	const top = [centre(0), ring(3.4, 0), ring(6.6, 0), ring(9.9, 0), rim];
	const grass = new THREE.Color();
	const topGeo = ringGeo(
		top,
		(c) =>
			c.copy(grass.setHSL(0.46 + rand() * 0.03, 0.4, 0.125 + rand() * 0.035)),
		(v) => v.set(0, 1, 0),
	);
	group.add(
		new THREE.Mesh(
			topGeo,
			new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }),
		),
	);

	const under = [
		rim,
		ring(ISLAND_RADIUS * 0.9, -1.9, 1.4, 0.5),
		ring(ISLAND_RADIUS * 0.62, -4.4, 1.6, 0.8),
		ring(ISLAND_RADIUS * 0.33, -7.2, 1.2, 0.9),
		centre(-10.2),
	];
	const rock = new THREE.Color();
	const underGeo = ringGeo(
		under,
		(c, p) =>
			c.copy(rock.setHSL(0.72, 0.22, 0.2 + rand() * 0.05 + p.y * 0.011)),
		(v) => v.set(v.x, -3, v.z),
	);
	group.add(
		new THREE.Mesh(
			underGeo,
			new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }),
		),
	);

	// plaza and the paths out to each door
	const stone = matte('#50537a');
	const plaza = new THREE.Mesh(
		new THREE.CylinderGeometry(PLAZA_RADIUS, PLAZA_RADIUS + 0.16, 0.16, 16),
		stone,
	);
	plaza.position.y = 0.08;
	group.add(plaza);
	const inner = new THREE.Mesh(
		new THREE.CylinderGeometry(1.45, 1.55, 0.1, 12),
		matte('#62669a'),
	);
	inner.position.y = 0.21;
	group.add(inner);

	const from = PLAZA_RADIUS - 0.1;
	const to = RING_RADIUS - 1.5;
	const paths = angles.map((deg) => {
		const a = (deg * Math.PI) / 180;
		const mid = (from + to) / 2;
		const matrix = new THREE.Matrix4()
			.makeTranslation(Math.sin(a) * mid, 0.035, -Math.cos(a) * mid)
			.multiply(new THREE.Matrix4().makeRotationY(-a));
		return { geo: new THREE.BoxGeometry(0.95, 0.07, to - from), matrix };
	});
	if (paths.length)
		group.add(new THREE.Mesh(mergeParts(paths), matte('#3f4268')));

	// trees in the gaps between buildings, a few rocks near the rim
	const spots = [];
	const gaps = angles.length || 6;
	for (let g = 0; g < gaps; g++) {
		const base = (((angles[g] ?? g * 60) + 180 / gaps) * Math.PI) / 180;
		const count = 2 + Math.floor(rand() * 2);
		for (let i = 0; i < count; i++) {
			const a = base + (rand() - 0.5) * 0.36;
			const r = 8.3 + rand() * 2.1;
			spots.push({
				x: Math.sin(a) * r,
				z: -Math.cos(a) * r,
				s: 0.75 + rand() * 0.6,
			});
		}
	}
	const leaf = new THREE.MeshLambertMaterial({ flatShading: true });
	const crowns = new THREE.InstancedMesh(
		new THREE.ConeGeometry(0.62, 1.25, 6),
		leaf,
		spots.length * 2,
	);
	const trunks = new THREE.InstancedMesh(
		new THREE.CylinderGeometry(0.09, 0.13, 0.5, 5),
		matte('#4a3a44'),
		spots.length,
	);
	const m = new THREE.Matrix4();
	const tint = new THREE.Color();
	spots.forEach((spot, i) => {
		const turn = new THREE.Quaternion().setFromAxisAngle(_up, rand() * 6);
		m.compose(
			new THREE.Vector3(spot.x, 0.25 * spot.s, spot.z),
			turn,
			new THREE.Vector3(spot.s, spot.s, spot.s),
		);
		trunks.setMatrixAt(i, m);
		for (let tier = 0; tier < 2; tier++) {
			const s = spot.s * (tier ? 0.7 : 1);
			m.compose(
				new THREE.Vector3(spot.x, (tier ? 1.75 : 1.05) * spot.s, spot.z),
				turn,
				new THREE.Vector3(s, s, s),
			);
			crowns.setMatrixAt(i * 2 + tier, m);
			crowns.setColorAt(
				i * 2 + tier,
				tint.setHSL(0.44 + rand() * 0.05, 0.48, 0.15 + rand() * 0.06),
			);
		}
	});
	crowns.instanceColor.needsUpdate = true;
	group.add(crowns, trunks);

	const ROCKS = 9;
	const rocks = new THREE.InstancedMesh(
		new THREE.IcosahedronGeometry(0.4, 0),
		matte('#4a4866'),
		ROCKS,
	);
	for (let i = 0; i < ROCKS; i++) {
		const a = rand() * Math.PI * 2;
		const r = 10 + rand() * 1.0;
		const s = 0.5 + rand() * 0.9;
		m.compose(
			new THREE.Vector3(Math.sin(a) * r, 0.05, -Math.cos(a) * r),
			new THREE.Quaternion().setFromAxisAngle(_up, rand() * 6),
			new THREE.Vector3(s, s * 0.7, s),
		);
		rocks.setMatrixAt(i, m);
	}
	group.add(rocks);
	return group;
}

/** The crystal over the plaza that shows what the mission as a whole is doing. */
export function makeBeacon() {
	const group = new THREE.Group();
	const pedestal = new THREE.Mesh(
		new THREE.CylinderGeometry(0.5, 0.68, 0.5, 8),
		matte('#8d91bb'),
	);
	pedestal.position.y = 0.5;
	group.add(pedestal);

	const material = new THREE.MeshLambertMaterial({
		color: '#2a2152',
		emissive: '#7b5cf0',
		emissiveIntensity: 0.3,
		flatShading: true,
	});
	const crystal = new THREE.Mesh(
		new THREE.OctahedronGeometry(0.58, 0),
		material,
	);
	crystal.scale.set(1, 1.85, 1);
	crystal.position.y = 2.25;
	group.add(crystal);

	const hoop = new THREE.Mesh(
		new THREE.TorusGeometry(1.0, 0.045, 5, 24),
		material,
	);
	hoop.position.y = 2.25;
	hoop.rotation.x = Math.PI / 2.4;
	group.add(hoop);

	const additive = {
		transparent: true,
		depthWrite: false,
		blending: THREE.AdditiveBlending,
	};
	const halo = new THREE.Sprite(
		new THREE.SpriteMaterial({
			map: glowTexture(),
			color: '#7b5cf0',
			opacity: 0.2,
			...additive,
		}),
	);
	halo.position.y = 2.25;
	halo.scale.setScalar(5);
	group.add(halo);

	// a ring inlaid in the plaza floor that lights with the crystal
	const inlay = new THREE.Mesh(
		new THREE.RingGeometry(1.95, 2.12, 32),
		new THREE.MeshBasicMaterial({
			color: '#7b5cf0',
			opacity: 0.25,
			...additive,
		}),
	);
	inlay.rotation.x = -Math.PI / 2;
	inlay.position.y = 0.175;
	group.add(inlay);

	const light = new THREE.PointLight('#7b5cf0', 0, 14, 2);
	light.position.y = 2.4;
	group.add(light);

	return { group, crystal, hoop, halo, inlay, light, material };
}
