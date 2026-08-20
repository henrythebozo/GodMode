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
jarvis init
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

### Keys

Read from the environment first, the config file second. Whichever you prefer:

```sh
export ANTHROPIC_API_KEY=sk-ant-...      # or OPENAI_API_KEY, OPENROUTER_API_KEY, GEMINI_API_KEY
```

A key that only ever came from the environment is never written back to disk —
saving it would quietly turn a per-shell secret into a stored one.

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

---

## Commands

| | |
|---|---|
| `jarvis "question"` | ask; `ask` is optional |
| `jarvis ask "…" --model ID --no-memory` | pick a model, or send no notes |
| `jarvis mem add "…" -f Folder -t Title -l Other` | write a note, optionally linked |
| `jarvis mem list [query]` | newest first |
| `jarvis mem show <title>` | the note, its links out, and its links in |
| `jarvis mem link <a> <b>` | link both ways |
| `jarvis mem rm <title>` / `mem open <title>` | delete, or open in `$EDITOR` |
| `jarvis graph` | counts, the most-connected notes, the unlinked ones |
| `jarvis graph <title> --depth N` | one note's neighbourhood, as a tree |
| `jarvis graph --open` | render the whole vault and open it in a browser |
| `jarvis chain add <name> <step>…` | a step is `note: Title` or `prompt: text` |
| `jarvis chain list` / `chain run <name>` | |
| `jarvis usage` | tokens and cost, measured not estimated |
| `jarvis config [key [value]]` | show or set; keys print redacted |
| `jarvis export [file]` / `jarvis import <file>` | the bridge to the web app |

Asking a question hands the model an index of every note plus the handful whose
words overlap your question. It can write and link notes back through the same
`jarvis-action` protocol the web app uses.

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
- Relevance for context is word overlap, not embeddings. It picks the right
  handful for a few hundred notes; it will not scale to thousands.
- There is no watch mode and no daemon. Every command is one shot.
