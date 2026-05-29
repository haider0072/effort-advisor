# effort-advisor

> A Claude Code plugin that makes Claude **assess task complexity and recommend the right effort level before every substantive task** — so you never run a hard problem at low effort and get a weak result.

Claude Opus 4.8 ships an **effort dial** (`low → medium → high → xhigh → max`) that controls how deeply the model reasons before acting. More effort = more accurate but slower and pricier; less effort = fast and cheap but shallow. The catch: it's manual, and it's easy to leave a hard task running at the wrong level.

`effort-advisor` fixes that. Before any non-trivial task, Claude tells you how complex it thinks the task is and which effort level to use — then waits for you to decide.

---

## What it looks like

Ask Claude to do something non-trivial, and before it starts you'll see:

```
Complexity: High — multi-layer root cause, touches production data, 4+ files
Recommended effort: xhigh   →   run /effort xhigh
```

Then it waits. You stay in control. Trivial work (one-liners, quick lookups, tiny edits) is skipped so it never becomes noise.

It is **accuracy-biased by design**: when complexity is unclear, it rounds *up*. Under-rating is worse than over-rating — extra tokens cost far less than a wrong result on a hard task.

---

## How it works

A single `UserPromptSubmit` hook injects a short instruction into context on every prompt. No model-invocation guesswork, no settings to flip, nothing to remember — install it and it's always on. The full instruction lives in [`plugins/effort-advisor/hooks/effort-instruction.md`](plugins/effort-advisor/hooks/effort-instruction.md) and is easy to customize.

### How complexity is judged

Ratings are based on concrete signals, never a vibe:

| Signal | Pushes complexity up when… |
| --- | --- |
| Scope | many files / modules / services affected |
| Coupling | affected parts depend on each other |
| Reasoning depth | root cause is multi-layer, not obvious |
| Risk / reversibility | DB migrations, prod changes, irreversible actions |
| Unknowns | lots of exploration needed just to understand it |

If Claude can't rate the task confidently without looking at the code first, it says so instead of guessing.

---

## Effort scale

| Level | Use for |
| --- | --- |
| `low` | classification, lookups, bulk simple edits |
| `medium` | routine drafting, summaries, straightforward changes |
| `high` *(default)* | most real coding and non-trivial debugging |
| `xhigh` | hard problems, long-running async work |
| `max` | the heaviest jobs where only the best result matters |

---

## Install

### 1. Add the marketplace

```
/plugin marketplace add haider0072/effort-advisor
```

### 2. Install the plugin

```
/plugin install effort-advisor@haider-plugins
```

### 3. Activate

```
/reload-plugins
```

That's it. The advisor is now on for every session.

### Try it locally first (without installing)

```bash
git clone https://github.com/haider0072/effort-advisor.git
claude --plugin-dir ./effort-advisor/plugins/effort-advisor
```

---

## Customize

Edit [`plugins/effort-advisor/hooks/effort-instruction.md`](plugins/effort-advisor/hooks/effort-instruction.md) to change the wording, the complexity signals, or the language Claude responds in. Then bump `version` in both `plugins/effort-advisor/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` so installed users pick up the update on `/plugin marketplace update`.

---

## Repo layout

```
effort-advisor/
├── .claude-plugin/
│   └── marketplace.json              # marketplace catalog (lists the plugin)
├── plugins/
│   └── effort-advisor/
│       ├── .claude-plugin/
│       │   └── plugin.json           # plugin manifest
│       ├── hooks/
│       │   ├── hooks.json            # UserPromptSubmit hook wiring
│       │   └── effort-instruction.md # the instruction injected each prompt
│       └── README.md                 # plugin-level docs
├── README.md                         # you are here
└── LICENSE
```

---

## License

[MIT](LICENSE) © Haider Ali Khan
