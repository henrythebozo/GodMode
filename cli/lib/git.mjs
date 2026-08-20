/* Git sync for the vault.
 *
 * The vault is already a folder of plain text files, so the sync problem was
 * solved before it was asked: git does versioning, conflict detection, offline
 * work and history, and it works on every machine you have. Nothing here
 * reimplements any of that — this shells out to the real `git`, which is the
 * one dependency worth having and is not an npm package.
 *
 * The one place git's default behaviour is wrong for a vault is a CONFLICT.
 * Git's answer is to write <<<<<<< markers into the file, which for a markdown
 * note means a corrupted body and, if the clash reaches the top of the file, a
 * frontmatter block that no longer parses. A note is not source code and
 * nobody is going to resolve it in an editor with a three-way merge tool. So
 * both sides are kept as whole notes instead, and you decide later, reading
 * them side by side in Obsidian like the prose they are.
 */
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { identifyKey } from './config.mjs';

/* `.jarvis/` inside the vault is machine state, and only some of it travels.
 * chains are worth having on every machine; a usage ledger and a rendered
 * graph are about one machine and would conflict on every single sync. */
export const GITIGNORE = [
	'# Written by `jarvis vault init`.',
	'#',
	'# Machine-local state. usage.json is this machine\'s spend and graph.html is',
	'# a rendered snapshot — both would conflict on every sync and neither means',
	'# anything on another computer. chains.json is deliberately NOT ignored: a',
	'# chain is worth having wherever you are.',
	'.jarvis/usage.json',
	'.jarvis/graph.html',
	'',
	'# Never. Keys live in ~/.jarvis/config.json, outside the vault, precisely so',
	'# that syncing the vault cannot publish them — this is the second lock.',
	'config.json',
	'*.pem',
	'.env',
	'',
].join('\n');

export function git(vault, args, opts) {
	const r = spawnSync('git', args, { cwd: vault, encoding: 'utf8', ...(opts || {}) });
	if (r.error && r.error.code === 'ENOENT') {
		const e = new Error('git is not installed, or not on PATH. Install it and try again — everything else in Jarvis works without it.');
		e.noGit = true;
		throw e;
	}
	return { code: r.status, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

export function hasGit() {
	try { return git(process.cwd(), ['--version']).code === 0; } catch { return false; }
}

export function isRepo(vault) {
	try { return git(vault, ['rev-parse', '--git-dir']).code === 0; } catch { return false; }
}

export function remoteUrl(vault) {
	const r = git(vault, ['remote', 'get-url', 'origin']);
	return r.code === 0 ? r.out : '';
}

export function branchName(vault) {
	const r = git(vault, ['rev-parse', '--abbrev-ref', 'HEAD']);
	return r.code === 0 ? r.out : '';
}

/* --------------------------- looking before leaping ----------------------
 * A vault is meant to be pushed somewhere, and "somewhere" is very often a
 * public repository. A key that has been pushed is a key that has to be
 * revoked, and no amount of history rewriting afterwards makes that untrue.
 * So every file that is about to travel is read first and every token in it is
 * matched against the same four shapes the paste handler uses. */
export function scanForSecrets(vault) {
	/* Exactly the set git would take — tracked files plus untracked ones that
	 * are not ignored. Asking git once beats walking the tree and running
	 * `check-ignore` per file, which is a subprocess per note. An ignored file
	 * is not scanned, because an ignored file cannot leak. */
	const listed = git(vault, ['ls-files', '-co', '--exclude-standard']);
	if (listed.code !== 0 || !listed.out) return [];
	const hits = [];
	for (const rel of listed.out.split('\n').filter(Boolean)) {
		const full = path.join(vault, rel);
		let text = '';
		try {
			if (fs.statSync(full).size > 2 * 1024 * 1024) continue;   // not a note
			text = fs.readFileSync(full, 'utf8');
		} catch { continue; }
		if (text.includes('\0')) continue;                            // binary
		for (const token of text.split(/[\s"'`,;<>()[\]{}]+/)) {
			const hit = identifyKey(token);
			if (hit) hits.push({ file: rel, label: hit.label, shown: token.slice(0, 8) + '…' + token.slice(-4) });
		}
	}
	return hits;
}

/* ----------------------- git inside a file syncer ------------------------
 * The one setup in this plan that quietly destroys data. Dropbox, iCloud and
 * the rest sync a directory file by file, in whatever order they please, with
 * no idea that the loose objects, the packfiles and the refs pointing at them
 * are a single consistent structure. A repository half-copied that way is
 * corrupt, and the corruption shows up long after the choice that caused it.
 *
 * Pick one mechanism per folder: git, OR a file syncer. Never both.
 *
 * These patterns are deliberately conservative. A false positive blocks a
 * setup that was perfectly fine and teaches people to reach for the override,
 * so a folder merely CALLED "Sync" or "Box" is not enough — only the names
 * these products actually create.
 */
const CLOUD_FOLDERS = [
	['iCloud Drive', /(^|\/)Library\/Mobile Documents(\/|$)/i],
	['iCloud Drive', /(^|\/)iCloudDrive(\/|$)/i],                    // Windows
	['a cloud folder', /(^|\/)Library\/CloudStorage(\/|$)/i],        // macOS 12+ mounts Dropbox, Drive, OneDrive and Box here
	['Dropbox', /(^|\/)Dropbox( \([^/]*\))?(\/|$)/i],
	['Google Drive', /(^|\/)Google ?Drive[^/]*(\/|$)/i],
	['Google Drive', /(^|\/)My Drive(\/|$)/i],
	['OneDrive', /(^|\/)OneDrive[^/]*(\/|$)/i],
	['Nextcloud', /(^|\/)Nextcloud(\/|$)/i],
	['ownCloud', /(^|\/)ownCloud(\/|$)/i],
	['pCloud', /(^|\/)pCloudDrive(\/|$)/i],
	['MEGA', /(^|\/)MEGA(sync)?(\/|$)/i],
	['Proton Drive', /(^|\/)Proton ?Drive(\/|$)/i],
];

/* Symlinks are the whole point of resolving first: `~/jarvis-vault` pointing
 * into iCloud is a normal thing to do and looks completely innocent from the
 * path alone. The vault may not exist yet at init, so this resolves the
 * nearest ancestor that does and re-attaches the rest. */
export function realish(p) {
  let cur = path.resolve(p);
  const tail = [];
  for (;;) {
    try { return path.join(fs.realpathSync(cur), ...tail.slice().reverse()); }
    catch {
      const parent = path.dirname(cur);
      if (parent === cur) return path.resolve(p);
      tail.push(path.basename(cur));
      cur = parent;
    }
  }
}

/* The name of the service syncing this folder, or '' if nothing looks like one. */
export function cloudSyncName(dir) {
	const p = realish(dir).split(path.sep).join('/');
	for (const [name, re] of CLOUD_FOLDERS) if (re.test(p)) return name;
	return '';
}

/* ------------------------------- the basics ------------------------------ */

export function initRepo(vault, remote) {
	fs.mkdirSync(vault, { recursive: true });
	const made = [];
	const fresh = !isRepo(vault);
	if (fresh) {
		git(vault, ['init', '-q']);
		made.push('repository');
		/* `main`, not whatever this machine's git happens to default to — two
		 * clones disagreeing about the branch name is a confusing first push.
		 * Only on a repository we just made: renaming the branch of one that
		 * already has history would leave that history on the old branch and
		 * push an empty `main` over the top of it. */
		if (branchName(vault) !== 'main') git(vault, ['checkout', '-q', '-B', 'main']);
	}
	const ignorePath = path.join(vault, '.gitignore');
	if (!fs.existsSync(ignorePath)) { fs.writeFileSync(ignorePath, GITIGNORE, 'utf8'); made.push('.gitignore'); }
	if (remote) {
		if (remoteUrl(vault)) git(vault, ['remote', 'set-url', 'origin', remote]);
		else { git(vault, ['remote', 'add', 'origin', remote]); made.push('origin'); }
	}
	return made;
}

/* Everything not yet committed, as paths. */
export function pendingChanges(vault) {
	const r = git(vault, ['status', '--porcelain']);
	if (r.code !== 0 || !r.out) return [];
	return r.out.split('\n').map((l) => ({ code: l.slice(0, 2).trim(), file: l.slice(3).trim() }));
}

export function aheadBehind(vault) {
	const branch = branchName(vault);
	const r = git(vault, ['rev-list', '--left-right', '--count', 'origin/' + branch + '...' + branch]);
	if (r.code !== 0) return null;                        // no upstream yet
	const [behind, ahead] = r.out.split(/\s+/).map(Number);
	return { ahead: ahead || 0, behind: behind || 0 };
}

export function commitAll(vault, message) {
	git(vault, ['add', '-A']);
	const staged = git(vault, ['diff', '--cached', '--name-only']);
	if (!staged.out) return null;                         // nothing to record
	const r = git(vault, ['commit', '-q', '-m', message]);
	if (r.code !== 0) throw new Error(r.err || r.out || 'git commit failed');
	return staged.out.split('\n').filter(Boolean);
}

/* ---------------------------- conflict handling -------------------------- */

function freeConflictPath(vault, rel) {
	const dir = path.dirname(rel), base = path.basename(rel, '.md');
	let name = base + ' (conflict)', i = 2;
	while (fs.existsSync(path.join(vault, dir, name + '.md'))) name = base + ' (conflict ' + i++ + ')';
	return dir === '.' ? name + '.md' : dir + '/' + name + '.md';
}

/* The copy gets its own title. Leaving both notes called "Noah" would make
 * every [[Noah]] ambiguous and hide the duplicate in the graph, which is the
 * opposite of what a conflict needs — it should be impossible to miss. */
function retitle(text, title) {
	if (!text.startsWith('---\n')) return text;
	const end = text.indexOf('\n---', 3);
	if (end < 0) return text;
	const head = text.slice(0, end).replace(/^title:.*$/m, 'title: ' + title);
	return head + text.slice(end);
}

function stage(vault, rel) {
	const r = git(vault, ['show', ':' + rel]);
	return r.code === 0 ? r.out : null;
}

/* Both sides survive: ours stays where it was, theirs becomes a sibling note
 * with "(conflict)" in its name and title. Nothing is merged line by line and
 * nothing is thrown away. */
export function resolveConflicts(vault) {
	const unmerged = git(vault, ['diff', '--name-only', '--diff-filter=U']);
	if (unmerged.code !== 0 || !unmerged.out) return [];
	const resolved = [];
	for (const rel of unmerged.out.split('\n').filter(Boolean)) {
		const ours = stage(vault, '2:' + rel);
		const theirs = stage(vault, '3:' + rel);
		if (ours === null && theirs === null) { git(vault, ['rm', '-q', '--', rel]); continue; }
		/* Modified on one side, deleted on the other: a deletion should never
		 * win over an edit, because the edit is the newer intent and the
		 * deletion can be repeated in one keystroke. */
		if (ours === null || theirs === null) {
			fs.writeFileSync(path.join(vault, rel), ours === null ? theirs : ours, 'utf8');
			git(vault, ['add', '--', rel]);
			resolved.push({ file: rel, kept: 'both', copy: null, note: 'edited on one side, deleted on the other — the edit was kept' });
			continue;
		}
		if (ours === theirs) { git(vault, ['add', '--', rel]); continue; }
		if (!rel.endsWith('.md')) {
			/* Not a note — no sensible "keep both", so ours stands and the
			 * person is told which file it was. */
			fs.writeFileSync(path.join(vault, rel), ours, 'utf8');
			git(vault, ['add', '--', rel]);
			resolved.push({ file: rel, kept: 'ours', copy: null, note: 'not a note, so this machine\'s version was kept' });
			continue;
		}
		const copyRel = freeConflictPath(vault, rel);
		const copyTitle = path.basename(copyRel, '.md');
		fs.mkdirSync(path.dirname(path.join(vault, copyRel)), { recursive: true });
		fs.writeFileSync(path.join(vault, copyRel), retitle(theirs, copyTitle), 'utf8');
		fs.writeFileSync(path.join(vault, rel), ours, 'utf8');
		git(vault, ['add', '--', rel, copyRel]);
		resolved.push({ file: rel, kept: 'both', copy: copyRel, note: null });
	}
	return resolved;
}

/* Fetch and merge, keeping both sides of anything that clashes. Returns what
 * happened rather than printing it — the caller owns the console. */
export function pull(vault) {
	const branch = branchName(vault);
	const fetched = git(vault, ['fetch', 'origin', branch]);
	if (fetched.code !== 0) {
		if (/couldn't find remote ref|Couldn't find remote ref/.test(fetched.err)) return { empty: true, changed: [], conflicts: [] };
		throw new Error(fetched.err || 'could not reach the remote');
	}
	const before = git(vault, ['rev-parse', 'HEAD']).out;
	const merged = git(vault, ['merge', '--no-edit', 'origin/' + branch]);
	let conflicts = [];
	if (merged.code !== 0) {
		conflicts = resolveConflicts(vault);
		if (!conflicts.length && git(vault, ['diff', '--name-only', '--diff-filter=U']).out) {
			git(vault, ['merge', '--abort']);
			throw new Error(merged.err || 'the merge could not be resolved automatically and was rolled back');
		}
		const done = git(vault, ['commit', '--no-edit', '-q']);
		if (done.code !== 0 && git(vault, ['diff', '--name-only', '--diff-filter=U']).out) {
			git(vault, ['merge', '--abort']);
			throw new Error('the merge could not be completed and was rolled back');
		}
	}
	const after = git(vault, ['rev-parse', 'HEAD']).out;
	const changed = before === after ? [] : (git(vault, ['diff', '--name-only', before, after]).out || '').split('\n').filter(Boolean);
	return { empty: false, changed, conflicts };
}

export function push(vault) {
	const branch = branchName(vault);
	const r = git(vault, ['push', '-u', 'origin', branch]);
	if (r.code !== 0) throw new Error(r.err || r.out || 'git push failed');
	return true;
}
