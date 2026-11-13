#!/bin/sh
# effort-advisor hook. Tells Claude which effort level the current turn really runs at,
# so the advice compares against the live level instead of a guess.
#
#   effort-advisor.sh prompt   UserPromptSubmit: look up the live level, print the instruction with it filled in
#   effort-advisor.sh tool     PostToolUse: Claude Code reports the real level to tool hooks. If it differs
#                              from what the prompt hook announced, add a one time correction for the model.
#
# Claude Code does not include the effort level in UserPromptSubmit input, so the prompt hook reads it from
# the places that change the moment the user changes it:
#   1. Claude desktop app: the session record the app saves when the effort picker (or /effort) changes.
#   2. The session transcript: an /effort command run after the last reply, otherwise the level the last
#      reply ran at (perTurnEffort).
#   3. The --effort flag the session was started with.
# POSIX sh with grep, sed, awk and tail only, so it runs on macOS, Linux and Git Bash on Windows.
#
# Test overrides: EFFORT_ADVISOR_STATE_DIR, EFFORT_ADVISOR_APP_STORES (newline separated roots),
# EFFORT_ADVISOR_PARENT_ARGS (skip the process lookup and use this command line instead).

mode=${1:-prompt}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
input=$(cat)

# First value of a string key in the hook input. Top level keys come before tool_input and
# tool_response, so the first match is the real one.
json_str() {
  printf '%s' "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 |
    sed 's/^[^:]*:[[:space:]]*"//; s/"$//; s/\\\\/\\/g; s/\\\//\//g'
}

valid_level() {
  case $1 in low | medium | high | xhigh | max) return 0 ;; esac
  return 1
}

session_id=$(json_str session_id | tr -cd 'A-Za-z0-9_-')
uid=$(id -u 2>/dev/null || echo user)
state_dir=${EFFORT_ADVISOR_STATE_DIR:-${TMPDIR:-/tmp}/effort-advisor-$uid}
state_file=
[ -n "$session_id" ] && state_file=$state_dir/$session_id

remember() { # remember what the model was told, for the tool hook to check
  [ -n "$state_file" ] || return 0
  mkdir -p "$state_dir" 2>/dev/null && printf '%s\n' "$1" >"$state_file.tmp" 2>/dev/null &&
    mv -f "$state_file.tmp" "$state_file" 2>/dev/null
}

# ---------------------------------------------------------------- tool mode
if [ "$mode" = tool ]; then
  # The common fields (agent_id, effort) come before hook_event_name; tool_input and tool_response come
  # after it and can contain anything. Look only at that head, unless a future version moved effort.
  head_part=$(printf '%s' "$input" | sed 's/"hook_event_name".*//')
  case $head_part in *'"effort"'*) ;; *) head_part=$input ;; esac
  # Subagents run at their own effort, which says nothing about the main conversation.
  printf '%s' "$head_part" | grep -q '"agent_id"[[:space:]]*:[[:space:]]*"[^"]' && exit 0
  level=$(printf '%s' "$head_part" |
    grep -o '"effort"[[:space:]]*:[[:space:]]*{[[:space:]]*"level"[[:space:]]*:[[:space:]]*"[a-z]*"' |
    head -n 1 | sed 's/.*"\([a-z]*\)"$/\1/')
  valid_level "$level" || exit 0
  [ -n "$state_file" ] || exit 0
  told=$(cat "$state_file" 2>/dev/null)
  if [ -z "$told" ]; then
    remember "$level"
    exit 0
  fi
  [ "$told" = "$level" ] && exit 0
  remember "$level"
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"effort-advisor correction: this turn is actually running at effort %s, not %s as stated earlier. Use %s as the current effort from now on, and correct any effort comparison you already made."}}\n' \
    "$level" "$told" "$level"
  exit 0
fi

# ---------------------------------------------------------------- prompt mode
level=
source=

# 1. Claude desktop app session record
app_stores() {
  printf '%s\n' "${EFFORT_ADVISOR_APP_STORES:-"$HOME/Library/Application Support/Claude/claude-code-sessions
${APPDATA:-/nonexistent}/Claude/claude-code-sessions
${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude-code-sessions"}" |
    while IFS= read -r root; do [ -n "$root" ] && [ -d "$root" ] && printf '%s\n' "$root"; done
}
belongs() { # file: is this the record of the current Claude Code session?
  grep -q -F -e "\"cliSessionId\":\"$session_id\"" -e "\"cliSessionId\": \"$session_id\"" "$1" 2>/dev/null
}
newest_of() { # stdin: files that belong to this session; prints the newest (the app keeps one copy per account)
  newest=
  while IFS= read -r f; do
    belongs "$f" || continue
    if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest=$f; fi
  done
  printf '%s' "$newest"
}
named() { # record file name: every copy of it, newest that belongs to this session
  printf '%s\n' "$roots" | while IFS= read -r root; do
    # find, not a glob: an unmatched glob aborts the command in some shells
    find "$root" -mindepth 3 -maxdepth 3 -type f -name "$1" 2>/dev/null
  done | newest_of
}
app_record() {
  roots=$(app_stores)
  [ -n "$roots" ] || return 0
  # Usually the record is named after the session.
  rec=$(named "local_$session_id.json")
  # It keeps its first name when Claude Code moves on to a new session id. Finding it then means reading
  # every record, so remember the name for the next prompts.
  if [ -z "$rec" ] && [ -n "$state_file" ]; then
    known=$(cat "$state_file.record" 2>/dev/null)
    [ -n "$known" ] && rec=$(named "$known")
  fi
  if [ -z "$rec" ]; then
    rec=$(printf '%s\n' "$roots" | while IFS= read -r root; do
      find "$root" -mindepth 3 -maxdepth 3 -type f -name 'local_*.json' -exec grep -l -F "$session_id" {} + 2>/dev/null
    done | newest_of)
    if [ -n "$rec" ] && [ -n "$state_file" ]; then
      mkdir -p "$state_dir" 2>/dev/null && printf '%s\n' "${rec##*/}" >"$state_file.record" 2>/dev/null
    fi
  fi
  printf '%s' "$rec"
}

if [ -n "$session_id" ] && [ "${CLAUDE_CODE_ENTRYPOINT:-}" = claude-desktop ]; then
  rec=$(app_record)
  if [ -n "$rec" ]; then
    v=$(grep -o '"effort"[[:space:]]*:[[:space:]]*"[a-z]*"' "$rec" 2>/dev/null | head -n 1 | sed 's/.*"\([a-z]*\)"$/\1/')
    if valid_level "$v"; then level=$v; source="the Claude desktop app's effort setting for this session"; fi
  fi
fi

# 2. Transcript: /effort run after the last reply, otherwise the level the last reply ran at
if [ -z "$level" ]; then
  tp=$(json_str transcript_path)
  if [ -n "$tp" ] && [ -f "$tp" ]; then
    # The last reply is almost always in the last megabyte. Look further back only when it is not
    # (a big pasted image, a huge tool result), since long JSON lines make every pass slow.
    for window in 1000000 8000000; do
      found=$(tail -c "$window" "$tp" 2>/dev/null | awk '
        index($0, "\"isSidechain\":true") { next }
        match($0, /"perTurnEffort"[ \t]*:[ \t]*"[a-z]+"/) {
          s = substr($0, RSTART, RLENGTH); sub(/.*:[ \t]*"/, "", s); sub(/"$/, "", s)
          turn = s; cmd = ""; next
        }
        index($0, "\"local_command\"") && match($0, /local-command-stdout>Set effort level to [a-z]+/) {
          s = substr($0, RSTART, RLENGTH); sub(/.* to /, "", s); cmd = s; next
        }
        index($0, "\"local_command\"") && index($0, "local-command-stdout>Effort level set to auto") { cmd = "auto"; next }
        END { print cmd "|" turn }')
      [ "$found" != "|" ] && break
      [ "$(wc -c <"$tp" 2>/dev/null)" -gt "$window" ] 2>/dev/null || break
    done
    cmd=${found%%|*}
    turn=${found#*|}
    if [ "$cmd" = auto ]; then
      level=default; source="the /effort auto command the user just ran (the model's default level applies)"
    elif valid_level "$cmd"; then
      level=$cmd; source="the /effort command the user just ran"
    elif valid_level "$turn"; then
      level=$turn; source="the level your previous reply in this session ran at"
    fi
  fi
fi

# 3. --effort flag of the Claude Code process that runs this hook
if [ -z "$level" ]; then
  if [ -n "${EFFORT_ADVISOR_PARENT_ARGS+set}" ]; then
    args=$EFFORT_ADVISOR_PARENT_ARGS
  else
    args= pid=$PPID n=0
    while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ $n -lt 4 ]; do
      a=$(ps -o args= -p "$pid" 2>/dev/null)
      case $a in *--effort*) args=$a; break ;; esac
      pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
      n=$((n + 1))
    done
  fi
  v=$(printf '%s' "$args" | grep -o -- '--effort[= ][a-z]*' | head -n 1 | sed 's/^--effort[= ]//')
  if valid_level "$v"; then level=$v; source="the --effort flag this session was started with"; fi
fi

if [ -z "$level" ]; then
  level=unknown
  source="nowhere: Claude Code did not expose it for this prompt"
fi
remember "$level"

template=$here/effort-instruction.md
if grep -q '{{CURRENT_EFFORT}}' "$template" 2>/dev/null; then
  sed -e "s#{{CURRENT_EFFORT}}#$level#g" -e "s#{{EFFORT_SOURCE}}#$source#g" "$template"
else
  # A customized instruction without placeholders: keep it and add the live level after it.
  cat "$template" 2>/dev/null
  printf '<effort-advisor-current>\nCurrent effort for this turn: %s (read from %s). It is looked up fresh on every prompt, so it already includes any change the user just made. Trust it over anything earlier in the conversation, and never claim the current level is higher or lower than this.\n</effort-advisor-current>\n' "$level" "$source"
fi
