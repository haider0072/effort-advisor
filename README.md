# effort-advisor

> A Claude Code plugin that makes Claude **assess task complexity and recommend the right effort level before every substantive task** — so you never run a hard problem at low effort and get a weak result.

Claude Opus 4.8 ships an **effort dial** (`low → medium → high → xhigh → max`) that controls how deeply the model reasons before acting. More effort = more accurate but slower and pricier; less effort = fast and cheap but shallow. The catch: it's manual, and it's easy to leave a hard task running at the wrong level.

`effort-advisor` fixes that. Before any non-trivial task, Claude tells you how complex it thinks the task is and which effort level to use — then waits for you to decide.

---

## What it looks like

Ask Claude to do something non-trivial, and before it starts you'll see:

```
Complexity: High — multi-layer root cause, touches production data, 4+ files
Recommended effort: xhigh (current: high)   →   run /effort xhigh
```

Then it waits. You stay in control. Trivial work (one-liners, quick lookups, tiny edits) is skipped so it never becomes noise.

It is **accuracy-biased by design**: when complexity is unclear, it rounds *up*. Under-rating is worse than over-rating — extra tokens cost far less than a wrong result on a hard task.

---

## How it works

A `UserPromptSubmit` hook injects a short instruction into context on every prompt. No model-invocation guesswork, no settings to flip, nothing to remember: install it and it's always on. The full instruction lives in [`plugins/effort-advisor/hooks/effort-instruction.md`](plugins/effort-advisor/hooks/effort-instruction.md) and is easy to customize.

### How it knows your current effort

The advice is only useful if it compares against the level you are really on. Claude Code does not pass the effort level to `UserPromptSubmit` hooks, so [`hooks/effort-advisor.sh`](plugins/effort-advisor/hooks/effort-advisor.sh) looks it up on every prompt, from the places that change the moment you change it:

1. **Claude desktop app:** the session record the app saves as soon as you use the effort picker or type `/effort`.
2. **Session transcript:** an `/effort` command you ran since the last reply, otherwise the level the last reply actually ran at.
3. **Startup flag:** the `--effort` flag the session was started with.

The level and where it came from are filled into the instruction, so Claude shows `(current: <level>)` and only suggests a switch when the recommendation really differs. Change the effort and the very next prompt sees it. If nothing is known it says `unknown`, and Claude is told not to guess.

A second hook, on `PostToolUse`, double checks. Claude Code does give tool hooks the exact level of the running turn. If it differs from what was announced (say you changed effort in a way none of the sources above saw), Claude gets a one time correction in the same turn. It stays silent when the levels match, and ignores subagents, which run at their own effort.

Both hooks are a plain POSIX `sh` script (grep, sed, awk, tail), so they work on macOS, Linux and Git Bash on Windows with nothing to install. A prompt costs about 0.1 s, even on a transcript of a few hundred megabytes.

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
│       │   ├── hooks.json            # UserPromptSubmit + PostToolUse hook wiring
│       │   ├── effort-advisor.sh     # finds the live effort level, fills in the instruction
│       │   └── effort-instruction.md # the instruction injected each prompt
│       └── README.md                 # plugin-level docs
├── tests/
│   └── run-tests.sh                  # hook tests against fixture sessions
├── README.md                         # you are here
└── LICENSE
```

---

## Tests

```bash
sh tests/run-tests.sh
```

Runs the hook against fixture transcripts and desktop app records: every source, the order between them, subagents, quoted text that only looks like an `/effort` command, renamed records, the one time correction, and the speed on a large transcript. `HOOK_SHELL=dash sh tests/run-tests.sh` runs the hook under another shell. CI runs it on Ubuntu and macOS.

---

## License

[MIT](LICENSE) © Haider Ali Khan
