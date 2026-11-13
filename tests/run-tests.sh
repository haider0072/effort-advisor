#!/bin/sh
# Tests for plugins/effort-advisor/hooks/effort-advisor.sh, run against fixture sessions.
# Usage: sh tests/run-tests.sh   (exit code 0 when every case passes)
# HOOK_SHELL=dash sh tests/run-tests.sh runs the hook under another shell.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
hook=$root/plugins/effort-advisor/hooks/effort-advisor.sh
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ea-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$1"
  else
    fail=$((fail + 1)); printf 'FAIL %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"
  fi
}

# ---- fixture builders --------------------------------------------------------
assistant() { # level [sidechain] [content]
  printf '{"parentUuid":"p","isSidechain":%s,"message":{"role":"assistant","content":%s},"type":"assistant","uuid":"u","timestamp":"2026-11-13T10:00:00.000Z","effort":"%s","perTurnEffort":"%s","userType":"external"}\n' \
    "${2:-false}" "${3:-[{\"type\":\"text\",\"text\":\"done\"}]}" "$1" "$1"
}
effort_cmd() { # level
  printf '{"parentUuid":"p","isSidechain":false,"type":"user","message":{"role":"user","content":"<command-name>/effort</command-name>\\n<command-args>%s</command-args>"},"uuid":"c"}\n' "$1"
  printf '{"parentUuid":"c","isSidechain":false,"type":"system","subtype":"local_command","content":"<local-command-stdout>Set effort level to %s (this session only): text</local-command-stdout>","level":"info","commandRun":{"command":"effort","args":"%s"}}\n' "$1" "$1"
}
effort_auto() {
  printf '{"parentUuid":"c","isSidechain":false,"type":"system","subtype":"local_command","content":"<local-command-stdout>Effort level set to auto</local-command-stdout>","level":"info","commandRun":{"command":"effort","args":"auto"}}\n'
}
user_text() { # text
  printf '{"parentUuid":"p","isSidechain":false,"type":"user","message":{"role":"user","content":"%s"},"uuid":"x"}\n' "$1"
}
app_record() { # file effort-json-fragment cliSessionId
  mkdir -p "$(dirname "$1")"
  printf '{"sessionId":"local_x","cliSessionId":"%s","cwd":"/w","model":"claude-opus-5-5"%s,"permissionMode":"default"}\n' "$3" "$2" >"$1"
}
prompt_input() { # session transcript
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"/w","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"fix the bug, it says \\"effort\\":{\\"level\\":\\"max\\"}"}' "$1" "$2"
}
tool_input() { # session level [extra top-level fields]
  printf '{"session_id":"%s","transcript_path":"/none","cwd":"/w","permission_mode":"default"%s,"effort":{"level":"%s"},"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"x","effort":{"level":"max"}},"tool_response":{"stdout":"ok"}}' \
    "$1" "${3:-}" "$2"
}

# ---- runners -----------------------------------------------------------------
# Every run gets its own state dir, no app store and no parent lookup unless a case sets them.
run_prompt() { # session transcript [entrypoint] [stores] [parent args]
  prompt_input "$1" "$2" | env EFFORT_ADVISOR_STATE_DIR="$tmp/state" CLAUDE_CODE_ENTRYPOINT="${3:-cli}" \
    EFFORT_ADVISOR_APP_STORES="${4:-$tmp/no-store}" EFFORT_ADVISOR_PARENT_ARGS="${5:-}" ${HOOK_SHELL:-sh} "$hook" prompt
}
current() { # first "Current effort" line as level|source
  sed -n 's/^Current effort for this turn: \([a-z]*\) (read from \(.*\))\.$/\1|\2/p' | head -n 1
}
level_of() { current | cut -d'|' -f1; }

# ---- prompt mode: Claude desktop app record -----------------------------------
store=$tmp/store
T=$tmp/t-desktop.jsonl
assistant xhigh >"$T"
app_record "$store/acct1/org1/local_s1.json" ',"effort":"high"' s1
check "desktop record beats the last turn" "high" "$(run_prompt s1 "$T" claude-desktop "$store" | level_of)"
check "desktop source is named" "high|the Claude desktop app's effort setting for this session" "$(run_prompt s1 "$T" claude-desktop "$store" | current)"
check "desktop record ignored outside the desktop app" "xhigh" "$(run_prompt s1 "$T" cli "$store" | level_of)"

app_record "$store/acct1/org1/local_s2.json" ', "effort": "max", "effortInherited": true' s2
check "spaced JSON in the desktop record" "max" "$(run_prompt s2 "$T" claude-desktop "$store" | level_of)"

app_record "$store/acct1/org1/local_original-id.json" ',"effort":"medium"' s3
check "desktop record found by cliSessionId when its name differs" "medium" "$(run_prompt s3 "$T" claude-desktop "$store" | level_of)"

app_record "$store/acct1/org1/local_s4.json" ',"effort":"low"' s4
app_record "$store/acct2/org1/local_s4.json" ',"effort":"max"' s4
touch -t 202601010000 "$store/acct1/org1/local_s4.json"
check "newest desktop copy wins (newer has max)" "max" "$(run_prompt s4 "$T" claude-desktop "$store" | level_of)"
touch -t 202601010000 "$store/acct2/org1/local_s4.json"
touch "$store/acct1/org1/local_s4.json"
check "newest desktop copy wins (newer has low)" "low" "$(run_prompt s4 "$T" claude-desktop "$store" | level_of)"

app_record "$store/acct1/org1/local_s5.json" '' s5
check "desktop record without effort falls back to the transcript" "xhigh" "$(run_prompt s5 "$T" claude-desktop "$store" | level_of)"

app_record "$store/acct1/org1/local_s6.json" ',"effort":"turbo"' s6
check "unknown level in the desktop record is ignored" "xhigh" "$(run_prompt s6 "$T" claude-desktop "$store" | level_of)"

# A record named after this session that now belongs to another one must not be used.
app_record "$store/acct1/org1/local_s7.json" ',"effort":"low"' moved-on
check "record named after the session but owned by another is ignored" "xhigh" "$(run_prompt s7 "$T" claude-desktop "$store" | level_of)"

# A renamed record is found by scanning once, then by its remembered name.
app_record "$store/acct1/org1/local_first-name.json" ',"effort":"medium"' s8
run_prompt s8 "$T" claude-desktop "$store" >/dev/null
check "renamed record's name is remembered" "local_first-name.json" "$(cat "$tmp/state/s8.record" 2>/dev/null)"
app_record "$store/acct1/org1/local_first-name.json" ',"effort":"max"' s8
check "remembered record is read fresh on the next prompt" "max" "$(run_prompt s8 "$T" claude-desktop "$store" | level_of)"

# ---- prompt mode: transcript --------------------------------------------------
T=$tmp/t1.jsonl
{ assistant xhigh; effort_cmd low; } >"$T"
check "/effort after the last reply wins" "low|the /effort command the user just ran" "$(run_prompt t1 "$T" | current)"

T=$tmp/t2.jsonl
{ effort_cmd low; assistant max; } >"$T"
check "a reply after /effort shows the level it ran at" "max|the level your previous reply in this session ran at" "$(run_prompt t2 "$T" | current)"

T=$tmp/t3.jsonl
{ assistant high; effort_auto; } >"$T"
check "/effort auto reports default" "default" "$(run_prompt t3 "$T" | level_of)"

T=$tmp/t4.jsonl
{ assistant xhigh; assistant low true; } >"$T"
check "subagent turns are ignored" "xhigh" "$(run_prompt t4 "$T" | level_of)"

T=$tmp/t5.jsonl
assistant high false '[{"type":"tool_use","name":"Agent","input":{"effort":"low","prompt":"go"}}]' >"$T"
check "an Agent call's effort input is not the session effort" "high" "$(run_prompt t5 "$T" | level_of)"

T=$tmp/t6.jsonl
{ assistant medium; user_text 'why did it say <local-command-stdout>Set effort level to max'; } >"$T"
check "quoted /effort text in a message is ignored" "medium" "$(run_prompt t6 "$T" | level_of)"

T=$tmp/t7.jsonl
{ assistant medium; effort_cmd xhigh; effort_cmd low; } >"$T"
check "the last of several /effort commands wins" "low" "$(run_prompt t7 "$T" | level_of)"

T=$tmp/'dir with spaces\and slash'
mkdir -p "$T"
assistant max >"$T/t.jsonl"
esc=$(printf '%s' "$T/t.jsonl" | sed 's/\\/\\\\/g')
check "escaped transcript path" "max" "$(run_prompt t8 "$esc" | level_of)"

T=$tmp/t9.jsonl
{ assistant low; i=0; while [ $i -lt 3000 ]; do user_text "padding line $i with some text to make the file bigger than a few kilobytes"; i=$((i + 1)); done; } >"$T"
check "last reply found far back in a long transcript" "low" "$(run_prompt t9 "$T" | level_of)"

# ---- prompt mode: fallbacks ---------------------------------------------------
check "--effort=flag of the session process" "medium|the --effort flag this session was started with" \
  "$(run_prompt f1 "$tmp/missing.jsonl" cli "" "/x/claude --model opus --effort=medium -p" | current)"
check "--effort flag with a space" "xhigh" "$(run_prompt f2 "$tmp/missing.jsonl" cli "" "/x/claude --effort xhigh" | level_of)"
check "nothing known says unknown" "unknown" "$(run_prompt f3 "$tmp/missing.jsonl" | level_of)"
check "transcript beats the startup flag" "low" "$(run_prompt t1 "$tmp/t1.jsonl" cli "" "/x/claude --effort max" | level_of)"

out=$(run_prompt f4 "$tmp/t1.jsonl")
case $out in *'{{'*) got=placeholder-left ;; *'(current: low)'*) got=filled ;; *) got=missing ;; esac
check "every placeholder is filled" "filled" "$got"

# A customized instruction without placeholders still gets the live level appended.
custom=$tmp/custom/hooks
mkdir -p "$custom"
cp "$hook" "$custom/"
printf '<effort-advisor>\nMy own wording.\n</effort-advisor>\n' >"$custom/effort-instruction.md"
out=$(prompt_input c1 "$tmp/t1.jsonl" | env EFFORT_ADVISOR_STATE_DIR="$tmp/state" CLAUDE_CODE_ENTRYPOINT=cli EFFORT_ADVISOR_APP_STORES="$tmp/no-store" EFFORT_ADVISOR_PARENT_ARGS= ${HOOK_SHELL:-sh} "$custom/effort-advisor.sh" prompt)
case $out in *'My own wording.'*'Current effort for this turn: low'*) got=appended ;; *) got=$out ;; esac
check "custom instruction keeps its text and gets the level" "appended" "$got"

# ---- tool mode ----------------------------------------------------------------
run_tool() { # session level [extra]
  tool_input "$1" "$2" "${3:-}" | env EFFORT_ADVISOR_STATE_DIR="$tmp/state" CLAUDE_CODE_ENTRYPOINT=cli EFFORT_ADVISOR_APP_STORES="$tmp/no-store" ${HOOK_SHELL:-sh} "$hook" tool
}
state() { cat "$tmp/state/$1" 2>/dev/null; }

run_prompt k1 "$tmp/t2.jsonl" >/dev/null # announces max
check "prompt mode remembers what it announced" "max" "$(state k1)"
check "matching level stays silent" "" "$(run_tool k1 max)"
out=$(run_tool k1 high)
case $out in *'actually running at effort high, not max'*) got=corrected ;; *) got=$out ;; esac
check "a different level sends one correction" "corrected" "$got"
check "the correction updates the state" "high" "$(state k1)"
check "the correction is sent only once" "" "$(run_tool k1 high)"
if command -v python3 >/dev/null 2>&1; then
  ok=$(run_tool k1 low | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["hookSpecificOutput"]["hookEventName"])' 2>&1)
  check "correction output is valid hook JSON" "PostToolUse" "$ok"
fi
check "subagent tool calls are ignored" "" "$(run_tool k1 max ',"agent_id":"a1"')"
check "subagent call leaves the state alone" "low" "$(state k1)"
# A main thread tool whose own input mentions agent_id (TaskStop, SendMessage) is not a subagent.
printf '%s\n' max >"$tmp/state/k5"
out=$(printf '{"session_id":"k5","transcript_path":"/none","cwd":"/w","permission_mode":"default","effort":{"level":"low"},"hook_event_name":"PostToolUse","tool_name":"TaskStop","tool_input":{"agent_id":"worker-1"},"tool_response":{}}' |
  env EFFORT_ADVISOR_STATE_DIR="$tmp/state" CLAUDE_CODE_ENTRYPOINT=cli ${HOOK_SHELL:-sh} "$hook" tool)
case $out in *'actually running at effort low, not max'*) got=corrected ;; *) got=$out ;; esac
check "agent_id inside tool_input does not hide a correction" "corrected" "$got"
# If a future Claude Code moves effort after hook_event_name, it is still read.
printf '%s\n' max >"$tmp/state/k6"
out=$(printf '{"session_id":"k6","transcript_path":"/none","hook_event_name":"PostToolUse","tool_name":"Bash","effort":{"level":"high"},"tool_input":{"command":"x"}}' |
  env EFFORT_ADVISOR_STATE_DIR="$tmp/state" CLAUDE_CODE_ENTRYPOINT=cli ${HOOK_SHELL:-sh} "$hook" tool)
case $out in *'actually running at effort high, not max'*) got=corrected ;; *) got=$out ;; esac
check "effort placed after hook_event_name is still read" "corrected" "$got"
check "first tool call without a prompt record stays silent" "" "$(run_tool k2 medium)"
check "and records the level" "medium" "$(state k2)"
run_prompt k3 "$tmp/missing.jsonl" >/dev/null # announces unknown
out=$(run_tool k3 xhigh)
case $out in *'actually running at effort xhigh, not unknown'*) got=corrected ;; *) got=$out ;; esac
check "an unknown announcement gets corrected" "corrected" "$got"
check "tool_input effort does not count" "" "$(run_tool k3 xhigh)"
check "invalid level is ignored" "" "$(run_tool k3 turbo)"
check "invalid level leaves the state alone" "xhigh" "$(state k3)"

# ---- speed --------------------------------------------------------------------
T=$tmp/big.jsonl
{ assistant high; i=0; while [ $i -lt 40000 ]; do user_text "line $i of a long session with a fair amount of text in every single entry, like real ones"; i=$((i + 1)); done; } >"$T"
start=$(date +%s)
lvl=$(run_prompt big "$T" | level_of)
secs=$(($(date +%s) - start))
check "big transcript still read" "high" "$lvl"
[ "$secs" -le 2 ] && got=fast || got="${secs}s"
check "big transcript under 2 seconds ($(wc -c <"$T" | tr -d ' ') bytes)" "fast" "$got"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
