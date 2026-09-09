#!/usr/bin/env bats
#
# The Stop hook nudges once, and only where a script can tell that a session
# with the log on wrote nothing to it.

bats_require_minimum_version 1.5.0

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/unrecorded.sh"
  DECISIONS="${BATS_TEST_DIRNAME}/../bin/decisions"
  REPO="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/proj"
  TRANSCRIPT="${BATS_TEST_TMPDIR}/transcript.jsonl"
  export HOOK DECISIONS REPO TRANSCRIPT
  export HOME="$BATS_TEST_TMPDIR"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  cd "$REPO" || exit 1
}

# A session with $1 turns of somebody typing, and the tool traffic between.
transcript() {
  : >"$TRANSCRIPT"
  local turn
  for ((turn = 0; turn < $1; turn++)); do
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"do the thing"}}' >>"$TRANSCRIPT"
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use"}]}}' >>"$TRANSCRIPT"
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result"}]}}' >>"$TRANSCRIPT"
  done
}

payload() {
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":%s}' \
    "${1:-s1}" "$TRANSCRIPT" "${2:-false}"
}

@test "quiet where the log was never turned on" {
  transcript 3
  run bash -c "printf '%s' '$(payload)' | \"$HOOK\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "quiet where the log is turned off, files and all" {
  "$DECISIONS" enable
  printf '# a topic\n' >.decisions/1788889263-a-topic.md
  "$DECISIONS" disable
  transcript 3
  run bash -c "printf '%s' '$(payload)' | \"$HOOK\""
  [ "$status" -eq 0 ]
}

@test "quiet after a single turn" {
  "$DECISIONS" enable
  transcript 1
  run bash -c "printf '%s' '$(payload)' | \"$HOOK\""
  [ "$status" -eq 0 ]
}

@test "blocks once when a multi-turn session recorded nothing" {
  "$DECISIONS" enable
  transcript 3
  run --separate-stderr bash -c "printf '%s' '$(payload)' | \"$HOOK\""
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"nothing reached .decisions/"* ]]
  [[ "$stderr" == *"q: / a: / why: / alt:"* ]]
}

@test "the second stop in the same session is quiet" {
  "$DECISIONS" enable
  transcript 3
  run bash -c "printf '%s' '$(payload s9)' | \"$HOOK\""
  [ "$status" -eq 2 ]
  run bash -c "printf '%s' '$(payload s9)' | \"$HOOK\""
  [ "$status" -eq 0 ]
}

@test "quiet when the session wrote a decision file" {
  "$DECISIONS" enable
  transcript 3
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","input":{"file_path":"/w/proj/.decisions/1788889263-a-topic.md"}}]}}' >>"$TRANSCRIPT"
  run bash -c "printf '%s' '$(payload)' | \"$HOOK\""
  [ "$status" -eq 0 ]
}

@test "quiet when the stop it would block is its own" {
  "$DECISIONS" enable
  transcript 3
  run bash -c "printf '%s' '$(payload s2 true)' | \"$HOOK\""
  [ "$status" -eq 0 ]
}

@test "quiet on a payload it cannot read" {
  "$DECISIONS" enable
  transcript 3
  run bash -c "printf '%s' 'not json' | \"$HOOK\""
  [ "$status" -eq 0 ]
  run bash -c "printf '' | \"$HOOK\""
  [ "$status" -eq 0 ]
}
