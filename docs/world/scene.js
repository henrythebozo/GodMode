/**
 * The 3D town. `createWorld(canvas, roster)` builds the island and returns a
 * small handle the rest of the page drives: set an agent's state, send a
 * courier between two buildings, move the camera, and ask where a building is
 * on screen so an HTML label can sit above it.
 *
 * Nothing here knows about missions or the API; it only draws what it is told.
 * The canvas is sized to fill its parent element.
 */
import * as THREE from '../vendor/three.min.js';
import { OrbitControls } from '../vendor/three.min.js';
import {
	ISLAND_RADIUS,
	RING_RADIUS,
	glowTexture,
	makeBeacon,
	makeBuilding,
	makeCheck,
	makeIsland,
	makeVillager,
} from './buildings.js';

const PLAZA = 'plaza';
const FOV = 38;
const TAN_HALF_FOV = Math.tan(THREE.MathUtils.degToRad(FOV / 2));
const MOTES = 18;

const VIOLET = new THREE.Color('#7b5cf0');
const RED = new THREE.Color('#ff4d5e');
const WARM = new THREE.Color('#ffe6bf');
const BLOOD = new THREE.Color('#5a1f2c');

/**
 * What each agent state looks like. `glow` is window brightness, `pulse` and
 * `rate` how much and how fast it breathes, `light` the lamp cast on the
 * ground, `halo` the soft bloom around the building, `motes` whether sparks
 * rise from the roof and how fast, `spin` how fast machinery turns.
 */
const STATES = {
	idle: {
		glow: 0.13,
		pulse: 0,
		rate: 0,
		light: 0,
		halo: 0,
		motes: 0,
		speed: 0,
		spin: 0,
	},
	queued: {
		glow: 0.36,
		pulse: 0.4,
		rate: 1.6,
		light: 3,
		halo: 0.12,
		motes: 0,
		speed: 0,
		spin: 0,
	},
	thinking: {
		glow: 0.85,
		pulse: 0.45,
		rate: 3.2,
		light: 14,
		halo: 0.4,
		motes: 1,
		speed: 0.7,
		spin: 0.9,
	},
	writing: {
		glow: 1.35,
		pulse: 0.08,
		rate: 9,
		light: 24,
		halo: 0.6,
		motes: 1,
		speed: 2.3,
		spin: 3.2,
	},
	done: {
		glow: 0.7,
		pulse: 0,
		rate: 0,
		light: 7,
		halo: 0.22,
		motes: 0,
		speed: 0,
		spin: 0,
	},
	skipped: {
		glow: 0,
		pulse: 0,
		rate: 0,
		light: 0,
		halo: 0,
		motes: 0,
		speed: 0,
		spin: 0,
	},
	error: {
		glow: 0.9,
		pulse: 0.3,
		rate: 2.2,
		light: 10,
		halo: 0.34,
		motes: 0,
		speed: 0,
		spin: 0,
	},
};

const BEACONS = {
	idle: {
		glow: 0.3,
		pulse: 0.12,
		rate: 1,
		spin: 0.15,
		light: 2,
		halo: 0.14,
		inlay: 0.2,
		color: VIOLET,
	},
	running: {
		glow: 1.05,
		pulse: 0.45,
		rate: 2.6,
		spin: 1.3,
		light: 20,
		halo: 0.5,
		inlay: 0.75,
		color: VIOLET,
	},
	done: {
		glow: 1.6,
		pulse: 0.08,
		rate: 1.4,
		spin: 0.45,
		light: 32,
		halo: 0.85,
		inlay: 1,
		color: new THREE.Color('#b9a4ff'),
	},
	error: {
		glow: 1.0,
		pulse: 0.3,
		rate: 2,
		spin: 0.08,
		light: 12,
		halo: 0.45,
		inlay: 0.6,
		color: RED,
	},
};

const ADDITIVE = {
	transparent: true,
	depthWrite: false,
	blending: THREE.AdditiveBlending,
};

function skyTexture() {
	const canvas = document.createElement('canvas');
	canvas.width = 4;
	canvas.height = 256;
	const ctx = canvas.getContext('2d');
	const gradient = ctx.createLinearGradient(0, 0, 0, 256);
	gradient.addColorStop(0, '#010106');
	gradient.addColorStop(0.38, '#070920');
	gradient.addColorStop(0.66, '#15124a');
	gradient.addColorStop(0.8, '#0c0b2c');
	gradient.addColorStop(1, '#020208');
	ctx.fillStyle = gradient;
	ctx.fillRect(0, 0, 4, 256);
	const texture = new THREE.CanvasTexture(canvas);
	texture.colorSpace = THREE.SRGBColorSpace;
	return texture;
}

function makeStars() {
	const group = new THREE.Group();
	const layer = (count, size, seed) => {
		const positions = new Float32Array(count * 3);
		const colors = new Float32Array(count * 3);
		const tint = new THREE.Color();
		let s = seed;
		const rand = () => {
			s = (s * 16807) % 2147483647;
			return s / 2147483647;
		};
		for (let i = 0; i < count; i++) {
			const u = rand() * 2 - 1;
			const a = rand() * Math.PI * 2;
			const r = Math.sqrt(1 - u * u) * 260;
			positions.set([Math.cos(a) * r, u * 260, Math.sin(a) * r], i * 3);
			tint.setHSL(0.58 + rand() * 0.2, 0.5, 0.45 + rand() * 0.5);
			colors.set([tint.r, tint.g, tint.b], i * 3);
		}
		const geo = new THREE.BufferGeometry();
		geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
		geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
		const material = new THREE.PointsMaterial({
			size,
			sizeAttenuation: false,
			vertexColors: true,
			transparent: true,
			depthWrite: false,
			fog: false,
		});
		group.add(new THREE.Points(geo, material));
	};
	layer(620, 1.4, 11);
	layer(70, 2.6, 23);
	return group;
}

const easeInOut = (t) =>
	t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

export function createWorld(canvas, roster = []) {
	const renderer = new THREE.WebGLRenderer({
		canvas,
		antialias: true,
		powerPreference: 'high-performance',
	});
	renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
	renderer.toneMapping = THREE.ACESFilmicToneMapping;
	renderer.toneMappingExposure = 1.15;
	if (!canvas.style.width) canvas.style.width = '100%';
	if (!canvas.style.height) canvas.style.height = '100%';
	if (!canvas.style.display) canvas.style.display = 'block';

	const scene = new THREE.Scene();
	scene.background = skyTexture();
	const camera = new THREE.PerspectiveCamera(FOV, 1, 0.5, 700);

	scene.add(new THREE.HemisphereLight('#5a66c4', '#150f2a', 0.8));
	const moon = new THREE.DirectionalLight('#c4d0ff', 1.45);
	moon.position.set(-7, 12, 8);
	scene.add(moon);
	scene.add(makeStars());
	scene.add(makeIsland(roster.map((agent) => agent.angle)));

	const beacon = makeBeacon();
	scene.add(beacon.group);
	const beaconNow = {
		glow: 0.3,
		spin: 0.15,
		light: 0,
		halo: 0.14,
		inlay: 0.2,
		color: VIOLET.clone(),
	};
	let beaconMode = 'idle';

	const reduceQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
	let reduced = reduceQuery.matches;
	const onReduce = (e) => (reduced = e.matches);
	reduceQuery.addEventListener('change', onReduce);

	/* ------------------------------- buildings ------------------------------ */

	const agents = new Map();
	const anchors = new Map([[PLAZA, new THREE.Vector3(0, 4.3, 0)]]);
	const docks = new Map([[PLAZA, new THREE.Vector3(0, 2.25, 0)]]);
	const proxies = [];
	const hidden = new THREE.MeshBasicMaterial();

	const addProxy = (id, geo, x, y, z, ry = 0) => {
		const proxy = new THREE.Mesh(geo, hidden);
		proxy.position.set(x, y, z);
		proxy.rotation.y = ry;
		proxy.visible = false; // never drawn; the raycaster still tests it
		proxy.userData.pick = id;
		scene.add(proxy);
		proxies.push(proxy);
	};
	addProxy(PLAZA, new THREE.CylinderGeometry(1.3, 1.3, 3.8, 8), 0, 1.9, 0);

	roster.forEach((agent, index) => {
		const angle = (agent.angle * Math.PI) / 180;
		const color = new THREE.Color(agent.color);
		// light sources use a deeper version of the agent colour: a pastel
		// pushed through tone mapping comes out white and loses its identity
		const hsl = color.getHSL({ h: 0, s: 0, l: 0 });
		const vivid = new THREE.Color().setHSL(
			hsl.h,
			Math.max(hsl.s, 0.9),
			Math.min(hsl.l, 0.52),
		);
		const built = makeBuilding(agent.building, agent.color);
		const pos = new THREE.Vector3(
			Math.sin(angle) * RING_RADIUS,
			0,
			-Math.cos(angle) * RING_RADIUS,
		);
		const inward = new THREE.Vector3(-Math.sin(angle), 0, Math.cos(angle));
		built.group.position.copy(pos);
		built.group.rotation.y = -angle;
		scene.add(built.group);

		const villager = makeVillager(agent.color);
		const home = new THREE.Vector3(1.25, 0, 2.25);
		villager.group.position.copy(home);
		built.group.add(villager.group);

		const halo = new THREE.Sprite(
			new THREE.SpriteMaterial({
				map: glowTexture(),
				color: vivid,
				opacity: 0,
				...ADDITIVE,
			}),
		);
		halo.position.set(0, built.haloY, 0);
		halo.scale.setScalar(Math.max(6.5, built.height * 1.5));
		built.group.add(halo);

		const pool = new THREE.Mesh(
			new THREE.CircleGeometry(3.6, 20),
			new THREE.MeshBasicMaterial({
				map: glowTexture(),
				color,
				opacity: 0,
				...ADDITIVE,
			}),
		);
		pool.rotation.x = -Math.PI / 2;
		pool.position.set(0, 0.1, 1.2);
		built.group.add(pool);

		const light = new THREE.PointLight(color, 0, 9, 2);
		light.position.set(0, 1.5, 2.1);
		built.group.add(light);

		const moteGeo = new THREE.BufferGeometry();
		moteGeo.setAttribute(
			'position',
			new THREE.BufferAttribute(new Float32Array(MOTES * 3), 3),
		);
		moteGeo.setAttribute(
			'color',
			new THREE.BufferAttribute(new Float32Array(MOTES * 3), 3),
		);
		const motes = new THREE.Points(
			moteGeo,
			new THREE.PointsMaterial({
				size: 0.5,
				map: glowTexture(),
				vertexColors: true,
				...ADDITIVE,
			}),
		);
		motes.frustumCulled = false;
		motes.visible = false;
		built.group.add(motes);

		const check = makeCheck();
		check.position.set(pos.x, built.height + 0.5, pos.z);
		check.visible = false;
		scene.add(check);

		const [pickW, pickD] = built.pickSize;
		addProxy(
			agent.id,
			new THREE.BoxGeometry(pickW, built.height, pickD),
			pos.x + inward.x * 0.6,
			built.height / 2,
			pos.z + inward.z * 0.6,
			-angle,
		);
		anchors.set(agent.id, new THREE.Vector3(pos.x, built.height + 1.2, pos.z));
		docks.set(agent.id, pos.clone().addScaledVector(inward, 2.5).setY(0.95));

		agents.set(agent.id, {
			...built,
			angle,
			pos,
			color,
			vivid,
			villager,
			home,
			halo,
			pool,
			light,
			motes,
			check,
			pickW,
			state: 'idle',
			phase: index * 1.7,
			glow: STATES.idle.glow,
			lightK: 0,
			haloK: 0,
			moteK: 0,
			moteSpeed: 0,
			moteClock: index,
			spinRate: 0,
			skipK: 0,
			errK: 0,
			doneK: 0,
			tintKey: 0,
			seeds: Array.from({ length: MOTES }, (_, i) => ({
				phase: (i * 0.618) % 1,
				angle: i * 2.4,
				radius: 0.25 + ((i * 0.37) % 1) * 0.55,
			})),
		});
	});

	const tmp = new THREE.Color();
	const grey = new THREE.Color();

	function updateAgent(b, dt, t) {
		const s = STATES[b.state];
		const k = 1 - Math.exp(-dt * 5);
		b.glow += (s.glow - b.glow) * k;
		b.lightK += (s.light - b.lightK) * k;
		b.haloK += (s.halo - b.haloK) * k;
		b.moteK += ((reduced ? 0 : s.motes) - b.moteK) * k;
		b.spinRate += ((reduced ? 0 : s.spin) - b.spinRate) * k;
		b.skipK += ((b.state === 'skipped' ? 1 : 0) - b.skipK) * k;
		b.errK += ((b.state === 'error' ? 1 : 0) - b.errK) * k;
		b.doneK += ((b.state === 'done' ? 1 : 0) - b.doneK) * k;
		const wave = reduced ? 0 : Math.sin(t * s.rate + b.phase) * s.pulse;

		// agent colour, warming when finished and turning red on failure
		tmp
			.copy(b.vivid)
			.lerp(WARM, b.doneK * 0.35)
			.lerp(RED, b.errK);
		const glow = b.materials.glow;
		glow.emissive.copy(tmp);
		glow.emissiveIntensity = b.glow * (1 + wave);
		b.light.color.copy(tmp);
		b.light.intensity = b.lightK * (1 + wave);
		b.halo.material.color.copy(tmp);
		b.halo.material.opacity = b.haloK * (1 + wave * 0.6);
		b.pool.material.color.copy(tmp);
		b.pool.material.opacity = Math.min(1, b.haloK * 1.1 * (1 + wave * 0.5));

		// walls only need recolouring while a skip or error fade is in progress
		const tintKey = Math.round(b.skipK * 200) * 1000 + Math.round(b.errK * 200);
		if (tintKey !== b.tintKey) {
			b.tintKey = tintKey;
			for (const name of ['wall', 'roof', 'trim']) {
				const c = b.materials[name].color.copy(b.base[name]);
				const l = (c.r * 0.3 + c.g * 0.59 + c.b * 0.11) * 0.4;
				c.lerp(grey.setRGB(l, l, l * 1.15), b.skipK).lerp(BLOOD, b.errK * 0.45);
			}
			const body = b.villager.bodyMaterial;
			body.color
				.copy(b.color)
				.lerp(grey.setRGB(0.16, 0.16, 0.2), b.skipK)
				.lerp(RED, b.errK);
			body.emissive.copy(body.color);
			body.emissiveIntensity = 0.3 * (1 - b.skipK);
		}

		// the villager
		let x = 0;
		let y = 0;
		let turn = 0;
		if (!reduced) {
			if (b.state === 'idle') y = Math.abs(Math.sin(t * 1.5 + b.phase)) * 0.045;
			else if (b.state === 'queued') turn = Math.sin(t * 1.3 + b.phase) * 0.6;
			else if (b.state === 'thinking') {
				x = Math.sin(t * 0.9 + b.phase) * 0.42;
				turn = Math.cos(t * 0.9 + b.phase) * 0.9;
			} else if (b.state === 'writing')
				y = Math.abs(Math.sin(t * 7 + b.phase)) * 0.18;
			else if (b.state === 'done')
				y = Math.abs(Math.sin(t * 2 + b.phase)) * 0.05;
			else if (b.state === 'error') x = Math.sin(t * 22) * 0.03;
		}
		const v = b.villager.group;
		v.position.set(b.home.x + x, y - b.skipK * 0.06, b.home.z);
		v.rotation.y += (turn - v.rotation.y) * k;
		v.scale.set(1.2, 1.2 * (1 - b.skipK * 0.2), 1.2);

		for (const part of b.spin) part.rotation.z += dt * b.spinRate;

		// sparks rising from the roof
		if (b.moteK > 0.02) {
			b.motes.visible = true;
			b.moteSpeed += (s.speed - b.moteSpeed) * k;
			b.moteClock += dt * Math.max(b.moteSpeed, 0.3);
			const fast = THREE.MathUtils.clamp((b.moteSpeed - 0.7) / 1.6, 0, 1);
			const positions = b.motes.geometry.attributes.position;
			const colors = b.motes.geometry.attributes.color;
			for (let i = 0; i < MOTES; i++) {
				const seed = b.seeds[i];
				const u = (b.moteClock * 0.42 + seed.phase) % 1;
				const r = seed.radius * (0.4 + u * (0.9 + fast * 1.2));
				const a = seed.angle + u * (2 + fast * 3);
				positions.setXYZ(
					i,
					b.moteOrigin.x + Math.cos(a) * r,
					b.moteOrigin.y + u * (2.6 - fast * 0.9),
					b.moteOrigin.z + Math.sin(a) * r,
				);
				const fade = Math.sin(u * Math.PI) * b.moteK * (0.75 + fast * 0.5);
				colors.setXYZ(i, tmp.r * fade, tmp.g * fade, tmp.b * fade);
			}
			positions.needsUpdate = true;
			colors.needsUpdate = true;
		} else {
			b.motes.visible = false;
		}

		// the tick over a finished building always faces the camera
		const pop =
			b.doneK < 0.02 ? 0 : b.doneK * (1 + 0.3 * Math.sin(b.doneK * Math.PI));
		b.check.visible = pop > 0;
		if (pop > 0) {
			b.check.scale.setScalar(pop * 1.25);
			b.check.quaternion.copy(camera.quaternion);
			b.check.position.y =
				b.height + 0.5 + (reduced ? 0 : Math.sin(t * 1.6 + b.phase) * 0.07);
		}
	}

	function updateBeacon(dt, t) {
		const s = BEACONS[beaconMode];
		const k = 1 - Math.exp(-dt * 4);
		beaconNow.glow += (s.glow - beaconNow.glow) * k;
		beaconNow.spin += ((reduced ? 0 : s.spin) - beaconNow.spin) * k;
		beaconNow.light += (s.light - beaconNow.light) * k;
		beaconNow.halo += (s.halo - beaconNow.halo) * k;
		beaconNow.inlay += (s.inlay - beaconNow.inlay) * k;
		beaconNow.color.lerp(s.color, k);
		const wave = reduced ? 0 : Math.sin(t * s.rate) * s.pulse;
		beacon.material.emissive.copy(beaconNow.color);
		beacon.material.emissiveIntensity = beaconNow.glow * (1 + wave);
		beacon.light.color.copy(beaconNow.color);
		beacon.light.intensity = beaconNow.light * (1 + wave);
		beacon.halo.material.color.copy(beaconNow.color);
		beacon.halo.material.opacity = beaconNow.halo * (1 + wave * 0.5);
		beacon.inlay.material.color.copy(beaconNow.color);
		beacon.inlay.material.opacity = Math.min(
			1,
			beaconNow.inlay * (1 + wave * 0.5),
		);
		beacon.crystal.rotation.y += dt * beaconNow.spin;
		beacon.hoop.rotation.z += dt * beaconNow.spin * 0.7;
		if (!reduced) beacon.crystal.position.y = 2.25 + Math.sin(t * 1.1) * 0.09;
	}

	/* --------------------------- couriers and bursts -------------------------- */

	// short-lived effects; each returns false from update() once it is over
	const effects = new Set();
	const pending = new Set(); // resolvers of couriers still in flight

	function addFlash(at, color, size = 3.2, seconds = 0.45) {
		const sprite = new THREE.Sprite(
			new THREE.SpriteMaterial({ map: glowTexture(), color, ...ADDITIVE }),
		);
		sprite.position.copy(at);
		scene.add(sprite);
		let age = 0;
		effects.add({
			update(dt) {
				age += dt;
				const u = Math.min(age / seconds, 1);
				sprite.scale.setScalar(0.6 + u * size);
				sprite.material.opacity = (1 - u) * 0.9;
				return u < 1;
			},
			dispose() {
				scene.remove(sprite);
				sprite.material.dispose();
			},
		});
	}

	function sendCourier(fromId, toId) {
		const from = docks.get(fromId);
		const to = docks.get(toId);
		if (!from || !to || fromId === toId) return Promise.resolve();
		const color = (agents.get(fromId)?.vivid || VIOLET).clone();
		const distance = from.distanceTo(to);
		const seconds = reduced
			? 0.3
			: THREE.MathUtils.clamp(0.8 + distance * 0.04, 0.95, 1.4);

		return new Promise((resolve) => {
			// a timer rather than the render loop resolves this, so a hidden tab
			// (whose frames stop) never leaves a mission waiting on a courier
			const finish = () => {
				clearTimeout(timer);
				pending.delete(finish);
				resolve();
			};
			const timer = setTimeout(finish, seconds * 1000);
			pending.add(finish);

			if (reduced) return addFlash(to, color, 2.4, 0.3);

			const control = from.clone().add(to).multiplyScalar(0.5);
			control.y = 4.2 + distance * 0.3;
			const curve = new THREE.QuadraticBezierCurve3(from, control, to);
			const group = new THREE.Group();
			const TRAIL = 10;
			const pale = color.clone().lerp(new THREE.Color('#ffffff'), 0.6);
			const sprites = Array.from({ length: TRAIL }, (_, i) => {
				const sprite = new THREE.Sprite(
					new THREE.SpriteMaterial({
						map: glowTexture(),
						color: i ? color : pale,
						opacity: i ? 0.85 * (1 - i / TRAIL) : 1,
						...ADDITIVE,
					}),
				);
				sprite.scale.setScalar(i ? 1.5 * (1 - i / (TRAIL + 3)) : 2.3);
				group.add(sprite);
				return sprite;
			});
			// a solid core, so the courier still reads as a dot against a lit wall
			const core = new THREE.Mesh(
				new THREE.IcosahedronGeometry(0.17, 1),
				new THREE.MeshBasicMaterial({ color: pale, toneMapped: false }),
			);
			group.add(core);
			scene.add(group);
			const started = performance.now();
			addFlash(from, color, 1.8, 0.3);
			effects.add({
				update() {
					const u = Math.min(
						(performance.now() - started) / (seconds * 1000),
						1,
					);
					const eased = easeInOut(u);
					sprites.forEach((sprite, i) => {
						curve.getPoint(Math.max(0, eased - i * 0.03), sprite.position);
					});
					core.position.copy(sprites[0].position);
					if (u < 1) return true;
					addFlash(to, color);
					return false;
				},
				dispose() {
					scene.remove(group);
					for (const sprite of sprites) sprite.material.dispose();
					core.geometry.dispose();
					core.material.dispose();
				},
			});
		});
	}

	/** The one-off celebration when a mission lands on the plaza. */
	function burst() {
		if (reduced) return addFlash(docks.get(PLAZA), BEACONS.done.color, 6, 0.5);
		const ring = new THREE.Mesh(
			new THREE.RingGeometry(0.86, 1, 40),
			new THREE.MeshBasicMaterial({
				color: BEACONS.done.color,
				side: THREE.DoubleSide,
				...ADDITIVE,
			}),
		);
		ring.rotation.x = -Math.PI / 2;
		ring.position.y = 0.3;
		const COUNT = 36;
		const positions = new Float32Array(COUNT * 3);
		const velocity = Array.from({ length: COUNT }, (_, i) => {
			const a = (i / COUNT) * Math.PI * 2 + (i % 3);
			const out = 1.6 + ((i * 0.37) % 1) * 2.6;
			return new THREE.Vector3(
				Math.cos(a) * out,
				4.5 + ((i * 0.61) % 1) * 3.5,
				Math.sin(a) * out,
			);
		});
		const geo = new THREE.BufferGeometry();
		geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
		const sparks = new THREE.Points(
			geo,
			new THREE.PointsMaterial({
				size: 0.6,
				map: glowTexture(),
				color: '#d9ccff',
				...ADDITIVE,
			}),
		);
		sparks.frustumCulled = false;
		scene.add(ring, sparks);
		addFlash(docks.get(PLAZA), BEACONS.done.color, 9, 0.7);
		let age = 0;
		effects.add({
			update(dt) {
				age += dt;
				const u = Math.min(age / 1.5, 1);
				ring.scale.setScalar(1 + u * 9);
				ring.material.opacity = (1 - u) * 0.9;
				for (let i = 0; i < COUNT; i++) {
					const v = velocity[i];
					positions[i * 3] = v.x * age;
					positions[i * 3 + 1] = 2.25 + v.y * age - 4.2 * age * age;
					positions[i * 3 + 2] = v.z * age;
				}
				geo.attributes.position.needsUpdate = true;
				sparks.material.opacity = 1 - u;
				return u < 1;
			},
			dispose() {
				scene.remove(ring, sparks);
				ring.geometry.dispose();
				ring.material.dispose();
				geo.dispose();
				sparks.material.dispose();
			},
		});
	}

	/* --------------------------------- camera -------------------------------- */

	const controls = new OrbitControls(camera, canvas);
	controls.enableDamping = true;
	controls.dampingFactor = 0.08;
	controls.enablePan = false;
	controls.rotateSpeed = 0.6;
	controls.zoomSpeed = 0.8;
	controls.minPolarAngle = 0.25;
	controls.maxPolarAngle = 1.36; // stops short of the horizon, so never under the island
	controls.minDistance = 6;
	controls.autoRotateSpeed = 0.45;

	let width = 1;
	let height = 1;
	let insets = { top: 0, right: 0, bottom: 0, left: 0 };
	let focusId = null;
	let userMoved = false; // has the person taken the camera since the last focus()
	let lastTouch = performance.now();
	let tween = null;
	const spherical = new THREE.Spherical();
	const offset = new THREE.Vector3();

	/** How far back the camera must sit for a box this big to fit the clear area. */
	function fit(halfWidth, halfHeight) {
		const clearW = Math.max(80, width - insets.left - insets.right);
		const clearH = Math.max(80, height - insets.top - insets.bottom);
		return Math.max(
			halfWidth / ((TAN_HALF_FOV * clearW) / height),
			halfHeight / ((TAN_HALF_FOV * clearH) / height),
		);
	}

	function currentPose() {
		offset.copy(camera.position).sub(controls.target);
		spherical.setFromVector3(offset);
		return {
			target: controls.target.clone(),
			radius: spherical.radius,
			phi: spherical.phi,
			theta: spherical.theta,
		};
	}

	function setPose(pose) {
		spherical.set(pose.radius, pose.phi, pose.theta);
		camera.position.setFromSpherical(spherical).add(pose.target);
		controls.target.copy(pose.target);
		camera.lookAt(pose.target);
	}

	function overviewPose() {
		const clearW = width - insets.left - insets.right;
		const clearH = height - insets.top - insets.bottom;
		// look down more steeply on a tall screen, where height is going spare
		const phi = clearW < clearH * 0.8 ? 0.8 : 0.95;
		const halfHeight =
			ISLAND_RADIUS * Math.cos(phi) + 3.4 * Math.sin(phi) + 1.3;
		return {
			target: new THREE.Vector3(0, 1.4, 0),
			radius: fit(ISLAND_RADIUS + 0.5, halfHeight) * 1.03,
			phi,
			theta: currentPose().theta,
		};
	}

	function goalPose() {
		const b = agents.get(focusId);
		if (!b) return overviewPose();
		return {
			target: new THREE.Vector3(b.pos.x, b.height * 0.5 + 0.2, b.pos.z),
			radius: Math.max(11, fit(b.pickW / 2 + 1.5, b.height / 2 + 1.7) * 1.05),
			// high enough to see over the buildings behind the camera
			phi: 0.96,
			// stand on the plaza side, a little off-axis so the building has depth
			theta: -b.angle + 0.3,
		};
	}

	function moveTo(goal, seconds) {
		controls.maxDistance = Math.max(
			55,
			overviewPose().radius * 1.3,
			goal.radius * 1.05,
		);
		if (reduced || seconds <= 0) {
			tween = null;
			controls.enabled = true;
			setPose(goal);
			controls.update();
			return;
		}
		const from = currentPose();
		const turn = goal.theta - from.theta;
		tween = {
			from,
			to: goal,
			turn: Math.atan2(Math.sin(turn), Math.cos(turn)),
			t: 0,
			seconds,
		};
		controls.enabled = false;
	}

	function updateCamera(dt, now) {
		if (tween) {
			tween.t = Math.min(tween.t + dt / tween.seconds, 1);
			const k = easeInOut(tween.t);
			const { from, to } = tween;
			setPose({
				target: from.target.clone().lerp(to.target, k),
				radius: from.radius + (to.radius - from.radius) * k,
				phi: from.phi + (to.phi - from.phi) * k,
				theta: from.theta + tween.turn * k,
			});
			if (tween.t >= 1) {
				tween = null;
				controls.enabled = true;
				lastTouch = now;
			}
			return;
		}
		controls.autoRotate = !reduced && !focusId && now - lastTouch > 5000;
		controls.update(dt);
	}

	function applyViewOffset() {
		const dx = (insets.left - insets.right) / 2;
		const dy = (insets.top - insets.bottom) / 2;
		if (dx || dy) camera.setViewOffset(width, height, -dx, -dy, width, height);
		else camera.clearViewOffset();
		camera.updateProjectionMatrix();
	}

	function resize() {
		const host = canvas.parentElement || canvas;
		const w = Math.max(1, Math.round(host.clientWidth || window.innerWidth));
		const h = Math.max(1, Math.round(host.clientHeight || window.innerHeight));
		if (w === width && h === height) return;
		const first = width === 1 && height === 1;
		width = w;
		height = h;
		renderer.setSize(w, h, false);
		camera.aspect = w / h;
		applyViewOffset();
		if (first) {
			setPose({ ...overviewPose(), theta: 0 });
			controls.maxDistance = Math.max(55, overviewPose().radius * 1.3);
			controls.update();
		} else if (!userMoved) {
			moveTo(goalPose(), 0);
		}
	}

	function setInsets(next = {}) {
		const clean = (n) => (Number.isFinite(n) && n > 0 ? n : 0);
		const wanted = {
			top: clean(next.top),
			right: clean(next.right),
			bottom: clean(next.bottom),
			left: clean(next.left),
		};
		if (
			['top', 'right', 'bottom', 'left'].every(
				(side) => wanted[side] === insets[side],
			)
		)
			return;
		insets = wanted;
		applyViewOffset();
		if (!userMoved) moveTo(goalPose(), 0.45);
	}

	function focus(id) {
		focusId = agents.has(id) ? id : null;
		userMoved = false;
		moveTo(goalPose(), 0.9);
	}

	controls.addEventListener('start', () => {
		userMoved = true;
		lastTouch = performance.now();
	});
	controls.addEventListener('end', () => (lastTouch = performance.now()));

	/* -------------------------------- picking -------------------------------- */

	const raycaster = new THREE.Raycaster();
	const pointer = new THREE.Vector2();
	const pickers = new Set();
	const touching = new Set();
	let press = null;
	let hover = null; // last mouse position, tested once per frame

	function pickAt(clientX, clientY) {
		const rect = canvas.getBoundingClientRect();
		if (!rect.width || !rect.height) return null;
		pointer.set(
			((clientX - rect.left) / rect.width) * 2 - 1,
			-((clientY - rect.top) / rect.height) * 2 + 1,
		);
		raycaster.setFromCamera(pointer, camera);
		const hit = raycaster.intersectObjects(proxies, false)[0];
		return hit ? hit.object.userData.pick : null;
	}

	const onDown = (e) => {
		lastTouch = performance.now();
		if (tween) {
			// taking hold of the camera cancels a move that is still easing
			tween = null;
			controls.enabled = true;
		}
		touching.add(e.pointerId);
		press =
			touching.size === 1
				? { id: e.pointerId, x: e.clientX, y: e.clientY, at: performance.now() }
				: null;
	};
	const onUp = (e) => {
		touching.delete(e.pointerId);
		const p = press;
		if (!p || p.id !== e.pointerId) return;
		press = null;
		const moved = Math.hypot(e.clientX - p.x, e.clientY - p.y);
		if (moved > 7 || performance.now() - p.at > 600) return; // that was a drag
		const id = pickAt(e.clientX, e.clientY);
		if (id) for (const cb of pickers) cb(id);
	};
	const onCancel = (e) => {
		touching.delete(e.pointerId);
		press = null;
	};
	const onMove = (e) => {
		if (e.pointerType === 'mouse') hover = { x: e.clientX, y: e.clientY };
	};
	canvas.addEventListener('pointerdown', onDown, true);
	canvas.addEventListener('pointerup', onUp);
	canvas.addEventListener('pointercancel', onCancel);
	canvas.addEventListener('pointermove', onMove);

	/* ------------------------------- render loop ----------------------------- */

	const frameCallbacks = new Set();
	let raf = 0;
	let last = 0;
	let clock = 0;
	let disposed = false;

	function frame(now) {
		raf = requestAnimationFrame(frame);
		const dt = Math.min((now - last) / 1000, 0.1);
		last = now;
		clock += dt;
		updateCamera(dt, now);
		for (const b of agents.values()) updateAgent(b, dt, clock);
		updateBeacon(dt, clock);
		for (const effect of effects) {
			if (effect.update(dt)) continue;
			effect.dispose();
			effects.delete(effect);
		}
		if (hover) {
			canvas.style.cursor = touching.size
				? 'grabbing'
				: pickAt(hover.x, hover.y)
					? 'pointer'
					: 'grab';
			hover = null;
		}
		renderer.render(scene, camera);
		for (const cb of frameCallbacks) cb();
	}

	function start() {
		if (raf || disposed || document.hidden) return;
		last = performance.now();
		raf = requestAnimationFrame(frame);
	}
	function stop() {
		cancelAnimationFrame(raf);
		raf = 0;
	}
	const onVisibility = () => (document.hidden ? stop() : start());
	document.addEventListener('visibilitychange', onVisibility);

	const observer = new ResizeObserver(resize);
	observer.observe(canvas.parentElement || canvas);
	resize();
	start();

	/* ---------------------------------- API ---------------------------------- */

	const projected = new THREE.Vector3();

	return {
		/** 'idle' | 'queued' | 'thinking' | 'writing' | 'done' | 'skipped' | 'error' */
		setState(id, state) {
			const b = agents.get(id);
			if (b && STATES[state]) b.state = state;
		},

		/** Fly a courier between two buildings (or the plaza). Resolves on arrival. */
		sendCourier,

		/** 'idle' | 'running' | 'done' | 'error' */
		setBeacon(mode) {
			if (!BEACONS[mode] || mode === beaconMode) return;
			beaconMode = mode;
			if (mode === 'done') burst();
		},

		/** Ease the camera to a building; null or 'plaza' returns to the overview. */
		focus,

		/** CSS px of the canvas hidden under HUD, so the view centres in the rest. */
		setInsets,

		/** cb(id) when a building, its villager or the beacon ('plaza') is tapped. */
		onPick(cb) {
			pickers.add(cb);
			return () => pickers.delete(cb);
		},

		/** Where a label for this building belongs, in CSS px from the canvas corner. */
		anchor(id) {
			const at = anchors.get(id);
			if (!at) return { x: 0, y: 0, visible: false };
			projected.copy(at).project(camera);
			return {
				x: (projected.x * 0.5 + 0.5) * width,
				y: (-projected.y * 0.5 + 0.5) * height,
				visible: projected.z > -1 && projected.z < 1,
			};
		},

		/** cb() after every rendered frame. */
		onFrame(cb) {
			frameCallbacks.add(cb);
			return () => frameCallbacks.delete(cb);
		},

		resize,

		dispose() {
			if (disposed) return;
			disposed = true;
			stop();
			observer.disconnect();
			document.removeEventListener('visibilitychange', onVisibility);
			reduceQuery.removeEventListener('change', onReduce);
			canvas.removeEventListener('pointerdown', onDown, true);
			canvas.removeEventListener('pointerup', onUp);
			canvas.removeEventListener('pointercancel', onCancel);
			canvas.removeEventListener('pointermove', onMove);
			for (const finish of [...pending]) finish(); // nobody is left waiting on a courier
			for (const effect of effects) effect.dispose();
			effects.clear();
			controls.dispose();
			scene.traverse((object) => {
				object.geometry?.dispose();
				for (const material of [].concat(object.material || []))
					material.dispose();
			});
			scene.background?.dispose();
			glowTexture().dispose();
			frameCallbacks.clear();
			pickers.clear();
			renderer.dispose();
		},
	};
}
