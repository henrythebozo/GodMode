# Agent World — design

Approved 2026-11-09. Kept outside `docs/` because `docs/` is the published site.

## What it is

A new Henry OS page, `docs/world.html`: a 3D town where six Claude agents work
one shared mission. The person types a goal, watches each agent think and work
in its own building, and gets one finished deliverable.

## Decisions

| Decision            | Choice                                                         | Why                                                                          |
| ------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| What agents work on | One shared mission per run                                     | Chosen by the owner. Produces something usable                               |
| Agents              | Real Claude API calls on the person's own key                  | Scripted thoughts would be a screensaver                                     |
| Key                 | Anthropic key only, the one Henry OS already saves             | Reasoning summaries and web search come from Anthropic's API directly        |
| Key entry           | Stays in Henry OS settings (`index.html#keys`)                 | One place owns keys and account sync                                         |
| Home                | Separate page, linked from the Henry OS sidebar                | `index.html` is already 2,500 lines; the 3D library should not load for chat |
| Libraries           | three.js and the Anthropic SDK, committed under `docs/vendor/` | The page holds API keys, so it runs no code fetched from a CDN               |
| Default model       | `claude-opus-5-5`, with Sonnet 5.5 and Haiku 5.5 selectable    | Cost is the person's call                                                    |

## The team

| Agent      | Building    | Job                                                       | Output       |
| ---------- | ----------- | --------------------------------------------------------- | ------------ |
| Planner    | Town Hall   | Picks which specialists the mission needs and briefs them | JSON plan    |
| Researcher | Library     | Facts that must be current or sourced; has web search     | Markdown     |
| Analyst    | Observatory | Options, numbers, trade-offs, risks                       | Markdown     |
| Engineer   | Workshop    | Technical parts: code, architecture, procedures           | Markdown     |
| Writer     | Print Shop  | Assembles the deliverable for the person                  | Markdown     |
| Critic     | Watchtower  | Reviews the draft against the mission                     | JSON verdict |

## Mission flow

1. **Plan.** Planner returns `{ brief, deliverable, assignments[] }`. Only the
   specialists it names run; the rest sit the mission out. If the plan cannot
   be read, every specialist gets the mission as its task.
2. **Work.** Assigned specialists run in parallel. One failing does not stop
   the mission; all failing does.
3. **Write.** Writer composes the deliverable from the mission, the plan and
   the specialists' work.
4. **Review.** Critic returns `{ approved, summary, issues[] }`. If not
   approved, the Writer revises once. A failed review or revision keeps the
   existing draft and says so.
5. **Done.** The result opens with copy and download, plus token counts and an
   estimated cost.

Every agent call is a single user turn, so no thinking blocks are replayed
between agents. The only multi-turn case is resuming a paused web-search turn.

## What the person sees

- Buildings light up in their agent's colour while it works; couriers carry
  work along the paths between buildings.
- A label over each building: name, state, and the latest line of reasoning.
- Tapping a building opens that agent's panel: Thoughts, Work, Brief.
- Progress is shown as states and steps, not a percentage. A model call has no
  honest percentage.
- "Thoughts" are Claude's summarized reasoning (`thinking.display:
"summarized"`). The API does not return raw chain-of-thought.

## Request shape

`client.beta.messages.stream` with `thinking: { type: "adaptive", display:
"summarized" }`, an explicit `output_config.effort`, and JSON agents using
`output_config.format`. Opus 5.5 and Sonnet 5.5 send `fallbacks: "default"`
(beta `server-side-fallback-2026-07-01`) so a classifier decline is retried
server-side; Haiku 5.5 has no server-side fallback and does not send it.
`stop_reason` is checked before content is read.

## Code layout

| File                                      | Responsibility                                       |
| ----------------------------------------- | ---------------------------------------------------- |
| `docs/world.html`, `docs/world/world.css` | Page shell and styles                                |
| `docs/world/roster.js`                    | The six agents: identity, building, colour, position |
| `docs/world/prompts.js`                   | System prompts and message builders                  |
| `docs/world/plan.js`                      | Plan and review schemas, parsing, fallbacks          |
| `docs/world/models.js`                    | Model list, prices, cost estimate                    |
| `docs/world/agent-run.js`                 | One agent call: streaming, paused turns, refusals    |
| `docs/world/mission.js`                   | The flow above. No DOM, no three.js                  |
| `docs/world/markdown.js`                  | Small escaping markdown renderer                     |
| `docs/world/store.js`                     | localStorage access                                  |
| `docs/world/scene.js`, `buildings.js`     | The 3D town                                          |
| `docs/world/ui.js`, `main.js`             | HUD and wiring                                       |

`mission.js` and `agent-run.js` take the API client as an argument, so tests
drive them with a fake client.

## Testing

- Unit tests with `node --test` (`npm run test:world`) for plan parsing, cost,
  markdown escaping, the agent runner and the mission flow.
- A Playwright smoke run (`npm run smoke:world`) that serves `docs/`, answers
  `api.anthropic.com` with a canned stream, runs a mission and screenshots it.
- Not covered: the live API. No key was available while building, so the first
  mission on a real key is the first live test.

## Left out on purpose

- OpenRouter keys, saved mission history in the account, more than one review
  round, editing the roster in the page.
