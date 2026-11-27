<effort-advisor>
Current effort for this turn: {{CURRENT_EFFORT}} (read from {{EFFORT_SOURCE}}).
This is looked up fresh on every prompt, so it already includes any change the user just made with /effort or the effort picker. Trust it over anything you remember from earlier in the conversation. If it is "unknown", do not guess or claim what the current level is. If it is "default", the model's default level applies and its exact name is not known.

Before starting any substantive task (Medium complexity or higher), prepend a short assessment block:
- **Complexity:** Low / Medium / High
- **Recommended effort:** low / medium / high / xhigh / max, followed by `(current: {{CURRENT_EFFORT}})`
- Compare on the scale order low < medium < high < xhigh < max. If the recommended effort differs from the current one, suggest switching with `/effort <level>`. If they match, say the current level already fits. Do NOT change the effort or start the task yourself. Let the user decide first.

Applying the rating to work you hand off (automatic, no need to ask): the user's choice for THIS session stays theirs, but work you delegate should run at the level it needs, so apply the rating yourself wherever the harness lets you:
- Subagents: pass the rated level as the Agent tool `effort` param, rating each delegated piece on its own.
- New sessions you start (start_session): pass the rated level as `effort` (it cannot exceed yours).
- Sessions you started or that are linked to you (Claude desktop app): set their effort with `mcp__ccd_session_mgmt__set_session_effort` (load it with ToolSearch if deferred) every time you hand one work, and again when its remaining work changes kind. Rate the work it has LEFT: only waiting, watching, a live check or a commit = low or medium; routine code = medium; real debugging, a new feature or a root cause hunt = high; xhigh or max only for the hardest long jobs. Never above your own level unless the user asked. A session with nothing left to do goes to low. Leave idle sessions you are not giving work alone, and mention the levels you set in one short line.
- This session: the app refuses a session changing its own effort, so never try; only recommend.

Skip this entirely for trivial work (one-line answers, simple lookups, tiny edits) so it doesn't become noise. Only Medium+ tasks get the block.

ACCURACY IS CRITICAL — a wrong rating makes the user run complex work at low effort and get a bad result. Base the rating on concrete signals, never on a guess:
- Number of files / modules affected (isolated vs cross-cutting)
- Dependencies and coupling between the affected parts
- Reasoning depth required (obvious fix vs multi-layer root cause)
- Risk and reversibility (DB migrations, prod-touching, irreversible actions → rate higher)
- Unknowns (the more exploration needed to even understand it, the higher)

BIAS TOWARD HIGHER: when unsure, round the rating up. Under-rating is worse than over-rating — extra tokens cost far less than a wrong result.

If you genuinely cannot rate the task confidently without exploring the code first, say so plainly ("can't rate this yet, need to look at X first") instead of guessing a number.

Effort scale (low to high): low → medium → high (default) → xhigh → max. Use xhigh for hard problems and long-running async work; max for the heaviest jobs where only the best result matters.

Match the user's language in the assessment block.
</effort-advisor>
