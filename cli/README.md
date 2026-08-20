# jarvis — the terminal half

A personal assistant that keeps its memory as **plain markdown files on your
disk**, linked to each other with `[[wikilinks]]`. Not a database, not a
proprietary format: a folder you can open in Obsidian, put in a git repo, grep,
or edit in vim, and the graph comes out the same however you edited it.

Zero dependencies. Node built-ins only — there is no lockfile, no build step,
and nothing to go stale.

```
$ jarvis "what's on my plate today"
$ jarvis mem add "Noah starts school Sept 3" -f People -t Noah
$ jarvis mem link Noah "Homeschool Portal"
$ jarvis graph --open
```

---

## Setup

You need Node 18 or newer (`node --version`).

```sh
git clone https://github.com/henrythebozo/GodMode
cd GodMode/cli
npm link          # puts `jarvis` on your PATH
jarvis login      # opens a browser, no key to paste
```

`npm link` needs no network and installs nothing — there is nothing to install.
If you would rather not touch your global npm prefix, skip it and add an alias
instead:

```sh
echo "alias jarvis='node $PWD/jarvis.mjs'" >> ~/.zshrc && source ~/.zshrc
```

`jarvis init` asks four things — where the vault lives, which provider, your
key, and what to call each other — then creates the vault and writes
`~/.jarvis/config.json` with `0600` permissions. Add `--yes` to take every
default without being asked, which is what you want from a dotfiles script.

### Signing in, or a key

`jarvis login` runs OpenRouter's OAuth: it binds a server to `127.0.0.1` on a
port the OS picks, opens your browser, takes the code off the callback and
exchanges it with PKCE. Nothing is exposed past the loopback interface and the
server exists only for the length of the sign-in. On a machine with no browser
— a container, anything over ssh — `jarvis login --manual` prints a URL you can
open anywhere and paste the key back from. `jarvis logout` forgets it here and
leaves your OpenRouter account alone.

**Only OpenRouter can be signed into, and that is not a shortcut we took.**
Anthropic's OAuth is reserved for Anthropic's own clients — there is no public
client registration that would let this offer "Sign in with Claude", and a
claude.ai login grants no API access. Google's exists but wants a Cloud
project, an enabled API, a consent screen and a `client_secret.json`, which is
more work than the AI Studio key it would replace. OpenRouter brokers Claude,
Gemini and GPT, so signing in there reaches all three regardless.

### Keys

If you would rather bring your own, they are read from the environment first
and the config file second. Whichever you prefer:

```sh
export ANTHROPIC_API_KEY=sk-ant-...      # or OPENAI_API_KEY, OPENROUTER_API_KEY, GEMINI_API_KEY
```

A key that only ever came from the environment is never written back to disk —
saving it would quietly turn a per-shell secret into a stored one. If you want
it stored, say so:

```sh
jarvis key            # what is set, and whether it came from a variable or the file
jarvis key import     # pick up whatever is already exported in this shell
```

`jarvis key import` is the one command allowed to break that rule, because
breaking it is the whole point — afterwards the key works in every shell, not
only the one that exported it. It shows each key redacted before storing
anything, and points out a key exported under the wrong variable name (an
Anthropic key in `OPENAI_API_KEY` is the mistake that actually happens),
though it will still store it if you say so — a shape is a guess and you know
what you copied.

To file a key you have just copied, without hunting for which setting it
belongs to:

```sh
pbpaste | jarvis key add          # macOS; wl-paste or xclip -o elsewhere
jarvis key add                    # or just run it and paste at the prompt
```

It works out which provider the key belongs to from its shape, so there is
nothing to choose. Reading it from stdin also keeps it out of your shell
history, which passing it as an argument would not. `jarvis key rm anthropic`
forgets one — and tells you if the variable is still exported, since otherwise
it silently reappears on the next command.

Storing a key also repoints the lead model **only if the current one has become
unreachable**. Import a Gemini key while Claude is already working and nothing
moves; import one with no key for the model you are pointed at and it moves to
the vendor you just configured, rather than failing on your first question.

**Keys live in `~/.jarvis/`, never in the vault.** The vault is the thing you
are meant to sync, share and commit; a credential riding along inside it ends
up pushed somewhere public eventually.

### A local model instead

Anything speaking the OpenAI API works — Ollama, llama.cpp, LM Studio, a
company gateway:

```sh
jarvis config baseUrl http://localhost:11434/v1
jarvis config model llama3.2
```

No key is demanded when you are not pointed at the hosted default.

---

## The vault

```
~/jarvis-vault/
├── People/
│   └── Noah.md
├── Projects/
│   ├── APEX.md
│   └── Homeschool Portal.md
├── Areas/
├── Topics/
└── .jarvis/
    ├── chains.json
    ├── usage.json
    └── graph.html        ← written by `jarvis graph --open`
```

A note is a markdown file:

```md
---
title: Noah
folder: People
created: 2026-08-20T02:07:44.812Z
updated: 2026-08-20T02:09:01.004Z
---

Noah starts school Sept 3 and needs a laptop.

Related: [[APEX]], [[Homeschool Portal]]
```

**Links are only ever in the prose.** They are parsed out of the body every
time it is read and stored nowhere else, so there is one copy of the truth and
it cannot drift — edit the file in Obsidian, through this CLI, or by hand, and
the graph is identical. A link inside backticks is not a link, so a note that
merely quotes the syntax does not invent nodes.

A link to a note you have not written yet is fine and deliberate. Those show up
in the graph as hollow circles: the shape of what you have not got round to.

### Open it in Obsidian

Obsidian → *Open folder as vault* → pick `~/jarvis-vault`. That is the whole
setup. Its graph view and this one are the same graph, because it is the same
format.

### Sync it across machines, with git

The vault is a folder of text files, which is what git is for. No server, no
account beyond the one you already have, and every version of every note kept.

```sh
# once, on the first machine
jarvis vault init git@github.com:you/jarvis-vault.git
jarvis vault push

# once, on the second
git clone git@github.com:you/jarvis-vault.git ~/jarvis-vault

# from then on, on either
jarvis vault sync
```

`sync` is `pull` then `push`; the two exist separately for when you want one.
`jarvis vault` on its own says what is uncommitted and how far ahead or behind
the remote you are.

**Conflicts keep both notes.** Git's normal answer is to write `<<<<<<<`
markers into the file, which for a note means a mangled body and, if the clash
reaches the top, frontmatter that no longer parses. Instead, your version stays
where it is and the other machine's becomes `Noah (conflict).md` — retitled, so
it is its own node in the graph rather than a second ambiguous `[[Noah]]`. Read
both, keep what you want, delete the other.

**Nothing is pushed until it has been read for keys.** Every file that would
travel is checked against the same four key shapes the app matches a paste
against, and a push carrying one stops with the file named. Keys live in
`~/.jarvis/config.json`, outside the vault, exactly so this cannot happen — the
scan is the second lock, and `--allow-secrets` is there for a false positive.

`.jarvis/usage.json` and `.jarvis/graph.html` are gitignored: one machine's
spend and one machine's rendered snapshot, which would conflict on every sync
and mean nothing anywhere else. `chains.json` is deliberately *not* ignored.

Obsidian's own Git plugin works on the same repo, so a phone running Obsidian
mobile can join in — that is the one route the browser's folder sync cannot
take, since no mobile browser has the File System Access API.

---

## Commands

| | |
|---|---|
| `jarvis login [--manual]` | sign in with OpenRouter; `--manual` for a machine with no browser |
| `jarvis logout` | forget the key on this machine |
| `jarvis "question"` | ask; `ask` is optional |
| `jarvis ask "…" --model ID --no-memory` | pick a model, or send no notes |
| `jarvis mem add "…" -f Folder -t Title -l Other` | write a note, optionally linked |
| `jarvis mem list [query]` | newest first |
| `jarvis mem show <title>` | the note, its links out, and its links in |
| `jarvis mem link <a> <b>` | link both ways |
| `jarvis mem rm <title>` / `mem open <title>` | delete, or open in `$EDITOR` |
| `jarvis mem suggest [--apply]` | links you already wrote in prose without brackets |
| `jarvis graph` | counts, the most-connected notes, the unlinked ones |
| `jarvis graph <title> --depth N` | one note's neighbourhood, as a tree |
| `jarvis graph --open` | render the whole vault and open it in a browser |
| `jarvis chain add <name> <step>…` | a step is `note: Title` or `prompt: text` |
| `jarvis chain list` / `chain run <name>` | |
| `jarvis key` | which keys are set, and where each came from |
| `jarvis key import` | store the ones already exported in this shell |
| `jarvis key add [KEY]` | file a key by its shape; reads stdin if omitted |
| `jarvis key rm <provider>` | forget one |
| `jarvis vault` | uncommitted changes, and how far from the remote |
| `jarvis vault init [git-url]` | put the vault in git and point it at a remote |
| `jarvis vault push [-m "…"]` | commit everything and send it |
| `jarvis vault pull` | bring in what other machines wrote |
| `jarvis vault sync` | pull, then push — the everyday one |
| `jarvis usage` | tokens and cost, measured not estimated |
| `jarvis config [key [value]]` | show or set; keys print redacted |
| `jarvis export [file]` / `jarvis import <file>` | the bridge to the web app |

Asking a question hands the model an index of every note plus the handful that
actually look relevant — scored by term frequency with a rarity weight, then
expanded **one hop along the links** out of the best matches. That last part is
what the graph is for: ask about Noah and you also get the project Noah's note
points at, even though you never named it. It can write and link notes back
through the same `jarvis-action` protocol the web app uses.

`jarvis mem suggest` finds the links you have already written without meaning
to — a note saying "APEX is the project Noah helps with" is describing an edge,
it just has not got the brackets. `--apply` adds them all, both ways. A title
quoted inside backticks does not count, so a note explaining the syntax does
not invent links.

**Ctrl-C stops the request, not the shell.** A second one really does quit.

---

## Tokens and cost

Counted from what each provider actually reports on the wire — Anthropic's
`message_start`/`message_delta` pair, Gemini's `usageMetadata`, the OpenAI
final chunk — never estimated. A model with no public price on file reports its
tokens and leaves the cost blank, because a confidently wrong number about your
money is worse than no number.

---

## The web app

`docs/jarvis.html` in this repo is the same assistant in a browser, with the
same memory graph drawn in the same way. Neither can reach the other's storage
— a browser cannot read your disk unprompted, and this cannot read
localStorage — so the bridge is a file you move across, not a claim of sync:

In Chrome or Edge the app can go one better: **Settings → Data → Vault folder**
points the browser at this same directory through the File System Access API,
and Sync moves whole notes both ways, most-recently-updated winning per note.
Safari and Firefox do not have that API, so there the file is still the bridge:

```sh
jarvis export vault.json          # then Settings → Data → Import in the app
jarvis import jarvis-backup.json  # a backup exported from the app
```

A pre-vault backup, where memory was a flat list of sentences, imports with each
sentence becoming its own note.

---

## Known limits

- **No live provider has ever been called from the environment this was built
  in.** The streaming path is covered end to end against a stub speaking each
  provider's real SSE shapes, which catches format and parsing bugs but cannot
  catch anything about the real endpoints. Treat the first real call as the
  actual test.
- `jarvis graph --open` writes a **snapshot**. Re-run it after editing the vault.
- Relevance is lexical plus one hop through the graph, not embeddings. Those
  need a model call per note and a vector store before you can ask anything;
  at the size a personal vault reaches they would pick the same handful. It
  will not scale to thousands of notes.
- Folder sync moves whole notes and never merges inside a file. Edit the same
  note in two places between syncs and the newer one wins outright. That is a
  job for git, which is why the vault is a git-friendly folder. "Newer" is the
  file's mtime, not the `updated:` line — no editor but this one touches
  frontmatter, so trusting that line made an edit in Obsidian look like it had
  never happened.
- Deletion crosses the sync only from the *second* sync onward. The app records
  what both sides agreed on last time, and without that record a note missing
  from one side is indistinguishable from a note that is new on the other. So
  the first sync between a vault and a folder always merges, and never deletes.
- Two notes can share a title, and each gets its own file (`Noah.md`,
  `Noah (2).md`). Nothing is lost, but a `[[link]]` to that title can only
  resolve to one of them — `jarvis mem add` says so when it happens.
- There is no watch mode and no daemon. Every command is one shot. `jarvis
  vault sync` is something you run, or put on a timer yourself.
- Git sync needs `git` on your PATH. Everything else in Jarvis works without
  it, and says so rather than failing obscurely.
