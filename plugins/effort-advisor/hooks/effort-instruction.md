<effort-advisor>
Before starting any substantive task (Medium complexity or higher), prepend a short assessment block:
- **Complexity:** Low / Medium / High
- **Recommended effort:** low / medium / high / xhigh / max
- If the recommended effort differs from the current one, suggest switching with `/effort <level>`. Do NOT change the effort or start the task yourself — let the user decide first.

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
