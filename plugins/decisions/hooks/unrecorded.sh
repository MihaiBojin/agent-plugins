#!/usr/bin/env bash
#
# Stop hook: one nudge, at the end of a session that settled something and
# wrote none of it down.
#
# What counts as worth recording is a judgement, and this script does not make
# it. It checks the three things a script can know - the log is on here, the
# session ran longer than a single turn, and nothing reached .decisions/ - and
# hands the judgement back to the model, once per session and never twice.
#
# Every unexpected input leaves the session alone.

set -uo pipefail

LOG_DIR=".decisions"

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# Blocking a stop this hook already blocked is a loop.
case "$payload" in
  *'"stop_hook_active"'*'true'*) exit 0 ;;
esac

field() {
  printf '%s' "$payload" |
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
    head -1
}

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$root" ] || exit 0
dir="${root}/${LOG_DIR}"
[ -d "$dir" ] || exit 0
[ -e "${dir}/.disabled" ] && exit 0

transcript="$(field transcript_path)"
[ -f "$transcript" ] || exit 0

# A decision that stayed open needs more than one turn to have stayed open in.
# Tool results are user entries too, and are not turns.
turns="$(grep '"type":"user"' "$transcript" 2>/dev/null | grep -vc 'tool_result' || true)"
[ "${turns:-0}" -gt 1 ] || exit 0

# Something already went into the log, by whichever tool put it there.
if grep -qE "\"file_path\": ?\"[^\"]*/${LOG_DIR}/|${LOG_DIR}/[0-9]{9,}-" \
  "$transcript" 2>/dev/null; then
  exit 0
fi

session="$(field session_id)"
marker="${TMPDIR:-/tmp}/decisions-stop-${session:-unknown}"
[ -e "$marker" ] && exit 0
: >"$marker" 2>/dev/null || true

cat >&2 <<MSG
decisions: the log is on in this repository and nothing reached ${LOG_DIR}/ this session.

If a choice made here stayed open across turns and changes what somebody would
do later, record it now: one file per topic, ${LOG_DIR}/<unix-timestamp>-<slug>.md,
with q: / a: / why: / alt: lines. A choice that was quick and easy, or that
changes nothing outside this session, is not one of them: say so in one line
and stop.
MSG
exit 2
