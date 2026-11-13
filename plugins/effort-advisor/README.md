# effort-advisor

A tiny Claude Code plugin that makes Claude **assess task complexity and recommend the right effort level before every substantive task** — so you never run a hard problem at low effort and get a weak result.

## What it does

Before any Medium-or-higher task, Claude prepends a short block:

```
Complexity: High (multi-layer root cause, touches prod data)
Recommended effort: xhigh (current: high)  →  /effort xhigh
```

Then it waits for you to decide. Trivial stuff (one-liners, quick lookups, tiny edits) is skipped so it never becomes noise.

It's **accuracy-biased**: when the complexity is unclear, it rounds *up*. Under-rating is worse than over-rating — extra tokens cost far less than a wrong result.

## How it works

A `UserPromptSubmit` hook injects a short instruction into context on every prompt. No model-invocation guesswork, no settings to flip — install it and it's always on.

The instruction carries your live effort level. `hooks/effort-advisor.sh` reads it on every prompt from the Claude desktop app's session record, the session transcript (an `/effort` you just ran, or the level the last reply ran at) or the `--effort` flag, so a change you make shows up on the very next prompt. A `PostToolUse` hook checks it against the exact level Claude Code reports to tool hooks and sends a one time correction if they differ.

## Effort scale

`low → medium → high (default) → xhigh → max`

- **low** — classification, lookups, bulk simple edits
- **medium** — routine drafting, summaries, straightforward changes
- **high** — most real coding and non-trivial debugging (default)
- **xhigh** — hard problems, long-running async work
- **max** — the heaviest jobs where only the best result matters

## Install

### Test locally first

```bash
claude --plugin-dir /path/to/effort-advisor
```

### Share with others (via a marketplace repo)

1. Push this folder to a git repo.
2. Add it as a marketplace:
   ```
   /plugin marketplace add <your-org>/<your-repo>
   ```
3. Install:
   ```
   /plugin install effort-advisor
   ```

After installing, run `/reload-plugins` to activate without restarting.

## Customize

Edit `hooks/effort-instruction.md` to change the wording, the complexity signals, or the language. Keep `{{CURRENT_EFFORT}}` and `{{EFFORT_SOURCE}}` where you want the live level; if you drop them, the level is added after your text instead. Bump `version` in `.claude-plugin/plugin.json` so installed users pick up the update.

## License

MIT
